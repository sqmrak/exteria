#include "test_util.h"

#include <zlib.h>

#include "exteria_tl.h"
#include "exteria_tl_ids.h"

static const exteria_tl_value *must_obj(const exteria_tl_value *v, const char *field) {
    const exteria_tl_value *out = NULL;
    CHECK_EQ_INT(exteria_tl_get_obj(v, field, &out), EXTERIA_OK);
    return out;
}

static void test_schema_tables(void) {
    uint32_t i;
    int sorted = 1, names_ok = 1;
    for (i = 0; i < exteria_tl_ctor_count; ++i) {
        const exteria_tl_ctor *c = &exteria_tl_ctors[i];
        if (i && exteria_tl_ctors[i - 1].id >= c->id) sorted = 0;
        if (exteria_tl_find_ctor(c->id) != c || exteria_tl_find_ctor_by_name(c->name) != c) names_ok = 0;
    }
    CHECK(sorted);
    CHECK(names_ok);
    CHECK_EQ_INT(exteria_tl_layer, 229);
    CHECK_EQ_INT(EXTERIA_TL_LAYER, 229);
    CHECK_EQ_INT(EXTERIA_TL_ID_ping, 0x7abe77ecu);
    CHECK_EQ_INT(EXTERIA_TL_ID_boolTrue, 0x997275b5u);
    CHECK(exteria_tl_find_ctor(0x12345678u) == NULL);
    CHECK(exteria_tl_find_ctor_by_name("noSuchCtor") == NULL);
    CHECK(exteria_tl_find_ctor_by_name(NULL) == NULL);
}

static void test_golden(void) {
    exteria_arena a;
    exteria_writer w;
    exteria_tl_value *v;
    uint8_t want[64];
    long n;
    exteria_arena_init(&a, 1 << 20);
    exteria_writer_init(&w, 1 << 16);

    v = exteria_tl_new_obj(&a, "ping");
    CHECK(v != NULL);
    CHECK_EQ_INT(exteria_tl_set_i64(&a, v, "ping_id", 0x0102030405060708ll), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    n = test_hex("ec77be7a 0807060504030201", want, sizeof(want));
    CHECK_EQ_INT(w.len, n);
    CHECK_MEM(w.data, want, (size_t)n);

    w.len = 0;
    v = exteria_tl_new_obj(&a, "req_pq_multi");
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, v, "nonce", "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10", 16), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    n = test_hex("f18e7ebe 0102030405060708090a0b0c0d0e0f10", want, sizeof(want));
    CHECK_EQ_INT(w.len, n);
    CHECK_MEM(w.data, want, (size_t)n);
    CHECK_EQ_INT(exteria_tl_set_bytes(&a, v, "nonce", "short", 5), EXTERIA_E_ARG);

    w.len = 0;
    v = exteria_tl_new_obj(&a, "msgs_ack");
    {
        int64_t ids[3] = { 1, 2, 0x1122334455667788ll };
        CHECK_EQ_INT(exteria_tl_set_i64_vec(&a, v, "msg_ids", ids, 3), EXTERIA_OK);
    }
    CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
    n = test_hex("59b4d662 15c4b51c 03000000 0100000000000000 0200000000000000 8877665544332211", want, sizeof(want));
    CHECK_EQ_INT(w.len, n);
    CHECK_MEM(w.data, want, (size_t)n);

    exteria_writer_free(&w);
    exteria_arena_free(&a);
}

static void test_decode_basics(void) {
    exteria_arena a;
    exteria_tl_value *v;
    const uint8_t bool_true[4] = { 0xb5, 0x75, 0x72, 0x99 };
    uint8_t buf[64];
    size_t used = 0;
    long n;
    exteria_arena_init(&a, 1 << 20);
    CHECK_EQ_INT(exteria_tl_decode(&a, NULL, EXTERIA_TL_REF_ANY, bool_true, 4, &used, &v), EXTERIA_OK);
    CHECK_EQ_INT(used, 4);
    CHECK(exteria_tl_is(v, EXTERIA_TL_ID_boolTrue));

    n = test_hex("79b784a3 05000000 07000000", buf, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &v), EXTERIA_OK);
    {
        int32_t id = 0, fl = 0;
        CHECK_EQ_INT(exteria_tl_get_i32(v, "id", &id), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_get_i32(v, "flags", &fl), EXTERIA_OK);
        CHECK_EQ_INT(id, 5);
        CHECK_EQ_INT(fl, 7);
        CHECK_EQ_INT(exteria_tl_get_i64(v, "id", NULL), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(exteria_tl_get_i32(v, "nope", &id), EXTERIA_E_NOTFOUND);
    }
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n - 1, &v), EXTERIA_E_TRUNCATED);
    buf[n] = 0;
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n + 1, &v), EXTERIA_E_MALFORMED);

    /* a bool is not a resPQ, accepting it would let a peer swap handshake steps */
    {
        const exteria_tl_ctor *res_pq = exteria_tl_find_ctor_by_name("resPQ");
        CHECK_EQ_INT(exteria_tl_decode(&a, NULL, res_pq->result, bool_true, 4, &used, &v), EXTERIA_E_MALFORMED);
        /* accepting a function here would let the peer send a request as a response */
        n = test_hex("ec77be7a 0807060504030201", buf, sizeof(buf));
        CHECK_EQ_INT(exteria_tl_decode(&a, NULL, res_pq->result, buf, (size_t)n, &used, &v), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(exteria_tl_decode(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &used, &v), EXTERIA_OK);
    }
    n = test_hex("78563412", buf, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_decode(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &used, &v), EXTERIA_E_UNSUPPORTED);
    CHECK(v == NULL);
    exteria_arena_free(&a);
}

static void test_string_padding(void) {
    static const size_t lens[] = { 0, 1, 2, 3, 4, 5, 252, 253, 254, 255, 256, 257, 1000, 70000 };
    exteria_arena a;
    exteria_writer w;
    unsigned i;
    exteria_writer_init(&w, 1 << 20);
    exteria_arena_init(&a, 8 << 20);
    for (i = 0; i < sizeof(lens) / sizeof(lens[0]); ++i) {
        size_t len = lens[i];
        uint8_t *payload = (uint8_t *)malloc(len + 1);
        exteria_tl_value *v, *back;
        const uint8_t *got;
        size_t got_len, header = len < 254 ? 1 : 4, padded = (header + len + 3) / 4 * 4;
        size_t k;
        for (k = 0; k < len; ++k) payload[k] = (uint8_t)(k * 31 + 7);
        w.len = 0;
        v = exteria_tl_new_obj(&a, "contacts.search");
        CHECK_EQ_INT(exteria_tl_set_bytes(&a, v, "q", payload, len), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_set_i32(&a, v, "limit", 10), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_encode(v, &w, NULL), EXTERIA_OK);
        CHECK_EQ_INT(w.len, 4 + 4 + padded + 4);
        if (len >= 254) CHECK_EQ_INT(w.data[8], 254);
        for (k = 8 + header + len; k < 8 + padded; ++k) CHECK_EQ_INT(w.data[k], 0);
        CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, w.data, w.len, &back), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_get_bytes(back, "q", &got, &got_len), EXTERIA_OK);
        CHECK_EQ_INT(got_len, len);
        if (len) CHECK_MEM(got, payload, len);
        CHECK_EQ_INT(got[len], 0);
        free(payload);
    }
    exteria_writer_free(&w);
    exteria_arena_free(&a);
}

static void test_flags(void) {
    exteria_arena a;
    exteria_writer w;
    exteria_tl_value *msg, *peer, *back;
    int32_t flags = -1;
    exteria_tl_error err;
    exteria_arena_init(&a, 1 << 20);
    exteria_writer_init(&w, 1 << 16);
    msg = exteria_tl_new_obj(&a, "messages.sendMessage");
    peer = exteria_tl_new_obj(&a, "inputPeerSelf");
    CHECK(msg && peer);
    CHECK_EQ_INT(exteria_tl_encode(msg, &w, &err), EXTERIA_E_ARG);
    CHECK(err.field && strcmp(err.field, "peer") == 0);
    CHECK_EQ_INT(w.len, 0);
    CHECK_EQ_INT(exteria_tl_set(msg, "peer", peer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&a, msg, "message", "hello"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&a, msg, "random_id", 42), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_flag(msg, "silent"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, msg, "schedule_date", 1700000000), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(msg, &w, &err), EXTERIA_OK);
    CHECK_EQ_INT(exteria_get_u32le(w.data + 4), (1u << 5) | (1u << 10));
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, w.data, w.len, &back), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i32(back, "flags", &flags), EXTERIA_OK);
    CHECK_EQ_INT(flags, (1 << 5) | (1 << 10));
    CHECK(exteria_tl_has(back, "silent"));
    CHECK(!exteria_tl_has(back, "background"));
    CHECK(!exteria_tl_has(back, "reply_to"));
    CHECK(exteria_tl_has(back, "schedule_date"));
    CHECK(exteria_tl_is(must_obj(back, "peer"), EXTERIA_TL_ID_inputPeerSelf));
    /* flags is derived from the fields, a caller cannot set it to disagree */
    CHECK_EQ_INT(exteria_tl_set_i32(&a, msg, "flags", 0xff), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, msg, "unknown_field", 1), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_tl_set_i32(&a, msg, "message", 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tl_set(msg, "peer", msg), EXTERIA_E_ARG);
    exteria_writer_free(&w);
    exteria_arena_free(&a);
}

static void test_truncation_and_garbage(void) {
    exteria_arena a;
    exteria_writer w;
    exteria_tl_value *msg, *peer, *ent_vec, *ent;
    size_t cut;
    exteria_arena_init(&a, 1 << 20);
    exteria_writer_init(&w, 1 << 16);
    msg = exteria_tl_new_obj(&a, "messages.sendMessage");
    peer = exteria_tl_new_obj(&a, "inputPeerChannel");
    exteria_tl_set_i64(&a, peer, "channel_id", 5);
    exteria_tl_set_i64(&a, peer, "access_hash", 6);
    exteria_tl_set(msg, "peer", peer);
    exteria_tl_set_str(&a, msg, "message", "text with an entity");
    exteria_tl_set_i64(&a, msg, "random_id", 9);
    ent_vec = exteria_tl_new_vec(&a, 1);
    ent = exteria_tl_new_obj(&a, "messageEntityBold");
    exteria_tl_set_i32(&a, ent, "offset", 0);
    exteria_tl_set_i32(&a, ent, "length", 4);
    exteria_tl_vec_set(ent_vec, 0, ent);
    CHECK_EQ_INT(exteria_tl_set(msg, "entities", ent_vec), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_encode(msg, &w, NULL), EXTERIA_OK);
    for (cut = 0; cut < w.len; ++cut) {
        exteria_tl_value *out;
        exteria_status s = exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, w.data, cut, &out);
        CHECK(s == EXTERIA_E_TRUNCATED || s == EXTERIA_E_MALFORMED);
    }
    {
        exteria_tl_value *out;
        CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, w.data, w.len, &out), EXTERIA_OK);
    }
    exteria_writer_free(&w);
    exteria_arena_free(&a);
}

static void test_vector_limits(void) {
    exteria_arena a;
    exteria_tl_value *v;
    uint8_t buf[64];
    long n;
    exteria_arena_init(&a, 1 << 20);
    n = test_hex("59b4d662 15c4b51c ffffffff", buf, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &v), EXTERIA_E_MALFORMED);
    n = test_hex("59b4d662 15c4b51d 00000000", buf, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &v), EXTERIA_E_MALFORMED);
    n = test_hex("59b4d662 15c4b51c 00000000", buf, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &v), EXTERIA_OK);
    {
        exteria_tl_limits lim = exteria_tl_default_limits;
        const exteria_tl_value *ids = NULL;
        uint8_t big[4 + 8 + 8 * 100];
        size_t i;
        exteria_put_u32le(big, EXTERIA_TL_ID_msgs_ack);
        exteria_put_u32le(big + 4, 0x1cb5c415u);
        exteria_put_u32le(big + 8, 100);
        for (i = 0; i < 100; ++i) exteria_put_u64le(big + 12 + 8 * i, i);
        lim.max_values = 50;
        CHECK_EQ_INT(exteria_tl_decode_all(&a, &lim, EXTERIA_TL_REF_ANY, big, sizeof(big), &v), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, big, sizeof(big), &v), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tl_get_vec(v, "msg_ids", &ids), EXTERIA_OK);
        CHECK_EQ_INT(ids->u.vec.count, 100);
        CHECK_EQ_INT(ids->u.vec.items[99]->u.i64, 99);
    }
    exteria_arena_free(&a);
    exteria_arena_init(&a, 100);
    n = test_hex("79b784a3 05000000 07000000", buf, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &v), EXTERIA_OK);
    exteria_arena_free(&a);
    exteria_arena_init(&a, 40);
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, (size_t)n, &v), EXTERIA_E_LIMIT);
    exteria_arena_free(&a);
}

static void test_depth(void) {
    enum { DEPTH = 100 };
    exteria_arena a;
    uint8_t *buf = (uint8_t *)malloc(4 * (DEPTH + 1));
    exteria_tl_value *v;
    int i;
    exteria_arena_init(&a, 8 << 20);
    for (i = 0; i < DEPTH; ++i) exteria_put_u32le(buf + 4 * i, EXTERIA_TL_ID_textBold);
    exteria_put_u32le(buf + 4 * DEPTH, EXTERIA_TL_ID_textEmpty);
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf, 4 * (DEPTH + 1), &v), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, buf + 4 * (DEPTH - 30), 4 * 31, &v), EXTERIA_OK);
    free(buf);
    exteria_arena_free(&a);
}

static size_t gzip_bytes(const uint8_t *in, size_t len, uint8_t **out) {
    z_stream zs;
    size_t cap = deflateBound(NULL, (uLong)len) + 64;
    memset(&zs, 0, sizeof(zs));
    *out = (uint8_t *)malloc(cap);
    deflateInit2(&zs, 6, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
    zs.next_in = (Bytef *)(uintptr_t)in;
    zs.avail_in = (uInt)len;
    zs.next_out = *out;
    zs.avail_out = (uInt)cap;
    deflate(&zs, Z_FINISH);
    cap = cap - zs.avail_out;
    deflateEnd(&zs);
    return cap;
}

static size_t wrap_gzip(const uint8_t *payload, size_t len, uint8_t **out) {
    uint8_t *packed;
    size_t plen = gzip_bytes(payload, len, &packed);
    exteria_writer w;
    exteria_tl_value *v;
    exteria_arena a;
    size_t n;
    exteria_arena_init(&a, 1 << 20);
    exteria_writer_init(&w, 1 << 26);
    v = exteria_tl_new_obj(&a, "gzip_packed");
    exteria_tl_set_bytes(&a, v, "packed_data", packed, plen);
    exteria_tl_encode(v, &w, NULL);
    *out = exteria_writer_take(&w, &n);
    free(packed);
    exteria_arena_free(&a);
    return n;
}

static void test_gzip(void) {
    exteria_arena a;
    exteria_tl_value *v;
    const uint8_t bool_true[4] = { 0xb5, 0x75, 0x72, 0x99 };
    uint8_t *packed, *twice;
    size_t n, n2;
    exteria_arena_init(&a, 64 << 20);
    n = wrap_gzip(bool_true, 4, &packed);
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, packed, n, &v), EXTERIA_OK);
    CHECK(exteria_tl_is(v, EXTERIA_TL_ID_boolTrue));
    {
        const exteria_tl_ctor *boolean = exteria_tl_find_ctor_by_name("boolTrue");
        CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, exteria_tl_find_ctor_by_name("resPQ")->result, packed, n, &v), EXTERIA_E_MALFORMED);
        CHECK(boolean != NULL);
    }
    /* one level only, a nested gzip is how a bomb hides its size */
    n2 = wrap_gzip(packed, n, &twice);
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, twice, n2, &v), EXTERIA_E_MALFORMED);
    free(twice);
    packed[n - 6] ^= 0xff;
    CHECK(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, packed, n, &v) != EXTERIA_OK);
    packed[n - 6] ^= 0xff;
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, packed, n - 8, &v) != EXTERIA_OK, 1);
    free(packed);
    {
        size_t big_len = 20u * 1024u * 1024u;
        uint8_t *zeros = (uint8_t *)calloc(1, big_len);
        n = wrap_gzip(zeros, big_len, &packed);
        CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, EXTERIA_TL_REF_ANY, packed, n, &v), EXTERIA_E_LIMIT);
        free(zeros);
        free(packed);
    }
    exteria_arena_free(&a);
}

static void test_result_ref(void) {
    exteria_arena a;
    exteria_tl_value *layer, *init, *inner;
    uint16_t ref = 0;
    const exteria_tl_ctor *receipt = exteria_tl_find_ctor_by_name("messages.receivedMessages");
    uint8_t buf[64];
    exteria_tl_value *out;
    long n;
    exteria_arena_init(&a, 1 << 20);
    inner = exteria_tl_new_obj(&a, "messages.receivedMessages");
    exteria_tl_set_i32(&a, inner, "max_id", 3);
    init = exteria_tl_new_obj(&a, "invokeAfterMsg");
    exteria_tl_set_i64(&a, init, "msg_id", 1);
    CHECK_EQ_INT(exteria_tl_set(init, "query", inner), EXTERIA_OK);
    layer = exteria_tl_new_obj(&a, "invokeWithLayer");
    exteria_tl_set_i32(&a, layer, "layer", 229);
    CHECK_EQ_INT(exteria_tl_set(layer, "query", init), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_result_ref(layer, &ref), EXTERIA_OK);
    CHECK_EQ_INT(ref, receipt->result);
    CHECK_EQ_INT(exteria_tl_result_ref(exteria_tl_new_obj(&a, "boolTrue"), &ref), EXTERIA_E_ARG);
    /* a vector answer has no ids on bare elements, so the request must say how to read it */
    n = test_hex("15c4b51c 01000000 79b784a3 05000000 07000000", buf, sizeof(buf));
    CHECK_EQ_INT(exteria_tl_decode_all(&a, NULL, ref, buf, (size_t)n, &out), EXTERIA_OK);
    CHECK_EQ_INT(out->kind, EXTERIA_TL_V_VEC);
    CHECK_EQ_INT(out->u.vec.count, 1);
    exteria_arena_free(&a);
}

static void test_dump(void) {
    exteria_arena a;
    exteria_writer w;
    exteria_tl_value *v;
    exteria_arena_init(&a, 1 << 20);
    exteria_writer_init(&w, 4096);
    v = exteria_tl_new_obj(&a, "ping");
    exteria_tl_set_i64(&a, v, "ping_id", 77);
    CHECK_EQ_INT(exteria_tl_dump(v, &w), EXTERIA_OK);
    CHECK_EQ_INT(w.len, strlen("ping(ping_id=77)"));
    CHECK_MEM(w.data, "ping(ping_id=77)", w.len);
    exteria_writer_free(&w);
    exteria_arena_free(&a);
}

int main(void) {
    test_schema_tables();
    test_golden();
    test_decode_basics();
    test_string_padding();
    test_flags();
    test_truncation_and_garbage();
    test_vector_limits();
    test_depth();
    test_gzip();
    test_result_ref();
    test_dump();
    return test_finish("test_tl");
}
