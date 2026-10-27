#ifndef EXTERIA_HTTPS_H
#define EXTERIA_HTTPS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"
#include "exteria_mt_socket.h"

/* one HTTPS POST for the account call of WARP, over TLS 1.2 or newer with the chain and the host name checked */

#define EXTERIA_HTTPS_MAX_RESPONSE (256u * 1024u)
/* the most a caller may ask for with max_response: a page of an article with its pictures, and no more */
#define EXTERIA_HTTPS_MAX_RESPONSE_LIMIT (6u * 1024u * 1024u)

typedef struct exteria_https_request {
    const char *host;                   /* the name asked for in the SNI and required in the certificate */
    const char *connect_ip;             /* a dotted IPv4 address to dial instead of resolving host, or NULL */
    uint16_t port;
    const char *path;                   /* starts with / */
    const char *const *headers;         /* "name: value" lines ending with NULL, or NULL */
    const uint8_t *body;
    size_t body_len;
    const char *roots_pem;              /* the trusted roots, PEM, at least one */
    size_t roots_len;
    int split_hello;                    /* write the first bytes of the TLS hello in small pieces with a short pause */
    int timeout_ms;                     /* the whole call */
    size_t max_response;                /* the most the reply (head and body) may take: zero for EXTERIA_HTTPS_MAX_RESPONSE, else up to EXTERIA_HTTPS_MAX_RESPONSE_LIMIT */
    int (*is_cancelled)(void *ctx);
    void *cancel_ctx;
    exteria_status (*connect_socket)(exteria_mt_socket *socket, const char *host, uint16_t port, int timeout_ms);
} exteria_https_request;

typedef struct exteria_https_response {
    int status;
    uint8_t *body;                      /* owned, free with exteria_https_response_free */
    size_t body_len;
    char headers[16385];
} exteria_https_response;

/* the answer of a streamed GET, read before any body byte is passed on */
#define EXTERIA_HTTPS_LOCATION_MAX 2048u
typedef struct exteria_https_head {
    int status;
    uint64_t content_length;                    /* of a 200, else zero */
    char location[EXTERIA_HTTPS_LOCATION_MAX];  /* of a redirect, else empty */
} exteria_https_head;

/* receives the body in pieces in order; any status but EXTERIA_OK stops the transfer and is returned as it is */
typedef exteria_status (*exteria_https_sink)(void *ctx, const uint8_t *data, size_t len);

/* a GET for a file too large to hold: a 200 with a Content-Length goes to the sink, and max_response (required, here a cap on the body alone
   and not limited to EXTERIA_HTTPS_MAX_RESPONSE_LIMIT) refuses a longer one before a byte is read. Every other status returns with the head
   filled and no body read, so the caller can follow a redirect. A chunked or unframed 200 is EXTERIA_E_UNSUPPORTED. timeout_ms covers the
   whole transfer */
exteria_status exteria_https_get_stream(const exteria_https_request *request, exteria_https_head *head, exteria_https_sink sink, void *sink_ctx);

/* EXTERIA_E_ARG for a request that is not well formed (a header with a line break, no roots, no host),
   EXTERIA_E_SECURITY when the certificate chain */
exteria_status exteria_https_post(const exteria_https_request *request, exteria_https_response *response);
/* the same verified transport for bounded raster tiles; no redirects are followed */
exteria_status exteria_https_get(const exteria_https_request *request, exteria_https_response *response);
void exteria_https_response_free(exteria_https_response *response);

#endif
