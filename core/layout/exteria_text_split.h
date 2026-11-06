#ifndef EXTERIA_TEXT_SPLIT_H
#define EXTERIA_TEXT_SPLIT_H

#include <stddef.h>
#include <stdint.h>

/* the longest message the server takes: 4096 UTF-16 units, 8192 for Premium */
#define EXTERIA_MESSAGE_LIMIT 4096u
#define EXTERIA_MESSAGE_LIMIT_PREMIUM 8192u

/* one piece of a long text, as units of the text it was cut from; the ends are trimmed of white space */
typedef struct {
    size_t begin;
    size_t end;
} exteria_text_part;

/* cuts the UTF-16 text into pieces of at most limit units the way the Android client does: when more than limit units are left, the cut is looked for in the 300 units
   before the limit, and the first of these that exists wins: a blank line, a line break, a space after a full stop, any white space. with none of them the cut is at
   the limit, moved back by one unit when it would split a surrogate pair. the break character itself belongs to no piece. pieces that are only white space are
   skipped. parts gets at most capacity pieces; *count is how many were written, and the result is the number of pieces the text needs (it may exceed capacity,
   so a caller sizes the array with ceil(len / (limit - 300)) + 1 or asks twice). returns 0 for no text or a limit below 2 */
size_t exteria_text_split(const uint16_t *units, size_t len, size_t limit, exteria_text_part *parts, size_t capacity, size_t *count);

#endif
