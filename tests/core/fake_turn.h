#ifndef EXTERIA_FAKE_TURN_H
#define EXTERIA_FAKE_TURN_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "exteria_crypto.h"
#include "test_util.h"

#define SERVER_IP 0x5b6c0d17u /* 91.108.13.23 */
#define SERVER_PORT 598
#define RELAY_IP 0x5b6c0d17u
#define RELAY_PORT 49512
#define MAPPED_IP 0x6edf0a14u
#define MAPPED_PORT 40071
#define PEER_IP 0x5b6c0e05u /* 91.108.14.5 */
#define PEER_PORT 31337
#define MAGIC 0x2112A442u

/* a TURN server written for the test from RFC 5766 and RFC 5389, apart from the client: it parses with its own reader and answers with its own writer */
typedef struct sent {
    uint8_t data[2048];
    size_t len;
} sent;

struct server;
typedef void (*forward_fn)(void *hub, struct server *from, uint32_t ip, uint16_t port, const uint8_t *data, size_t len);

typedef struct server {
    const char *user, *pass, *realm, *nonce;
    uint8_t key[16];
    /* the relayed address this server gives the client that allocates on it, and who may send to that client */
    uint32_t relay_ip, mapped_ip;
    uint16_t relay_port, mapped_port;
    uint32_t granted[16];
    size_t granted_count;
    forward_fn forward;
    void *hub;
    int allocations, challenges, permissions, bad_integrity, send_indications, stale_next;
    uint32_t last_permission_ip, last_peer_ip;
    uint16_t last_peer_port;
    uint8_t last_data[1500];
    size_t last_data_len;
    uint8_t last_request[600];
    size_t last_request_len;
    int silent;
} server;

typedef struct client_side {
    sent out[64];
    size_t count;
    char traces[64][200];
    size_t trace_count;
} client_side;

static inline void on_send(void *ctx, const uint8_t *data, size_t len) {
    client_side *c = ctx;
    if (c->count < 64 && len <= sizeof(c->out[0].data)) {
        memcpy(c->out[c->count].data, data, len);
        c->out[c->count].len = len;
        ++c->count;
    }
}

static inline void on_trace(void *ctx, const char *line) {
    client_side *c = ctx;
    if (c->trace_count < 64) {
        strncpy(c->traces[c->trace_count], line, 199);
        c->traces[c->trace_count][199] = '\0';
        ++c->trace_count;
    }
}

static inline uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static inline void wr16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }
static inline void wr32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v; }

/* finds an attribute; returns its value and length, or NULL */
static inline const uint8_t *find_attr(const uint8_t *msg, size_t len, uint16_t type, size_t *alen) {
    size_t pos = 20;
    while (pos + 4 <= len) {
        uint16_t t = rd16(msg + pos), l = rd16(msg + pos + 2);
        if (t == type) {
            if (alen) *alen = l;
            return msg + pos + 4;
        }
        pos += 4 + (((size_t)l + 3) & ~(size_t)3);
    }
    return NULL;
}

typedef struct wbuf {
    uint8_t b[1500];
    size_t len;
} wbuf;

static inline void wbegin(wbuf *w, uint16_t type, const uint8_t *txid) {
    memset(w, 0, sizeof(*w));
    wr16(w->b, type);
    wr32(w->b + 4, MAGIC);
    memcpy(w->b + 8, txid, 12);
    w->len = 20;
}

static inline void wattr(wbuf *w, uint16_t type, const void *v, size_t l) {
    wr16(w->b + w->len, type);
    wr16(w->b + w->len + 2, (uint16_t)l);
    memcpy(w->b + w->len + 4, v, l);
    w->len += 4 + ((l + 3) & ~(size_t)3);
}

static inline void wxor(wbuf *w, uint16_t type, uint32_t ip, uint16_t port) {
    uint8_t v[8] = {0, 1};
    wr16(v + 2, (uint16_t)(port ^ (MAGIC >> 16)));
    wr32(v + 4, ip ^ MAGIC);
    wattr(w, type, v, 8);
}

static inline void wfinish(wbuf *w, const uint8_t *key) {
    wr16(w->b + 2, (uint16_t)(w->len - 20));
    if (key) {
        uint8_t mac[20];
        exteria_slice part;
        wr16(w->b + 2, (uint16_t)(w->len - 20 + 24));
        part.data = w->b;
        part.len = w->len;
        exteria_hmac_sha1(key, 16, &part, 1, mac);
        wattr(w, 0x0008, mac, 20);
    }
    wr16(w->b + 2, (uint16_t)(w->len - 20));
}

static inline int integrity_ok(const server *s, const uint8_t *msg, size_t len) {
    size_t pos = 20;
    while (pos + 4 <= len) {
        uint16_t t = rd16(msg + pos), l = rd16(msg + pos + 2);
        if (t == 0x0008) {
            uint8_t copy[600], mac[20];
            exteria_slice part;
            memcpy(copy, msg, pos);
            wr16(copy + 2, (uint16_t)(pos - 20 + 24));
            part.data = copy;
            part.len = pos;
            exteria_hmac_sha1(s->key, 16, &part, 1, mac);
            return memcmp(mac, msg + pos + 4, 20) == 0;
        }
        pos += 4 + (((size_t)l + 3) & ~(size_t)3);
    }
    return 0;
}

static inline void server_init(server *s) {
    exteria_slice part;
    char text[200];
    memset(s, 0, sizeof(*s));
    s->relay_ip = RELAY_IP;
    s->relay_port = RELAY_PORT;
    s->mapped_ip = MAPPED_IP;
    s->mapped_port = MAPPED_PORT;
    s->user = "reflector";
    s->pass = "s3cret-pass";
    s->realm = "tg.test";
    s->nonce = "0123456789abcdef";
    snprintf(text, sizeof(text), "%s:%s:%s", s->user, s->realm, s->pass);
    part.data = (const uint8_t *)text;
    part.len = strlen(text);
    exteria_md5(&part, 1, s->key);
}

static inline void error_response(const server *s, const uint8_t *req, uint16_t type, unsigned code, int with_challenge, wbuf *w) {
    uint8_t v[4] = {0, 0, (uint8_t)(code / 100), (uint8_t)(code % 100)};
    wbegin(w, (uint16_t)(type | 0x0110), req + 8);
    wattr(w, 0x0009, v, 4);
    if (with_challenge) {
        wattr(w, 0x0014, s->realm, strlen(s->realm));
        wattr(w, 0x0015, s->nonce, strlen(s->nonce));
    }
    wfinish(w, NULL);
}

/* what the server answers to one datagram of the client, or nothing */
static inline int server_answer(server *s, const uint8_t *req, size_t len, wbuf *w) {
    uint16_t type = rd16(req);
    size_t alen = 0;
    const uint8_t *user;
    if (s->silent) return 0;
    if (type == 0x0016) {
        const uint8_t *peer = find_attr(req, len, 0x0012, NULL), *data = find_attr(req, len, 0x0013, &alen);
        CHECK(peer != NULL && data != NULL);
        if (!peer || !data) return 0;
        s->last_peer_port = (uint16_t)(rd16(peer + 2) ^ (MAGIC >> 16));
        s->last_peer_ip = ((uint32_t)peer[4] << 24 | (uint32_t)peer[5] << 16 | (uint32_t)peer[6] << 8 | peer[7]) ^ MAGIC;
        memcpy(s->last_data, data, alen);
        s->last_data_len = alen;
        ++s->send_indications;
        if (s->forward) s->forward(s->hub, s, s->last_peer_ip, s->last_peer_port, data, alen);
        return 0;
    }
    memcpy(s->last_request, req, len);
    s->last_request_len = len;
    user = find_attr(req, len, 0x0006, NULL);
    if (!user) {
        ++s->challenges;
        error_response(s, req, type, 401, 1, w);
        return 1;
    }
    if (s->stale_next) {
        s->stale_next = 0;
        error_response(s, req, type, 438, 1, w);
        return 1;
    }
    if (!integrity_ok(s, req, len)) {
        ++s->bad_integrity;
        error_response(s, req, type, 401, 1, w);
        return 1;
    }
    wbegin(w, (uint16_t)(type | 0x0100), req + 8);
    if (type == 0x0003) {
        uint8_t life[4];
        ++s->allocations;
        wxor(w, 0x0016, s->relay_ip, s->relay_port);
        wxor(w, 0x0020, s->mapped_ip, s->mapped_port);
        wr32(life, 600);
        wattr(w, 0x000D, life, 4);
    } else if (type == 0x0008) {
        const uint8_t *peer = find_attr(req, len, 0x0012, NULL);
        ++s->permissions;
        if (peer) {
            s->last_permission_ip = ((uint32_t)peer[4] << 24 | (uint32_t)peer[5] << 16 | (uint32_t)peer[6] << 8 | peer[7]) ^ MAGIC;
            if (s->granted_count < 16) s->granted[s->granted_count++] = s->last_permission_ip;
        }
    } else if (type == 0x0004) {
        uint8_t life[4];
        wr32(life, 600);
        wattr(w, 0x000D, life, 4);
    }
    wfinish(w, s->key);
    return 1;
}


#endif
