#ifndef EXTERIA_REACTION_ART_H
#define EXTERIA_REACTION_ART_H

#include "exteria_messages.h"
#include "exteria_reactions.h"

/* the pictures the server draws a reaction with, from messages.getAvailableReactions. icon is the still one (static_icon), the others are lottie: appear
   (the reaction pop up of the picker), select (its press), activate (the reaction flying to the message), effect (the large burst beside it) and around (the
   short burst of a double tap). a document the answer leaves out is zeroed, its id is 0 */
typedef struct exteria_reaction_art {
    char emoji[EXTERIA_REACTION_EMOJI_MAX];
    exteria_custom_emoji icon;
    exteria_custom_emoji appear;
    exteria_custom_emoji select;
    exteria_custom_emoji activate;
    exteria_custom_emoji effect;
    exteria_custom_emoji around;
} exteria_reaction_art;
/* every reaction of the answer, active or not, since an old message still shows a reaction the server has retired. a row without the emoji, or whose icon, appear, select,
   activate or effect document is missing, is EXTERIA_E_MALFORMED */
exteria_status exteria_reaction_art_read(const exteria_tl_value *answer, exteria_reaction_art *items, size_t cap, size_t *count);
#endif
