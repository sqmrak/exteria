#ifndef EXTERIA_MENTION_H
#define EXTERIA_MENTION_H

#include <stddef.h>

/* the longest query kept; a name that long is already unique */
#define EXTERIA_MENTION_QUERY_MAX 33

typedef struct exteria_mention_token {
    size_t start;                           /* byte offset of the '@' */
    size_t end;                             /* byte offset after the last character of the query, which is where the caret stands */
    char query[EXTERIA_MENTION_QUERY_MAX];  /* the characters after the '@', possibly none */
} exteria_mention_token;

/* finds the "@query" the caret stands at the end of, in UTF-8 text with the caret at byte offset caret (it must be
   on a character boundary) */
int exteria_mention_scan(const char *text, size_t caret, exteria_mention_token *out);

#endif
