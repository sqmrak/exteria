#ifndef EXTERIA_GIFTS_H
#define EXTERIA_GIFTS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_gift.h"
#include "exteria_messages.h"
#include "exteria_tl.h"

#define EXTERIA_GIFTS_MAX 300
#define EXTERIA_SAVED_GIFTS_MAX 50
#define EXTERIA_GIFT_NOTE_MAX 256
#define EXTERIA_GIFT_OFFSET_MAX 64

/* the fallback until the server's app configuration arrives */
#define EXTERIA_GIFT_CONVERT_PERIOD_DEFAULT (7 * 86400)
exteria_status exteria_gift_convert_period_parse(const exteria_tl_value *answer, int32_t *seconds);

/* a gift on a profile: what was received, from whom, and what can be done with it */
typedef struct exteria_saved_gift {
    exteria_gift gift;
    int64_t from_id;            /* zero when the sender hid their name */
    exteria_person_row from_person; /* the sender as the answer carries them, id zero when the name is hidden or the user is missing */
    int32_t date;
    int32_t msg_id;             /* names the gift to the server on the profile of a user */
    uint8_t name_hidden;
    uint8_t unsaved;            /* hidden from the profile */
    uint8_t can_upgrade;
    uint8_t pinned;
    uint8_t refunded;
    int64_t convert_stars;
    int64_t upgrade_stars;      /* what the upgrade costs the receiver, zero when it was prepaid or is not offered */
    int64_t transfer_stars;     /* what handing a unique gift to someone costs, zero when free */
    int32_t can_transfer_at;    /* unix time from which a unique gift can be handed on */
    char from_name[EXTERIA_PERSON_NAME_MAX];
    char note[EXTERIA_GIFT_NOTE_MAX];
    exteria_entity note_entities[EXTERIA_MESSAGE_ENTITIES_MAX];
    uint8_t note_entity_count;
    char note_urls[EXTERIA_MESSAGE_URLS_MAX];
} exteria_saved_gift;

int exteria_gift_can_convert(const exteria_saved_gift *gift, int64_t now, int32_t period);

typedef struct exteria_saved_gift_page {
    int32_t total;
    char next_offset[EXTERIA_GIFT_OFFSET_MAX];  /* empty on the last page */
} exteria_saved_gift_page;

/* a folder of the gifts on a profile, as the server keeps them: the gifts of a user or a channel are shown by folder, "all gifts" being no folder at all */
#define EXTERIA_GIFT_COLLECTIONS_MAX 100
#define EXTERIA_GIFT_COLLECTION_TITLE_MAX 64
/* the most gifts one request adds to or takes from a folder */
#define EXTERIA_GIFT_COLLECTION_BATCH_MAX 50
typedef struct exteria_gift_collection {
    int32_t id;
    int32_t count;              /* how many gifts it holds */
    char title[EXTERIA_GIFT_COLLECTION_TITLE_MAX];
} exteria_gift_collection;

/* one starGiftCollection, the answer of a create or an update; anything else is EXTERIA_E_MALFORMED */
exteria_status exteria_gift_collection_read(const exteria_tl_value *value, exteria_gift_collection *out);
/* a payments.starGiftCollections answer in server order; a folder that cannot be read is skipped. starGiftCollectionsNotModified is EXTERIA_E_NOTFOUND */
exteria_status exteria_gift_collections_parse(const exteria_tl_value *answer, exteria_gift_collection *rows, size_t cap, size_t *count);

/* a payments.starGifts answer in server order, the gifts that cannot be sold any more last; starGiftsNotModified is
   EXTERIA_E_NOTFOUND. hash is what the next request sends to skip an unchanged catalog */
exteria_status exteria_gifts_parse(const exteria_tl_value *answer, exteria_gift *gifts, size_t cap, size_t *count, int32_t *hash);

/* a payments.savedStarGifts answer in server order; a gift that cannot be read is skipped */
exteria_status exteria_saved_gifts_parse(const exteria_tl_value *answer, exteria_saved_gift *rows, size_t cap, size_t *count,
                                         exteria_saved_gift_page *page);

/* the stars of a payments.starsStatus answer; an amount in toncoin is EXTERIA_E_UNSUPPORTED */
exteria_status exteria_stars_balance_parse(const exteria_tl_value *answer, int64_t *stars);

/* the form and total of a paymentFormStarGift answer; any other form is EXTERIA_E_UNSUPPORTED, this client pays in
   stars only */
exteria_status exteria_payment_form_parse(const exteria_tl_value *answer, int64_t *form_id, int64_t *stars);

/* a payments.paymentResult; a result that asks for a web verification is EXTERIA_E_UNSUPPORTED */
exteria_status exteria_payment_result_check(const exteria_tl_value *answer);

/* requests, built in arena. limit is 1 to EXTERIA_SAVED_GIFTS_MAX and offset is "" for the first page */
exteria_status exteria_gifts_request(exteria_arena *arena, int32_t hash, exteria_tl_value **out);
exteria_status exteria_saved_gifts_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *offset, int32_t limit,
                                           exteria_tl_value **out);
exteria_status exteria_stars_balance_request(exteria_arena *arena, exteria_tl_value **out);
/* the gifts of one folder: the request above with collection_id; the id must be positive */
exteria_status exteria_saved_gifts_in_collection_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t collection_id, const char *offset,
                                                         int32_t limit, exteria_tl_value **out);
/* the folders of a profile, and the changes the owner of the profile makes to them */
exteria_status exteria_gift_collections_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out);
exteria_status exteria_gift_collection_create_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *title, const int32_t *msg_ids,
                                                      size_t count, exteria_tl_value **out);
/* a nil title keeps the name; adds and removes may be empty but not both, and the title may change alone */
exteria_status exteria_gift_collection_update_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t collection_id, const char *title,
                                                      const int32_t *add, size_t add_count, const int32_t *remove, size_t remove_count,
                                                      exteria_tl_value **out);
exteria_status exteria_gift_collection_delete_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t collection_id, exteria_tl_value **out);

/* the three invoices of a gift: buying one for a user, upgrading a received one, handing one on */
exteria_status exteria_gift_invoice_send(exteria_arena *arena, const exteria_peer_ref *peer, int64_t gift_id, const char *note,
                                         int hide_name, int include_upgrade, exteria_tl_value **out);
exteria_status exteria_gift_invoice_upgrade(exteria_arena *arena, int32_t msg_id, int keep_details, exteria_tl_value **out);
exteria_status exteria_gift_invoice_transfer(exteria_arena *arena, int32_t msg_id, const exteria_peer_ref *to, exteria_tl_value **out);
/* payments.getPaymentForm and payments.sendStarsForm for an invoice made above */
exteria_status exteria_payment_form_request(exteria_arena *arena, exteria_tl_value *invoice, exteria_tl_value **out);
exteria_status exteria_payment_send_request(exteria_arena *arena, int64_t form_id, exteria_tl_value *invoice, exteria_tl_value **out);

/* what the receiver of a gift can do without paying */
exteria_status exteria_gift_save_request(exteria_arena *arena, int32_t msg_id, int unsave, exteria_tl_value **out);
exteria_status exteria_gift_convert_request(exteria_arena *arena, int32_t msg_id, exteria_tl_value **out);
/* free upgrade of a gift whose upgrade was prepaid, and the free transfer of a unique one */
exteria_status exteria_gift_upgrade_request(exteria_arena *arena, int32_t msg_id, int keep_details, exteria_tl_value **out);
exteria_status exteria_gift_transfer_request(exteria_arena *arena, int32_t msg_id, const exteria_peer_ref *to, exteria_tl_value **out);
exteria_status exteria_gift_pin_request(exteria_arena *arena, const int32_t *msg_ids, size_t count, exteria_tl_value **out);

#endif
