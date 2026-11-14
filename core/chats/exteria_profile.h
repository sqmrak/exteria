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
/* the private note on a contact, in bytes of utf-8 with the terminator */
#define EXTERIA_CONTACT_NOTE_MAX 512

typedef struct exteria_star_rating {
    int32_t level;
    int64_t current_level_stars;
    int64_t stars;
    int64_t next_level_stars;
    uint8_t has_next;
} exteria_star_rating;

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
    uint8_t sharing_restricted;     /* either participant has disabled sharing */
    uint8_t blocked;                /* the account has blocked this user */
    uint8_t has_music;              /* the song the profile shows first, from its saved music */
    exteria_media_info music;
    /* the message the person set for every new chat with them: a title, a text and one sticker; a business account feature */
    uint8_t has_intro;
    char intro_title[64];
    char intro_text[256];
    uint8_t has_intro_sticker;
    exteria_sticker_row intro_sticker;
    char note[EXTERIA_CONTACT_NOTE_MAX];    /* the note the account keeps on this contact, empty when there is none */
    uint8_t has_personal_photo;     /* the account set its own photo for this contact, which the server shows instead of the one they chose */
    uint8_t has_public_photo;       /* the photo those who may not see the main one get; only the answer for the signed in user carries it */
    exteria_media_info public_photo;
    uint8_t has_rating;
    uint8_t has_pending_rating;
    int32_t pending_rating_date;
    exteria_star_rating rating;
    exteria_star_rating pending_rating;
    int32_t common_chats;           /* how many groups the account and this user are both in; zero when the answer does not say */
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
/* the most groups one page of the common chats holds, which is what the server allows */
#define EXTERIA_COMMON_CHATS_PAGE 100
/* messages.getCommonChats: the groups the account shares with a user (kind 1, with an access hash), a page of limit (1 to EXTERIA_COMMON_CHATS_PAGE) after the chat id max_id,
   or from the start when max_id is zero */
exteria_status exteria_common_chats_request(exteria_arena *arena, const exteria_peer_ref *user, int64_t max_id, int32_t limit, exteria_tl_value **out);
/* the rows of a messages.chats or messages.chatsSlice answer: groups and supergroups, in the order sent (a channel with no hash and a chat the server only names are left out).
   last_id is the id of the last chat the answer holds, left-out ones included, which the next page starts after; raw is how many chats it held, so a page of fewer than
   the limit ends the list */
exteria_status exteria_common_chats_parse(const exteria_tl_value *answer, exteria_dialog_row *rows, size_t cap, size_t *count, int64_t *last_id, size_t *raw);
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
/* the same with fallback set: the photo is shown to those who may not see the main one, and the main photo stays */
exteria_status exteria_profile_public_photo_request(exteria_arena *arena, exteria_tl_value *file, exteria_tl_value **out);
/* photos.deletePhotos for one profile photo of the signed in user, as a photo ref from the list of profile photos tells it; anything but a photo
   with an id is EXTERIA_E_ARG */
exteria_status exteria_profile_photo_delete_request(exteria_arena *arena, const exteria_media_ref *photo, exteria_tl_value **out);
/* a profile picture that moves: the uploaded mp4 and the second of it that stands for it while it does not play */
exteria_status exteria_profile_video_request(exteria_arena *arena, exteria_tl_value *video, double start_seconds, exteria_tl_value **out);

/* contacts.updateContactNote: the note is plain text without entities, empty to take it off; a user needs a hash, and a note of EXTERIA_CONTACT_NOTE_MAX bytes or more is EXTERIA_E_ARG */
exteria_status exteria_contact_note_request(exteria_arena *arena, const exteria_peer_ref *user, const char *note, exteria_tl_value **out);
/* photos.uploadContactProfilePhoto for a file already uploaded: suggest sends it to the contact as a proposal for their own photo; without it the photo is set for
   this contact on the account's side only */
exteria_status exteria_contact_photo_request(exteria_arena *arena, const exteria_peer_ref *user, exteria_tl_value *file, int suggest, exteria_tl_value **out);
/* the same call with the save flag and no file, which takes away the photo the account set for the contact, so the contact's own photo shows again */
exteria_status exteria_contact_photo_reset_request(exteria_arena *arena, const exteria_peer_ref *user, exteria_tl_value **out);

#endif
