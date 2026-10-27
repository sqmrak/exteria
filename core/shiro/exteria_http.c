#include "exteria_http.h"

#include <string.h>

static int is_token_char(uint8_t c) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return 1;
    return c && strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

static int iequal(const uint8_t *a, size_t alen, const char *b) {
    size_t i;
    if (alen != strlen(b)) return 0;
    for (i = 0; i < alen; ++i) {
        uint8_t x = a[i], y = (uint8_t)b[i];
        if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32);
        if (y >= 'A' && y <= 'Z') y = (uint8_t)(y + 32);
        if (x != y) return 0;
    }
    return 1;
}

/* the position of the CRLF that ends the line starting at from, or len when there is none */
static size_t find_crlf(const uint8_t *data, size_t len, size_t from) {
    size_t i;
    for (i = from; i + 1 < len; ++i) {
        if (data[i] == '\r' && data[i + 1] == '\n') return i;
    }
    return len;
}

static int hex_digit(uint8_t c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static exteria_status decode_chunked(const uint8_t *data, size_t len, int eof, uint8_t *body, size_t cap, size_t *body_len) {
    size_t pos = 0, out = 0;
    for (;;) {
        size_t line_end = find_crlf(data, len, pos), size = 0, digits = 0;
        if (line_end >= len) return len - pos > 64 ? EXTERIA_E_MALFORMED : EXTERIA_E_TRUNCATED;
        while (pos + digits < line_end && hex_digit(data[pos + digits]) >= 0) {
            size = size << 4 | (size_t)hex_digit(data[pos + digits]);
            if (++digits > 8) return EXTERIA_E_MALFORMED;
        }
        if (digits == 0) return EXTERIA_E_MALFORMED;
        /* chunk extensions are allowed and ignored, nothing else may follow the size */
        if (pos + digits < line_end && data[pos + digits] != ';') return EXTERIA_E_MALFORMED;
        pos = line_end + 2;
        if (size == 0) {
            /* trailers, then the empty line */
            for (;;) {
                size_t end = find_crlf(data, len, pos);
                if (end >= len) return EXTERIA_E_TRUNCATED;
                if (end == pos) {
                    *body_len = out;
                    return EXTERIA_OK;
                }
                pos = end + 2;
            }
        }
        if (size > cap - out) return EXTERIA_E_LIMIT;
        if (len - pos < size + 2) return EXTERIA_E_TRUNCATED;
        memcpy(body + out, data + pos, size);
        out += size;
        pos += size;
        if (data[pos] != '\r' || data[pos + 1] != '\n') return EXTERIA_E_MALFORMED;
        pos += 2;
    }
    (void)eof;
}

exteria_status exteria_http_parse_head(const uint8_t *data, size_t len, int eof, exteria_http_head *out) {
    size_t pos, line_end;
    int status, i;
    if (out) memset(out, 0, sizeof(*out));
    if (!data || !out) return EXTERIA_E_ARG;
    line_end = find_crlf(data, len, 0);
    if (line_end >= len) return len > 512 ? EXTERIA_E_MALFORMED : (eof ? EXTERIA_E_MALFORMED : EXTERIA_E_TRUNCATED);
    if (line_end < 12 || memcmp(data, "HTTP/1.", 7) != 0 || (data[7] != '0' && data[7] != '1') || data[8] != ' ') return EXTERIA_E_MALFORMED;
    status = 0;
    for (i = 9; i < 12; ++i) {
        if (data[i] < '0' || data[i] > '9') return EXTERIA_E_MALFORMED;
        status = status * 10 + (data[i] - '0');
    }
    if (status < 100 || status > 599 || (line_end > 12 && data[12] != ' ')) return EXTERIA_E_MALFORMED;
    /* an interim answer would be followed by the real one; a registration call never asks for that, so it is a sign of something else answering */
    if (status < 200) return EXTERIA_E_MALFORMED;
    pos = line_end + 2;
    for (;;) {
        size_t end = find_crlf(data, len, pos), colon, name_len, vstart, vend;
        if (pos > EXTERIA_HTTP_MAX_HEADERS) return EXTERIA_E_LIMIT;
        if (end >= len) return eof ? EXTERIA_E_MALFORMED : EXTERIA_E_TRUNCATED;
        if (end == pos) {
            out->body_start = pos + 2;
            break;
        }
        for (colon = pos; colon < end && data[colon] != ':'; ++colon) {
            if (!is_token_char(data[colon])) return EXTERIA_E_MALFORMED;
        }
        if (colon == pos || colon >= end) return EXTERIA_E_MALFORMED;
        name_len = colon - pos;
        vstart = colon + 1;
        while (vstart < end && (data[vstart] == ' ' || data[vstart] == '\t')) ++vstart;
        vend = end;
        while (vend > vstart && (data[vend - 1] == ' ' || data[vend - 1] == '\t')) --vend;
        if (iequal(data + pos, name_len, "content-length")) {
            size_t k, value = 0;
            if (vend == vstart || vend - vstart > 9) return EXTERIA_E_MALFORMED;
            for (k = vstart; k < vend; ++k) {
                if (data[k] < '0' || data[k] > '9') return EXTERIA_E_MALFORMED;
                value = value * 10 + (size_t)(data[k] - '0');
            }
            if (out->has_length && value != out->content_length) return EXTERIA_E_MALFORMED;
            out->has_length = 1;
            out->content_length = value;
        } else if (iequal(data + pos, name_len, "transfer-encoding")) {
            if (!iequal(data + vstart, vend - vstart, "chunked")) return EXTERIA_E_MALFORMED;
            out->chunked = 1;
        } else if (iequal(data + pos, name_len, "location")) {
            size_t k;
            if (vend - vstart >= sizeof(out->location)) return EXTERIA_E_LIMIT;
            for (k = vstart; k < vend; ++k) {
                if (data[k] < 0x21 || data[k] > 0x7E) return EXTERIA_E_MALFORMED;
            }
            memcpy(out->location, data + vstart, vend - vstart);
            out->location[vend - vstart] = 0;
        }
        pos = end + 2;
    }
    if (out->chunked && out->has_length) return EXTERIA_E_MALFORMED;
    out->status = status;
    return EXTERIA_OK;
}

exteria_status exteria_http_parse_response(const uint8_t *data, size_t len, int eof, exteria_http_response *out, uint8_t *body, size_t cap) {
    exteria_http_head head;
    exteria_status parsed;
    if (out) memset(out, 0, sizeof(*out));
    if (!data || !out || (cap && !body)) return EXTERIA_E_ARG;
    parsed = exteria_http_parse_head(data, len, eof, &head);
    if (parsed != EXTERIA_OK) return parsed;
    out->status = head.status;
    if (head.status == 204 || head.status == 304) return EXTERIA_OK;
    if (head.chunked) return decode_chunked(data + head.body_start, len - head.body_start, eof, body, cap, &out->body_len);
    if (head.has_length) {
        if (head.content_length > cap) return EXTERIA_E_LIMIT;
        if (len - head.body_start < head.content_length) return EXTERIA_E_TRUNCATED;
        memcpy(body, data + head.body_start, head.content_length);
        out->body_len = head.content_length;
        return EXTERIA_OK;
    }
    /* no framing: the body runs to the end of the connection */
    if (!eof) return EXTERIA_E_TRUNCATED;
    if (len - head.body_start > cap) return EXTERIA_E_LIMIT;
    memcpy(body, data + head.body_start, len - head.body_start);
    out->body_len = len - head.body_start;
    return EXTERIA_OK;
}
