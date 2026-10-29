#include "exteria_article.h"

#include <string.h>

static int ascii_alpha(uint8_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static int name_matches(const uint8_t *data, size_t length, const char *name) {
    size_t n = strlen(name), i;
    if (length < n) return 0;
    for (i = 0; i < n; ++i) {
        uint8_t c = data[i];
        if (c >= 'A' && c <= 'Z') c = (uint8_t)(c + ('a' - 'A'));
        if (c != (uint8_t)name[i]) return 0;
    }
    return length == n || data[n] == '>' || data[n] == '/' || data[n] == ' ' || data[n] == '\t' || data[n] == '\r' || data[n] == '\n' || data[n] == '\f';
}

static size_t tag_end(const uint8_t *html, size_t length, size_t start) {
    uint8_t quote = 0;
    for (size_t i = start; i < length; ++i) {
        uint8_t c = html[i];
        if (quote) { if (c == quote) quote = 0; }
        else if (c == '\'' || c == '"') quote = c;
        else if (c == '>') return i + 1;
    }
    return length;
}

static size_t raw_end(const uint8_t *html, size_t length, size_t start, const char *name) {
    for (size_t i = start; i + 2 < length; ++i) {
        if (html[i] == '<' && html[i + 1] == '/' && name_matches(html + i + 2, length - i - 2, name)) {
            size_t end = tag_end(html, length, i + 2);
            if (end <= length && html[end - 1] == '>') return end;
            return 0;
        }
    }
    return 0;
}

exteria_status exteria_article_readonly(const uint8_t *html, size_t length, uint8_t *out, size_t capacity, size_t *written) {
    size_t pos = 0, used = 0;
    if (written) *written = 0;
    if (!written || (!html && length) || (!out && capacity)) return EXTERIA_E_ARG;
    if (capacity < length) return EXTERIA_E_LIMIT;
    while (pos < length) {
        size_t end = pos + 1;
        int omit = 0;
        if (html[pos] == '<' && pos + 3 < length && !memcmp(html + pos, "<!--", 4)) {
            end = pos + 4;
            while (end + 2 < length && memcmp(html + end, "-->", 3)) ++end;
            end = end + 2 < length ? end + 3 : length;
        } else if (html[pos] == '<' && pos + 1 < length && (ascii_alpha(html[pos + 1]) || html[pos + 1] == '/' || html[pos + 1] == '!' || html[pos + 1] == '?')) {
            const char *raw = NULL;
            if (name_matches(html + pos + 1, length - pos - 1, "script")) { raw = "script"; omit = 1; }
            else if (name_matches(html + pos + 1, length - pos - 1, "style")) raw = "style";
            else if (name_matches(html + pos + 1, length - pos - 1, "textarea")) raw = "textarea";
            else if (name_matches(html + pos + 1, length - pos - 1, "title")) raw = "title";
            end = tag_end(html, length, pos + 1);
            if (raw && (end == length && html[end - 1] != '>')) return EXTERIA_E_MALFORMED;
            if (raw) {
                size_t close = raw_end(html, length, end, raw);
                if (!close) return EXTERIA_E_MALFORMED;
                end = close;
            }
        }
        if (!omit) { memcpy(out + used, html + pos, end - pos); used += end - pos; }
        pos = end;
    }
    *written = used;
    return EXTERIA_OK;
}
