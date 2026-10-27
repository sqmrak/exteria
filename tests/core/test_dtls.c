#include "exteria_dtls.h"
#include "exteria_rtp.h"
#include "exteria_tgc_srtp.h"
#include "test_util.h"

#include <time.h>
#include <unistd.h>

/* moves datagrams between two sessions until both are quiet. drop(n) says whether the nth datagram sent (counted over both directions) is lost */
typedef int (*drop_fn)(int n);

static int sent;

static int pump(exteria_dtls *a, exteria_dtls *b, drop_fn drop) {
    uint8_t buf[EXTERIA_DTLS_MAX_DATAGRAM];
    size_t len = 0;
    int moved = 0, progress;
    do {
        exteria_dtls *ends[2];
        int i;
        progress = 0;
        ends[0] = a;
        ends[1] = b;
        for (i = 0; i < 2; ++i) {
            while (exteria_dtls_poll(ends[i], buf, sizeof(buf), &len) == EXTERIA_OK) {
                int lost = drop && drop(sent);
                ++sent;
                progress = 1;
                if (lost) continue;
                ++moved;
                exteria_dtls_input(ends[1 - i], buf, len);
            }
        }
    } while (progress);
    return moved;
}

static void make_pair(exteria_dtls **client, exteria_dtls **server) {
    CHECK_EQ_INT(exteria_dtls_new(client), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_new(server), EXTERIA_OK);
    CHECK(*client && *server);
    CHECK_EQ_INT(strlen(exteria_dtls_local_fingerprint(*client)), EXTERIA_DTLS_FINGERPRINT_LEN);
    CHECK(strcmp(exteria_dtls_local_fingerprint(*client), exteria_dtls_local_fingerprint(*server)) != 0);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(*client, "sha-256", exteria_dtls_local_fingerprint(*server)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(*server, "SHA-256", exteria_dtls_local_fingerprint(*client)), EXTERIA_OK);
}

static void handshake_and_keys(void) {
    exteria_dtls *c, *s;
    uint8_t ck[16], cs[14], crk[16], crs[14], sk[16], ss[14], srk[16], srs[14];
    make_pair(&c, &s);
    CHECK_EQ_INT(exteria_dtls_get_state(c), EXTERIA_DTLS_IDLE);
    CHECK_EQ_INT(exteria_dtls_srtp_keys(c, ck, cs, crk, crs), EXTERIA_E_STATE);
    /* the server is started first and waits; the client's first flight starts the exchange */
    CHECK_EQ_INT(exteria_dtls_start(s, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_start(c, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_start(c, 1), EXTERIA_E_STATE);
    CHECK(pump(c, s, NULL) > 0);
    CHECK_EQ_INT(exteria_dtls_get_state(c), EXTERIA_DTLS_CONNECTED);
    CHECK_EQ_INT(exteria_dtls_get_state(s), EXTERIA_DTLS_CONNECTED);
    CHECK_EQ_INT(exteria_dtls_srtp_keys(c, ck, cs, crk, crs), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_srtp_keys(s, sk, ss, srk, srs), EXTERIA_OK);
    /* what the client sends is what the server receives, and the two directions use different keys */
    CHECK_MEM(ck, srk, 16);
    CHECK_MEM(cs, srs, 14);
    CHECK_MEM(crk, sk, 16);
    CHECK_MEM(crs, ss, 14);
    CHECK(memcmp(ck, crk, 16) != 0);
    CHECK(memcmp(cs, crs, 14) != 0);

    /* and they work as SRTP keys: a packet protected by one end opens at the other, both ways */
    {
        exteria_tgc_srtp tx, rx;
        uint8_t pkt[64];
        size_t n = 0, m = 0;
        CHECK_EQ_INT(exteria_tgc_srtp_init(&tx, ck, cs), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_srtp_init(&rx, srk, srs), EXTERIA_OK);
        exteria_rtp_write_header(pkt, sizeof(pkt), 111, 0, 1, 1, 0x1234u);
        memcpy(pkt + 12, "voice", 5);
        CHECK_EQ_INT(exteria_tgc_srtp_protect(&tx, pkt, 17, sizeof(pkt), &n), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_srtp_unprotect(&rx, pkt, n, &m), EXTERIA_OK);
        CHECK(memcmp(pkt + 12, "voice", 5) == 0);
        CHECK_EQ_INT(exteria_tgc_srtp_init(&tx, sk, ss), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_srtp_init(&rx, crk, crs), EXTERIA_OK);
        exteria_rtp_write_header(pkt, sizeof(pkt), 111, 0, 1, 1, 0x4321u);
        memcpy(pkt + 12, "reply", 5);
        CHECK_EQ_INT(exteria_tgc_srtp_protect(&tx, pkt, 17, sizeof(pkt), &n), EXTERIA_OK);
        CHECK_EQ_INT(exteria_tgc_srtp_unprotect(&rx, pkt, n, &m), EXTERIA_OK);
        CHECK(memcmp(pkt + 12, "reply", 5) == 0);
    }
    exteria_dtls_free(c);
    exteria_dtls_free(s);
}

static void application_data(void) {
    exteria_dtls *c, *s;
    uint8_t msg[EXTERIA_DTLS_MAX_APP_DATA], out[EXTERIA_DTLS_MAX_DATAGRAM];
    size_t n = 0, i;
    make_pair(&c, &s);
    CHECK_EQ_INT(exteria_dtls_write(c, msg, 10), EXTERIA_E_STATE);
    exteria_dtls_start(s, 0);
    exteria_dtls_start(c, 1);
    pump(c, s, NULL);
    for (i = 0; i < sizeof(msg); ++i) msg[i] = (uint8_t)(i * 5u + 3u);
    /* one byte, a typical packet, and the largest; each arrives as one message, in order */
    CHECK_EQ_INT(exteria_dtls_write(c, msg, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_write(c, msg, 300), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_write(s, msg, EXTERIA_DTLS_MAX_APP_DATA), EXTERIA_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(exteria_dtls_read(s, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 1);
    CHECK_EQ_INT(exteria_dtls_read(s, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 300);
    CHECK_MEM(out, msg, 300);
    CHECK_EQ_INT(exteria_dtls_read(s, out, sizeof(out), &n), EXTERIA_E_RETRY);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(exteria_dtls_read(c, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, EXTERIA_DTLS_MAX_APP_DATA);
    CHECK_MEM(out, msg, EXTERIA_DTLS_MAX_APP_DATA);
    /* limits */
    CHECK_EQ_INT(exteria_dtls_write(c, msg, 0), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_dtls_write(c, msg, EXTERIA_DTLS_MAX_APP_DATA + 1), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_dtls_write(NULL, msg, 4), EXTERIA_E_ARG);
    /* a message the reader's buffer cannot take is dropped, and the next one is still there */
    CHECK_EQ_INT(exteria_dtls_write(c, msg, 500), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_write(c, msg, 20), EXTERIA_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(exteria_dtls_read(s, out, 100, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_dtls_read(s, out, 100, &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 20);
    exteria_dtls_free(c);
    exteria_dtls_free(s);
}

static void wrong_or_missing_fingerprint(void) {
    exteria_dtls *c, *s, *other;
    int i;
    /* the client expects another certificate than the server has */
    CHECK_EQ_INT(exteria_dtls_new(&c), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_new(&s), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_new(&other), EXTERIA_OK);
    exteria_dtls_set_peer_fingerprint(c, "sha-256", exteria_dtls_local_fingerprint(other));
    exteria_dtls_set_peer_fingerprint(s, "sha-256", exteria_dtls_local_fingerprint(c));
    exteria_dtls_start(s, 0);
    exteria_dtls_start(c, 1);
    pump(c, s, NULL);
    CHECK_EQ_INT(exteria_dtls_get_state(c), EXTERIA_DTLS_FAILED);
    CHECK(exteria_dtls_get_state(s) != EXTERIA_DTLS_CONNECTED);
    {
        uint8_t k[16], t[14], k2[16], t2[14];
        CHECK_EQ_INT(exteria_dtls_srtp_keys(c, k, t, k2, t2), EXTERIA_E_STATE);
    }
    exteria_dtls_free(c);
    exteria_dtls_free(s);

    /* the server expects another certificate than the client has: the server refuses it */
    CHECK_EQ_INT(exteria_dtls_new(&c), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_new(&s), EXTERIA_OK);
    exteria_dtls_set_peer_fingerprint(c, "sha-256", exteria_dtls_local_fingerprint(s));
    exteria_dtls_set_peer_fingerprint(s, "sha-256", exteria_dtls_local_fingerprint(other));
    exteria_dtls_start(s, 0);
    exteria_dtls_start(c, 1);
    pump(c, s, NULL);
    CHECK_EQ_INT(exteria_dtls_get_state(s), EXTERIA_DTLS_FAILED);
    CHECK(exteria_dtls_get_state(c) != EXTERIA_DTLS_CONNECTED);
    exteria_dtls_free(c);
    exteria_dtls_free(s);

    /* none given at all */
    CHECK_EQ_INT(exteria_dtls_new(&c), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_new(&s), EXTERIA_OK);
    exteria_dtls_set_peer_fingerprint(s, "sha-256", exteria_dtls_local_fingerprint(c));
    exteria_dtls_start(s, 0);
    exteria_dtls_start(c, 1);
    pump(c, s, NULL);
    CHECK_EQ_INT(exteria_dtls_get_state(c), EXTERIA_DTLS_FAILED);
    for (i = 0; i < 3; ++i) {
        uint8_t junk[40] = {0};
        CHECK(exteria_dtls_input(c, junk, sizeof(junk)) != EXTERIA_OK);
    }
    exteria_dtls_free(c);
    exteria_dtls_free(s);
    exteria_dtls_free(other);
}

static void fingerprint_parsing(void) {
    exteria_dtls *d;
    char good[EXTERIA_DTLS_FINGERPRINT_LEN + 1], lower[EXTERIA_DTLS_FINGERPRINT_LEN + 1], bad[EXTERIA_DTLS_FINGERPRINT_LEN + 1];
    size_t i;
    CHECK_EQ_INT(exteria_dtls_new(&d), EXTERIA_OK);
    snprintf(good, sizeof(good), "%s", exteria_dtls_local_fingerprint(d));
    for (i = 0; i <= EXTERIA_DTLS_FINGERPRINT_LEN; ++i) lower[i] = (char)((good[i] >= 'A' && good[i] <= 'F') ? good[i] + 32 : good[i]);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", good), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "Sha-256", lower), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-1", good), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-2560", good), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "", good), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", ""), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", "AA:BB"), EXTERIA_E_MALFORMED);
    snprintf(bad, sizeof(bad), "%s", good);
    bad[2] = '-';
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", bad), EXTERIA_E_MALFORMED);
    snprintf(bad, sizeof(bad), "%s", good);
    bad[10] = 'G';
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", bad), EXTERIA_E_MALFORMED);
    snprintf(bad, sizeof(bad), "%s", good);
    bad[EXTERIA_DTLS_FINGERPRINT_LEN - 1] = '\0';
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", bad), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(NULL, "sha-256", good), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, NULL, good), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", NULL), EXTERIA_E_ARG);
    /* the fingerprint may not change once the handshake began */
    {
        exteria_dtls *other;
        CHECK_EQ_INT(exteria_dtls_new(&other), EXTERIA_OK);
        exteria_dtls_start(d, 1);
        CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", good), EXTERIA_OK);
        CHECK_EQ_INT(exteria_dtls_set_peer_fingerprint(d, "sha-256", exteria_dtls_local_fingerprint(other)), EXTERIA_E_STATE);
        exteria_dtls_free(other);
    }
    exteria_dtls_free(d);
    CHECK_EQ_INT(exteria_dtls_new(NULL), EXTERIA_E_ARG);
    CHECK(exteria_dtls_local_fingerprint(NULL) == NULL);
    CHECK_EQ_INT(exteria_dtls_get_state(NULL), EXTERIA_DTLS_FAILED);
    exteria_dtls_free(NULL);
}

/* the flights are lost once each: the handshake must finish by resending on the timer */
static int drop_first_of_each_early_datagram(int n) {
    return n == 0 || n == 2;
}

static void loss_and_retransmission(void) {
    exteria_dtls *c, *s;
    int rounds;
    sent = 0;
    make_pair(&c, &s);
    exteria_dtls_start(s, 0);
    exteria_dtls_start(c, 1);
    pump(c, s, drop_first_of_each_early_datagram);
    for (rounds = 0; rounds < 12 && !(exteria_dtls_get_state(c) == EXTERIA_DTLS_CONNECTED && exteria_dtls_get_state(s) == EXTERIA_DTLS_CONNECTED); ++rounds) {
        uint32_t wait_c = 0, wait_s = 0, wait;
        exteria_status sc = exteria_dtls_timeout(c, &wait_c), ss = exteria_dtls_timeout(s, &wait_s);
        if (sc != EXTERIA_OK && ss != EXTERIA_OK) break;
        wait = sc == EXTERIA_OK ? wait_c : wait_s;
        if (ss == EXTERIA_OK && wait_s < wait) wait = wait_s;
        usleep((useconds_t)(wait + 20) * 1000);
        exteria_dtls_on_timeout(c);
        exteria_dtls_on_timeout(s);
        pump(c, s, NULL);
    }
    CHECK_EQ_INT(exteria_dtls_get_state(c), EXTERIA_DTLS_CONNECTED);
    CHECK_EQ_INT(exteria_dtls_get_state(s), EXTERIA_DTLS_CONNECTED);
    {
        uint32_t ms;
        CHECK_EQ_INT(exteria_dtls_timeout(c, &ms), EXTERIA_E_STATE);
        CHECK_EQ_INT(exteria_dtls_on_timeout(c), EXTERIA_OK);
    }
    exteria_dtls_free(c);
    exteria_dtls_free(s);
}

static void early_and_damaged_input(void) {
    exteria_dtls *c, *s;
    uint8_t buf[EXTERIA_DTLS_MAX_DATAGRAM], big[EXTERIA_DTLS_MAX_DATAGRAM + 1];
    size_t n = 0;
    make_pair(&c, &s);
    /* the client's first flight arrives at the server before the server was started: it is kept and used */
    exteria_dtls_start(c, 1);
    while (exteria_dtls_poll(c, buf, sizeof(buf), &n) == EXTERIA_OK) CHECK_EQ_INT(exteria_dtls_input(s, buf, n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_get_state(s), EXTERIA_DTLS_IDLE);
    CHECK_EQ_INT(exteria_dtls_start(s, 0), EXTERIA_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(exteria_dtls_get_state(c), EXTERIA_DTLS_CONNECTED);
    CHECK_EQ_INT(exteria_dtls_get_state(s), EXTERIA_DTLS_CONNECTED);
    /* garbage after the handshake, an empty datagram, one that is too large: dropped, the session lives on */
    memset(buf, 0x5A, 60);
    CHECK_EQ_INT(exteria_dtls_input(c, buf, 60), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_input(c, buf, 0), EXTERIA_OK);
    memset(big, 0, sizeof(big));
    CHECK_EQ_INT(exteria_dtls_input(c, big, sizeof(big)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_dtls_input(c, NULL, 5), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_dtls_get_state(c), EXTERIA_DTLS_CONNECTED);
    CHECK_EQ_INT(exteria_dtls_write(c, (const uint8_t *)"still here", 10), EXTERIA_OK);
    pump(c, s, NULL);
    CHECK_EQ_INT(exteria_dtls_read(s, buf, sizeof(buf), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 10);
    /* poll with no datagram, with a small buffer */
    CHECK_EQ_INT(exteria_dtls_poll(c, buf, sizeof(buf), &n), EXTERIA_E_RETRY);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(exteria_dtls_write(c, (const uint8_t *)"abc", 3), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_poll(c, buf, 10, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_dtls_poll(c, buf, sizeof(buf), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_dtls_poll(NULL, buf, sizeof(buf), &n), EXTERIA_E_ARG);
    exteria_dtls_free(c);
    exteria_dtls_free(s);

    /* more datagrams than the queue holds before the start: the extra ones are refused, not lost silently */
    {
        exteria_dtls *d;
        int i, refused = 0;
        CHECK_EQ_INT(exteria_dtls_new(&d), EXTERIA_OK);
        for (i = 0; i < 40; ++i) if (exteria_dtls_input(d, buf, 50) == EXTERIA_E_LIMIT) ++refused;
        CHECK_EQ_INT(refused, 8);
        exteria_dtls_free(d);
    }
}

int main(void) {
    handshake_and_keys();
    application_data();
    wrong_or_missing_fingerprint();
    fingerprint_parsing();
    early_and_damaged_input();
    loss_and_retransmission();
    return test_finish("test_dtls");
}
