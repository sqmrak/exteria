#include "exteria_mention.h"

#include <string.h>

static int name_byte(unsigned char c) {
    return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c >= 0x80u;
}

static int opens_mention(unsigned char before) {
    return before == ' ' || before == '\n' || before == '\t' || before == '(' || before == '[' || before == '{' || before == '"' || before == '\'' ||
           before == ',' || before == '.' || before == ';' || before == ':' || before == '!' || before == '?' || before == '-';
}

int exteria_mention_scan(const char *text, size_t caret, exteria_mention_token *out) {
    size_t len, at;
    if (out) memset(out, 0, sizeof(*out));
    if (!text || !out) return 0;
    len = strlen(text);
    if (caret > len || caret == 0) return 0;
    /* back over the name characters to the '@' they belong to */
    at = caret;
    while (at > 0 && name_byte((unsigned char)text[at - 1])) --at;
    if (at == 0 || text[at - 1] != '@') return 0;
    --at;
    if (at > 0 && !opens_mention((unsigned char)text[at - 1])) return 0;
    if (caret - at - 1 >= EXTERIA_MENTION_QUERY_MAX) return 0;
    out->start = at;
    out->end = caret;
    memcpy(out->query, text + at + 1, caret - at - 1);
    out->query[caret - at - 1] = 0;
    return 1;
}
