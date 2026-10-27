#ifndef EXTERIA_NOTIFY_TYPES_H
#define EXTERIA_NOTIFY_TYPES_H

#include <stdint.h>

/* the notification settings of one chat or one kind of chat, as the server holds them; the rules that use them are in exteria_notify_prefs.h */

#define EXTERIA_SOUND_NAME_MAX 48
#define EXTERIA_NOTIFY_MUTE_FOREVER 2147483647

typedef enum exteria_sound_kind {
    EXTERIA_SOUND_DEFAULT = 0,
    EXTERIA_SOUND_NONE,
    /* a tone of the app: data is the file name of the bundle, title the name the person sees */
    EXTERIA_SOUND_LOCAL,
    /* a tone saved in the cloud of the account */
    EXTERIA_SOUND_RINGTONE
} exteria_sound_kind;

typedef struct exteria_notify_sound {
    int32_t kind;
    int64_t ringtone_id;
    char title[EXTERIA_SOUND_NAME_MAX];
    char data[EXTERIA_SOUND_NAME_MAX];
} exteria_notify_sound;

/* what a peerNotifySettings holds */
typedef struct exteria_peer_notify {
    uint8_t has_mute;
    int32_t mute_until;         /* zero is on, a time in the past is on, EXTERIA_NOTIFY_MUTE_FOREVER is off for good */
    uint8_t has_previews;
    uint8_t previews;           /* 1 shows the text of the message */
    uint8_t has_silent;
    uint8_t silent;             /* 1 delivers without a sound */
    uint8_t has_sound;
    exteria_notify_sound sound;
    uint8_t has_stories_muted;
    uint8_t stories_muted;
    uint8_t has_stories_hide_sender;
    uint8_t stories_hide_sender;
    uint8_t has_stories_sound;
    exteria_notify_sound stories_sound;
} exteria_peer_notify;

#endif
