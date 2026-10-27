#include "exteria_tgc_call.h"
#include "test_util.h"

#include <unistd.h>

/* two calls, one key, the reflector servers between them and the signaling channel, all in memory with a clock the
   test moves */

#define QUEUE 1024
#define MAX_RX 512

typedef struct item {
    int kind;               /* 0 datagram to a server, 1 datagram from a server to an agent, 2 signaling to an agent */
    int agent;
    unsigned reflector;
    uint64_t due;
    size_t len;
    uint8_t data[EXTERIA_TGC_SIGNAL_MAX + 64];
} item;

typedef struct client {
    uint32_t tag;
    int agent;
    unsigned reflector;
    int known;
} client;

typedef struct server {
    uint8_t id;
    uint8_t prefix[12];
    client clients[4];
    int dead;
} server;

typedef struct audio_rx {
    uint16_t seq;
    uint32_t ts;
    uint8_t id;
    size_t len;
} audio_rx;

typedef struct video_rx {
    size_t len;
    int key;
    uint32_t ts;
    uint32_t sum;
} video_rx;

typedef struct world {
    exteria_tgc_call *call[2];
    server servers[4];
    unsigned server_count;
    item *queue;
    size_t queued;
    uint64_t now;
    uint64_t latency;
    uint64_t signaling_latency;
    unsigned loss;
    unsigned rng;
    int realtime;
    int drop_big_from;      /* -1, or the agent whose next datagram over 400 bytes is lost */
    int states[2];
    int state_events[2][8];
    unsigned state_count[2];
    audio_rx audio[2][MAX_RX];
    unsigned audio_count[2];
    video_rx video[2][64];
    unsigned video_count[2];
    unsigned streams_events[2];
    int remote_muted[2];
    int remote_video[2];
    unsigned remote_media_events[2];
    unsigned key_requests[2];
    unsigned signals_sent[2];
    char trace[2][16384];
    size_t trace_len[2];
    unsigned long_lines;
} world;

typedef struct ctx {
    world *w;
    int agent;
} ctx;

static ctx ctxs[2];

static unsigned rnd(world *w) {
    w->rng = w->rng * 1103515245u + 12345u;
    return (w->rng >> 16) & 0x7FFF;
}

static void push(world *w, int kind, int agent, unsigned reflector, const uint8_t *data, size_t len, uint64_t latency) {
    item *it;
    if (w->queued >= QUEUE) return;
    it = &w->queue[w->queued++];
    it->kind = kind;
    it->agent = agent;
    it->reflector = reflector;
    it->due = w->now + latency;
    it->len = len;
    memcpy(it->data, data, len);
}

static void on_signaling(void *c, const uint8_t *data, size_t len) {
    ctx *x = (ctx *)c;
    ++x->w->signals_sent[x->agent];
    push(x->w, 2, 1 - x->agent, 0, data, len, x->w->signaling_latency);
}

static void on_datagram(void *c, unsigned index, const uint8_t *data, size_t len) {
    ctx *x = (ctx *)c;
    world *w = x->w;
    if (w->drop_big_from == x->agent && len > 400) {
        w->drop_big_from = -1;
        return;
    }
    if (w->loss && rnd(w) % 100 < w->loss) return;
    push(w, 0, x->agent, index, data, len, w->latency);
}

static void on_state(void *c, exteria_tgc_call_state state) {
    ctx *x = (ctx *)c;
    world *w = x->w;
    w->states[x->agent] = (int)state;
    if (w->state_count[x->agent] < 8) w->state_events[x->agent][w->state_count[x->agent]++] = (int)state;
}

static void on_streams(void *c) {
    ctx *x = (ctx *)c;
    ++x->w->streams_events[x->agent];
}

static void on_remote_media(void *c, int muted, int video_state, int rotation) {
    ctx *x = (ctx *)c;
    (void)rotation;
    x->w->remote_muted[x->agent] = muted;
    x->w->remote_video[x->agent] = video_state;
    ++x->w->remote_media_events[x->agent];
}

static void on_audio(void *c, const uint8_t *opus, size_t len, uint16_t seq, uint32_t ts) {
    ctx *x = (ctx *)c;
    world *w = x->w;
    unsigned k = w->audio_count[x->agent];
    if (k >= MAX_RX || len == 0) return;
    w->audio[x->agent][k].seq = seq;
    w->audio[x->agent][k].ts = ts;
    w->audio[x->agent][k].id = opus[0];
    w->audio[x->agent][k].len = len;
    ++w->audio_count[x->agent];
}

static uint32_t checksum(const uint8_t *d, size_t n) {
    uint32_t s = 17;
    size_t i;
    for (i = 0; i < n; ++i) s = s * 31 + d[i];
    return s;
}

static void on_video(void *c, const uint8_t *frame, size_t len, int key, uint32_t ts) {
    ctx *x = (ctx *)c;
    world *w = x->w;
    unsigned k = w->video_count[x->agent];
    if (k >= 64) return;
    w->video[x->agent][k].len = len;
    w->video[x->agent][k].key = key;
    w->video[x->agent][k].ts = ts;
    w->video[x->agent][k].sum = checksum(frame, len);
    ++w->video_count[x->agent];
}

static void on_key_request(void *c) {
    ctx *x = (ctx *)c;
    ++x->w->key_requests[x->agent];
}

static void on_trace(void *c, const char *line) {
    ctx *x = (ctx *)c;
    world *w = x->w;
    size_t n = strlen(line);
    if (n > 219) ++w->long_lines;
    if (w->trace_len[x->agent] + n + 2 < sizeof(w->trace[0])) {
        memcpy(w->trace[x->agent] + w->trace_len[x->agent], line, n);
        w->trace_len[x->agent] += n;
        w->trace[x->agent][w->trace_len[x->agent]++] = '\n';
        w->trace[x->agent][w->trace_len[x->agent]] = '\0';
    }
}

static void server_receive(world *w, server *s, const item *p) {
    unsigned i;
    uint32_t target, sender;
    client *c = NULL;
    if (s->dead || p->len < 16 || memcmp(p->data, s->prefix, 12) != 0) return;
    if (p->len >= 40 && p->data[16] == 0xFF && p->data[28] == 0xFE) {
        sender = (uint32_t)p->data[12] | (uint32_t)p->data[13] << 8 | (uint32_t)p->data[14] << 16 | (uint32_t)p->data[15] << 24;
        for (i = 0; i < 4 && s->clients[i].known; ++i) if (s->clients[i].tag == sender && s->clients[i].agent == p->agent) c = &s->clients[i];
        if (!c) {
            for (i = 0; i < 4 && s->clients[i].known; ++i) {}
            if (i == 4) return;
            c = &s->clients[i];
            c->known = 1;
            c->tag = sender;
            c->agent = p->agent;
            c->reflector = p->reflector;
        }
        push(w, 1, p->agent, p->reflector, p->data, 40, w->latency);
        return;
    }
    if (p->len < 24) return;
    target = (uint32_t)p->data[12] | (uint32_t)p->data[13] << 8 | (uint32_t)p->data[14] << 16 | (uint32_t)p->data[15] << 24;
    for (i = 0; i < 4 && s->clients[i].known; ++i) {
        if (s->clients[i].tag == target) {
            push(w, 1, s->clients[i].agent, s->clients[i].reflector, p->data, p->len, w->latency);
            return;
        }
    }
}

static void step(world *w, uint64_t ms) {
    uint64_t end = w->now + ms;
    while (w->now < end) {
        size_t i = 0;
        int a;
        w->now += 5;
        if (w->realtime) usleep(5000);
        while (i < w->queued) {
            item it;
            if (w->queue[i].due > w->now) {
                ++i;
                continue;
            }
            it = w->queue[i];
            memmove(&w->queue[i], &w->queue[i + 1], (w->queued - i - 1) * sizeof(item));
            --w->queued;
            if (it.kind == 0) {
                unsigned s;
                /* the server of the sender's reflector; the reflector index is the server index here */
                for (s = 0; s < w->server_count; ++s) if (s == it.reflector) server_receive(w, &w->servers[s], &it);
            } else if (it.kind == 1) {
                exteria_tgc_call_datagram(w->call[it.agent], it.reflector, it.data, it.len, w->now);
            } else {
                exteria_tgc_call_signaling(w->call[it.agent], it.data, it.len, w->now);
            }
            i = 0;
        }
        for (a = 0; a < 2; ++a) exteria_tgc_call_tick(w->call[a], w->now);
    }
}

static world *make_world(unsigned servers, int caller_video, unsigned dead_mask) {
    world *w = (world *)calloc(1, sizeof(*w));
    exteria_tgc_call_config cfg[2];
    exteria_tgc_call_events ev;
    uint8_t key[EXTERIA_TGC_KEY_LEN];
    unsigned s;
    int a, i;
    for (i = 0; i < EXTERIA_TGC_KEY_LEN; ++i) key[i] = (uint8_t)(i * 13 + 5);
    w->queue = (item *)calloc(QUEUE, sizeof(item));
    w->rng = 4242;
    w->latency = 15;
    w->signaling_latency = 40;
    w->server_count = servers;
    w->drop_big_from = -1;
    for (a = 0; a < 2; ++a) {
        memset(&cfg[a], 0, sizeof(cfg[a]));
        cfg[a].is_outgoing = a == 0;
        memcpy(cfg[a].key, key, sizeof(key));
        cfg[a].with_video = (caller_video & (1 << a)) != 0;
        cfg[a].reflector_count = servers;
    }
    for (s = 0; s < servers; ++s) {
        w->servers[s].id = (uint8_t)(s + 1);
        w->servers[s].dead = (dead_mask >> s) & 1;
        for (i = 0; i < 12; ++i) w->servers[s].prefix[i] = (uint8_t)(0x30 + s * 20 + i);
        for (a = 0; a < 2; ++a) {
            exteria_tgc_ice_reflector_config *r = &cfg[a].reflectors[s];
            r->server_id = (uint8_t)(s + 1);
            memcpy(r->peer_tag, w->servers[s].prefix, 12);
            r->port = 599;
            r->address[0] = 149;
            r->address[1] = 154;
            r->address[3] = (uint8_t)(s + 1);
        }
    }
    for (a = 0; a < 2; ++a) {
        ctxs[a].w = w;
        ctxs[a].agent = a;
        memset(&ev, 0, sizeof(ev));
        ev.context = &ctxs[a];
        ev.send_signaling = on_signaling;
        ev.send_datagram = on_datagram;
        ev.state = on_state;
        ev.streams = on_streams;
        ev.remote_media = on_remote_media;
        ev.audio = on_audio;
        ev.video = on_video;
        ev.key_frame_requested = on_key_request;
        ev.trace = on_trace;
        CHECK_EQ_INT(exteria_tgc_call_new(&w->call[a], &cfg[a], &ev), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tgc_call_start(w->call[0], 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_call_start(w->call[1], 0), EXTERIA_OK);
    return w;
}

static void free_world(world *w) {
    exteria_tgc_call_free(w->call[0]);
    exteria_tgc_call_free(w->call[1]);
    free(w->queue);
    free(w);
}

static void make_audio(uint8_t *frame, size_t len, uint8_t id) {
    size_t i;
    frame[0] = id;
    for (i = 1; i < len; ++i) frame[i] = (uint8_t)(id * 7u + i);
}

/* a frame that looks like VP8 to the depacketizer: the tag bit says key or inter, a key frame carries its start code */
static void make_frame(uint8_t *frame, size_t len, int key, uint8_t seed) {
    size_t i;
    for (i = 0; i < len; ++i) frame[i] = (uint8_t)(i * 29u + seed);
    frame[0] = (uint8_t)(key ? 0x10 : 0x11);
    if (key && len >= 10) {
        frame[3] = 0x9D;
        frame[4] = 0x01;
        frame[5] = 0x2A;
    }
}

static void audio_both_ways(void) {
    world *w = make_world(1, 0, 0);
    exteria_tgc_stream out[2], in[2];
    uint8_t frame[80];
    int i;
    unsigned k;
    step(w, 5000);
    CHECK_EQ_INT(w->states[0], EXTERIA_TGC_CALL_CONNECTED);
    CHECK_EQ_INT(w->states[1], EXTERIA_TGC_CALL_CONNECTED);
    CHECK_EQ_INT(w->state_count[0], 1);
    CHECK_EQ_INT(w->state_count[1], 1);
    /* the trace tells the story of the call in order, in short lines, and says nothing a log may not */
    CHECK(strstr(w->trace[0], "signal out InitialSetup") != NULL);
    CHECK(strstr(w->trace[0], "signal in InitialSetup") != NULL);
    CHECK(strstr(w->trace[0], "ice selected pair") != NULL);
    CHECK(strstr(w->trace[0], "dtls starts as client") != NULL);
    CHECK(strstr(w->trace[1], "dtls starts as server") != NULL);
    CHECK(strstr(w->trace[0], "dtls connected") != NULL);
    CHECK(strstr(w->trace[0], "data channel open") != NULL);
    CHECK(strstr(w->trace[0], "call state 0 -> 1") != NULL);
    CHECK(strstr(w->trace[0], "pwd") == NULL && strstr(w->trace[0], "password") == NULL);
    CHECK_EQ_INT(w->long_lines, 0);
    exteria_tgc_call_streams(w->call[0], out, in);
    CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_AUDIO].payload_type, EXTERIA_TGC_OPUS_PAYLOAD);
    CHECK_EQ_INT(in[EXTERIA_TGC_STREAM_AUDIO].payload_type, EXTERIA_TGC_OPUS_PAYLOAD + EXTERIA_TGC_CALLEE_PAYLOAD_SHIFT);
    CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    CHECK_EQ_INT(in[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    /* a call of 100 frames each way, 20 ms apart */
    for (i = 0; i < 100; ++i) {
        make_audio(frame, 40 + (size_t)(i % 30), (uint8_t)i);
        CHECK_EQ_INT(exteria_tgc_call_send_audio(w->call[0], frame, 40 + (size_t)(i % 30), 960, w->now), EXTERIA_OK);
        make_audio(frame, 50 + (size_t)(i % 20), (uint8_t)(200 + i % 50));
        CHECK_EQ_INT(exteria_tgc_call_send_audio(w->call[1], frame, 50 + (size_t)(i % 20), 960, w->now), EXTERIA_OK);
        step(w, 20);
    }
    step(w, 200);
    CHECK_EQ_INT(w->audio_count[1], 100);
    CHECK_EQ_INT(w->audio_count[0], 100);
    for (k = 0; k < w->audio_count[1]; ++k) {
        CHECK_EQ_INT(w->audio[1][k].id, k);
        CHECK_EQ_INT(w->audio[1][k].len, 40 + k % 30);
        if (k) {
            CHECK_EQ_INT((uint16_t)(w->audio[1][k].seq - w->audio[1][k - 1].seq), 1);
            CHECK(w->audio[1][k].ts - w->audio[1][k - 1].ts == 960);
        }
    }
    for (k = 0; k < w->audio_count[0]; ++k) CHECK_EQ_INT(w->audio[0][k].id, 200 + k % 50);
    /* the data channel is open: the mute of one side shows at the other */
    CHECK_EQ_INT(w->remote_media_events[0] > 0 && w->remote_media_events[1] > 0, 1);
    exteria_tgc_call_set_muted(w->call[0], 1, w->now);
    step(w, 300);
    CHECK_EQ_INT(w->remote_muted[1], 1);
    exteria_tgc_call_set_muted(w->call[0], 0, w->now);
    step(w, 300);
    CHECK_EQ_INT(w->remote_muted[1], 0);
    {
        int ice, dtls, sctp;
        unsigned in_n, out_n;
        exteria_tgc_call_diagnostics(w->call[0], &ice, &dtls, &sctp, &in_n, &out_n);
        CHECK_EQ_INT(ice, EXTERIA_TGC_ICE_CONNECTED);
        CHECK_EQ_INT(dtls, EXTERIA_DTLS_CONNECTED);
        CHECK_EQ_INT(sctp, EXTERIA_TGC_SCTP_ESTABLISHED);
        CHECK(in_n >= 4 && out_n >= 4);
    }
    free_world(w);
}

static void video_call_with_loss_and_key_request(void) {
    world *w = make_world(1, 1, 0);
    exteria_tgc_stream out[2], in[2];
    uint8_t frame[70000];
    static const size_t sizes[] = {800, 3500, 14000, 60000};
    unsigned i, got = 0;
    step(w, 5000);
    CHECK_EQ_INT(w->states[0], EXTERIA_TGC_CALL_CONNECTED);
    exteria_tgc_call_streams(w->call[0], out, in);
    CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_VIDEO].active, 1);
    CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_VIDEO].payload_type, EXTERIA_TGC_VP8_PAYLOAD);
    exteria_tgc_call_streams(w->call[1], out, in);
    CHECK_EQ_INT(in[EXTERIA_TGC_STREAM_VIDEO].active, 1);
    /* frames of several packets arrive whole, with their kind and clock, and the same bytes */
    for (i = 0; i < 4; ++i) {
        make_frame(frame, sizes[i], i == 0, (uint8_t)i);
        CHECK_EQ_INT(exteria_tgc_call_send_video(w->call[0], frame, sizes[i], 9000u * (i + 1), w->now), EXTERIA_OK);
        step(w, 66);
        CHECK_EQ_INT(w->video_count[1], i + 1);
        CHECK_EQ_INT(w->video[1][i].len, sizes[i]);
        CHECK_EQ_INT(w->video[1][i].key, i == 0);
        CHECK(w->video[1][i].ts == 9000u * (i + 1));
        CHECK(w->video[1][i].sum == checksum(frame, sizes[i]));
    }
    CHECK_EQ_INT(w->key_requests[0], 0);
    /* one packet of the next inter frame is lost: that frame is not delivered, the receiver asks for a key frame, and the sender is told */
    w->drop_big_from = 0;
    make_frame(frame, 9000, 0, 77);
    CHECK_EQ_INT(exteria_tgc_call_send_video(w->call[0], frame, 9000, 45000, w->now), EXTERIA_OK);
    step(w, 100);
    CHECK_EQ_INT(w->video_count[1], 4);
    CHECK(w->key_requests[0] >= 1);
    /* an inter frame meanwhile is held back; the key frame the sender makes on request restores the stream */
    make_frame(frame, 700, 0, 78);
    exteria_tgc_call_send_video(w->call[0], frame, 700, 54000, w->now);
    step(w, 100);
    CHECK_EQ_INT(w->video_count[1], 4);
    make_frame(frame, 4000, 1, 79);
    exteria_tgc_call_send_video(w->call[0], frame, 4000, 63000, w->now);
    step(w, 100);
    CHECK_EQ_INT(w->video_count[1], 5);
    CHECK_EQ_INT(w->video[1][4].key, 1);
    make_frame(frame, 900, 0, 80);
    exteria_tgc_call_send_video(w->call[0], frame, 900, 72000, w->now);
    step(w, 100);
    CHECK_EQ_INT(w->video_count[1], 6);
    /* the decoder of the receiver can also ask for one: the sender is told, once in a while and not more often */
    {
        unsigned before;
        /* the loss above asked a moment ago, so the limit is first let run out */
        step(w, 500);
        before = w->key_requests[0];
        CHECK_EQ_INT(exteria_tgc_call_request_key_frame(w->call[1], w->now), EXTERIA_OK);
        step(w, 100);
        CHECK_EQ_INT(w->key_requests[0], before + 1);
        CHECK_EQ_INT(exteria_tgc_call_request_key_frame(w->call[1], w->now), EXTERIA_OK);
        step(w, 100);
        CHECK_EQ_INT(w->key_requests[0], before + 1);
        step(w, 400);
        CHECK_EQ_INT(exteria_tgc_call_request_key_frame(w->call[1], w->now), EXTERIA_OK);
        step(w, 100);
        CHECK_EQ_INT(w->key_requests[0], before + 2);
        CHECK_EQ_INT(exteria_tgc_call_request_key_frame(w->call[0], w->now), EXTERIA_E_STATE);
        CHECK_EQ_INT(exteria_tgc_call_request_key_frame(NULL, w->now), EXTERIA_E_ARG);
    }
    (void)got;
    /* the camera off: the channel goes at both ends and nothing can be sent */
    exteria_tgc_call_set_video(w->call[0], 0, 0, w->now);
    step(w, 500);
    exteria_tgc_call_streams(w->call[1], out, in);
    CHECK_EQ_INT(in[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    CHECK_EQ_INT(exteria_tgc_call_send_video(w->call[0], frame, 900, 81000, w->now), EXTERIA_E_STATE);
    free_world(w);
}

static void video_both_sides_at_once(void) {
    world *w = make_world(1, 0, 0);
    exteria_tgc_stream out[2], in[2];
    uint8_t frame[1800];
    int side;
    step(w, 5000);
    exteria_tgc_call_set_video(w->call[0], 1, 0, w->now);
    exteria_tgc_call_set_video(w->call[1], 1, 0, w->now);
    step(w, 1000);
    for (side = 0; side < 2; ++side) {
        exteria_tgc_call_streams(w->call[side], out, in);
        CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_VIDEO].active, 1);
        CHECK_EQ_INT(in[EXTERIA_TGC_STREAM_VIDEO].active, 1);
        CHECK_EQ_INT(w->remote_video[side], EXTERIA_TGC_VIDEO_ACTIVE);
        make_frame(frame, sizeof(frame), 1, (uint8_t)side);
        CHECK_EQ_INT(exteria_tgc_call_send_video(w->call[side], frame, sizeof(frame), 3000, w->now), EXTERIA_OK);
    }
    step(w, 100);
    CHECK_EQ_INT(w->video_count[0], 1);
    CHECK_EQ_INT(w->video_count[1], 1);
    free_world(w);
}

static void video_from_call_start(void) {
    world *w = make_world(1, 3, 0);
    exteria_tgc_stream out[2], in[2];
    uint8_t frame[1800];
    int side;
    step(w, 5000);
    for (side = 0; side < 2; ++side) {
        exteria_tgc_call_streams(w->call[side], out, in);
        CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_VIDEO].active, 1);
        CHECK_EQ_INT(in[EXTERIA_TGC_STREAM_VIDEO].active, 1);
        CHECK_EQ_INT(w->remote_video[side], EXTERIA_TGC_VIDEO_ACTIVE);
        make_frame(frame, sizeof(frame), 1, (uint8_t)side);
        CHECK_EQ_INT(exteria_tgc_call_send_video(w->call[side], frame, sizeof(frame), 3000, w->now), EXTERIA_OK);
    }
    step(w, 100);
    CHECK_EQ_INT(w->video_count[0], 1);
    CHECK_EQ_INT(w->video_count[1], 1);
    free_world(w);
}

static void video_added_midcall(void) {
    world *w = make_world(1, 0, 0);
    exteria_tgc_stream out[2], in[2];
    uint8_t frame[2000];
    unsigned before;
    step(w, 5000);
    CHECK_EQ_INT(w->states[0], EXTERIA_TGC_CALL_CONNECTED);
    CHECK_EQ_INT(exteria_tgc_call_send_video(w->call[1], frame, 500, 1, w->now), EXTERIA_E_STATE);
    before = w->streams_events[0];
    /* the called side turns its camera on: a new offer, an answer, and frames flow from it to the caller */
    exteria_tgc_call_set_video(w->call[1], 1, 0, w->now);
    step(w, 1000);
    CHECK(w->streams_events[0] > before);
    exteria_tgc_call_streams(w->call[1], out, in);
    CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_VIDEO].active, 1);
    CHECK_EQ_INT(out[EXTERIA_TGC_STREAM_VIDEO].payload_type, EXTERIA_TGC_VP8_PAYLOAD + EXTERIA_TGC_CALLEE_PAYLOAD_SHIFT);
    exteria_tgc_call_streams(w->call[0], out, in);
    CHECK_EQ_INT(in[EXTERIA_TGC_STREAM_VIDEO].active, 1);
    CHECK_EQ_INT(w->remote_video[0], EXTERIA_TGC_VIDEO_ACTIVE);
    make_frame(frame, 1800, 1, 3);
    CHECK_EQ_INT(exteria_tgc_call_send_video(w->call[1], frame, 1800, 3000, w->now), EXTERIA_OK);
    step(w, 100);
    CHECK_EQ_INT(w->video_count[0], 1);
    CHECK_EQ_INT(w->video[0][0].len, 1800);
    CHECK(w->video[0][0].sum == checksum(frame, 1800));
    /* the audio went on all the while */
    CHECK_EQ_INT(w->states[0], EXTERIA_TGC_CALL_CONNECTED);
    free_world(w);
}

static void dead_reflector_and_loss(void) {
    /* the first server is dead, the second drops one packet in twelve; the call finds its way; DTLS resends on the
       real clock, so this runs in real time */
    world *w = make_world(2, 0, 1);
    uint8_t frame[60];
    int i;
    w->loss = 8;
    w->realtime = 1;
    step(w, 14000);
    CHECK_EQ_INT(w->states[0], EXTERIA_TGC_CALL_CONNECTED);
    CHECK_EQ_INT(w->states[1], EXTERIA_TGC_CALL_CONNECTED);
    w->loss = 0;
    w->realtime = 0;
    for (i = 0; i < 20; ++i) {
        make_audio(frame, 50, (uint8_t)i);
        exteria_tgc_call_send_audio(w->call[0], frame, 50, 960, w->now);
        step(w, 20);
    }
    step(w, 200);
    CHECK_EQ_INT(w->audio_count[1], 20);
    free_world(w);
}

static void signaling_is_authenticated(void) {
    world *w = make_world(1, 0, 0);
    uint8_t junk[200];
    uint8_t other_key[EXTERIA_TGC_KEY_LEN];
    exteria_tgc_cipher stranger;
    uint8_t sealed[EXTERIA_TGC_PACKET_MAX];
    size_t n = 0;
    unsigned before_states;
    int i;
    step(w, 5000);
    before_states = w->state_count[1];
    memset(junk, 0x5A, sizeof(junk));
    CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], junk, sizeof(junk), w->now), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], junk, 10, w->now), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], NULL, 10, w->now), EXTERIA_E_ARG);
    /* a message sealed with another key, even a well formed one, is refused */
    for (i = 0; i < EXTERIA_TGC_KEY_LEN; ++i) other_key[i] = (uint8_t)(i * 3 + 1);
    exteria_tgc_cipher_init(&stranger, other_key, 1);
    exteria_tgc_cipher_seal(&stranger, (const uint8_t *)"{\"@type\":\"MediaState\",\"muted\":true}", 35, sealed, sizeof(sealed), &n);
    CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], sealed, n, w->now), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(w->remote_muted[1], 0);
    CHECK_EQ_INT(w->state_count[1], before_states);
    /* a message the call itself sealed, and then replayed, is taken once */
    {
        exteria_tgc_cipher same;
        uint8_t key[EXTERIA_TGC_KEY_LEN];
        for (i = 0; i < EXTERIA_TGC_KEY_LEN; ++i) key[i] = (uint8_t)(i * 13 + 5);
        exteria_tgc_cipher_init(&same, key, 1);
        same.sent = 5000;
        exteria_tgc_cipher_seal(&same, (const uint8_t *)"{\"@type\":\"MediaState\",\"muted\":true}", 35, sealed, sizeof(sealed), &n);
        CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], sealed, n, w->now), EXTERIA_OK);
        CHECK_EQ_INT(w->remote_muted[1], 1);
        CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], sealed, n, w->now), EXTERIA_E_RETRY);
        /* well sealed but not JSON of a message, and a message of an unknown type */
        exteria_tgc_cipher_seal(&same, (const uint8_t *)"not json at all", 15, sealed, sizeof(sealed), &n);
        CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], sealed, n, w->now), EXTERIA_E_MALFORMED);
        exteria_tgc_cipher_seal(&same, (const uint8_t *)"{\"@type\":\"Nope\"}", 16, sealed, sizeof(sealed), &n);
        CHECK_EQ_INT(exteria_tgc_call_signaling(w->call[1], sealed, n, w->now), EXTERIA_E_UNSUPPORTED);
    }
    CHECK_EQ_INT(w->states[1], EXTERIA_TGC_CALL_CONNECTED);
    free_world(w);
}

static void arguments(void) {
    exteria_tgc_call *c = NULL;
    exteria_tgc_call_config cfg;
    exteria_tgc_call_events ev;
    memset(&cfg, 0, sizeof(cfg));
    memset(&ev, 0, sizeof(ev));
    CHECK_EQ_INT(exteria_tgc_call_new(&c, &cfg, &ev), EXTERIA_E_ARG);
    CHECK(c == NULL);
    cfg.reflector_count = 1;
    cfg.reflectors[0].server_id = 1;
    cfg.reflectors[0].port = 599;
    CHECK_EQ_INT(exteria_tgc_call_new(NULL, &cfg, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_call_new(&c, NULL, &ev), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_call_new(&c, &cfg, NULL), EXTERIA_E_ARG);
    cfg.reflector_count = EXTERIA_TGC_ICE_MAX_REFLECTORS + 1;
    CHECK_EQ_INT(exteria_tgc_call_new(&c, &cfg, &ev), EXTERIA_E_ARG);
    cfg.reflector_count = 1;
    CHECK_EQ_INT(exteria_tgc_call_new(&c, &cfg, &ev), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_call_get_state(c), EXTERIA_TGC_CALL_CONNECTING);
    CHECK_EQ_INT(exteria_tgc_call_send_audio(c, (const uint8_t *)"x", 1, 960, 0), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_tgc_call_start(c, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_call_start(c, 0), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_tgc_call_start(NULL, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_call_datagram(c, 0, NULL, 0, 0), EXTERIA_E_ARG);
    exteria_tgc_call_tick(NULL, 0);
    exteria_tgc_call_free(c);
    exteria_tgc_call_free(NULL);
    CHECK_EQ_INT(exteria_tgc_call_get_state(NULL), EXTERIA_TGC_CALL_FAILED);
}

int main(void) {
    audio_both_ways();
    video_call_with_loss_and_key_request();
    video_both_sides_at_once();
    video_from_call_start();
    video_added_midcall();
    signaling_is_authenticated();
    arguments();
    dead_reflector_and_loss();
    return test_finish("test_tgc_call");
}
