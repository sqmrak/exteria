#ifndef EXTERIA_FAKETLS_H
#define EXTERIA_FAKETLS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_bytes.h"
#include "exteria_status.h"

/* the "ee" secrets of an MTProto proxy: the stream of the obfuscated transport rides inside what looks like a TLS 1.3 connection to a real site (the
   domain at the end of the secret). The client hello proves the secret with an HMAC in its random field, the proxy answers with a server hello that
   proves it back, and from then on every write is a TLS application data record */

#define EXTERIA_FAKETLS_SECRET_LEN 16
#define EXTERIA_FAKETLS_HELLO_LEN 517
/* the bytes the hello draws on: a session id, the private key of the key share, and the values that stand in the GREASE slots */
#define EXTERIA_FAKETLS_ENTROPY_LEN 72
/* the longest a domain may be and still leave room for the padding extension of a 517 byte hello */
#define EXTERIA_FAKETLS_DOMAIN_MAX 120
/* what one record carries when the client writes; the real clients cut there too */
#define EXTERIA_FAKETLS_RECORD_MAX 2878
/* a record that claims more than this is not TLS (a record holds 16384 bytes, and 256 for the cipher) */
#define EXTERIA_FAKETLS_PAYLOAD_MAX 16640
/* the server hello, the change cipher spec and the first application record, together, at the most */
#define EXTERIA_FAKETLS_REPLY_MAX (3 * (5 + EXTERIA_FAKETLS_PAYLOAD_MAX))

/* the client hello into out; timestamp is the unix time that the proxy checks against its clock. random receives the 32 bytes of the random field as
   sent, which the reply is checked against. EXTERIA_E_ARG for a domain that is empty, longer than EXTERIA_FAKETLS_DOMAIN_MAX or has a character that
   is not a letter, a digit, a dot or a hyphen */
exteria_status exteria_faketls_hello(const uint8_t secret[EXTERIA_FAKETLS_SECRET_LEN], const char *domain, uint32_t timestamp,
                                     const uint8_t entropy[EXTERIA_FAKETLS_ENTROPY_LEN], uint8_t out[EXTERIA_FAKETLS_HELLO_LEN],
                                     uint8_t random[32]);

/* how far a reply has got: EXTERIA_OK when buf holds the whole of the three records (total is their length), EXTERIA_E_RETRY while more bytes are
   needed (total is what the records seen so far ask for, or zero when that is not known yet), EXTERIA_E_MALFORMED for anything that is not a server
   hello, a change cipher spec and an application record in that order */
exteria_status exteria_faketls_reply_progress(const uint8_t *buf, size_t len, size_t *total);

/* the three records as a whole: EXTERIA_E_SECURITY when the digest in the server hello is not the HMAC of the client's random field and the reply, which
   is what a server that does not hold the secret cannot produce */
exteria_status exteria_faketls_check_reply(const uint8_t secret[EXTERIA_FAKETLS_SECRET_LEN], const uint8_t random[32], const uint8_t *reply, size_t len);

/* the records of the stream after the handshake, read as the bytes arrive */
typedef struct exteria_faketls_reader {
    uint8_t header[5];
    uint8_t header_len;
    uint16_t remaining;     /* payload bytes of the record that is open */
    uint8_t type;
} exteria_faketls_reader;

void exteria_faketls_reader_init(exteria_faketls_reader *reader);
/* in comes from the socket and out gets the payload of the application records in it, never more than in_len bytes (out_cap must be at least in_len).
   A change cipher spec record is skipped, an alert or any other kind, a version other than 3.3 or a length above EXTERIA_FAKETLS_PAYLOAD_MAX is
   EXTERIA_E_MALFORMED, and the reader stays where a partial record left it */
exteria_status exteria_faketls_unwrap(exteria_faketls_reader *reader, const uint8_t *in, size_t in_len, uint8_t *out, size_t out_cap, size_t *out_len);

/* data as application data records of at most EXTERIA_FAKETLS_RECORD_MAX bytes each, appended to out */
exteria_status exteria_faketls_wrap(const uint8_t *data, size_t len, exteria_writer *out);

/* HMAC-SHA256, the message the parts joined */
exteria_status exteria_faketls_hmac(const uint8_t *key, size_t key_len, const exteria_slice *parts, size_t count, uint8_t out[32]);

#endif
