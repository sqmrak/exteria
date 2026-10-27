#include "exteria_mt_transport.h"

#include <stdlib.h>
#include <string.h>

#include "exteria_random.h"

#define RX_MAX (EXTERIA_MT_MAX_FRAME + 4096u)
#define INIT_LEN 64u

void exteria_mt_transport_init(exteria_mt_transport *t) {
    memset(t, 0, sizeof(*t));
    exteria_writer_init(&t->rx, RX_MAX);
}

void exteria_mt_transport_free(exteria_mt_transport *t) {
    exteria_aes_ctr_free(t->enc);
    exteria_aes_ctr_free(t->dec);
    exteria_writer_free(&t->rx);
    memset(t, 0, sizeof(*t));
}

int exteria_mt_transport_padded(const exteria_mt_transport *t) {
    return t->kind == EXTERIA_MT_PADDED_INTERMEDIATE;
}

static uint32_t tag_of(exteria_mt_transport_kind kind) {
    switch (kind) {
    case EXTERIA_MT_ABRIDGED: return 0xefefefefu;
    case EXTERIA_MT_INTERMEDIATE: return 0xeeeeeeeeu;
    case EXTERIA_MT_PADDED_INTERMEDIATE: return 0xddddddddu;
    }
    return 0;
}

/* the secret is mixed into the key so only a client that knows it gets a stream the proxy accepts */
static exteria_status derive(const uint8_t *seed48, const uint8_t *secret, uint8_t key[32], uint8_t iv[16]) {
    memcpy(iv, seed48 + 32, 16);
    if (!secret) {
        memcpy(key, seed48, 32);
        return EXTERIA_OK;
    }
    {
        exteria_slice parts[2];
        parts[0].data = seed48;
        parts[0].len = 32;
        parts[1].data = secret;
        parts[1].len = EXTERIA_MT_SECRET_LEN;
        return exteria_sha256(parts, 2, key);
    }
}

static exteria_status make_ciphers(exteria_mt_transport *t, const uint8_t init[INIT_LEN], int server) {
    uint8_t fwd[48], rev[48], key[32], iv[16];
    const uint8_t *secret = t->obf.has_secret ? t->obf.secret : NULL;
    exteria_status s;
    size_t i;
    memcpy(fwd, init + 8, 48);
    for (i = 0; i < 48; ++i) rev[i] = init[55 - i];
    s = derive(fwd, secret, key, iv);
    if (s != EXTERIA_OK) return s;
    {
        exteria_aes_ctr *c = exteria_aes_ctr_new(key, iv);
        if (!c) return EXTERIA_E_CRYPTO;
        if (server) t->dec = c;
        else t->enc = c;
    }
    s = derive(rev, secret, key, iv);
    if (s != EXTERIA_OK) return s;
    {
        exteria_aes_ctr *c = exteria_aes_ctr_new(key, iv);
        if (!c) return EXTERIA_E_CRYPTO;
        if (server) t->enc = c;
        else t->dec = c;
    }
    exteria_wipe(fwd, sizeof(fwd));
    exteria_wipe(rev, sizeof(rev));
    exteria_wipe(key, sizeof(key));
    return EXTERIA_OK;
}

/* a proxy must not mistake the obfuscation header for http or a transport marker */
static int init_is_forbidden(const uint8_t *b) {
    uint32_t first = exteria_get_u32le(b);
    uint32_t second = exteria_get_u32le(b + 4);
    return b[0] == 0xef || first == 0x44414548u || first == 0x54534f50u || first == 0x20544547u ||
           first == 0x4954504fu || first == 0xeeeeeeeeu || first == 0xddddddddu || first == 0x02010316u ||
           second == 0;
}

exteria_status exteria_mt_transport_start(exteria_mt_transport *t, exteria_mt_transport_kind kind,
                                          const exteria_mt_obfuscation *obf, exteria_writer *out) {
    uint8_t init[INIT_LEN], enc_init[INIT_LEN];
    exteria_status s;
    if (!t || !out || t->synced || tag_of(kind) == 0) return EXTERIA_E_ARG;
    t->kind = kind;
    t->server_side = 0;
    if (obf) t->obf = *obf;
    if (!t->obf.enabled) {
        uint8_t tag[4];
        size_t n;
        if (t->obf.has_secret) return EXTERIA_E_ARG;
        if (kind == EXTERIA_MT_ABRIDGED) {
            tag[0] = 0xef;
            n = 1;
        } else {
            memset(tag, kind == EXTERIA_MT_INTERMEDIATE ? 0xee : 0xdd, 4);
            n = 4;
        }
        t->synced = 1;
        return exteria_wr_bytes(out, tag, n);
    }
    do {
        s = exteria_random(init, sizeof(init));
        if (s != EXTERIA_OK) return s;
    } while (init_is_forbidden(init));
    exteria_put_u32le(init + 56, tag_of(kind));
    init[60] = (uint8_t)((uint16_t)t->obf.dc_id & 0xff);
    init[61] = (uint8_t)(((uint16_t)t->obf.dc_id >> 8) & 0xff);
    s = make_ciphers(t, init, 0);
    if (s != EXTERIA_OK) return s;
    /* the whole init passes through the cipher so the stream stays in step, only its tail goes out encrypted */
    s = exteria_aes_ctr_apply(t->enc, init, enc_init, INIT_LEN);
    if (s != EXTERIA_OK) return s;
    memcpy(enc_init, init, 56);
    t->synced = 1;
    s = exteria_wr_bytes(out, enc_init, INIT_LEN);
    exteria_wipe(init, sizeof(init));
    return s;
}

exteria_status exteria_mt_transport_start_server(exteria_mt_transport *t, const uint8_t *secret) {
    if (!t || t->synced) return EXTERIA_E_ARG;
    t->server_side = 1;
    t->synced = 0;
    if (secret) {
        t->obf.has_secret = 1;
        memcpy(t->obf.secret, secret, EXTERIA_MT_SECRET_LEN);
    }
    return EXTERIA_OK;
}

exteria_status exteria_mt_transport_wrap(exteria_mt_transport *t, const uint8_t *payload, size_t len,
                                         int request_quick_ack, exteria_writer *out) {
    uint8_t head[4];
    uint8_t pad[16];
    size_t head_len, pad_len = 0, mark, total;
    exteria_status s;
    if (!t || !out || (len && !payload) || !t->synced || len == 0 || len > EXTERIA_MT_MAX_FRAME) return EXTERIA_E_ARG;
    if (len % 4) return EXTERIA_E_ARG;
    mark = out->len;
    if (t->kind == EXTERIA_MT_ABRIDGED) {
        uint32_t words = (uint32_t)(len / 4);
        if (words < 0x7f) {
            head[0] = (uint8_t)words;
            head_len = 1;
        } else {
            head[0] = 0x7f;
            head[1] = (uint8_t)words;
            head[2] = (uint8_t)(words >> 8);
            head[3] = (uint8_t)(words >> 16);
            head_len = 4;
        }
        if (request_quick_ack) head[0] |= 0x80;
    } else {
        uint32_t word;
        if (t->kind == EXTERIA_MT_PADDED_INTERMEDIATE) {
            uint8_t r;
            s = exteria_random(&r, 1);
            if (s != EXTERIA_OK) return s;
            pad_len = r % 16u;
            s = exteria_random(pad, pad_len);
            if (s != EXTERIA_OK) return s;
        }
        word = (uint32_t)(len + pad_len);
        if (request_quick_ack) word |= 0x80000000u;
        exteria_put_u32le(head, word);
        head_len = 4;
    }
    s = exteria_wr_bytes(out, head, head_len);
    if (s == EXTERIA_OK) s = exteria_wr_bytes(out, payload, len);
    if (s == EXTERIA_OK && pad_len) s = exteria_wr_bytes(out, pad, pad_len);
    if (s != EXTERIA_OK) {
        out->len = mark;
        return s;
    }
    total = head_len + len + pad_len;
    if (t->enc) {
        s = exteria_aes_ctr_apply(t->enc, out->data + mark, out->data + mark, total);
        if (s != EXTERIA_OK) {
            out->len = mark;
            return s;
        }
    }
    return EXTERIA_OK;
}

static void rx_compact(exteria_mt_transport *t) {
    if (t->rx_pos == 0) return;
    if (t->rx_pos == t->rx.len) {
        t->rx.len = 0;
        t->rx_pos = 0;
    } else if (t->rx_pos >= 65536u) {
        memmove(t->rx.data, t->rx.data + t->rx_pos, t->rx.len - t->rx_pos);
        t->rx.len -= t->rx_pos;
        t->rx_pos = 0;
    }
}

/* deriving the server transport from the preamble exercises the client's actual wire format */
static exteria_status server_sync(exteria_mt_transport *t) {
    const uint8_t *b = t->rx.data;
    size_t have = t->rx.len;
    if (have == 0) return EXTERIA_OK;
    if (b[0] == 0xef) {
        t->kind = EXTERIA_MT_ABRIDGED;
        t->rx_pos = 1;
        t->synced = 1;
        return EXTERIA_OK;
    }
    if (have >= 4) {
        uint32_t first = exteria_get_u32le(b);
        if (first == 0xeeeeeeeeu || first == 0xddddddddu) {
            t->kind = first == 0xeeeeeeeeu ? EXTERIA_MT_INTERMEDIATE : EXTERIA_MT_PADDED_INTERMEDIATE;
            t->rx_pos = 4;
            t->synced = 1;
            return EXTERIA_OK;
        }
    }
    if (have < INIT_LEN) return EXTERIA_OK;
    {
        uint8_t plain[INIT_LEN];
        uint32_t tag;
        exteria_status s;
        t->obf.enabled = 1;
        s = make_ciphers(t, b, 1);
        if (s != EXTERIA_OK) return s;
        s = exteria_aes_ctr_apply(t->dec, b, plain, INIT_LEN);
        if (s != EXTERIA_OK) return s;
        tag = exteria_get_u32le(plain + 56);
        if (tag == 0xefefefefu) t->kind = EXTERIA_MT_ABRIDGED;
        else if (tag == 0xeeeeeeeeu) t->kind = EXTERIA_MT_INTERMEDIATE;
        else if (tag == 0xddddddddu) t->kind = EXTERIA_MT_PADDED_INTERMEDIATE;
        else return EXTERIA_E_MALFORMED;
        t->obf.dc_id = (int16_t)((uint16_t)plain[60] | ((uint16_t)plain[61] << 8));
        t->rx_pos = INIT_LEN;
        t->synced = 1;
        if (t->rx.len > INIT_LEN) {
            s = exteria_aes_ctr_apply(t->dec, t->rx.data + INIT_LEN, t->rx.data + INIT_LEN, t->rx.len - INIT_LEN);
            if (s != EXTERIA_OK) return s;
        }
    }
    return EXTERIA_OK;
}

exteria_status exteria_mt_transport_feed(exteria_mt_transport *t, const uint8_t *data, size_t len) {
    size_t mark;
    exteria_status s;
    if (!t || (len && !data)) return EXTERIA_E_ARG;
    if (len == 0) return EXTERIA_OK;
    rx_compact(t);
    mark = t->rx.len;
    s = exteria_wr_bytes(&t->rx, data, len);
    if (s != EXTERIA_OK) return s;
    if (!t->synced) return t->server_side ? server_sync(t) : EXTERIA_E_STATE;
    if (t->dec) {
        s = exteria_aes_ctr_apply(t->dec, t->rx.data + mark, t->rx.data + mark, len);
        if (s != EXTERIA_OK) return s;
    }
    return EXTERIA_OK;
}

exteria_status exteria_mt_transport_next(exteria_mt_transport *t, exteria_mt_frame *frame) {
    const uint8_t *p;
    size_t avail, head_len, body_len;
    memset(frame, 0, sizeof(*frame));
    if (!t->synced) return EXTERIA_E_TRUNCATED;
    p = t->rx.data + t->rx_pos;
    avail = t->rx.len - t->rx_pos;
    if (avail == 0) return EXTERIA_E_TRUNCATED;
    if (t->kind == EXTERIA_MT_ABRIDGED) {
        uint8_t first = p[0];
        if (first & 0x80) {
            if (avail < 4) return EXTERIA_E_TRUNCATED;
            frame->kind = EXTERIA_MT_FRAME_QUICK_ACK;
            frame->quick_ack = exteria_get_u32be(p) & 0x7fffffffu;
            t->rx_pos += 4;
            return EXTERIA_OK;
        }
        if (first == 0x7f) {
            if (avail < 4) return EXTERIA_E_TRUNCATED;
            body_len = ((size_t)p[1] | ((size_t)p[2] << 8) | ((size_t)p[3] << 16)) * 4u;
            head_len = 4;
        } else {
            body_len = (size_t)first * 4u;
            head_len = 1;
        }
    } else {
        uint32_t word;
        if (avail < 4) return EXTERIA_E_TRUNCATED;
        word = exteria_get_u32le(p);
        if (word & 0x80000000u) {
            frame->kind = EXTERIA_MT_FRAME_QUICK_ACK;
            frame->quick_ack = word & 0x7fffffffu;
            t->rx_pos += 4;
            return EXTERIA_OK;
        }
        body_len = word;
        head_len = 4;
    }
    if (body_len > EXTERIA_MT_MAX_FRAME) return EXTERIA_E_LIMIT;
    if (t->kind != EXTERIA_MT_PADDED_INTERMEDIATE && body_len % 4u) return EXTERIA_E_MALFORMED;
    if (body_len == 0) return EXTERIA_E_MALFORMED;
    if (avail - head_len < body_len) return EXTERIA_E_TRUNCATED;
    frame->data = p + head_len;
    frame->len = body_len;
    t->rx_pos += head_len + body_len;
    /* treating transport errors as lengths would allocate from a negative int32 */
    if (body_len == 4 && (int32_t)exteria_get_u32le(frame->data) < 0) {
        frame->kind = EXTERIA_MT_FRAME_ERROR;
        frame->error_code = (int32_t)exteria_get_u32le(frame->data);
        return EXTERIA_OK;
    }
    frame->kind = EXTERIA_MT_FRAME_DATA;
    return EXTERIA_OK;
}
