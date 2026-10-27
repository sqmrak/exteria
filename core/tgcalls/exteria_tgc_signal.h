#ifndef EXTERIA_TGC_SIGNAL_H
#define EXTERIA_TGC_SIGNAL_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the messages of the tgcalls v2 signaling (Signaling.cpp of tgcalls), read from and written as the JSON the
   official clients exchange */

#define EXTERIA_TGC_MAX_CONTENTS 4
#define EXTERIA_TGC_MAX_PAYLOADS 4
#define EXTERIA_TGC_MAX_FEEDBACK 6
#define EXTERIA_TGC_MAX_PARAMS 6
#define EXTERIA_TGC_MAX_EXTENSIONS 8
#define EXTERIA_TGC_MAX_GROUPS 3
#define EXTERIA_TGC_MAX_GROUP_SSRCS 4
#define EXTERIA_TGC_MAX_CANDIDATES 24
#define EXTERIA_TGC_MAX_FINGERPRINTS 2

#define EXTERIA_TGC_NAME_LEN 24
#define EXTERIA_TGC_FEEDBACK_LEN 20
#define EXTERIA_TGC_PARAM_KEY_LEN 32
#define EXTERIA_TGC_PARAM_VALUE_LEN 64
#define EXTERIA_TGC_URI_LEN 96
#define EXTERIA_TGC_UFRAG_LEN 64
#define EXTERIA_TGC_PWD_LEN 128
#define EXTERIA_TGC_FINGERPRINT_LEN 128
#define EXTERIA_TGC_CANDIDATE_LEN 384

typedef enum exteria_tgc_message_type {
    EXTERIA_TGC_MESSAGE_NONE = 0,
    EXTERIA_TGC_MESSAGE_INITIAL_SETUP,
    EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS,
    EXTERIA_TGC_MESSAGE_CANDIDATES,
    EXTERIA_TGC_MESSAGE_MEDIA_STATE
} exteria_tgc_message_type;

typedef struct exteria_tgc_feedback {
    char type[EXTERIA_TGC_FEEDBACK_LEN];
    char subtype[EXTERIA_TGC_FEEDBACK_LEN];
} exteria_tgc_feedback;

typedef struct exteria_tgc_param {
    char key[EXTERIA_TGC_PARAM_KEY_LEN];
    char value[EXTERIA_TGC_PARAM_VALUE_LEN];
} exteria_tgc_param;

typedef struct exteria_tgc_payload {
    uint8_t id;
    char name[EXTERIA_TGC_NAME_LEN];
    uint32_t clockrate;
    uint32_t channels;
    uint8_t feedback_count;
    exteria_tgc_feedback feedback[EXTERIA_TGC_MAX_FEEDBACK];
    uint8_t param_count;
    exteria_tgc_param params[EXTERIA_TGC_MAX_PARAMS];
} exteria_tgc_payload;

typedef struct exteria_tgc_extension {
    uint8_t id;
    char uri[EXTERIA_TGC_URI_LEN];
} exteria_tgc_extension;

typedef struct exteria_tgc_ssrc_group {
    char semantics[EXTERIA_TGC_NAME_LEN];
    uint8_t count;
    uint32_t ssrcs[EXTERIA_TGC_MAX_GROUP_SSRCS];
} exteria_tgc_ssrc_group;

typedef struct exteria_tgc_content {
    uint8_t video;              /* 0 audio, 1 video */
    uint32_t ssrc;
    uint8_t group_count;
    exteria_tgc_ssrc_group groups[EXTERIA_TGC_MAX_GROUPS];
    uint8_t payload_count;
    exteria_tgc_payload payloads[EXTERIA_TGC_MAX_PAYLOADS];
    uint8_t extension_count;
    exteria_tgc_extension extensions[EXTERIA_TGC_MAX_EXTENSIONS];
} exteria_tgc_content;

typedef struct exteria_tgc_fingerprint {
    char hash[EXTERIA_TGC_NAME_LEN];
    char setup[EXTERIA_TGC_NAME_LEN];
    char value[EXTERIA_TGC_FINGERPRINT_LEN];
} exteria_tgc_fingerprint;

typedef struct exteria_tgc_initial_setup {
    char ufrag[EXTERIA_TGC_UFRAG_LEN];
    char pwd[EXTERIA_TGC_PWD_LEN];
    uint8_t renomination;
    uint8_t fingerprint_count;
    exteria_tgc_fingerprint fingerprints[EXTERIA_TGC_MAX_FINGERPRINTS];
} exteria_tgc_initial_setup;

typedef struct exteria_tgc_negotiate {
    uint32_t exchange_id;
    uint8_t content_count;
    exteria_tgc_content contents[EXTERIA_TGC_MAX_CONTENTS];
} exteria_tgc_negotiate;

typedef struct exteria_tgc_candidates {
    uint8_t count;
    char sdp[EXTERIA_TGC_MAX_CANDIDATES][EXTERIA_TGC_CANDIDATE_LEN];
} exteria_tgc_candidates;

typedef enum exteria_tgc_video_state {
    EXTERIA_TGC_VIDEO_INACTIVE = 0,
    EXTERIA_TGC_VIDEO_SUSPENDED,
    EXTERIA_TGC_VIDEO_ACTIVE
} exteria_tgc_video_state;

typedef struct exteria_tgc_media_state {
    uint8_t muted;
    uint8_t low_battery;
    uint8_t video_state;        /* exteria_tgc_video_state */
    uint16_t video_rotation;    /* 0, 90, 180 or 270 degrees */
    uint8_t screencast_state;   /* exteria_tgc_video_state */
} exteria_tgc_media_state;

typedef struct exteria_tgc_message {
    exteria_tgc_message_type type;
    union {
        exteria_tgc_initial_setup initial_setup;
        exteria_tgc_negotiate negotiate;
        exteria_tgc_candidates candidates;
        exteria_tgc_media_state media_state;
    } u;
} exteria_tgc_message;

/* reads one message. out is always initialised */
exteria_status exteria_tgc_message_parse(const char *text, size_t len, exteria_tgc_message *out);

/* writes the message as JSON, NUL terminated, and the length of it to len; EXTERIA_E_ARG for a message of no type
   or a value that cannot be sent (an empty ufrag, a content with ssrc 0), EXTERIA_E_LIMIT when the buffer is too
   small */
exteria_status exteria_tgc_message_write(const exteria_tgc_message *message, char *out, size_t capacity, size_t *len);

#endif
