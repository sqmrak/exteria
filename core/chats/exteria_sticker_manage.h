#ifndef EXTERIA_STICKER_MANAGE_H
#define EXTERIA_STICKER_MANAGE_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_tl.h"

/* keeping the installed sticker sets of the account in order, for the Stickers and Emoji screen: taking one away
   and putting them in another order */

#define EXTERIA_STICKER_ORDER_MAX 400

/* messages.installStickerSet for the set with this id and access hash, not archived; the id must be positive */
exteria_status exteria_sticker_install_request(exteria_arena *arena, int64_t id, int64_t access_hash, exteria_tl_value **out);
exteria_status exteria_sticker_install_parse(const exteria_tl_value *answer);
/* messages.uninstallStickerSet for the set with this id and access hash; the id must be positive */
exteria_status exteria_sticker_uninstall_request(exteria_arena *arena, int64_t id, int64_t access_hash, exteria_tl_value **out);
/* messages.reorderStickerSets: the ids of the sets of the account in the new order */
exteria_status exteria_sticker_reorder_request(exteria_arena *arena, const int64_t *ids, size_t count, exteria_tl_value **out);
/* the Bool either call answers: EXTERIA_OK for true, EXTERIA_E_STATE for false, EXTERIA_E_MALFORMED otherwise */
exteria_status exteria_sticker_manage_parse(const exteria_tl_value *answer);

#endif
