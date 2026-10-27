#include "exteria_tgc_stun.h"

#include <string.h>

#include "exteria_bytes.h"
#include "exteria_crypto.h"

#define MAGIC_COOKIE 0x2112A442u
#define ATTR_MAPPED_ADDRESS 0x0001
#define ATTR_USERNAME 0x0006
#define ATTR_MESSAGE_INTEGRITY 0x0008
#define ATTR_ERROR_CODE 0x0009
#define ATTR_UNKNOWN_ATTRIBUTES 0x000A
#define ATTR_REALM 0x0014
#define ATTR_NONCE 0x0015
#define ATTR_XOR_MAPPED_ADDRESS 0x0020
#define ATTR_PRIORITY 0x0024
#define ATTR_USE_CANDIDATE 0x0025
#define ATTR_FINGERPRINT 0x8028
#define ATTR_ICE_CONTROLLED 0x8029
#define ATTR_ICE_CONTROLLING 0x802A
#define FINGERPRINT_XOR 0x5354554Eu
#define INTEGRITY_LEN 20

static uint16_t be16(const uint8_t *p) {
    return (uint16_t)((unsigned)p[0] << 8 | p[1]);
}

static uint32_t be32(const uint8_t *p) {
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static uint64_t be64(const uint8_t *p) {
    return (uint64_t)be32(p) << 32 | be32(p + 4);
}

static void put16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)v;
}

static void put64(uint8_t *p, uint64_t v) {
    exteria_put_u32be(p, (uint32_t)(v >> 32));
    exteria_put_u32be(p + 4, (uint32_t)v);
}

uint32_t exteria_stun_crc32(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    size_t i;
    int bit;
    for (i = 0; i < len; ++i) {
        crc ^= data[i];
        for (bit = 0; bit < 8; ++bit) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

int exteria_stun_looks_like(const uint8_t *data, size_t len) {
    return data && len >= EXTERIA_STUN_HEADER_LEN && (data[0] & 0xC0) == 0 && be32(data + 4) == MAGIC_COOKIE && ((len - EXTERIA_STUN_HEADER_LEN) % 4) == 0;
}

static int known_comprehension_required(uint16_t type) {
    switch (type) {
    case ATTR_MAPPED_ADDRESS:
    case ATTR_USERNAME:
    case ATTR_MESSAGE_INTEGRITY:
    case ATTR_ERROR_CODE:
    case ATTR_UNKNOWN_ATTRIBUTES:
    case ATTR_REALM:
    case ATTR_NONCE:
    case ATTR_XOR_MAPPED_ADDRESS:
    case ATTR_PRIORITY:
    case ATTR_USE_CANDIDATE:
        return 1;
    default:
        return 0;
    }
}

exteria_status exteria_stun_parse(const uint8_t *data, size_t len, exteria_stun *out) {
    size_t pos, body;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!data) return EXTERIA_E_ARG;
    if (!exteria_stun_looks_like(data, len)) return EXTERIA_E_MALFORMED;
    body = be16(data + 2);
    if (body != len - EXTERIA_STUN_HEADER_LEN) return EXTERIA_E_MALFORMED;
    out->type = be16(data);
    memcpy(out->txid, data + 8, EXTERIA_STUN_TXID_LEN);
    pos = EXTERIA_STUN_HEADER_LEN;
    while (pos < len) {
        uint16_t type, alen;
        const uint8_t *v;
        size_t padded;
        if (len - pos < 4) goto bad;
        type = be16(data + pos);
        alen = be16(data + pos + 2);
        padded = ((size_t)alen + 3) & ~(size_t)3;
        if (padded > len - pos - 4) goto bad;
        v = data + pos + 4;
        /* nothing after the integrity attribute counts but the fingerprint */
        if (out->integrity_offset && type != ATTR_FINGERPRINT) {
            pos += 4 + padded;
            continue;
        }
        switch (type) {
        case ATTR_USERNAME:
            if (alen == 0 || alen > EXTERIA_STUN_MAX_USERNAME) goto bad;
            memcpy(out->username, v, alen);
            out->username[alen] = '\0';
            out->has_username = 1;
            break;
        case ATTR_PRIORITY:
            if (alen != 4) goto bad;
            out->priority = be32(v);
            out->has_priority = 1;
            break;
        case ATTR_USE_CANDIDATE:
            if (alen != 0) goto bad;
            out->use_candidate = 1;
            break;
        case ATTR_ICE_CONTROLLING:
            if (alen != 8) goto bad;
            out->controlling = be64(v);
            out->has_controlling = 1;
            break;
        case ATTR_ICE_CONTROLLED:
            if (alen != 8) goto bad;
            out->controlled = be64(v);
            out->has_controlled = 1;
            break;
        case ATTR_XOR_MAPPED_ADDRESS:
        case ATTR_MAPPED_ADDRESS: {
            int ipv6;
            size_t addr_len, i;
            uint8_t mask[16];
            if (alen < 8 || v[1] != 1 + (alen == 20 ? 1 : 0)) goto bad;
            ipv6 = v[1] == 2;
            addr_len = ipv6 ? 16 : 4;
            if (alen != 4 + addr_len) goto bad;
            if (type == ATTR_XOR_MAPPED_ADDRESS || !out->has_mapped) {
                exteria_put_u32be(mask, MAGIC_COOKIE);
                memcpy(mask + 4, out->txid, EXTERIA_STUN_TXID_LEN);
                out->mapped_ipv6 = (uint8_t)ipv6;
                out->mapped_port = be16(v + 2);
                memcpy(out->mapped_address, v + 4, addr_len);
                if (type == ATTR_XOR_MAPPED_ADDRESS) {
                    out->mapped_port = (uint16_t)(out->mapped_port ^ (MAGIC_COOKIE >> 16));
                    for (i = 0; i < addr_len; ++i) out->mapped_address[i] ^= mask[i];
                }
                out->has_mapped = 1;
            }
            break;
        }
        case ATTR_ERROR_CODE:
            if (alen < 4) goto bad;
            out->error_code = (uint16_t)((v[2] & 7) * 100 + v[3]);
            out->has_error = 1;
            break;
        case ATTR_MESSAGE_INTEGRITY:
            if (alen != INTEGRITY_LEN) goto bad;
            out->integrity_offset = (uint16_t)pos;
            break;
        case ATTR_FINGERPRINT:
            if (alen != 4) goto bad;
            out->fingerprint_offset = (uint16_t)pos;
            break;
        default:
            if (type < 0x8000 && !known_comprehension_required(type)) goto bad;
            break;
        }
        pos += 4 + padded;
    }
    return EXTERIA_OK;
bad:
    memset(out, 0, sizeof(*out));
    return EXTERIA_E_MALFORMED;
}

/* the attributes after the one being checked do not count, and the length field in the header is taken as if the message ended with that attribute */
static exteria_status checked_copy_hash(const uint8_t *data, size_t offset, size_t attr_len, const uint8_t *key, size_t key_len, uint8_t mac[EXTERIA_SHA1_LEN]) {
    uint8_t head[EXTERIA_STUN_HEADER_LEN];
    exteria_slice parts[2];
    memcpy(head, data, sizeof(head));
    put16(head + 2, (uint16_t)(offset - EXTERIA_STUN_HEADER_LEN + attr_len));
    parts[0].data = head;
    parts[0].len = sizeof(head);
    parts[1].data = data + EXTERIA_STUN_HEADER_LEN;
    parts[1].len = offset - EXTERIA_STUN_HEADER_LEN;
    return exteria_hmac_sha1(key, key_len, parts, 2, mac);
}

exteria_status exteria_stun_check_integrity(const uint8_t *data, size_t len, const exteria_stun *m, const uint8_t *key, size_t key_len) {
    uint8_t mac[EXTERIA_SHA1_LEN], diff = 0;
    size_t i;
    exteria_status status;
    if (!data || !m || !key || key_len == 0) return EXTERIA_E_ARG;
    if (m->integrity_offset == 0) return EXTERIA_E_NOTFOUND;
    if ((size_t)m->integrity_offset + 4 + INTEGRITY_LEN > len) return EXTERIA_E_MALFORMED;
    status = checked_copy_hash(data, m->integrity_offset, 4 + INTEGRITY_LEN, key, key_len, mac);
    if (status != EXTERIA_OK) return status;
    for (i = 0; i < INTEGRITY_LEN; ++i) diff |= (uint8_t)(mac[i] ^ data[m->integrity_offset + 4 + i]);
    return diff == 0 ? EXTERIA_OK : EXTERIA_E_SECURITY;
}

exteria_status exteria_stun_check_fingerprint(const uint8_t *data, size_t len, const exteria_stun *m) {
    uint8_t head[EXTERIA_STUN_HEADER_LEN];
    uint32_t crc;
    if (!data || !m) return EXTERIA_E_ARG;
    if (m->fingerprint_offset == 0) return EXTERIA_E_NOTFOUND;
    if ((size_t)m->fingerprint_offset + 8 > len) return EXTERIA_E_MALFORMED;
    /* the crc runs over the header with its length as if the message ended at the fingerprint, then the attributes before it */
    memcpy(head, data, sizeof(head));
    put16(head + 2, (uint16_t)(m->fingerprint_offset - EXTERIA_STUN_HEADER_LEN + 8));
    {
        uint8_t buf[EXTERIA_STUN_MAX_MESSAGE];
        size_t before = m->fingerprint_offset;
        if (before > sizeof(buf)) return EXTERIA_E_LIMIT;
        memcpy(buf, head, sizeof(head));
        memcpy(buf + sizeof(head), data + EXTERIA_STUN_HEADER_LEN, before - EXTERIA_STUN_HEADER_LEN);
        crc = exteria_stun_crc32(buf, before) ^ FINGERPRINT_XOR;
    }
    return crc == be32(data + m->fingerprint_offset + 4) ? EXTERIA_OK : EXTERIA_E_SECURITY;
}

typedef struct writer {
    uint8_t *buf;
    size_t cap;
    size_t len;
    int overflow;
} writer;

static uint8_t *take(writer *w, size_t n) {
    uint8_t *p;
    if (w->overflow || n > w->cap - w->len) {
        w->overflow = 1;
        return NULL;
    }
    p = w->buf + w->len;
    w->len += n;
    return p;
}

static void put_attr(writer *w, uint16_t type, const uint8_t *value, size_t len) {
    uint8_t *p = take(w, 4 + ((len + 3) & ~(size_t)3));
    if (!p) return;
    put16(p, type);
    put16(p + 2, (uint16_t)len);
    if (len) memcpy(p + 4, value, len);
    memset(p + 4 + len, 0, ((len + 3) & ~(size_t)3) - len);
}

exteria_status exteria_stun_write(const exteria_stun *m, const uint8_t *key, size_t key_len, int with_fingerprint, uint8_t *out, size_t capacity,
                                  size_t *len) {
    writer w;
    uint8_t *head;
    uint8_t tmp[20];
    if (len) *len = 0;
    if (!m || !out || !len) return EXTERIA_E_ARG;
    if (capacity > EXTERIA_STUN_MAX_MESSAGE) capacity = EXTERIA_STUN_MAX_MESSAGE;
    w.buf = out;
    w.cap = capacity;
    w.len = 0;
    w.overflow = 0;
    head = take(&w, EXTERIA_STUN_HEADER_LEN);
    if (!head) return EXTERIA_E_LIMIT;
    put16(head, m->type);
    put16(head + 2, 0);
    exteria_put_u32be(head + 4, MAGIC_COOKIE);
    memcpy(head + 8, m->txid, EXTERIA_STUN_TXID_LEN);
    if (m->has_username) {
        size_t n = strlen(m->username);
        if (n == 0 || n > EXTERIA_STUN_MAX_USERNAME) return EXTERIA_E_ARG;
        put_attr(&w, ATTR_USERNAME, (const uint8_t *)m->username, n);
    }
    if (m->has_mapped) {
        size_t addr_len = m->mapped_ipv6 ? 16 : 4, i;
        uint8_t value[20], mask[16];
        exteria_put_u32be(mask, MAGIC_COOKIE);
        memcpy(mask + 4, m->txid, EXTERIA_STUN_TXID_LEN);
        value[0] = 0;
        value[1] = (uint8_t)(m->mapped_ipv6 ? 2 : 1);
        put16(value + 2, (uint16_t)(m->mapped_port ^ (MAGIC_COOKIE >> 16)));
        for (i = 0; i < addr_len; ++i) value[4 + i] = (uint8_t)(m->mapped_address[i] ^ mask[i]);
        put_attr(&w, ATTR_XOR_MAPPED_ADDRESS, value, 4 + addr_len);
    }
    if (m->has_error) {
        uint8_t value[4];
        value[0] = 0;
        value[1] = 0;
        value[2] = (uint8_t)(m->error_code / 100);
        value[3] = (uint8_t)(m->error_code % 100);
        put_attr(&w, ATTR_ERROR_CODE, value, sizeof(value));
    }
    if (m->has_priority) {
        exteria_put_u32be(tmp, m->priority);
        put_attr(&w, ATTR_PRIORITY, tmp, 4);
    }
    if (m->has_controlling) {
        put64(tmp, m->controlling);
        put_attr(&w, ATTR_ICE_CONTROLLING, tmp, 8);
    }
    if (m->has_controlled) {
        put64(tmp, m->controlled);
        put_attr(&w, ATTR_ICE_CONTROLLED, tmp, 8);
    }
    if (m->use_candidate) put_attr(&w, ATTR_USE_CANDIDATE, NULL, 0);
    if (w.overflow) return EXTERIA_E_LIMIT;
    if (key) {
        uint8_t mac[EXTERIA_SHA1_LEN];
        exteria_status status;
        uint8_t *attr;
        put16(out + 2, (uint16_t)(w.len - EXTERIA_STUN_HEADER_LEN + 4 + INTEGRITY_LEN));
        status = checked_copy_hash(out, w.len, 4 + INTEGRITY_LEN, key, key_len, mac);
        if (status != EXTERIA_OK) return status;
        attr = take(&w, 4 + INTEGRITY_LEN);
        if (!attr) return EXTERIA_E_LIMIT;
        put16(attr, ATTR_MESSAGE_INTEGRITY);
        put16(attr + 2, INTEGRITY_LEN);
        memcpy(attr + 4, mac, INTEGRITY_LEN);
    }
    if (with_fingerprint) {
        uint8_t *attr;
        uint32_t crc;
        put16(out + 2, (uint16_t)(w.len - EXTERIA_STUN_HEADER_LEN + 8));
        crc = exteria_stun_crc32(out, w.len) ^ FINGERPRINT_XOR;
        attr = take(&w, 8);
        if (!attr) return EXTERIA_E_LIMIT;
        put16(attr, ATTR_FINGERPRINT);
        put16(attr + 2, 4);
        exteria_put_u32be(attr + 4, crc);
    }
    put16(out + 2, (uint16_t)(w.len - EXTERIA_STUN_HEADER_LEN));
    *len = w.len;
    return EXTERIA_OK;
}
