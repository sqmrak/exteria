#ifndef EXTERIA_DIALOGS_H
#define EXTERIA_DIALOGS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_media_ref.h"
#include "exteria_notify_types.h"
#include "exteria_people.h"
#include "exteria_photos.h"
#include "exteria_tl.h"

#define EXTERIA_DIALOGS_MAX 200
#define EXTERIA_DIALOG_TITLE_MAX 128
#define EXTERIA_DIALOG_SENDER_MAX 64
#define EXTERIA_DIALOG_TEXT_MAX 160

typedef enum exteria_dialog_kind {
    EXTERIA_DIALOG_USER = 1,
    EXTERIA_DIALOG_BOT,
    EXTERIA_DIALOG_GROUP,
    EXTERIA_DIALOG_CHANNEL
} exteria_dialog_kind;

typedef enum exteria_preview_kind {
    EXTERIA_PREVIEW_NONE = 0,
    EXTERIA_PREVIEW_TEXT,
    EXTERIA_PREVIEW_PHOTO,
    EXTERIA_PREVIEW_VIDEO,
    EXTERIA_PREVIEW_VIDEO_MESSAGE,
    EXTERIA_PREVIEW_VOICE,
    EXTERIA_PREVIEW_AUDIO,
    EXTERIA_PREVIEW_STICKER,
    EXTERIA_PREVIEW_GIF,
    EXTERIA_PREVIEW_FILE,
    EXTERIA_PREVIEW_LOCATION,
    EXTERIA_PREVIEW_CONTACT,
    EXTERIA_PREVIEW_POLL,
    EXTERIA_PREVIEW_SERVICE,
    EXTERIA_PREVIEW_OTHER
} exteria_preview_kind;

/* one chat list row; text is UTF-8 cut at a character boundary with line breaks turned into spaces */
typedef struct exteria_dialog_row {
    int32_t peer_kind;      /* 1 user, 2 chat, 3 channel, as exteria_peer */
    int64_t peer_id;
    exteria_dialog_kind kind;
    uint8_t contact;
    uint8_t saved;          /* the chat with oneself */
    uint8_t deleted;
    uint8_t verified;
    uint8_t premium;        /* the user of a private chat has Telegram Premium */
    int64_t emoji_status;       /* the custom emoji document the user shows after their name, zero without one */
    int32_t emoji_status_until; /* unix time it ends, zero when it has none */
    uint8_t pinned;
    uint8_t muted;
    /* the settings the chat sets itself, which stand over those of its kind; muted above is only its own mute */
    exteria_peer_notify notify;
    uint8_t can_post;       /* a broadcast channel the account may post in: its creator, or an admin allowed to post */
    uint8_t unread_mark;
    uint8_t outgoing;       /* the last message is ours */
    uint8_t forwarded;      /* the last message carries a forward header, which the list marks with an arrow before the preview */
    uint8_t read;           /* and the other side has read it */
    uint8_t sender_is_self;
    uint8_t folder;         /* the archive entry of the chat list, not a chat */
    uint8_t forum;          /* a supergroup whose chat is split into topics */
    uint8_t community;      /* a community: a set of chats the server lists as one entry; peer_id is its id */
    uint8_t community_collapsed;    /* the account asked to see the community as one chat in its list */
    /* a chat or bot that was added to a community: its id, and the access hash and title of the community when the answer carries it; zero without one */
    int64_t linked_community_id;
    int64_t linked_community_hash;
    char linked_community_title[EXTERIA_DIALOG_TITLE_MAX];
    uint8_t left;           /* the account is not a member of this group or channel */
    /* a topic row: the forum above names the peer fields, topic_id the thread (1 is General) */
    int32_t topic_id;
    int64_t topic_icon_emoji;   /* the custom emoji document of the icon, zero for the plain colored hash */
    int32_t topic_icon_color;   /* 0xRRGGBB of the plain icon */
    uint8_t topic_closed;
    int32_t folder_id;
    int64_t peer_hash;      /* the access hash an input peer needs; zero for a basic group */
    int32_t top_message;
    int32_t read_inbox_max_id;  /* everything up to this id of theirs we have read */
    int32_t read_outbox_max_id; /* everything up to this id of ours they have read */
    int32_t date;
    int32_t unread_count;
    int32_t mentions;
    int32_t reactions;      /* messages of ours that got a reaction we have not seen */
    int32_t participants_count;
    exteria_preview_kind preview;
    /* a small picture of the photo, video, gif or round video of the last message, for the chat list; source none for everything else */
    exteria_media_ref thumb;
    uint8_t service;        /* for a service message: exteria_service_kind + 1, with its text and number below */
    int32_t service_value;
    exteria_presence presence;  /* of the other side of a user chat, unknown for the rest */
    int32_t seen;
    exteria_photo_ref photo;
    char title[EXTERIA_DIALOG_TITLE_MAX];
    /* who wrote the last message when it was not a user chat; empty otherwise */
    char sender[EXTERIA_DIALOG_SENDER_MAX];
    /* the user behind that name and the photo of the user, for the small picture before the preview; zero when the name is empty or the user has no photo */
    int64_t sender_id;
    exteria_photo_ref sender_photo;
    /* the message text, a caption, a sticker emoji or a file name; empty when the kind says it all */
    char text[EXTERIA_DIALOG_TEXT_MAX];
} exteria_dialog_row;

/* fills the title, photo, hash and kind of a row whose peer_kind and peer_id are set, from the users and chats of an answer;
   a peer the answer does not carry is left with an empty title (a user is then marked deleted) */
void exteria_dialog_peer_read(exteria_dialog_row *row, const exteria_tl_value *users, const exteria_tl_value *chats, int64_t self_id);

/* what a global search looks through: every message, only the posts of channels, or one kind of attachment */
typedef enum exteria_search_kind {
    EXTERIA_SEARCH_ALL = 0,
    EXTERIA_SEARCH_POSTS,
    EXTERIA_SEARCH_MEDIA,
    EXTERIA_SEARCH_LINKS,
    EXTERIA_SEARCH_FILES,
    EXTERIA_SEARCH_MUSIC,
    EXTERIA_SEARCH_VOICE
} exteria_search_kind;

/* reads a messages.messages, messagesSlice or channelMessages answer to a global search */
exteria_status exteria_search_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *rows, size_t cap,
                                    size_t *count, int32_t *next_rate);

/* contacts.search for the text over every public user, bot, group and channel; limit is 1 to EXTERIA_DIALOGS_MAX */
exteria_status exteria_found_request(exteria_arena *arena, const char *query, int32_t limit, exteria_tl_value **out);
/* reads a contacts.found answer: first the chats the account already has with the text, then the public ones, each
   peer once, at most cap rows */
exteria_status exteria_found_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *rows, size_t cap, size_t *count);

/* reads a messages.dialogs or messages.dialogsSlice answer in server order, at most cap rows. self_id marks the
   saved messages chat, now (unix seconds) decides which mutes are still running */
exteria_status exteria_dialogs_parse(const exteria_tl_value *answer, int64_t self_id, int32_t now,
                                     exteria_dialog_row *rows, size_t cap, size_t *count);

/* messages.getSavedDialogs: the favorites split by the chat each message came from, newest first, up to limit (1
   to EXTERIA_DIALOGS_MAX), pinned ones included */
exteria_status exteria_saved_dialogs_request(exteria_arena *arena, int32_t offset_date, int32_t offset_id, int32_t offset_peer_kind, int64_t offset_peer_id,
                                             int64_t offset_peer_hash, int32_t limit, exteria_tl_value **out);

/* what the header of a community screen needs besides its chats */
#define EXTERIA_COMMUNITY_ABOUT_MAX 256
typedef struct exteria_community_info {
    char title[EXTERIA_DIALOG_TITLE_MAX];
    char about[EXTERIA_COMMUNITY_ABOUT_MAX];
    uint8_t collapsed;      /* shown as one chat in the list */
    exteria_photo_ref photo;
} exteria_community_info;

/* reads the messages.chatFull answer to channels.getFullChannel for a community: its title, description and list
   state in info, and one row per chat it links in server order, at most cap rows */
exteria_status exteria_community_parse(const exteria_tl_value *answer, exteria_community_info *info, exteria_dialog_row *rows,
                                       size_t cap, size_t *count);

/* adds live dialog state without losing community order, membership or peer metadata */
exteria_status exteria_community_previews_apply(const exteria_tl_value *answer, int64_t self_id, int32_t now,
                                               exteria_dialog_row *rows, size_t count);

/* communities.toggleCommunityCollapsedInDialogs: collapsed shows the community as one chat in the account's list */
exteria_status exteria_community_collapse_request(exteria_arena *arena, int64_t id, int64_t access_hash, int collapsed, exteria_tl_value **out);

/* messages.getForumTopics for a forum: offset_date, offset_id and offset_topic are zero for the first page and the
   date */
exteria_status exteria_topics_request(exteria_arena *arena, int32_t peer_kind, int64_t peer_id, int64_t peer_hash, int32_t offset_date,
                                      int32_t offset_id, int32_t offset_topic, int32_t limit, exteria_tl_value **out);

/* reads a messages.forumTopics answer into one row per topic in server order (pinned first, then by last message),
   at most cap rows. forum is the row of the forum itself */
exteria_status exteria_topics_parse(const exteria_tl_value *answer, const exteria_dialog_row *forum, int64_t self_id, int32_t now,
                                    exteria_dialog_row *rows, size_t cap, size_t *count);

/* folder-filtered getDialogs may omit dialogFolder, but archive remains a valid destination */
exteria_status exteria_dialogs_ensure_archive(exteria_dialog_row *rows, size_t cap, size_t *count);

/* folder metadata supplies total unread chats; only names from folder 1 form its preview */
exteria_status exteria_archive_summary_parse(const exteria_tl_value *info, const exteria_tl_value *contents,
                                              int64_t self_id, int32_t now, exteria_dialog_row *out);

#endif
