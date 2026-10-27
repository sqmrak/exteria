#ifndef EXTERIA_HTTP_H
#define EXTERIA_HTTP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the one HTTP/1.x response a registration call gets back, read strictly */

#define EXTERIA_HTTP_MAX_HEADERS 16384u
#define EXTERIA_HTTP_LOCATION_MAX 2048u

/* the status line and the headers a caller acts on, before any body byte is read */
typedef struct exteria_http_head {
    int status;                             /* 200 to 599 */
    int chunked;
    int has_length;
    size_t content_length;
    size_t body_start;                      /* offset of the first body byte in the data */
    char location[EXTERIA_HTTP_LOCATION_MAX];   /* the Location value, or empty */
} exteria_http_head;

typedef struct exteria_http_response {
    int status;             /* 100 to 599 */
    size_t body_len;
} exteria_http_response;

/* EXTERIA_E_TRUNCATED until the blank line that ends the headers has arrived */
exteria_status exteria_http_parse_head(const uint8_t *data, size_t len, int eof, exteria_http_head *out);

/* data is everything received so far; eof says the connection is closed */
exteria_status exteria_http_parse_response(const uint8_t *data, size_t len, int eof, exteria_http_response *out, uint8_t *body, size_t cap);

#endif
