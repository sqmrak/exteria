#include "exteria_faketls.h"

#include <string.h>

#include "exteria_crypto.h"

#define BLOCK 64
#define RANDOM_AT 11
#define TLS_VERSION_MAJOR 3
#define TLS_VERSION_MINOR 3

exteria_status exteria_faketls_hmac(const uint8_t *key, size_t key_len, const exteria_slice *parts, size_t count, uint8_t out[32]) {
    uint8_t block[BLOCK], inner[32];
    exteria_slice outer[2], list[8];
    size_t i;
    exteria_status status;
    if (!key || !parts || !out || count == 0 || count > 7) return EXTERIA_E_ARG;
    memset(block, 0, sizeof(block));
    if (key_len > BLOCK) {
        status = exteria_sha256_one(key, key_len, block);
        if (status != EXTERIA_OK) return status;
    } else {
        memcpy(block, key, key_len);
    }
    for (i = 0; i < BLOCK; ++i) block[i] ^= 0x36;
    list[0].data = block;
    list[0].len = BLOCK;
    for (i = 0; i < count; ++i) list[i + 1] = parts[i];
    status = exteria_sha256(list, count + 1, inner);
    if (status != EXTERIA_OK) goto done;
    for (i = 0; i < BLOCK; ++i) block[i] ^= 0x36 ^ 0x5c;
    outer[0].data = block;
    outer[0].len = BLOCK;
    outer[1].data = inner;
    outer[1].len = sizeof(inner);
    status = exteria_sha256(outer, 2, out);
done:
    exteria_wipe(block, sizeof(block));
    exteria_wipe(inner, sizeof(inner));
    return status;
}

typedef struct hello_builder {
    uint8_t *buf;
    size_t n;
    int overflow;
} hello_builder;

static void put(hello_builder *b, const void *data, size_t len) {
    if (b->overflow || b->n + len > EXTERIA_FAKETLS_HELLO_LEN) {
        b->overflow = 1;
        return;
    }
    memcpy(b->buf + b->n, data, len);
    b->n += len;
}

static void put_u16(hello_builder *b, unsigned value) {
    uint8_t two[2];
    two[0] = (uint8_t)(value >> 8);
    two[1] = (uint8_t)value;
    put(b, two, 2);
}

/* the placeholder values of the GREASE slots: both bytes alike, and a high nibble that changes from one to the next */
static void put_grease(hello_builder *b, uint8_t value) {
    uint8_t two[2];
    two[0] = two[1] = value;
    put(b, two, 2);
}

static int domain_valid(const char *domain) {
    size_t len, i;
    if (!domain) return 0;
    len = strlen(domain);
    if (len == 0 || len > EXTERIA_FAKETLS_DOMAIN_MAX) return 0;
    for (i = 0; i < len; ++i) {
        char c = domain[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-')) return 0;
    }
    return 1;
}

exteria_status exteria_faketls_hello(const uint8_t secret[EXTERIA_FAKETLS_SECRET_LEN], const char *domain, uint32_t timestamp,
                                     const uint8_t entropy[EXTERIA_FAKETLS_ENTROPY_LEN], uint8_t out[EXTERIA_FAKETLS_HELLO_LEN],
                                     uint8_t random[32]) {
    static const uint8_t head[] = {0x16, 0x03, 0x01, 0x02, 0x00, 0x01, 0x00, 0x01, 0xfc, 0x03, 0x03};
    static const uint8_t suites[] = {0x13, 0x01, 0x13, 0x02, 0x13, 0x03, 0xc0, 0x2b, 0xc0, 0x2f, 0xc0, 0x2c, 0xc0, 0x30, 0xcc, 0xa9,
                                     0xcc, 0xa8, 0xc0, 0x13, 0xc0, 0x14, 0x00, 0x9c, 0x00, 0x9d, 0x00, 0x2f, 0x00, 0x35};
    static const uint8_t after_suites[] = {0x01, 0x00};
    static const uint8_t plain_a[] = {0x00, 0x17, 0x00, 0x00, 0xff, 0x01, 0x00, 0x01, 0x00};
    static const uint8_t groups[] = {0x00, 0x0a, 0x00, 0x0a, 0x00, 0x08};
    static const uint8_t groups_tail[] = {0x00, 0x1d, 0x00, 0x17, 0x00, 0x18};
    static const uint8_t plain_b[] = {0x00, 0x0b, 0x00, 0x02, 0x01, 0x00, 0x00, 0x23, 0x00, 0x00, 0x00, 0x10, 0x00, 0x0e, 0x00, 0x0c, 0x02, 0x68,
                                      0x32, 0x08, 0x68, 0x74, 0x74, 0x70, 0x2f, 0x31, 0x2e, 0x31, 0x00, 0x05, 0x00, 0x05, 0x01, 0x00, 0x00, 0x00,
                                      0x00, 0x00, 0x0d, 0x00, 0x14, 0x00, 0x12, 0x04, 0x03, 0x08, 0x04, 0x04, 0x01, 0x05, 0x03, 0x08, 0x05, 0x05,
                                      0x01, 0x08, 0x06, 0x06, 0x01, 0x02, 0x01, 0x00, 0x12, 0x00, 0x00};
    static const uint8_t share[] = {0x00, 0x33, 0x00, 0x2b, 0x00, 0x29};
    static const uint8_t share_mid[] = {0x00, 0x01, 0x00, 0x00, 0x1d, 0x00, 0x20};
    static const uint8_t modes[] = {0x00, 0x2d, 0x00, 0x02, 0x01, 0x01};
    static const uint8_t versions[] = {0x00, 0x2b, 0x00, 0x0b, 0x0a};
    static const uint8_t versions_tail[] = {0x03, 0x04, 0x03, 0x03, 0x03, 0x02, 0x03, 0x01};
    static const uint8_t compress[] = {0x00, 0x1b, 0x00, 0x03, 0x02, 0x00, 0x02};
    static const uint8_t last_ext[] = {0x00, 0x01, 0x00};
    hello_builder b;
    uint8_t grease[7], private_key[EXTERIA_X25519_LEN], public_key[EXTERIA_X25519_LEN], digest[32], mark = 0x20;
    uint8_t zero_random[32];
    exteria_slice parts[1];
    size_t domain_len, extensions_at, padding;
    unsigned i;
    exteria_status status;
    if (random) memset(random, 0, 32);
    if (!secret || !entropy || !out || !random) return EXTERIA_E_ARG;
    if (!domain_valid(domain)) return EXTERIA_E_ARG;
    domain_len = strlen(domain);
    for (i = 0; i < 7; ++i) grease[i] = (uint8_t)((entropy[64 + i] & 0xf0u) | 0x0au);
    /* the first and the last extension carry GREASE values that must differ */
    if (grease[3] == grease[2]) grease[3] = (uint8_t)(grease[3] ^ 0x10u);
    memcpy(private_key, entropy + 32, sizeof(private_key));
    status = exteria_x25519_public(private_key, public_key);
    exteria_wipe(private_key, sizeof(private_key));
    if (status != EXTERIA_OK) return status;

    memset(out, 0, EXTERIA_FAKETLS_HELLO_LEN);
    b.buf = out;
    b.n = 0;
    b.overflow = 0;
    put(&b, head, sizeof(head));
    b.n += 32;
    put(&b, &mark, 1);
    put(&b, entropy, 32);
    put_u16(&b, 2 + sizeof(suites));
    put_grease(&b, grease[0]);
    put(&b, suites, sizeof(suites));
    put(&b, after_suites, sizeof(after_suites));
    extensions_at = b.n;
    put_u16(&b, 0);
    put_grease(&b, grease[2]);
    put_u16(&b, 0);
    put_u16(&b, 0);
    put_u16(&b, (unsigned)domain_len + 5);
    put_u16(&b, (unsigned)domain_len + 3);
    mark = 0;
    put(&b, &mark, 1);
    put_u16(&b, (unsigned)domain_len);
    put(&b, domain, domain_len);
    put(&b, plain_a, sizeof(plain_a));
    put(&b, groups, sizeof(groups));
    put_grease(&b, grease[4]);
    put(&b, groups_tail, sizeof(groups_tail));
    put(&b, plain_b, sizeof(plain_b));
    put(&b, share, sizeof(share));
    put_grease(&b, grease[4]);
    put(&b, share_mid, sizeof(share_mid));
    put(&b, public_key, sizeof(public_key));
    put(&b, modes, sizeof(modes));
    put(&b, versions, sizeof(versions));
    put_grease(&b, grease[6]);
    put(&b, versions_tail, sizeof(versions_tail));
    put(&b, compress, sizeof(compress));
    put_grease(&b, grease[3]);
    put(&b, last_ext, sizeof(last_ext));
    /* the padding extension brings the record to 517 bytes, as the real clients' hellos have */
    if (b.overflow || b.n + 4 > EXTERIA_FAKETLS_HELLO_LEN) return EXTERIA_E_LIMIT;
    padding = EXTERIA_FAKETLS_HELLO_LEN - b.n - 4;
    put_u16(&b, 0x0015);
    put_u16(&b, (unsigned)padding);
    b.n += padding;
    if (b.overflow || b.n != EXTERIA_FAKETLS_HELLO_LEN) return EXTERIA_E_LIMIT;
    out[extensions_at] = (uint8_t)((EXTERIA_FAKETLS_HELLO_LEN - extensions_at - 2) >> 8);
    out[extensions_at + 1] = (uint8_t)(EXTERIA_FAKETLS_HELLO_LEN - extensions_at - 2);

    memset(zero_random, 0, sizeof(zero_random));
    parts[0].data = out;
    parts[0].len = EXTERIA_FAKETLS_HELLO_LEN;
    status = exteria_faketls_hmac(secret, EXTERIA_FAKETLS_SECRET_LEN, parts, 1, digest);
    if (status != EXTERIA_OK) return status;
    /* the clock rides in the last four bytes, which the proxy reads back to refuse a replayed hello */
    digest[28] = (uint8_t)(digest[28] ^ (uint8_t)timestamp);
    digest[29] = (uint8_t)(digest[29] ^ (uint8_t)(timestamp >> 8));
    digest[30] = (uint8_t)(digest[30] ^ (uint8_t)(timestamp >> 16));
    digest[31] = (uint8_t)(digest[31] ^ (uint8_t)(timestamp >> 24));
    memcpy(out + RANDOM_AT, digest, 32);
    memcpy(random, digest, 32);
    return EXTERIA_OK;
}

static size_t record_length(const uint8_t *header) {
    return ((size_t)header[3] << 8) | header[4];
}

exteria_status exteria_faketls_reply_progress(const uint8_t *buf, size_t len, size_t *total) {
    static const uint8_t spec[6] = {0x14, 0x03, 0x03, 0x00, 0x01, 0x01};
    size_t at = 0, n;
    if (total) *total = 0;
    if (!buf || !total) return EXTERIA_E_ARG;
    /* the server hello */
    if (len > 0 && buf[0] != 0x16) return EXTERIA_E_MALFORMED;
    if (len > 1 && buf[1] != TLS_VERSION_MAJOR) return EXTERIA_E_MALFORMED;
    if (len > 2 && buf[2] != TLS_VERSION_MINOR) return EXTERIA_E_MALFORMED;
    if (len < 5) return EXTERIA_E_RETRY;
    n = record_length(buf);
    if (n < 4 + 2 + 32 || n > EXTERIA_FAKETLS_PAYLOAD_MAX) return EXTERIA_E_MALFORMED;
    at = 5 + n;
    *total = at;
    /* the change cipher spec */
    if (len <= at) return EXTERIA_E_RETRY;
    if (memcmp(buf + at, spec, len - at < sizeof(spec) ? len - at : sizeof(spec)) != 0) return EXTERIA_E_MALFORMED;
    at += sizeof(spec);
    *total = at;
    if (len < at) return EXTERIA_E_RETRY;
    /* the application record, which holds what stands in for the certificate */
    if (len > at && buf[at] != 0x17) return EXTERIA_E_MALFORMED;
    if (len > at + 1 && buf[at + 1] != TLS_VERSION_MAJOR) return EXTERIA_E_MALFORMED;
    if (len > at + 2 && buf[at + 2] != TLS_VERSION_MINOR) return EXTERIA_E_MALFORMED;
    if (len < at + 5) return EXTERIA_E_RETRY;
    n = record_length(buf + at);
    if (n > EXTERIA_FAKETLS_PAYLOAD_MAX) return EXTERIA_E_MALFORMED;
    at += 5 + n;
    *total = at;
    return len >= at ? EXTERIA_OK : EXTERIA_E_RETRY;
}

exteria_status exteria_faketls_check_reply(const uint8_t secret[EXTERIA_FAKETLS_SECRET_LEN], const uint8_t random[32], const uint8_t *reply, size_t len) {
    uint8_t zeroed[32], expected[32], head[RANDOM_AT];
    exteria_slice parts[4];
    size_t total = 0;
    exteria_status status;
    if (!secret || !random || !reply) return EXTERIA_E_ARG;
    status = exteria_faketls_reply_progress(reply, len, &total);
    if (status == EXTERIA_E_RETRY || (status == EXTERIA_OK && total != len)) return EXTERIA_E_MALFORMED;
    if (status != EXTERIA_OK) return status;
    memset(zeroed, 0, sizeof(zeroed));
    memcpy(head, reply, RANDOM_AT);
    parts[0].data = random;
    parts[0].len = 32;
    parts[1].data = head;
    parts[1].len = RANDOM_AT;
    parts[2].data = zeroed;
    parts[2].len = 32;
    parts[3].data = reply + RANDOM_AT + 32;
    parts[3].len = len - RANDOM_AT - 32;
    status = exteria_faketls_hmac(secret, EXTERIA_FAKETLS_SECRET_LEN, parts, 4, expected);
    if (status != EXTERIA_OK) return status;
    return exteria_ct_equal(expected, reply + RANDOM_AT, 32) ? EXTERIA_OK : EXTERIA_E_SECURITY;
}

void exteria_faketls_reader_init(exteria_faketls_reader *reader) {
    memset(reader, 0, sizeof(*reader));
}

exteria_status exteria_faketls_unwrap(exteria_faketls_reader *reader, const uint8_t *in, size_t in_len, uint8_t *out, size_t out_cap, size_t *out_len) {
    size_t at = 0, produced = 0;
    if (out_len) *out_len = 0;
    if (!reader || !out_len || (in_len && !in) || (in_len && !out) || out_cap < in_len) return EXTERIA_E_ARG;
    while (at < in_len) {
        if (reader->remaining == 0) {
            size_t n;
            reader->header[reader->header_len++] = in[at++];
            if (reader->header_len < sizeof(reader->header)) continue;
            reader->header_len = 0;
            reader->type = reader->header[0];
            if ((reader->type != 0x17 && reader->type != 0x14) || reader->header[1] != TLS_VERSION_MAJOR || reader->header[2] != TLS_VERSION_MINOR) return EXTERIA_E_MALFORMED;
            n = record_length(reader->header);
            if (n > EXTERIA_FAKETLS_PAYLOAD_MAX) return EXTERIA_E_MALFORMED;
            reader->remaining = (uint16_t)n;
            continue;
        }
        {
            size_t take = in_len - at < reader->remaining ? in_len - at : reader->remaining;
            if (reader->type == 0x17) {
                memcpy(out + produced, in + at, take);
                produced += take;
            }
            at += take;
            reader->remaining = (uint16_t)(reader->remaining - take);
        }
    }
    *out_len = produced;
    return EXTERIA_OK;
}

exteria_status exteria_faketls_wrap(const uint8_t *data, size_t len, exteria_writer *out) {
    if (!out || (len && !data)) return EXTERIA_E_ARG;
    while (len) {
        size_t chunk = len < EXTERIA_FAKETLS_RECORD_MAX ? len : EXTERIA_FAKETLS_RECORD_MAX;
        uint8_t header[5];
        exteria_status status;
        header[0] = 0x17;
        header[1] = TLS_VERSION_MAJOR;
        header[2] = TLS_VERSION_MINOR;
        header[3] = (uint8_t)(chunk >> 8);
        header[4] = (uint8_t)chunk;
        status = exteria_wr_bytes(out, header, sizeof(header));
        if (status == EXTERIA_OK) status = exteria_wr_bytes(out, data, chunk);
        if (status != EXTERIA_OK) return status;
        data += chunk;
        len -= chunk;
    }
    return EXTERIA_OK;
}
