#ifndef EXTERIA_KEYWORDS_H
#define EXTERIA_KEYWORDS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_tl.h"

/* the words that find an emoji, as the server keeps them for a language (messages.getEmojiKeywords): each keyword lists the emoji it names. the index is kept in memory in
   one block for each keyword, sorted by keyword, and is written to a file as it is so the next launch starts from it and asks the server only for what changed */
#define EXTERIA_KEYWORD_MAX 64            /* bytes of a keyword */
#define EXTERIA_KEYWORD_EMOJI_MAX 32      /* bytes of one emoji: the longest sequences of joiners stay under it */
#define EXTERIA_KEYWORD_EMOJI_PER 48      /* emoji a keyword lists */
#define EXTERIA_KEYWORDS_MAX 120000       /* keywords of one language */
#define EXTERIA_KEYWORDS_FILE_MAX (16u * 1024u * 1024u)
#define EXTERIA_KEYWORD_RESULTS_MAX 200

typedef struct exteria_keyword_index exteria_keyword_index;

exteria_keyword_index *exteria_keyword_index_new(void);
void exteria_keyword_index_free(exteria_keyword_index *index);
/* the version of the server's list this index holds; 0 for an empty one */
int32_t exteria_keyword_index_version(const exteria_keyword_index *index);
size_t exteria_keyword_index_count(const exteria_keyword_index *index);

/* the full list when from_version is 0, the changes since from_version otherwise; lang is a language code of the server, ASCII, up to 15 bytes */
exteria_status exteria_keywords_request(exteria_arena *arena, const char *lang, int32_t from_version, exteria_tl_value **out);
/* takes an emojiKeywordsDifference of the language into the index. a difference that starts at 0 replaces everything; any other must start at the version the index holds, or
   EXTERIA_E_STATE is answered and the caller asks for the full list. EXTERIA_E_MALFORMED for an answer that is not one of that language, EXTERIA_E_LIMIT for one over the caps; the index
   is left as it was when the answer is refused */
exteria_status exteria_keywords_apply(exteria_keyword_index *index, const char *lang, const exteria_tl_value *answer);

/* the emoji for a typed query, best first: keywords equal to it, then those that start with it, then those with a word that starts with it. the case of Latin, Latin-1 and Cyrillic
   letters is ignored. out holds cap emoji of EXTERIA_KEYWORD_EMOJI_MAX bytes each, NUL terminated; the number of them is the answer, 0 for an empty query */
size_t exteria_keywords_search(const exteria_keyword_index *index, const char *query, char (*out)[EXTERIA_KEYWORD_EMOJI_MAX], size_t cap);

/* the file form: a header with the version and the count, then each keyword block. encode answers a malloc'ed buffer the caller frees; decode makes a new index and refuses a
   file that is cut short, out of order or over the caps */
exteria_status exteria_keyword_index_encode(const exteria_keyword_index *index, uint8_t **out, size_t *length);
exteria_status exteria_keyword_index_decode(const uint8_t *data, size_t length, exteria_keyword_index **out);

#endif
