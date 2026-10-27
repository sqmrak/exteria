#ifndef EXTERIA_CALL_H
#define EXTERIA_CALL_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_tl.h"

/* the signaling of one-to-one voice calls: the Diffie-Hellman exchange that makes the call key, the phone.*
   requests, and the reading of a PhoneCall */

#define EXTERIA_CALL_KEY_LEN 256
#define EXTERIA_CALL_EMOJI_COUNT 333
#define EXTERIA_CALL_EMOJI_SHOWN 4
#define EXTERIA_CALL_CONNECTIONS_MAX 8
#define EXTERIA_CALL_TURNS_MAX 4
#define EXTERIA_CALL_CREDENTIAL_MAX 128
#define EXTERIA_CALL_IP_MAX 48
#define EXTERIA_CALL_TAG_LEN 16

/* the lowest layer of the call protocol we speak, the highest one, and the library version we name: libtgvoip 2.4.4 is the audio engine
   built into the app, and both sides must name a version they share */
#define EXTERIA_CALL_MIN_LAYER 65
#define EXTERIA_CALL_MAX_LAYER 92
#define EXTERIA_CALL_LIBRARY_VERSION "2.4.4"
/* the tgcalls version this app also speaks; listed first, so that two phones that both know it settle on it, and
   one that does not falls back to libtgvoip */
#define EXTERIA_CALL_TGCALLS_VERSION "7.0.0"

/* messages.getDhConfig as the call asks it: version is what the app already holds (zero for none) */
exteria_status exteria_call_dh_request(exteria_arena *arena, int32_t version, exteria_tl_value **out);

typedef struct exteria_call_dh {
    uint8_t p[EXTERIA_CALL_KEY_LEN];
    int32_t g;
    int32_t version;
} exteria_call_dh;

/* reads a messages.DhConfig */
exteria_status exteria_call_dh_parse(const exteria_tl_value *answer, const exteria_call_dh *known, exteria_call_dh *out, uint8_t random[EXTERIA_CALL_KEY_LEN]);

/* one side's secret and public value: the secret is the system's random bytes xor the server's, the public value
   is g to that power mod p, 256 bytes */
exteria_status exteria_call_make_secret(const exteria_call_dh *dh, const uint8_t server_random[EXTERIA_CALL_KEY_LEN],
                                       uint8_t secret[EXTERIA_CALL_KEY_LEN], uint8_t pub[EXTERIA_CALL_KEY_LEN]);
/* the same with a fixed random, for tests */
exteria_status exteria_call_make_secret_from(const exteria_call_dh *dh, const uint8_t seed[EXTERIA_CALL_KEY_LEN],
                                            const uint8_t server_random[EXTERIA_CALL_KEY_LEN], uint8_t secret[EXTERIA_CALL_KEY_LEN],
                                            uint8_t pub[EXTERIA_CALL_KEY_LEN]);

/* the key both sides share: the other's public value to the power of our secret, mod p, as 256 bytes, and its
   fingerprint, the last eight bytes of its sha1 as a little endian integer */
exteria_status exteria_call_make_key(const exteria_call_dh *dh, const uint8_t other_pub[EXTERIA_CALL_KEY_LEN],
                                    const uint8_t secret[EXTERIA_CALL_KEY_LEN], uint8_t key[EXTERIA_CALL_KEY_LEN], int64_t *fingerprint);

/* what the caller commits to before it sees the callee's value: the sha256 of its public value */
exteria_status exteria_call_commit(const uint8_t pub[EXTERIA_CALL_KEY_LEN], uint8_t hash[32]);

/* the four emoji of a call, as indexes into exteria_call_emoji, from the key and the caller's public value; the two people compare them
   aloud to be sure no one sits between them */
exteria_status exteria_call_emoji_indexes(const uint8_t key[EXTERIA_CALL_KEY_LEN], const uint8_t caller_pub[EXTERIA_CALL_KEY_LEN],
                                         uint16_t indexes[EXTERIA_CALL_EMOJI_SHOWN]);
extern const char *const exteria_call_emoji[EXTERIA_CALL_EMOJI_COUNT];

/* phone.requestCall to a user, with the commitment and our protocol; video asks for a video call */
exteria_status exteria_call_request_request(exteria_arena *arena, const exteria_peer_ref *user, int32_t random_id, const uint8_t hash[32], int video,
                                           exteria_tl_value **out);
/* phone.acceptCall with our public value, and phone.confirmCall with the caller's own and the key's fingerprint */
exteria_status exteria_call_accept_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t pub[EXTERIA_CALL_KEY_LEN],
                                          exteria_tl_value **out);
exteria_status exteria_call_confirm_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t pub[EXTERIA_CALL_KEY_LEN],
                                           int64_t fingerprint, exteria_tl_value **out);
/* phone.sendSignalingData: bytes of the call's signaling for the other phone; EXTERIA_E_LIMIT for none or more than 16 KiB */
exteria_status exteria_call_signaling_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t *data, size_t len, exteria_tl_value **out);
/* phone.receivedCall: tells the caller that the phone rings */
exteria_status exteria_call_received_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, exteria_tl_value **out);

typedef enum exteria_call_reason {
    EXTERIA_CALL_REASON_NONE = 0,
    EXTERIA_CALL_REASON_MISSED,
    EXTERIA_CALL_REASON_DISCONNECT,
    EXTERIA_CALL_REASON_HANGUP,
    EXTERIA_CALL_REASON_BUSY
} exteria_call_reason;

/* phone.discardCall; duration is the seconds the call lasted, connection_id the id of the endpoint it ran on (zero when none) */
exteria_status exteria_call_discard_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, int32_t duration, exteria_call_reason reason,
                                           int64_t connection_id, exteria_tl_value **out);

typedef enum exteria_call_kind {
    EXTERIA_CALL_EMPTY = 0,
    EXTERIA_CALL_WAITING,       /* ours, the callee's phone has not rung yet */
    EXTERIA_CALL_REQUESTED,     /* theirs, ringing */
    EXTERIA_CALL_ACCEPTED,      /* ours, the callee answered with their public value */
    EXTERIA_CALL_ACTIVE,        /* the key is set, the endpoints are known */
    EXTERIA_CALL_DISCARDED
} exteria_call_kind;

typedef struct exteria_call_connection {
    int64_t id;
    uint8_t tcp;
    uint16_t port;
    char ip[EXTERIA_CALL_IP_MAX];
    char ipv6[EXTERIA_CALL_IP_MAX];
    uint8_t peer_tag[EXTERIA_CALL_TAG_LEN];
} exteria_call_connection;

/* a TURN server of the call (a PhoneConnectionWebrtc with the turn flag): the other phone can be reached through
   an allocation on it when the reflector protocol is blocked on its network; IPv4 only */
typedef struct exteria_call_turn {
    int64_t id;
    uint16_t port;
    char ip[EXTERIA_CALL_IP_MAX];
    char username[EXTERIA_CALL_CREDENTIAL_MAX];
    char password[EXTERIA_CALL_CREDENTIAL_MAX];
} exteria_call_turn;

typedef struct exteria_phone_call {
    exteria_call_kind kind;
    int64_t id;
    int64_t access_hash;
    int32_t date;
    int64_t admin_id;           /* who called */
    int64_t participant_id;     /* who was called */
    uint8_t video;
    uint8_t p2p_allowed;
    int32_t receive_date;       /* waiting: when the callee's phone got it, zero until then */
    uint8_t has_hash;
    uint8_t g_hash[32];         /* requested: the caller's commitment */
    uint8_t has_g;
    uint8_t g[EXTERIA_CALL_KEY_LEN];    /* accepted: the callee's value, active: the other side's value */
    int64_t key_fingerprint;
    int32_t min_layer;
    int32_t max_layer;
    char version[16];           /* the first library version the call settled on */
    uint8_t connection_count;
    exteria_call_connection connections[EXTERIA_CALL_CONNECTIONS_MAX];
    uint8_t turn_count;
    exteria_call_turn turns[EXTERIA_CALL_TURNS_MAX];
    exteria_call_reason reason;
    int32_t duration;
    uint8_t need_rating;
} exteria_phone_call;

/* reads a PhoneCall, from an updatePhoneCall's phone_call or a phone.phoneCall's */
exteria_status exteria_phone_call_parse(const exteria_tl_value *call, exteria_phone_call *out);
/* the phone_call of a phone.phoneCall answer, which also names the users */
exteria_status exteria_phone_call_from_answer(const exteria_tl_value *answer, exteria_phone_call *out);

#endif
