#include "exteria_blake2s.h"
#include "exteria_bytes.h"
#include "exteria_crypto.h"
#include "exteria_random.h"
#include "exteria_wg.h"
#include "shiro_responder.h"
#include "test_util.h"

#include <string.h>

typedef struct capture {
    uint8_t data[40][2048];
    size_t len[40];
    size_t count;
} capture;

static void emit_into(void *context, const uint8_t *data, size_t len) {
    capture *c = (capture *)context;
    if (c->count < 40 && len <= 2048) {
        memcpy(c->data[c->count], data, len);
        c->len[c->count] = len;
        ++c->count;
    }
}

static void keys(uint8_t *initiator_priv, uint8_t *responder_priv, uint8_t *responder_pub, uint8_t *initiator_pub) {
    exteria_random(initiator_priv, 32);
    exteria_random(responder_priv, 32);
    exteria_x25519_public(responder_priv, responder_pub);
    exteria_x25519_public(initiator_priv, initiator_pub);
}

static void base_config(exteria_wg_config *c, const uint8_t *priv, const uint8_t *peer_pub) {
    memset(c, 0, sizeof(*c));
    memcpy(c->private_key, priv, 32);
    memcpy(c->peer_public, peer_pub, 32);
}

static void plain_handshake_and_transport(void) {
    uint8_t ip[32], rp[32], rpub[32], ipub[32], reply[EXTERIA_WG_RESPONSE_LEN];
    exteria_wg_config cfg;
    exteria_wg_handshake hs;
    exteria_wg_session s;
    capture cap;
    responder r;
    memset(&cap, 0, sizeof(cap));
    keys(ip, rp, rpub, ipub);
    base_config(&cfg, ip, rpub);
    responder_init(&r, rp, ipub);
    CHECK_EQ_INT(exteria_wg_handshake_begin(&hs, &cfg, 1700000000, 123456789, emit_into, &cap), EXTERIA_OK);
    CHECK_EQ_INT(cap.count, 1);
    CHECK_EQ_INT(cap.len[0], EXTERIA_WG_INITIATION_LEN);
    CHECK_EQ_INT(responder_answer(&r, cap.data[0], reply, 1, 2), 0);
    CHECK_EQ_INT(r.seen_stamp_sec, 1700000000);
    CHECK_EQ_INT(r.seen_stamp_nanos, 123456789);
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, reply, sizeof(reply), 5000, &s), EXTERIA_OK);
    CHECK(s.active);
    CHECK_MEM(s.send_key, r.recv_key, 32);
    CHECK_MEM(s.recv_key, r.send_key, 32);
    CHECK_EQ_INT(s.remote_index, r.index);
    CHECK_EQ_INT(exteria_wg_session_age_ms(&s, 9000), 4000);
    CHECK_EQ_INT(exteria_wg_session_age_ms(&s, 1000), 0);

    /* initiator to responder: the data message carries the receiver's index and a counter, the plain text is padded to 16 */
    {
        uint8_t packet[60], out[EXTERIA_WG_MAX_DATAGRAM], back[EXTERIA_WG_MAX_DATAGRAM], nonce[12];
        size_t n = 0, m = 0;
        int i;
        for (i = 0; i < 60; ++i) packet[i] = (uint8_t)(i * 3);
        CHECK_EQ_INT(exteria_wg_seal(&s, packet, sizeof(packet), out, sizeof(out), &n), EXTERIA_OK);
        CHECK_EQ_INT(n, EXTERIA_WG_HEADER_LEN + 64 + EXTERIA_WG_TAG_LEN);
        CHECK_EQ_INT(exteria_get_u32le(out), 4);
        CHECK_EQ_INT(exteria_get_u32le(out + 4), r.index);
        CHECK_EQ_INT(exteria_get_u64le(out + 8), 0);
        memset(nonce, 0, 12);
        CHECK_EQ_INT(exteria_chacha20poly1305_open(r.recv_key, nonce, NULL, 0, out + 16, 64, back, out + 16 + 64), EXTERIA_OK);
        CHECK_MEM(back, packet, 60);
        for (i = 60; i < 64; ++i) CHECK_EQ_INT(back[i], 0);
        /* responder to initiator */
        {
            uint8_t msg[16 + 48 + 16], body[48], tag[16];
            uint8_t nonce2[12];
            memset(body, 0x5A, sizeof(body));
            memset(nonce2, 0, 12);
            nonce2[4] = 9;
            exteria_put_u32le(msg, 4);
            exteria_put_u32le(msg + 4, r.peer_index);
            exteria_put_u64le(msg + 8, 9);
            exteria_chacha20poly1305_seal(r.send_key, nonce2, NULL, 0, body, 48, msg + 16, tag);
            memcpy(msg + 64, tag, 16);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_OK);
            CHECK_EQ_INT(m, 48);
            CHECK_MEM(back, body, 48);
            /* the same datagram again is a replay */
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_E_RETRY);
            /* a counter below the highest but unseen is still welcome */
            exteria_put_u64le(msg + 8, 3);
            memset(nonce2, 0, 12);
            nonce2[4] = 3;
            exteria_chacha20poly1305_seal(r.send_key, nonce2, NULL, 0, body, 48, msg + 16, tag);
            memcpy(msg + 64, tag, 16);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_OK);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_E_RETRY);
            /* a forged counter far ahead does not authenticate and must not move the window */
            exteria_put_u64le(msg + 8, 100000);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_E_SECURITY);
            exteria_put_u64le(msg + 8, 11);
            memset(nonce2, 0, 12);
            nonce2[4] = 11;
            exteria_chacha20poly1305_seal(r.send_key, nonce2, NULL, 0, body, 48, msg + 16, tag);
            memcpy(msg + 64, tag, 16);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_OK);
            /* a counter more than a window behind is too old even if never seen */
            exteria_put_u64le(msg + 8, 11 + 300);
            memset(nonce2, 0, 12);
            exteria_put_u64le(nonce2 + 4, 311);
            exteria_chacha20poly1305_seal(r.send_key, nonce2, NULL, 0, body, 48, msg + 16, tag);
            memcpy(msg + 64, tag, 16);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_OK);
            exteria_put_u64le(msg + 8, 5);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), back, sizeof(back), &m), EXTERIA_E_RETRY);
        }
        /* a keepalive is an empty plain text */
        CHECK_EQ_INT(exteria_wg_seal(&s, NULL, 0, out, sizeof(out), &n), EXTERIA_OK);
        CHECK_EQ_INT(n, EXTERIA_WG_HEADER_LEN + EXTERIA_WG_TAG_LEN);
        CHECK_EQ_INT(exteria_get_u64le(out + 8), 1);
    }
    exteria_wg_session_clear(&s);
    CHECK_EQ_INT(s.active, 0);
}

static void tampered_and_foreign_datagrams(void) {
    uint8_t ip[32], rp[32], rpub[32], ipub[32], reply[EXTERIA_WG_RESPONSE_LEN], bad[EXTERIA_WG_RESPONSE_LEN];
    exteria_wg_config cfg;
    exteria_wg_handshake hs;
    exteria_wg_session s;
    capture cap;
    responder r;
    size_t i;
    memset(&cap, 0, sizeof(cap));
    keys(ip, rp, rpub, ipub);
    base_config(&cfg, ip, rpub);
    responder_init(&r, rp, ipub);
    CHECK_EQ_INT(exteria_wg_handshake_begin(&hs, &cfg, 1, 0, emit_into, &cap), EXTERIA_OK);
    CHECK_EQ_INT(responder_answer(&r, cap.data[0], reply, 1, 2), 0);
    /* wrong length, wrong type and a receiver index that is not ours are not answers; the handshake stays open for the real one */
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, reply, 91, 0, &s), EXTERIA_E_MALFORMED);
    memcpy(bad, reply, sizeof(bad));
    bad[0] = 4;
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, bad, sizeof(bad), 0, &s), EXTERIA_E_MALFORMED);
    memcpy(bad, reply, sizeof(bad));
    bad[8] ^= 1;
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, bad, sizeof(bad), 0, &s), EXTERIA_E_MALFORMED);
    CHECK(hs.pending);
    /* every single flipped bit of the authenticated part fails authentication and ends the attempt */
    for (i = 12; i < EXTERIA_WG_RESPONSE_LEN - 32; i += 5) {
        exteria_wg_handshake copy = hs;
        memcpy(bad, reply, sizeof(bad));
        bad[i] ^= 0x04;
        CHECK_EQ_INT(exteria_wg_handshake_finish(&copy, bad, sizeof(bad), 0, &s), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(copy.pending, 0);
        CHECK_EQ_INT(exteria_wg_handshake_finish(&copy, reply, sizeof(reply), 0, &s), EXTERIA_E_STATE);
    }
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, reply, sizeof(reply), 0, &s), EXTERIA_OK);
    /* a data message for another index, or from a wrong key, is refused */
    {
        uint8_t msg[48], out[EXTERIA_WG_MAX_DATAGRAM];
        size_t n = 0;
        memset(msg, 0, sizeof(msg));
        exteria_put_u32le(msg, 4);
        exteria_put_u32le(msg + 4, s.local_index + 1);
        CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), out, sizeof(out), &n), EXTERIA_E_MALFORMED);
        exteria_put_u32le(msg + 4, s.local_index);
        CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), out, sizeof(out), &n), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(exteria_wg_open(&s, msg, 20, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(exteria_wg_open(&s, msg, 2000, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    }
    /* a peer whose key is a point of small order cannot be talked to */
    {
        exteria_wg_config bad_cfg = cfg;
        uint8_t one[32] = {1};
        memcpy(bad_cfg.peer_public, one, 32);
        capture none;
        memset(&none, 0, sizeof(none));
        CHECK_EQ_INT(exteria_wg_handshake_begin(&hs, &bad_cfg, 1, 0, emit_into, &none), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(none.count, 0);
    }
}

static void amnezia_framing(void) {
    uint8_t ip[32], rp[32], rpub[32], ipub[32], reply[EXTERIA_WG_RESPONSE_LEN + 40];
    exteria_wg_config cfg;
    exteria_wg_handshake hs;
    exteria_wg_session s;
    capture cap;
    responder r;
    size_t i;
    memset(&cap, 0, sizeof(cap));
    keys(ip, rp, rpub, ipub);
    base_config(&cfg, ip, rpub);
    cfg.junk_count = 4;
    cfg.junk_min = 40;
    cfg.junk_max = 70;
    cfg.s1 = 17;
    cfg.s2 = 24;
    cfg.h1 = 0x1234;
    cfg.h2 = 0x2345;
    cfg.h4 = 0x4567;
    cfg.reserved[0] = 0xAB;
    cfg.reserved[1] = 0xCD;
    cfg.reserved[2] = 0xEF;
    cfg.has_reserved = 1;
    cfg.signature[0] = "<b 0x474554202f20485454502f312e31><r 4><t>";
    cfg.signature[1] = "<b 0xdeadbeef>";
    responder_init(&r, rp, ipub);
    CHECK_EQ_INT(exteria_wg_handshake_begin(&hs, &cfg, 1700000001, 5, emit_into, &cap), EXTERIA_OK);
    /* two signatures, four junk datagrams, then the initiation behind its random prefix */
    CHECK_EQ_INT(cap.count, 2 + 4 + 1);
    CHECK_EQ_INT(cap.len[0], 14 + 4 + 4);
    CHECK_MEM(cap.data[0], "GET / HTTP/1.1", 14);
    CHECK_EQ_INT(exteria_get_u32le(cap.data[0] + 18), 1700000001);
    CHECK_EQ_INT(cap.len[1], 4);
    CHECK_EQ_INT(cap.data[1][0], 0xde);
    for (i = 2; i < 6; ++i) CHECK(cap.len[i] >= 40 && cap.len[i] <= 70);
    CHECK_EQ_INT(cap.len[6], 17 + EXTERIA_WG_INITIATION_LEN);
    /* the type is the configured one and the reserved bytes sit where the type's upper bytes were */
    CHECK_EQ_INT(cap.data[6][17], 0x34);
    CHECK_EQ_INT(cap.data[6][18], 0xAB);
    CHECK_EQ_INT(cap.data[6][19], 0xCD);
    CHECK_EQ_INT(cap.data[6][20], 0xEF);
    CHECK_EQ_INT(responder_answer(&r, cap.data[6] + 17, reply + 24, 0x1234, 0x2345), 0);
    for (i = 0; i < 24; ++i) reply[i] = (uint8_t)(0x90 + i);
    /* the response arrives behind s2 random bytes, with its type in the configured form (a type above 255 has to match whole, reserved bytes or not) */
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, reply, 24 + EXTERIA_WG_RESPONSE_LEN, 1, &s), EXTERIA_OK);
    {
        uint8_t out[EXTERIA_WG_MAX_DATAGRAM], packet[20] = {1, 2, 3};
        size_t n = 0;
        CHECK_EQ_INT(exteria_wg_seal(&s, packet, sizeof(packet), out, sizeof(out), &n), EXTERIA_OK);
        CHECK_EQ_INT(out[0], 0x67);
        CHECK_EQ_INT(out[1], 0xAB);
        CHECK_EQ_INT(out[2], 0xCD);
        CHECK_EQ_INT(out[3], 0xEF);
        CHECK_EQ_INT(n, 16 + 32 + 16);
        /* the peer's data messages may carry other bytes in the reserved place */
        {
            uint8_t msg[16 + 16], tag[16], nonce[12] = {0}, empty[1];
            exteria_put_u32le(msg, 0x4567);
            msg[1] = 0x11;
            msg[2] = 0x22;
            msg[3] = 0x33;
            exteria_put_u32le(msg + 4, s.local_index);
            exteria_put_u64le(msg + 8, 0);
            exteria_chacha20poly1305_seal(r.send_key, nonce, NULL, 0, empty, 0, empty, tag);
            memcpy(msg + 16, tag, 16);
            /* type 0x4567 has its upper byte in the reserved place and expected >= 256, so only an exact match is taken */
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), out, sizeof(out), &n), EXTERIA_E_MALFORMED);
            exteria_put_u32le(msg, 0x4567);
            CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), out, sizeof(out), &n), EXTERIA_OK);
            CHECK_EQ_INT(n, 0);
        }
    }
}

static void standard_types_with_reserved_bytes(void) {
    uint8_t ip[32], rp[32], rpub[32], ipub[32], reply[EXTERIA_WG_RESPONSE_LEN];
    exteria_wg_config cfg;
    exteria_wg_handshake hs;
    exteria_wg_session s;
    capture cap;
    responder r;
    memset(&cap, 0, sizeof(cap));
    keys(ip, rp, rpub, ipub);
    base_config(&cfg, ip, rpub);
    cfg.reserved[0] = 1;
    cfg.reserved[1] = 2;
    cfg.reserved[2] = 3;
    cfg.has_reserved = 1;
    responder_init(&r, rp, ipub);
    CHECK_EQ_INT(exteria_wg_handshake_begin(&hs, &cfg, 9, 9, emit_into, &cap), EXTERIA_OK);
    CHECK_EQ_INT(cap.data[0][0], 1);
    CHECK_EQ_INT(cap.data[0][1], 1);
    CHECK_EQ_INT(cap.data[0][3], 3);
    CHECK_EQ_INT(responder_answer(&r, cap.data[0], reply, 1, 2), 0);
    /* WARP answers with its own bytes in the reserved place */
    reply[1] = 0x77;
    reply[2] = 0x88;
    reply[3] = 0x99;
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, reply, sizeof(reply), 0, &s), EXTERIA_OK);
    {
        uint8_t msg[32], tag[16], nonce[12] = {0}, empty[1], out[EXTERIA_WG_MAX_DATAGRAM];
        size_t n = 0;
        exteria_put_u32le(msg, 4);
        msg[1] = 0x55;
        exteria_put_u32le(msg + 4, s.local_index);
        exteria_put_u64le(msg + 8, 0);
        exteria_chacha20poly1305_seal(r.send_key, nonce, NULL, 0, empty, 0, empty, tag);
        memcpy(msg + 16, tag, 16);
        CHECK_EQ_INT(exteria_wg_open(&s, msg, sizeof(msg), out, sizeof(out), &n), EXTERIA_OK);
    }
}

static void signature_rendering(void) {
    uint8_t out[64];
    size_t n = 0;
    CHECK_EQ_INT(exteria_wg_signature_render("<b 0x0102>", 0, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 2);
    CHECK_EQ_INT(exteria_wg_signature_render("<b 0x01><c><t><r 3>", 0x01020304, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 1 + 4 + 4 + 3);
    CHECK_EQ_INT(exteria_get_u32le(out + 1), 1);
    CHECK_EQ_INT(exteria_get_u32le(out + 5), 0x01020304);
    CHECK_EQ_INT(exteria_wg_signature_render("  <B 0xAA> <b 0xbb>  ", 0, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 2);
    CHECK_EQ_INT(exteria_wg_signature_render("", 0, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_wg_signature_render("<x 5>", 0, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_wg_signature_render("<b 0x1>", 0, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_wg_signature_render("<b 0x0102", 0, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_wg_signature_render("<r 0>", 0, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_wg_signature_render("<r 2000>", 0, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_wg_signature_render("<r 100>", 0, out, 50, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_wg_signature_render("<b 0x01020304>", 0, out, 3, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_wg_signature_render("<t>", 0, out, 3, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_wg_signature_render(NULL, 0, out, sizeof(out), &n), EXTERIA_E_ARG);
}

static void config_limits_and_states(void) {
    uint8_t ip[32], rp[32], rpub[32], ipub[32];
    exteria_wg_config cfg;
    exteria_wg_handshake hs;
    exteria_wg_session s;
    capture cap;
    uint8_t out[EXTERIA_WG_MAX_DATAGRAM], big[EXTERIA_WG_MAX_PLAIN + 1];
    size_t n = 0;
    memset(&cap, 0, sizeof(cap));
    memset(&s, 0, sizeof(s));
    memset(big, 0, sizeof(big));
    keys(ip, rp, rpub, ipub);
    base_config(&cfg, ip, rpub);
    CHECK_EQ_INT(exteria_wg_config_check(&cfg), EXTERIA_OK);
    cfg.junk_count = 33;
    CHECK_EQ_INT(exteria_wg_config_check(&cfg), EXTERIA_E_ARG);
    cfg.junk_count = 2;
    cfg.junk_min = 50;
    cfg.junk_max = 40;
    CHECK_EQ_INT(exteria_wg_config_check(&cfg), EXTERIA_E_ARG);
    cfg.junk_max = 1401;
    CHECK_EQ_INT(exteria_wg_config_check(&cfg), EXTERIA_E_ARG);
    cfg.junk_count = 0;
    cfg.junk_min = cfg.junk_max = 0;
    cfg.s1 = 1025;
    CHECK_EQ_INT(exteria_wg_config_check(&cfg), EXTERIA_E_ARG);
    cfg.s1 = 0;
    memset(cfg.private_key, 0, 32);
    CHECK_EQ_INT(exteria_wg_config_check(&cfg), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_wg_handshake_begin(&hs, &cfg, 1, 1, emit_into, &cap), EXTERIA_E_ARG);
    CHECK_EQ_INT(cap.count, 0);
    CHECK_EQ_INT(exteria_wg_config_check(NULL), EXTERIA_E_ARG);
    /* an inactive session neither seals nor opens */
    CHECK_EQ_INT(exteria_wg_seal(&s, big, 10, out, sizeof(out), &n), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_wg_open(&s, out, 64, out, sizeof(out), &n), EXTERIA_E_STATE);
    s.active = 1;
    CHECK_EQ_INT(exteria_wg_seal(&s, big, sizeof(big), out, sizeof(out), &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_wg_seal(&s, big, 100, out, 100, &n), EXTERIA_E_LIMIT);
    s.send_counter = (uint64_t)1 << 60;
    CHECK_EQ_INT(exteria_wg_seal(&s, big, 10, out, sizeof(out), &n), EXTERIA_E_STATE);
    /* handshake finish with nothing pending */
    memset(&hs, 0, sizeof(hs));
    CHECK_EQ_INT(exteria_wg_handshake_finish(&hs, out, EXTERIA_WG_RESPONSE_LEN, 0, &s), EXTERIA_E_STATE);
}

static void replay_window_edges(void) {
    exteria_wg_session s;
    uint8_t key[32], msg[32 + 16], plain[64], nonce[12], tag[16], empty[1];
    uint64_t counters[] = {0, 1, 255, 256, 300, 44, 45, 301, 1000, 744, 745, 999, 1255, 1256, 1000};
    int expect[] = {1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 0};
    size_t i, n = 0;
    memset(&s, 0, sizeof(s));
    memset(key, 0x42, sizeof(key));
    memcpy(s.recv_key, key, 32);
    s.active = 1;
    s.local_index = 7;
    s.data_type = 4;
    for (i = 0; i < sizeof(counters) / sizeof(counters[0]); ++i) {
        memset(msg, 0, sizeof(msg));
        exteria_put_u32le(msg, 4);
        exteria_put_u32le(msg + 4, 7);
        exteria_put_u64le(msg + 8, counters[i]);
        memset(nonce, 0, 12);
        exteria_put_u64le(nonce + 4, counters[i]);
        exteria_chacha20poly1305_seal(key, nonce, NULL, 0, empty, 0, empty, tag);
        memcpy(msg + 16, tag, 16);
        /* 44 lies more than 256 behind 301 and counts as too old; 744 and 745 are inside the window of 1000 and so on, as the table says */
        n = 0;
        {
            exteria_status st = exteria_wg_open(&s, msg, 32, plain, sizeof(plain), &n);
            if (expect[i]) CHECK_EQ_INT(st, EXTERIA_OK);
            else CHECK_EQ_INT(st, EXTERIA_E_RETRY);
        }
    }
}

int main(void) {
    plain_handshake_and_transport();
    tampered_and_foreign_datagrams();
    amnezia_framing();
    standard_types_with_reserved_bytes();
    signature_rendering();
    config_limits_and_states();
    replay_window_edges();
    return test_finish("test_shiro_wg");
}
