#ifndef EXTERIA_PROFILE_H
#define EXTERIA_PROFILE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_messages.h"
#include "exteria_people.h"
#include "exteria_tl.h"

#define EXTERIA_ABOUT_MAX 512
#define EXTERIA_NAME_PART_MAX 64
#define EXTERIA_USERNAME_MIN 5
#define EXTERIA_USERNAME_MAX 32

typedef struct exteria_full_user {
    char about[EXTERIA_ABOUT_MAX];  /* the bio, empty when there is none; line breaks stay */
    uint8_t has_person;
    exteria_person_row person;      /* the user's own entry of the answer: name, username, phone when visible, photo */
    uint8_t has_birthday;
    int32_t birthday_day;
    int32_t birthday_month;
    int32_t birthday_year;          /* zero when the year is hidden */
    uint8_t has_channel;            /* the personal channel shown on the profile */
    exteria_dialog_row channel;     /* peer_kind 3 with its title, photo and access hash */
    int32_t channel_participants;
    int32_t channel_message;        /* the id of the message the profile shows from it, zero for none */
    uint8_t require_premium;        /* only Telegram Premium users may write to this user, and nobody else may reply to their stories */
    uint8_t has_music;              /* the song the profile shows first, from its saved music */
    exteria_media_info music;
} exteria_full_user;

/* the songs saved on a profile, one page at a time */
#define EXTERIA_MUSIC_PAGE 30
/* users.getSavedMusic of the user a peer names (kind 1 with an access hash, or oneself), from offset on; limit is
   1 to EXTERIA_MUSIC_PAGE */
exteria_status exteria_saved_music_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset, int32_t limit, exteria_tl_value **out);
/* account.saveMusic: puts the song on the signed in profile, or takes it off it when unsave is set; the song is
   the one a reference names (a document with a file reference); EXTERIA_E_ARG for one that cannot be fetched */
exteria_status exteria_save_music_request(exteria_arena *arena, const exteria_media_ref *song, int unsave, exteria_tl_value **out);
/* a users.savedMusic answer: the songs that have a fetchable file are put in tracks (at most cap), count says how
   many, and total is how many the profile has altogether */
exteria_status exteria_saved_music_parse(const exteria_tl_value *answer, exteria_media_info *tracks, size_t cap, size_t *count, int32_t *total);

/* users.getFullUser for the signed in user, or for another user named by peer (kind 1, with an access hash) */
exteria_status exteria_full_user_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_full_user_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out);
/* a users.userFull answer; anything else is EXTERIA_E_MALFORMED. out is always initialised */
exteria_status exteria_full_user_parse(const exteria_tl_value *answer, exteria_full_user *out);

/* account.updateBirthday; year 0 leaves it out */
exteria_status exteria_birthday_request(exteria_arena *arena, int32_t day, int32_t month, int32_t year, exteria_tl_value **out);
/* account.updateBirthday without a birthday, which takes it off the profile */
exteria_status exteria_birthday_clear_request(exteria_arena *arena, exteria_tl_value **out);

/* account.updatePersonalChannel for a channel the person manages, or no channel when channel is NULL */
exteria_status exteria_personal_channel_request(exteria_arena *arena, const exteria_peer_ref *channel, exteria_tl_value **out);
/* the channels that can be put on the profile, and the rows of the answer (a messages.chats), channels only */
exteria_status exteria_admined_channels_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_admined_channels_parse(const exteria_tl_value *answer, exteria_dialog_row *rows, size_t cap, size_t *count);
/* channels.getMessages for one message of a channel */
exteria_status exteria_channel_message_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t id, exteria_tl_value **out);

/* account.updateProfile for the fields that are not NULL; a first name must not be empty; names are at most
   EXTERIA_NAME_PART_MAX bytes, the bio EXTERIA_ABOUT_MAX - 1; all three NULL is EXTERIA_E_ARG */
exteria_status exteria_profile_update_request(exteria_arena *arena, const char *first_name, const char *last_name, const char *about,
                                              exteria_tl_value **out);

/* a username is empty (which removes it) or 5 to 32 letters, digits and underscores, starting with a letter and not
   ending with an underscore; EXTERIA_E_ARG otherwise */
exteria_status exteria_username_check(const char *name);
exteria_status exteria_username_request(exteria_arena *arena, const char *name, exteria_tl_value **out);

/* photos.uploadProfilePhoto for a file already uploaded, the inputFile the upload gave */
exteria_status exteria_profile_photo_request(exteria_arena *arena, exteria_tl_value *file, exteria_tl_value **out);

#endif
