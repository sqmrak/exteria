#include "exteria_dns.h"

#include <string.h>

#define HEADER_LEN 12
#define TYPE_A 1
#define CLASS_IN 1
#define LABEL_MAX 63
#define NAME_MAX 253
#define RECORDS_MAX 64
#define NAME_STEPS_MAX 128

static int name_char(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_';
}

exteria_status exteria_dns_query_a(const char *host, uint16_t id, uint8_t *out, size_t cap, size_t *len) {
    size_t host_len, at = HEADER_LEN, label_start, i;
    if (len) *len = 0;
    if (!host || !out || !len) return EXTERIA_E_ARG;
    host_len = strlen(host);
    if (host_len > 0 && host[host_len - 1] == '.') --host_len;
    if (host_len == 0 || host_len > NAME_MAX) return EXTERIA_E_ARG;
    if (cap < HEADER_LEN + host_len + 2 + 4) return EXTERIA_E_LIMIT;
    memset(out, 0, HEADER_LEN);
    out[0] = (uint8_t)(id >> 8);
    out[1] = (uint8_t)id;
    out[2] = 0x01; /* recursion desired */
    out[5] = 1;    /* one question */
    label_start = at++;
    for (i = 0; i <= host_len; ++i) {
        if (i == host_len || host[i] == '.') {
            size_t label = at - label_start - 1;
            if (label == 0 || label > LABEL_MAX) return EXTERIA_E_ARG;
            out[label_start] = (uint8_t)label;
            label_start = at++;
            continue;
        }
        if (!name_char((unsigned char)host[i])) return EXTERIA_E_ARG;
        out[at++] = (uint8_t)host[i];
    }
    /* the last label start is the terminating zero */
    out[label_start] = 0;
    at = label_start + 1;
    if (cap < at + 4) return EXTERIA_E_LIMIT;
    out[at++] = 0;
    out[at++] = TYPE_A;
    out[at++] = 0;
    out[at++] = CLASS_IN;
    *len = at;
    return EXTERIA_OK;
}

/* the position after a name that starts at pos: its labels, or a pointer, which ends it; the pointer is not followed, since nothing here
   needs the words */
static exteria_status skip_name(const uint8_t *msg, size_t len, size_t pos, size_t *next) {
    unsigned steps;
    for (steps = 0; steps < NAME_STEPS_MAX; ++steps) {
        uint8_t b;
        if (pos >= len) return EXTERIA_E_MALFORMED;
        b = msg[pos];
        if (b == 0) {
            *next = pos + 1;
            return EXTERIA_OK;
        }
        if ((b & 0xC0u) == 0xC0u) {
            if (pos + 2 > len) return EXTERIA_E_MALFORMED;
            *next = pos + 2;
            return EXTERIA_OK;
        }
        if ((b & 0xC0u) != 0) return EXTERIA_E_MALFORMED;
        if (pos + 1 + b > len) return EXTERIA_E_MALFORMED;
        pos += 1u + b;
    }
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_dns_answer_a(const uint8_t *msg, size_t len, uint16_t id, uint32_t *ip, uint32_t *ttl) {
    unsigned flags, questions, answers, i;
    size_t pos = HEADER_LEN;
    exteria_status status;
    if (ip) *ip = 0;
    if (ttl) *ttl = 0;
    if (!msg || !ip || !ttl) return EXTERIA_E_ARG;
    if (len < HEADER_LEN || len > EXTERIA_DNS_ANSWER_MAX) return EXTERIA_E_MALFORMED;
    if ((unsigned)((msg[0] << 8) | msg[1]) != id) return EXTERIA_E_MALFORMED;
    flags = (unsigned)((msg[2] << 8) | msg[3]);
    if (!(flags & 0x8000u)) return EXTERIA_E_MALFORMED;
    if (flags & 0x0200u) return EXTERIA_E_RETRY;
    switch (flags & 0x000Fu) {
    case 0: break;
    case 3: return EXTERIA_E_NOTFOUND;
    default: return EXTERIA_E_IO;
    }
    questions = (unsigned)((msg[4] << 8) | msg[5]);
    answers = (unsigned)((msg[6] << 8) | msg[7]);
    if (questions != 1 || answers > RECORDS_MAX) return EXTERIA_E_MALFORMED;
    status = skip_name(msg, len, pos, &pos);
    if (status != EXTERIA_OK) return status;
    if (pos + 4 > len) return EXTERIA_E_MALFORMED;
    pos += 4;
    for (i = 0; i < answers; ++i) {
        unsigned type, klass, rdlen;
        uint32_t life;
        status = skip_name(msg, len, pos, &pos);
        if (status != EXTERIA_OK) return status;
        if (pos + 10 > len) return EXTERIA_E_MALFORMED;
        type = (unsigned)((msg[pos] << 8) | msg[pos + 1]);
        klass = (unsigned)((msg[pos + 2] << 8) | msg[pos + 3]);
        life = ((uint32_t)msg[pos + 4] << 24) | ((uint32_t)msg[pos + 5] << 16) | ((uint32_t)msg[pos + 6] << 8) | msg[pos + 7];
        rdlen = (unsigned)((msg[pos + 8] << 8) | msg[pos + 9]);
        pos += 10;
        if (pos + rdlen > len) return EXTERIA_E_MALFORMED;
        if (type == TYPE_A && klass == CLASS_IN && rdlen == 4) {
            *ip = ((uint32_t)msg[pos] << 24) | ((uint32_t)msg[pos + 1] << 16) | ((uint32_t)msg[pos + 2] << 8) | msg[pos + 3];
            *ttl = life;
            return EXTERIA_OK;
        }
        pos += rdlen;
    }
    return EXTERIA_E_NOTFOUND;
}
