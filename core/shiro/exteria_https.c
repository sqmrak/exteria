#include "exteria_https.h"

#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509_vfy.h>
#include <openssl/x509v3.h>

#include "exteria_bytes.h"
#include "exteria_clock.h"
#include "exteria_http.h"
#include "exteria_mt_socket.h"

#define SPLIT_PIECE 6u
#define SPLIT_PIECES 23u
#define SPLIT_GAP_MS 12
#define REQUEST_MAX 16384u
#define READ_STEP 4096u

typedef struct io {
    exteria_mt_socket socket;
    SSL *ssl;
    BIO *rbio, *wbio;
    uint64_t deadline;
    int eof;
    int split;
    const exteria_https_request *request;
} io;

static int time_left(const io *c) {
    if (c->request && c->request->is_cancelled && c->request->is_cancelled(c->request->cancel_ctx)) return 0;
    uint64_t now = exteria_system_clock.monotonic_ms(NULL);
    return now >= c->deadline ? 0 : (int)(c->deadline - now > 0x7FFFFFFFu ? 0x7FFFFFFFu : c->deadline - now);
}

static void pause_ms(int ms) {
    (void)poll(NULL, 0, ms);
}

/* every byte OpenSSL has queued for the peer goes out; the very first batch (the hello) may be cut up when asked */
static exteria_status flush(io *c) {
    uint8_t buf[16384];
    for (;;) {
        size_t pending = BIO_ctrl_pending(c->wbio), n, sent = 0;
        int got;
        if (pending == 0) return EXTERIA_OK;
        n = pending < sizeof(buf) ? pending : sizeof(buf);
        got = BIO_read(c->wbio, buf, (int)n);
        if (got <= 0) return EXTERIA_E_IO;
        n = (size_t)got;
        if (c->split && n > SPLIT_PIECE) {
            size_t piece, pieces = 0;
            c->split = 0;
            while (sent < n) {
                piece = sent + SPLIT_PIECE < n && pieces < SPLIT_PIECES ? SPLIT_PIECE : n - sent;
                if (time_left(c) == 0) return EXTERIA_E_TIMEOUT;
                if (exteria_mt_socket_write_all(&c->socket, buf + sent, piece, time_left(c)) != EXTERIA_OK) return EXTERIA_E_IO;
                sent += piece;
                ++pieces;
                if (sent < n) pause_ms(SPLIT_GAP_MS);
            }
        } else {
            exteria_status s;
            c->split = 0;
            if (time_left(c) == 0) return EXTERIA_E_TIMEOUT;
            s = exteria_mt_socket_write_all(&c->socket, buf, n, time_left(c));
            if (s != EXTERIA_OK) return s == EXTERIA_E_TIMEOUT ? s : EXTERIA_E_IO;
        }
    }
}

/* one read from the socket into OpenSSL's input */
static exteria_status fill(io *c) {
    uint8_t buf[READ_STEP];
    size_t got = 0;
    int left = time_left(c);
    exteria_status s;
    if (c->eof) return EXTERIA_E_EOF;
    if (left == 0) return EXTERIA_E_TIMEOUT;
    do {
        s = exteria_mt_socket_read(&c->socket, buf, sizeof(buf), &got, left > 100 ? 100 : left);
        left = time_left(c);
    } while (s == EXTERIA_E_TIMEOUT && left > 0);
    if (s == EXTERIA_E_EOF) {
        c->eof = 1;
        return EXTERIA_E_EOF;
    }
    if (s != EXTERIA_OK) return s == EXTERIA_E_TIMEOUT ? s : EXTERIA_E_IO;
    if (BIO_write(c->rbio, buf, (int)got) != (int)got) return EXTERIA_E_IO;
    return EXTERIA_OK;
}

static int load_roots(SSL_CTX *ctx, const char *pem, size_t len) {
    BIO *bio;
    X509_STORE *store = SSL_CTX_get_cert_store(ctx);
    int added = 0;
    if (!pem || len == 0 || len > 0x7FFFFFFF) return 0;
    bio = BIO_new_mem_buf(pem, (int)len);
    if (!bio) return 0;
    for (;;) {
        X509 *cert = PEM_read_bio_X509(bio, NULL, NULL, NULL);
        if (!cert) break;
        if (X509_STORE_add_cert(store, cert) == 1) ++added;
        X509_free(cert);
    }
    ERR_clear_error();
    BIO_free(bio);
    return added;
}

static int has_line_break(const char *s) {
    return s && (strchr(s, '\r') || strchr(s, '\n'));
}

static exteria_status build_request(const exteria_https_request *r, const char *method, char *out, size_t cap, size_t *len) {
    size_t n = 0, i;
    int w;
    w = snprintf(out, cap, "%s %s HTTP/1.1\r\nHost: %s\r\n", method, r->path, r->host);
    if (w < 0 || (size_t)w >= cap) return EXTERIA_E_ARG;
    n = (size_t)w;
    for (i = 0; r->headers && r->headers[i]; ++i) {
        if (has_line_break(r->headers[i]) || !strchr(r->headers[i], ':')) return EXTERIA_E_ARG;
        w = snprintf(out + n, cap - n, "%s\r\n", r->headers[i]);
        if (w < 0 || (size_t)w >= cap - n) return EXTERIA_E_ARG;
        n += (size_t)w;
    }
    w = snprintf(out + n, cap - n, "Content-Length: %zu\r\nConnection: close\r\n\r\n", r->body_len);
    if (w < 0 || (size_t)w >= cap - n) return EXTERIA_E_ARG;
    n += (size_t)w;
    *len = n;
    return EXTERIA_OK;
}

/* the reply so far, as a response when it is complete; on success the body buffer passes to the response */
static exteria_status take_response(const uint8_t *in, size_t in_len, int eof, uint8_t **body, exteria_https_response *response, size_t limit) {
    exteria_http_response parsed;
    exteria_status status = exteria_http_parse_response(in, in_len, eof, &parsed, *body, limit);
    uint8_t *shrunk;
    if (status != EXTERIA_OK) return status;
    shrunk = (uint8_t *)realloc(*body, parsed.body_len ? parsed.body_len : 1);
    response->body = shrunk ? shrunk : *body;
    *body = NULL;
    response->status = parsed.status;
    response->body_len = parsed.body_len;
    for (size_t i = 0; i + 3 < in_len && i < sizeof(response->headers) - 4; ++i) {
        if (!memcmp(in + i, "\r\n\r\n", 4)) {
            memcpy(response->headers, in, i + 2);
            response->headers[i + 2] = 0;
            break;
        }
    }
    return EXTERIA_OK;
}

static void close_io(io *c) {
    if (c->ssl) SSL_free(c->ssl);   /* frees both BIOs */
    exteria_mt_socket_close(&c->socket);
    c->ssl = NULL;
}

/* validates the request, dials, checks the chain and the name, and writes the request; on success the caller owns the connection and closes it */
static exteria_status open_request(const exteria_https_request *request, const char *method, io *c) {
    SSL_CTX *ctx = NULL;
    char head[REQUEST_MAX];
    size_t head_len = 0;
    exteria_status status;
    int rc;
    if (!request || !request->host || !request->host[0] || !request->path || request->path[0] != '/' || request->port == 0 ||
        request->timeout_ms <= 0 || (request->body_len && !request->body) || request->body_len > REQUEST_MAX || has_line_break(request->host) ||
        has_line_break(request->path) || strchr(request->host, ' ') || strchr(request->path, ' ')) {
        return EXTERIA_E_ARG;
    }
    status = build_request(request, method, head, sizeof(head), &head_len);
    if (status != EXTERIA_OK) return status;
    memset(c, 0, sizeof(*c));
    c->request = request;
    exteria_mt_socket_init(&c->socket);
    c->deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)request->timeout_ms;
    c->split = request->split_hello;
    if (!time_left(c)) return EXTERIA_E_TIMEOUT;

    ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) return EXTERIA_E_CRYPTO;
    if (SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) != 1) {
        SSL_CTX_free(ctx);
        return EXTERIA_E_CRYPTO;
    }
    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
    if (load_roots(ctx, request->roots_pem, request->roots_len) == 0) {
        SSL_CTX_free(ctx);
        return EXTERIA_E_ARG;
    }
    c->ssl = SSL_new(ctx);
    SSL_CTX_free(ctx);
    if (!c->ssl) return EXTERIA_E_CRYPTO;
    c->rbio = BIO_new(BIO_s_mem());
    c->wbio = BIO_new(BIO_s_mem());
    if (!c->rbio || !c->wbio) {
        BIO_free(c->rbio);
        BIO_free(c->wbio);
        SSL_free(c->ssl);
        c->ssl = NULL;
        return EXTERIA_E_NOMEM;
    }
    /* the SSL object owns the BIOs from here on */
    SSL_set_bio(c->ssl, c->rbio, c->wbio);
    SSL_set_connect_state(c->ssl);
    SSL_set_hostflags(c->ssl, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
    if (SSL_set1_host(c->ssl, request->host) != 1 || SSL_set_tlsext_host_name(c->ssl, request->host) != 1) {
        close_io(c);
        return EXTERIA_E_CRYPTO;
    }

    status = (request->connect_socket ? request->connect_socket : exteria_mt_socket_connect)(
        &c->socket, request->connect_ip ? request->connect_ip : request->host, request->port, time_left(c) ? time_left(c) : 1);
    if (status != EXTERIA_OK) {
        close_io(c);
        return status == EXTERIA_E_TIMEOUT ? status : EXTERIA_E_IO;
    }

    for (;;) {
        int err;
        ERR_clear_error();
        rc = SSL_do_handshake(c->ssl);
        status = flush(c);
        if (status != EXTERIA_OK) goto fail;
        if (rc == 1) break;
        err = SSL_get_error(c->ssl, rc);
        if (err == SSL_ERROR_WANT_READ) {
            status = fill(c);
            if (status == EXTERIA_E_EOF) status = EXTERIA_E_IO;
            if (status != EXTERIA_OK) goto fail;
        } else if (err != SSL_ERROR_WANT_WRITE) {
            /* a certificate or a name that does not check out is a security failure and is told apart from a network one */
            long verify = SSL_get_verify_result(c->ssl);
            unsigned long e = ERR_peek_last_error();
            status = (verify != X509_V_OK || ERR_GET_LIB(e) == ERR_LIB_X509 || ERR_GET_REASON(e) == SSL_R_UNSUPPORTED_PROTOCOL ||
                      ERR_GET_REASON(e) == SSL_R_TLSV1_ALERT_PROTOCOL_VERSION || ERR_GET_REASON(e) == SSL_R_WRONG_SSL_VERSION)
                         ? EXTERIA_E_SECURITY
                         : EXTERIA_E_IO;
            goto fail;
        }
    }
    if (SSL_get_verify_result(c->ssl) != X509_V_OK) {
        status = EXTERIA_E_SECURITY;
        goto fail;
    }

    /* the request, header and body in one write */
    {
        size_t total = head_len + request->body_len, sent = 0;
        uint8_t *all = (uint8_t *)malloc(total);
        if (!all) {
            status = EXTERIA_E_NOMEM;
            goto fail;
        }
        memcpy(all, head, head_len);
        if (request->body_len) memcpy(all + head_len, request->body, request->body_len);
        while (sent < total) {
            int w;
            ERR_clear_error();
            w = SSL_write(c->ssl, all + sent, (int)(total - sent));
            if (w > 0) {
                sent += (size_t)w;
                status = flush(c);
                if (status != EXTERIA_OK) {
                    exteria_wipe(all, total);
                    free(all);
                    goto fail;
                }
                continue;
            }
            if (SSL_get_error(c->ssl, w) != SSL_ERROR_WANT_WRITE && SSL_get_error(c->ssl, w) != SSL_ERROR_WANT_READ) {
                exteria_wipe(all, total);
                free(all);
                status = EXTERIA_E_IO;
                goto fail;
            }
            status = flush(c);
            if (status != EXTERIA_OK) {
                exteria_wipe(all, total);
                free(all);
                goto fail;
            }
            if (SSL_get_error(c->ssl, w) == SSL_ERROR_WANT_READ && (status = fill(c)) != EXTERIA_OK) {
                exteria_wipe(all, total);
                free(all);
                goto fail;
            }
        }
        exteria_wipe(all, total);
        free(all);
    }
    return EXTERIA_OK;
fail:
    close_io(c);
    return status;
}

static exteria_status execute(const exteria_https_request *request, exteria_https_response *response, const char *method) {
    io c;
    size_t in_len = 0;
    uint8_t *in = NULL, *body = NULL;
    exteria_status status;
    size_t limit;
    if (response) memset(response, 0, sizeof(*response));
    if (!response || (request && request->max_response > EXTERIA_HTTPS_MAX_RESPONSE_LIMIT)) return EXTERIA_E_ARG;
    status = open_request(request, method, &c);
    if (status != EXTERIA_OK) return status;
    limit = request->max_response ? request->max_response : EXTERIA_HTTPS_MAX_RESPONSE;

    in = (uint8_t *)malloc(limit);
    body = (uint8_t *)malloc(limit);
    if (!in || !body) {
        status = EXTERIA_E_NOMEM;
        goto fail;
    }
    for (;;) {
        int got, err;
        ERR_clear_error();
        got = SSL_read(c.ssl, in + in_len, (int)(limit - in_len));
        if (got > 0) {
            in_len += (size_t)got;
            status = take_response(in, in_len, 0, &body, response, limit);
            if (status == EXTERIA_OK) goto done;
            if (status != EXTERIA_E_TRUNCATED) goto fail;
            if (in_len >= limit) {
                status = EXTERIA_E_LIMIT;
                goto fail;
            }
            continue;
        }
        err = SSL_get_error(c.ssl, got);
        if (err == SSL_ERROR_WANT_READ) {
            status = fill(&c);
            if (status == EXTERIA_OK) continue;
            if (status != EXTERIA_E_EOF) goto fail;
        } else if (err != SSL_ERROR_ZERO_RETURN) {
            status = EXTERIA_E_IO;
            goto fail;
        }
        /* the server closed, which ends a reply that has no length of its own; one that had a length and was cut short stays incomplete */
        status = take_response(in, in_len, 1, &body, response, limit);
        if (status == EXTERIA_E_TRUNCATED) status = EXTERIA_E_IO;
        if (status == EXTERIA_OK) goto done;
        goto fail;
    }
fail:
    if (response->body) {
        free(response->body);
        response->body = NULL;
    }
done:
    if (in) {
        exteria_wipe(in, in_len);
        free(in);
    }
    free(body);
    close_io(&c);
    return status;
}

exteria_status exteria_https_get_stream(const exteria_https_request *request, exteria_https_head *head, exteria_https_sink sink, void *sink_ctx) {
    io c;
    uint8_t buf[READ_STEP];
    size_t in_len = 0;
    uint64_t remaining = 0;
    exteria_http_head parsed;
    exteria_status status;
    if (head) memset(head, 0, sizeof(*head));
    if (!request || !head || !sink || request->body_len || !request->max_response) return EXTERIA_E_ARG;
    status = open_request(request, "GET", &c);
    if (status != EXTERIA_OK) return status;

    /* the head is read into a bounded buffer; whatever body bytes came with it are handed on first */
    {
        uint8_t *in = (uint8_t *)malloc(EXTERIA_HTTP_MAX_HEADERS + READ_STEP);
        if (!in) {
            close_io(&c);
            return EXTERIA_E_NOMEM;
        }
        for (;;) {
            int got, err;
            ERR_clear_error();
            if (in_len >= EXTERIA_HTTP_MAX_HEADERS + READ_STEP) {
                status = EXTERIA_E_LIMIT;
                break;
            }
            got = SSL_read(c.ssl, in + in_len, (int)(EXTERIA_HTTP_MAX_HEADERS + READ_STEP - in_len < READ_STEP ? EXTERIA_HTTP_MAX_HEADERS + READ_STEP - in_len : READ_STEP));
            if (got > 0) {
                in_len += (size_t)got;
                status = exteria_http_parse_head(in, in_len, 0, &parsed);
                if (status != EXTERIA_E_TRUNCATED) break;
                continue;
            }
            err = SSL_get_error(c.ssl, got);
            if (err == SSL_ERROR_WANT_READ) {
                status = fill(&c);
                if (status == EXTERIA_OK) continue;
                if (status == EXTERIA_E_EOF) status = EXTERIA_E_IO;
                break;
            }
            status = EXTERIA_E_IO;
            break;
        }
        if (status == EXTERIA_OK) {
            head->status = parsed.status;
            head->content_length = parsed.has_length ? (uint64_t)parsed.content_length : 0;
            memcpy(head->location, parsed.location, sizeof(head->location));
            /* only a 200 with a length is a body to keep: the size is checked before a byte reaches the sink, and a chunked or unframed
               reply cannot be bounded that way */
            if (parsed.status == 200) {
                if (parsed.chunked || !parsed.has_length) status = EXTERIA_E_UNSUPPORTED;
                else if (parsed.content_length > request->max_response) status = EXTERIA_E_LIMIT;
                else if (in_len - parsed.body_start > parsed.content_length) status = EXTERIA_E_MALFORMED;
                else {
                    remaining = parsed.content_length;
                    if (in_len > parsed.body_start) {
                        status = sink(sink_ctx, in + parsed.body_start, in_len - parsed.body_start);
                        remaining -= in_len - parsed.body_start;
                    }
                }
            }
        }
        exteria_wipe(in, in_len);
        free(in);
    }
    if (status != EXTERIA_OK || head->status != 200) {
        close_io(&c);
        return status;
    }
    while (remaining > 0) {
        size_t want = remaining < sizeof(buf) ? (size_t)remaining : sizeof(buf);
        int got, err;
        ERR_clear_error();
        got = SSL_read(c.ssl, buf, (int)want);
        if (got > 0) {
            status = sink(sink_ctx, buf, (size_t)got);
            if (status != EXTERIA_OK) break;
            remaining -= (uint64_t)got;
            continue;
        }
        err = SSL_get_error(c.ssl, got);
        if (err == SSL_ERROR_WANT_READ) {
            status = fill(&c);
            if (status == EXTERIA_OK) continue;
            if (status == EXTERIA_E_EOF) status = EXTERIA_E_IO;
            break;
        }
        /* a close before the whole length arrived is a cut file, not a short one */
        status = EXTERIA_E_IO;
        break;
    }
    close_io(&c);
    return status;
}

exteria_status exteria_https_post(const exteria_https_request *request, exteria_https_response *response) {
    return execute(request, response, "POST");
}

exteria_status exteria_https_get(const exteria_https_request *request, exteria_https_response *response) {
    if (request && request->body_len) {
        if (response) memset(response, 0, sizeof(*response));
        return EXTERIA_E_ARG;
    }
    return execute(request, response, "GET");
}

void exteria_https_response_free(exteria_https_response *response) {
    if (!response) return;
    if (response->body) {
        exteria_wipe(response->body, response->body_len);
        free(response->body);
    }
    memset(response, 0, sizeof(*response));
}
