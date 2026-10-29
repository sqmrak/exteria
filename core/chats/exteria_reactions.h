#ifndef EXTERIA_REACTIONS_H
#define EXTERIA_REACTIONS_H

#include "exteria_tl.h"

#define EXTERIA_REACTIONS_MAX 64
#define EXTERIA_REACTION_EMOJI_MAX 32
#define EXTERIA_REACTION_CATALOG_MAX 128
#define EXTERIA_REACTION_PEOPLE_PAGE 50
#define EXTERIA_REACTION_OFFSET_MAX 256
/* the people a chip names with their pictures instead of a number: a message with this few reactions is small enough for the
   server's recent list to hold every reactor */
#define EXTERIA_REACTORS_MAX 3

typedef enum exteria_reaction_kind {
    EXTERIA_REACTION_EMOJI = 1,
    EXTERIA_REACTION_CUSTOM,
    EXTERIA_REACTION_PAID
} exteria_reaction_kind;

typedef struct exteria_reaction {
    uint8_t kind;
    uint8_t chosen;
    int32_t chosen_order;
    int32_t count;
    int64_t document_id;
    char emoji[EXTERIA_REACTION_EMOJI_MAX];
    /* users the recent list of the message names for this reaction, in list order; empty when the answer carried no list or none
       of its entries is a user */
    uint8_t reactor_count;
    int64_t reactors[EXTERIA_REACTORS_MAX];
} exteria_reaction;

typedef struct exteria_reactions {
    uint8_t count;
    uint8_t min;
    exteria_reaction items[EXTERIA_REACTIONS_MAX];
} exteria_reactions;

/* what a chip shows beside its emoji: the number of people, or their pictures while they are few */
typedef enum exteria_faces {
    EXTERIA_FACES_NONE = 0,         /* the number */
    EXTERIA_FACES_SELF_AND_OTHER,   /* private chat, both sides chose it */
    EXTERIA_FACES_SELF,             /* private chat, only we did */
    EXTERIA_FACES_OTHER,            /* private chat, only the other side did */
    EXTERIA_FACES_REACTORS          /* the people of exteria_reaction.reactors */
} exteria_faces;

/* the faces of the chip at index of a message's reactions; a private chat has two possible reactors, so who chose
   is known from the count and the chosen flag alone */
exteria_faces exteria_reaction_faces(const exteria_reactions *all, size_t index, int private_chat);

struct exteria_peer_ref;

typedef struct exteria_reaction_person {
    int32_t peer_kind;
    int64_t peer_id;
    int32_t date;
    exteria_reaction reaction;
} exteria_reaction_person;

exteria_status exteria_reaction_people_request(exteria_arena *arena, const struct exteria_peer_ref *peer, int32_t message_id,
                                               const char *offset, exteria_tl_value **out);
exteria_status exteria_reaction_people_parse(const exteria_tl_value *answer, exteria_reaction_person *rows, size_t capacity,
                                             size_t *count, char *next, size_t next_capacity);

/* absent reactions are an empty set, malformed or oversized sets leave out empty */
exteria_status exteria_reactions_read(const exteria_tl_value *value, exteria_reactions *out);
int exteria_reaction_equal(const exteria_reaction *a, const exteria_reaction *b);
/* the catalog contains active ordinary emoji, custom and paid reactions have separate APIs */
exteria_status exteria_reaction_catalog_read(const exteria_tl_value *answer, exteria_reaction *items,
                                             size_t cap, size_t *count);
exteria_status exteria_reaction_policy_read(const exteria_tl_value *answer, exteria_reactions *allowed, int *all);
/* whether a chatFull answer lets everyone use any custom emoji as a reaction (chatReactionsAll with allow_custom) */
int exteria_reaction_policy_custom(const exteria_tl_value *answer);
/* messages.getTopReactions or, when recent is set, messages.getRecentReactions for at most limit reactions */
exteria_status exteria_reaction_list_request(exteria_arena *arena, int recent, int32_t limit, exteria_tl_value **out);
/* the custom emoji among the reactions of a messages.reactions answer, in answer order; ordinary and paid
   reactions are left out, and so is one that is malformed. messages.reactionsNotModified is EXTERIA_E_NOTFOUND */
exteria_status exteria_reaction_list_read(const exteria_tl_value *answer, exteria_reaction *items, size_t cap, size_t *count);
/* one Reaction object; reactionEmpty and unknown constructors are EXTERIA_E_MALFORMED */
exteria_status exteria_reaction_parse(const exteria_tl_value *value, exteria_reaction *out);
/* the Reaction object of a choice, built in arena */
exteria_status exteria_reaction_build(exteria_arena *arena, const exteria_reaction *r, exteria_tl_value **out);
exteria_status exteria_send_reactions_request(exteria_arena *arena, const struct exteria_peer_ref *peer,
                                              int32_t id, const exteria_reaction *items, size_t count,
                                              exteria_tl_value **out);
exteria_status exteria_get_reactions_request(exteria_arena *arena, const struct exteria_peer_ref *peer,
                                             const int32_t *ids, size_t count, exteria_tl_value **out);

/* the matching reaction update in a refresh answer, EXTERIA_E_NOTFOUND when none was returned */
exteria_status exteria_reaction_update_read(const exteria_tl_value *updates, int32_t peer_kind, int64_t peer_id,
                                            int32_t message_id, exteria_reactions *out);

/* a min update carries counts but omits our selection, so matching chosen_order fields survive */
exteria_status exteria_reactions_merge_min(exteria_tl_value *incoming, const exteria_tl_value *previous);

#endif
