#ifndef EXTERIA_TRANSLATE_HTML_H
#define EXTERIA_TRANSLATE_HTML_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the styled runs of a message go to a web translator as light markup and come back from it it */

#define EXTERIA_TH_TEXT_MAX 8192u
#define EXTERIA_TH_SPAN_MAX 512u

typedef enum {
    EXTERIA_TH_BOLD = 1,
    EXTERIA_TH_ITALIC,
    EXTERIA_TH_UNDERLINE,
    EXTERIA_TH_STRIKE,
    EXTERIA_TH_CODE,
    EXTERIA_TH_LINK
} exteria_th_kind;

typedef struct exteria_th_span {
    int32_t kind;
    uint32_t offset;
    uint32_t length;
} exteria_th_span;

/* the text with its spans as markup; a span with no length, one that leaves the text or one of a kind not listed
   above is left out */
exteria_status exteria_th_encode(const uint16_t *text, size_t len, const exteria_th_span *spans, size_t count, uint16_t *out, size_t cap, size_t *out_len);

/* the markup a translator returned as plain text and spans, ordered by offset and then by length, longest first */
exteria_status exteria_th_decode(const uint16_t *markup, size_t len, uint16_t *out, size_t out_cap, size_t *out_len, exteria_th_span *spans, size_t span_cap,
                                 size_t *span_count);

#endif
