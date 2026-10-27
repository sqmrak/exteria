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
    uint8_t skipped;        /* the server sent only the header, getStoriesByID gives the content */
    uint8_t pinned;
    uint8_t close_friends;
    uint8_t out;
    uint8_t edited;
    uint8_t noforwards;
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
/* messages.sendMessage as a reply to a story of the chat's user */
exteria_status exteria_story_reply_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t story_id, const char *text,
                                           int64_t random_id, exteria_tl_value **out);

#endif
