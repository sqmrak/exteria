#include "exteria_mt_client.h"

#include <stdlib.h>
#include <string.h>

#include "exteria_random.h"
#include "exteria_tl_ids.h"

#define CONTAINER_ID 0x73f1f8dcu
#define BATCH_MAX (96u * 1024u)
#define MAX_PENDING_DEFAULT 512u
#define RESULT_ARENA_DEFAULT (16u * 1024u * 1024u)
#define PONG_TIMEOUT_DEFAULT 20000u
/* the server drops a link that has not pinged within disconnect_delay seconds, so it is the interval plus this many seconds of slack (75 s at the
   default 30 s interval) */
#define PING_DISCONNECT_SLACK 45u
#define PING_INTERVAL_MIN 10000u
#define PING_INTERVAL_MAX 300000u
#define MAX_ACKS_PER_MESSAGE 128u
#define MAX_CONTAINER_MESSAGES 1024u
#define MAX_BATCH_ITEMS 64u
#define TIME_SYNC_SLACK_MS 30000

struct exteria_mt_pending {
    uint64_t request_id;
    uint64_t msg_id;
    int32_t seq_no;
    uint8_t *raw;
    size_t raw_len;
    uint8_t *final_body;
    size_t final_len;
    uint16_t result_ref;
    uint8_t queued;
    uint8_t acked;
    uint8_t wrapped;
    uint8_t need_new_id;
    uint8_t solo;
    uint8_t sends;
    uint64_t deadline_ms;
};

typedef struct batch_item {
    uint64_t msg_id;
    int32_t seq_no;
    const uint8_t *body;
    size_t len;
} batch_item;

static uint64_t mono_ms(const exteria_mt_client *c) {
    return c->config.clock->monotonic_ms(c->config.clock->ctx);
}

static uint64_t real_ms(const exteria_mt_client *c) {
    return c->config.clock->realtime_ms(c->config.clock->ctx);
}

static uint64_t server_ms(const exteria_mt_client *c) {
    return (uint64_t)((int64_t)real_ms(c) + c->time_offset_ms);
}

static uint64_t next_id(exteria_mt_client *c) {
    return exteria_mt_next_msg_id(server_ms(c), &c->last_msg_id);
}

static int32_t next_seq(exteria_mt_client *c, int content_related) {
    int32_t seq = (int32_t)(c->seq_count * 2u + (content_related ? 1u : 0u));
    if (content_related) c->seq_count++;
    return seq;
}

static void set_state(exteria_mt_client *c, exteria_mt_client_state st, exteria_status reason) {
    c->state = st;
    if (c->events.state) c->events.state(c->events.ctx, st, reason);
}

static void notify_session(exteria_mt_client *c) {
    exteria_mt_session_state st;
    if (!c->events.session_changed || !c->has_key) return;
    memcpy(st.auth_key, c->key.key, sizeof(st.auth_key));
    st.server_salt = c->salt;
    st.time_offset_ms = c->time_offset_ms;
    c->events.session_changed(c->events.ctx, &st);
    exteria_wipe(&st, sizeof(st));
}

static void free_pending_bodies(exteria_mt_pending *p) {
    if (p->final_body) exteria_wipe(p->final_body, p->final_len);
    free(p->final_body);
    p->final_body = NULL;
    p->final_len = 0;
    p->wrapped = 0;
}

static void free_pending(exteria_mt_pending *p) {
    free_pending_bodies(p);
    if (p->raw) exteria_wipe(p->raw, p->raw_len);
    free(p->raw);
    p->raw = NULL;
}

static exteria_mt_pending *find_by_msg(exteria_mt_client *c, uint64_t msg_id) {
    uint32_t i;
    if (msg_id == 0) return NULL;
    for (i = 0; i < c->pending_count; ++i) {
        if (c->pending[i].msg_id == msg_id) return &c->pending[i];
    }
    return NULL;
}

/* whether id names a message that is still waiting for its answer, or a container this client sent; the server's
   complaint about the clock names the container when the requests went out in one, and that complaint is the only
   way a wrong clock gets fixed */
static int is_outgoing(const exteria_mt_client *c, uint64_t id) {
    uint32_t i;
    if (id == 0) return 0;
    for (i = 0; i < c->pending_count; ++i) {
        if (c->pending[i].msg_id == id) return 1;
    }
    for (i = 0; i < EXTERIA_MT_CONTAINER_RING; ++i) {
        if (c->containers[i].id == id) return 1;
    }
    return 0;
}

static int find_index_by_request(const exteria_mt_client *c, uint64_t request_id) {
    uint32_t i;
    for (i = 0; i < c->pending_count; ++i) {
        if (c->pending[i].request_id == request_id) return (int)i;
    }
    return -1;
}

/* the entry leaves the table before the callback runs, so the callback may submit or cancel freely */
static void finish(exteria_mt_client *c, uint32_t index, exteria_status status, const exteria_tl_value *value,
                   int32_t code, const char *text) {
    exteria_mt_pending p = c->pending[index];
    exteria_mt_rpc_result r;
    memmove(&c->pending[index], &c->pending[index + 1], sizeof(c->pending[0]) * (c->pending_count - index - 1));
    c->pending_count--;
    r.status = status;
    r.value = value;
    r.error_code = code;
    r.error_text = text;
    r.msg_id = p.msg_id;
    if (c->events.rpc_result) c->events.rpc_result(c->events.ctx, p.request_id, &r);
    free_pending(&p);
}

static exteria_status flush(exteria_mt_client *c);
static exteria_status die(exteria_mt_client *c, exteria_status reason);

static exteria_status send_bytes(exteria_mt_client *c, const uint8_t *data, size_t len) {
    if (c->closing) return EXTERIA_E_STATE;
    if (c->events.send_checked) return c->events.send_checked(c->events.ctx, data, len);
    if (!c->events.send) return EXTERIA_E_STATE;
    c->events.send(c->events.ctx, data, len);
    return c->closing ? EXTERIA_E_STATE : EXTERIA_OK;
}

static int seen_before(exteria_mt_client *c, uint64_t msg_id) {
    uint32_t i;
    uint64_t lowest = UINT64_MAX;
    for (i = 0; i < c->seen_pos; ++i) {
        if (c->seen[i] == msg_id) return 1;
        if (c->seen[i] < lowest) lowest = c->seen[i];
    }
    /* once the window is full, older ids cannot become new messages again */
    return c->seen_pos == EXTERIA_MT_SEEN_MAX && msg_id < lowest;
}

static void remember(exteria_mt_client *c, uint64_t msg_id) {
    uint32_t i, lowest = 0;
    if (c->seen_pos < EXTERIA_MT_SEEN_MAX) {
        c->seen[c->seen_pos++] = msg_id;
        return;
    }
    for (i = 1; i < EXTERIA_MT_SEEN_MAX; ++i) {
        if (c->seen[i] < c->seen[lowest]) lowest = i;
    }
    c->seen[lowest] = msg_id;
}

static exteria_status queue_ack(exteria_mt_client *c, uint64_t msg_id) {
    uint32_t i;
    for (i = 0; i < c->ack_count; ++i) {
        if (c->acks[i] == msg_id) return EXTERIA_OK;
    }
    /* a full queue must be sent before another content message can be accepted */
    if (c->ack_count == EXTERIA_MT_ACK_MAX) {
        exteria_status s = flush(c);
        if (s != EXTERIA_OK) return s;
    }
    c->acks[c->ack_count++] = msg_id;
    return EXTERIA_OK;
}

/* service messages are encoded through the generic codec so they cannot drift from the schema */
static exteria_status encode_service(exteria_tl_value *v, exteria_writer *w) {
    return exteria_tl_encode(v, w, NULL);
}

static exteria_status build_ack(exteria_mt_client *c, uint32_t take, exteria_writer *w) {
    exteria_arena a;
    exteria_tl_value *v;
    int64_t ids[MAX_ACKS_PER_MESSAGE];
    uint32_t i;
    exteria_status s;
    exteria_arena_init(&a, 16384);
    v = exteria_tl_new_obj(&a, "msgs_ack");
    for (i = 0; i < take; ++i) ids[i] = (int64_t)c->acks[i];
    s = v ? exteria_tl_set_i64_vec(&a, v, "msg_ids", ids, take) : EXTERIA_E_NOMEM;
    if (s == EXTERIA_OK) s = encode_service(v, w);
    exteria_arena_free(&a);
    return s;
}

static exteria_status build_ping(uint64_t ping_id, uint32_t disconnect_delay, exteria_writer *w) {
    exteria_arena a;
    exteria_tl_value *v;
    exteria_status s;
    exteria_arena_init(&a, 4096);
    v = exteria_tl_new_obj(&a, "ping_delay_disconnect");
    s = v ? exteria_tl_set_i64(&a, v, "ping_id", (int64_t)ping_id) : EXTERIA_E_NOMEM;
    if (s == EXTERIA_OK) s = exteria_tl_set_i32(&a, v, "disconnect_delay", (int32_t)disconnect_delay);
    if (s == EXTERIA_OK) s = encode_service(v, w);
    exteria_arena_free(&a);
    return s;
}

static exteria_status emit_packet(exteria_mt_client *c, uint64_t msg_id, int32_t seq_no, const uint8_t *body, size_t len) {
    exteria_writer enc, framed;
    exteria_mt_header h;
    exteria_status s;
    h.salt = c->salt;
    h.session_id = c->session_id;
    h.msg_id = msg_id;
    h.seq_no = seq_no;
    exteria_writer_init(&enc, len + 2048);
    s = exteria_mt_encrypt(&c->key, 1, &h, body, len, &enc);
    if (s != EXTERIA_OK) {
        exteria_writer_free(&enc);
        return s;
    }
    exteria_writer_init(&framed, enc.len + 64);
    s = exteria_mt_transport_wrap(&c->transport, enc.data, enc.len, 0, &framed);
    if (s == EXTERIA_OK) s = send_bytes(c, framed.data, framed.len);
    exteria_writer_free(&enc);
    exteria_writer_free(&framed);
    return s;
}

/* telegram needs connection metadata before the first api query succeeds */
static exteria_status finalize_body(exteria_mt_client *c, exteria_mt_pending *p, const uint8_t **body, size_t *len) {
    if (c->config.api_id == 0 || c->init_confirmed || !c->init_prefix) {
        free_pending_bodies(p);
        *body = p->raw;
        *len = p->raw_len;
        return EXTERIA_OK;
    }
    if (!p->final_body) {
        p->final_len = c->init_prefix_len + p->raw_len;
        p->final_body = (uint8_t *)malloc(p->final_len);
        if (!p->final_body) return EXTERIA_E_NOMEM;
        memcpy(p->final_body, c->init_prefix, c->init_prefix_len);
        memcpy(p->final_body + c->init_prefix_len, p->raw, p->raw_len);
        p->wrapped = 1;
    }
    *body = p->final_body;
    *len = p->final_len;
    return EXTERIA_OK;
}

static int cmp_items(const void *a, const void *b) {
    uint64_t x = ((const batch_item *)a)->msg_id, y = ((const batch_item *)b)->msg_id;
    return x < y ? -1 : (x > y ? 1 : 0);
}

static void record_container(exteria_mt_client *c, uint64_t id, const batch_item *items, uint32_t count) {
    exteria_mt_container_rec *r = &c->containers[c->container_pos];
    uint32_t i;
    c->container_pos = (c->container_pos + 1u) % EXTERIA_MT_CONTAINER_RING;
    r->id = id;
    r->count = 0;
    for (i = 0; i < count && r->count < EXTERIA_MT_CONTAINER_INNER; ++i) r->inner[r->count++] = items[i].msg_id;
}

static exteria_status send_batch(exteria_mt_client *c, batch_item *items, uint32_t count) {
    exteria_writer body;
    uint32_t i;
    exteria_status s;
    if (count == 1) return emit_packet(c, items[0].msg_id, items[0].seq_no, items[0].body, items[0].len);
    qsort(items, count, sizeof(items[0]), cmp_items);
    exteria_writer_init(&body, BATCH_MAX + 4096);
    s = exteria_wr_u32le(&body, CONTAINER_ID);
    if (s == EXTERIA_OK) s = exteria_wr_u32le(&body, count);
    for (i = 0; i < count && s == EXTERIA_OK; ++i) {
        s = exteria_wr_u64le(&body, items[i].msg_id);
        if (s == EXTERIA_OK) s = exteria_wr_u32le(&body, (uint32_t)items[i].seq_no);
        if (s == EXTERIA_OK) s = exteria_wr_u32le(&body, (uint32_t)items[i].len);
        if (s == EXTERIA_OK) s = exteria_wr_bytes(&body, items[i].body, items[i].len);
    }
    if (s == EXTERIA_OK) {
        /* the container id comes after the ids of its messages, the server checks that order */
        uint64_t id = next_id(c);
        record_container(c, id, items, count);
        s = emit_packet(c, id, next_seq(c, 0), body.data, body.len);
    }
    exteria_writer_free(&body);
    return s;
}

static exteria_status flush(exteria_mt_client *c) {
    uint32_t round;
    exteria_status s = EXTERIA_OK;
    if (c->state != EXTERIA_MT_CLIENT_READY) return EXTERIA_OK;
    for (round = 0; round < 4096; ++round) {
        batch_item items[MAX_BATCH_ITEMS];
        exteria_writer scratch[3];
        uint32_t count = 0, i, scratch_used = 0;
        size_t total = 0;
        int more = 0;
        if (c->ack_count) {
            uint32_t take = c->ack_count < MAX_ACKS_PER_MESSAGE ? c->ack_count : MAX_ACKS_PER_MESSAGE;
            exteria_writer_init(&scratch[scratch_used], 4096);
            s = build_ack(c, take, &scratch[scratch_used]);
            if (s != EXTERIA_OK) {
                exteria_writer_free(&scratch[scratch_used]);
                return s;
            }
            memmove(c->acks, c->acks + take, sizeof(c->acks[0]) * (c->ack_count - take));
            c->ack_count -= take;
            items[count].msg_id = next_id(c);
            items[count].seq_no = next_seq(c, 0);
            items[count].body = scratch[scratch_used].data;
            items[count].len = scratch[scratch_used].len;
            total += items[count].len;
            count++;
            scratch_used++;
        }
        for (i = 0; i < c->pending_count && count < MAX_BATCH_ITEMS; ++i) {
            exteria_mt_pending *p = &c->pending[i];
            const uint8_t *body;
            size_t len;
            if (!p->queued) continue;
            if (p->sends >= 8) {
                finish(c, i, EXTERIA_E_LIMIT, NULL, 0, NULL);
                if (c->closing) { s = EXTERIA_E_STATE; break; }
                --i;
                continue;
            }
            if (count > 0 && (p->solo || total + p->raw_len + 64 > BATCH_MAX)) {
                more = 1;
                continue;
            }
            if (p->msg_id == 0 || p->need_new_id) {
                p->msg_id = next_id(c);
                p->seq_no = next_seq(c, 1);
                p->need_new_id = 0;
                p->acked = 0;
            }
            s = finalize_body(c, p, &body, &len);
            if (s != EXTERIA_OK) break;
            items[count].msg_id = p->msg_id;
            items[count].seq_no = p->seq_no;
            items[count].body = body;
            items[count].len = len;
            total += len;
            count++;
            p->queued = 0;
            ++p->sends;
            if (p->solo || len > BATCH_MAX) break;
        }
        if (s == EXTERIA_OK && count > 0) s = send_batch(c, items, count);
        for (i = 0; i < scratch_used; ++i) exteria_writer_free(&scratch[i]);
        if (s != EXTERIA_OK || count == 0 || c->closing) break;
        for (i = 0; i < c->pending_count && !more; ++i) {
            if (c->pending[i].queued) more = 1;
        }
        if (!more && c->ack_count == 0) break;
    }
    return s;
}

static exteria_status send_service(exteria_mt_client *c, const uint8_t *body, size_t len) {
    if (c->state != EXTERIA_MT_CLIENT_READY) return EXTERIA_OK;
    return emit_packet(c, next_id(c), next_seq(c, 0), body, len);
}

static exteria_status send_ping(exteria_mt_client *c) {
    exteria_writer w;
    exteria_status s;
    uint64_t id;
    s = exteria_random_u64(&id);
    if (s != EXTERIA_OK) return s;
    exteria_writer_init(&w, 64);
    s = build_ping(id, c->config.ping_interval_ms / 1000u + PING_DISCONNECT_SLACK, &w);
    if (s == EXTERIA_OK) s = send_service(c, w.data, w.len);
    exteria_writer_free(&w);
    if (s == EXTERIA_OK) {
        c->ping_id = id;
        c->ping_sent_ms = mono_ms(c);
        c->awaiting_pong = 1;
    }
    return s;
}

static void requeue_all(exteria_mt_client *c) {
    uint32_t i;
    for (i = 0; i < c->pending_count; ++i) {
        exteria_mt_pending *p = &c->pending[i];
        p->queued = 1;
        p->need_new_id = 1;
        p->acked = 0;
        free_pending_bodies(p);
    }
}

/* a new session id restarts the sequence numbers, the server and the client then agree again after a clock fix */
static exteria_status restart_session(exteria_mt_client *c) {
    exteria_status s = exteria_random_u64(&c->session_id);
    if (s != EXTERIA_OK) return s;
    if (!c->session_id) return EXTERIA_E_CRYPTO;
    c->last_msg_id = 0;
    c->seq_count = 0;
    c->ack_count = 0;
    c->init_confirmed = 0;
    c->awaiting_pong = 0;
    c->seen_pos = 0;
    memset(c->seen, 0, sizeof(c->seen));
    memset(c->containers, 0, sizeof(c->containers));
    requeue_all(c);
    return EXTERIA_OK;
}

static void adjust_time(exteria_mt_client *c, uint64_t server_msg_id) {
    uint64_t seconds = server_msg_id >> 32;
    uint64_t millis = ((server_msg_id & 0xffffffffull) * 1000u) >> 32;
    int64_t server_time = (int64_t)(seconds * 1000u + millis);
    c->time_offset_ms = server_time - (int64_t)real_ms(c);
    notify_session(c);
}

static void mark_resend(exteria_mt_client *c, uint64_t id, int new_id, int solo) {
    exteria_mt_pending *p = find_by_msg(c, id);
    uint32_t i, k;
    if (p) {
        p->queued = 1;
        if (new_id) p->need_new_id = 1;
        if (solo) p->solo = 1;
        return;
    }
    for (i = 0; i < EXTERIA_MT_CONTAINER_RING; ++i) {
        if (c->containers[i].id != id) continue;
        for (k = 0; k < c->containers[i].count; ++k) {
            exteria_mt_pending *q = find_by_msg(c, c->containers[i].inner[k]);
            if (!q) continue;
            q->queued = 1;
            if (new_id) q->need_new_id = 1;
            if (solo) q->solo = 1;
        }
        return;
    }
}

static exteria_status build_init_prefix(exteria_mt_client *c) {
    exteria_arena a;
    exteria_tl_value *layer, *init, *dummy;
    exteria_writer w;
    exteria_status s;
    const exteria_mt_client_config *cfg = &c->config;
    if (cfg->api_id == 0) return EXTERIA_OK;
    exteria_arena_init(&a, 16384);
    layer = exteria_tl_new_obj(&a, "invokeWithLayer");
    init = exteria_tl_new_obj(&a, "initConnection");
    dummy = exteria_tl_new_obj(&a, "help.getConfig");
    if (!layer || !init || !dummy) {
        exteria_arena_free(&a);
        return EXTERIA_E_NOMEM;
    }
    s = exteria_tl_set_i32(&a, init, "api_id", cfg->api_id);
    if (s == EXTERIA_OK) s = exteria_tl_set_str(&a, init, "device_model", cfg->device_model ? cfg->device_model : "");
    if (s == EXTERIA_OK) s = exteria_tl_set_str(&a, init, "system_version", cfg->system_version ? cfg->system_version : "");
    if (s == EXTERIA_OK) s = exteria_tl_set_str(&a, init, "app_version", cfg->app_version ? cfg->app_version : "");
    if (s == EXTERIA_OK) s = exteria_tl_set_str(&a, init, "system_lang_code", cfg->system_lang_code ? cfg->system_lang_code : "en");
    if (s == EXTERIA_OK) s = exteria_tl_set_str(&a, init, "lang_pack", cfg->lang_pack ? cfg->lang_pack : "");
    if (s == EXTERIA_OK) s = exteria_tl_set_str(&a, init, "lang_code", cfg->lang_code ? cfg->lang_code : "en");
    if (s == EXTERIA_OK) s = exteria_tl_set(init, "query", dummy);
    if (s == EXTERIA_OK) s = exteria_tl_set_i32(&a, layer, "layer", (int32_t)exteria_tl_layer);
    if (s == EXTERIA_OK) s = exteria_tl_set(layer, "query", init);
    exteria_writer_init(&w, 4096);
    if (s == EXTERIA_OK) s = exteria_tl_encode(layer, &w, NULL);
    exteria_arena_free(&a);
    if (s != EXTERIA_OK) {
        exteria_writer_free(&w);
        return s;
    }
    /* encoding a complete wrapper keeps optional fields aligned with the schema */
    c->init_prefix_len = w.len - 4;
    c->init_prefix = (uint8_t *)malloc(c->init_prefix_len);
    if (!c->init_prefix) {
        exteria_writer_free(&w);
        return EXTERIA_E_NOMEM;
    }
    memcpy(c->init_prefix, w.data, c->init_prefix_len);
    exteria_writer_free(&w);
    return EXTERIA_OK;
}

exteria_status exteria_mt_client_init(exteria_mt_client *c, const exteria_mt_client_config *config,
                                      const exteria_mt_client_events *events) {
    exteria_status s;
    if (!c || !config || !events || (!events->send && !events->send_checked) ||
        config->max_pending > 8192 || config->result_arena_limit > 64u * 1024u * 1024u ||
        (config->clock && (!config->clock->realtime_ms || !config->clock->monotonic_ms))) return EXTERIA_E_ARG;
    memset(c, 0, sizeof(*c));
    c->config = *config;
    c->events = *events;
    if (!c->config.clock) c->config.clock = &exteria_system_clock;
    if (!c->config.transport) c->config.transport = EXTERIA_MT_INTERMEDIATE;
    if (c->config.max_pending == 0) c->config.max_pending = MAX_PENDING_DEFAULT;
    if (c->config.result_arena_limit == 0) c->config.result_arena_limit = RESULT_ARENA_DEFAULT;
    if (c->config.ping_interval_ms == 0) c->config.ping_interval_ms = EXTERIA_MT_PING_INTERVAL_DEFAULT;
    if (c->config.pong_timeout_ms == 0) c->config.pong_timeout_ms = PONG_TIMEOUT_DEFAULT;
    c->state = EXTERIA_MT_CLIENT_DISCONNECTED;
    exteria_mt_transport_init(&c->transport);
    if (config->restore) {
        s = exteria_mt_auth_key_set(&c->key, config->restore->auth_key);
        if (s != EXTERIA_OK) return s;
        c->has_key = 1;
        c->salt = config->restore->server_salt;
        c->time_offset_ms = config->restore->time_offset_ms;
        c->config.restore = NULL;
    }
    return build_init_prefix(c);
}

void exteria_mt_client_free(exteria_mt_client *c) {
    if (!c || c->closing) return;
    if (c->operation_depth) { c->closing = 1; c->state = EXTERIA_MT_CLIENT_DEAD; return; }
    c->closing = 1;
    c->state = EXTERIA_MT_CLIENT_DEAD;
    while (c->pending_count) finish(c, c->pending_count - 1, EXTERIA_E_STATE, NULL, 0, NULL);
    free(c->pending);
    free(c->init_prefix);
    exteria_mt_transport_free(&c->transport);
    exteria_mt_hs_wipe(&c->handshake);
    exteria_wipe(&c->key, sizeof(c->key));
    memset(c, 0, sizeof(*c));
}

static exteria_status send_framed(exteria_mt_client *c, const uint8_t *packet, size_t len) {
    exteria_writer w;
    exteria_status s;
    exteria_writer_init(&w, len + 64);
    s = exteria_mt_transport_wrap(&c->transport, packet, len, 0, &w);
    if (s == EXTERIA_OK) s = send_bytes(c, w.data, w.len);
    exteria_writer_free(&w);
    return s;
}

static exteria_status client_connect(exteria_mt_client *c) {
    exteria_writer preamble;
    exteria_status s;
    if (!c || c->state != EXTERIA_MT_CLIENT_DISCONNECTED) return EXTERIA_E_STATE;
    exteria_mt_transport_free(&c->transport);
    exteria_mt_transport_init(&c->transport);
    c->transport_error = 0;
    c->last_ctor = 0;
    c->security_note = NULL;
    c->security_value = 0;
    c->heard = 0;
    exteria_writer_init(&preamble, 256);
    s = exteria_mt_transport_start(&c->transport, c->config.transport, &c->config.obfuscation, &preamble);
    if (s != EXTERIA_OK) {
        exteria_writer_free(&preamble);
        return s;
    }
    if (preamble.len) s = send_bytes(c, preamble.data, preamble.len);
    exteria_writer_free(&preamble);
    if (s != EXTERIA_OK) return die(c, s);
    c->last_rx_ms = mono_ms(c);
    if (!c->has_key) {
        exteria_mt_hs_config hc;
        exteria_writer out;
        memset(&hc, 0, sizeof(hc));
        hc.dc_id = c->config.dc_id;
        hc.is_test = c->config.is_test;
        hc.keys = c->config.keys;
        hc.key_count = c->config.key_count;
        hc.clock = c->config.clock;
        exteria_mt_hs_init(&c->handshake, &hc);
        exteria_writer_init(&out, 4096);
        s = exteria_mt_hs_start(&c->handshake, &out);
        if (s == EXTERIA_OK) s = send_framed(c, out.data, out.len);
        exteria_writer_free(&out);
        if (s != EXTERIA_OK) return s;
        set_state(c, EXTERIA_MT_CLIENT_HANDSHAKE, EXTERIA_OK);
        return EXTERIA_OK;
    }
    s = restart_session(c);
    if (s != EXTERIA_OK) return s;
    set_state(c, EXTERIA_MT_CLIENT_READY, EXTERIA_OK);
    return flush(c);
}

void exteria_mt_client_disconnected(exteria_mt_client *c) {
    if (!c) return;
    exteria_mt_transport_free(&c->transport);
    exteria_mt_transport_init(&c->transport);
    c->ack_count = 0;
    c->awaiting_pong = 0;
    if (c->state != EXTERIA_MT_CLIENT_DISCONNECTED) set_state(c, EXTERIA_MT_CLIENT_DISCONNECTED, EXTERIA_OK);
}

static exteria_status die(exteria_mt_client *c, exteria_status reason) {
    set_state(c, EXTERIA_MT_CLIENT_DEAD, reason);
    return reason;
}

static void deliver_updates(exteria_mt_client *c, const exteria_tl_value *v) {
    if (c->events.update) c->events.update(c->events.ctx, v);
}

static exteria_status accept_salts(exteria_mt_client *c, const exteria_tl_value *v) {
    const exteria_tl_value *vec = exteria_tl_get(v, "salts");
    exteria_mt_salt salts[64];
    uint32_t i;
    uint64_t current = server_ms(c) / 1000u;
    if (!vec || vec->kind != EXTERIA_TL_V_VEC || !vec->u.vec.count || vec->u.vec.count > 64) return EXTERIA_E_MALFORMED;
    for (i = 0; i < vec->u.vec.count; ++i) {
        int64_t value;
        const exteria_tl_value *item = vec->u.vec.items[i];
        if (exteria_tl_get_i32(item, "valid_since", &salts[i].since) != EXTERIA_OK ||
            exteria_tl_get_i32(item, "valid_until", &salts[i].until) != EXTERIA_OK ||
            exteria_tl_get_i64(item, "salt", &value) != EXTERIA_OK || salts[i].since < 0 || salts[i].until <= salts[i].since)
            return EXTERIA_E_MALFORMED;
        salts[i].value = (uint64_t)value;
    }
    memcpy(c->salts, salts, vec->u.vec.count * sizeof(salts[0]));
    c->salt_count = vec->u.vec.count;
    for (i = 0; i < c->salt_count; ++i) {
        if ((uint64_t)c->salts[i].since <= current && current < (uint64_t)c->salts[i].until && c->salt != c->salts[i].value) {
            c->salt = c->salts[i].value;
            notify_session(c);
            break;
        }
    }
    return EXTERIA_OK;
}

static exteria_status handle_rpc_result(exteria_mt_client *c, const uint8_t *body, size_t len) {
    uint64_t req_id;
    exteria_mt_pending *p;
    exteria_arena a;
    exteria_tl_value *v = NULL;
    exteria_tl_limits lim = exteria_tl_default_limits;
    exteria_status s;
    uint32_t index;
    if (len < 16) return EXTERIA_E_MALFORMED;
    req_id = exteria_get_u64le(body + 4);
    p = find_by_msg(c, req_id);
    if (!p) return EXTERIA_OK;
    index = (uint32_t)(p - c->pending);
    int wrapped = p->wrapped;
    exteria_arena_init(&a, c->config.result_arena_limit);
    s = exteria_tl_decode_all(&a, &lim, p->result_ref, body + 12, len - 12, &v);
    if (s == EXTERIA_OK && !exteria_tl_is(v, EXTERIA_TL_ID_rpc_error)) {
        if (wrapped) c->init_confirmed = 1;
        if (exteria_tl_is(v, EXTERIA_TL_ID_future_salts)) s = accept_salts(c, v);
        finish(c, index, s, s == EXTERIA_OK ? v : NULL, 0, NULL);
    } else {
        exteria_tl_value *any = v;
        exteria_status s2 = s;
        if (s != EXTERIA_OK) {
            /* a failed typed decode must not consume the error decoder's arena budget */
            exteria_arena_free(&a);
            s2 = exteria_tl_decode_all(&a, &lim, EXTERIA_TL_REF_ANY, body + 12, len - 12, &any);
        }
        if (s2 == EXTERIA_OK && exteria_tl_is(any, EXTERIA_TL_ID_rpc_error)) {
            int32_t code = 0;
            const uint8_t *text = (const uint8_t *)"";
            size_t text_len = 0;
            (void)exteria_tl_get_i32(any, "error_code", &code);
            (void)exteria_tl_get_bytes(any, "error_message", &text, &text_len);
            if (memchr(text, 0, text_len)) finish(c, index, EXTERIA_E_MALFORMED, NULL, 0, NULL);
            else finish(c, index, EXTERIA_E_RPC, NULL, code, (const char *)text);
        } else {
            finish(c, index, s == EXTERIA_E_TRUNCATED ? EXTERIA_E_MALFORMED : s, NULL, 0, NULL);
        }
    }
    exteria_arena_free(&a);
    return EXTERIA_OK;
}

static void handle_ack_list(exteria_mt_client *c, const exteria_tl_value *v) {
    const exteria_tl_value *ids = NULL;
    uint32_t i;
    if (exteria_tl_get_vec(v, "msg_ids", &ids) != EXTERIA_OK) return;
    for (i = 0; i < ids->u.vec.count; ++i) {
        exteria_mt_pending *p = find_by_msg(c, (uint64_t)ids->u.vec.items[i]->u.i64);
        if (p) p->acked = 1;
    }
}

static exteria_status handle_bad_msg(exteria_mt_client *c, const exteria_tl_value *v, uint64_t server_msg_id) {
    int64_t bad_id = 0;
    int32_t code = 0;
    (void)exteria_tl_get_i64(v, "bad_msg_id", &bad_id);
    (void)exteria_tl_get_i32(v, "error_code", &code);
    switch (code) {
    case 16:
    case 17:
        adjust_time(c, server_msg_id);
        return restart_session(c);
        break;
    case 18:
    case 19:
    case 20:
        mark_resend(c, (uint64_t)bad_id, 1, 0);
        c->flush_wanted = 1;
        break;
    case 32:
    case 33:
    case 34:
    case 35:
        return restart_session(c);
        break;
    case 64:
        mark_resend(c, (uint64_t)bad_id, 1, 1);
        break;
    default:
        return EXTERIA_E_MALFORMED;
    }
    c->flush_wanted = 1;
    return EXTERIA_OK;
}

static void handle_bad_salt(exteria_mt_client *c, const exteria_tl_value *v) {
    int64_t bad_id = 0, salt = 0;
    (void)exteria_tl_get_i64(v, "bad_msg_id", &bad_id);
    if (exteria_tl_get_i64(v, "new_server_salt", &salt) != EXTERIA_OK) return;
    c->salt = (uint64_t)salt;
    notify_session(c);
    /* the server dropped the message before running it, so the same id and sequence number go out again */
    mark_resend(c, (uint64_t)bad_id, 0, 0);
    c->flush_wanted = 1;
}

static void handle_new_session(exteria_mt_client *c, const exteria_tl_value *v) {
    int64_t first = 0, salt = 0;
    uint32_t i;
    (void)exteria_tl_get_i64(v, "first_msg_id", &first);
    if (exteria_tl_get_i64(v, "server_salt", &salt) == EXTERIA_OK) {
        c->salt = (uint64_t)salt;
        notify_session(c);
    }
    /* anything older than the first message of the session was lost with the previous one */
    for (i = 0; i < c->pending_count; ++i) {
        exteria_mt_pending *p = &c->pending[i];
        if (!p->queued && p->msg_id != 0 && p->msg_id < (uint64_t)first) {
            p->queued = 1;
            p->need_new_id = 1;
        }
    }
    if (c->events.new_session) c->events.new_session(c->events.ctx);
    c->flush_wanted = 1;
}

static exteria_status handle_detailed_info(exteria_mt_client *c, const exteria_tl_value *v) {
    int64_t answer = 0;
    exteria_arena a;
    exteria_tl_value *req;
    exteria_writer w;
    exteria_status s = exteria_tl_get_i64(v, "answer_msg_id", &answer);
    if (s != EXTERIA_OK) return s;
    if (seen_before(c, (uint64_t)answer)) return queue_ack(c, (uint64_t)answer);
    exteria_arena_init(&a, 4096);
    req = exteria_tl_new_obj(&a, "msg_resend_req");
    exteria_writer_init(&w, 128);
    s = req ? exteria_tl_set_i64_vec(&a, req, "msg_ids", &answer, 1) : EXTERIA_E_NOMEM;
    if (s == EXTERIA_OK) s = encode_service(req, &w);
    if (s == EXTERIA_OK) s = send_service(c, w.data, w.len);
    exteria_writer_free(&w);
    exteria_arena_free(&a);
    return s;
}

static exteria_status handle_state_req(exteria_mt_client *c, const exteria_tl_value *v, uint64_t msg_id) {
    const exteria_tl_value *ids = NULL;
    exteria_arena a;
    exteria_tl_value *reply;
    exteria_writer w;
    uint8_t info[8192];
    uint32_t i, n;
    exteria_status s = exteria_tl_get_vec(v, "msg_ids", &ids);
    if (s != EXTERIA_OK) return s;
    n = ids->u.vec.count;
    /* mtproto requires one status byte per requested id, truncation changes the reply */
    if (n > sizeof(info)) return EXTERIA_E_LIMIT;
    for (i = 0; i < n; ++i) info[i] = seen_before(c, (uint64_t)ids->u.vec.items[i]->u.i64) ? 4 : 1;
    exteria_arena_init(&a, 16384);
    reply = exteria_tl_new_obj(&a, "msgs_state_info");
    exteria_writer_init(&w, sizeof(info) + 64);
    s = reply ? exteria_tl_set_i64(&a, reply, "req_msg_id", (int64_t)msg_id) : EXTERIA_E_NOMEM;
    if (s == EXTERIA_OK) s = exteria_tl_set_bytes(&a, reply, "info", info, n);
    if (s == EXTERIA_OK) s = encode_service(reply, &w);
    if (s == EXTERIA_OK) s = send_service(c, w.data, w.len);
    exteria_writer_free(&w);
    exteria_arena_free(&a);
    return s;
}

static exteria_status process_message(exteria_mt_client *c, uint64_t msg_id, int32_t seq_no, const uint8_t *body,
                                      size_t len, unsigned depth);

static exteria_status process_container(exteria_mt_client *c, uint64_t msg_id, int32_t seq_no,
                                        const uint8_t *body, size_t len, unsigned depth) {
    exteria_reader r;
    uint32_t count, i;
    if (depth != 0 || len < 8 || (seq_no & 1)) return EXTERIA_E_MALFORMED;
    exteria_reader_init(&r, body + 4, len - 4);
    count = exteria_rd_u32le(&r);
    if (count > MAX_CONTAINER_MESSAGES || count > exteria_reader_left(&r) / 20u) return EXTERIA_E_MALFORMED;
    /* validate every frame before a callback can observe any part of the container */
    for (i = 0; i < count; ++i) {
        uint64_t id = exteria_rd_u64le(&r);
        int32_t seq = (int32_t)exteria_rd_u32le(&r);
        uint32_t n = exteria_rd_u32le(&r);
        const uint8_t *p;
        if (r.status != EXTERIA_OK || !(id & 1u) || id >= msg_id || seq < 0 ||
            n % 4u || n < 4u || n > exteria_reader_left(&r)) return EXTERIA_E_MALFORMED;
        p = exteria_rd_bytes(&r, n);
        if (!p || exteria_get_u32le(p) == CONTAINER_ID) return EXTERIA_E_MALFORMED;
    }
    if (exteria_reader_left(&r) != 0) return EXTERIA_E_MALFORMED;
    exteria_reader_init(&r, body + 8, len - 8);
    for (i = 0; i < count; ++i) {
        uint64_t id = exteria_rd_u64le(&r);
        int32_t seq = (int32_t)exteria_rd_u32le(&r);
        uint32_t n = exteria_rd_u32le(&r);
        const uint8_t *p = exteria_rd_bytes(&r, n);
        exteria_status s = process_message(c, id, seq, p, n, depth + 1);
        if (s != EXTERIA_OK) return s;
    }
    return EXTERIA_OK;
}

static int is_updates_type(const exteria_tl_value *v) {
    const char *name;
    if (!v || v->kind != EXTERIA_TL_V_OBJ) return 0;
    name = exteria_tl_result_type_name(v->u.obj.ctor);
    return name && strcmp(name, "Updates") == 0;
}

static exteria_status dispatch_body(exteria_mt_client *c, uint64_t msg_id, int32_t seq_no,
                                    const uint8_t *body, size_t len, unsigned depth, int unpacked) {
    uint32_t id;
    exteria_arena a;
    exteria_tl_value *v = NULL;
    exteria_status s = EXTERIA_OK;
    if (len < 4 || len % 4u) return EXTERIA_E_MALFORMED;
    id = exteria_get_u32le(body);
    c->last_ctor = id;
    if (id == EXTERIA_TL_ID_gzip_packed) {
        exteria_writer plain;
        size_t limit = c->config.result_arena_limit;
        if (unpacked) return EXTERIA_E_MALFORMED;
        if (limit > exteria_tl_default_limits.max_inflate) limit = exteria_tl_default_limits.max_inflate;
        exteria_writer_init(&plain, limit);
        s = exteria_tl_unpack_gzip(body, len, &plain);
        if (s == EXTERIA_OK) s = dispatch_body(c, msg_id, seq_no, plain.data, plain.len, depth, 1);
        exteria_writer_free(&plain);
        return s == EXTERIA_E_TRUNCATED ? EXTERIA_E_MALFORMED : s;
    }
    if (id == CONTAINER_ID) return process_container(c, msg_id, seq_no, body, len, depth);
    if (id == EXTERIA_TL_ID_rpc_result) return handle_rpc_result(c, body, len);
    exteria_arena_init(&a, c->config.result_arena_limit);
    s = exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, body, len, &v);
    if (s != EXTERIA_OK) {
        /* an updates message that cannot be read leaves a hole, the owner of the update state has to refill it */
        const exteria_tl_ctor *ctor = exteria_tl_find_ctor(id);
        const char *type = ctor ? exteria_tl_result_type_name(ctor) : NULL;
        if (!ctor || (type && strcmp(type, "Updates") == 0)) {
            if (c->events.update_lost) c->events.update_lost(c->events.ctx, s);
            s = EXTERIA_OK;
        }
        exteria_arena_free(&a);
        return s == EXTERIA_E_TRUNCATED ? EXTERIA_E_MALFORMED : s;
    }
    switch (exteria_tl_id(v)) {
    case EXTERIA_TL_ID_msgs_ack: handle_ack_list(c, v); break;
    case EXTERIA_TL_ID_pong: {
        int64_t ping = 0;
        if (exteria_tl_get_i64(v, "ping_id", &ping) == EXTERIA_OK && c->awaiting_pong && (uint64_t)ping == c->ping_id) c->awaiting_pong = 0;
        break;
    }
    case EXTERIA_TL_ID_bad_msg_notification: s = handle_bad_msg(c, v, msg_id); break;
    case EXTERIA_TL_ID_bad_server_salt: handle_bad_salt(c, v); break;
    case EXTERIA_TL_ID_new_session_created: handle_new_session(c, v); break;
    case EXTERIA_TL_ID_msg_detailed_info:
    case EXTERIA_TL_ID_msg_new_detailed_info: s = handle_detailed_info(c, v); break;
    case EXTERIA_TL_ID_msgs_state_req: s = handle_state_req(c, v, msg_id); break;
    case EXTERIA_TL_ID_msg_resend_req: {
        const exteria_tl_value *ids;
        uint32_t i;
        s = exteria_tl_get_vec(v, "msg_ids", &ids);
        if (s == EXTERIA_OK && ids->u.vec.count > 8192) s = EXTERIA_E_LIMIT;
        if (s == EXTERIA_OK) for (i = 0; i < ids->u.vec.count; ++i)
            mark_resend(c, (uint64_t)ids->u.vec.items[i]->u.i64, 0, 0);
        break;
    }
    case EXTERIA_TL_ID_future_salts: s = accept_salts(c, v); break;
    case EXTERIA_TL_ID_msgs_all_info:
    case EXTERIA_TL_ID_msgs_state_info:
    case EXTERIA_TL_ID_destroy_session_ok:
    case EXTERIA_TL_ID_destroy_session_none:
        break;
    default:
        if (is_updates_type(v)) deliver_updates(c, v);
        break;
    }
    exteria_arena_free(&a);
    return s;
}

static exteria_status process_message(exteria_mt_client *c, uint64_t msg_id, int32_t seq_no,
                                      const uint8_t *body, size_t len, unsigned depth) {
    exteria_status s;
    uint32_t id;
    if (len < 4 || len % 4u || !(msg_id & 1u) || seq_no < 0) return EXTERIA_E_MALFORMED;
    id = exteria_get_u32le(body);
    /* a container is a service message, but the server packs large content, such as updates, in gzip with an odd seq_no */
    if ((seq_no & 1) && id == CONTAINER_ID) return EXTERIA_E_MALFORMED;
    if (seq_no & 1) {
        s = queue_ack(c, msg_id);
        if (s != EXTERIA_OK) return s;
    }
    if (seen_before(c, msg_id)) return EXTERIA_OK;
    s = dispatch_body(c, msg_id, seq_no, body, len, depth, 0);
    if (s == EXTERIA_OK) remember(c, msg_id);
    return s;
}

/* the server packs its salt correction and the start of a session into a container, and the salt on that container
   is already the new one, so it cannot be checked against the old */
static int container_corrects_salt(const uint8_t *body, size_t len) {
    exteria_reader r;
    uint32_t count, i;
    if (len < 8) return 0;
    exteria_reader_init(&r, body + 4, len - 4);
    count = exteria_rd_u32le(&r);
    if (count > MAX_CONTAINER_MESSAGES) return 0;
    for (i = 0; i < count; ++i) {
        uint32_t n, ctor;
        const uint8_t *p;
        (void)exteria_rd_u64le(&r);
        (void)exteria_rd_u32le(&r);
        n = exteria_rd_u32le(&r);
        if (r.status != EXTERIA_OK || n < 4u || n > exteria_reader_left(&r)) return 0;
        p = exteria_rd_bytes(&r, n);
        if (!p) return 0;
        ctor = exteria_get_u32le(p);
        if (ctor == EXTERIA_TL_ID_bad_server_salt || ctor == EXTERIA_TL_ID_new_session_created) return 1;
    }
    return 0;
}

static exteria_status handle_handshake_frame(exteria_mt_client *c, const exteria_mt_frame *f) {
    exteria_writer out;
    exteria_status s;
    exteria_writer_init(&out, 4096);
    s = exteria_mt_hs_receive(&c->handshake, f->data, f->len, exteria_mt_transport_padded(&c->transport), &out);
    if (s == EXTERIA_OK && out.len) s = send_framed(c, out.data, out.len);
    exteria_writer_free(&out);
    if (s != EXTERIA_OK) return s;
    if (c->handshake.state == EXTERIA_MT_HS_DONE) {
        const exteria_mt_hs_result *r = exteria_mt_hs_result_get(&c->handshake);
        s = exteria_mt_auth_key_set(&c->key, r->key.key);
        if (s != EXTERIA_OK) return s;
        c->has_key = 1;
        c->salt = r->server_salt;
        c->time_offset_ms = r->time_offset_ms;
        exteria_mt_hs_wipe(&c->handshake);
        notify_session(c);
        s = restart_session(c);
        if (s != EXTERIA_OK) return s;
        set_state(c, EXTERIA_MT_CLIENT_READY, EXTERIA_OK);
    }
    return EXTERIA_OK;
}

/* a frame from the server is refused as unsafe; the note and number say which check it failed */
static exteria_status refuse(exteria_mt_client *c, const char *note, int64_t value) {
    c->security_note = note;
    c->security_value = value;
    return EXTERIA_E_SECURITY;
}

static exteria_status handle_data_frame(exteria_mt_client *c, const exteria_mt_frame *f) {
    exteria_writer plain;
    exteria_mt_header h;
    const uint8_t *body;
    size_t body_len;
    exteria_status s;
    exteria_writer_init(&plain, f->len + 64);
    s = exteria_mt_decrypt(&c->key, 0, exteria_mt_transport_padded(&c->transport), f->data, f->len, &plain, &h, &body, &body_len);
    if (s != EXTERIA_OK) {
        exteria_writer_free(&plain);
        if (s == EXTERIA_E_SECURITY) return refuse(c, f->len >= 8 && exteria_get_u64le(f->data) != c->key.id ? "auth key id" : "message key", 0);
        return s;
    }
    if (h.session_id != c->session_id) {
        exteria_writer_free(&plain);
        return refuse(c, "session id", 0);
    }
    uint32_t ctor = body_len >= 4 ? exteria_get_u32le(body) : 0;
    uint64_t timestamp = (h.msg_id >> 32) * 1000u;
    uint64_t current = server_ms(c);
    int correction = 0, valid_salt = h.salt == c->salt;
    uint32_t i;
    if (ctor == EXTERIA_TL_ID_bad_msg_notification && body_len >= 20) {
        uint32_t code = exteria_get_u32le(body + 16);
        correction = (code == 16 || code == 17) && is_outgoing(c, exteria_get_u64le(body + 4));
    }
    for (i = 0; i < c->salt_count; ++i) {
        if (h.salt == c->salts[i].value && (uint64_t)c->salts[i].since <= timestamp / 1000u &&
            timestamp / 1000u < (uint64_t)c->salts[i].until) valid_salt = 1;
    }
    int stale = !correction && ((timestamp < current && current - timestamp > 300000u) ||
                                (timestamp > current && timestamp - current > TIME_SYNC_SLACK_MS));
    int unknown_salt = !valid_salt && ctor != EXTERIA_TL_ID_bad_server_salt && ctor != EXTERIA_TL_ID_new_session_created &&
                       !(ctor == CONTAINER_ID && container_corrects_salt(body, body_len));
    if (stale || unknown_salt) {
        exteria_writer_free(&plain);
        return refuse(c, stale ? "message time" : "server salt", (int64_t)timestamp - (int64_t)current);
    }
    s = process_message(c, h.msg_id, h.seq_no, body, body_len, 0);
    exteria_writer_free(&plain);
    if (s == EXTERIA_OK) c->heard = 1;
    return s;
}

static exteria_status client_feed(exteria_mt_client *c, const uint8_t *data, size_t len) {
    exteria_status s;
    exteria_mt_frame f;
    if (!c || (len && !data)) return EXTERIA_E_ARG;
    if (c->in_feed || c->closing) return EXTERIA_E_STATE;
    if (c->state != EXTERIA_MT_CLIENT_HANDSHAKE && c->state != EXTERIA_MT_CLIENT_READY) return EXTERIA_E_STATE;
    s = exteria_mt_transport_feed(&c->transport, data, len);
    if (s != EXTERIA_OK) return die(c, s);
    c->last_rx_ms = mono_ms(c);
    c->in_feed = 1;
    for (;;) {
        s = exteria_mt_transport_next(&c->transport, &f);
        if (s == EXTERIA_E_TRUNCATED) {
            s = EXTERIA_OK;
            break;
        }
        if (s != EXTERIA_OK) break;
        if (f.kind == EXTERIA_MT_FRAME_QUICK_ACK) continue;
        if (f.kind == EXTERIA_MT_FRAME_ERROR) {
            c->transport_error = f.error_code;
            s = f.error_code == -404 ? EXTERIA_E_NOTFOUND : (f.error_code == -429 ? EXTERIA_E_LIMIT : EXTERIA_E_IO);
            break;
        }
        if (c->state == EXTERIA_MT_CLIENT_HANDSHAKE) s = handle_handshake_frame(c, &f);
        else s = handle_data_frame(c, &f);
        if (s != EXTERIA_OK) break;
        if (c->state != EXTERIA_MT_CLIENT_HANDSHAKE && c->state != EXTERIA_MT_CLIENT_READY) break;
    }
    c->in_feed = 0;
    if (s != EXTERIA_OK) return die(c, s);
    if (c->state == EXTERIA_MT_CLIENT_READY) {
        c->flush_wanted = 0;
        s = flush(c);
        if (s != EXTERIA_OK) return die(c, s);
    }
    return EXTERIA_OK;
}

static exteria_status client_submit(exteria_mt_client *c, uint64_t request_id, const exteria_tl_value *request,
                                        uint32_t timeout_ms) {
    exteria_writer w;
    exteria_mt_pending *p;
    uint16_t ref = 0;
    exteria_status s;
    if (!c || !request || !request_id) return EXTERIA_E_ARG;
    if (c->state == EXTERIA_MT_CLIENT_DEAD || c->closing) return EXTERIA_E_STATE;
    if (c->pending_count >= c->config.max_pending) return EXTERIA_E_LIMIT;
    if (find_index_by_request(c, request_id) >= 0) return EXTERIA_E_ARG;
    s = exteria_tl_result_ref(request, &ref);
    if (s != EXTERIA_OK) return s;
    exteria_writer_init(&w, 4u * 1024u * 1024u);
    s = exteria_tl_encode(request, &w, NULL);
    if (s != EXTERIA_OK) {
        exteria_writer_free(&w);
        return s;
    }
    if (c->pending_count == c->pending_cap) {
        uint32_t cap = c->pending_cap ? c->pending_cap * 2u : 16u;
        exteria_mt_pending *grown = (exteria_mt_pending *)realloc(c->pending, sizeof(*grown) * cap);
        if (!grown) {
            exteria_writer_free(&w);
            return EXTERIA_E_NOMEM;
        }
        c->pending = grown;
        c->pending_cap = cap;
    }
    p = &c->pending[c->pending_count++];
    memset(p, 0, sizeof(*p));
    p->request_id = request_id;
    p->raw = exteria_writer_take(&w, &p->raw_len);
    p->result_ref = ref;
    p->queued = 1;
    p->deadline_ms = timeout_ms ? mono_ms(c) + timeout_ms : 0;
    if (c->in_feed) {
        c->flush_wanted = 1;
        return EXTERIA_OK;
    }
    s = flush(c);
    return s == EXTERIA_OK ? s : die(c, s);
}

exteria_status exteria_mt_client_cancel(exteria_mt_client *c, uint64_t request_id) {
    int idx;
    exteria_mt_pending p;
    if (!c) return EXTERIA_E_ARG;
    idx = find_index_by_request(c, request_id);
    if (idx < 0) return EXTERIA_E_NOTFOUND;
    p = c->pending[idx];
    memmove(&c->pending[idx], &c->pending[idx + 1], sizeof(c->pending[0]) * (c->pending_count - (uint32_t)idx - 1));
    c->pending_count--;
    free_pending(&p);
    return EXTERIA_OK;
}

static uint32_t client_tick(exteria_mt_client *c) {
    uint64_t now, next = UINT64_MAX;
    uint32_t i;
    if (!c) return UINT32_MAX;
    now = mono_ms(c);
    for (i = 0; i < c->pending_count;) {
        exteria_mt_pending *p = &c->pending[i];
        if (p->deadline_ms && now >= p->deadline_ms) {
            finish(c, i, EXTERIA_E_TIMEOUT, NULL, 0, NULL);
            continue;
        }
        if (p->deadline_ms && p->deadline_ms < next) next = p->deadline_ms;
        ++i;
    }
    if (c->state == EXTERIA_MT_CLIENT_READY) {
        if (c->awaiting_pong) {
            uint64_t due = c->ping_sent_ms + c->config.pong_timeout_ms;
            if (now >= due) {
                (void)die(c, EXTERIA_E_TIMEOUT);
                return UINT32_MAX;
            }
            if (due < next) next = due;
        } else {
            uint64_t due = c->last_rx_ms + c->config.ping_interval_ms;
            if (now >= due) {
                exteria_status status = send_ping(c);
                if (status != EXTERIA_OK) { die(c, status); return UINT32_MAX; }
                due = c->ping_sent_ms + c->config.pong_timeout_ms;
            }
            if (due < next) next = due;
        }
        exteria_status status = flush(c);
        if (status != EXTERIA_OK) { die(c, status); return UINT32_MAX; }
    }
    if (next == UINT64_MAX) return UINT32_MAX;
    next = next > now ? next - now : 0;
    return next > 0xfffffffeu ? 0xfffffffeu : (uint32_t)next;
}

int exteria_mt_client_get_session(const exteria_mt_client *c, exteria_mt_session_state *out) {
    if (!c || !out || !c->has_key) return 0;
    memcpy(out->auth_key, c->key.key, sizeof(out->auth_key));
    out->server_salt = c->salt;
    out->time_offset_ms = c->time_offset_ms;
    return 1;
}

uint32_t exteria_mt_client_last_ctor(const exteria_mt_client *c) {
    return c ? c->last_ctor : 0;
}

int32_t exteria_mt_client_transport_error(const exteria_mt_client *c) {
    return c ? c->transport_error : 0;
}

const char *exteria_mt_client_security_note(const exteria_mt_client *c, int64_t *value) {
    if (value) *value = c ? c->security_value : 0;
    return c ? c->security_note : NULL;
}

void exteria_mt_client_set_ping_interval(exteria_mt_client *c, uint32_t interval_ms) {
    if (!c) return;
    if (interval_ms < PING_INTERVAL_MIN) interval_ms = PING_INTERVAL_MIN;
    if (interval_ms > PING_INTERVAL_MAX) interval_ms = PING_INTERVAL_MAX;
    c->config.ping_interval_ms = interval_ms;
}

uint32_t exteria_mt_client_ping_interval(const exteria_mt_client *c) {
    return c ? c->config.ping_interval_ms : 0;
}

int exteria_mt_client_heard(const exteria_mt_client *c) {
    return c ? c->heard : 0;
}

uint32_t exteria_mt_client_pending_count(const exteria_mt_client *c) {
    return c ? c->pending_count : 0;
}

void exteria_mt_rpc_error_split(const char *text, char *name, size_t name_cap, int32_t *number) {
    size_t len, end, digits_at;
    int64_t value = 0;
    if (number) *number = -1;
    if (!name || name_cap == 0) return;
    name[0] = 0;
    if (!text) return;
    len = strlen(text);
    end = len;
    digits_at = len;
    while (digits_at > 0 && text[digits_at - 1] >= '0' && text[digits_at - 1] <= '9') --digits_at;
    /* only a number after an underscore counts, names such as DC_ID_INVALID2 keep their digits */
    if (digits_at < len && digits_at > 0 && text[digits_at - 1] == '_' && len - digits_at <= 9) {
        size_t i;
        for (i = digits_at; i < len; ++i) value = value * 10 + (text[i] - '0');
        if (number) *number = (int32_t)value;
        end = digits_at - 1;
    }
    if (end >= name_cap) end = name_cap - 1;
    memcpy(name, text, end);
    name[end] = 0;
}

static exteria_status leave_operation(exteria_mt_client *c, exteria_status status) {
    --c->operation_depth;
    if (!c->operation_depth && c->closing) {
        c->closing = 0;
        exteria_mt_client_free(c);
        return EXTERIA_E_STATE;
    }
    return status;
}

exteria_status exteria_mt_client_connect(exteria_mt_client *c) {
    exteria_status status;
    if (!c || c->closing || c->operation_depth) return EXTERIA_E_STATE;
    ++c->operation_depth;
    status = client_connect(c);
    return leave_operation(c, status);
}

exteria_status exteria_mt_client_feed(exteria_mt_client *c, const uint8_t *data, size_t len) {
    exteria_status status;
    if (!c || c->closing || c->operation_depth) return EXTERIA_E_STATE;
    ++c->operation_depth;
    status = client_feed(c, data, len);
    return leave_operation(c, status);
}

exteria_status exteria_mt_client_submit(exteria_mt_client *c, uint64_t request_id, const exteria_tl_value *request,
                                        uint32_t timeout_ms) {
    exteria_status status;
    if (!c || c->closing) return EXTERIA_E_STATE;
    ++c->operation_depth;
    status = client_submit(c, request_id, request, timeout_ms);
    return leave_operation(c, status);
}

uint32_t exteria_mt_client_tick(exteria_mt_client *c) {
    uint32_t next;
    if (!c || c->closing || c->operation_depth) return UINT32_MAX;
    ++c->operation_depth;
    next = client_tick(c);
    if (leave_operation(c, EXTERIA_OK) != EXTERIA_OK) return UINT32_MAX;
    return next;
}
