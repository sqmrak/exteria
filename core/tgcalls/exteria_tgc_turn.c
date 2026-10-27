#include "exteria_tgc_turn.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "exteria_bytes.h"
#include "exteria_crypto.h"
#include "exteria_random.h"

#define MAGIC_COOKIE 0x2112A442u
#define HEADER_LEN 20

#define TYPE_ALLOCATE 0x0003
#define TYPE_REFRESH 0x0004
#define TYPE_SEND 0x0016
#define TYPE_DATA 0x0017
#define TYPE_CREATE_PERMISSION 0x0008

#define ATTR_USERNAME 0x0006
#define ATTR_MESSAGE_INTEGRITY 0x0008
#define ATTR_ERROR_CODE 0x0009
#define ATTR_LIFETIME 0x000D
#define ATTR_XOR_PEER_ADDRESS 0x0012
#define ATTR_DATA 0x0013
#define ATTR_REALM 0x0014
#define ATTR_NONCE 0x0015
#define ATTR_XOR_RELAYED_ADDRESS 0x0016
#define ATTR_REQUESTED_TRANSPORT 0x0019
#define ATTR_XOR_MAPPED_ADDRESS 0x0020

#define KIND_ALLOCATE 1
#define KIND_REFRESH 2
#define KIND_PERMISSION 3

#define RTO_BASE_MS 500
#define MAX_TRIES 6
#define DEFAULT_LIFETIME_S 600
#define LIFETIME_ASKED_S 600
/* a permission lasts five minutes (RFC 5766 section 8), so it is asked for again after four */
#define PERMISSION_RENEW_MS 240000

enum { PERMISSION_WANTED = 0, PERMISSION_ASKED = 1, PERMISSION_GRANTED = 2, PERMISSION_REFUSED = 3 };

static void trace(const exteria_tgc_turn *t, const char *format, ...) {
    char line[200];
    va_list args;
    if (!t->events.trace) return;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    t->events.trace(t->events.context, line);
}

static uint16_t be16(const uint8_t *p) {
    return (uint16_t)((unsigned)p[0] << 8 | p[1]);
}

static void put16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)v;
}

exteria_status exteria_tgc_turn_init(exteria_tgc_turn *t, uint32_t server_ip, uint16_t server_port, const char *username, const char *password,
                                     const exteria_tgc_turn_events *events) {
    if (!t) return EXTERIA_E_ARG;
    memset(t, 0, sizeof(*t));
    if (server_ip == 0 || server_port == 0 || !username || !password || !events || !events->send) return EXTERIA_E_ARG;
    if (!username[0] || strlen(username) >= sizeof(t->username) || strlen(password) >= sizeof(t->password)) return EXTERIA_E_ARG;
    t->events = *events;
    t->server_ip = server_ip;
    t->server_port = server_port;
    memcpy(t->username, username, strlen(username) + 1);
    memcpy(t->password, password, strlen(password) + 1);
    t->state = EXTERIA_TGC_TURN_IDLE;
    return EXTERIA_OK;
}

typedef struct writer {
    uint8_t *buf;
    size_t cap;
    size_t len;
    int overflow;
} writer;

static void begin(writer *w, uint8_t *buf, size_t cap, uint16_t type, const uint8_t txid[12]) {
    w->buf = buf;
    w->cap = cap;
    w->len = HEADER_LEN;
    w->overflow = cap < HEADER_LEN;
    if (w->overflow) return;
    put16(buf, type);
    put16(buf + 2, 0);
    exteria_put_u32be(buf + 4, MAGIC_COOKIE);
    memcpy(buf + 8, txid, 12);
}

static void attr(writer *w, uint16_t type, const uint8_t *value, size_t len) {
    size_t padded = (len + 3) & ~(size_t)3;
    if (w->overflow || 4 + padded > w->cap - w->len) {
        w->overflow = 1;
        return;
    }
    put16(w->buf + w->len, type);
    put16(w->buf + w->len + 2, (uint16_t)len);
    if (len) memcpy(w->buf + w->len + 4, value, len);
    memset(w->buf + w->len + 4 + len, 0, padded - len);
    w->len += 4 + padded;
}

static void xor_address(writer *w, uint16_t type, const uint8_t txid[12], uint32_t ip, uint16_t port) {
    uint8_t value[8];
    (void)txid;
    value[0] = 0;
    value[1] = 1;
    put16(value + 2, (uint16_t)(port ^ (MAGIC_COOKIE >> 16)));
    exteria_put_u32be(value + 4, ip ^ MAGIC_COOKIE);
    attr(w, type, value, sizeof(value));
}

/* the long term credential: the key is the MD5 of "username:realm:password" (RFC 5389 section 15.4) */
static exteria_status make_key(exteria_tgc_turn *t) {
    char text[EXTERIA_TGC_TURN_USERNAME_MAX + EXTERIA_TGC_TURN_REALM_MAX + EXTERIA_TGC_TURN_PASSWORD_MAX + 2];
    exteria_slice part;
    int n = snprintf(text, sizeof(text), "%s:%s:%s", t->username, t->realm, t->password);
    if (n < 0 || (size_t)n >= sizeof(text)) return EXTERIA_E_LIMIT;
    part.data = (const uint8_t *)text;
    part.len = (size_t)n;
    t->has_key = exteria_md5(&part, 1, t->key) == EXTERIA_OK;
    exteria_wipe(text, sizeof(text));
    return t->has_key ? EXTERIA_OK : EXTERIA_E_CRYPTO;
}

/* MESSAGE-INTEGRITY over the message so far, with the length field as if the attribute were already in (RFC 5389 section 15.4) */
static void integrity(exteria_tgc_turn *t, writer *w) {
    uint8_t mac[EXTERIA_SHA1_LEN];
    exteria_slice part;
    if (w->overflow) return;
    put16(w->buf + 2, (uint16_t)(w->len - HEADER_LEN + 4 + EXTERIA_SHA1_LEN));
    part.data = w->buf;
    part.len = w->len;
    if (exteria_hmac_sha1(t->key, sizeof(t->key), &part, 1, mac) != EXTERIA_OK) {
        w->overflow = 1;
        return;
    }
    attr(w, ATTR_MESSAGE_INTEGRITY, mac, sizeof(mac));
}

static void credentials(exteria_tgc_turn *t, writer *w) {
    attr(w, ATTR_USERNAME, (const uint8_t *)t->username, strlen(t->username));
    attr(w, ATTR_REALM, (const uint8_t *)t->realm, strlen(t->realm));
    attr(w, ATTR_NONCE, t->nonce, t->nonce_len);
}

/* builds the message of a request into its slot with a new transaction id */
static exteria_status build(exteria_tgc_turn *t, exteria_tgc_turn_request *r) {
    writer w;
    uint8_t value[4];
    uint16_t type = r->kind == KIND_ALLOCATE ? TYPE_ALLOCATE : (r->kind == KIND_REFRESH ? TYPE_REFRESH : TYPE_CREATE_PERMISSION);
    exteria_status status = exteria_random(r->txid, sizeof(r->txid));
    if (status != EXTERIA_OK) return status;
    begin(&w, r->message, sizeof(r->message), type, r->txid);
    if (r->kind == KIND_ALLOCATE) {
        value[0] = 17;
        value[1] = value[2] = value[3] = 0;
        attr(&w, ATTR_REQUESTED_TRANSPORT, value, sizeof(value));
    } else if (r->kind == KIND_REFRESH) {
        exteria_put_u32be(value, LIFETIME_ASKED_S);
        attr(&w, ATTR_LIFETIME, value, sizeof(value));
    } else {
        xor_address(&w, ATTR_XOR_PEER_ADDRESS, r->txid, t->permissions[r->permission].ip, 0);
    }
    r->authenticated = t->has_key ? 1 : 0;
    if (t->has_key) {
        credentials(t, &w);
        integrity(t, &w);
    }
    if (w.overflow) return EXTERIA_E_LIMIT;
    put16(w.buf + 2, (uint16_t)(w.len - HEADER_LEN));
    r->len = (uint16_t)w.len;
    return EXTERIA_OK;
}

static void transmit(exteria_tgc_turn *t, exteria_tgc_turn_request *r, uint64_t now_ms) {
    r->last_tx_ms = now_ms;
    ++r->tries;
    t->events.send(t->events.context, r->message, r->len);
}

static exteria_tgc_turn_request *start_request(exteria_tgc_turn *t, unsigned kind, unsigned permission, uint64_t now_ms) {
    size_t i;
    for (i = 0; i < EXTERIA_TGC_TURN_MAX_REQUESTS; ++i) {
        exteria_tgc_turn_request *r = &t->requests[i];
        if (r->used) continue;
        memset(r, 0, sizeof(*r));
        r->used = 1;
        r->kind = (uint8_t)kind;
        r->permission = (uint8_t)permission;
        if (build(t, r) != EXTERIA_OK) {
            r->used = 0;
            return NULL;
        }
        transmit(t, r, now_ms);
        return r;
    }
    return NULL;
}

static void fail(exteria_tgc_turn *t, const char *why) {
    if (t->state == EXTERIA_TGC_TURN_FAILED) return;
    trace(t, "turn server %u.%u.%u.%u:%u failed: %s", (unsigned)(t->server_ip >> 24), (unsigned)(t->server_ip >> 16 & 255), (unsigned)(t->server_ip >> 8 & 255),
          (unsigned)(t->server_ip & 255), (unsigned)t->server_port, why);
    t->state = EXTERIA_TGC_TURN_FAILED;
}

void exteria_tgc_turn_tick(exteria_tgc_turn *t, uint64_t now_ms) {
    size_t i;
    if (!t || t->state == EXTERIA_TGC_TURN_FAILED) return;
    if (!t->started) {
        t->started = 1;
        t->state = EXTERIA_TGC_TURN_ALLOCATING;
        if (!start_request(t, KIND_ALLOCATE, 0, now_ms)) fail(t, "the request could not be made");
        return;
    }
    for (i = 0; i < EXTERIA_TGC_TURN_MAX_REQUESTS; ++i) {
        exteria_tgc_turn_request *r = &t->requests[i];
        unsigned shift;
        if (!r->used) continue;
        shift = r->tries > 0 ? (unsigned)r->tries - 1u : 0u;
        if (shift > 4) shift = 4;
        if (now_ms - r->last_tx_ms < (uint64_t)RTO_BASE_MS << shift) continue;
        if (r->tries >= MAX_TRIES) {
            r->used = 0;
            if (r->kind == KIND_PERMISSION) {
                t->permissions[r->permission].state = PERMISSION_REFUSED;
                trace(t, "turn permission for %u.%u.%u.%u got no answer", (unsigned)(t->permissions[r->permission].ip >> 24),
                      (unsigned)(t->permissions[r->permission].ip >> 16 & 255), (unsigned)(t->permissions[r->permission].ip >> 8 & 255),
                      (unsigned)(t->permissions[r->permission].ip & 255));
            } else {
                fail(t, "no answer");
            }
            continue;
        }
        transmit(t, r, now_ms);
    }
    if (t->state != EXTERIA_TGC_TURN_READY) return;
    if (now_ms >= t->refresh_due_ms) {
        t->refresh_due_ms = now_ms + 60000;
        (void)start_request(t, KIND_REFRESH, 0, now_ms);
    }
    for (i = 0; i < EXTERIA_TGC_TURN_MAX_PERMISSIONS; ++i) {
        exteria_tgc_turn_permission *p = &t->permissions[i];
        if (p->ip == 0) continue;
        if (p->state == PERMISSION_GRANTED && !p->renewing && now_ms - p->granted_ms >= PERMISSION_RENEW_MS) {
            p->renewing = 1;
            (void)start_request(t, KIND_PERMISSION, (unsigned)i, now_ms);
        } else if (p->state == PERMISSION_WANTED) {
            if (start_request(t, KIND_PERMISSION, (unsigned)i, now_ms)) p->state = PERMISSION_ASKED;
        }
    }
}

typedef struct reading {
    uint16_t type;
    uint8_t txid[12];
    int has_error;
    uint16_t error_code;
    int has_realm;
    char realm[EXTERIA_TGC_TURN_REALM_MAX];
    int has_nonce;
    uint8_t nonce[EXTERIA_TGC_TURN_NONCE_MAX];
    size_t nonce_len;
    int has_relayed, has_mapped, has_lifetime, has_peer, has_data;
    uint32_t relayed_ip, mapped_ip, peer_ip, lifetime;
    uint16_t relayed_port, mapped_port, peer_port;
    const uint8_t *data;
    size_t data_len;
    size_t integrity_offset;
} reading;

static int read_xor(const uint8_t *v, size_t alen, uint32_t *ip, uint16_t *port) {
    if (alen != 8 || v[1] != 1) return 0;
    *port = (uint16_t)(be16(v + 2) ^ (MAGIC_COOKIE >> 16));
    *ip = (uint32_t)v[4] << 24 | (uint32_t)v[5] << 16 | (uint32_t)v[6] << 8 | v[7];
    *ip ^= MAGIC_COOKIE;
    return 1;
}

static exteria_status read_message(const uint8_t *data, size_t len, reading *out) {
    size_t pos = HEADER_LEN;
    memset(out, 0, sizeof(*out));
    if (len < HEADER_LEN || (data[0] & 0xC0) != 0 || be16(data + 2) != len - HEADER_LEN || ((len - HEADER_LEN) & 3) != 0) return EXTERIA_E_MALFORMED;
    if (exteria_get_u32be(data + 4) != MAGIC_COOKIE) return EXTERIA_E_MALFORMED;
    out->type = be16(data);
    memcpy(out->txid, data + 8, 12);
    while (pos < len) {
        uint16_t type, alen;
        size_t padded;
        const uint8_t *v;
        if (len - pos < 4) return EXTERIA_E_MALFORMED;
        type = be16(data + pos);
        alen = be16(data + pos + 2);
        padded = ((size_t)alen + 3) & ~(size_t)3;
        if (padded > len - pos - 4) return EXTERIA_E_MALFORMED;
        v = data + pos + 4;
        /* nothing after the integrity attribute counts but the fingerprint */
        if (out->integrity_offset && type != 0x8028) {
            pos += 4 + padded;
            continue;
        }
        switch (type) {
        case ATTR_ERROR_CODE:
            if (alen < 4) return EXTERIA_E_MALFORMED;
            out->has_error = 1;
            out->error_code = (uint16_t)((v[2] & 7) * 100 + v[3]);
            break;
        case ATTR_REALM:
            if (alen == 0 || alen >= sizeof(out->realm)) return EXTERIA_E_MALFORMED;
            memcpy(out->realm, v, alen);
            out->realm[alen] = '\0';
            out->has_realm = 1;
            break;
        case ATTR_NONCE:
            if (alen == 0 || alen > sizeof(out->nonce)) return EXTERIA_E_MALFORMED;
            memcpy(out->nonce, v, alen);
            out->nonce_len = alen;
            out->has_nonce = 1;
            break;
        case ATTR_XOR_RELAYED_ADDRESS:
            if (!read_xor(v, alen, &out->relayed_ip, &out->relayed_port)) break;
            out->has_relayed = 1;
            break;
        case ATTR_XOR_MAPPED_ADDRESS:
            if (!read_xor(v, alen, &out->mapped_ip, &out->mapped_port)) break;
            out->has_mapped = 1;
            break;
        case ATTR_XOR_PEER_ADDRESS:
            if (!read_xor(v, alen, &out->peer_ip, &out->peer_port)) return EXTERIA_E_MALFORMED;
            out->has_peer = 1;
            break;
        case ATTR_LIFETIME:
            if (alen != 4) return EXTERIA_E_MALFORMED;
            out->lifetime = (uint32_t)v[0] << 24 | (uint32_t)v[1] << 16 | (uint32_t)v[2] << 8 | v[3];
            out->has_lifetime = 1;
            break;
        case ATTR_DATA:
            out->data = v;
            out->data_len = alen;
            out->has_data = 1;
            break;
        case ATTR_MESSAGE_INTEGRITY:
            if (alen != EXTERIA_SHA1_LEN) return EXTERIA_E_MALFORMED;
            out->integrity_offset = pos;
            break;
        default:
            break;
        }
        pos += 4 + padded;
    }
    return EXTERIA_OK;
}

static exteria_status check_integrity(const exteria_tgc_turn *t, const uint8_t *data, size_t len, const reading *m) {
    uint8_t head[HEADER_LEN], mac[EXTERIA_SHA1_LEN], diff = 0;
    exteria_slice parts[2];
    size_t i;
    if (m->integrity_offset == 0 || m->integrity_offset + 4 + EXTERIA_SHA1_LEN > len) return EXTERIA_E_NOTFOUND;
    memcpy(head, data, sizeof(head));
    put16(head + 2, (uint16_t)(m->integrity_offset - HEADER_LEN + 4 + EXTERIA_SHA1_LEN));
    parts[0].data = head;
    parts[0].len = sizeof(head);
    parts[1].data = data + HEADER_LEN;
    parts[1].len = m->integrity_offset - HEADER_LEN;
    if (exteria_hmac_sha1(t->key, sizeof(t->key), parts, 2, mac) != EXTERIA_OK) return EXTERIA_E_CRYPTO;
    for (i = 0; i < EXTERIA_SHA1_LEN; ++i) diff |= (uint8_t)(mac[i] ^ data[m->integrity_offset + 4 + i]);
    return diff == 0 ? EXTERIA_OK : EXTERIA_E_SECURITY;
}

static exteria_tgc_turn_request *find_request(exteria_tgc_turn *t, const uint8_t txid[12]) {
    size_t i;
    for (i = 0; i < EXTERIA_TGC_TURN_MAX_REQUESTS; ++i) {
        if (t->requests[i].used && memcmp(t->requests[i].txid, txid, 12) == 0) return &t->requests[i];
    }
    return NULL;
}

/* a new realm or nonce: every request that was not accepted is made again with it */
static void take_challenge(exteria_tgc_turn *t, const reading *m, uint64_t now_ms) {
    size_t i;
    if (m->has_realm) {
        memcpy(t->realm, m->realm, strlen(m->realm) + 1);
        if (make_key(t) != EXTERIA_OK) {
            fail(t, "the key could not be made");
            return;
        }
    }
    if (m->has_nonce) {
        memcpy(t->nonce, m->nonce, m->nonce_len);
        t->nonce_len = m->nonce_len;
    }
    if (!t->has_key) {
        fail(t, "challenge without a realm");
        return;
    }
    for (i = 0; i < EXTERIA_TGC_TURN_MAX_REQUESTS; ++i) {
        exteria_tgc_turn_request *r = &t->requests[i];
        if (!r->used) continue;
        r->tries = 0;
        if (build(t, r) != EXTERIA_OK) {
            r->used = 0;
            continue;
        }
        transmit(t, r, now_ms);
    }
}

exteria_status exteria_tgc_turn_input(exteria_tgc_turn *t, const uint8_t *packet, size_t len, uint64_t now_ms, exteria_tgc_turn_output *out) {
    reading m;
    exteria_tgc_turn_request *r;
    exteria_status status;
    if (out) memset(out, 0, sizeof(*out));
    if (!t || !packet || !out) return EXTERIA_E_ARG;
    status = read_message(packet, len, &m);
    if (status != EXTERIA_OK) return status;
    if (m.type == TYPE_DATA) {
        if (!m.has_peer || !m.has_data || m.data_len == 0) return EXTERIA_OK;
        ++t->data_in;
        out->kind = EXTERIA_TGC_TURN_INPUT_DATA;
        out->peer_ip = m.peer_ip;
        out->peer_port = m.peer_port;
        out->data = m.data;
        out->len = m.data_len;
        return EXTERIA_OK;
    }
    if ((m.type & 0x0100) == 0) return EXTERIA_OK;
    r = find_request(t, m.txid);
    if (!r) return EXTERIA_OK;
    if (m.type & 0x0010) {
        unsigned code = m.has_error ? m.error_code : 0;
        if ((code == 401 || code == 438) && m.has_nonce) {
            /* an allocation is answered with its challenge first; a stale nonce later brings a new one */
            if (code == 401 && r->authenticated) {
                fail(t, "the credentials were refused");
                return EXTERIA_OK;
            }
            trace(t, "turn challenge %u (%s)", code, m.has_realm ? "realm given" : "same realm");
            take_challenge(t, &m, now_ms);
            return EXTERIA_OK;
        }
        r->used = 0;
        if (r->kind == KIND_PERMISSION) {
            t->permissions[r->permission].state = PERMISSION_REFUSED;
            trace(t, "turn permission refused with %u", code);
        } else {
            char why[40];
            snprintf(why, sizeof(why), "error %u", code);
            fail(t, why);
        }
        return EXTERIA_OK;
    }
    /* a success answer to an authenticated request carries MESSAGE-INTEGRITY with the same key */
    if (t->has_key && m.integrity_offset) {
        status = check_integrity(t, packet, len, &m);
        if (status != EXTERIA_OK) return status == EXTERIA_E_SECURITY ? status : EXTERIA_OK;
    }
    r->used = 0;
    if (r->kind == KIND_ALLOCATE) {
        if (!m.has_relayed) {
            fail(t, "the allocation has no relayed address");
            return EXTERIA_OK;
        }
        t->relay_ip = m.relayed_ip;
        t->relay_port = m.relayed_port;
        t->mapped_ip = m.has_mapped ? m.mapped_ip : 0;
        t->mapped_port = m.has_mapped ? m.mapped_port : 0;
        t->lifetime_s = m.has_lifetime && m.lifetime > 0 ? m.lifetime : DEFAULT_LIFETIME_S;
        /* half the lifetime, so one lost refresh still leaves time for the next */
        t->refresh_due_ms = now_ms + (uint64_t)t->lifetime_s * 500u;
        t->state = EXTERIA_TGC_TURN_READY;
        trace(t, "turn allocation ready: relay %u.%u.%u.%u:%u, lifetime %u s", (unsigned)(t->relay_ip >> 24), (unsigned)(t->relay_ip >> 16 & 255),
              (unsigned)(t->relay_ip >> 8 & 255), (unsigned)(t->relay_ip & 255), (unsigned)t->relay_port, (unsigned)t->lifetime_s);
        out->kind = EXTERIA_TGC_TURN_INPUT_READY;
    } else if (r->kind == KIND_REFRESH) {
        if (m.has_lifetime && m.lifetime > 0) {
            t->lifetime_s = m.lifetime;
            t->refresh_due_ms = now_ms + (uint64_t)m.lifetime * 500u;
        }
    } else {
        exteria_tgc_turn_permission *p = &t->permissions[r->permission];
        if (p->state != PERMISSION_GRANTED) trace(t, "turn permission granted for %u.%u.%u.%u", (unsigned)(p->ip >> 24), (unsigned)(p->ip >> 16 & 255),
                                                  (unsigned)(p->ip >> 8 & 255), (unsigned)(p->ip & 255));
        p->state = PERMISSION_GRANTED;
        p->renewing = 0;
        p->granted_ms = now_ms;
    }
    return EXTERIA_OK;
}

int exteria_tgc_turn_ready(const exteria_tgc_turn *t) {
    return t && t->state == EXTERIA_TGC_TURN_READY;
}

int exteria_tgc_turn_relayed(const exteria_tgc_turn *t, uint32_t *relay_ip, uint16_t *relay_port, uint32_t *mapped_ip, uint16_t *mapped_port) {
    if (!t || t->state != EXTERIA_TGC_TURN_READY) return 0;
    if (relay_ip) *relay_ip = t->relay_ip;
    if (relay_port) *relay_port = t->relay_port;
    if (mapped_ip) *mapped_ip = t->mapped_ip;
    if (mapped_port) *mapped_port = t->mapped_port;
    return 1;
}

int exteria_tgc_turn_permit(exteria_tgc_turn *t, uint32_t ip) {
    size_t i;
    if (!t || ip == 0) return -1;
    for (i = 0; i < EXTERIA_TGC_TURN_MAX_PERMISSIONS; ++i) {
        if (t->permissions[i].ip == ip) {
            if (t->permissions[i].state == PERMISSION_GRANTED) return 1;
            return t->permissions[i].state == PERMISSION_REFUSED ? -1 : 0;
        }
    }
    for (i = 0; i < EXTERIA_TGC_TURN_MAX_PERMISSIONS; ++i) {
        if (t->permissions[i].ip == 0) {
            t->permissions[i].ip = ip;
            t->permissions[i].state = PERMISSION_WANTED;
            return 0;
        }
    }
    return -1;
}

exteria_status exteria_tgc_turn_wrap(exteria_tgc_turn *t, uint32_t ip, uint16_t port, const uint8_t *payload, size_t len, uint8_t *out, size_t capacity,
                                     size_t *out_len) {
    writer w;
    uint8_t txid[12];
    if (out_len) *out_len = 0;
    if (!t || !payload || !out || !out_len || len == 0) return EXTERIA_E_ARG;
    if (t->state != EXTERIA_TGC_TURN_READY) return EXTERIA_E_STATE;
    if (len > EXTERIA_TGC_TURN_MAX_PAYLOAD) return EXTERIA_E_LIMIT;
    if (exteria_random(txid, sizeof(txid)) != EXTERIA_OK) return EXTERIA_E_CRYPTO;
    begin(&w, out, capacity, TYPE_SEND, txid);
    xor_address(&w, ATTR_XOR_PEER_ADDRESS, txid, ip, port);
    attr(&w, ATTR_DATA, payload, len);
    if (w.overflow) return EXTERIA_E_LIMIT;
    put16(out + 2, (uint16_t)(w.len - HEADER_LEN));
    *out_len = w.len;
    ++t->data_out;
    return EXTERIA_OK;
}
