#include "exteria_links.h"

#include <ctype.h>
#include <string.h>

static int word_char(char c, int dash) {
    return isalnum((unsigned char)c) || c == '_' || (dash && c == '-');
}

static int word_valid(const char *s, size_t len, size_t min, size_t max, int dash) {
    size_t i;
    if (len < min || len > max) return 0;
    for (i = 0; i < len; ++i) if (!word_char(s[i], dash)) return 0;
    return 1;
}

static int equals_nocase(const char *s, size_t len, const char *name) {
    size_t i;
    if (strlen(name) != len) return 0;
    for (i = 0; i < len; ++i) if (tolower((unsigned char)s[i]) != tolower((unsigned char)name[i])) return 0;
    return 1;
}

static int starts_with_nocase(const char *s, const char *prefix) {
    while (*prefix) {
        if (tolower((unsigned char)*s) != tolower((unsigned char)*prefix)) return 0;
        ++s;
        ++prefix;
    }
    return 1;
}

static int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* a field of the query or a path segment, percent decoded into out; false when it does not fit or an escape is broken */
static int decode_value(const char *s, size_t len, char *out, size_t cap) {
    size_t i = 0, n = 0;
    while (i < len) {
        char c = s[i];
        if (c == '%') {
            int hi, lo;
            if (i + 2 >= len) return 0;
            hi = hex_value(s[i + 1]);
            lo = hex_value(s[i + 2]);
            if (hi < 0 || lo < 0) return 0;
            c = (char)((hi << 4) | lo);
            i += 3;
        } else {
            ++i;
        }
        if (n + 1 >= cap) return 0;
        out[n++] = c;
    }
    out[n] = 0;
    return 1;
}

typedef struct span {
    const char *start;
    size_t len;
} span;

/* the raw value of a key in a query string; the first of two equal keys wins */
static int query_get(span q, const char *key, span *value) {
    size_t key_len = strlen(key), i = 0;
    while (i < q.len) {
        size_t end = i, field;
        while (end < q.len && q.start[end] != '&') ++end;
        field = end - i;
        if (field >= key_len && !memcmp(q.start + i, key, key_len) && (field == key_len || q.start[i + key_len] == '=')) {
            value->start = q.start + i + key_len + (field > key_len ? 1 : 0);
            value->len = field - key_len - (field > key_len ? 1 : 0);
            return 1;
        }
        i = end + 1;
    }
    return 0;
}

/* a start parameter: dropped, not cut, when it is not one the server would take */
static void read_param(span q, const char *key, char *out, size_t cap, uint8_t *present) {
    span value;
    out[0] = 0;
    *present = 0;
    if (!query_get(q, key, &value)) return;
    if (!decode_value(value.start, value.len, out, cap) || (out[0] && !word_valid(out, strlen(out), 1, cap - 1, 1))) {
        out[0] = 0;
        return;
    }
    *present = 1;
}

static int digits_only(const char *s, size_t len, int32_t *value) {
    size_t i;
    int64_t v = 0;
    if (len == 0 || len > 10) return 0;
    for (i = 0; i < len; ++i) {
        if (s[i] < '0' || s[i] > '9') return 0;
        v = v * 10 + (s[i] - '0');
    }
    if (v <= 0 || v > 2147483647) return 0;
    *value = (int32_t)v;
    return 1;
}

static void read_start(span q, exteria_tg_link *out) {
    read_param(q, "start", out->start, sizeof(out->start), &out->has_start);
    read_param(q, "startapp", out->start_app, sizeof(out->start_app), &out->has_start_app);
}

static int copy_word(char *dst, size_t cap, const char *s, size_t len, int dash) {
    if (!word_valid(s, len, 1, cap - 1, dash)) return 0;
    memcpy(dst, s, len);
    dst[len] = 0;
    return 1;
}

static int copy_slug(char *dst, size_t cap, const char *s, size_t len) {
    char decoded[EXTERIA_LINK_SLUG_MAX];
    if (!decode_value(s, len, decoded, sizeof(decoded)) || !word_valid(decoded, strlen(decoded), 1, cap - 1, 1)) return 0;
    strcpy(dst, decoded);
    return 1;
}

/* an invite hash; t.me/+digits is a phone number link and not an invite */
static int copy_invite(char *dst, size_t cap, const char *s, size_t len) {
    size_t i;
    int digits = 1;
    if (!copy_slug(dst, cap, s, len)) return 0;
    for (i = 0; dst[i]; ++i) if (dst[i] < '0' || dst[i] > '9') digits = 0;
    if (digits) dst[0] = 0;
    return !digits;
}

/* the fields of a proxy link, which is dropped (left of kind other) when the server or the port is not one a connection could use, or an MTProto proxy has no
   secret; what the secret says is for exteria_proxy_secret_decode */
static void read_proxy(span q, int socks, exteria_tg_link *out) {
    span value;
    int32_t port = 0;
    size_t i, len;
    if (!query_get(q, "server", &value) || !decode_value(value.start, value.len, out->proxy_server, sizeof(out->proxy_server))) goto drop;
    len = strlen(out->proxy_server);
    if (len == 0 || len > 253) goto drop;
    for (i = 0; i < len; ++i) {
        char c = out->proxy_server[i];
        if (!(isalnum((unsigned char)c) || c == '-' || c == '.')) goto drop;
    }
    if (!query_get(q, "port", &value) || !digits_only(value.start, value.len, &port) || port > 65535) goto drop;
    out->proxy_port = (uint16_t)port;
    if (socks) {
        if (query_get(q, "user", &value) && !decode_value(value.start, value.len, out->proxy_user, sizeof(out->proxy_user))) goto drop;
        if (query_get(q, "pass", &value) && !decode_value(value.start, value.len, out->proxy_password, sizeof(out->proxy_password))) goto drop;
        out->kind = EXTERIA_LINK_SOCKS;
        return;
    }
    if (!query_get(q, "secret", &value) || !decode_value(value.start, value.len, out->proxy_secret, sizeof(out->proxy_secret)) || !out->proxy_secret[0]) goto drop;
    out->kind = EXTERIA_LINK_PROXY;
    return;
drop:
    out->proxy_server[0] = 0;
    out->proxy_port = 0;
    out->proxy_secret[0] = 0;
    out->proxy_user[0] = 0;
    out->proxy_password[0] = 0;
}

/* tg://resolve?domain=name&start=x, tg://invoice?slug=s, tg://proxy?server=&port=&secret= */
static void parse_tg(const char *rest, exteria_tg_link *out) {
    const char *question = strchr(rest, '?');
    size_t command_len = question ? (size_t)(question - rest) : strlen(rest);
    span q;
    span value;
    q.start = question ? question + 1 : rest + command_len;
    q.len = strlen(q.start);
    if (equals_nocase(rest, command_len, "resolve") && query_get(q, "domain", &value)) {
        char name[EXTERIA_LINK_NAME_MAX];
        if (!decode_value(value.start, value.len, name, sizeof(name)) || !word_valid(name, strlen(name), 1, EXTERIA_LINK_NAME_MAX - 1, 0)) return;
        out->kind = EXTERIA_LINK_PEER;
        strcpy(out->username, name);
        read_start(q, out);
        if (query_get(q, "appname", &value)) {
            char app[EXTERIA_LINK_NAME_MAX];
            if (decode_value(value.start, value.len, app, sizeof(app)) && word_valid(app, strlen(app), 1, EXTERIA_LINK_NAME_MAX - 1, 0))
                strcpy(out->app_name, app);
        }
        if (query_get(q, "post", &value)) digits_only(value.start, value.len, &out->message_id);
    } else if (equals_nocase(rest, command_len, "invoice") && query_get(q, "slug", &value)) {
        if (copy_slug(out->slug, sizeof(out->slug), value.start, value.len)) out->kind = EXTERIA_LINK_INVOICE;
    } else if (equals_nocase(rest, command_len, "join") && query_get(q, "invite", &value)) {
        if (copy_invite(out->slug, sizeof(out->slug), value.start, value.len)) out->kind = EXTERIA_LINK_INVITE;
    } else if (equals_nocase(rest, command_len, "proxy")) {
        read_proxy(q, 0, out);
    } else if (equals_nocase(rest, command_len, "socks")) {
        read_proxy(q, 1, out);
    }
}

/* names in the first path segment that are pages of telegram and not a user or a channel */
static const char *const reserved[] = {
    "joinchat", "addstickers", "addemoji", "addtheme", "setlanguage", "share", "msg", "proxy", "socks", "bg", "login", "c", "s", "iv",
    "confirmphone", "giftcode", "m", "boost", "addlist", "contact", "folder", "premium", "k", "a", "web", "webk", "webz", "invoice"
};

static int is_reserved(const char *s, size_t len) {
    size_t i;
    for (i = 0; i < sizeof(reserved) / sizeof(reserved[0]); ++i) if (equals_nocase(s, len, reserved[i])) return 1;
    return 0;
}

static int host_is_telegram(const char *host, size_t len) {
    if (len > 4 && starts_with_nocase(host, "www.")) {
        host += 4;
        len -= 4;
    }
    return equals_nocase(host, len, "t.me") || equals_nocase(host, len, "telegram.me") || equals_nocase(host, len, "telegram.dog");
}

/* https://t.me/name, /name/app, /name/123, /$slug, /invoice/slug, /+hash, /joinchat/hash */
static void parse_web(const char *path, size_t path_len, span q, exteria_tg_link *out) {
    const char *first = path;
    size_t first_len = 0, second_len = 0;
    const char *second;
    while (first_len < path_len && first[first_len] != '/') ++first_len;
    second = first + first_len;
    if (first_len < path_len) ++second;
    while (second_len < (size_t)(path + path_len - second) && second[second_len] != '/') ++second_len;
    if (first_len == 0) return;
    if (first[0] == '$') {
        if (copy_slug(out->slug, sizeof(out->slug), first + 1, first_len - 1)) out->kind = EXTERIA_LINK_INVOICE;
        return;
    }
    if (equals_nocase(first, first_len, "proxy") || equals_nocase(first, first_len, "socks")) {
        read_proxy(q, equals_nocase(first, first_len, "socks"), out);
        return;
    }
    if (equals_nocase(first, first_len, "invoice")) {
        if (second_len && copy_slug(out->slug, sizeof(out->slug), second, second_len)) out->kind = EXTERIA_LINK_INVOICE;
        return;
    }
    if (first[0] == '+') {
        if (copy_invite(out->slug, sizeof(out->slug), first + 1, first_len - 1)) out->kind = EXTERIA_LINK_INVITE;
        return;
    }
    if (equals_nocase(first, first_len, "joinchat")) {
        if (second_len && copy_invite(out->slug, sizeof(out->slug), second, second_len)) out->kind = EXTERIA_LINK_INVITE;
        return;
    }
    if (is_reserved(first, first_len) || !copy_word(out->username, sizeof(out->username), first, first_len, 0)) {
        out->username[0] = 0;
        return;
    }
    out->kind = EXTERIA_LINK_PEER;
    read_start(q, out);
    if (second_len && !digits_only(second, second_len, &out->message_id)) copy_word(out->app_name, sizeof(out->app_name), second, second_len, 0);
}

exteria_status exteria_tg_link_parse(const char *url, exteria_tg_link *out) {
    size_t len;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!url) return EXTERIA_E_ARG;
    len = strlen(url);
    if (len > EXTERIA_LINK_URL_MAX) return EXTERIA_E_LIMIT;
    if (starts_with_nocase(url, "tg://")) {
        parse_tg(url + 5, out);
    } else if (starts_with_nocase(url, "tg:") && url[3] != '/') {
        parse_tg(url + 3, out);
    } else {
        const char *host, *slash, *question, *hash;
        size_t host_len, path_len;
        span q;
        if (starts_with_nocase(url, "https://")) host = url + 8;
        else if (starts_with_nocase(url, "http://")) host = url + 7;
        else return EXTERIA_OK;
        slash = strchr(host, '/');
        if (!slash) return EXTERIA_OK;
        host_len = (size_t)(slash - host);
        if (!host_is_telegram(host, host_len)) return EXTERIA_OK;
        question = strchr(slash, '?');
        hash = strchr(slash, '#');
        path_len = (size_t)((question ? question : hash ? hash : url + len) - (slash + 1));
        if (question && hash && hash < question) path_len = (size_t)(hash - (slash + 1));
        q.start = question && (!hash || question < hash) ? question + 1 : "";
        q.len = question && (!hash || question < hash) ? (size_t)((hash && hash > question ? hash : url + len) - (question + 1)) : 0;
        parse_web(slash + 1, path_len, q, out);
    }
    return EXTERIA_OK;
}

exteria_status exteria_mention_name(const char *text, char *out, size_t cap) {
    size_t len;
    if (out && cap) out[0] = 0;
    if (!text || !out || cap == 0) return EXTERIA_E_ARG;
    if (text[0] == '@') ++text;
    len = strlen(text);
    if (!word_valid(text, len, 1, EXTERIA_LINK_NAME_MAX - 1, 0) || len >= cap) return EXTERIA_E_MALFORMED;
    memcpy(out, text, len + 1);
    return EXTERIA_OK;
}

exteria_status exteria_bot_command_split(const char *text, char *command, size_t command_cap, char *bot, size_t bot_cap) {
    const char *at;
    size_t name_len, bot_len = 0;
    if (command && command_cap) command[0] = 0;
    if (bot && bot_cap) bot[0] = 0;
    if (!text || !command || !bot || command_cap < 34 || bot_cap < EXTERIA_LINK_NAME_MAX) return EXTERIA_E_ARG;
    if (text[0] != '/') return EXTERIA_E_MALFORMED;
    at = strchr(text, '@');
    name_len = (at ? (size_t)(at - text) : strlen(text)) - 1;
    if (!word_valid(text + 1, name_len, 1, 32, 0)) return EXTERIA_E_MALFORMED;
    if (at) {
        bot_len = strlen(at + 1);
        if (!word_valid(at + 1, bot_len, 1, EXTERIA_LINK_NAME_MAX - 1, 0)) return EXTERIA_E_MALFORMED;
    }
    memcpy(command, text, name_len + 1);
    command[name_len + 1] = 0;
    if (bot_len) memcpy(bot, at + 1, bot_len + 1);
    return EXTERIA_OK;
}
