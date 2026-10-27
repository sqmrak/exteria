#include "test_util.h"
#include "exteria_call.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

#define MODP14 "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF"

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set_i32(exteria_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, f, x), EXTERIA_OK); }
static void set_i64(exteria_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, f, x), EXTERIA_OK); }
static void set_str(exteria_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(exteria_tl_set_str(&arena, v, f, x), EXTERIA_OK); }
static void set_bytes(exteria_tl_value *v, const char *f, const void *x, size_t n) { CHECK_EQ_INT(exteria_tl_set_bytes(&arena, v, f, x, n), EXTERIA_OK); }
static void set_flag(exteria_tl_value *v, const char *f) { CHECK_EQ_INT(exteria_tl_set_flag(v, f), EXTERIA_OK); }
static void set(exteria_tl_value *v, const char *f, exteria_tl_value *x) { CHECK_EQ_INT(exteria_tl_set(v, f, x), EXTERIA_OK); }

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *v = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(v, i, items[i]), EXTERIA_OK);
    return v;
}

static void unhex(const char *hex, uint8_t *out, size_t n) {
    size_t i;
    for (i = 0; i < n; ++i) {
        unsigned value;
        sscanf(hex + 2 * i, "%2x", &value);
        out[i] = (uint8_t)value;
    }
}

static exteria_call_dh modp14(void) {
    exteria_call_dh dh;
    memset(&dh, 0, sizeof(dh));
    unhex(MODP14, dh.p, EXTERIA_CALL_KEY_LEN);
    dh.g = 2;
    dh.version = 7;
    return dh;
}

static void test_emoji_table(void) {
    size_t i;
    CHECK(!strcmp(exteria_call_emoji[0], "\xf0\x9f\x98\x89"));
    CHECK(!strcmp(exteria_call_emoji[EXTERIA_CALL_EMOJI_COUNT - 1], "\xf0\x9f\x94\xb7"));
    for (i = 0; i < EXTERIA_CALL_EMOJI_COUNT; ++i) CHECK(exteria_call_emoji[i] != NULL && exteria_call_emoji[i][0] != 0);
}

static void test_dh_config(void) {
    exteria_call_dh dh = modp14(), parsed;
    uint8_t random[EXTERIA_CALL_KEY_LEN], server[EXTERIA_CALL_KEY_LEN];
    exteria_tl_value *answer = obj("messages.dhConfig"), *request = NULL;
    memset(server, 0x5a, sizeof(server));
    set_i32(answer, "g", 2);
    set_bytes(answer, "p", dh.p, EXTERIA_CALL_KEY_LEN);
    set_i32(answer, "version", 7);
    set_bytes(answer, "random", server, sizeof(server));
    CHECK_EQ_INT(exteria_call_dh_parse(answer, NULL, &parsed, random), EXTERIA_OK);
    CHECK_EQ_INT(parsed.g, 2);
    CHECK_EQ_INT(parsed.version, 7);
    CHECK(!memcmp(parsed.p, dh.p, EXTERIA_CALL_KEY_LEN));
    CHECK(!memcmp(random, server, sizeof(server)));
    /* a prime that is not a safe prime is refused */
    {
        uint8_t composite[EXTERIA_CALL_KEY_LEN];
        memcpy(composite, dh.p, sizeof(composite));
        composite[EXTERIA_CALL_KEY_LEN - 1] ^= 2;
        set_bytes(answer, "p", composite, sizeof(composite));
        CHECK_EQ_INT(exteria_call_dh_parse(answer, NULL, &parsed, random), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(parsed.version, 0);
        set_bytes(answer, "p", dh.p, 255);
        CHECK_EQ_INT(exteria_call_dh_parse(answer, NULL, &parsed, random), EXTERIA_E_SECURITY);
        set_bytes(answer, "p", dh.p, EXTERIA_CALL_KEY_LEN);
    }
    set_i32(answer, "g", 9);
    CHECK_EQ_INT(exteria_call_dh_parse(answer, NULL, &parsed, random), EXTERIA_E_SECURITY);
    /* not modified: only valid against the config the app holds */
    {
        exteria_tl_value *same = obj("messages.dhConfigNotModified");
        set_bytes(same, "random", server, sizeof(server));
        CHECK_EQ_INT(exteria_call_dh_parse(same, NULL, &parsed, random), EXTERIA_E_STATE);
        CHECK_EQ_INT(exteria_call_dh_parse(same, &dh, &parsed, random), EXTERIA_OK);
        CHECK_EQ_INT(parsed.version, 7);
        CHECK(!memcmp(random, server, sizeof(server)));
    }
    CHECK_EQ_INT(exteria_call_dh_parse(obj("boolTrue"), &dh, &parsed, random), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_call_dh_request(&arena, 7, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getDhConfig);
    CHECK_EQ_INT(exteria_call_dh_request(&arena, -1, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

static void test_key_exchange(void) {
    exteria_call_dh dh = modp14();
    uint8_t seed_a[EXTERIA_CALL_KEY_LEN], seed_b[EXTERIA_CALL_KEY_LEN], server[EXTERIA_CALL_KEY_LEN];
    uint8_t a[EXTERIA_CALL_KEY_LEN], g_a[EXTERIA_CALL_KEY_LEN], b[EXTERIA_CALL_KEY_LEN], g_b[EXTERIA_CALL_KEY_LEN];
    uint8_t key_a[EXTERIA_CALL_KEY_LEN], key_b[EXTERIA_CALL_KEY_LEN], hash[32], again[32];
    int64_t fp_a, fp_b;
    uint16_t emoji_a[4], emoji_b[4];
    size_t i;
    for (i = 0; i < sizeof(seed_a); ++i) {
        seed_a[i] = (uint8_t)(i * 7 + 3);
        seed_b[i] = (uint8_t)(i * 13 + 11);
        server[i] = (uint8_t)(255 - i);
    }
    CHECK_EQ_INT(exteria_call_make_secret_from(&dh, seed_a, server, a, g_a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_call_make_secret_from(&dh, seed_b, server, b, g_b), EXTERIA_OK);
    CHECK(memcmp(g_a, g_b, sizeof(g_a)) != 0);
    CHECK_EQ_INT(a[0], seed_a[0] ^ server[0]);
    /* the two sides reach one key from each other's public value */
    CHECK_EQ_INT(exteria_call_make_key(&dh, g_b, a, key_a, &fp_a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_call_make_key(&dh, g_a, b, key_b, &fp_b), EXTERIA_OK);
    CHECK(!memcmp(key_a, key_b, sizeof(key_a)));
    CHECK_EQ_INT(fp_a, fp_b);
    CHECK(fp_a != 0);
    /* and the same four emoji, which change with the key */
    CHECK_EQ_INT(exteria_call_emoji_indexes(key_a, g_a, emoji_a), EXTERIA_OK);
    CHECK_EQ_INT(exteria_call_emoji_indexes(key_b, g_a, emoji_b), EXTERIA_OK);
    for (i = 0; i < 4; ++i) {
        CHECK_EQ_INT(emoji_a[i], emoji_b[i]);
        CHECK(emoji_a[i] < EXTERIA_CALL_EMOJI_COUNT);
    }
    CHECK_EQ_INT(exteria_call_emoji_indexes(key_a, g_b, emoji_b), EXTERIA_OK);
    CHECK(memcmp(emoji_a, emoji_b, sizeof(emoji_a)) != 0);
    /* the commitment is the hash of the public value and nothing else */
    CHECK_EQ_INT(exteria_call_commit(g_a, hash), EXTERIA_OK);
    CHECK_EQ_INT(exteria_call_commit(g_a, again), EXTERIA_OK);
    CHECK(!memcmp(hash, again, 32));
    CHECK_EQ_INT(exteria_call_commit(g_b, again), EXTERIA_OK);
    CHECK(memcmp(hash, again, 32) != 0);
    /* values that are 0, 1 or p - 1 would give a key anyone can guess */
    {
        uint8_t bad[EXTERIA_CALL_KEY_LEN];
        memset(bad, 0, sizeof(bad));
        CHECK_EQ_INT(exteria_call_make_key(&dh, bad, a, key_a, &fp_a), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(fp_a, 0);
        bad[EXTERIA_CALL_KEY_LEN - 1] = 1;
        CHECK_EQ_INT(exteria_call_make_key(&dh, bad, a, key_a, &fp_a), EXTERIA_E_SECURITY);
        memcpy(bad, dh.p, sizeof(bad));
        bad[EXTERIA_CALL_KEY_LEN - 1] -= 1;
        CHECK_EQ_INT(exteria_call_make_key(&dh, bad, a, key_a, &fp_a), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(key_a[0], 0);
    }
    CHECK_EQ_INT(exteria_call_make_secret_from(&dh, seed_a, server, NULL, g_a), EXTERIA_E_ARG);
}

static void test_requests(void) {
    exteria_tl_value *request = NULL;
    exteria_peer_ref user = {1, 77, 5, 0, 0}, nohash = {1, 77, 0, 0, 0}, channel = {3, 77, 5, 0, 0};
    uint8_t hash[32], pub[EXTERIA_CALL_KEY_LEN];
    memset(hash, 1, sizeof(hash));
    memset(pub, 2, sizeof(pub));
    CHECK_EQ_INT(exteria_call_request_request(&arena, &user, 99, hash, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_phone_requestCall);
    {
        const exteria_tl_value *proto = exteria_tl_get(request, "protocol"), *versions;
        int32_t min = 0, max = 0;
        const uint8_t *text;
        size_t len;
        CHECK_EQ_INT(exteria_tl_has(proto, "udp_p2p"), 1);
        CHECK_EQ_INT(exteria_tl_has(proto, "udp_reflector"), 1);
        CHECK_EQ_INT(exteria_tl_get_i32(proto, "min_layer", &min), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_get_i32(proto, "max_layer", &max), EXTERIA_OK);
        CHECK_EQ_INT(min, EXTERIA_CALL_MIN_LAYER);
        CHECK_EQ_INT(max, EXTERIA_CALL_MAX_LAYER);
        versions = exteria_tl_get(proto, "library_versions");
        /* tgcalls first, so that two phones that know it settle on it, then libtgvoip for a phone that does not */
        CHECK_EQ_INT(versions->u.vec.count, 2);
        CHECK_EQ_INT(exteria_tl_get_bytes(proto, "library_versions", &text, &len) == EXTERIA_OK, 0);
        CHECK_EQ_INT(versions->u.vec.items[0]->u.bytes.len, strlen(EXTERIA_CALL_TGCALLS_VERSION));
        CHECK(memcmp(versions->u.vec.items[0]->u.bytes.data, EXTERIA_CALL_TGCALLS_VERSION, strlen(EXTERIA_CALL_TGCALLS_VERSION)) == 0);
        CHECK_EQ_INT(versions->u.vec.items[1]->u.bytes.len, strlen(EXTERIA_CALL_LIBRARY_VERSION));
        CHECK_EQ_INT(exteria_tl_has(request, "video"), 0);
    }
    /* a video call carries the flag */
    CHECK_EQ_INT(exteria_call_request_request(&arena, &user, 99, hash, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "video"), 1);
    /* the signaling of a call: the call, the bytes, and refusals for none, too many, or no call */
    {
        static uint8_t big[16385];
        const uint8_t *got;
        size_t got_len;
        CHECK_EQ_INT(exteria_call_signaling_request(&arena, 5, 6, (const uint8_t *)"sealed", 6, &request), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_phone_sendSignalingData);
        CHECK_EQ_INT(exteria_tl_get_bytes(request, "data", &got, &got_len), EXTERIA_OK);
        CHECK(got_len == 6 && memcmp(got, "sealed", 6) == 0);
        CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "peer")), EXTERIA_TL_ID_inputPhoneCall);
        CHECK_EQ_INT(exteria_call_signaling_request(&arena, 5, 6, big, 16384, &request), EXTERIA_OK);
        CHECK_EQ_INT(exteria_call_signaling_request(&arena, 5, 6, big, 16385, &request), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(exteria_call_signaling_request(&arena, 5, 6, big, 0, &request), EXTERIA_E_LIMIT);
        CHECK(request == NULL);
        CHECK_EQ_INT(exteria_call_signaling_request(&arena, 0, 6, big, 4, &request), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_call_signaling_request(&arena, 5, 6, NULL, 4, &request), EXTERIA_E_ARG);
    }
    CHECK_EQ_INT(exteria_call_request_request(&arena, &nohash, 99, hash, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_call_request_request(&arena, &channel, 99, hash, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_accept_request(&arena, 5, 6, pub, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_phone_acceptCall);
    CHECK_EQ_INT(exteria_call_confirm_request(&arena, 5, 6, pub, -12345, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_phone_confirmCall);
    CHECK_EQ_INT(exteria_call_received_request(&arena, 5, 6, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_phone_receivedCall);
    CHECK_EQ_INT(exteria_call_discard_request(&arena, 5, 6, 61, EXTERIA_CALL_REASON_HANGUP, 3, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_phone_discardCall);
    CHECK_EQ_INT(exteria_tl_id(exteria_tl_get(request, "reason")), EXTERIA_TL_ID_phoneCallDiscardReasonHangup);
    CHECK_EQ_INT(exteria_call_discard_request(&arena, 5, 6, -1, EXTERIA_CALL_REASON_HANGUP, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_discard_request(&arena, 5, 6, 0, EXTERIA_CALL_REASON_NONE, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_call_accept_request(&arena, 0, 6, pub, &request), EXTERIA_E_ARG);
}

static exteria_tl_value *protocol_object(void) {
    exteria_tl_value *p = obj("phoneCallProtocol"), *versions[2];
    versions[0] = exteria_tl_new_str(&arena, "2.4.4");
    versions[1] = exteria_tl_new_str(&arena, "5.0.0");
    set_flag(p, "udp_p2p");
    set_i32(p, "min_layer", 65);
    set_i32(p, "max_layer", 92);
    set(p, "library_versions", vec_of(versions, 2));
    return p;
}

static exteria_tl_value *call_base(const char *ctor) {
    exteria_tl_value *c = obj(ctor);
    set_i64(c, "id", 4001);
    set_i64(c, "access_hash", 9001);
    set_i32(c, "date", 1700);
    set_i64(c, "admin_id", 10);
    set_i64(c, "participant_id", 20);
    set(c, "protocol", protocol_object());
    return c;
}

static void test_parse(void) {
    exteria_phone_call call;
    uint8_t g[EXTERIA_CALL_KEY_LEN], tag[16];
    exteria_tl_value *c, *conn, *conns[5], *answer;
    memset(g, 7, sizeof(g));
    memset(tag, 9, sizeof(tag));

    c = call_base("phoneCallWaiting");
    set_i32(c, "receive_date", 1710);
    CHECK_EQ_INT(exteria_phone_call_parse(c, &call), EXTERIA_OK);
    CHECK_EQ_INT(call.kind, EXTERIA_CALL_WAITING);
    CHECK_EQ_INT(call.id, 4001);
    CHECK_EQ_INT(call.receive_date, 1710);
    CHECK_EQ_INT(call.admin_id, 10);
    CHECK_EQ_INT(call.participant_id, 20);
    CHECK_EQ_INT(call.max_layer, 92);
    CHECK(!strcmp(call.version, "2.4.4"));

    c = call_base("phoneCallRequested");
    set_bytes(c, "g_a_hash", g, 32);
    CHECK_EQ_INT(exteria_phone_call_parse(c, &call), EXTERIA_OK);
    CHECK_EQ_INT(call.kind, EXTERIA_CALL_REQUESTED);
    CHECK_EQ_INT(call.has_hash, 1);
    CHECK_EQ_INT(call.g_hash[5], 7);
    /* a commitment of the wrong length cannot be checked later, so the call is refused now */
    set_bytes(c, "g_a_hash", g, 31);
    CHECK_EQ_INT(exteria_phone_call_parse(c, &call), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(call.id, 0);

    c = call_base("phoneCallAccepted");
    set_bytes(c, "g_b", g, EXTERIA_CALL_KEY_LEN);
    CHECK_EQ_INT(exteria_phone_call_parse(c, &call), EXTERIA_OK);
    CHECK_EQ_INT(call.kind, EXTERIA_CALL_ACCEPTED);
    CHECK_EQ_INT(call.has_g, 1);
    CHECK_EQ_INT(call.g[100], 7);

    c = call_base("phoneCall");
    set_flag(c, "p2p_allowed");
    set_bytes(c, "g_a_or_b", g, EXTERIA_CALL_KEY_LEN);
    set_i64(c, "key_fingerprint", -77);
    set_i32(c, "start_date", 1800);
    conn = obj("phoneConnection");
    set_i64(conn, "id", 31);
    set_str(conn, "ip", "149.154.167.1");
    set_str(conn, "ipv6", "");
    set_i32(conn, "port", 599);
    set_bytes(conn, "peer_tag", tag, 16);
    conns[0] = conn;
    conns[1] = obj("phoneConnectionWebrtc");
    set_i64(conns[1], "id", 32);
    set_str(conns[1], "ip", "1.2.3.4");
    set_str(conns[1], "ipv6", "");
    set_i32(conns[1], "port", 3478);
    set_str(conns[1], "username", "u");
    set_str(conns[1], "password", "p");
    conns[2] = obj("phoneConnection");
    set_i64(conns[2], "id", 33);
    set_str(conns[2], "ip", "149.154.167.2");
    set_str(conns[2], "ipv6", "2001:db8::1");
    set_i32(conns[2], "port", 599);
    set_bytes(conns[2], "peer_tag", tag, 15);
    /* a TURN server of the call (with the turn flag), and one that has the flag and no credentials */
    conns[3] = obj("phoneConnectionWebrtc");
    set_flag(conns[3], "turn");
    set_flag(conns[3], "stun");
    set_i64(conns[3], "id", 34);
    set_str(conns[3], "ip", "91.108.13.23");
    set_str(conns[3], "ipv6", "");
    set_i32(conns[3], "port", 598);
    set_str(conns[3], "username", "reflector");
    set_str(conns[3], "password", "p4ss-w0rd");
    conns[4] = obj("phoneConnectionWebrtc");
    set_flag(conns[4], "turn");
    set_i64(conns[4], "id", 35);
    set_str(conns[4], "ip", "91.108.13.24");
    set_str(conns[4], "ipv6", "");
    set_i32(conns[4], "port", 598);
    set_str(conns[4], "username", "");
    set_str(conns[4], "password", "x");
    set(c, "connections", vec_of(conns, 5));
    CHECK_EQ_INT(exteria_phone_call_parse(c, &call), EXTERIA_OK);
    CHECK_EQ_INT(call.kind, EXTERIA_CALL_ACTIVE);
    CHECK_EQ_INT(call.turn_count, 1);
    CHECK_EQ_INT(call.turns[0].id, 34);
    CHECK_EQ_INT(call.turns[0].port, 598);
    CHECK(!strcmp(call.turns[0].ip, "91.108.13.23"));
    CHECK(!strcmp(call.turns[0].username, "reflector"));
    CHECK(!strcmp(call.turns[0].password, "p4ss-w0rd"));
    CHECK_EQ_INT(call.p2p_allowed, 1);
    CHECK_EQ_INT(call.key_fingerprint, -77);
    /* the webrtc endpoint and the one with a short tag are left out, the reflector stays */
    CHECK_EQ_INT(call.connection_count, 1);
    CHECK_EQ_INT(call.connections[0].id, 31);
    CHECK_EQ_INT(call.connections[0].port, 599);
    CHECK(!strcmp(call.connections[0].ip, "149.154.167.1"));
    CHECK_EQ_INT(call.connections[0].peer_tag[3], 9);
    answer = obj("phone.phoneCall");
    set(answer, "phone_call", c);
    set(answer, "users", exteria_tl_new_vec(&arena, 0));
    CHECK_EQ_INT(exteria_phone_call_from_answer(answer, &call), EXTERIA_OK);
    CHECK_EQ_INT(call.kind, EXTERIA_CALL_ACTIVE);
    CHECK_EQ_INT(exteria_phone_call_from_answer(c, &call), EXTERIA_E_MALFORMED);

    c = obj("phoneCallDiscarded");
    set_i64(c, "id", 4001);
    set_i32(c, "duration", 42);
    set(c, "reason", obj("phoneCallDiscardReasonBusy"));
    set_flag(c, "need_rating");
    CHECK_EQ_INT(exteria_phone_call_parse(c, &call), EXTERIA_OK);
    CHECK_EQ_INT(call.kind, EXTERIA_CALL_DISCARDED);
    CHECK_EQ_INT(call.reason, EXTERIA_CALL_REASON_BUSY);
    CHECK_EQ_INT(call.duration, 42);
    CHECK_EQ_INT(call.need_rating, 1);

    c = obj("phoneCallEmpty");
    set_i64(c, "id", 5);
    CHECK_EQ_INT(exteria_phone_call_parse(c, &call), EXTERIA_OK);
    CHECK_EQ_INT(call.kind, EXTERIA_CALL_EMPTY);
    CHECK_EQ_INT(exteria_phone_call_parse(obj("boolTrue"), &call), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_phone_call_parse(NULL, &call), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_phone_call_parse(c, NULL), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_emoji_table();
    test_dh_config();
    test_key_exchange();
    test_requests();
    test_parse();
    exteria_arena_free(&arena);
    return test_finish("test_call");
}
