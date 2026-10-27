#include "exteria_gifts.h"

#include <string.h>
#include <math.h>

#include "exteria_store.h"
#include "exteria_tl_ids.h"

exteria_status exteria_gift_convert_period_parse(const exteria_tl_value *answer, int32_t *seconds) {
    const exteria_tl_value *config, *entries;
    static const char key[] = "stargifts_convert_period_max";
    if (seconds) *seconds = 0;
    if (!seconds || !exteria_tl_is(answer, EXTERIA_TL_ID_help_appConfig)) return EXTERIA_E_MALFORMED;
    config = exteria_tl_get(answer, "config");
    if (!exteria_tl_is(config, EXTERIA_TL_ID_jsonObject) || exteria_tl_get_vec(config, "value", &entries) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    for (uint32_t i = 0; i < entries->u.vec.count; ++i) {
        const exteria_tl_value *entry = entries->u.vec.items[i], *value;
        const uint8_t *name;
        size_t len;
        double number;
        if (!exteria_tl_is(entry, EXTERIA_TL_ID_jsonObjectValue) || exteria_tl_get_bytes(entry, "key", &name, &len) != EXTERIA_OK ||
            len != sizeof(key) - 1 || !name || memcmp(name, key, len)) continue;
        value = exteria_tl_get(entry, "value");
        if (!exteria_tl_is(value, EXTERIA_TL_ID_jsonNumber) || exteria_tl_get_f64(value, "value", &number) != EXTERIA_OK ||
            !isfinite(number) || number < 0 || number > INT32_MAX || floor(number) != number) return EXTERIA_E_MALFORMED;
        *seconds = (int32_t)number;
        return EXTERIA_OK;
    }
    return EXTERIA_E_NOTFOUND;
}

int exteria_gift_can_convert(const exteria_saved_gift *gift, int64_t now, int32_t period) {
    return gift && !gift->gift.unique && !gift->gift.auction && !gift->refunded && gift->convert_stars > 0 &&
           gift->date > 0 && period > 0 && now >= gift->date && now - gift->date < period;
}

static exteria_status stars_of(const exteria_tl_value *amount, int64_t *stars) {
    if (exteria_tl_is(amount, EXTERIA_TL_ID_starsTonAmount)) return EXTERIA_E_UNSUPPORTED;
    if (!exteria_tl_is(amount, EXTERIA_TL_ID_starsAmount) || exteria_tl_get_i64(amount, "amount", stars) != EXTERIA_OK ||
        *stars < 0) return EXTERIA_E_MALFORMED;
    return EXTERIA_OK;
}

exteria_status exteria_gifts_parse(const exteria_tl_value *answer, exteria_gift *gifts, size_t cap, size_t *count, int32_t *hash) {
    const exteria_tl_value *list;
    uint32_t i;
    size_t n = 0, pass;
    if (count) *count = 0;
    if (hash) *hash = 0;
    if (!gifts || !count || !cap) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_payments_starGiftsNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_payments_starGifts) || exteria_tl_get_vec(answer, "gifts", &list) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    if (list->u.vec.count > EXTERIA_GIFTS_MAX * 2) return EXTERIA_E_LIMIT;
    if (hash) exteria_tl_get_i32(answer, "hash", hash);
    /* the gifts that can still be bought come first, then the sold out ones, each group in server order */
    for (pass = 0; pass < 2; ++pass) {
        for (i = 0; i < list->u.vec.count && n < cap; ++i) {
            exteria_gift gift;
            if (exteria_gift_read(list->u.vec.items[i], &gift) != EXTERIA_OK || gift.unique) continue;
            if ((gift.sold_out || gift.auction) != (pass == 1)) continue;
            gifts[n++] = gift;
        }
    }
    *count = n;
    return EXTERIA_OK;
}

static const exteria_tl_value *find_user(const exteria_tl_value *users, int64_t id) {
    uint32_t i;
    for (i = 0; users && i < users->u.vec.count; ++i) {
        int64_t user_id;
        if (exteria_tl_get_i64(users->u.vec.items[i], "id", &user_id) == EXTERIA_OK && user_id == id) return users->u.vec.items[i];
    }
    return NULL;
}

static void copy_note(char *dst, size_t cap, const exteria_tl_value *text) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (!text || exteria_tl_get_bytes(text, "text", &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static exteria_status read_saved(const exteria_tl_value *item, const exteria_tl_value *users, exteria_saved_gift *out) {
    exteria_peer from;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(item, EXTERIA_TL_ID_savedStarGift) || exteria_tl_get_i32(item, "date", &out->date) != EXTERIA_OK ||
        exteria_gift_read(exteria_tl_get(item, "gift"), &out->gift) != EXTERIA_OK) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    out->name_hidden = exteria_tl_has(item, "name_hidden") ? 1 : 0;
    out->unsaved = exteria_tl_has(item, "unsaved") ? 1 : 0;
    out->can_upgrade = exteria_tl_has(item, "can_upgrade") ? 1 : 0;
    out->pinned = exteria_tl_has(item, "pinned_to_top") ? 1 : 0;
    out->refunded = exteria_tl_has(item, "refunded") ? 1 : 0;
    exteria_tl_get_i32(item, "msg_id", &out->msg_id);
    exteria_tl_get_i64(item, "convert_stars", &out->convert_stars);
    exteria_tl_get_i64(item, "upgrade_stars", &out->upgrade_stars);
    exteria_tl_get_i64(item, "transfer_stars", &out->transfer_stars);
    exteria_tl_get_i32(item, "can_transfer_at", &out->can_transfer_at);
    copy_note(out->note, sizeof(out->note), exteria_tl_get(item, "message"));
    exteria_entities_read(exteria_tl_get(item, "message"), out->note_entities, EXTERIA_MESSAGE_ENTITIES_MAX,
                          out->note_urls, sizeof(out->note_urls), &out->note_entity_count);
    if (!out->name_hidden && exteria_peer_from_tl(exteria_tl_get(item, "from_id"), &from) == EXTERIA_OK && from.kind == 1) {
        exteria_person_row person;
        const exteria_tl_value *user = find_user(users, from.id);
        out->from_id = from.id;
        if (user && exteria_person_parse(user, &person) == EXTERIA_OK) {
            strncpy(out->from_name, person.name, sizeof(out->from_name) - 1);
            out->from_name[sizeof(out->from_name) - 1] = 0;
            out->from_person = person;
        }
    }
    return EXTERIA_OK;
}

exteria_status exteria_saved_gifts_parse(const exteria_tl_value *answer, exteria_saved_gift *rows, size_t cap, size_t *count,
                                         exteria_saved_gift_page *page) {
    const exteria_tl_value *list, *users;
    const uint8_t *offset;
    size_t offset_len, n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (page) memset(page, 0, sizeof(*page));
    if (!rows || !count || !page || !cap) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_payments_savedStarGifts) || exteria_tl_get_vec(answer, "gifts", &list) != EXTERIA_OK ||
        exteria_tl_get_vec(answer, "users", &users) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (list->u.vec.count > EXTERIA_SAVED_GIFTS_MAX) return EXTERIA_E_LIMIT;
    exteria_tl_get_i32(answer, "count", &page->total);
    if (exteria_tl_has(answer, "next_offset") && exteria_tl_get_bytes(answer, "next_offset", &offset, &offset_len) == EXTERIA_OK) {
        /* an offset that does not fit would restart the list at the wrong place, so the list ends here instead */
        if (offset_len > 0 && offset_len < sizeof(page->next_offset)) {
            memcpy(page->next_offset, offset, offset_len);
            page->next_offset[offset_len] = 0;
        }
    }
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        if (read_saved(list->u.vec.items[i], users, &rows[n]) == EXTERIA_OK) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_stars_balance_parse(const exteria_tl_value *answer, int64_t *stars) {
    if (stars) *stars = 0;
    if (!stars) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_payments_starsStatus)) return EXTERIA_E_MALFORMED;
    return stars_of(exteria_tl_get(answer, "balance"), stars);
}

exteria_status exteria_payment_form_parse(const exteria_tl_value *answer, int64_t *form_id, int64_t *stars) {
    const exteria_tl_value *invoice, *prices;
    uint32_t i;
    int64_t total = 0;
    if (form_id) *form_id = 0;
    if (stars) *stars = 0;
    if (!form_id || !stars) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_payments_paymentFormStarGift)) {
        return exteria_tl_is(answer, EXTERIA_TL_ID_payments_paymentForm) || exteria_tl_is(answer, EXTERIA_TL_ID_payments_paymentFormStars)
            ? EXTERIA_E_UNSUPPORTED : EXTERIA_E_MALFORMED;
    }
    invoice = exteria_tl_get(answer, "invoice");
    if (exteria_tl_get_i64(answer, "form_id", form_id) != EXTERIA_OK || !exteria_tl_is(invoice, EXTERIA_TL_ID_invoice) ||
        exteria_tl_get_vec(invoice, "prices", &prices) != EXTERIA_OK || prices->u.vec.count == 0 || prices->u.vec.count > 16)
        return EXTERIA_E_MALFORMED;
    for (i = 0; i < prices->u.vec.count; ++i) {
        int64_t amount;
        if (exteria_tl_get_i64(prices->u.vec.items[i], "amount", &amount) != EXTERIA_OK || amount < 0 || amount > INT64_MAX - total) {
            *form_id = 0;
            return EXTERIA_E_MALFORMED;
        }
        total += amount;
    }
    *stars = total;
    return EXTERIA_OK;
}

exteria_status exteria_payment_result_check(const exteria_tl_value *answer) {
    if (exteria_tl_is(answer, EXTERIA_TL_ID_payments_paymentResult)) return EXTERIA_OK;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_payments_paymentVerificationNeeded)) return EXTERIA_E_UNSUPPORTED;
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_gifts_request(exteria_arena *arena, int32_t hash, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "payments.getStarGifts");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "hash", hash);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_saved_gifts_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *offset, int32_t limit,
                                           exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !offset || strlen(offset) >= EXTERIA_GIFT_OFFSET_MAX || limit < 1 || limit > EXTERIA_SAVED_GIFTS_MAX) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "payments.getSavedStarGifts");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "offset", offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_saved_gifts_in_collection_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t collection_id, const char *offset,
                                                         int32_t limit, exteria_tl_value **out) {
    exteria_status status;
    if (out) *out = NULL;
    if (!out || collection_id <= 0) return EXTERIA_E_ARG;
    status = exteria_saved_gifts_request(arena, peer, offset, limit, out);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, *out, "collection_id", collection_id);
    if (status != EXTERIA_OK) *out = NULL;
    return status;
}

exteria_status exteria_gift_collection_read(const exteria_tl_value *value, exteria_gift_collection *out) {
    const uint8_t *title;
    size_t length;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(value, EXTERIA_TL_ID_starGiftCollection) || exteria_tl_get_i32(value, "collection_id", &out->id) != EXTERIA_OK || out->id <= 0 ||
        exteria_tl_get_bytes(value, "title", &title, &length) != EXTERIA_OK || !length) return EXTERIA_E_MALFORMED;
    exteria_tl_get_i32(value, "gifts_count", &out->count);
    if (out->count < 0) out->count = 0;
    /* a title the buffer cannot hold is cut at a character boundary */
    if (length >= sizeof(out->title)) {
        length = sizeof(out->title) - 1;
        while (length > 0 && (title[length] & 0xC0) == 0x80) --length;
    }
    memcpy(out->title, title, length);
    out->title[length] = 0;
    return length ? EXTERIA_OK : EXTERIA_E_MALFORMED;
}

exteria_status exteria_gift_collections_parse(const exteria_tl_value *answer, exteria_gift_collection *rows, size_t cap, size_t *count) {
    const exteria_tl_value *list;
    size_t n = 0;
    uint32_t i;
    if (count) *count = 0;
    if (!rows || !count || !cap) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_payments_starGiftCollectionsNotModified)) return EXTERIA_E_NOTFOUND;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_payments_starGiftCollections) || exteria_tl_get_vec(answer, "collections", &list) != EXTERIA_OK)
        return EXTERIA_E_MALFORMED;
    if (list->u.vec.count > EXTERIA_GIFT_COLLECTIONS_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < list->u.vec.count && n < cap; ++i) {
        if (exteria_gift_collection_read(list->u.vec.items[i], &rows[n]) == EXTERIA_OK) ++n;
    }
    *count = n;
    return EXTERIA_OK;
}

exteria_status exteria_gift_collections_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "payments.getStarGiftCollections");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* InputSavedStarGift of a gift on our own profile, which the server names by the id of its message */
static exteria_status saved_input(exteria_arena *arena, int32_t msg_id, exteria_tl_value **out);

static exteria_status saved_vector(exteria_arena *arena, const int32_t *ids, size_t count, exteria_tl_value **out) {
    exteria_tl_value *vec;
    size_t i;
    *out = NULL;
    if (!ids || count > EXTERIA_GIFT_COLLECTION_BATCH_MAX) return EXTERIA_E_ARG;
    vec = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!vec) return EXTERIA_E_NOMEM;
    for (i = 0; i < count; ++i) {
        exteria_tl_value *input;
        exteria_status status = saved_input(arena, ids[i], &input);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(vec, (uint32_t)i, input);
        if (status != EXTERIA_OK) return status;
    }
    *out = vec;
    return EXTERIA_OK;
}

static int title_ok(const char *title) {
    size_t length = title ? strlen(title) : 0;
    return length > 0 && length < EXTERIA_GIFT_COLLECTION_TITLE_MAX;
}

exteria_status exteria_gift_collection_create_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *title, const int32_t *msg_ids,
                                                      size_t count, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *gifts;
    exteria_status status;
    int32_t none = 0;
    if (out) *out = NULL;
    if (!arena || !out || !title_ok(title)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    status = saved_vector(arena, count ? msg_ids : &none, count, &gifts);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "payments.createStarGiftCollection");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "title", title);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stargift", gifts);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_gift_collection_update_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t collection_id, const char *title,
                                                      const int32_t *add, size_t add_count, const int32_t *remove, size_t remove_count,
                                                      exteria_tl_value **out) {
    exteria_tl_value *request, *input, *vec;
    exteria_status status;
    int32_t none = 0;
    if (out) *out = NULL;
    if (!arena || !out || collection_id <= 0 || (title && !title_ok(title)) || (!title && !add_count && !remove_count)) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "payments.updateStarGiftCollection");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "collection_id", collection_id);
    if (status == EXTERIA_OK && title) status = exteria_tl_set_str(arena, request, "title", title);
    if (status == EXTERIA_OK && add_count) {
        status = saved_vector(arena, add ? add : &none, add_count, &vec);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "add_stargift", vec);
    }
    if (status == EXTERIA_OK && remove_count) {
        status = saved_vector(arena, remove ? remove : &none, remove_count, &vec);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "delete_stargift", vec);
    }
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_gift_collection_delete_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t collection_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || collection_id <= 0) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "payments.deleteStarGiftCollection");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "collection_id", collection_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_stars_balance_request(exteria_arena *arena, exteria_tl_value **out) {
    exteria_tl_value *request, *self;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "payments.getStarsStatus");
    self = exteria_tl_new_obj(arena, "inputPeerSelf");
    if (!request || !self) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", self);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* InputSavedStarGift of a gift on our own profile, which the server names by the id of its message */
static exteria_status saved_input(exteria_arena *arena, int32_t msg_id, exteria_tl_value **out) {
    exteria_tl_value *input;
    exteria_status status;
    *out = NULL;
    if (!arena || msg_id <= 0) return EXTERIA_E_ARG;
    input = exteria_tl_new_obj(arena, "inputSavedStarGiftUser");
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, input, "msg_id", msg_id);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

exteria_status exteria_gift_invoice_send(exteria_arena *arena, const exteria_peer_ref *peer, int64_t gift_id, const char *note,
                                         int hide_name, int include_upgrade, exteria_tl_value **out) {
    exteria_tl_value *invoice, *input, *text;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || gift_id <= 0 || !note || strlen(note) >= EXTERIA_GIFT_NOTE_MAX) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    invoice = exteria_tl_new_obj(arena, "inputInvoiceStarGift");
    if (!invoice) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(invoice, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, invoice, "gift_id", gift_id);
    if (status == EXTERIA_OK && hide_name) status = exteria_tl_set_flag(invoice, "hide_name");
    if (status == EXTERIA_OK && include_upgrade) status = exteria_tl_set_flag(invoice, "include_upgrade");
    if (status == EXTERIA_OK && note[0]) {
        text = exteria_tl_new_obj(arena, "textWithEntities");
        if (!text) return EXTERIA_E_NOMEM;
        status = exteria_tl_set_str(arena, text, "text", note);
        if (status == EXTERIA_OK) status = exteria_tl_set(text, "entities", exteria_tl_new_vec(arena, 0));
        if (status == EXTERIA_OK) status = exteria_tl_set(invoice, "message", text);
    }
    if (status == EXTERIA_OK) *out = invoice;
    return status;
}

exteria_status exteria_gift_invoice_upgrade(exteria_arena *arena, int32_t msg_id, int keep_details, exteria_tl_value **out) {
    exteria_tl_value *invoice, *input;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = saved_input(arena, msg_id, &input);
    if (status != EXTERIA_OK) return status;
    invoice = exteria_tl_new_obj(arena, "inputInvoiceStarGiftUpgrade");
    if (!invoice) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(invoice, "stargift", input);
    if (status == EXTERIA_OK && keep_details) status = exteria_tl_set_flag(invoice, "keep_original_details");
    if (status == EXTERIA_OK) *out = invoice;
    return status;
}

exteria_status exteria_gift_invoice_transfer(exteria_arena *arena, int32_t msg_id, const exteria_peer_ref *to, exteria_tl_value **out) {
    exteria_tl_value *invoice, *input, *target;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = saved_input(arena, msg_id, &input);
    if (status == EXTERIA_OK) status = exteria_input_peer(arena, to, &target);
    if (status != EXTERIA_OK) return status;
    invoice = exteria_tl_new_obj(arena, "inputInvoiceStarGiftTransfer");
    if (!invoice) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(invoice, "stargift", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(invoice, "to_id", target);
    if (status == EXTERIA_OK) *out = invoice;
    return status;
}

exteria_status exteria_payment_form_request(exteria_arena *arena, exteria_tl_value *invoice, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !invoice) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "payments.getPaymentForm");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "invoice", invoice);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_payment_send_request(exteria_arena *arena, int64_t form_id, exteria_tl_value *invoice, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !invoice || form_id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "payments.sendStarsForm");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, request, "form_id", form_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "invoice", invoice);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* a request whose only argument is one of our received gifts */
static exteria_status saved_request(exteria_arena *arena, const char *name, int32_t msg_id, exteria_tl_value **request) {
    exteria_tl_value *input;
    exteria_status status = saved_input(arena, msg_id, &input);
    *request = NULL;
    if (status != EXTERIA_OK) return status;
    *request = exteria_tl_new_obj(arena, name);
    if (!*request) return EXTERIA_E_NOMEM;
    return exteria_tl_set(*request, "stargift", input);
}

exteria_status exteria_gift_save_request(exteria_arena *arena, int32_t msg_id, int unsave, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = saved_request(arena, "payments.saveStarGift", msg_id, &request);
    if (status == EXTERIA_OK && unsave) status = exteria_tl_set_flag(request, "unsave");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_gift_convert_request(exteria_arena *arena, int32_t msg_id, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = saved_request(arena, "payments.convertStarGift", msg_id, &request);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_gift_upgrade_request(exteria_arena *arena, int32_t msg_id, int keep_details, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = saved_request(arena, "payments.upgradeStarGift", msg_id, &request);
    if (status == EXTERIA_OK && keep_details) status = exteria_tl_set_flag(request, "keep_original_details");
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_gift_transfer_request(exteria_arena *arena, int32_t msg_id, const exteria_peer_ref *to, exteria_tl_value **out) {
    exteria_tl_value *request, *target;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    status = exteria_input_peer(arena, to, &target);
    if (status == EXTERIA_OK) status = saved_request(arena, "payments.transferStarGift", msg_id, &request);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "to_id", target);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_gift_pin_request(exteria_arena *arena, const int32_t *msg_ids, size_t count, exteria_tl_value **out) {
    exteria_tl_value *request, *self, *vec;
    exteria_status status = EXTERIA_OK;
    size_t i;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    /* the profile shows at most six pinned gifts */
    if (!arena || (count && !msg_ids) || count > 6) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "payments.toggleStarGiftsPinnedToTop");
    self = exteria_tl_new_obj(arena, "inputPeerSelf");
    vec = exteria_tl_new_vec(arena, (uint32_t)count);
    if (!request || !self || !vec) return EXTERIA_E_NOMEM;
    for (i = 0; status == EXTERIA_OK && i < count; ++i) {
        exteria_tl_value *input;
        status = saved_input(arena, msg_ids[i], &input);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(vec, (uint32_t)i, input);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", self);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "stargift", vec);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
