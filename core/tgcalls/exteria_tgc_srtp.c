#include "exteria_tgc_srtp.h"

#include <string.h>

#include "exteria_bytes.h"
#include "exteria_crypto.h"
#include "exteria_rtp.h"

#define LABEL_RTP_ENCRYPTION 0x00
#define LABEL_RTP_AUTH 0x01
#define LABEL_RTP_SALT 0x02
#define LABEL_RTCP_ENCRYPTION 0x03
#define LABEL_RTCP_AUTH 0x04
#define LABEL_RTCP_SALT 0x05
#define RTCP_HEADER_LEN 8
#define SRTCP_ENCRYPTED_BIT 0x80000000u
#define SRTCP_INDEX_MASK 0x7FFFFFFFu
#define PACKET_INDEX_MASK 0xFFFFFFFFFFFFull

/* key derivation function of RFC 3711 section 4.3.1: AES counter mode with the master key, from the counter block made of the master
   salt xor the label placed at byte 7, with a zero key derivation rate */
static exteria_status derive(const uint8_t key[EXTERIA_TGC_SRTP_KEY_LEN], const uint8_t salt[EXTERIA_TGC_SRTP_SALT_LEN], uint8_t label,
                             uint8_t *out, size_t n) {
    uint8_t iv[16] = {0}, zeros[EXTERIA_TGC_SRTP_AUTH_KEY_LEN] = {0};
    memcpy(iv, salt, EXTERIA_TGC_SRTP_SALT_LEN);
    iv[7] ^= label;
    return exteria_aes128_ctr(key, iv, zeros, out, n);
}

exteria_status exteria_tgc_srtp_init(exteria_tgc_srtp *s, const uint8_t master_key[EXTERIA_TGC_SRTP_KEY_LEN],
                                     const uint8_t master_salt[EXTERIA_TGC_SRTP_SALT_LEN]) {
    exteria_status status;
    if (!s) return EXTERIA_E_ARG;
    memset(s, 0, sizeof(*s));
    if (!master_key || !master_salt) return EXTERIA_E_ARG;
    status = derive(master_key, master_salt, LABEL_RTP_ENCRYPTION, s->rtp_key, sizeof(s->rtp_key));
    if (status == EXTERIA_OK) status = derive(master_key, master_salt, LABEL_RTP_AUTH, s->rtp_auth, sizeof(s->rtp_auth));
    if (status == EXTERIA_OK) status = derive(master_key, master_salt, LABEL_RTP_SALT, s->rtp_salt, sizeof(s->rtp_salt));
    if (status == EXTERIA_OK) status = derive(master_key, master_salt, LABEL_RTCP_ENCRYPTION, s->rtcp_key, sizeof(s->rtcp_key));
    if (status == EXTERIA_OK) status = derive(master_key, master_salt, LABEL_RTCP_AUTH, s->rtcp_auth, sizeof(s->rtcp_auth));
    if (status == EXTERIA_OK) status = derive(master_key, master_salt, LABEL_RTCP_SALT, s->rtcp_salt, sizeof(s->rtcp_salt));
    if (status != EXTERIA_OK) memset(s, 0, sizeof(*s));
    return status;
}

/* the counter block of RFC 3711 section 4.1.1; the session salt shifted left 16 bits, xor the ssrc at bytes 4 to 7
   and the 48 bit index at bytes 8 to 13 (for SRTCP the 31 bit index sits at the same place) */
static void packet_iv(const uint8_t salt[EXTERIA_TGC_SRTP_SALT_LEN], uint32_t ssrc, uint64_t index, uint8_t iv[16]) {
    int i;
    memset(iv, 0, 16);
    memcpy(iv, salt, EXTERIA_TGC_SRTP_SALT_LEN);
    iv[4] ^= (uint8_t)(ssrc >> 24);
    iv[5] ^= (uint8_t)(ssrc >> 16);
    iv[6] ^= (uint8_t)(ssrc >> 8);
    iv[7] ^= (uint8_t)ssrc;
    for (i = 0; i < 6; ++i) iv[8 + i] ^= (uint8_t)(index >> (8 * (5 - i)));
}

static exteria_status auth_tag(const uint8_t auth_key[EXTERIA_TGC_SRTP_AUTH_KEY_LEN], const uint8_t *data, size_t len, const uint8_t *tail, size_t tail_len,
                               uint8_t tag[EXTERIA_TGC_SRTP_TAG_LEN]) {
    exteria_slice parts[2];
    uint8_t mac[EXTERIA_SHA1_LEN];
    exteria_status status;
    parts[0].data = data;
    parts[0].len = len;
    parts[1].data = tail;
    parts[1].len = tail_len;
    status = exteria_hmac_sha1(auth_key, EXTERIA_TGC_SRTP_AUTH_KEY_LEN, parts, 2, mac);
    if (status == EXTERIA_OK) memcpy(tag, mac, EXTERIA_TGC_SRTP_TAG_LEN);
    memset(mac, 0, sizeof(mac));
    return status;
}

static int tags_equal(const uint8_t *a, const uint8_t *b) {
    uint8_t diff = 0;
    int i;
    for (i = 0; i < EXTERIA_TGC_SRTP_TAG_LEN; ++i) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

/* replay window: the newest index and one bit per index in the last 128, at position index mod 128 */
static int window_is_fresh(const exteria_tgc_srtp_window *w, uint64_t index) {
    uint64_t behind;
    if (!w->has_highest || index > w->highest) return 1;
    behind = w->highest - index;
    if (behind >= EXTERIA_TGC_SRTP_WINDOW) return 0;
    return (w->bits[(index % EXTERIA_TGC_SRTP_WINDOW) / 8] & (1u << (index % 8))) == 0;
}

static void window_commit(exteria_tgc_srtp_window *w, uint64_t index) {
    if (!w->has_highest) {
        memset(w->bits, 0, sizeof(w->bits));
        w->has_highest = 1;
        w->highest = index;
    } else if (index > w->highest) {
        uint64_t gap = index - w->highest, i;
        if (gap >= EXTERIA_TGC_SRTP_WINDOW) {
            memset(w->bits, 0, sizeof(w->bits));
        } else {
            /* the positions of the indexes that were skipped must read as unseen, whatever an older lap left there */
            for (i = w->highest + 1; i < index; ++i) w->bits[(i % EXTERIA_TGC_SRTP_WINDOW) / 8] &= (uint8_t)~(1u << (i % 8));
        }
        w->highest = index;
    }
    w->bits[(index % EXTERIA_TGC_SRTP_WINDOW) / 8] |= (uint8_t)(1u << (index % 8));
}

static exteria_tgc_srtp_stream *find_stream(exteria_tgc_srtp_stream *table, uint32_t ssrc, int create) {
    int i, free_slot = -1;
    for (i = 0; i < EXTERIA_TGC_SRTP_STREAMS; ++i) {
        if (table[i].used && table[i].ssrc == ssrc) return &table[i];
        if (!table[i].used && free_slot < 0) free_slot = i;
    }
    if (!create || free_slot < 0) return NULL;
    memset(&table[free_slot], 0, sizeof(table[free_slot]));
    table[free_slot].used = 1;
    table[free_slot].ssrc = ssrc;
    return &table[free_slot];
}

/* the rollover counter a received sequence number implies (RFC 3711 appendix A), given the newest sequence of the stream */
static uint32_t guess_roc(const exteria_tgc_srtp_stream *st, uint16_t seq) {
    if (!st->has_seq) return 0;
    if (st->last_seq < 32768) {
        if ((int)seq - (int)st->last_seq > 32768) return st->roc ? st->roc - 1 : 0xFFFFFFFFu;
        return st->roc;
    }
    if ((int)st->last_seq - 32768 > (int)seq) return st->roc + 1;
    return st->roc;
}

exteria_status exteria_tgc_srtp_protect(exteria_tgc_srtp *s, uint8_t *pkt, size_t len, size_t capacity, size_t *out_len) {
    exteria_rtp_header h;
    exteria_tgc_srtp_stream *st;
    uint8_t iv[16], roc_bytes[4];
    uint64_t index;
    uint32_t roc;
    exteria_status status;
    if (out_len) *out_len = 0;
    if (!s || !pkt || !out_len) return EXTERIA_E_ARG;
    status = exteria_rtp_parse(pkt, len, &h);
    if (status != EXTERIA_OK) return status == EXTERIA_E_ARG ? status : EXTERIA_E_MALFORMED;
    if (capacity < len + EXTERIA_TGC_SRTP_TAG_LEN) return EXTERIA_E_LIMIT;
    st = find_stream(s->streams, h.ssrc, 1);
    if (!st) return EXTERIA_E_LIMIT;
    roc = st->roc;
    /* a sender's sequence only moves forward, so a number far below the last one is the wrap of the 16 bits */
    if (st->has_seq && h.sequence < st->last_seq && (uint32_t)st->last_seq - h.sequence > 32768u) {
        if (roc == 0xFFFFFFFFu) return EXTERIA_E_STATE;
        ++roc;
    }
    index = ((uint64_t)roc << 16) | h.sequence;
    packet_iv(s->rtp_salt, h.ssrc, index, iv);
    status = exteria_aes128_ctr(s->rtp_key, iv, pkt + h.payload_offset, pkt + h.payload_offset, len - h.payload_offset);
    if (status != EXTERIA_OK) return status;
    exteria_put_u32be(roc_bytes, roc);
    status = auth_tag(s->rtp_auth, pkt, len, roc_bytes, sizeof(roc_bytes), pkt + len);
    if (status != EXTERIA_OK) return status;
    st->roc = roc;
    st->last_seq = h.sequence;
    st->has_seq = 1;
    *out_len = len + EXTERIA_TGC_SRTP_TAG_LEN;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_srtp_unprotect(exteria_tgc_srtp *s, uint8_t *pkt, size_t len, size_t *out_len) {
    exteria_rtp_header h;
    exteria_tgc_srtp_stream *st, fresh;
    uint8_t iv[16], roc_bytes[4], expect[EXTERIA_TGC_SRTP_TAG_LEN];
    uint64_t index;
    uint32_t roc;
    size_t body;
    exteria_status status;
    if (out_len) *out_len = 0;
    if (!s || !pkt || !out_len) return EXTERIA_E_ARG;
    if (len < EXTERIA_RTP_FIXED_LEN + EXTERIA_TGC_SRTP_TAG_LEN) return EXTERIA_E_MALFORMED;
    body = len - EXTERIA_TGC_SRTP_TAG_LEN;
    status = exteria_rtp_parse(pkt, body, &h);
    if (status != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    st = find_stream(s->streams, h.ssrc, 0);
    if (!st) {
        /* a stream is entered into the table only once a packet of it has passed the tag, so unknown senders cost nothing */
        memset(&fresh, 0, sizeof(fresh));
        fresh.ssrc = h.ssrc;
        st = &fresh;
    }
    roc = guess_roc(st, h.sequence);
    index = ((uint64_t)roc << 16) | h.sequence;
    if (!window_is_fresh(&st->replay, index)) return EXTERIA_E_RETRY;
    exteria_put_u32be(roc_bytes, roc);
    status = auth_tag(s->rtp_auth, pkt, body, roc_bytes, sizeof(roc_bytes), expect);
    if (status != EXTERIA_OK) return status;
    if (!tags_equal(expect, pkt + body)) return EXTERIA_E_SECURITY;
    if (st == &fresh) {
        st = find_stream(s->streams, h.ssrc, 1);
        if (!st) return EXTERIA_E_LIMIT;
    }
    packet_iv(s->rtp_salt, h.ssrc, index, iv);
    status = exteria_aes128_ctr(s->rtp_key, iv, pkt + h.payload_offset, pkt + h.payload_offset, body - h.payload_offset);
    if (status != EXTERIA_OK) return status;
    window_commit(&st->replay, index);
    if (!st->has_seq || roc > st->roc || (roc == st->roc && h.sequence > st->last_seq)) {
        st->roc = roc;
        st->last_seq = h.sequence;
        st->has_seq = 1;
    }
    *out_len = body;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_srtcp_protect(exteria_tgc_srtp *s, uint8_t *pkt, size_t len, size_t capacity, size_t *out_len) {
    exteria_tgc_srtp_stream *st;
    uint8_t iv[16];
    uint32_t ssrc, index, word;
    exteria_status status;
    if (out_len) *out_len = 0;
    if (!s || !pkt || !out_len) return EXTERIA_E_ARG;
    if (len < RTCP_HEADER_LEN || (pkt[0] >> 6) != 2) return EXTERIA_E_MALFORMED;
    if (capacity < len + EXTERIA_TGC_SRTCP_TRAILER_LEN) return EXTERIA_E_LIMIT;
    ssrc = (uint32_t)pkt[4] << 24 | (uint32_t)pkt[5] << 16 | (uint32_t)pkt[6] << 8 | pkt[7];
    st = find_stream(s->rtcp_streams, ssrc, 1);
    if (!st) return EXTERIA_E_LIMIT;
    if (st->rtcp_index >= SRTCP_INDEX_MASK) return EXTERIA_E_STATE;
    /* each sender counts its own packets, and counts before use, so the first packet carries 1, as in libsrtp and so in every webrtc sender */
    index = st->rtcp_index + 1;
    packet_iv(s->rtcp_salt, ssrc, index, iv);
    status = exteria_aes128_ctr(s->rtcp_key, iv, pkt + RTCP_HEADER_LEN, pkt + RTCP_HEADER_LEN, len - RTCP_HEADER_LEN);
    if (status != EXTERIA_OK) return status;
    word = SRTCP_ENCRYPTED_BIT | index;
    exteria_put_u32be(pkt + len, word);
    status = auth_tag(s->rtcp_auth, pkt, len + 4, NULL, 0, pkt + len + 4);
    if (status != EXTERIA_OK) return status;
    st->rtcp_index = index;
    *out_len = len + EXTERIA_TGC_SRTCP_TRAILER_LEN;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_srtcp_unprotect(exteria_tgc_srtp *s, uint8_t *pkt, size_t len, size_t *out_len) {
    exteria_tgc_srtp_stream *st, fresh;
    uint8_t iv[16], expect[EXTERIA_TGC_SRTP_TAG_LEN];
    uint32_t ssrc, word, index;
    size_t body;
    exteria_status status;
    if (out_len) *out_len = 0;
    if (!s || !pkt || !out_len) return EXTERIA_E_ARG;
    if (len < RTCP_HEADER_LEN + EXTERIA_TGC_SRTCP_TRAILER_LEN || (pkt[0] >> 6) != 2) return EXTERIA_E_MALFORMED;
    body = len - EXTERIA_TGC_SRTCP_TRAILER_LEN;
    ssrc = (uint32_t)pkt[4] << 24 | (uint32_t)pkt[5] << 16 | (uint32_t)pkt[6] << 8 | pkt[7];
    word = (uint32_t)pkt[body] << 24 | (uint32_t)pkt[body + 1] << 16 | (uint32_t)pkt[body + 2] << 8 | pkt[body + 3];
    index = word & SRTCP_INDEX_MASK;
    st = find_stream(s->rtcp_streams, ssrc, 0);
    if (!st) {
        memset(&fresh, 0, sizeof(fresh));
        fresh.ssrc = ssrc;
        st = &fresh;
    }
    if (!window_is_fresh(&st->replay, index)) return EXTERIA_E_RETRY;
    status = auth_tag(s->rtcp_auth, pkt, body + 4, NULL, 0, expect);
    if (status != EXTERIA_OK) return status;
    if (!tags_equal(expect, pkt + body + 4)) return EXTERIA_E_SECURITY;
    if (st == &fresh) {
        st = find_stream(s->rtcp_streams, ssrc, 1);
        if (!st) return EXTERIA_E_LIMIT;
    }
    if (word & SRTCP_ENCRYPTED_BIT) {
        packet_iv(s->rtcp_salt, ssrc, index, iv);
        status = exteria_aes128_ctr(s->rtcp_key, iv, pkt + RTCP_HEADER_LEN, pkt + RTCP_HEADER_LEN, body - RTCP_HEADER_LEN);
        if (status != EXTERIA_OK) return status;
    }
    window_commit(&st->replay, index);
    *out_len = body;
    return EXTERIA_OK;
}

void exteria_tgc_srtp_wipe(exteria_tgc_srtp *s) {
    if (s) memset(s, 0, sizeof(*s));
}
