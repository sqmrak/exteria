#ifndef EXTERIA_ZALGO_H
#define EXTERIA_ZALGO_H

#include <stddef.h>

/* at most this many combining marks stay on one character; real scripts stack two (a Vietnamese letter with a hat and a tone) */
#define EXTERIA_ZALGO_MARKS_MAX 2

/* copies UTF-8 text into out (capacity cap, which must be at least strlen(in) + 1) and drops the combining marks
   that pile more than EXTERIA_ZALGO_MARKS_MAX on a single character */
size_t exteria_zalgo_filter(const char *in, char *out, size_t cap);

#endif
