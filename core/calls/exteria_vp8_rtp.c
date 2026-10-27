#include "exteria_vp8_rtp.h"

#include <string.h>

#define PICTURE_ID_MASK 0x7FFFu
#define KEY_FRAME_TAG_MIN 10u
#define FRAME_TAG_MIN 3u

exteria_status exteria_vp8_packetizer_init(exteria_vp8_packetizer *p, const uint8_t *frame, size_t length, size_t max_payload,
                                           uint16_t picture_id, int non_reference) {
    if (!p) return EXTERIA_E_ARG;
    memset(p, 0, sizeof(*p));
    if (!frame || length == 0) return EXTERIA_E_ARG;
    if (max_payload < EXTERIA_VP8_MIN_PAYLOAD || max_payload > EXTERIA_VP8_MAX_PAYLOAD) return EXTERIA_E_ARG;
    if (length > EXTERIA_VP8_MAX_FRAME) return EXTERIA_E_LIMIT;
    p->frame = frame;
    p->length = length;
    p->max_payload = max_payload;
    p->picture_id = (uint16_t)(picture_id & PICTURE_ID_MASK);
    p->non_reference = non_reference ? 1 : 0;
    return EXTERIA_OK;
}

exteria_status exteria_vp8_packetizer_next(exteria_vp8_packetizer *p, uint8_t *out, size_t capacity, size_t *out_len, int *marker) {
    size_t room, left, packets, take;
    if (out_len) *out_len = 0;
    if (marker) *marker = 0;
    if (!p || !out || !out_len || !marker || !p->frame) return EXTERIA_E_ARG;
    if (capacity < p->max_payload) return EXTERIA_E_LIMIT;
    if (p->offset >= p->length) return EXTERIA_E_EOF;
    room = p->max_payload - EXTERIA_VP8_DESCRIPTOR_LEN;
    left = p->length - p->offset;
    packets = (left + room - 1) / room;
    take = (left + packets - 1) / packets;
    /* s marks the first packet of the frame, partition 0; X announces the extension byte, I the picture id inside
       it */
    out[0] = (uint8_t)(0x80 | (p->non_reference ? 0x20 : 0) | (p->started ? 0 : 0x10));
    out[1] = 0x80;
    out[2] = (uint8_t)(0x80 | (p->picture_id >> 8));
    out[3] = (uint8_t)p->picture_id;
    memcpy(out + EXTERIA_VP8_DESCRIPTOR_LEN, p->frame + p->offset, take);
    p->offset += take;
    p->started = 1;
    *out_len = EXTERIA_VP8_DESCRIPTOR_LEN + take;
    *marker = p->offset >= p->length;
    return EXTERIA_OK;
}

exteria_status exteria_vp8_depacketizer_init(exteria_vp8_depacketizer *d, uint8_t *storage, size_t capacity) {
    if (!d) return EXTERIA_E_ARG;
    memset(d, 0, sizeof(*d));
    if (!storage || capacity < KEY_FRAME_TAG_MIN) return EXTERIA_E_ARG;
    if (capacity > EXTERIA_VP8_MAX_FRAME) return EXTERIA_E_LIMIT;
    d->frame = storage;
    d->capacity = capacity;
    d->need_key_frame = 1;
    return EXTERIA_OK;
}

static void drop_frame(exteria_vp8_depacketizer *d) {
    if (d->in_frame) ++d->dropped_frames;
    d->in_frame = 0;
    d->length = 0;
    d->need_key_frame = 1;
}

/* reads the payload descriptor; start is set for the first packet of partition 0, that is of a frame */
static exteria_status read_descriptor(const uint8_t *payload, size_t len, int *start, size_t *offset) {
    size_t at = 1;
    uint8_t first;
    if (len < 2) return EXTERIA_E_MALFORMED;
    first = payload[0];
    if (first & 0x48) return EXTERIA_E_MALFORMED;
    *start = (first & 0x10) && (first & 0x07) == 0;
    if (first & 0x80) {
        uint8_t flags = payload[at++];
        if (flags & 0x0F) return EXTERIA_E_MALFORMED;
        if (flags & 0x80) {
            if (at >= len) return EXTERIA_E_MALFORMED;
            at += (payload[at] & 0x80) ? 2 : 1;
        }
        if (flags & 0x40) ++at;
        if (flags & 0x30) ++at;
        if (at >= len) return EXTERIA_E_MALFORMED;
    }
    *offset = at;
    return EXTERIA_OK;
}

exteria_status exteria_vp8_depacketizer_push(exteria_vp8_depacketizer *d, uint16_t sequence, uint32_t timestamp, int marker,
                                             const uint8_t *payload, size_t len, exteria_vp8_frame_info *info) {
    int start = 0;
    size_t offset = 0, bytes;
    exteria_status status;
    if (info) memset(info, 0, sizeof(*info));
    if (!d || !d->frame || !info || (!payload && len)) return EXTERIA_E_ARG;
    if (d->has_sequence) {
        int16_t delta = (int16_t)(uint16_t)(sequence - d->last_sequence);
        /* a repeated or reordered packet says nothing new, and the frame it belonged to is already given up on or done */
        if (delta <= 0) return EXTERIA_OK;
        if (delta > 1) drop_frame(d);
    }
    d->last_sequence = sequence;
    d->has_sequence = 1;

    status = read_descriptor(payload, len, &start, &offset);
    if (status != EXTERIA_OK) {
        drop_frame(d);
        return status;
    }
    if (start) {
        /* a new frame while one is open means the marker packet never came, although no sequence number is missing */
        if (d->in_frame) drop_frame(d);
        d->in_frame = 1;
        d->length = 0;
        d->timestamp = timestamp;
    } else if (!d->in_frame) {
        return EXTERIA_OK;
    } else if (timestamp != d->timestamp) {
        drop_frame(d);
        return EXTERIA_OK;
    }
    bytes = len - offset;
    if (bytes > d->capacity - d->length) {
        drop_frame(d);
        return EXTERIA_E_LIMIT;
    }
    memcpy(d->frame + d->length, payload + offset, bytes);
    d->length += bytes;
    if (!marker) return EXTERIA_OK;

    d->in_frame = 0;
    if (d->length < FRAME_TAG_MIN) {
        d->length = 0;
        d->need_key_frame = 1;
        ++d->dropped_frames;
        return EXTERIA_E_MALFORMED;
    }
    /* bit 0 of the frame tag is 0 for a key frame, which also carries the start code 9d 01 2a */
    info->key_frame = (uint8_t)!(d->frame[0] & 1);
    if (info->key_frame && (d->length < KEY_FRAME_TAG_MIN || d->frame[3] != 0x9D || d->frame[4] != 0x01 || d->frame[5] != 0x2A)) {
        d->length = 0;
        d->need_key_frame = 1;
        ++d->dropped_frames;
        memset(info, 0, sizeof(*info));
        return EXTERIA_E_MALFORMED;
    }
    if (info->key_frame) d->need_key_frame = 0;
    else if (d->need_key_frame) {
        ++d->dropped_frames;
        d->length = 0;
        info->key_frame = 0;
        return EXTERIA_OK;
    }
    info->ready = 1;
    info->length = d->length;
    info->timestamp = d->timestamp;
    return EXTERIA_OK;
}
