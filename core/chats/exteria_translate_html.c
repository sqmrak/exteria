#include "exteria_translate_html.h"

#include <string.h>

#define NESTING_MAX 64u

typedef struct writer {
    uint16_t *data;
    size_t cap;
    size_t len;
    int overflow;
} writer;

static void put(writer *w, uint16_t unit) {
    if (w->len < w->cap) w->data[w->len] = unit;
    else w->overflow = 1;
    ++w->len;
}

static void put_ascii(writer *w, const char *text) {
    while (*text) put(w, (uint16_t)(unsigned char)*text++);
}

static const char *tag_name(int32_t kind) {
    switch (kind) {
    case EXTERIA_TH_BOLD: return "b";
    case EXTERIA_TH_ITALIC: return "i";
    case EXTERIA_TH_UNDERLINE: return "u";
    case EXTERIA_TH_STRIKE: return "s";
    case EXTERIA_TH_CODE: return "tt";
    case EXTERIA_TH_LINK: return "a";
    default: return NULL;
    }
}

static void put_tag(writer *w, int32_t kind, int closing) {
    put(w, '<');
    if (closing) put(w, '/');
    put_ascii(w, tag_name(kind));
    put(w, '>');
}

exteria_status exteria_th_encode(const uint16_t *text, size_t len, const exteria_th_span *spans, size_t count, uint16_t *out, size_t cap, size_t *out_len) {
    exteria_th_span live[EXTERIA_TH_SPAN_MAX];
    size_t open[EXTERIA_TH_SPAN_MAX], depth = 0, kept = 0, i, pos;
    writer w;
    if (out_len) *out_len = 0;
    if ((!text && len) || (!spans && count) || !out || !out_len || !cap) return EXTERIA_E_ARG;
    if (len > EXTERIA_TH_TEXT_MAX || count > EXTERIA_TH_SPAN_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < count; ++i) {
        if (!tag_name(spans[i].kind) || !spans[i].length || spans[i].offset > len || spans[i].length > len - spans[i].offset) continue;
        live[kept++] = spans[i];
    }
    w.data = out;
    w.cap = cap;
    w.len = 0;
    w.overflow = 0;
    for (pos = 0; pos <= len; ++pos) {
        size_t lowest = depth, a, b;
        /* the spans that end here close; any span opened above one of them closes first and opens again after it, which keeps the tags nested */
        for (a = 0; a < depth; ++a) {
            if (live[open[a]].offset + live[open[a]].length == pos) {
                lowest = a;
                break;
            }
        }
        if (lowest < depth) {
            size_t reopen[EXTERIA_TH_SPAN_MAX], reopened = 0;
            for (a = depth; a > lowest; --a) put_tag(&w, live[open[a - 1]].kind, 1);
            for (a = lowest + 1; a < depth; ++a) {
                if (live[open[a]].offset + live[open[a]].length != pos) reopen[reopened++] = open[a];
            }
            depth = lowest;
            for (a = 0; a < reopened; ++a) {
                put_tag(&w, live[reopen[a]].kind, 0);
                open[depth++] = reopen[a];
            }
        }
        /* the spans that start here open, the longest first so that the shorter ones nest inside it */
        {
            size_t starting[EXTERIA_TH_SPAN_MAX], n = 0;
            for (a = 0; a < kept; ++a) {
                if (live[a].offset == pos) starting[n++] = a;
            }
            for (a = 1; a < n; ++a) {
                size_t item = starting[a];
                uint32_t end = live[item].offset + live[item].length;
                for (b = a; b > 0 && live[starting[b - 1]].offset + live[starting[b - 1]].length < end; --b) starting[b] = starting[b - 1];
                starting[b] = item;
            }
            for (a = 0; a < n; ++a) {
                put_tag(&w, live[starting[a]].kind, 0);
                open[depth++] = starting[a];
            }
        }
        if (pos < len) put(&w, text[pos] == '<' ? 0x2027 : text[pos]);
    }
    if (w.overflow) return EXTERIA_E_LIMIT;
    *out_len = w.len;
    return EXTERIA_OK;
}

typedef struct frame {
    int32_t kind;
    size_t start;
} frame;

static int ends_with_space(const writer *w) {
    return w->len && w->len <= w->cap && w->data[w->len - 1] == ' ';
}

static int lower(uint16_t unit) {
    return unit >= 'A' && unit <= 'Z' ? unit + 32 : unit;
}

/* the kind a tag name stands for, 0 for a name that is dropped, -1 for a line break */
static int32_t kind_of_tag(const char *name, size_t length) {
    struct { const char *name; int32_t kind; } known[] = {
        {"b", EXTERIA_TH_BOLD}, {"strong", EXTERIA_TH_BOLD}, {"i", EXTERIA_TH_ITALIC}, {"em", EXTERIA_TH_ITALIC}, {"u", EXTERIA_TH_UNDERLINE},
        {"s", EXTERIA_TH_STRIKE}, {"strike", EXTERIA_TH_STRIKE}, {"del", EXTERIA_TH_STRIKE}, {"tt", EXTERIA_TH_CODE}, {"code", EXTERIA_TH_CODE},
        {"a", EXTERIA_TH_LINK}, {"br", -1}
    };
    size_t i;
    for (i = 0; i < sizeof(known) / sizeof(known[0]); ++i) {
        if (strlen(known[i].name) == length && memcmp(known[i].name, name, length) == 0) return known[i].kind;
    }
    return 0;
}

/* a character reference at markup[at] == '&': the unit it stands for and how many units it spans, or 0 when it is no reference */
static size_t read_reference(const uint16_t *markup, size_t len, size_t at, uint32_t *value) {
    char name[12];
    size_t n = 0, i = at + 1;
    uint32_t number = 0;
    int digits = 0;
    if (i < len && markup[i] == '#') {
        int hex = 0;
        ++i;
        if (i < len && (markup[i] == 'x' || markup[i] == 'X')) {
            hex = 1;
            ++i;
        }
        for (; i < len && i - at < 11; ++i) {
            uint16_t c = markup[i];
            uint32_t digit;
            if (c >= '0' && c <= '9') digit = (uint32_t)(c - '0');
            else if (hex && c >= 'a' && c <= 'f') digit = (uint32_t)(c - 'a' + 10);
            else if (hex && c >= 'A' && c <= 'F') digit = (uint32_t)(c - 'A' + 10);
            else break;
            number = number * (hex ? 16u : 10u) + digit;
            ++digits;
        }
        if (!digits || i >= len || markup[i] != ';' || !number || number > 0x10FFFFu) return 0;
        *value = number;
        return i - at + 1;
    }
    for (; i < len && n < sizeof(name) - 1; ++i) {
        uint16_t c = markup[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) break;
        name[n++] = (char)lower(c);
    }
    if (!n || i >= len || markup[i] != ';') return 0;
    name[n] = 0;
    if (!strcmp(name, "amp")) *value = '&';
    else if (!strcmp(name, "lt")) *value = '<';
    else if (!strcmp(name, "gt")) *value = '>';
    else if (!strcmp(name, "quot")) *value = '"';
    else if (!strcmp(name, "apos")) *value = '\'';
    else if (!strcmp(name, "nbsp")) *value = 0xA0;
    else return 0;
    return i - at + 1;
}

/* a tag at markup[at] == '<': its kind and the length of it, or 0 length when the bracket is plain text */
static size_t read_tag(const uint16_t *markup, size_t len, size_t at, int *closing, int32_t *kind, int *known) {
    size_t i = at + 1, end, name_start, name_len;
    char name[12];
    *closing = 0;
    *known = 0;
    while (i < len && markup[i] == ' ') ++i;
    if (i < len && markup[i] == '/') {
        *closing = 1;
        ++i;
        while (i < len && markup[i] == ' ') ++i;
    }
    name_start = i;
    while (i < len && ((markup[i] >= 'a' && markup[i] <= 'z') || (markup[i] >= 'A' && markup[i] <= 'Z') || (markup[i] >= '0' && markup[i] <= '9') || markup[i] == '-')) ++i;
    name_len = i - name_start;
    if (!name_len) return 0;
    for (end = i; end < len && markup[end] != '>' && markup[end] != '<'; ++end) {
    }
    if (end >= len || markup[end] != '>') return 0;
    if (name_len < sizeof(name)) {
        size_t k;
        for (k = 0; k < name_len; ++k) name[k] = (char)lower(markup[name_start + k]);
        *kind = kind_of_tag(name, name_len);
        *known = *kind != 0;
    } else {
        *kind = 0;
    }
    return end - at + 1;
}

static void close_frame(frame *stack, size_t *depth, size_t index, size_t end, exteria_th_span *spans, size_t span_cap, size_t *count, int *overflow) {
    size_t top;
    /* everything opened above the closed tag ends with it */
    for (top = *depth; top > index; --top) {
        frame f = stack[top - 1];
        if (end > f.start) {
            if (*count < span_cap && *count < EXTERIA_TH_SPAN_MAX) {
                spans[*count].kind = f.kind;
                spans[*count].offset = (uint32_t)f.start;
                spans[*count].length = (uint32_t)(end - f.start);
                ++*count;
            } else {
                *overflow = 1;
            }
        }
    }
    *depth = index;
}

exteria_status exteria_th_decode(const uint16_t *markup, size_t len, uint16_t *out, size_t out_cap, size_t *out_len, exteria_th_span *spans, size_t span_cap,
                                 size_t *span_count) {
    frame stack[NESTING_MAX];
    size_t depth = 0, i = 0, count = 0, a, b;
    writer w;
    int overflow = 0;
    if (out_len) *out_len = 0;
    if (span_count) *span_count = 0;
    if ((!markup && len) || !out || !out_len || !out_cap || !spans || !span_count) return EXTERIA_E_ARG;
    if (len > EXTERIA_TH_TEXT_MAX * 2u) return EXTERIA_E_LIMIT;
    w.data = out;
    w.cap = out_cap;
    w.len = 0;
    w.overflow = 0;
    while (i < len) {
        uint16_t unit = markup[i];
        if (unit == '<') {
            int closing, known;
            int32_t kind = 0;
            size_t used = read_tag(markup, len, i, &closing, &kind, &known);
            if (used) {
                if (kind == -1) {
                    if (!closing) put(&w, '\n');
                } else if (known && !closing) {
                    /* a translator pads a tag with a space on each side; one of them goes */
                    if (depth < NESTING_MAX) {
                        stack[depth].kind = kind;
                        stack[depth].start = w.len;
                        ++depth;
                    }
                    if (ends_with_space(&w) && i + used < len && markup[i + used] == ' ') ++used;
                } else if (known) {
                    size_t index = depth;
                    while (index > 0 && stack[index - 1].kind != kind) --index;
                    if (index > 0) {
                        if (ends_with_space(&w) && i + used < len && markup[i + used] == ' ' && w.len - 1 > stack[index - 1].start) --w.len;
                        close_frame(stack, &depth, index - 1, w.len, spans, span_cap, &count, &overflow);
                    }
                }
                i += used;
                continue;
            }
        }
        if (unit == '&') {
            uint32_t value = 0;
            size_t used = read_reference(markup, len, i, &value);
            if (used) {
                if (value >= 0x10000u) {
                    put(&w, (uint16_t)(0xD800u + ((value - 0x10000u) >> 10)));
                    put(&w, (uint16_t)(0xDC00u + ((value - 0x10000u) & 0x3FFu)));
                } else {
                    put(&w, (uint16_t)value);
                }
                i += used;
                continue;
            }
        }
        if (unit == 0x2027) unit = '<';
        else if (unit == 0x2029) unit = '\n';
        put(&w, unit);
        ++i;
    }
    if (w.overflow) return EXTERIA_E_LIMIT;
    /* a single line break at the end is the translator's, not the author's */
    if (w.len && (w.data[w.len - 1] == '\n' || w.data[w.len - 1] == '\r')) --w.len;
    close_frame(stack, &depth, 0, w.len, spans, span_cap, &count, &overflow);
    if (overflow) return EXTERIA_E_LIMIT;
    /* a span that started in the cut line break ends where the text does */
    for (a = 0; a < count; ++a) {
        if (spans[a].offset >= w.len) spans[a].length = 0;
        else if (spans[a].offset + spans[a].length > w.len) spans[a].length = (uint32_t)(w.len - spans[a].offset);
    }
    for (a = 0, b = 0; a < count; ++a) {
        if (spans[a].length) spans[b++] = spans[a];
    }
    count = b;
    for (a = 1; a < count; ++a) {
        exteria_th_span item = spans[a];
        for (b = a; b > 0 && (spans[b - 1].offset > item.offset || (spans[b - 1].offset == item.offset && spans[b - 1].length < item.length)); --b) spans[b] = spans[b - 1];
        spans[b] = item;
    }
    *out_len = w.len;
    *span_count = count;
    return EXTERIA_OK;
}
