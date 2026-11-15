#ifndef EXTERIA_EFFECTS_H
#define EXTERIA_EFFECTS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_tl.h"

/* the animated effects a message of a private chat can be sent with (messages.getAvailableEffects): the server names each by the emoji that stands for it */
#define EXTERIA_EFFECTS_MAX 64
#define EXTERIA_EFFECT_EMOTICON_MAX 32

typedef struct exteria_effect {
    int64_t id;
    char emoticon[EXTERIA_EFFECT_EMOTICON_MAX];
    uint8_t premium;             /* the effect needs Telegram Premium */
    int64_t sticker_id;          /* the sticker that shows the effect in a list, 0 when it has none */
    int64_t animation_id;        /* the full screen animation, 0 when it has none */
    exteria_custom_emoji animation; /* the document of the animation, id 0 when the answer does not carry it */
    exteria_custom_emoji sticker;   /* the document of the sticker of the effect, which plays when there is no animation */
} exteria_effect;

exteria_status exteria_effects_request(exteria_arena *arena, exteria_tl_value **out);
/* the documents of the answer are matched to the ids, so a row says where to fetch the picture of its effect from.
   the effects of an answer, at most cap of them, in the order the server gave; an effect with no id or no emoji is left out. EXTERIA_E_MALFORMED for an answer of another kind */
exteria_status exteria_effects_parse(const exteria_tl_value *answer, exteria_effect *rows, size_t cap, size_t *count);
/* the effect a sendMessage request goes with */
exteria_status exteria_set_effect(exteria_arena *arena, exteria_tl_value *request, int64_t effect);

#endif
