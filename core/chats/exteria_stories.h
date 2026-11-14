#ifndef EXTERIA_STORIES_H
#define EXTERIA_STORIES_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_messages.h"
#include "exteria_reactions.h"
#include "exteria_tl.h"

#define EXTERIA_STORY_PEERS_MAX 200
#define EXTERIA_STORIES_MAX 100
#define EXTERIA_STORY_CAPTION_MAX 1024

typedef struct exteria_story_row {
    int32_t id;
    int32_t date;
    int32_t expire_date;
    int32_t views;
    int32_t reactions;      /* how many reactions the story has gathered, 0 when the server gave none */
    uint8_t skipped;        /* the server sent only the header, getStoriesByID gives the content */
    uint8_t pinned;
    uint8_t close_friends;
    uint8_t out;
    uint8_t edited;
    uint8_t noforwards;
    uint8_t contacts;       /* shown to contacts only */
    uint8_t selected;       /* shown to a chosen list of people, which this client can keep but not build */
    uint8_t reacted;        /* our reaction is in reaction */
    exteria_reaction reaction;
    exteria_media_info media;
    exteria_media_info music;   /* the track that plays with the story, a source of none when it has no music */
    char caption[EXTERIA_STORY_CAPTION_MAX];
} exteria_story_row;

/* one ring of the story strip: who posted, and how much of it is still unseen */
typedef struct exteria_story_peer {
    exteria_dialog_row owner;   /* peer_kind, peer_id, title, photo and access hash of the poster */
    int32_t max_read_id;        /* stories up to this id are seen */
    int32_t count;              /* stories alive now */
    int32_t unread;             /* of them, the ones past max_read_id */
    int32_t newest_date;
    int32_t first_unread_id;    /* zero when everything is seen */
    uint8_t close_friends;      /* an unseen story is for close friends only, which gives the ring its green */
} exteria_story_peer;

/* a StoryItem; storyItemDeleted is EXTERIA_E_NOTFOUND, a skipped item has only id and dates, anything else is
   EXTERIA_E_MALFORMED. out is always initialised */
exteria_status exteria_story_read(const exteria_tl_value *item, exteria_story_row *out);

/* a stories.allStories answer in server order (own stories, unseen posters, then seen ones); allStoriesNotModified
   is EXTERIA_E_NOTFOUND. more is set when the server has another page */
exteria_status exteria_story_peers_parse(const exteria_tl_value *answer, int64_t self_id, exteria_story_peer *peers,
                                         size_t cap, size_t *count, int *more);

/* a stories.peerStories answer: the poster and their live stories, oldest first as the server keeps them */
exteria_status exteria_story_peer_parse(const exteria_tl_value *answer, int64_t self_id, exteria_story_peer *peer,
                                        exteria_story_row *rows, size_t cap, size_t *count);

/* a stories.stories answer in server order; deleted items are dropped */
exteria_status exteria_stories_parse(const exteria_tl_value *answer, exteria_story_row *rows, size_t cap, size_t *count);

/* requests, built in arena; a peer that cannot be named or an empty id list is EXTERIA_E_ARG */
exteria_status exteria_story_all_request(exteria_arena *arena, int next, exteria_tl_value **out);
exteria_status exteria_story_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out);
exteria_status exteria_story_ids_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                         exteria_tl_value **out);
exteria_status exteria_story_read_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t max_id, exteria_tl_value **out);
exteria_status exteria_story_views_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                           exteria_tl_value **out);
/* the pinned stories of a poster, and the archive of our own expired ones, a page of up to limit before offset_id (zero for
   the newest); the answer is a stories.stories */
exteria_status exteria_story_pinned_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t limit,
                                            exteria_tl_value **out);
exteria_status exteria_story_archive_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t offset_id, int32_t limit,
                                             exteria_tl_value **out);
/* a null reaction takes ours back */
exteria_status exteria_story_react_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id,
                                           const exteria_reaction *reaction, exteria_tl_value **out);
/* stories.sendStory of a photo already uploaded as file (an InputFile), to the signed in user's own stories: shown to everyone for a day,
   no caption. random_id must not be zero */
#define EXTERIA_STORY_PERIOD 86400
exteria_status exteria_story_send_photo_request(exteria_arena *arena, exteria_tl_value *file, int64_t random_id, exteria_tl_value **out);
/* who sees a story we publish or edit */
typedef enum exteria_story_privacy {
    EXTERIA_STORY_EVERYONE = 0,
    EXTERIA_STORY_CONTACTS,
    EXTERIA_STORY_CLOSE_FRIENDS,
    /* a list of chosen people and nobody else; only an audience (below) can name them */
    EXTERIA_STORY_SELECTED
} exteria_story_privacy;
/* who sees a story, with the people the choice names: the chosen ones of SELECTED, or the ones left out of EVERYONE and CONTACTS */
#define EXTERIA_STORY_USERS_MAX 200
typedef struct exteria_story_user {
    int64_t id;
    int64_t access_hash;
} exteria_story_user;
typedef struct exteria_story_audience {
    exteria_story_privacy base;
    uint16_t allow_count;
    uint16_t deny_count;
    exteria_story_user allow[EXTERIA_STORY_USERS_MAX];
    exteria_story_user deny[EXTERIA_STORY_USERS_MAX];
} exteria_story_audience;
#define EXTERIA_STORY_CAPTION_SEND_MAX 200
/* the audience of a story row we read */
exteria_story_privacy exteria_story_row_privacy(const exteria_story_row *row);
/* stories.sendStory of an uploaded photo with a caption (NULL or empty for none, at most EXTERIA_STORY_CAPTION_SEND_MAX bytes) and an audience */
exteria_status exteria_story_publish_photo_request(exteria_arena *arena, exteria_tl_value *file, int64_t random_id, const char *caption,
                                                   exteria_story_privacy privacy, exteria_tl_value **out);
/* the same two calls for an audience that may name people */
exteria_status exteria_story_publish_photo_audience_request(exteria_arena *arena, exteria_tl_value *file, int64_t random_id, const char *caption,
                                                            const exteria_story_audience *audience, exteria_tl_value **out);
exteria_status exteria_story_edit_audience_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *caption, int set_audience,
                                                   const exteria_story_audience *audience, exteria_tl_value **out);
/* stories.exportStoryLink of one story of a user or channel, and the address in the exportedStoryLink it answers (capacity cap, at most 255 bytes kept) */
exteria_status exteria_story_link_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, exteria_tl_value **out);
exteria_status exteria_story_link_parse(const exteria_tl_value *answer, char *link, size_t cap);
/* stories.togglePeerStoriesHidden: the stories of a user or channel leave the strip for the archive section (hidden) or come back to it */
exteria_status exteria_story_hide_peer_request(exteria_arena *arena, const exteria_peer_ref *peer, int hidden, exteria_tl_value **out);
/* stories.editStory of one of our stories: a NULL caption leaves the text alone, an empty one takes it off; set_privacy 0 leaves the audience alone */
exteria_status exteria_story_edit_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t id, const char *caption, int set_privacy,
                                          exteria_story_privacy privacy, exteria_tl_value **out);
/* who looked at one of our stories: a page of the answer to stories.getStoryViewsList, newest first; the offset of the next page is empty at the end */
#define EXTERIA_STORY_VIEWERS_PAGE 50
#define EXTERIA_STORY_VIEWERS_OFFSET_MAX 256
typedef struct exteria_story_viewer {
    int64_t user_id;
    int32_t date;
    uint8_t blocked;    /* they cannot see our stories */
    uint8_t reacted;    /* they reacted, and the reaction is in reaction */
    exteria_reaction reaction;
} exteria_story_viewer;
exteria_status exteria_story_viewers_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t story_id, const char *offset, exteria_tl_value **out);
/* the viewers in rows (a viewer that is a forward or a repost of the story carries no user and is left out), the next offset in next, the whole number of views in total
   and the whole number of reactions in reactions (either may be NULL) */
exteria_status exteria_story_viewers_parse(const exteria_tl_value *answer, exteria_story_viewer *rows, size_t capacity, size_t *count, char *next, size_t next_capacity,
                                           int32_t *total, int32_t *reactions);
exteria_status exteria_story_delete_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count,
                                            exteria_tl_value **out);
/* pinned keeps the story on the profile after it expires, unpinned leaves it only in the archive */
exteria_status exteria_story_pin_request(exteria_arena *arena, const exteria_peer_ref *peer, const int32_t *ids, size_t count, int pinned,
                                         exteria_tl_value **out);
/* messages.sendMessage as a reply to a story of the chat's user */
exteria_status exteria_story_reply_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t story_id, const char *text,
                                           int64_t random_id, exteria_tl_value **out);
/* messages.sendMedia of an inputMediaStory: the story of owner sent into the chat target, as a message that opens the story. owner may be the account itself;
   a target that is a basic group or user needs no more than its id, a topic of a forum is answered the way a text is */
exteria_status exteria_story_forward_request(exteria_arena *arena, const exteria_peer_ref *target, const exteria_peer_ref *owner, int32_t story_id,
                                             int64_t random_id, exteria_tl_value **out);

#endif
