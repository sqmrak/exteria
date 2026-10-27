#include "exteria_tgc_reflector.h"

#include <stdio.h>
#include <string.h>

#include "exteria_bytes.h"

#define SPECIAL_TAG_LEN 12
#define HELLO_MARKER_LEN 16

static void put_le32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static uint32_t get_be32(const uint8_t *p) {
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static uint32_t get_le32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

exteria_status exteria_tgc_reflector_init(exteria_tgc_reflector *r, uint8_t server_id, const uint8_t peer_tag[EXTERIA_TGC_PEER_TAG_LEN], uint32_t local_tag, int tcp) {
    if (!r) return EXTERIA_E_ARG;
    memset(r, 0, sizeof(*r));
    if (!peer_tag || server_id == 0 || local_tag == 0) return EXTERIA_E_ARG;
    r->server_id = server_id;
    memcpy(r->prefix, peer_tag, EXTERIA_TGC_TAG_PREFIX_LEN);
    r->local_tag = local_tag;
    r->tcp = tcp ? 1 : 0;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_reflector_hello(const exteria_tgc_reflector *r, uint8_t *out, size_t capacity, size_t *len) {
    size_t n = 0;
    if (len) *len = 0;
    if (!r || !out || !len) return EXTERIA_E_ARG;
    n = r->tcp ? EXTERIA_TGC_REFLECTOR_HELLO_TCP_LEN : EXTERIA_TGC_REFLECTOR_HELLO_UDP_LEN;
    if (capacity < n) return EXTERIA_E_LIMIT;
    memset(out, 0, n);
    memcpy(out, r->prefix, EXTERIA_TGC_TAG_PREFIX_LEN);
    put_le32(out + EXTERIA_TGC_TAG_PREFIX_LEN, r->local_tag);
    if (r->tcp) {
        /* the stream form carries a zero word after the tag */
        *len = n - 4;
        return EXTERIA_OK;
    }
    /* the ping: twelve 0xFF bytes, 0xFE, three 0xFF, and the number 123 in eight bytes, big endian */
    memset(out + 16, 0xFF, SPECIAL_TAG_LEN);
    out[28] = 0xFE;
    memset(out + 29, 0xFF, 3);
    out[39] = 123;
    *len = n;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_reflector_wrap(const exteria_tgc_reflector *r, uint32_t remote_tag, const uint8_t *payload, size_t len, uint8_t *out,
                                          size_t capacity, size_t *out_len) {
    size_t total;
    if (out_len) *out_len = 0;
    if (!r || !payload || !out || !out_len || remote_tag == 0) return EXTERIA_E_ARG;
    if (len == 0 || len > EXTERIA_TGC_REFLECTOR_MAX_PAYLOAD) return EXTERIA_E_LIMIT;
    total = (EXTERIA_TGC_REFLECTOR_WRAP_OVERHEAD + len + 3) & ~(size_t)3;
    if (capacity < total) return EXTERIA_E_LIMIT;
    memcpy(out, r->prefix, EXTERIA_TGC_TAG_PREFIX_LEN);
    put_le32(out + 12, remote_tag);
    put_le32(out + 16, r->local_tag);
    exteria_put_u32be(out + 20, (uint32_t)len);
    memcpy(out + 24, payload, len);
    memset(out + 24 + len, 0, total - 24 - len);
    *out_len = total;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_reflector_unwrap(exteria_tgc_reflector *r, const uint8_t *packet, size_t len, uint32_t *sender_tag, const uint8_t **payload,
                                            size_t *payload_len) {
    static const uint8_t special[SPECIAL_TAG_LEN] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    uint32_t size;
    if (sender_tag) *sender_tag = 0;
    if (payload) *payload = NULL;
    if (payload_len) *payload_len = 0;
    if (!r || !packet || !sender_tag || !payload || !payload_len) return EXTERIA_E_ARG;
    if (len < EXTERIA_TGC_PEER_TAG_LEN || memcmp(packet, r->prefix, EXTERIA_TGC_TAG_PREFIX_LEN) != 0) return EXTERIA_E_MALFORMED;
    r->ready = 1;
    if (len <= EXTERIA_TGC_REFLECTOR_WRAP_OVERHEAD) return EXTERIA_OK;
    /* a ping or the answer to a hello starts its body with twelve 0xFF bytes, which no sender tag and size make */
    if (len >= 16 + SPECIAL_TAG_LEN && memcmp(packet + 16, special, SPECIAL_TAG_LEN) == 0) return EXTERIA_OK;
    size = get_be32(packet + 20);
    if (size > len - EXTERIA_TGC_REFLECTOR_WRAP_OVERHEAD) return EXTERIA_E_MALFORMED;
    *sender_tag = get_le32(packet + 16);
    *payload = packet + EXTERIA_TGC_REFLECTOR_WRAP_OVERHEAD;
    *payload_len = size;
    if (size == 0 || *sender_tag == 0) {
        *payload = NULL;
        *payload_len = 0;
        *sender_tag = 0;
    }
    return EXTERIA_OK;
}

exteria_status exteria_tgc_reflector_host(uint8_t server_id, uint32_t tag, char *out, size_t capacity) {
    int n;
    if (!out || capacity == 0) return EXTERIA_E_ARG;
    out[0] = '\0';
    if (server_id == 0 || tag == 0) return EXTERIA_E_ARG;
    n = snprintf(out, capacity, "reflector-%u-%lu.reflector", (unsigned)server_id, (unsigned long)tag);
    if (n < 0 || (size_t)n >= capacity) {
        out[0] = '\0';
        return EXTERIA_E_LIMIT;
    }
    return EXTERIA_OK;
}

/* a decimal number of up to 10 digits that fits 32 bits, read from s up to the end or the stop character; returns the end position, NULL on a bad one */
static const char *read_decimal(const char *s, char stop, uint32_t *out) {
    uint64_t v = 0;
    size_t digits = 0;
    while (*s >= '0' && *s <= '9') {
        v = v * 10 + (uint64_t)(*s - '0');
        if (++digits > 10 || v > 0xFFFFFFFFull) return NULL;
        ++s;
    }
    if (digits == 0 || *s != stop) return NULL;
    *out = (uint32_t)v;
    return s;
}

exteria_status exteria_tgc_reflector_parse_host(const char *host, uint8_t *server_id, uint32_t *tag) {
    uint32_t id = 0, t = 0;
    const char *p;
    static const char prefix[] = "reflector-";
    static const char suffix[] = ".reflector";
    if (server_id) *server_id = 0;
    if (tag) *tag = 0;
    if (!host || !server_id || !tag) return EXTERIA_E_ARG;
    if (strncmp(host, prefix, sizeof(prefix) - 1) != 0) return EXTERIA_E_MALFORMED;
    p = read_decimal(host + sizeof(prefix) - 1, '-', &id);
    if (!p || id == 0 || id > 255) return EXTERIA_E_MALFORMED;
    p = read_decimal(p + 1, '.', &t);
    if (!p || t == 0 || strcmp(p, suffix) != 0) return EXTERIA_E_MALFORMED;
    *server_id = (uint8_t)id;
    *tag = t;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_reflector_candidate_sdp(const exteria_tgc_reflector *r, uint16_t port, uint32_t priority, const char *ufrag, char *out, size_t capacity) {
    char host[EXTERIA_TGC_REFLECTOR_HOST_MAX];
    int n;
    exteria_status status;
    if (out && capacity) out[0] = '\0';
    if (!r || !out || !ufrag || capacity == 0 || port == 0) return EXTERIA_E_ARG;
    status = exteria_tgc_reflector_host(r->server_id, r->local_tag, host, sizeof(host));
    if (status != EXTERIA_OK) return status;
    /* the foundation is the server id: candidates of one server share it, as ICE wants for candidates of one kind and base */
    n = snprintf(out, capacity, "candidate:%u 1 udp %lu %s %u typ relay generation 0 ufrag %s network-id 1 network-cost 10", (unsigned)r->server_id,
                 (unsigned long)priority, host, (unsigned)port, ufrag);
    if (n < 0 || (size_t)n >= capacity) {
        out[0] = '\0';
        return EXTERIA_E_LIMIT;
    }
    return EXTERIA_OK;
}

exteria_status exteria_tgc_reflector_parse_candidate(const char *sdp, uint8_t *server_id, uint32_t *tag, uint16_t *port, uint32_t *priority) {
    char fields[8][EXTERIA_TGC_REFLECTOR_HOST_MAX + 12];
    size_t count = 0;
    const char *p = sdp;
    uint32_t prio = 0, prt = 0, comp = 0;
    const char *foundation;
    if (server_id) *server_id = 0;
    if (tag) *tag = 0;
    if (port) *port = 0;
    if (priority) *priority = 0;
    if (!sdp || !server_id || !tag || !port || !priority) return EXTERIA_E_ARG;
    if (strlen(sdp) > 1024) return EXTERIA_E_MALFORMED;
    while (*p && count < 8) {
        size_t n = 0;
        while (*p == ' ' || *p == '\t') ++p;
        if (!*p) break;
        while (p[n] && p[n] != ' ' && p[n] != '\t') ++n;
        if (n >= sizeof(fields[0])) return EXTERIA_E_MALFORMED;
        memcpy(fields[count], p, n);
        fields[count][n] = '\0';
        ++count;
        p += n;
    }
    if (count < 8) return EXTERIA_E_MALFORMED;
    foundation = fields[0];
    if (strncmp(foundation, "a=", 2) == 0) foundation += 2;
    if (strncmp(foundation, "candidate:", 10) != 0 || foundation[10] == '\0') return EXTERIA_E_MALFORMED;
    if (!read_decimal(fields[1], '\0', &comp) || comp != 1) return EXTERIA_E_MALFORMED;
    if (strcmp(fields[2], "udp") != 0 && strcmp(fields[2], "UDP") != 0) return EXTERIA_E_MALFORMED;
    if (!read_decimal(fields[3], '\0', &prio)) return EXTERIA_E_MALFORMED;
    if (!read_decimal(fields[5], '\0', &prt) || prt == 0 || prt > 65535) return EXTERIA_E_MALFORMED;
    if (strcmp(fields[6], "typ") != 0 || strcmp(fields[7], "relay") != 0) return EXTERIA_E_MALFORMED;
    if (exteria_tgc_reflector_parse_host(fields[4], server_id, tag) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    *port = (uint16_t)prt;
    *priority = prio;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_reflector_server_ids(const int64_t *ids, size_t count, uint8_t *out) {
    size_t i, j;
    if (!out || (count && !ids)) return EXTERIA_E_ARG;
    if (count > 255) return EXTERIA_E_LIMIT;
    for (i = 0; i < count; ++i) {
        size_t rank = 1;
        for (j = 0; j < count; ++j) {
            if (ids[j] < ids[i]) ++rank;
        }
        out[i] = (uint8_t)rank;
    }
    return EXTERIA_OK;
}

exteria_status exteria_tgc_tcp_frame(const uint8_t *packet, size_t len, int first, uint8_t *out, size_t capacity, size_t *out_len) {
    size_t at = 0;
    if (out_len) *out_len = 0;
    if (!packet || !out || !out_len) return EXTERIA_E_ARG;
    if (len == 0 || len >= EXTERIA_TGC_TCP_MAX_FRAME) return EXTERIA_E_LIMIT;
    if (capacity < (first ? 4u : 0u) + 4 + len) return EXTERIA_E_LIMIT;
    if (first) {
        put_le32(out, EXTERIA_TGC_TCP_PROLOGUE);
        at = 4;
    }
    put_le32(out + at, (uint32_t)len);
    memcpy(out + at + 4, packet, len);
    *out_len = at + 4 + len;
    return EXTERIA_OK;
}

static void compact(exteria_tgc_tcp_reader *rd) {
    if (rd->pending == 0) return;
    memmove(rd->buf, rd->buf + rd->pending, rd->used - rd->pending);
    rd->used -= rd->pending;
    rd->pending = 0;
}

exteria_status exteria_tgc_tcp_reader_push(exteria_tgc_tcp_reader *rd, const uint8_t *data, size_t len) {
    if (!rd || (len && !data)) return EXTERIA_E_ARG;
    compact(rd);
    if (len > sizeof(rd->buf) - rd->used) return EXTERIA_E_LIMIT;
    memcpy(rd->buf + rd->used, data, len);
    rd->used += len;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_tcp_reader_next(exteria_tgc_tcp_reader *rd, const uint8_t **frame, size_t *len) {
    uint32_t n;
    if (frame) *frame = NULL;
    if (len) *len = 0;
    if (!rd || !frame || !len) return EXTERIA_E_ARG;
    /* the frame handed out last time is dropped now, so its bytes stayed valid for the caller until this call */
    compact(rd);
    if (rd->used < 4) return EXTERIA_E_RETRY;
    n = get_le32(rd->buf);
    if (n == 0 || n >= EXTERIA_TGC_TCP_MAX_FRAME) return EXTERIA_E_MALFORMED;
    if (rd->used < 4 + (size_t)n) return EXTERIA_E_RETRY;
    *frame = rd->buf + 4;
    *len = n;
    rd->pending = 4 + (size_t)n;
    return EXTERIA_OK;
}
