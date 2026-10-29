#include "exteria_id3.h"

#include <string.h>

#define FLAG_UNSYNC 0x80u
#define FLAG_EXTENDED 0x40u
#define PICTURE_FRONT 3u

/* four bytes of seven bits each */
static int read_syncsafe(const uint8_t *p, uint32_t *out) {
    if ((p[0] | p[1] | p[2] | p[3]) & 0x80u) return 0;
    *out = ((uint32_t)p[0] << 21) | ((uint32_t)p[1] << 14) | ((uint32_t)p[2] << 7) | p[3];
    return 1;
}

static uint32_t read_u32be(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

exteria_status exteria_id3_tag_size(const uint8_t *head, size_t len, size_t *tag_size) {
    uint32_t size;
    if (tag_size) *tag_size = 0;
    if (!head || !tag_size || len < EXTERIA_ID3_HEADER) return EXTERIA_E_ARG;
    if (memcmp(head, "ID3", 3) != 0) return EXTERIA_E_NOTFOUND;
    if (head[3] < 2 || head[3] > 4 || head[4] == 0xFF || !read_syncsafe(head + 6, &size)) return EXTERIA_E_MALFORMED;
    /* the unsynchronisation of a whole tag changes its byte count, and version 2.2 sets the next bit for a compressed tag */
    if (head[5] & FLAG_UNSYNC) return EXTERIA_E_UNSUPPORTED;
    if (head[3] == 2 && (head[5] & FLAG_EXTENDED)) return EXTERIA_E_UNSUPPORTED;
    if (size > EXTERIA_ID3_TAG_MAX - EXTERIA_ID3_HEADER) return EXTERIA_E_LIMIT;
    *tag_size = EXTERIA_ID3_HEADER + size;
    return EXTERIA_OK;
}

/* the offset of the picture bytes inside a frame body that holds one, 0 when the body is no usable picture; type receives the picture type */
static size_t picture_start(const uint8_t *body, size_t len, int v22, uint8_t *type) {
    size_t pos = 1;
    uint8_t encoding;
    if (len < 4) return 0;
    encoding = body[0];
    if (encoding > 3) return 0;
    if (v22) {
        pos += 3;
    } else {
        /* the type of the picture, as a text ended by a zero byte; "-->" says the data is a link and not a picture */
        while (pos < len && body[pos]) ++pos;
        if (pos >= len) return 0;
        if (pos == 4 && !memcmp(body + 1, "-->", 3)) return 0;
        ++pos;
    }
    if (pos >= len) return 0;
    *type = body[pos++];
    /* the description ends with one zero byte, or with two on an even position for the two UTF-16 encodings */
    if (encoding == 1 || encoding == 2) {
        for (;;) {
            if (pos + 1 >= len) return 0;
            if (!body[pos] && !body[pos + 1]) {
                pos += 2;
                break;
            }
            pos += 2;
        }
    } else {
        while (pos < len && body[pos]) ++pos;
        if (pos >= len) return 0;
        ++pos;
    }
    return pos < len ? pos : 0;
}

exteria_status exteria_id3_cover(const uint8_t *data, size_t len, size_t *offset, size_t *size) {
    size_t tag_size = 0, pos, end, found_offset = 0, found_size = 0;
    uint8_t version;
    int found = 0;
    exteria_status status;
    if (offset) *offset = 0;
    if (size) *size = 0;
    if (!data || !offset || !size) return EXTERIA_E_ARG;
    if (len < EXTERIA_ID3_HEADER) return EXTERIA_E_TRUNCATED;
    status = exteria_id3_tag_size(data, len, &tag_size);
    if (status != EXTERIA_OK) return status;
    version = data[3];
    end = len < tag_size ? len : tag_size;
    pos = EXTERIA_ID3_HEADER;
    if (version != 2 && (data[5] & FLAG_EXTENDED)) {
        uint32_t extended;
        if (end < pos + 4) return len < tag_size ? EXTERIA_E_TRUNCATED : EXTERIA_E_MALFORMED;
        if (version == 4) {
            if (!read_syncsafe(data + pos, &extended) || extended < 6) return EXTERIA_E_MALFORMED;
            pos += extended;
        } else {
            extended = read_u32be(data + pos);
            if (extended > tag_size) return EXTERIA_E_MALFORMED;
            pos += 4 + (size_t)extended;
        }
    }
    for (;;) {
        size_t header = version == 2 ? 6 : 10, frame_size, body_start, body_end;
        uint16_t flags = 0;
        int v22 = version == 2, usable = 1;
        uint8_t type = 0;
        size_t start;
        if (pos + header > tag_size) break;
        if (pos + header > end) {
            if (len < tag_size) {
                if (found) break;
                return EXTERIA_E_TRUNCATED;
            }
            return EXTERIA_E_MALFORMED;
        }
        /* a zero byte where an identifier should be starts the padding, which runs to the end of the tag */
        if (!data[pos]) break;
        if (v22) {
            frame_size = ((size_t)data[pos + 3] << 16) | ((size_t)data[pos + 4] << 8) | data[pos + 5];
        } else if (version == 4) {
            uint32_t value;
            if (!read_syncsafe(data + pos + 4, &value)) return EXTERIA_E_MALFORMED;
            frame_size = value;
            flags = (uint16_t)((data[pos + 8] << 8) | data[pos + 9]);
        } else {
            frame_size = read_u32be(data + pos + 4);
            flags = (uint16_t)((data[pos + 8] << 8) | data[pos + 9]);
        }
        if (frame_size > tag_size - (pos + header)) return EXTERIA_E_MALFORMED;
        body_start = pos + header;
        body_end = body_start + frame_size;
        if ((v22 ? !memcmp(data + pos, "PIC", 3) : !memcmp(data + pos, "APIC", 4))) {
            if (body_end > end) {
                if (len < tag_size) {
                    if (found) break;
                    return EXTERIA_E_TRUNCATED;
                }
                return EXTERIA_E_MALFORMED;
            }
            if (version == 3) {
                /* compression and encryption bits; the group byte comes first */
                if (flags & 0x00C0u) usable = 0;
                else if (flags & 0x0020u) ++body_start;
            } else if (version == 4) {
                if (flags & 0x000Eu) usable = 0;
                else {
                    if (flags & 0x0040u) ++body_start;
                    if (flags & 0x0001u) body_start += 4;
                }
            }
            if (usable && body_start < body_end) {
                start = picture_start(data + body_start, body_end - body_start, v22, &type);
                if (start) {
                    size_t at = body_start + start, bytes = body_end - at;
                    if (type == PICTURE_FRONT) {
                        *offset = at;
                        *size = bytes;
                        return EXTERIA_OK;
                    }
                    if (!found) {
                        found = 1;
                        found_offset = at;
                        found_size = bytes;
                    }
                }
            }
        }
        pos = body_end;
        if (pos > end) break;
    }
    if (found) {
        *offset = found_offset;
        *size = found_size;
        return EXTERIA_OK;
    }
    return len < tag_size ? EXTERIA_E_TRUNCATED : EXTERIA_E_NOTFOUND;
}
