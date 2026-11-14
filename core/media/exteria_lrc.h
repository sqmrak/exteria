#ifndef EXTERIA_LRC_H
#define EXTERIA_LRC_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* synchronized lyrics in the LRC form that LRCLIB serves: lines that start with one or more [mm:ss.xx] stamps and then the text. tags that name the song ([ar:], [ti:])
   and the word stamps of the enhanced form (<mm:ss.xx>) are dropped, a line with no text is dropped, and the lines come out in the order of their stamps */

#define EXTERIA_LRC_INPUT_MAX (256u * 1024u)
#define EXTERIA_LRC_LINES_MAX 2000u
#define EXTERIA_LRC_TEXT_MAX 512u

typedef struct exteria_lrc_line {
    uint32_t start_ms;
    char *text;     /* UTF-8, owned by the exteria_lrc */
} exteria_lrc_line;

typedef struct exteria_lrc {
    exteria_lrc_line *lines;
    size_t count;
} exteria_lrc;

/* EXTERIA_E_MALFORMED when no line carries a stamp (the text is then plain, not synchronized), EXTERIA_E_LIMIT for input over EXTERIA_LRC_INPUT_MAX; more than
   EXTERIA_LRC_LINES_MAX lines keep the first ones. out is empty after a failure */
exteria_status exteria_lrc_parse(const char *text, size_t len, exteria_lrc *out);
void exteria_lrc_free(exteria_lrc *lrc);

/* the line that is being sung at ms: the last one that has started, -1 before the first */
long exteria_lrc_active(const exteria_lrc *lrc, uint32_t ms);

/* a title or an artist as a lyrics search wants it: the parts in [] and () and a trailing "feat." / "ft." / "featuring" credit are cut off; when nothing is left
   the trimmed original stays. EXTERIA_E_LIMIT when out is too small */
exteria_status exteria_lrc_search_text(const char *in, char *out, size_t cap);

#endif
