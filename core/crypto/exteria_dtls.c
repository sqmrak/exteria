#include "exteria_dtls.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#include <openssl/bio.h>
#include <openssl/bn.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#define IN_QUEUE_LEN 32
#define OUT_QUEUE_LEN 32
#define APP_QUEUE_LEN 8
#define SESSION_MTU 1200
#define SRTP_PROFILE "SRTP_AES128_CM_SHA1_80"
#define SRTP_EXPORT_LABEL "EXTRACTOR-dtls_srtp"
#define EXPORT_LEN (2 * (EXTERIA_DTLS_SRTP_KEY_LEN + EXTERIA_DTLS_SRTP_SALT_LEN))
#define CERT_BACKDATE_SECONDS (24 * 3600)
#define CERT_LIFETIME_SECONDS (30 * 24 * 3600)

typedef struct dgram {
    uint16_t len;
    uint8_t data[EXTERIA_DTLS_MAX_DATAGRAM];
} dgram;

typedef struct queue {
    dgram *items;
    size_t capacity;
    size_t head;
    size_t count;
} queue;

struct exteria_dtls {
    SSL_CTX *ctx;
    SSL *ssl;
    queue in;
    queue out;
    queue app;
    char local_fingerprint[EXTERIA_DTLS_FINGERPRINT_LEN + 1];
    uint8_t peer_fingerprint[32];
    uint8_t has_peer_fingerprint;
    uint8_t is_client;
    uint8_t started;
    uint8_t mismatch;
    exteria_dtls_state state;
    uint8_t keys[EXPORT_LEN];
};

/* the queues hold whole datagrams: the BIOs below take one datagram per read and make one per write, which DTLS needs and a memory BIO
   (a byte stream) cannot give */

static int queue_init(queue *q, size_t capacity) {
    q->items = (dgram *)calloc(capacity, sizeof(dgram));
    q->capacity = capacity;
    q->head = 0;
    q->count = 0;
    return q->items != NULL;
}

static void queue_free(queue *q) {
    free(q->items);
    memset(q, 0, sizeof(*q));
}

static int queue_push(queue *q, const uint8_t *data, size_t len) {
    dgram *slot;
    if (q->count >= q->capacity || len > EXTERIA_DTLS_MAX_DATAGRAM) return 0;
    slot = &q->items[(q->head + q->count) % q->capacity];
    slot->len = (uint16_t)len;
    memcpy(slot->data, data, len);
    ++q->count;
    return 1;
}

static dgram *queue_front(queue *q) {
    return q->count ? &q->items[q->head] : NULL;
}

static void queue_pop(queue *q) {
    if (!q->count) return;
    q->head = (q->head + 1) % q->capacity;
    --q->count;
}

static int dgram_write(BIO *bio, const char *data, int len) {
    queue *q = (queue *)BIO_get_data(bio);
    BIO_clear_retry_flags(bio);
    if (len < 0) return -1;
    /* a datagram that does not fit the queue is lost, which UDP may do to it as well, and DTLS resends what matters */
    queue_push(q, (const uint8_t *)data, (size_t)len);
    return len;
}

static int dgram_read(BIO *bio, char *out, int len) {
    queue *q = (queue *)BIO_get_data(bio);
    dgram *front = queue_front(q);
    int n;
    BIO_clear_retry_flags(bio);
    if (!out || len <= 0) return 0;
    if (!front) {
        BIO_set_retry_read(bio);
        return -1;
    }
    n = front->len < len ? front->len : len;
    memcpy(out, front->data, (size_t)n);
    queue_pop(q);
    return n;
}

static long dgram_ctrl(BIO *bio, int cmd, long num, void *ptr) {
    (void)bio;
    (void)num;
    (void)ptr;
    switch (cmd) {
    case BIO_CTRL_FLUSH:
    case BIO_CTRL_DGRAM_SET_CONNECTED:
        return 1;
    case BIO_CTRL_DGRAM_GET_MTU_OVERHEAD:
        return 0;
    default:
        return 0;
    }
}

static BIO_METHOD *dgram_method;
static pthread_once_t dgram_once = PTHREAD_ONCE_INIT;

static void make_dgram_method(void) {
    BIO_METHOD *m = BIO_meth_new(BIO_get_new_index() | BIO_TYPE_SOURCE_SINK, "exteria dtls datagrams");
    if (!m) return;
    if (!BIO_meth_set_write(m, dgram_write) || !BIO_meth_set_read(m, dgram_read) || !BIO_meth_set_ctrl(m, dgram_ctrl)) {
        BIO_meth_free(m);
        return;
    }
    dgram_method = m;
}

static BIO *make_bio(queue *q) {
    BIO *bio;
    pthread_once(&dgram_once, make_dgram_method);
    if (!dgram_method) return NULL;
    bio = BIO_new(dgram_method);
    if (!bio) return NULL;
    BIO_set_data(bio, q);
    BIO_set_init(bio, 1);
    return bio;
}

static void hex_fingerprint(const uint8_t digest[32], char out[EXTERIA_DTLS_FINGERPRINT_LEN + 1]) {
    static const char hex[] = "0123456789ABCDEF";
    int i;
    for (i = 0; i < 32; ++i) {
        out[i * 3] = hex[digest[i] >> 4];
        out[i * 3 + 1] = hex[digest[i] & 15];
        if (i < 31) out[i * 3 + 2] = ':';
    }
    out[EXTERIA_DTLS_FINGERPRINT_LEN] = '\0';
}

static int certificate_digest(X509 *cert, uint8_t digest[32]) {
    unsigned n = 0;
    return cert && X509_digest(cert, EVP_sha256(), digest, &n) == 1 && n == 32;
}

/* a self signed ECDSA P-256 certificate, the kind webrtc stacks make; its identity is its fingerprint, so the name is of no weight */
static int make_certificate(SSL_CTX *ctx, char fingerprint[EXTERIA_DTLS_FINGERPRINT_LEN + 1]) {
    EVP_PKEY_CTX *kctx = EVP_PKEY_CTX_new_id(EVP_PKEY_EC, NULL);
    EVP_PKEY *key = NULL;
    X509 *cert = X509_new();
    BIGNUM *serial = BN_new();
    uint8_t digest[32];
    X509_NAME *name;
    int ok = 0;
    if (!kctx || !cert || !serial) goto done;
    if (EVP_PKEY_keygen_init(kctx) != 1 || EVP_PKEY_CTX_set_ec_paramgen_curve_nid(kctx, NID_X9_62_prime256v1) != 1 ||
        EVP_PKEY_keygen(kctx, &key) != 1) goto done;
    if (BN_rand(serial, 63, BN_RAND_TOP_ANY, BN_RAND_BOTTOM_ANY) != 1 || BN_is_zero(serial)) goto done;
    if (X509_set_version(cert, 2) != 1 || !BN_to_ASN1_INTEGER(serial, X509_get_serialNumber(cert))) goto done;
    if (!X509_gmtime_adj(X509_getm_notBefore(cert), -CERT_BACKDATE_SECONDS) || !X509_gmtime_adj(X509_getm_notAfter(cert), CERT_LIFETIME_SECONDS)) goto done;
    if (X509_set_pubkey(cert, key) != 1) goto done;
    name = X509_get_subject_name(cert);
    if (X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (const unsigned char *)"exteria", -1, -1, 0) != 1) goto done;
    if (X509_set_issuer_name(cert, name) != 1 || X509_sign(cert, key, EVP_sha256()) <= 0) goto done;
    if (SSL_CTX_use_certificate(ctx, cert) != 1 || SSL_CTX_use_PrivateKey(ctx, key) != 1 || SSL_CTX_check_private_key(ctx) != 1) goto done;
    if (!certificate_digest(cert, digest)) goto done;
    hex_fingerprint(digest, fingerprint);
    ok = 1;
done:
    BN_free(serial);
    X509_free(cert);
    EVP_PKEY_free(key);
    EVP_PKEY_CTX_free(kctx);
    return ok;
}

/* the whole chain check is replaced: the certificate of the peer is trusted exactly when its SHA-256 is the one signaling announced */
static int verify_peer(X509_STORE_CTX *store, void *arg) {
    exteria_dtls *d = (exteria_dtls *)arg;
    uint8_t digest[32];
    uint8_t diff = 0;
    int i;
    X509 *cert = X509_STORE_CTX_get0_cert(store);
    if (!d->has_peer_fingerprint || !certificate_digest(cert, digest)) {
        d->mismatch = 1;
        return 0;
    }
    for (i = 0; i < 32; ++i) diff |= (uint8_t)(digest[i] ^ d->peer_fingerprint[i]);
    if (diff) {
        d->mismatch = 1;
        return 0;
    }
    return 1;
}

exteria_status exteria_dtls_new(exteria_dtls **out) {
    exteria_dtls *d;
    BIO *rbio, *wbio;
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    d = (exteria_dtls *)calloc(1, sizeof(*d));
    if (!d) return EXTERIA_E_NOMEM;
    if (!queue_init(&d->in, IN_QUEUE_LEN) || !queue_init(&d->out, OUT_QUEUE_LEN) || !queue_init(&d->app, APP_QUEUE_LEN)) {
        exteria_dtls_free(d);
        return EXTERIA_E_NOMEM;
    }
    ERR_clear_error();
    d->ctx = SSL_CTX_new(DTLS_method());
    if (!d->ctx || SSL_CTX_set_min_proto_version(d->ctx, DTLS1_2_VERSION) != 1 || SSL_CTX_set_max_proto_version(d->ctx, DTLS1_2_VERSION) != 1 ||
        SSL_CTX_set_tlsext_use_srtp(d->ctx, SRTP_PROFILE) != 0 ||
        SSL_CTX_set_cipher_list(d->ctx, "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305") != 1 ||
        !make_certificate(d->ctx, d->local_fingerprint)) {
        exteria_dtls_free(d);
        return EXTERIA_E_CRYPTO;
    }
    SSL_CTX_set_verify(d->ctx, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, NULL);
    SSL_CTX_set_cert_verify_callback(d->ctx, verify_peer, d);
    /* the session never asks the network for its MTU: it is a fixed 1200, under every path a call takes */
    SSL_CTX_set_options(d->ctx, SSL_OP_NO_QUERY_MTU);
    d->ssl = SSL_new(d->ctx);
    rbio = make_bio(&d->in);
    wbio = make_bio(&d->out);
    if (!d->ssl || !rbio || !wbio) {
        BIO_free(rbio);
        BIO_free(wbio);
        exteria_dtls_free(d);
        return EXTERIA_E_CRYPTO;
    }
    SSL_set_bio(d->ssl, rbio, wbio);
    SSL_set_mtu(d->ssl, SESSION_MTU);
    d->state = EXTERIA_DTLS_IDLE;
    *out = d;
    return EXTERIA_OK;
}

void exteria_dtls_free(exteria_dtls *d) {
    if (!d) return;
    SSL_free(d->ssl);
    SSL_CTX_free(d->ctx);
    queue_free(&d->in);
    queue_free(&d->out);
    queue_free(&d->app);
    OPENSSL_cleanse(d->keys, sizeof(d->keys));
    free(d);
}

const char *exteria_dtls_local_fingerprint(const exteria_dtls *d) {
    return d ? d->local_fingerprint : NULL;
}

static int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

exteria_status exteria_dtls_set_peer_fingerprint(exteria_dtls *d, const char *hash, const char *fingerprint) {
    uint8_t parsed[32];
    size_t i;
    static const char want[] = "sha-256";
    if (!d || !hash || !fingerprint) return EXTERIA_E_ARG;
    for (i = 0; i < sizeof(want); ++i) {
        char c = hash[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
        if (c != want[i]) return EXTERIA_E_UNSUPPORTED;
        if (!want[i]) break;
    }
    if (strlen(fingerprint) != EXTERIA_DTLS_FINGERPRINT_LEN) return EXTERIA_E_MALFORMED;
    for (i = 0; i < 32; ++i) {
        int hi = hex_value(fingerprint[i * 3]), lo = hex_value(fingerprint[i * 3 + 1]);
        if (hi < 0 || lo < 0 || (i < 31 && fingerprint[i * 3 + 2] != ':')) return EXTERIA_E_MALFORMED;
        parsed[i] = (uint8_t)(hi << 4 | lo);
    }
    if (d->started && d->has_peer_fingerprint && memcmp(parsed, d->peer_fingerprint, 32) != 0) return EXTERIA_E_STATE;
    memcpy(d->peer_fingerprint, parsed, 32);
    d->has_peer_fingerprint = 1;
    return EXTERIA_OK;
}

static exteria_status fail(exteria_dtls *d) {
    d->state = EXTERIA_DTLS_FAILED;
    ERR_clear_error();
    return d->mismatch ? EXTERIA_E_SECURITY : EXTERIA_E_CRYPTO;
}

/* the handshake is done: the profile is the one asked for and the keys come out of the session */
static exteria_status finish_handshake(exteria_dtls *d) {
    const SRTP_PROTECTION_PROFILE *profile = SSL_get_selected_srtp_profile(d->ssl);
    if (!profile || strcmp(profile->name, SRTP_PROFILE) != 0) return fail(d);
    if (SSL_export_keying_material(d->ssl, d->keys, sizeof(d->keys), SRTP_EXPORT_LABEL, sizeof(SRTP_EXPORT_LABEL) - 1, NULL, 0, 0) != 1) return fail(d);
    d->state = EXTERIA_DTLS_CONNECTED;
    return EXTERIA_OK;
}

static exteria_status pump_app_data(exteria_dtls *d) {
    uint8_t buf[EXTERIA_DTLS_MAX_DATAGRAM];
    for (;;) {
        int n = SSL_read(d->ssl, buf, (int)sizeof(buf));
        if (n > 0) {
            /* a message past the queue is dropped; the sender (SCTP) retransmits what was not acknowledged */
            queue_push(&d->app, buf, (size_t)n);
            continue;
        }
        switch (SSL_get_error(d->ssl, n)) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE:
            ERR_clear_error();
            return EXTERIA_OK;
        default:
            return fail(d);
        }
    }
}

static exteria_status drive(exteria_dtls *d) {
    if (!d->started || d->state == EXTERIA_DTLS_FAILED) return d->state == EXTERIA_DTLS_FAILED ? EXTERIA_E_CRYPTO : EXTERIA_OK;
    ERR_clear_error();
    if (d->state == EXTERIA_DTLS_HANDSHAKING) {
        int r = SSL_do_handshake(d->ssl);
        if (r == 1) {
            exteria_status status = finish_handshake(d);
            if (status != EXTERIA_OK) return status;
        } else {
            int err = SSL_get_error(d->ssl, r);
            if (err != SSL_ERROR_WANT_READ && err != SSL_ERROR_WANT_WRITE) return fail(d);
            ERR_clear_error();
            return EXTERIA_OK;
        }
    }
    return pump_app_data(d);
}

exteria_status exteria_dtls_start(exteria_dtls *d, int is_client) {
    if (!d) return EXTERIA_E_ARG;
    if (d->started) return EXTERIA_E_STATE;
    d->started = 1;
    d->is_client = is_client ? 1 : 0;
    d->state = EXTERIA_DTLS_HANDSHAKING;
    if (d->is_client) SSL_set_connect_state(d->ssl);
    else SSL_set_accept_state(d->ssl);
    return drive(d);
}

exteria_status exteria_dtls_input(exteria_dtls *d, const uint8_t *datagram, size_t len) {
    if (!d || (!datagram && len)) return EXTERIA_E_ARG;
    if (len > EXTERIA_DTLS_MAX_DATAGRAM) return EXTERIA_E_LIMIT;
    if (d->state == EXTERIA_DTLS_FAILED) return EXTERIA_E_CRYPTO;
    if (len == 0) return EXTERIA_OK;
    if (!queue_push(&d->in, datagram, len)) return EXTERIA_E_LIMIT;
    return drive(d);
}

exteria_status exteria_dtls_poll(exteria_dtls *d, uint8_t *out, size_t capacity, size_t *len) {
    dgram *front;
    if (len) *len = 0;
    if (!d || !out || !len) return EXTERIA_E_ARG;
    front = queue_front(&d->out);
    if (!front) return EXTERIA_E_RETRY;
    if (capacity < front->len) return EXTERIA_E_LIMIT;
    memcpy(out, front->data, front->len);
    *len = front->len;
    queue_pop(&d->out);
    return EXTERIA_OK;
}

exteria_status exteria_dtls_timeout(exteria_dtls *d, uint32_t *ms) {
    struct timeval tv;
    if (ms) *ms = 0;
    if (!d || !ms) return EXTERIA_E_ARG;
    if (!d->started || d->state != EXTERIA_DTLS_HANDSHAKING) return EXTERIA_E_STATE;
    if (DTLSv1_get_timeout(d->ssl, &tv) != 1) return EXTERIA_E_STATE;
    *ms = (uint32_t)(tv.tv_sec * 1000 + tv.tv_usec / 1000);
    return EXTERIA_OK;
}

exteria_status exteria_dtls_on_timeout(exteria_dtls *d) {
    if (!d) return EXTERIA_E_ARG;
    if (!d->started || d->state != EXTERIA_DTLS_HANDSHAKING) return EXTERIA_OK;
    ERR_clear_error();
    if (DTLSv1_handle_timeout(d->ssl) < 0) return fail(d);
    return EXTERIA_OK;
}

exteria_dtls_state exteria_dtls_get_state(const exteria_dtls *d) {
    return d ? d->state : EXTERIA_DTLS_FAILED;
}

exteria_status exteria_dtls_srtp_keys(exteria_dtls *d, uint8_t send_key[EXTERIA_DTLS_SRTP_KEY_LEN], uint8_t send_salt[EXTERIA_DTLS_SRTP_SALT_LEN],
                                      uint8_t recv_key[EXTERIA_DTLS_SRTP_KEY_LEN], uint8_t recv_salt[EXTERIA_DTLS_SRTP_SALT_LEN]) {
    const uint8_t *client_key, *server_key, *client_salt, *server_salt;
    if (!d || !send_key || !send_salt || !recv_key || !recv_salt) return EXTERIA_E_ARG;
    if (d->state != EXTERIA_DTLS_CONNECTED) return EXTERIA_E_STATE;
    /* RFC 5764 section 4.2: client key, server key, client salt, server salt, one after the other */
    client_key = d->keys;
    server_key = d->keys + EXTERIA_DTLS_SRTP_KEY_LEN;
    client_salt = d->keys + 2 * EXTERIA_DTLS_SRTP_KEY_LEN;
    server_salt = client_salt + EXTERIA_DTLS_SRTP_SALT_LEN;
    memcpy(send_key, d->is_client ? client_key : server_key, EXTERIA_DTLS_SRTP_KEY_LEN);
    memcpy(send_salt, d->is_client ? client_salt : server_salt, EXTERIA_DTLS_SRTP_SALT_LEN);
    memcpy(recv_key, d->is_client ? server_key : client_key, EXTERIA_DTLS_SRTP_KEY_LEN);
    memcpy(recv_salt, d->is_client ? server_salt : client_salt, EXTERIA_DTLS_SRTP_SALT_LEN);
    return EXTERIA_OK;
}

exteria_status exteria_dtls_write(exteria_dtls *d, const uint8_t *data, size_t len) {
    int n;
    if (!d || !data) return EXTERIA_E_ARG;
    if (len == 0 || len > EXTERIA_DTLS_MAX_APP_DATA) return EXTERIA_E_LIMIT;
    if (d->state != EXTERIA_DTLS_CONNECTED) return EXTERIA_E_STATE;
    ERR_clear_error();
    n = SSL_write(d->ssl, data, (int)len);
    if (n != (int)len) return fail(d);
    return EXTERIA_OK;
}

exteria_status exteria_dtls_read(exteria_dtls *d, uint8_t *out, size_t capacity, size_t *len) {
    dgram *front;
    if (len) *len = 0;
    if (!d || !out || !len) return EXTERIA_E_ARG;
    front = queue_front(&d->app);
    if (!front) return EXTERIA_E_RETRY;
    if (capacity < front->len) {
        queue_pop(&d->app);
        return EXTERIA_E_LIMIT;
    }
    memcpy(out, front->data, front->len);
    *len = front->len;
    queue_pop(&d->app);
    return EXTERIA_OK;
}
