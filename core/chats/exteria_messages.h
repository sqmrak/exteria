#ifndef EXTERIA_MESSAGES_H
#define EXTERIA_MESSAGES_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_gift.h"
#include "exteria_media.h"
#include "exteria_reactions.h"
#include "exteria_poll.h"
#include "exteria_tl.h"
#include "exteria_voice.h"

#define EXTERIA_MESSAGES_MAX 100
#define EXTERIA_MESSAGE_TEXT_MAX (4 * 4096 + 4)
#define EXTERIA_MESSAGE_ENTITIES_MAX 48
#define EXTERIA_MESSAGE_URLS_MAX 1024
#define EXTERIA_STICKERS_MAX 400
#define EXTERIA_STICKER_SETS_MAX 200
#define EXTERIA_ANIMATED_EMOJI_MAX 1024
#define EXTERIA_ANIMATED_EMOJI_BYTES_MAX (512 * 1024)

typedef enum exteria_entity_kind {
    EXTERIA_ENTITY_BOLD = 1,
    EXTERIA_ENTITY_ITALIC,
    EXTERIA_ENTITY_UNDERLINE,
    EXTERIA_ENTITY_STRIKE,
    EXTERIA_ENTITY_CODE,
    EXTERIA_ENTITY_URL,         /* the text is the address */
    EXTERIA_ENTITY_TEXT_URL,    /* the address is in the url pool */
    EXTERIA_ENTITY_EMAIL,
    EXTERIA_ENTITY_MENTION,
    EXTERIA_ENTITY_HASHTAG,
    EXTERIA_ENTITY_CUSTOM_EMOJI, /* the text is the emoji it stands for, document_id draws it */
    EXTERIA_ENTITY_BOT_COMMAND, /* "/start" or "/start@bot", a command a tap sends */
    EXTERIA_ENTITY_SPOILER,
    EXTERIA_ENTITY_PRE,         /* a block of code, its language (maybe empty) in the url pool */
    EXTERIA_ENTITY_BLOCKQUOTE,  /* flags: EXTERIA_ENTITY_COLLAPSED */
    EXTERIA_ENTITY_MENTION_NAME, /* a name that opens the profile of user_id, whatever the words say */
    EXTERIA_ENTITY_FORMATTED_DATE /* the words stand for the moment date, shown as the flags ask */
} exteria_entity_kind;

/* flags of an entity: a quote that starts folded, and the shapes a formatted date takes (none set means the plain date and time) */
enum {
    EXTERIA_ENTITY_COLLAPSED = 1,
    EXTERIA_DATE_RELATIVE = 1,
    EXTERIA_DATE_SHORT_TIME = 2,
    EXTERIA_DATE_LONG_TIME = 4,
    EXTERIA_DATE_SHORT_DATE = 8,
    EXTERIA_DATE_LONG_DATE = 16,
    EXTERIA_DATE_DAY_OF_WEEK = 32
};

/* offsets and lengths count UTF-16 units, as the server sends them and as NSString counts */
typedef struct exteria_entity {
    uint8_t kind;
    int32_t offset;
    int32_t length;
    int16_t url_offset;     /* into exteria_message_row.urls, -1 without one */
    int16_t url_length;
    int64_t document_id;    /* custom emoji only */
    int64_t user_id;        /* mention name only */
    int32_t date;           /* formatted date only, seconds since 1970 */
    uint8_t flags;
} exteria_entity;

/* reads the entities shared by a message and a textWithEntities, with a bounded url pool */
void exteria_entities_read(const exteria_tl_value *value, exteria_entity *entities, size_t capacity,
                           char *urls, size_t urls_capacity, uint8_t *count);

/* an entity of a message being sent. text is the address of a text link or the language of a block of code (NULL
   or empty for none) and only has to live through the call */
typedef struct exteria_send_entity {
    uint8_t kind;
    uint8_t flags;
    int32_t offset;
    int32_t length;
    int64_t id;
    int64_t access_hash;
    int32_t date;
    const char *text;
} exteria_send_entity;

typedef enum exteria_service_kind {
    EXTERIA_SERVICE_OTHER = 0,
    EXTERIA_SERVICE_CHAT_CREATE,
    EXTERIA_SERVICE_TITLE,
    EXTERIA_SERVICE_PHOTO_CHANGED,
    EXTERIA_SERVICE_PHOTO_DELETED,
    EXTERIA_SERVICE_USER_ADDED,
    EXTERIA_SERVICE_USER_REMOVED,
    EXTERIA_SERVICE_JOINED,
    EXTERIA_SERVICE_CHANNEL_CREATE,
    EXTERIA_SERVICE_PIN,
    EXTERIA_SERVICE_CALL,
    EXTERIA_SERVICE_GIFT,
    EXTERIA_SERVICE_CONTACT_JOINED,
    EXTERIA_SERVICE_SCREENSHOT,
    EXTERIA_SERVICE_HISTORY_CLEAR,
    EXTERIA_SERVICE_MIGRATED,         /* text names the group it was upgraded from, empty for the group that was upgraded */
    EXTERIA_SERVICE_CUSTOM,           /* text is the whole line, as a bot or the server wrote it */
    EXTERIA_SERVICE_VIDEO_CHAT,       /* value is the length in seconds of a video chat that ended, zero while one starts */
    EXTERIA_SERVICE_VIDEO_CHAT_INVITE,
    EXTERIA_SERVICE_TOPIC_CREATE,
    EXTERIA_SERVICE_TOPIC_EDIT,       /* text is the new title when it changed; value is 1 for closed, 2 for reopened */
    EXTERIA_SERVICE_TTL,              /* value is the auto-delete period in seconds, zero when it was turned off */
    EXTERIA_SERVICE_BOOST,
    EXTERIA_SERVICE_PAYMENT,
    EXTERIA_SERVICE_BOT_ALLOWED,
    EXTERIA_SERVICE_PREMIUM_GIFT,     /* value is the number of months; the gift of a Premium subscription or a gift code */
    EXTERIA_SERVICE_THEME,            /* text is the emoji of the new theme of the chat, empty when the theme was taken off */
    EXTERIA_SERVICE_WALLPAPER,
    EXTERIA_SERVICE_PHOTO_SUGGESTED,
    EXTERIA_SERVICE_GAME_SCORE,       /* value is the score */
    EXTERIA_SERVICE_GIVEAWAY,
    EXTERIA_SERVICE_GIVEAWAY_RESULTS, /* value is the number of winners */
    EXTERIA_SERVICE_PAYMENT_REFUNDED,
    EXTERIA_SERVICE_SHARING_REQUEST, /* value bits: previous, requested, expired */
    EXTERIA_SERVICE_SHARING_TOGGLE   /* value bits: previous, new */
} exteria_service_kind;

/* how a call ended, as the server says: nothing for a call that was talked through and hung up */
typedef enum exteria_call_outcome {
    EXTERIA_OUTCOME_ENDED = 0,
    EXTERIA_OUTCOME_MISSED,
    EXTERIA_OUTCOME_BUSY,
    EXTERIA_OUTCOME_DISCONNECTED
} exteria_call_outcome;

/* a messageAction as the kind plus one, the line it carries in text, a number in value and the user it names in
   target */
uint8_t exteria_service_summary(const exteria_tl_value *action, char *text, size_t cap, int32_t *value, int64_t *target);

typedef struct exteria_message_row {
    int32_t id;
    int32_t date;
    int32_t edit_date;
    uint8_t edit_hide;          /* the server changed the message (a reaction, a vote) and asks that it is not shown as edited, whatever edit_date says */
    int32_t reply_peer_kind;   /* zero when the original is in this chat */
    int64_t reply_peer_id;
    char reply_quote[1024];
    int32_t reply_to;           /* id of the replied message, zero without one, or when it is only the root of its forum topic */
    int32_t topic_id;           /* the forum topic it belongs to; 1 (General) for a message with no topic header */
    int32_t thread_id;          /* the top reply in a discussion, or the direct reply when there is no top */
    int64_t from_id;            /* the user who wrote it, zero for a channel post or an anonymous sender */
    int64_t from_channel;       /* the channel it was written as in a group, zero when a user wrote it */
    int64_t target_id;          /* the user a service message is about */
    uint8_t out;
    uint8_t unread_mention;
    uint8_t post;
    uint8_t forwarded;
    int32_t saved_peer_kind;    /* in the favorites: the chat the message came from (the account itself for its own notes); zero elsewhere */
    int64_t saved_peer_id;
    uint8_t forward_saved_out;  /* the header says the copy in the favorites was written by the account itself */
    uint8_t service;            /* exteria_service_kind + 1, zero for an ordinary message */
    int32_t service_value;      /* the number some service kinds carry, see exteria_service_kind */
    uint8_t entity_count;
    char forward_name[EXTERIA_DIALOG_SENDER_MAX];
    int64_t grouped_id;         /* the album the message is a part of, zero for a message of its own */
    int32_t forward_date;       /* when the original was written, unix seconds; zero when the header has none */
    int64_t forward_from;       /* who wrote a forwarded message, when the header says */
    uint8_t call_reason;        /* a call service message: exteria_call_outcome */
    uint8_t call_video;         /* and whether the call had video; the length in seconds is service_value */
    char from_rank[128];
    exteria_media_info media;
    exteria_gift gift;          /* a gift service message: the gift, with its note in text */
    exteria_reactions reactions;
    uint8_t reactions_possible;
    int64_t via_bot_id;         /* the bot whose inline result this message is, zero otherwise */
    uint8_t has_markup;         /* buttons or a keyboard came with it; exteria_markup_read of the message's reply_markup tells which */
    uint8_t has_reactions;
    int32_t views;              /* how many saw a channel post, zero when the server did not count */
    uint8_t has_comments;       /* a channel post that has a comment thread in its discussion group */
    int32_t comments;           /* the comments so far */
    int64_t discussion_id;      /* the discussion group (a channel id), zero when unknown */
    uint8_t commenter_count;
    int64_t commenters[3];      /* the newest commenters, most recent first, users only */
    exteria_entity entities[EXTERIA_MESSAGE_ENTITIES_MAX];
    /* the poll of a message whose media is one; present is zero for any other message */
    exteria_poll poll;
    char urls[EXTERIA_MESSAGE_URLS_MAX];
    /* for a service message the new title, otherwise the message text; line breaks stay */
    char text[EXTERIA_MESSAGE_TEXT_MAX];
} exteria_message_row;

typedef struct exteria_sticker_row {
    exteria_media_info media;
} exteria_sticker_row;

typedef struct exteria_sticker_set_row {
    int64_t id;
    int64_t access_hash;
    int32_t count;
    int32_t hash;
    int32_t thumb_dc;
    int32_t thumb_version;
    int64_t thumb_document_id;
    uint8_t official;
    uint8_t installed;      /* the account has the set among its own */
    char title[64];
    char short_name[48];
} exteria_sticker_set_row;

/* how a request names a chat: user and channel need the access hash, a basic group does not,
   and the chat with oneself is inputPeerSelf */
typedef struct exteria_peer_ref {
    int32_t kind;           /* 1 user, 2 chat, 3 channel, as exteria_peer */
    int64_t id;
    int64_t access_hash;
    uint8_t self;
    int32_t topic_id;       /* a forum topic the chat is narrowed to, zero for the whole chat */
} exteria_peer_ref;


/* one Document as a sticker; EXTERIA_E_MALFORMED when it is not a sticker the app can show (a mask, a custom emoji,
   a document without the sticker attribute) */
exteria_status exteria_sticker_read(const exteria_tl_value *document, exteria_sticker_row *out);

/* a Message or MessageService; messageEmpty is EXTERIA_E_NOTFOUND, anything else EXTERIA_E_MALFORMED */
exteria_status exteria_message_read(const exteria_tl_value *message, exteria_message_row *out);

/* a messages.messages, messagesSlice or channelMessages answer in server order (newest first), at most cap rows */
exteria_status exteria_messages_parse(const exteria_tl_value *answer, exteria_message_row *rows, size_t cap, size_t *count);

/* a messages.allStickers answer; allStickersNotModified is EXTERIA_E_NOTFOUND; sets of masks and of custom emoji
   are left out, they are no use in a message */
exteria_status exteria_sticker_sets_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count);

/* messages.getFeaturedStickers with hash zero, the trending sets */
exteria_status exteria_featured_stickers_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_featured_stickers_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count);
/* messages.getArchivedStickers for sticker sets, a page of limit (1 to 100) after the set with offset_id, zero for
   the first page */
exteria_status exteria_archived_stickers_request(exteria_arena *arena, int64_t offset_id, int32_t limit, exteria_tl_value **out);
exteria_status exteria_archived_stickers_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count, int32_t *total);

/* a messages.stickerSet answer: the set header and its stickers in set order */
exteria_status exteria_sticker_set_parse(const exteria_tl_value *answer, exteria_sticker_set_row *set,
                                         exteria_sticker_row *stickers, size_t cap, size_t *count);
exteria_status exteria_animated_emoji_request(exteria_arena *arena, exteria_tl_value **out);
/* messages.getStickerSet of a set named by its short name, such as tg_placeholders_android; the name is 1 to 64
   letters, digits and underscores, else EXTERIA_E_ARG */
exteria_status exteria_sticker_set_by_name_request(exteria_arena *arena, const char *short_name, exteria_tl_value **out);
/* official emoji pack mappings, with the pack emoticon in media.alt; unsupported formats are left out */
exteria_status exteria_animated_emoji_parse(const exteria_tl_value *answer, exteria_sticker_row *rows, size_t cap, size_t *count);

/* messages.getFavedStickers and messages.getSavedGifs with hash zero, which the server answers in full; read with the two parsers below */
exteria_status exteria_faved_stickers_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_saved_gifs_request(exteria_arena *arena, exteria_tl_value **out);
/* a messages.favedStickers answer; favedStickersNotModified is EXTERIA_E_NOTFOUND */
exteria_status exteria_faved_stickers_parse(const exteria_tl_value *answer, exteria_sticker_row *stickers, size_t cap, size_t *count);
/* a messages.savedGifs answer: the animations the account kept, as rows whose media kind is EXTERIA_PREVIEW_GIF (a document that is no animation is
   left out); savedGifsNotModified is EXTERIA_E_NOTFOUND */
exteria_status exteria_saved_gifs_parse(const exteria_tl_value *answer, exteria_sticker_row *gifs, size_t cap, size_t *count);
/* messages.faveSticker: puts the sticker among the favorites, or takes it out when unfave is set; the sticker is a document with its reference */
exteria_status exteria_fave_sticker_request(exteria_arena *arena, const exteria_media_ref *sticker, int unfave, exteria_tl_value **out);
/* messages.clearRecentStickers, which empties the recent list */
exteria_status exteria_clear_recent_stickers_request(exteria_arena *arena, exteria_tl_value **out);
/* a messages.recentStickers answer, newest first; recentStickersNotModified is EXTERIA_E_NOTFOUND */
exteria_status exteria_recent_stickers_parse(const exteria_tl_value *answer, exteria_sticker_row *stickers, size_t cap, size_t *count);

/* the server id the answer to a send gave the message with this random id; EXTERIA_E_NOTFOUND when it names none */
exteria_status exteria_sent_parse(const exteria_tl_value *updates, int64_t random_id, int32_t *id);

/* a message sent into a topic answers the topic root, which is how the server files it; General has no root to answer, and a chat
   without topics is left as it is */
exteria_status exteria_set_topic_reply(exteria_arena *arena, exteria_tl_value *request, const exteria_peer_ref *peer);

/* requests, all built in arena; a basic group or channel without its hash, or a user without one, is EXTERIA_E_ARG */
exteria_status exteria_input_peer(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out);
/* messages.getPeerDialogs, at most 100 explicit peers per request */
exteria_status exteria_peer_dialogs_request(exteria_arena *arena, const exteria_peer_ref *peers, size_t count, exteria_tl_value **out);
exteria_status exteria_history_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t limit,
                                      exteria_tl_value **out);
/* the same with add_offset: a negative one moves the page toward newer messages, so offset_id of a message plus one with add_offset of minus half the limit gives the
   page around that message, and offset_id of the newest message held with minus the limit gives the page after it. add_offset must stay under the limit */
exteria_status exteria_history_window_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t add_offset, int32_t limit,
                                              exteria_tl_value **out);
/* messages.getSavedHistory: the messages of the favorites that came from one chat (the account itself for its own
   notes), newest first, read with exteria_messages_parse. source must be a user */
exteria_status exteria_saved_history_request(exteria_arena *arena, const exteria_peer_ref *source, int32_t offset_id, int32_t limit,
                                             exteria_tl_value **out);
/* the same with the negative add_offset of exteria_history_window_request */
exteria_status exteria_saved_history_window_request(exteria_arena *arena, const exteria_peer_ref *source, int32_t offset_id, int32_t add_offset, int32_t limit,
                                                    exteria_tl_value **out);
/* channels.exportMessageLink for one message of a channel or supergroup: the link, public or private, that opens
   it */
exteria_status exteria_message_link_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t id, exteria_tl_value **out);
/* the exportedMessageLink it answers: the address in link (capacity cap, at most 255 bytes kept) */
exteria_status exteria_message_link_parse(const exteria_tl_value *answer, char *link, size_t cap);
/* messages.search for the pinned messages of a chat or its topic, newest first, up to limit (1 to EXTERIA_MESSAGES_MAX); the answer is read with
   exteria_messages_parse */
/* messages.getStickers for one emoji: the stickers the server suggests for it, as the empty chat's greeting asks
   with a waving hand */
#define EXTERIA_STICKER_EMOTICON_MAX 32
exteria_status exteria_stickers_request(exteria_arena *arena, const char *emoticon, exteria_tl_value **out);
/* a messages.Stickers: EXTERIA_E_NOTFOUND for stickersNotModified, which a request with hash zero never gets */
exteria_status exteria_stickers_parse(const exteria_tl_value *answer, exteria_sticker_row *stickers, size_t cap, size_t *count);
exteria_status exteria_pinned_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out);
/* messages.getUnreadReactions for the messages of ours that got a reaction not seen yet, newest first, up to limit (1 to EXTERIA_MESSAGES_MAX);
   read with exteria_messages_parse */
exteria_status exteria_unread_reactions_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out);
/* messages.readReactions: every reaction of the chat or its topic counts as seen */
exteria_status exteria_read_reactions_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out);
/* messages.search for the messages that set a new photo of a group or channel, newest first, up to limit (1 to EXTERIA_MESSAGES_MAX); the answer is
   read with exteria_chat_avatars_parse */
exteria_status exteria_chat_photos_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t limit, exteria_tl_value **out);
#define EXTERIA_CHAT_SEARCH_QUERY_MAX 256
/* messages.search for a text in one chat, newest matches first, up to limit (1 to EXTERIA_MESSAGES_MAX); read with
   the same parser as the pinned messages */
exteria_status exteria_chat_search_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *query, int32_t limit,
                                           exteria_tl_value **out);
/* messages.search for everything one person wrote in a chat, newest first, up to limit (1 to EXTERIA_MESSAGES_MAX); read with the same parser.
   from must be a user with its hash, or the account itself (self set), anything else is EXTERIA_E_ARG */
exteria_status exteria_chat_from_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_peer_ref *from, int32_t limit,
                                         exteria_tl_value **out);
/* messages.getMessages, or channels.getMessages for a channel, for these message ids (one to EXTERIA_MESSAGES_MAX,
   all positive) */
exteria_status exteria_messages_by_id_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count, exteria_tl_value **out);
/* sets schedule_date of a send request: the message waits on the server until that time (unix seconds, positive),
   and the account sees it in the scheduled messages of the chat */
exteria_status exteria_set_schedule(exteria_arena *arena, exteria_tl_value *request, int32_t date);
/* the kinds of media a chat is looked through by: its photos and videos, its files, its links */
typedef enum exteria_shared_kind {
    EXTERIA_SHARED_MEDIA = 0,
    EXTERIA_SHARED_FILES,
    EXTERIA_SHARED_LINKS,
    EXTERIA_SHARED_AUDIO,
    EXTERIA_SHARED_VOICE
} exteria_shared_kind;
/* messages.search with the filter of a kind and no text, newest first, a page of limit (1 to EXTERIA_MESSAGES_MAX) older than offset_id (zero for the
   newest); read with exteria_messages_parse */
exteria_status exteria_shared_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_shared_kind kind, int32_t offset_id, int32_t limit, exteria_tl_value **out);

/* one photo or video of an album, once the server has it: what an inputMediaPhoto or inputMediaDocument needs */
#define EXTERIA_ALBUM_ITEMS_MAX 10
#define EXTERIA_ALBUM_REF_MAX 256
typedef struct exteria_album_media {
    uint8_t is_photo;               /* a photo, otherwise a document (a video) */
    int64_t id;
    int64_t access_hash;
    uint8_t file_reference[EXTERIA_ALBUM_REF_MAX];
    size_t file_reference_len;
    uint8_t spoiler;                /* shown blurred until the person taps it */
} exteria_album_media;
struct exteria_upload_spec;
/* messages.uploadMedia for an uploaded file of this spec (a photo or a video) into the chat, which the server answers with the media to send */
exteria_status exteria_album_upload_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value *file, const struct exteria_upload_spec *spec,
                                            exteria_tl_value **out);
/* the messageMediaPhoto or messageMediaDocument it answers; out is always initialised and EXTERIA_E_MALFORMED means anything else */
exteria_status exteria_album_media_parse(const exteria_tl_value *answer, exteria_album_media *out);
/* messages.sendMultiMedia of two to EXTERIA_ALBUM_ITEMS_MAX items */
exteria_status exteria_album_send_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_album_media *items, const int64_t *random_ids,
                                          const char *const *captions, size_t count, exteria_tl_value **out);
/* the entity vector of text for a request that carries entities; *out stays NULL when none of them is sent. EXTERIA_E_ARG for a range outside the text or
   a kind without what it points at */
exteria_status exteria_send_entities_build(exteria_arena *arena, const char *text, const exteria_send_entity *entities, size_t entity_count,
                                          exteria_tl_value **out);
/* every kind of entity but the ones the server finds itself (addresses, hashtags, commands) is sent; offsets and
   lengths count UTF-16 units of text */
exteria_status exteria_send_text_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *text,
                                        const exteria_send_entity *entities, size_t entity_count, int64_t random_id, exteria_tl_value **out);
/* the same as an answer to the message reply_to (zero for none, which is the plain request); a negative id is EXTERIA_E_ARG */
exteria_status exteria_send_text_reply_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *text,
                                               const exteria_send_entity *entities, size_t entity_count, int64_t random_id, int32_t reply_to,
                                               exteria_tl_value **out);
/* sets reply_to of a send request: the message answered, with the topic when the chat has one; zero answers the topic root only */
exteria_status exteria_set_reply(exteria_arena *arena, exteria_tl_value *request, const exteria_peer_ref *peer, int32_t reply_to);
exteria_status exteria_send_sticker_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_media_ref *sticker,
                                           int64_t random_id, exteria_tl_value **out);
typedef enum exteria_upload_kind {
    EXTERIA_UPLOAD_VOICE = 1,       /* an Ogg Opus voice note with its waveform */
    EXTERIA_UPLOAD_ROUND,           /* a square mp4 played in a circle */
    EXTERIA_UPLOAD_PHOTO,           /* a jpeg shown as a photo */
    EXTERIA_UPLOAD_VIDEO,           /* an mp4 shown as a video */
    EXTERIA_UPLOAD_FILE             /* anything else, sent as a document with its name */
} exteria_upload_kind;

#define EXTERIA_UPLOAD_NAME_MAX 128
#define EXTERIA_UPLOAD_CAPTION_MAX 4096

/* what a message about an uploaded file needs beyond the file itself */
typedef struct exteria_upload_spec {
    exteria_upload_kind kind;
    int32_t reply_to;
    int32_t duration_ms;
    int32_t width;                  /* a round video's side is the width */
    int32_t height;
    const uint8_t *waveform;
    size_t waveform_len;
    char caption[EXTERIA_UPLOAD_CAPTION_MAX + 1];
    char name[EXTERIA_UPLOAD_NAME_MAX];
    char mime[EXTERIA_MEDIA_MIME_MAX];
    uint8_t spoiler;                /* a photo or a video that is shown blurred until it is tapped */
    uint8_t view_once;              /* a photo, video, voice note or round video that is gone after the other side has opened it; files and albums cannot be */
} exteria_upload_spec;

/* messages.sendMedia for a file already uploaded: file is the inputFile or inputFileBig the upload gave */
exteria_status exteria_send_upload_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value *file,
                                           const exteria_upload_spec *spec, int64_t random_id, exteria_tl_value **out);
/* messages.sendMedia with a point on the map; EXTERIA_E_ARG outside the valid latitudes and longitudes */
exteria_status exteria_send_geo_request(exteria_arena *arena, const exteria_peer_ref *peer, double latitude, double longitude,
                                        int64_t random_id, exteria_tl_value **out);
exteria_status exteria_send_location_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_geo_point *location,
                                            int64_t random_id, exteria_tl_value **out);
#define EXTERIA_CUSTOM_EMOJI_MAX 100

/* a custom emoji by the document that draws it, and the ordinary emoji it stands for */
typedef struct exteria_custom_emoji {
    int64_t id;
    char alt[EXTERIA_MEDIA_ALT_MAX];
    exteria_sticker_format format;  /* static webp, gzip lottie, or webm of which only the preview can be drawn */
    exteria_media_ref ref;          /* the file; source none when the document cannot be fetched */
    exteria_media_ref preview;      /* the thumbnail, the only picture of a webm emoji */
} exteria_custom_emoji;

/* messages.getCustomEmojiDocuments for 1 to EXTERIA_CUSTOM_EMOJI_MAX documents */
exteria_status exteria_custom_emoji_request(exteria_arena *arena, const int64_t *ids, size_t count, exteria_tl_value **out);
/* the answer to it: one row per document that carries the custom emoji attribute with a text, in answer order */
exteria_status exteria_custom_emoji_parse(const exteria_tl_value *answer, exteria_custom_emoji *rows, size_t cap, size_t *count);
/* messages.getEmojiStickers and its answer; only sets of custom emoji are kept, a set that is archived is left out */
exteria_status exteria_emoji_sets_request(exteria_arena *arena, exteria_tl_value **out);
exteria_status exteria_emoji_sets_parse(const exteria_tl_value *answer, exteria_sticker_set_row *sets, size_t cap, size_t *count);
/* a messages.stickerSet answer of a custom emoji set: the header and one row per emoji, in set order */
exteria_status exteria_emoji_set_parse(const exteria_tl_value *answer, exteria_sticker_set_row *set, exteria_custom_emoji *rows,
                                       size_t cap, size_t *count);
/* messages.searchGlobal for the text in every chat; kind narrows it to posts or to one kind of attachment. offset_rate is
   zero for the first page and next_rate of the previous one for the next */
exteria_status exteria_search_request(exteria_arena *arena, const char *query, exteria_search_kind kind, int32_t offset_rate,
                                      int32_t limit, exteria_tl_value **out);
/* messages.readHistory, channels.readHistory for a channel, or messages.readDiscussion for a peer narrowed to a topic */
exteria_status exteria_read_history_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t max_id,
                                           exteria_tl_value **out);
/* the InputFileLocation of a ref, and of the thumbnail of a sticker set */
exteria_status exteria_media_location(exteria_arena *arena, const exteria_media_ref *ref, exteria_tl_value **out);
exteria_status exteria_sticker_set_thumb_location(exteria_arena *arena, const exteria_sticker_set_row *set, exteria_tl_value **out);
exteria_status exteria_sticker_set_request(exteria_arena *arena, const exteria_sticker_set_row *set, exteria_tl_value **out);

#endif
