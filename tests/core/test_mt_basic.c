#include "test_util.h"

#include "exteria_crypto.h"
#include "exteria_mt_handshake.h"
#include "exteria_mt_keys.h"
#include "exteria_mt_msg.h"
#include "exteria_mt_transport.h"
#include "exteria_random.h"

#define GOLDEN_KEY "0104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9acafb2b5b8bbbec1c4c7cacdd0d3d6d9dcdfe2e5e8ebeef1f4f7fafd000306090c0f1215181b1e2124272a2d303336393c3f4245484b4e5154575a5d606366696c6f7275787b7e8184878a8d909396999c9fa2a5a8abaeb1b4b7babdc0c3c6c9cccfd2d5d8dbdee1e4e7eaedf0f3f6f9fcff0205080b0e1114171a1d202326292c2f3235383b3e4144474a4d505356595c5f6265686b6e7174777a7d808386898c8f9295989b9ea1a4a7aaadb0b3b6b9bcbfc2c5c8cbced1d4d7dadde0e3e6e9eceff2f5f8fbfe"
#define GOLDEN_BODY "090e13181d22272c31363b40454a4f54595e63686d72777c81868b90959a9fa4a9aeb3b8bdc2c7cc"
#define GOLDEN_CLIENT_PACKET "c04b048704bb081f0a628bb298ea2410165fc0dc54a852233759ceef270f0613add327416e9bcfbcf409b8b5f7c985a1c3055a34f50ec058db6b9cb9585f74daf5919da3e3cbaa141d2a4549186c04db9f84ee5fbd12e685f014ba970543009e8f637513ad2b69d78356abd8d4e6c2cfe8ca2fc144817ac9"
#define GOLDEN_SERVER_PACKET "c04b048704bb081ff32d66c60fd6263a48e82275358bf49ba786699f9215a489be48e40fc71968423568df18d69cffca7534815153b978c28c59b79b0c5f86a2eb5b2fafb9ce943a97612391b886df34f3102c4b7c003b991948f2400d159f1096724d1d87f79ca87c21d7af2151e8daa5cfdaf88f87b735"

static void test_keys(void) {
    size_t count = 0, i;
    const exteria_mt_rsa_key *keys = exteria_mt_default_keys(0, &count);
    uint64_t fp;
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_mt_rsa_fingerprint(keys[0].n, keys[0].n_len, keys[0].e, &fp), EXTERIA_OK);
    CHECK(fp == 0xd09d1d85de64fd85ull);
    CHECK(keys[0].fingerprint == fp);
    keys = exteria_mt_default_keys(1, &count);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_mt_rsa_fingerprint(keys[0].n, keys[0].n_len, keys[0].e, &fp), EXTERIA_OK);
    CHECK(fp == 0xb25898df208d2603ull);
    CHECK(keys[0].fingerprint == fp);
    CHECK(exteria_mt_find_key(keys, count, fp) == &keys[0]);
    CHECK(exteria_mt_find_key(keys, count, 1) == NULL);
    for (i = 0; i < keys[0].n_len; ++i) if (keys[0].n[i]) break;
    CHECK(keys[0].n[0] & 0x80);
    CHECK_EQ_INT(exteria_mt_rsa_fingerprint(NULL, 0, 65537, &fp), EXTERIA_E_ARG);
}

static void test_factor(void) {
    static const struct { uint64_t pq; uint32_t p, q; } cases[] = {
        { 1724114033281923457ull, 1229739323u, 1402015859u },
        { 15, 3, 5 },
        { 6, 2, 3 },
        { 3233, 53, 61 },
        { 1000000007ull * 998244353ull, 998244353u, 1000000007u },
        { 4294967291ull * 4294967279ull, 4294967279u, 4294967291u },
        { 2147483647ull * 2147483629ull, 2147483629u, 2147483647u },
    };
    unsigned i;
    uint32_t p = 7, q = 7;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        CHECK_EQ_INT(exteria_mt_factor_pq(cases[i].pq, &p, &q), EXTERIA_OK);
        CHECK_EQ_INT(p, cases[i].p);
        CHECK_EQ_INT(q, cases[i].q);
    }
    /* a prime would keep the search running to its budget */
    CHECK_EQ_INT(exteria_mt_factor_pq(2147483647ull, &p, &q), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(p, 0);
    CHECK_EQ_INT(exteria_mt_factor_pq(5, &p, &q), EXTERIA_E_ARG);
    /* a factor above 32 bits cannot be sent back in the protocol */
    CHECK(exteria_mt_factor_pq(4294967311ull * 3ull, &p, &q) != EXTERIA_OK);
}

static void test_dh_checks(void) {
    uint8_t prime[256];
    exteria_bn *bn;
    uint8_t value[256];
    const exteria_mt_rsa_key *keys;
    size_t count;
    memset(prime, 0xff, sizeof(prime));
    CHECK_EQ_INT(exteria_mt_check_dh_prime(prime, 256, 3), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_mt_check_dh_prime(prime, 255, 3), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_mt_check_dh_prime(prime, 256, 1), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_mt_check_dh_prime(prime, 256, 8), EXTERIA_E_SECURITY);
    /* the key moduli are composite, so they must never pass as a dh prime */
    keys = exteria_mt_default_keys(0, &count);
    CHECK_EQ_INT(exteria_mt_check_dh_prime(keys[0].n, 256, 3), EXTERIA_E_SECURITY);
    memset(value, 0, sizeof(value));
    value[0] = 0x80;
    CHECK_EQ_INT(exteria_mt_check_dh_value(keys[0].n, 256, value, 256), EXTERIA_OK);
    value[0] = 0x00;
    value[8] = 0x01;
    CHECK_EQ_INT(exteria_mt_check_dh_value(keys[0].n, 256, value, 256), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_mt_check_dh_value(keys[0].n, 256, keys[0].n, 256), EXTERIA_E_SECURITY);
    bn = exteria_bn_from_u64(1);
    CHECK(bn != NULL);
    exteria_bn_free(bn);
}

static void test_msg_golden(void) {
    uint8_t key[256], body[64], packet[256];
    exteria_mt_auth_key k;
    exteria_writer plain;
    exteria_mt_header h;
    const uint8_t *got;
    size_t got_len;
    long klen = test_hex(GOLDEN_KEY, key, sizeof(key));
    long blen = test_hex(GOLDEN_BODY, body, sizeof(body));
    long plen;
    CHECK_EQ_INT(klen, 256);
    CHECK_EQ_INT(exteria_mt_auth_key_set(&k, key), EXTERIA_OK);
    exteria_writer_init(&plain, 4096);
    plen = test_hex(GOLDEN_CLIENT_PACKET, packet, sizeof(packet));
    CHECK_EQ_INT(plen, 120);
    CHECK_EQ_INT(exteria_mt_decrypt(&k, 1, 0, packet, (size_t)plen, &plain, &h, &got, &got_len), EXTERIA_OK);
    CHECK(h.salt == 0x1122334455667788ull);
    CHECK(h.session_id == 0x0102030405060708ull);
    CHECK(h.msg_id == 0x5f5e100000000004ull);
    CHECK_EQ_INT(h.seq_no, 3);
    CHECK_EQ_INT(got_len, blen);
    CHECK_MEM(got, body, (size_t)blen);
    /* the two directions use different halves of the key, so a packet cannot be replayed backwards */
    plain.len = 0;
    CHECK_EQ_INT(exteria_mt_decrypt(&k, 0, 0, packet, (size_t)plen, &plain, &h, &got, &got_len), EXTERIA_E_SECURITY);
    plen = test_hex(GOLDEN_SERVER_PACKET, packet, sizeof(packet));
    plain.len = 0;
    CHECK_EQ_INT(exteria_mt_decrypt(&k, 0, 0, packet, (size_t)plen, &plain, &h, &got, &got_len), EXTERIA_OK);
    CHECK_EQ_INT(got_len, blen);
    CHECK_MEM(got, body, (size_t)blen);
    exteria_writer_free(&plain);
}

static void test_msg_roundtrip(void) {
    uint8_t key[256], body[1000];
    exteria_mt_auth_key k, other;
    exteria_writer enc, plain;
    exteria_mt_header h, back;
    const uint8_t *got;
    size_t got_len, i, lens[] = { 4, 8, 12, 20, 36, 40, 100, 1000 }, n;
    exteria_random(key, sizeof(key));
    CHECK_EQ_INT(exteria_mt_auth_key_set(&k, key), EXTERIA_OK);
    key[5] ^= 1;
    CHECK_EQ_INT(exteria_mt_auth_key_set(&other, key), EXTERIA_OK);
    CHECK(k.id != other.id);
    h.salt = 9;
    h.session_id = 8;
    h.msg_id = 0x1000000000000004ull;
    h.seq_no = -5;
    exteria_writer_init(&enc, 1 << 16);
    exteria_writer_init(&plain, 1 << 16);
    for (n = 0; n < sizeof(lens) / sizeof(lens[0]); ++n) {
        size_t len = lens[n];
        for (i = 0; i < len; ++i) body[i] = (uint8_t)(i * 13 + 1);
        enc.len = 0;
        plain.len = 0;
        CHECK_EQ_INT(exteria_mt_encrypt(&k, 1, &h, body, len, &enc), EXTERIA_OK);
        CHECK_EQ_INT((enc.len - 24) % 16, 0);
        CHECK(enc.len - 24 >= 32 + len + 12 && enc.len - 24 <= 32 + len + 12 + 15 + 32);
        CHECK_EQ_INT(exteria_mt_decrypt(&k, 1, 0, enc.data, enc.len, &plain, &back, &got, &got_len), EXTERIA_OK);
        CHECK_EQ_INT(got_len, len);
        CHECK_MEM(got, body, len);
        CHECK(back.msg_id == h.msg_id && back.salt == 9 && back.session_id == 8);
        CHECK_EQ_INT(back.seq_no, -5);
        plain.len = 0;
        CHECK_EQ_INT(exteria_mt_decrypt(&other, 1, 0, enc.data, enc.len, &plain, &back, &got, &got_len), EXTERIA_E_SECURITY);
        /* every single bit flip must be caught, the msg_key covers the whole plaintext */
        if (len == 36) {
            for (i = 0; i < enc.len; ++i) {
                enc.data[i] ^= 0x10;
                plain.len = 0;
                CHECK(exteria_mt_decrypt(&k, 1, 0, enc.data, enc.len, &plain, &back, &got, &got_len) != EXTERIA_OK);
                enc.data[i] ^= 0x10;
            }
            plain.len = 0;
            CHECK_EQ_INT(exteria_mt_decrypt(&k, 1, 0, enc.data, enc.len - 1, &plain, &back, &got, &got_len), EXTERIA_E_MALFORMED);
            CHECK_EQ_INT(exteria_mt_decrypt(&k, 1, 0, enc.data, 40, &plain, &back, &got, &got_len), EXTERIA_E_MALFORMED);
            /* transport padding must not invalidate an authenticated packet */
            {
                uint8_t *tail = (uint8_t *)malloc(enc.len + 7);
                memcpy(tail, enc.data, enc.len);
                memset(tail + enc.len, 0x55, 7);
                plain.len = 0;
                CHECK_EQ_INT(exteria_mt_decrypt(&k, 1, 0, tail, enc.len + 7, &plain, &back, &got, &got_len), EXTERIA_E_MALFORMED);
                plain.len = 0;
                CHECK_EQ_INT(exteria_mt_decrypt(&k, 1, 1, tail, enc.len + 7, &plain, &back, &got, &got_len), EXTERIA_OK);
                free(tail);
            }
        }
    }
    CHECK_EQ_INT(exteria_mt_encrypt(&k, 1, &h, body, 6, &enc), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_mt_encrypt(&k, 1, &h, body, 0, &enc), EXTERIA_E_ARG);
    exteria_writer_free(&enc);
    exteria_writer_free(&plain);
}

static void test_plain(void) {
    exteria_writer w;
    uint64_t id = 0;
    const uint8_t *body;
    size_t len;
    uint8_t body_in[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
    exteria_writer_init(&w, 4096);
    CHECK_EQ_INT(exteria_mt_plain_wrap(0x1234, body_in, 8, &w), EXTERIA_OK);
    CHECK_EQ_INT(w.len, 28);
    CHECK_EQ_INT(exteria_mt_plain_unwrap(w.data, w.len, 0, &id, &body, &len), EXTERIA_OK);
    CHECK_EQ_INT(id, 0x1234);
    CHECK_EQ_INT(len, 8);
    CHECK_MEM(body, body_in, 8);
    CHECK_EQ_INT(exteria_mt_plain_unwrap(w.data, w.len - 1, 0, &id, &body, &len), EXTERIA_E_MALFORMED);
    w.data[0] = 1;
    CHECK_EQ_INT(exteria_mt_plain_unwrap(w.data, w.len, 0, &id, &body, &len), EXTERIA_E_MALFORMED);
    w.data[0] = 0;
    CHECK_EQ_INT(exteria_mt_plain_wrap(1, body_in, 7, &w), EXTERIA_E_ARG);
    CHECK_EQ_INT(w.len, 28);
    exteria_writer_free(&w);
}

static void test_msg_ids(void) {
    uint64_t last = 0, a, b, c;
    a = exteria_mt_next_msg_id(1700000000123ull, &last);
    CHECK_EQ_INT(a & 3, 0);
    CHECK_EQ_INT(a >> 32, 1700000000);
    b = exteria_mt_next_msg_id(1700000000123ull, &last);
    CHECK(b > a && (b & 3) == 0);
    c = exteria_mt_next_msg_id(1600000000000ull, &last);
    CHECK(c > b && (c & 3) == 0);
}

static void feed_all(exteria_mt_transport *to, const uint8_t *data, size_t len, size_t chunk) {
    size_t i;
    for (i = 0; i < len; i += chunk) {
        size_t n = len - i < chunk ? len - i : chunk;
        CHECK_EQ_INT(exteria_mt_transport_feed(to, data + i, n), EXTERIA_OK);
    }
}

static void roundtrip_kind(exteria_mt_transport_kind kind, int obfuscated, int secret, size_t chunk) {
    exteria_mt_transport client, server;
    exteria_mt_obfuscation obf;
    exteria_writer wire, back;
    uint8_t secret_bytes[16];
    uint8_t payloads[3][400];
    size_t sizes[3] = { 8, 4, 400 }, i;
    exteria_mt_frame f;
    memset(&obf, 0, sizeof(obf));
    obf.enabled = obfuscated;
    obf.dc_id = 2;
    exteria_random(secret_bytes, sizeof(secret_bytes));
    if (secret) {
        obf.has_secret = 1;
        memcpy(obf.secret, secret_bytes, 16);
    }
    exteria_mt_transport_init(&client);
    exteria_mt_transport_init(&server);
    exteria_writer_init(&wire, 1 << 16);
    exteria_writer_init(&back, 1 << 16);
    CHECK_EQ_INT(exteria_mt_transport_start_server(&server, secret ? secret_bytes : NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_transport_start(&client, kind, &obf, &wire), EXTERIA_OK);
    if (!obfuscated) CHECK_EQ_INT(wire.len, kind == EXTERIA_MT_ABRIDGED ? 1 : 4);
    else CHECK_EQ_INT(wire.len, 64);
    for (i = 0; i < 3; ++i) {
        size_t k;
        for (k = 0; k < sizes[i]; ++k) payloads[i][k] = (uint8_t)(i * 50 + k);
        CHECK_EQ_INT(exteria_mt_transport_wrap(&client, payloads[i], sizes[i], 0, &wire), EXTERIA_OK);
    }
    feed_all(&server, wire.data, wire.len, chunk);
    CHECK_EQ_INT(server.kind, kind);
    if (obfuscated) CHECK_EQ_INT(server.obf.dc_id, 2);
    for (i = 0; i < 3; ++i) {
        CHECK_EQ_INT(exteria_mt_transport_next(&server, &f), EXTERIA_OK);
        CHECK_EQ_INT(f.kind, EXTERIA_MT_FRAME_DATA);
        if (kind == EXTERIA_MT_PADDED_INTERMEDIATE) {
            CHECK(f.len >= sizes[i] && f.len < sizes[i] + 16);
            CHECK_MEM(f.data, payloads[i], sizes[i]);
        } else {
            CHECK_EQ_INT(f.len, sizes[i]);
            CHECK_MEM(f.data, payloads[i], sizes[i]);
        }
    }
    CHECK_EQ_INT(exteria_mt_transport_next(&server, &f), EXTERIA_E_TRUNCATED);
    /* independent directions must not share a ctr stream position */
    for (i = 0; i < 3; ++i) {
        CHECK_EQ_INT(exteria_mt_transport_wrap(&server, payloads[i], sizes[i], 0, &back), EXTERIA_OK);
    }
    feed_all(&client, back.data, back.len, chunk);
    for (i = 0; i < 3; ++i) {
        CHECK_EQ_INT(exteria_mt_transport_next(&client, &f), EXTERIA_OK);
        CHECK(f.len >= sizes[i]);
        CHECK_MEM(f.data, payloads[i], sizes[i]);
    }
    exteria_mt_transport_free(&client);
    exteria_mt_transport_free(&server);
    exteria_writer_free(&wire);
    exteria_writer_free(&back);
}

static void test_transport_roundtrips(void) {
    exteria_mt_transport_kind kinds[3] = { EXTERIA_MT_ABRIDGED, EXTERIA_MT_INTERMEDIATE, EXTERIA_MT_PADDED_INTERMEDIATE };
    size_t chunks[3] = { 1, 7, 100000 };
    unsigned k, c;
    for (k = 0; k < 3; ++k) {
        for (c = 0; c < 3; ++c) {
            roundtrip_kind(kinds[k], 0, 0, chunks[c]);
            roundtrip_kind(kinds[k], 1, 0, chunks[c]);
            roundtrip_kind(kinds[k], 1, 1, chunks[c]);
        }
    }
}

static void test_transport_frames(void) {
    exteria_mt_transport t;
    exteria_mt_obfuscation obf;
    exteria_writer w;
    exteria_mt_frame f;
    uint8_t quick_abridged[4] = { 0x80, 0x00, 0x01, 0x02 };
    uint8_t quick_inter[4] = { 0x02, 0x01, 0x00, 0x80 };
    uint8_t err_frame[8] = { 0x04, 0x00, 0x00, 0x00, 0x6c, 0xfe, 0xff, 0xff };
    uint8_t err_abridged[5] = { 0x01, 0x6c, 0xfe, 0xff, 0xff };
    uint8_t huge[4] = { 0xff, 0xff, 0xff, 0x7f };
    uint8_t odd[8] = { 0x05, 0x00, 0x00, 0x00, 1, 2, 3, 4 };
    uint8_t long_hdr[12] = { 0x7f, 0x02, 0x00, 0x00, 1, 2, 3, 4, 5, 6, 7, 8 };
    memset(&obf, 0, sizeof(obf));
    exteria_writer_init(&w, 64);
    exteria_mt_transport_init(&t);
    CHECK_EQ_INT(exteria_mt_transport_start(&t, EXTERIA_MT_ABRIDGED, &obf, &w), EXTERIA_OK);
    exteria_mt_transport_feed(&t, quick_abridged, 4);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_OK);
    CHECK_EQ_INT(f.kind, EXTERIA_MT_FRAME_QUICK_ACK);
    CHECK_EQ_INT(f.quick_ack, 0x00000102);
    exteria_mt_transport_feed(&t, err_abridged, 1);
    exteria_mt_transport_feed(&t, err_abridged + 1, 4);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_OK);
    CHECK_EQ_INT(f.kind, EXTERIA_MT_FRAME_ERROR);
    CHECK_EQ_INT(f.error_code, -404);
    /* a split header must not consume the incomplete frame */
    exteria_mt_transport_feed(&t, long_hdr, 8);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_E_TRUNCATED);
    exteria_mt_transport_feed(&t, long_hdr + 8, 4);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_OK);
    CHECK_EQ_INT(f.len, 8);
    exteria_mt_transport_free(&t);
    w.len = 0;
    exteria_mt_transport_init(&t);
    CHECK_EQ_INT(exteria_mt_transport_start(&t, EXTERIA_MT_INTERMEDIATE, &obf, &w), EXTERIA_OK);
    exteria_mt_transport_feed(&t, quick_inter, 4);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_OK);
    CHECK_EQ_INT(f.kind, EXTERIA_MT_FRAME_QUICK_ACK);
    CHECK_EQ_INT(f.quick_ack, 0x00000102);
    exteria_mt_transport_feed(&t, err_frame, 8);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_OK);
    CHECK_EQ_INT(f.kind, EXTERIA_MT_FRAME_ERROR);
    CHECK_EQ_INT(f.error_code, -404);
    exteria_mt_transport_feed(&t, huge, 4);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_E_LIMIT);
    exteria_mt_transport_free(&t);
    w.len = 0;
    exteria_mt_transport_init(&t);
    CHECK_EQ_INT(exteria_mt_transport_start(&t, EXTERIA_MT_INTERMEDIATE, &obf, &w), EXTERIA_OK);
    exteria_mt_transport_feed(&t, odd, 8);
    CHECK_EQ_INT(exteria_mt_transport_next(&t, &f), EXTERIA_E_MALFORMED);
    exteria_mt_transport_free(&t);
    CHECK_EQ_INT(exteria_mt_transport_wrap(&t, odd, 4, 0, &w), EXTERIA_E_ARG);
    exteria_writer_free(&w);
}

static void test_obfuscation_init_rules(void) {
    exteria_mt_obfuscation obf;
    unsigned i;
    memset(&obf, 0, sizeof(obf));
    obf.enabled = 1;
    for (i = 0; i < 200; ++i) {
        exteria_mt_transport t;
        exteria_writer w;
        uint32_t first;
        exteria_mt_transport_init(&t);
        exteria_writer_init(&w, 64);
        CHECK_EQ_INT(exteria_mt_transport_start(&t, EXTERIA_MT_ABRIDGED, &obf, &w), EXTERIA_OK);
        first = exteria_get_u32le(w.data);
        /* the plain head must not look like an http verb or another transport tag */
        CHECK(w.data[0] != 0xef && first != 0x44414548u && first != 0x54534f50u && first != 0x20544547u &&
              first != 0x4954504fu && first != 0xeeeeeeeeu && first != 0xddddddddu && first != 0x02010316u);
        CHECK(exteria_get_u32le(w.data + 4) != 0);
        exteria_mt_transport_free(&t);
        exteria_writer_free(&w);
    }
}

int main(void) {
    test_keys();
    test_factor();
    test_dh_checks();
    test_msg_golden();
    test_msg_roundtrip();
    test_plain();
    test_msg_ids();
    test_transport_roundtrips();
    test_transport_frames();
    test_obfuscation_init_rules();
    return test_finish("test_mt_basic");
}
