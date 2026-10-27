#include "exteria_notify.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STATE_VERSION 1
#define STATE_ENTRY_BYTES 16

void exteria_notify_state_init(exteria_notify_state *state) {
    if (state) memset(state, 0, sizeof(*state));
}

/* copies text into a field of cap bytes, cutting at a character boundary, and turns line breaks and tabs into spaces */
static void copy_clean(char *dst, size_t cap, const char *src) {
    size_t len = strlen(src), i;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && ((unsigned char)src[len] & 0xC0u) == 0x80u) --len;
    }
    for (i = 0; i < len; ++i) {
        char c = src[i];
        dst[i] = c == '\n' || c == '\r' || c == '\t' ? ' ' : c;
    }
    dst[len] = 0;
}

static const char *media_word(exteria_preview_kind kind, int russian) {
    static const char *const en[] = {"", "", "Photo", "Video", "Video message", "Voice message", "Audio", "Sticker", "GIF", "File", "Location",
                                     "Contact", "Poll", "", "Message"};
    static const char *const ru[] = {"", "", "\xD0\xA4\xD0\xBE\xD1\x82\xD0\xBE", "\xD0\x92\xD0\xB8\xD0\xB4\xD0\xB5\xD0\xBE",
                                     "\xD0\x92\xD0\xB8\xD0\xB4\xD0\xB5\xD0\xBE\xD1\x81\xD0\xBE\xD0\xBE\xD0\xB1\xD1\x89\xD0\xB5\xD0\xBD\xD0\xB8\xD0\xB5",
                                     "\xD0\x93\xD0\xBE\xD0\xBB\xD0\xBE\xD1\x81\xD0\xBE\xD0\xB2\xD0\xBE\xD0\xB5 \xD1\x81\xD0\xBE\xD0\xBE\xD0\xB1\xD1\x89\xD0\xB5\xD0\xBD\xD0\xB8\xD0\xB5",
                                     "\xD0\x90\xD1\x83\xD0\xB4\xD0\xB8\xD0\xBE", "\xD0\xA1\xD1\x82\xD0\xB8\xD0\xBA\xD0\xB5\xD1\x80", "GIF",
                                     "\xD0\xA4\xD0\xB0\xD0\xB9\xD0\xBB", "\xD0\x93\xD0\xB5\xD0\xBE\xD0\xBF\xD0\xBE\xD0\xB7\xD0\xB8\xD1\x86\xD0\xB8\xD1\x8F",
                                     "\xD0\x9A\xD0\xBE\xD0\xBD\xD1\x82\xD0\xB0\xD0\xBA\xD1\x82", "\xD0\x9E\xD0\xBF\xD1\x80\xD0\xBE\xD1\x81",
                                     "", "\xD0\xA1\xD0\xBE\xD0\xBE\xD0\xB1\xD1\x89\xD0\xB5\xD0\xBD\xD0\xB8\xD0\xB5"};
    if ((int)kind < 0 || (size_t)kind >= sizeof(en) / sizeof(en[0])) kind = EXTERIA_PREVIEW_OTHER;
    return russian ? ru[kind] : en[kind];
}

static const char *plain_word(int russian) {
    return russian ? "\xD0\x9D\xD0\xBE\xD0\xB2\xD0\xBE\xD0\xB5 \xD1\x81\xD0\xBE\xD0\xBE\xD0\xB1\xD1\x89\xD0\xB5\xD0\xBD\xD0\xB8\xD0\xB5" : "New message";
}

static void write_event(exteria_notify_event *event, const exteria_dialog_row *row, const exteria_notify_settings *settings, const exteria_notify_decision *decision) {
    /* room for a sender, the text and the separator whole; copy_clean then cuts to the field */
    char body[EXTERIA_DIALOG_SENDER_MAX + EXTERIA_DIALOG_TEXT_MAX + 8];
    const char *text;
    memset(event, 0, sizeof(*event));
    event->peer_kind = row->peer_kind;
    event->peer_id = row->peer_id;
    event->message_id = row->top_message;
    copy_clean(event->title, sizeof(event->title), row->title[0] ? row->title : "Telegram");
    event->sound = decision->sound;
    if (decision->previews) {
        text = row->text[0] ? row->text : media_word(row->preview, settings->russian);
        if (!text[0]) text = plain_word(settings->russian);
        if (row->sender[0] && (row->kind == EXTERIA_DIALOG_GROUP || row->kind == EXTERIA_DIALOG_CHANNEL)) snprintf(body, sizeof(body), "%s: %s", row->sender, text);
        else snprintf(body, sizeof(body), "%s", text);
    } else {
        snprintf(body, sizeof(body), "%s", plain_word(settings->russian));
    }
    copy_clean(event->body, sizeof(event->body), body);
}

/* the decision for a chat: its own settings over those of its kind, and the two kinds of service message that have a switch of their own */
static int wanted(const exteria_dialog_row *row, const exteria_notify_settings *settings, int32_t now, exteria_notify_decision *decision) {
    exteria_notify_decide(&settings->rules, exteria_notify_scope_of(row->peer_kind, row->kind == EXTERIA_DIALOG_CHANNEL), &row->notify, now, decision);
    if (!decision->notify) return 0;
    if (row->service == EXTERIA_SERVICE_PIN + 1 && !settings->rules.pinned_messages) return 0;
    if (row->service == EXTERIA_SERVICE_CONTACT_JOINED + 1 && !settings->rules.contact_joined) return 0;
    return 1;
}

/* index of the chat in the state, or -1 */
static int find_seen(const exteria_notify_state *state, int32_t kind, int64_t id) {
    uint32_t i;
    for (i = 0; i < state->count; ++i) {
        if (state->seen[i].peer_kind == kind && state->seen[i].peer_id == id) return (int)i;
    }
    return -1;
}

static void remember(exteria_notify_state *state, int32_t kind, int64_t id, int32_t top) {
    int at = find_seen(state, kind, id);
    if (at < 0) {
        if (state->count == EXTERIA_NOTIFY_SEEN_MAX) {
            /* the oldest remembered chat makes room */
            memmove(&state->seen[0], &state->seen[1], sizeof(state->seen[0]) * (EXTERIA_NOTIFY_SEEN_MAX - 1));
            --state->count;
        }
        at = (int)state->count++;
        state->seen[at].peer_kind = kind;
        state->seen[at].peer_id = id;
    }
    state->seen[at].top_message = top;
}

exteria_status exteria_notify_diff(exteria_notify_state *state, const exteria_notify_settings *settings, const exteria_dialog_row *rows, size_t row_count,
                                   int32_t now, int32_t active_peer_kind, int64_t active_peer_id, exteria_notify_event *events, size_t cap,
                                   size_t *count, size_t *more_suppressed) {
    size_t i, found = 0, kept, skip;
    /* candidates newest first, as the server lists them; only their rows are kept, so the cap can drop the oldest */
    const exteria_dialog_row *candidates[EXTERIA_DIALOGS_MAX];
    exteria_notify_decision decisions[EXTERIA_DIALOGS_MAX];
    int baselining;
    if (!state || !settings || !count || !more_suppressed || (!rows && row_count) || (!events && cap)) return EXTERIA_E_ARG;
    *count = 0;
    *more_suppressed = 0;
    if (row_count > EXTERIA_DIALOGS_MAX) row_count = EXTERIA_DIALOGS_MAX;
    baselining = !state->baselined;
    for (i = 0; i < row_count; ++i) {
        const exteria_dialog_row *row = &rows[i];
        int at, fresh;
        if (row->folder || row->deleted || row->peer_id == 0) continue;
        at = find_seen(state, row->peer_kind, row->peer_id);
        fresh = at < 0 ? row->top_message > 0 : row->top_message > state->seen[at].top_message;
        remember(state, row->peer_kind, row->peer_id, at >= 0 && state->seen[at].top_message > row->top_message ? state->seen[at].top_message : row->top_message);
        if (baselining || !fresh || !settings->enabled) continue;
        if (row->saved || row->outgoing || row->unread_count <= 0 || row->top_message <= row->read_inbox_max_id) continue;
        if (!wanted(row, settings, now, &decisions[found])) continue;
        if (active_peer_id != 0 && row->peer_kind == active_peer_kind && row->peer_id == active_peer_id) continue;
        /* a chat that was not seen before and whose message is old is old news, not a new message */
        if (now > row->date && now - row->date > EXTERIA_NOTIFY_CATCHUP_SECONDS) continue;
        candidates[found++] = row;
    }
    state->baselined = 1;
    kept = found < cap ? found : cap;
    skip = found - kept;
    /* the newest kept chats go out, oldest of them first */
    for (i = 0; i < kept; ++i) write_event(&events[i], candidates[kept - 1 - i], settings, &decisions[kept - 1 - i]);
    *count = kept;
    *more_suppressed = skip;
    return EXTERIA_OK;
}

void exteria_notify_more_text(const exteria_notify_settings *settings, size_t more, char *out, size_t cap) {
    if (!out || cap == 0) return;
    if (settings && settings->russian) {
        /* "и ещё n" with the plural of the word for messages left to the reader: the count and a neutral word */
        snprintf(out, cap, "\xD0\x98 \xD0\xB5\xD1\x89\xD1\x91: %lu", (unsigned long)more);
    } else {
        snprintf(out, cap, "And %lu more", (unsigned long)more);
    }
}

static void put_u32(uint8_t *p, uint32_t v) {
    int i;
    for (i = 0; i < 4; ++i) p[i] = (uint8_t)(v >> (8 * i));
}

static void put_u64(uint8_t *p, uint64_t v) {
    int i;
    for (i = 0; i < 8; ++i) p[i] = (uint8_t)(v >> (8 * i));
}

static uint32_t get_u32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint64_t get_u64(const uint8_t *p) {
    uint64_t v = 0;
    int i;
    for (i = 7; i >= 0; --i) v = v << 8 | p[i];
    return v;
}

exteria_status exteria_notify_state_pack(const exteria_notify_state *state, uint8_t *out, size_t cap, size_t *len) {
    size_t need, i;
    if (!state || !out || !len) return EXTERIA_E_ARG;
    *len = 0;
    if (state->count > EXTERIA_NOTIFY_SEEN_MAX) return EXTERIA_E_ARG;
    need = 8 + (size_t)state->count * STATE_ENTRY_BYTES;
    if (cap < need) return EXTERIA_E_LIMIT;
    memcpy(out, "EXNS", 4);
    out[4] = STATE_VERSION;
    out[5] = state->baselined ? 1 : 0;
    out[6] = (uint8_t)(state->count & 0xffu);
    out[7] = (uint8_t)(state->count >> 8);
    for (i = 0; i < state->count; ++i) {
        uint8_t *at = out + 8 + i * STATE_ENTRY_BYTES;
        put_u32(at, (uint32_t)state->seen[i].peer_kind);
        put_u64(at + 4, (uint64_t)state->seen[i].peer_id);
        put_u32(at + 12, (uint32_t)state->seen[i].top_message);
    }
    *len = need;
    return EXTERIA_OK;
}

exteria_status exteria_notify_state_unpack(const uint8_t *data, size_t len, exteria_notify_state *out) {
    size_t count, i;
    if (!out) return EXTERIA_E_ARG;
    exteria_notify_state_init(out);
    if (!data || len < 8 || memcmp(data, "EXNS", 4) || data[4] != STATE_VERSION || data[5] > 1) return EXTERIA_E_MALFORMED;
    count = (size_t)data[6] | (size_t)data[7] << 8;
    if (count > EXTERIA_NOTIFY_SEEN_MAX || len != 8 + count * STATE_ENTRY_BYTES) return EXTERIA_E_MALFORMED;
    for (i = 0; i < count; ++i) {
        const uint8_t *at = data + 8 + i * STATE_ENTRY_BYTES;
        out->seen[i].peer_kind = (int32_t)get_u32(at);
        out->seen[i].peer_id = (int64_t)get_u64(at + 4);
        out->seen[i].top_message = (int32_t)get_u32(at + 12);
    }
    out->count = (uint32_t)count;
    out->baselined = data[5];
    return EXTERIA_OK;
}

exteria_status exteria_notify_line_encode(const exteria_notify_event *event, char *out, size_t cap, size_t *len) {
    char title[EXTERIA_NOTIFY_TITLE_MAX], body[EXTERIA_NOTIFY_BODY_MAX];
    int n;
    if (!event || !out || !len) return EXTERIA_E_ARG;
    *len = 0;
    copy_clean(title, sizeof(title), event->title);
    copy_clean(body, sizeof(body), event->body);
    n = snprintf(out, cap, "N\t%ld\t%lld\t%ld\t%s\t%s\n", (long)event->peer_kind, (long long)event->peer_id, (long)event->message_id, title, body);
    if (n < 0 || (size_t)n >= cap) {
        if (cap) out[0] = 0;
        return EXTERIA_E_LIMIT;
    }
    *len = (size_t)n;
    return EXTERIA_OK;
}

/* the next tab separated field of line, ending at a tab or at the end; returns its length and moves line past the tab */
static size_t field(const char **line, const char *end, const char **start) {
    const char *at = *line;
    size_t length = 0;
    *start = at;
    while (at + length < end && at[length] != '\t') ++length;
    *line = at + length < end ? at + length + 1 : end;
    return length;
}

static int parse_number(const char *text, size_t len, long long *out) {
    size_t i = 0;
    int negative = 0;
    unsigned long long v = 0;
    if (len == 0 || len > 20) return 0;
    if (text[0] == '-') {
        negative = 1;
        i = 1;
        if (len == 1) return 0;
    }
    for (; i < len; ++i) {
        if (text[i] < '0' || text[i] > '9') return 0;
        if (v > (9223372036854775807ull - (unsigned long long)(text[i] - '0')) / 10ull) return 0;
        v = v * 10ull + (unsigned long long)(text[i] - '0');
    }
    *out = negative ? -(long long)v : (long long)v;
    return 1;
}

exteria_status exteria_notify_line_decode(const char *line, size_t len, exteria_notify_event *out) {
    const char *at = line, *end = line + len, *f;
    size_t n;
    long long kind, id, message;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!line || len < 2 || line[0] != 'N' || line[1] != '\t') return EXTERIA_E_MALFORMED;
    at += 2;
    n = field(&at, end, &f);
    if (!parse_number(f, n, &kind) || kind < 1 || kind > 3) return EXTERIA_E_MALFORMED;
    n = field(&at, end, &f);
    if (!parse_number(f, n, &id) || id <= 0) return EXTERIA_E_MALFORMED;
    n = field(&at, end, &f);
    if (!parse_number(f, n, &message) || message <= 0 || message > 2147483647ll) return EXTERIA_E_MALFORMED;
    n = field(&at, end, &f);
    /* the title must end at a tab, or the line has no body field at all */
    if (n == 0 || n >= sizeof(out->title) || f + n >= end) return EXTERIA_E_MALFORMED;
    memcpy(out->title, f, n);
    out->title[n] = 0;
    /* the body is the rest of the line and holds no tab, because the encoder never writes one there */
    n = (size_t)(end - at);
    if (n >= sizeof(out->body) || memchr(at, '\t', n)) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    memcpy(out->body, at, n);
    out->body[n] = 0;
    out->peer_kind = (int32_t)kind;
    out->peer_id = (int64_t)id;
    out->message_id = (int32_t)message;
    return EXTERIA_OK;
}
