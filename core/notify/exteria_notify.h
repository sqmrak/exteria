#ifndef EXTERIA_NOTIFY_H
#define EXTERIA_NOTIFY_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_notify_prefs.h"
#include "exteria_status.h"

/* what the notification daemon shows when the app is closed; no I/O here, so the rules are tested on the host */

#define EXTERIA_NOTIFY_SEEN_MAX 256
#define EXTERIA_NOTIFY_EVENTS_MAX 8
#define EXTERIA_NOTIFY_TITLE_MAX 128
#define EXTERIA_NOTIFY_BODY_MAX 200
/* a chat whose newest message is older than this is not announced after the daemon was down, so a reboot does not bring a day of old banners */
#define EXTERIA_NOTIFY_CATCHUP_SECONDS (6 * 3600)
#define EXTERIA_NOTIFY_STATE_BYTES (8 + EXTERIA_NOTIFY_SEEN_MAX * 16)
/* the longest line the daemon writes to a banner client */
#define EXTERIA_NOTIFY_LINE_MAX (EXTERIA_NOTIFY_TITLE_MAX + EXTERIA_NOTIFY_BODY_MAX + 80)

typedef struct exteria_notify_settings {
    uint8_t enabled;    /* the master switch of the phone: no look, no banner */
    uint8_t russian;    /* the words of the banner are Russian, else English */
    exteria_notify_rules rules; /* the settings of the account and the few switches of the phone */
} exteria_notify_settings;

/* the newest message of each chat that was already looked at; the daemon keeps it on disk between runs */
typedef struct exteria_notify_state {
    uint32_t count;
    uint8_t baselined;  /* a first look was taken, so what it saw is not new */
    struct {
        int32_t peer_kind;
        int64_t peer_id;
        int32_t top_message;
    } seen[EXTERIA_NOTIFY_SEEN_MAX];
} exteria_notify_state;

typedef struct exteria_notify_event {
    int32_t peer_kind;
    int64_t peer_id;
    int32_t message_id;
    char title[EXTERIA_NOTIFY_TITLE_MAX];
    char body[EXTERIA_NOTIFY_BODY_MAX];
    /* the tone the chat asks for; kind NONE is a banner without a sound */
    exteria_notify_sound sound;
} exteria_notify_event;

void exteria_notify_state_init(exteria_notify_state *state);

/* looks at the chat list the server just gave (newest first) and says which chats got a message worth a banner
   since the last look */
exteria_status exteria_notify_diff(exteria_notify_state *state, const exteria_notify_settings *settings, const exteria_dialog_row *rows, size_t row_count,
                                   int32_t now, int32_t active_peer_kind, int64_t active_peer_id, exteria_notify_event *events, size_t cap,
                                   size_t *count, size_t *more_suppressed);

/* the summary line for what did not fit: "and N more messages" in the language of the settings */
void exteria_notify_more_text(const exteria_notify_settings *settings, size_t more, char *out, size_t cap);

/* the state as bytes for a file, and back. unpack rejects wrong magic, version and counts and leaves a fresh state then */
exteria_status exteria_notify_state_pack(const exteria_notify_state *state, uint8_t *out, size_t cap, size_t *len);
exteria_status exteria_notify_state_unpack(const uint8_t *data, size_t len, exteria_notify_state *out);

/* one event as a text line: "N", the peer kind, peer id and message id, then the title and the body, tab
   separated, ended with a newline */
exteria_status exteria_notify_line_encode(const exteria_notify_event *event, char *out, size_t cap, size_t *len);
/* the reverse, for a line without its newline; EXTERIA_E_MALFORMED for anything else */
exteria_status exteria_notify_line_decode(const char *line, size_t len, exteria_notify_event *out);

#endif
