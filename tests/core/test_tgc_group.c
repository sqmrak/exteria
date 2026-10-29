#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_dtls.h"
#include "exteria_rtp.h"
#include "exteria_tgc_group.h"
#include "exteria_tgc_json.h"
#include "test_util.h"

#define QUEUE 256
#define SFU_PORT 5000
#define LOCALHOST 0x7f000001u

typedef struct packet {
    uint8_t data[1500];
    size_t len;
} packet;

typedef struct queue {
    packet items[QUEUE];
    size_t head, count;
} queue;

typedef struct heard {
    unsigned count;
    uint32_t ssrc;
    uint8_t opus[64];
    size_t len;
    uint16_t sequence;
    int level, voice;
} heard;

typedef struct sfu {
    exteria_tgc_ice ice;
    exteria_dtls *dtls;
    exteria_tgc_srtp send_srtp, recv_srtp;
    int srtp_ready, dtls_started;
    queue *out;
    uint8_t received[1500];
    size_t received_len;
    unsigned media_in;
} sfu;

typedef struct world {
    exteria_tgc_group *client;
    sfu server;
    queue to_server, to_client;
    heard audio;
    int states[8];
    int state_count;
    unsigned client_sent;
} world;

static void push(queue *q, const uint8_t *data, size_t len) {
    packet *p;
    CHECK(q->count < QUEUE && len <= sizeof(p->data));
    p = &q->items[(q->head + q->count++) % QUEUE];
    memcpy(p->data, data, len);
    p->len = len;
}

static int pop(queue *q, packet *out) {
    if (!q->count) return 0;
    *out = q->items[q->head];
    q->head = (q->head + 1) % QUEUE;
    --q->count;
    return 1;
}

static void client_send(void *context, unsigned index, const uint8_t *data, size_t len) {
    world *w = (world *)context;
    CHECK_EQ_INT(index, 0);
    ++w->client_sent;
    push(&w->to_server, data, len);
}

static void client_state(void *context, exteria_tgc_group_state state) {
    world *w = (world *)context;
    CHECK(w->state_count < 8);
    w->states[w->state_count++] = (int)state;
}

static void client_audio(void *context, uint32_t ssrc, const uint8_t *opus, size_t len, uint16_t sequence, uint32_t timestamp, int level, int voice) {
    world *w = (world *)context;
    (void)timestamp;
    ++w->audio.count;
    w->audio.ssrc = ssrc;
    w->audio.len = len < sizeof(w->audio.opus) ? len : sizeof(w->audio.opus);
    memcpy(w->audio.opus, opus, w->audio.len);
    w->audio.sequence = sequence;
    w->audio.level = level;
    w->audio.voice = voice;
}

static void sfu_send(void *context, unsigned index, const uint8_t *data, size_t len) {
    sfu *s = (sfu *)context;
    CHECK_EQ_INT(index, 0);
    push(s->out, data, len);
}

static void sfu_state(void *context, exteria_tgc_ice_state state) {
    (void)context;
    (void)state;
}

static void sfu_pump(sfu *s) {
    uint8_t buf[EXTERIA_DTLS_MAX_DATAGRAM];
    size_t n = 0;
    while (exteria_dtls_poll(s->dtls, buf, sizeof(buf), &n) == EXTERIA_OK) exteria_tgc_ice_send(&s->ice, buf, n);
    if (!s->srtp_ready && exteria_dtls_get_state(s->dtls) == EXTERIA_DTLS_CONNECTED) {
        uint8_t sk[16], ss[14], rk[16], rs[14];
        CHECK_EQ_INT(exteria_dtls_srtp_keys(s->dtls, sk, ss, rk, rs), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_srtp_init(&s->send_srtp, sk, ss), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_srtp_init(&s->recv_srtp, rk, rs), EXTERIA_OK);
        s->srtp_ready = 1;
    }
}

static void sfu_payload(void *context, const uint8_t *data, size_t len) {
    sfu *s = (sfu *)context;
    if (len && data[0] >= 20 && data[0] <= 63) {
        exteria_dtls_input(s->dtls, data, len);
        sfu_pump(s);
    } else if (len && data[0] >= 128 && data[0] <= 191 && s->srtp_ready) {
        uint8_t copy[1500];
        size_t n = 0;
        memcpy(copy, data, len);
        if (exteria_tgc_srtp_unprotect(&s->recv_srtp, copy, len, &n) == EXTERIA_OK) {
            memcpy(s->received, copy, n);
            s->received_len = n;
            ++s->media_in;
        }
    }
}

/* the transport the server answers with, and the credentials of the client read from its join payload */
static void make_world(world *w, exteria_tgc_group_transport *answer, uint32_t *client_ssrc) {
    exteria_tgc_group_events ev;
    exteria_tgc_ice_events ice_ev;
    char join[1024];
    size_t join_len = 0, text_len = 0;
    exteria_json_doc *doc = NULL;
    const exteria_json *root, *fp;
    char ufrag[64], pwd[128], fingerprint[96];
    int64_t signed_ssrc = 0;
    static const char server_ufrag[] = "sfuU";
    static const char server_pwd[] = "sfuPasswordOfTwentyFourCh";
    memset(w, 0, sizeof(*w));
    memset(&ev, 0, sizeof(ev));
    ev.context = w;
    ev.send_datagram = client_send;
    ev.state = client_state;
    ev.audio = client_audio;
    CHECK_EQ_INT(exteria_tgc_group_new(&w->client, &ev), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_group_join_payload(w->client, join, sizeof(join), &join_len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_json_parse(join, join_len, &doc), EXTERIA_OK);
    root = exteria_json_root(doc);
    snprintf(ufrag, sizeof(ufrag), "%s", exteria_json_string(exteria_json_get(root, "ufrag"), &text_len));
    snprintf(pwd, sizeof(pwd), "%s", exteria_json_string(exteria_json_get(root, "pwd"), &text_len));
    fp = exteria_json_first(exteria_json_get(root, "fingerprints"));
    snprintf(fingerprint, sizeof(fingerprint), "%s", exteria_json_string(exteria_json_get(fp, "fingerprint"), &text_len));
    CHECK(!strcmp(exteria_json_string(exteria_json_get(fp, "setup"), &text_len), "passive"));
    CHECK_EQ_INT(exteria_json_int(exteria_json_get(root, "ssrc"), &signed_ssrc), EXTERIA_OK);
    *client_ssrc = (uint32_t)signed_ssrc;
    CHECK_EQ_INT(*client_ssrc, exteria_tgc_group_ssrc(w->client));
    exteria_json_free(doc);

    w->server.out = &w->to_client;
    memset(&ice_ev, 0, sizeof(ice_ev));
    ice_ev.context = &w->server;
    ice_ev.send = sfu_send;
    ice_ev.state = sfu_state;
    ice_ev.payload = sfu_payload;
    CHECK_EQ_INT(exteria_tgc_ice_init_direct(&w->server.ice, 0, 7, server_ufrag, server_pwd, &ice_ev), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_ice_set_remote(&w->server.ice, ufrag, pwd), EXTERIA_OK);
    {
        unsigned index = 9;
        CHECK_EQ_INT(exteria_tgc_ice_add_direct(&w->server.ice, LOCALHOST, 6000, 1, &index), EXTERIA_OK);
        CHECK_EQ_INT(index, 0);
    }
    CHECK_EQ_INT(exteria_dtls_new(&w->server.dtls), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(w->server.dtls, "sha-256", fingerprint), EXTERIA_OK);

    memset(answer, 0, sizeof(*answer));
    snprintf(answer->ufrag, sizeof(answer->ufrag), "%s", server_ufrag);
    snprintf(answer->pwd, sizeof(answer->pwd), "%s", server_pwd);
    snprintf(answer->fingerprint, sizeof(answer->fingerprint), "%s", exteria_dtls_local_fingerprint(w->server.dtls));
    snprintf(answer->setup, sizeof(answer->setup), "active");
    answer->candidate_count = 2;
    /* an IPv6 candidate and a TCP one are skipped, the UDP IPv4 one is the endpoint */
    snprintf(answer->candidates[0].ip, sizeof(answer->candidates[0].ip), "2001:db8::1");
    snprintf(answer->candidates[0].protocol, sizeof(answer->candidates[0].protocol), "udp");
    answer->candidates[0].port = 443;
    snprintf(answer->candidates[1].ip, sizeof(answer->candidates[1].ip), "127.0.0.1");
    snprintf(answer->candidates[1].protocol, sizeof(answer->candidates[1].protocol), "udp");
    answer->candidates[1].port = SFU_PORT;
    answer->candidates[1].priority = 1;
    answer->audio_payload_type = 111;
    answer->audio_level_ext = 1;
}

static void step(world *w, uint64_t now) {
    packet p;
    exteria_tgc_group_tick(w->client, now);
    exteria_tgc_ice_tick(&w->server.ice, now);
    /* the server starts the handshake once its ICE path is up, as the real one does */
    if (!w->server.dtls_started && w->server.ice.state == EXTERIA_TGC_ICE_CONNECTED) {
        w->server.dtls_started = 1;
        CHECK_EQ_INT(exteria_dtls_start(w->server.dtls, 1), EXTERIA_OK);
        sfu_pump(&w->server);
    }
    if (w->server.dtls_started && exteria_dtls_get_state(w->server.dtls) == EXTERIA_DTLS_HANDSHAKING) {
        uint32_t ms = 0;
        if (exteria_dtls_timeout(w->server.dtls, &ms) == EXTERIA_OK && now % 1000 == 0) {
            exteria_dtls_on_timeout(w->server.dtls);
            sfu_pump(&w->server);
        }
    }
    while (pop(&w->to_server, &p)) CHECK_EQ_INT(exteria_tgc_ice_input(&w->server.ice, 0, p.data, p.len, now), EXTERIA_OK);
    while (pop(&w->to_client, &p)) exteria_tgc_group_datagram(w->client, 0, p.data, p.len, now);
}

static void finish(world *w) {
    exteria_tgc_group_free(w->client);
    exteria_dtls_free(w->server.dtls);
}

/* a plain Opus packet from a source of the call, with the audio level extension the server forwards */
static size_t source_packet(world *w, uint8_t *out, uint32_t ssrc, uint8_t payload_type, uint16_t sequence, int level, int voice, int with_level) {
    static const uint8_t opus[] = {0x78, 1, 2, 3, 4, 5};
    size_t n = 12, protected_len = 0;
    memset(out, 0, 64);
    out[0] = with_level ? 0x90 : 0x80;
    out[1] = payload_type;
    out[2] = (uint8_t)(sequence >> 8);
    out[3] = (uint8_t)sequence;
    out[7] = 1;
    out[8] = (uint8_t)(ssrc >> 24);
    out[9] = (uint8_t)(ssrc >> 16);
    out[10] = (uint8_t)(ssrc >> 8);
    out[11] = (uint8_t)ssrc;
    if (with_level) {
        out[12] = 0xBE;
        out[13] = 0xDE;
        out[15] = 1;
        /* a one-byte element of another id first, then the level, then padding */
        out[16] = 0x20;
        out[17] = 0x55;
        out[18] = 0x10;
        out[19] = (uint8_t)((voice ? 0x80 : 0) | level);
        n = 20;
    }
    memcpy(out + n, opus, sizeof(opus));
    CHECK_EQ_INT(exteria_tgc_srtp_protect(&w->server.send_srtp, out, n + sizeof(opus), 128, &protected_len), EXTERIA_OK);
    return protected_len;
}

static void call_connects_and_carries_audio(void) {
    world *w = (world *)calloc(1, sizeof(*w));
    exteria_tgc_group_transport answer;
    uint32_t client_ssrc = 0, ip = 0;
    uint16_t port = 0;
    uint64_t now;
    int step_no;
    uint8_t opus[] = {0x48, 9, 8, 7}, wire[256];
    exteria_rtp_header h;
    size_t n;
    CHECK(w != NULL);
    make_world(w, &answer, &client_ssrc);
    CHECK_EQ_INT(exteria_tgc_group_get_state(w->client), EXTERIA_TGC_GROUP_NEW);
    CHECK_EQ_INT(exteria_tgc_group_endpoint(w->client, 0, &ip, &port), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_tgc_group_send_audio(w->client, opus, sizeof(opus), 960, 30, 1), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_tgc_group_apply(w->client, &answer, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_group_apply(w->client, &answer, 0), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_tgc_group_endpoint(w->client, 0, &ip, &port), EXTERIA_OK);
    CHECK_EQ_INT(ip, LOCALHOST);
    CHECK_EQ_INT(port, SFU_PORT);
    CHECK_EQ_INT(exteria_tgc_group_endpoint(w->client, 1, &ip, &port), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_tgc_group_get_state(w->client), EXTERIA_TGC_GROUP_CONNECTING);
    for (step_no = 1; step_no < 600 && exteria_tgc_group_get_state(w->client) != EXTERIA_TGC_GROUP_CONNECTED; ++step_no) {
        now = (uint64_t)step_no * 50;
        step(w, now);
    }
    CHECK_EQ_INT(exteria_tgc_group_get_state(w->client), EXTERIA_TGC_GROUP_CONNECTED);
    CHECK_EQ_INT(w->states[0], EXTERIA_TGC_GROUP_CONNECTING);
    CHECK_EQ_INT(w->states[w->state_count - 1], EXTERIA_TGC_GROUP_CONNECTED);
    now = (uint64_t)step_no * 50;
    step(w, now);

    /* the microphone: the server decrypts the packet and finds the payload type, the ssrc, the level extension and the Opus bytes */
    CHECK_EQ_INT(exteria_tgc_group_send_audio(w->client, opus, sizeof(opus), 960, 30, 1), EXTERIA_OK);
    step(w, now + 20);
    CHECK_EQ_INT(w->server.media_in, 1);
    CHECK_EQ_INT(exteria_rtp_parse(w->server.received, w->server.received_len, &h), EXTERIA_OK);
    CHECK_EQ_INT(h.payload_type, 111);
    CHECK(h.ssrc == client_ssrc);
    CHECK_EQ_INT(h.payload_len, sizeof(opus));
    CHECK(memcmp(w->server.received + h.payload_offset, opus, sizeof(opus)) == 0);
    CHECK_EQ_INT(w->server.received[0] & 0x10, 0x10);
    CHECK_EQ_INT(w->server.received[12], 0xBE);
    CHECK_EQ_INT(w->server.received[16], 0x10);
    CHECK_EQ_INT(w->server.received[17], 0x80 | 30);
    CHECK_EQ_INT(w->server.received[18], 0x31);
    CHECK_EQ_INT(exteria_tgc_group_send_audio(w->client, opus, sizeof(opus), 960, 31, 0), EXTERIA_OK);
    step(w, now + 40);
    CHECK_EQ_INT(w->server.media_in, 2);
    CHECK_EQ_INT(w->server.received[17], 31);
    CHECK_EQ_INT(exteria_tgc_group_send_audio(w->client, opus, sizeof(opus), 960, 128, 0), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_group_send_audio(w->client, opus, 0, 960, 10, 0), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_group_send_audio(NULL, opus, sizeof(opus), 960, 10, 0), EXTERIA_E_ARG);

    /* a speaker of the call: the packet arrives with the ssrc, the sequence and the level of its sender */
    n = source_packet(w, wire, 4242, 111, 77, 40, 1, 1);
    push(&w->to_client, wire, n);
    step(w, now + 60);
    CHECK_EQ_INT(w->audio.count, 1);
    CHECK_EQ_INT(w->audio.ssrc, 4242);
    CHECK_EQ_INT(w->audio.sequence, 77);
    CHECK_EQ_INT(w->audio.level, 40);
    CHECK_EQ_INT(w->audio.voice, 1);
    CHECK_EQ_INT(w->audio.len, 6);
    CHECK_EQ_INT(w->audio.opus[0], 0x78);
    /* without the extension the level is unknown */
    n = source_packet(w, wire, 4243, 111, 5, 0, 0, 0);
    push(&w->to_client, wire, n);
    step(w, now + 80);
    CHECK_EQ_INT(w->audio.count, 2);
    CHECK_EQ_INT(w->audio.level, -1);
    CHECK_EQ_INT(w->audio.voice, 0);
    /* another payload type, the phone's own ssrc and a replay are not played */
    n = source_packet(w, wire, 4244, 100, 1, 10, 0, 1);
    push(&w->to_client, wire, n);
    n = source_packet(w, wire, client_ssrc, 111, 2, 10, 0, 1);
    push(&w->to_client, wire, n);
    n = source_packet(w, wire, 4242, 111, 77, 40, 1, 1);
    push(&w->to_client, wire, n);
    step(w, now + 100);
    CHECK_EQ_INT(w->audio.count, 2);

    /* many sources one after another: each one that left gives its place back, so the table never fills */
    {
        uint32_t ssrc;
        for (ssrc = 1000; ssrc < 1100; ++ssrc) {
            n = source_packet(w, wire, ssrc, 111, 1, 20, 0, 1);
            push(&w->to_client, wire, n);
            step(w, now + 120 + ssrc);
            exteria_tgc_group_forget(w->client, ssrc);
            exteria_tgc_srtp_forget(&w->server.send_srtp, ssrc);
        }
        CHECK_EQ_INT(w->audio.count, 102);
        CHECK_EQ_INT(w->audio.ssrc, 1099);
    }
    {
        int ice = -1, dtls = -1;
        unsigned in = 0, out = 0;
        exteria_tgc_group_diagnostics(w->client, &ice, &dtls, &in, &out);
        CHECK_EQ_INT(ice, EXTERIA_TGC_ICE_CONNECTED);
        CHECK_EQ_INT(dtls, EXTERIA_DTLS_CONNECTED);
        CHECK_EQ_INT(in, 102);
        CHECK_EQ_INT(out, 2);
    }
    finish(w);
    free(w);
}

static void bad_answers(void) {
    world *w = (world *)calloc(1, sizeof(*w));
    exteria_tgc_group_transport answer, broken;
    uint32_t client_ssrc = 0;
    CHECK(w != NULL);
    make_world(w, &answer, &client_ssrc);
    broken = answer;
    broken.candidate_count = 0;
    CHECK_EQ_INT(exteria_tgc_group_apply(w->client, &broken, 0), EXTERIA_E_UNSUPPORTED);
    broken = answer;
    snprintf(broken.candidates[1].protocol, sizeof(broken.candidates[1].protocol), "tcp");
    CHECK_EQ_INT(exteria_tgc_group_apply(w->client, &broken, 0), EXTERIA_E_UNSUPPORTED);
    broken = answer;
    snprintf(broken.fingerprint, sizeof(broken.fingerprint), "not a fingerprint");
    CHECK_EQ_INT(exteria_tgc_group_apply(w->client, &broken, 0), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_tgc_group_apply(NULL, &answer, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_group_apply(w->client, NULL, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_group_get_state(w->client), EXTERIA_TGC_GROUP_NEW);
    /* nothing arrives before an answer is applied */
    CHECK_EQ_INT(exteria_tgc_group_datagram(w->client, 0, (const uint8_t *)"x", 1, 0), EXTERIA_E_STATE);
    exteria_tgc_group_tick(w->client, 100000);
    CHECK_EQ_INT(exteria_tgc_group_get_state(w->client), EXTERIA_TGC_GROUP_NEW);
    finish(w);
    free(w);
}

static void silent_server_fails(void) {
    world *w = (world *)calloc(1, sizeof(*w));
    exteria_tgc_group_transport answer;
    uint32_t client_ssrc = 0;
    uint64_t now;
    CHECK(w != NULL);
    make_world(w, &answer, &client_ssrc);
    CHECK_EQ_INT(exteria_tgc_group_apply(w->client, &answer, 1000), EXTERIA_OK);
    /* the checks go out and nobody answers them */
    for (now = 1000; now < 1000 + EXTERIA_TGC_GROUP_CONNECT_TIMEOUT_MS + 2000; now += 50) exteria_tgc_group_tick(w->client, now);
    CHECK_EQ_INT(exteria_tgc_group_get_state(w->client), EXTERIA_TGC_GROUP_FAILED);
    CHECK_EQ_INT(w->states[w->state_count - 1], EXTERIA_TGC_GROUP_FAILED);
    CHECK(w->client_sent > 0);
    /* a failed connection stays failed and says so once */
    {
        int count = w->state_count;
        exteria_tgc_group_tick(w->client, now + 1000);
        CHECK_EQ_INT(w->state_count, count);
    }
    finish(w);
    free(w);
}

int main(void) {
    call_connects_and_carries_audio();
    bad_answers();
    silent_server_fails();
    exteria_tgc_group_forget(NULL, 1);
    CHECK_EQ_INT(exteria_tgc_group_ssrc(NULL), 0);
    CHECK_EQ_INT(exteria_tgc_group_get_state(NULL), EXTERIA_TGC_GROUP_FAILED);
    return test_finish("test_tgc_group");
}
