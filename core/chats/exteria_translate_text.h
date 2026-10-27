#ifndef EXTERIA_TRANSLATE_TEXT_H
#define EXTERIA_TRANSLATE_TEXT_H

#include <stddef.h>

#include "exteria_status.h"

/* plain text repairs for what a translator hands back */

/* the Google API turns each single line break of a Chinese translation into two; EXTERIA_E_LIMIT when out cannot
   hold the result */
exteria_status exteria_tr_restore_newlines(const char *original, const char *translated, char *out, size_t cap);

#endif
