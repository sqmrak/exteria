#include "exteria_lrc.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

/* [mm:ss], [mm:ss.x], [mm:ss.xx] or [mm:ss.xxx] (also with : before the fraction) at p; returns the bytes taken, 0 when p does not hold a stamp */
static size_t parse_stamp(const char *p, const char *end, char close, uint32_t *ms) {
    const char *s = p;
    if (s >= end || *s != (close == ']' ? '[' : '<')) return 0;
    ++s;
    uint32_t minutes = 0;
    size_t digits = 0;
    while (s < end && isdigit((unsigned char)*s) && digits < 4) { minutes = minutes * 10 + (uint32_t)(*s - '0'); ++s; ++digits; }
    if (!digits || s >= end || *s != ':') return 0;
    ++s;
    uint32_t seconds = 0;
    digits = 0;
    while (s < end && isdigit((unsigned char)*s) && digits < 3) { seconds = seconds * 10 + (uint32_t)(*s - '0'); ++s; ++digits; }
    if (digits != 2 || seconds > 59) return 0;
    uint32_t fraction = 0, scale = 100;
    if (s < end && (*s == '.' || *s == ':')) {
        ++s;
        digits = 0;
        while (s < end && isdigit((unsigned char)*s) && digits < 3) { fraction += (uint32_t)(*s - '0') * scale; scale /= 10; ++s; ++digits; }
        if (!digits) return 0;
    }
    if (s >= end || *s != close) return 0;
    *ms = (minutes * 60u + seconds) * 1000u + fraction;
    return (size_t)(s + 1 - p);
}

/* stable, and quick on the usual file that is already in order */
static void sort_lines(exteria_lrc_line *lines, size_t count) {
    for (size_t i = 1; i < count; ++i) {
        exteria_lrc_line moving = lines[i];
        size_t j = i;
        while (j > 0 && lines[j - 1].start_ms > moving.start_ms) { lines[j] = lines[j - 1]; --j; }
        lines[j] = moving;
    }
}

void exteria_lrc_free(exteria_lrc *lrc) {
    if (!lrc) return;
    for (size_t i = 0; i < lrc->count; ++i) free(lrc->lines[i].text);
    free(lrc->lines);
    lrc->lines = NULL;
    lrc->count = 0;
}

exteria_status exteria_lrc_parse(const char *text, size_t len, exteria_lrc *out) {
    if (!out) return EXTERIA_E_ARG;
    out->lines = NULL;
    out->count = 0;
    if (!text && len) return EXTERIA_E_ARG;
    if (len > EXTERIA_LRC_INPUT_MAX) return EXTERIA_E_LIMIT;
    const char *p = text, *end = text + len;
    if (len >= 3 && (unsigned char)p[0] == 0xEF && (unsigned char)p[1] == 0xBB && (unsigned char)p[2] == 0xBF) p += 3;
    size_t cap = 0;
    exteria_lrc_line *lines = NULL;
    size_t count = 0;
    int stamped = 0;
    while (p < end && count < EXTERIA_LRC_LINES_MAX) {
        const char *eol = p;
        while (eol < end && *eol != '\n' && *eol != '\r') ++eol;
        const char *q = p;
        uint32_t stamps[16];
        size_t stamp_count = 0;
        for (;;) {
            while (q < eol && (*q == ' ' || *q == '\t')) ++q;
            uint32_t ms;
            size_t taken = parse_stamp(q, eol, ']', &ms);
            if (!taken) break;
            if (stamp_count < 16) stamps[stamp_count++] = ms;
            q += taken;
        }
        if (stamp_count) {
            stamped = 1;
            char buffer[EXTERIA_LRC_TEXT_MAX + 1];
            size_t n = 0;
            while (q < eol) {
                uint32_t ignored;
                size_t taken = parse_stamp(q, eol, '>', &ignored);
                if (taken) { q += taken; continue; }
                if (n < EXTERIA_LRC_TEXT_MAX) buffer[n++] = *q;
                ++q;
            }
            /* cut at a character boundary when the line was too long */
            if (n == EXTERIA_LRC_TEXT_MAX) while (n && ((unsigned char)buffer[n] & 0xC0) == 0x80) --n;
            while (n && (buffer[n - 1] == ' ' || buffer[n - 1] == '\t')) --n;
            size_t start = 0;
            while (start < n && (buffer[start] == ' ' || buffer[start] == '\t')) ++start;
            if (n > start) {
                for (size_t i = 0; i < stamp_count && count < EXTERIA_LRC_LINES_MAX; ++i) {
                    if (count == cap) {
                        size_t grown = cap ? cap * 2 : 64;
                        exteria_lrc_line *bigger = realloc(lines, grown * sizeof *lines);
                        if (!bigger) { for (size_t k = 0; k < count; ++k) free(lines[k].text); free(lines); return EXTERIA_E_NOMEM; }
                        lines = bigger;
                        cap = grown;
                    }
                    char *copy = malloc(n - start + 1);
                    if (!copy) { for (size_t k = 0; k < count; ++k) free(lines[k].text); free(lines); return EXTERIA_E_NOMEM; }
                    memcpy(copy, buffer + start, n - start);
                    copy[n - start] = 0;
                    lines[count].start_ms = stamps[i];
                    lines[count].text = copy;
                    ++count;
                }
            }
        }
        p = eol;
        while (p < end && (*p == '\n' || *p == '\r')) ++p;
    }
    if (!stamped || !count) {
        for (size_t k = 0; k < count; ++k) free(lines[k].text);
        free(lines);
        return EXTERIA_E_MALFORMED;
    }
    sort_lines(lines, count);
    out->lines = lines;
    out->count = count;
    return EXTERIA_OK;
}

long exteria_lrc_active(const exteria_lrc *lrc, uint32_t ms) {
    if (!lrc || !lrc->count) return -1;
    size_t low = 0, high = lrc->count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (lrc->lines[middle].start_ms <= ms) low = middle + 1;
        else high = middle;
    }
    return (long)low - 1;
}

static int word_at(const char *s, const char *word) {
    size_t n = strlen(word);
    for (size_t i = 0; i < n; ++i) if (tolower((unsigned char)s[i]) != word[i]) return 0;
    return 1;
}

/* where a credit " feat. X" begins: a space, then feat, ft or featuring, then a dot or a space or the end */
static const char *credit_start(const char *s) {
    static const char *const words[] = {"featuring", "feat", "ft"};
    for (const char *p = s; *p; ++p) {
        if (*p != ' ' && *p != '\t') continue;
        const char *w = p;
        while (*w == ' ' || *w == '\t') ++w;
        for (size_t i = 0; i < sizeof words / sizeof *words; ++i) {
            if (!word_at(w, words[i])) continue;
            const char *after = w + strlen(words[i]);
            if (*after == '.' || *after == ' ' || *after == '\t') return p;
        }
    }
    return NULL;
}

exteria_status exteria_lrc_search_text(const char *in, char *out, size_t cap) {
    if (!in || !out || !cap) return EXTERIA_E_ARG;
    size_t length = strlen(in);
    char *work = malloc(length + 1);
    if (!work) return EXTERIA_E_NOMEM;
    size_t n = 0;
    int square = 0, round = 0;
    for (size_t i = 0; i < length; ++i) {
        char c = in[i];
        if (c == '[') { ++square; continue; }
        if (c == ']') { if (square) --square; continue; }
        if (c == '(') { ++round; continue; }
        if (c == ')') { if (round) --round; continue; }
        if (!square && !round) work[n++] = c;
    }
    work[n] = 0;
    const char *credit = credit_start(work);
    if (credit) n = (size_t)(credit - work);
    work[n] = 0;
    const char *start = work, *stop = work + n;
    while (start < stop && isspace((unsigned char)*start)) ++start;
    while (stop > start && isspace((unsigned char)stop[-1])) --stop;
    if (start == stop) {
        start = in;
        stop = in + length;
        while (start < stop && isspace((unsigned char)*start)) ++start;
        while (stop > start && isspace((unsigned char)stop[-1])) --stop;
    }
    size_t size = (size_t)(stop - start);
    exteria_status status = EXTERIA_OK;
    if (size + 1 > cap) status = EXTERIA_E_LIMIT;
    else { memcpy(out, start, size); out[size] = 0; }
    free(work);
    return status;
}
