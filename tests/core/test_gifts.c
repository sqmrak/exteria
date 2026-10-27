#include "test_util.h"
#include "exteria_gifts.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set(exteria_tl_value *v, const char *field, exteria_tl_value *x) {
    CHECK_EQ_INT(exteria_tl_set(v, field, x), EXTERIA_OK);
}
static void i32(exteria_tl_value *v, const char *field, int32_t x) {
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, field, x), EXTERIA_OK);
}
static void i64(exteria_tl_value *v, const char *field, int64_t x) {
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, field, x), EXTERIA_OK);
}
static void str(exteria_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, field, x), EXTERIA_OK);
}
static void flag(exteria_tl_value *v, const char *field) {
    CHECK_EQ_INT(exteria_tl_set_flag(v, field), EXTERIA_OK);
}
static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    return vec;
}
static exteria_tl_value *document(int64_t id, const char *mime) {
    exteria_tl_value *d = obj("document"), *attr = obj("documentAttributeSticker"), *list[1];
    i64(d, "id", id);
    i64(d, "access_hash", 5);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, d, "file_reference", "abc", 3), EXTERIA_OK);
    i32(d, "date", 1);
    str(d, "mime_type", mime);
    i64(d, "size", 4000);
    i32(d, "dc_id", 2);
    str(attr, "alt", "🎁");
    list[0] = attr;
    set(d, "attributes", vec_of(list, 1));
    return d;
}
static exteria_tl_value *gift(int64_t id, int64_t stars, int limited, int sold_out) {
    exteria_tl_value *g = obj("starGift");
    i64(g, "id", id);
    i64(g, "stars", stars);
    i64(g, "convert_stars", stars / 2);
    set(g, "sticker", document(id + 1000, "application/x-tgsticker"));
    if (limited) {
        flag(g, "limited");
        i32(g, "availability_remains", 40);
        i32(g, "availability_total", 100);
    }
    if (sold_out) flag(g, "sold_out");
    return g;
}
static exteria_tl_value *rarity(int32_t permille) {
    exteria_tl_value *r = obj("starGiftAttributeRarity");
    i32(r, "permille", permille);
    return r;
}
static exteria_tl_value *unique(int64_t id) {
    exteria_tl_value *g = obj("starGiftUnique"), *model = obj("starGiftAttributeModel"), *pattern = obj("starGiftAttributePattern");
    exteria_tl_value *backdrop = obj("starGiftAttributeBackdrop"), *attrs[3], *owner = obj("peerUser");
    i64(g, "id", id);
    i64(g, "gift_id", 77);
    str(g, "title", "Plush Pepe");
    str(g, "slug", "PlushPepe-12");
    i32(g, "num", 12);
    i32(g, "availability_issued", 30);
    i32(g, "availability_total", 100);
    i64(owner, "user_id", 9);
    set(g, "owner_id", owner);
    str(model, "name", "Frog");
    set(model, "document", document(5000, "application/x-tgsticker"));
    set(model, "rarity", rarity(30));
    str(pattern, "name", "Dots");
    set(pattern, "document", document(5001, "application/x-tgsticker"));
    set(pattern, "rarity", rarity(4));
    str(backdrop, "name", "Mint");
    set(backdrop, "rarity", obj("starGiftAttributeRarityRare"));
    i32(backdrop, "pattern_color", 0x0a0b0c);
    i32(backdrop, "center_color", 0x112233);
    i32(backdrop, "edge_color", (int32_t)0xff445566);
    i32(backdrop, "text_color", 0x778899);
    attrs[0] = model;
    attrs[1] = pattern;
    attrs[2] = backdrop;
    set(g, "attributes", vec_of(attrs, 3));
    return g;
}

static void test_gift_read(void) {
    exteria_gift g;
    CHECK_EQ_INT(exteria_gift_read(gift(10, 100, 1, 0), &g), EXTERIA_OK);
    CHECK_EQ_INT(g.id, 10);
    CHECK_EQ_INT(g.stars, 100);
    CHECK_EQ_INT(g.convert_stars, 50);
    CHECK_EQ_INT(g.limited, 1);
    CHECK_EQ_INT(g.remains, 40);
    CHECK_EQ_INT(g.total, 100);
    CHECK_EQ_INT(g.sticker.ref.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(g.sticker.ref.id, 1010);
    CHECK_EQ_INT(g.sticker.sticker, EXTERIA_STICKER_ANIMATED);
    CHECK_EQ_INT(g.unique, 0);

    CHECK_EQ_INT(exteria_gift_read(unique(20), &g), EXTERIA_OK);
    CHECK_EQ_INT(g.unique, 1);
    CHECK_EQ_INT(g.catalog_id, 77);
    CHECK(!strcmp(g.title, "Plush Pepe"));
    CHECK(!strcmp(g.model, "Frog"));
    CHECK(!strcmp(g.pattern, "Dots"));
    CHECK(!strcmp(g.backdrop, "Mint"));
    CHECK_EQ_INT(g.num, 12);
    CHECK_EQ_INT(g.owner_id, 9);
    CHECK_EQ_INT(g.has_backdrop, 1);
    CHECK_EQ_INT(g.backdrop_center, 0x112233);
    CHECK_EQ_INT(g.backdrop_edge, 0x445566);
    CHECK_EQ_INT(g.sticker.ref.id, 5000);
    CHECK_EQ_INT(g.pattern_sticker.ref.id, 5001);
    CHECK_EQ_INT(g.pattern_sticker.sticker, EXTERIA_STICKER_ANIMATED);
    CHECK_EQ_INT(g.backdrop_pattern, 0x0a0b0c);
    CHECK_EQ_INT(g.model_permille, 30);
    CHECK_EQ_INT(g.pattern_permille, 4);
    /* a ranked rarity names no number */
    CHECK_EQ_INT(g.backdrop_permille, 0);

    /* a backdrop without its own pattern color draws the symbols in the text color */
    {
        exteria_tl_value *plain = unique(21), *attrs[1];
        exteria_tl_value *back = obj("starGiftAttributeBackdrop");
        str(back, "name", "Gray");
        i32(back, "center_color", 1);
        i32(back, "edge_color", 2);
        i32(back, "text_color", 0x778899);
        attrs[0] = back;
        set(plain, "attributes", vec_of(attrs, 1));
        CHECK_EQ_INT(exteria_gift_read(plain, &g), EXTERIA_OK);
        CHECK_EQ_INT(g.backdrop_pattern, 0x778899);
        CHECK_EQ_INT(g.pattern_sticker.ref.source, EXTERIA_MEDIA_SOURCE_NONE);
    }

    /* a picture that is not a document leaves the gift readable without one */
    {
        exteria_tl_value *no_picture = gift(11, 5, 0, 0);
        set(no_picture, "sticker", obj("documentEmpty"));
        CHECK_EQ_INT(exteria_gift_read(no_picture, &g), EXTERIA_OK);
        CHECK_EQ_INT(g.sticker.ref.source, EXTERIA_MEDIA_SOURCE_NONE);
    }
    CHECK_EQ_INT(exteria_gift_read(gift(0, 5, 0, 0), &g), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(g.id, 0);
    CHECK_EQ_INT(exteria_gift_read(gift(3, -1, 0, 0), &g), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_gift_read(obj("boolTrue"), &g), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_gift_read(NULL, &g), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_gift_read(gift(3, 1, 0, 0), NULL), EXTERIA_E_ARG);
    {
        exteria_tl_value *bad = unique(21);
        str(bad, "title", "");
        CHECK_EQ_INT(exteria_gift_read(bad, &g), EXTERIA_E_MALFORMED);
        bad = unique(22);
        i32(bad, "num", 0);
        CHECK_EQ_INT(exteria_gift_read(bad, &g), EXTERIA_E_MALFORMED);
    }
}

static void test_catalog(void) {
    exteria_gift *gifts = calloc(EXTERIA_GIFTS_MAX, sizeof(*gifts));
    exteria_tl_value *items[4], *answer = obj("payments.starGifts");
    size_t count = 5;
    int32_t hash = 0;
    CHECK(gifts != NULL);
    items[0] = gift(1, 10, 1, 1);
    items[1] = gift(2, 20, 0, 0);
    items[2] = obj("boolTrue");
    items[3] = unique(3);
    set(answer, "gifts", vec_of(items, 4));
    i32(answer, "hash", 4242);
    CHECK_EQ_INT(exteria_gifts_parse(answer, gifts, EXTERIA_GIFTS_MAX, &count, &hash), EXTERIA_OK);
    /* the sold out gift goes last, a unique gift is no catalog entry and an unreadable one is dropped */
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(gifts[0].id, 2);
    CHECK_EQ_INT(gifts[1].id, 1);
    CHECK_EQ_INT(hash, 4242);
    CHECK_EQ_INT(exteria_gifts_parse(answer, gifts, 1, &count, &hash), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_gifts_parse(obj("payments.starGiftsNotModified"), gifts, 4, &count, &hash), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_gifts_parse(obj("boolTrue"), gifts, 4, &count, &hash), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_gifts_parse(answer, NULL, 4, &count, &hash), EXTERIA_E_ARG);
    set(answer, "gifts", exteria_tl_new_vec(&arena, EXTERIA_GIFTS_MAX * 2 + 1));
    CHECK_EQ_INT(exteria_gifts_parse(answer, gifts, 4, &count, &hash), EXTERIA_E_LIMIT);
    free(gifts);
}

static void test_saved(void) {
    exteria_saved_gift *rows = calloc(EXTERIA_SAVED_GIFTS_MAX, sizeof(*rows));
    exteria_saved_gift_page page;
    exteria_tl_value *a = obj("savedStarGift"), *b = obj("savedStarGift"), *items[3], *users[1], *answer = obj("payments.savedStarGifts");
    exteria_tl_value *from = obj("peerUser"), *note = obj("textWithEntities"), *bad = obj("savedStarGift");
    size_t count = 9;
    CHECK(rows != NULL);
    i64(from, "user_id", 6);
    i32(a, "date", 1000);
    set(a, "gift", gift(10, 100, 0, 0));
    set(a, "from_id", from);
    i32(a, "msg_id", 55);
    flag(a, "can_upgrade");
    flag(a, "pinned_to_top");
    i64(a, "convert_stars", 40);
    i64(a, "upgrade_stars", 300);
    str(note, "text", "happy birthday");
    {
        exteria_tl_value *emoji = obj("messageEntityCustomEmoji"), *bad_emoji = obj("messageEntityCustomEmoji"), *bold = obj("messageEntityBold");
        exteria_tl_value *entities[] = {emoji, bad_emoji, bold};
        i32(emoji, "offset", 1);
        i32(emoji, "length", 2);
        i64(emoji, "document_id", 123456789);
        i32(bad_emoji, "offset", -1);
        i32(bad_emoji, "length", 2);
        i64(bad_emoji, "document_id", 1);
        i32(bold, "offset", 5);
        i32(bold, "length", 8);
        set(note, "entities", vec_of(entities, 3));
    }
    set(a, "message", note);
    i32(b, "date", 900);
    set(b, "gift", unique(30));
    flag(b, "name_hidden");
    flag(b, "unsaved");
    i32(b, "msg_id", 56);
    i64(b, "transfer_stars", 25);
    i32(bad, "date", 800);
    set(bad, "gift", gift(0, 5, 0, 0));
    items[0] = a;
    items[1] = bad;
    items[2] = b;
    {
        exteria_tl_value *user = obj("user");
        i64(user, "id", 6);
        i64(user, "access_hash", 1);
        str(user, "first_name", "Kim");
        {
            exteria_tl_value *photo = obj("userProfilePhoto");
            i64(photo, "photo_id", 900);
            i32(photo, "dc_id", 4);
            set(user, "photo", photo);
        }
        users[0] = user;
    }
    set(answer, "gifts", vec_of(items, 3));
    set(answer, "users", vec_of(users, 1));
    set(answer, "chats", exteria_tl_new_vec(&arena, 0));
    i32(answer, "count", 17);
    str(answer, "next_offset", "abc");
    CHECK_EQ_INT(exteria_saved_gifts_parse(answer, rows, EXTERIA_SAVED_GIFTS_MAX, &count, &page), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(page.total, 17);
    CHECK(!strcmp(page.next_offset, "abc"));
    CHECK_EQ_INT(rows[0].msg_id, 55);
    CHECK_EQ_INT(rows[0].from_id, 6);
    CHECK(!strcmp(rows[0].from_name, "Kim"));
    CHECK_EQ_INT(rows[0].from_person.id, 6);
    CHECK_EQ_INT(rows[0].from_person.access_hash, 1);
    CHECK_EQ_INT(rows[0].from_person.photo.photo_id, 900);
    CHECK_EQ_INT(rows[0].from_person.photo.dc, 4);
    CHECK_EQ_INT(rows[1].from_person.id, 0);
    CHECK(!strcmp(rows[0].note, "happy birthday"));
    CHECK_EQ_INT(rows[0].note_entity_count, 2);
    CHECK_EQ_INT(rows[0].note_entities[0].kind, EXTERIA_ENTITY_CUSTOM_EMOJI);
    CHECK_EQ_INT(rows[0].note_entities[0].offset, 1);
    CHECK_EQ_INT(rows[0].note_entities[0].length, 2);
    CHECK_EQ_INT(rows[0].note_entities[0].document_id, 123456789);
    CHECK_EQ_INT(rows[0].note_entities[1].kind, EXTERIA_ENTITY_BOLD);
    CHECK_EQ_INT(rows[0].can_upgrade, 1);
    CHECK_EQ_INT(rows[0].pinned, 1);
    CHECK_EQ_INT(rows[0].convert_stars, 40);
    CHECK_EQ_INT(rows[0].upgrade_stars, 300);
    CHECK_EQ_INT(rows[1].name_hidden, 1);
    CHECK_EQ_INT(rows[1].unsaved, 1);
    CHECK_EQ_INT(rows[1].from_id, 0);
    CHECK_EQ_INT(rows[1].gift.unique, 1);
    CHECK_EQ_INT(rows[1].transfer_stars, 25);

    CHECK_EQ_INT(exteria_saved_gifts_parse(answer, rows, 1, &count, &page), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    str(answer, "next_offset", "0123456789012345678901234567890123456789012345678901234567890123456789");
    CHECK_EQ_INT(exteria_saved_gifts_parse(answer, rows, EXTERIA_SAVED_GIFTS_MAX, &count, &page), EXTERIA_OK);
    CHECK_EQ_INT(page.next_offset[0], 0);
    CHECK_EQ_INT(exteria_saved_gifts_parse(obj("boolTrue"), rows, 4, &count, &page), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_saved_gifts_parse(answer, rows, 0, &count, &page), EXTERIA_E_ARG);
    set(answer, "gifts", exteria_tl_new_vec(&arena, EXTERIA_SAVED_GIFTS_MAX + 1));
    CHECK_EQ_INT(exteria_saved_gifts_parse(answer, rows, 4, &count, &page), EXTERIA_E_LIMIT);
    free(rows);
}

static void test_payment_parse(void) {
    int64_t stars = 9, form = 9;
    exteria_tl_value *answer = obj("payments.starsStatus"), *amount = obj("starsAmount"), *ton = obj("starsTonAmount");
    exteria_tl_value *prices[2], *invoice = obj("invoice"), *price_a = obj("labeledPrice"), *price_b = obj("labeledPrice");
    exteria_tl_value *form_answer = obj("payments.paymentFormStarGift");
    i64(amount, "amount", 1500);
    i32(amount, "nanos", 0);
    set(answer, "balance", amount);
    CHECK_EQ_INT(exteria_stars_balance_parse(answer, &stars), EXTERIA_OK);
    CHECK_EQ_INT(stars, 1500);
    i64(ton, "amount", 5);
    set(answer, "balance", ton);
    CHECK_EQ_INT(exteria_stars_balance_parse(answer, &stars), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(stars, 0);
    i64(amount, "amount", -1);
    set(answer, "balance", amount);
    CHECK_EQ_INT(exteria_stars_balance_parse(answer, &stars), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_stars_balance_parse(obj("boolTrue"), &stars), EXTERIA_E_MALFORMED);

    str(price_a, "label", "gift");
    i64(price_a, "amount", 100);
    str(price_b, "label", "upgrade");
    i64(price_b, "amount", 50);
    prices[0] = price_a;
    prices[1] = price_b;
    str(invoice, "currency", "XTR");
    set(invoice, "prices", vec_of(prices, 2));
    i64(form_answer, "form_id", 4444);
    set(form_answer, "invoice", invoice);
    CHECK_EQ_INT(exteria_payment_form_parse(form_answer, &form, &stars), EXTERIA_OK);
    CHECK_EQ_INT(form, 4444);
    CHECK_EQ_INT(stars, 150);
    i64(price_b, "amount", INT64_MAX);
    CHECK_EQ_INT(exteria_payment_form_parse(form_answer, &form, &stars), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(form, 0);
    set(invoice, "prices", exteria_tl_new_vec(&arena, 0));
    CHECK_EQ_INT(exteria_payment_form_parse(form_answer, &form, &stars), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_payment_form_parse(obj("payments.paymentFormStars"), &form, &stars), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_payment_form_parse(obj("boolTrue"), &form, &stars), EXTERIA_E_MALFORMED);

    CHECK_EQ_INT(exteria_payment_result_check(obj("payments.paymentResult")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_payment_result_check(obj("payments.paymentVerificationNeeded")), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_payment_result_check(obj("boolTrue")), EXTERIA_E_MALFORMED);
}

static void roundtrip(exteria_tl_value *request, uint32_t constructor) {
    exteria_writer writer;
    exteria_tl_value *decoded = NULL;
    exteria_writer_init(&writer, 65536);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, writer.data, writer.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), constructor);
    exteria_writer_free(&writer);
}

static void test_requests(void) {
    exteria_peer_ref user = {1, 5, 7, 0, 0}, self = {1, 1, 0, 1, 0}, bad = {1, 5, 0, 0, 0};
    exteria_tl_value *request, *invoice;
    int32_t ids[] = {4, 5};
    int32_t zero[] = {4, 0};
    CHECK_EQ_INT(exteria_gifts_request(&arena, 12, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_getStarGifts);
    CHECK_EQ_INT(exteria_saved_gifts_request(&arena, &self, "", 30, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_getSavedStarGifts);
    CHECK_EQ_INT(exteria_saved_gifts_request(&arena, &user, "next", 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_saved_gifts_request(&arena, &user, "", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_gifts_request(&arena, &user, "", EXTERIA_SAVED_GIFTS_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_gifts_request(&arena, &user, NULL, 5, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_gifts_request(&arena, &bad, "", 5, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_stars_balance_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_getStarsStatus);

    CHECK_EQ_INT(exteria_gift_invoice_send(&arena, &user, 10, "hi", 1, 1, &invoice), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(invoice, "hide_name"), 1);
    CHECK_EQ_INT(exteria_tl_has(invoice, "include_upgrade"), 1);
    CHECK_EQ_INT(exteria_tl_has(invoice, "message"), 1);
    CHECK_EQ_INT(exteria_payment_form_request(&arena, invoice, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_getPaymentForm);
    CHECK_EQ_INT(exteria_payment_send_request(&arena, 4444, invoice, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_sendStarsForm);
    CHECK_EQ_INT(exteria_gift_invoice_send(&arena, &user, 10, "", 0, 0, &invoice), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(invoice, "message"), 0);
    CHECK_EQ_INT(exteria_gift_invoice_send(&arena, &user, 0, "", 0, 0, &invoice), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_invoice_send(&arena, &user, 10, NULL, 0, 0, &invoice), EXTERIA_E_ARG);
    {
        char big[EXTERIA_GIFT_NOTE_MAX + 1];
        memset(big, 'a', sizeof(big));
        big[sizeof(big) - 1] = 0;
        CHECK_EQ_INT(exteria_gift_invoice_send(&arena, &user, 10, big, 0, 0, &invoice), EXTERIA_E_ARG);
    }
    CHECK_EQ_INT(exteria_gift_invoice_upgrade(&arena, 8, 1, &invoice), EXTERIA_OK);
    CHECK_EQ_INT(exteria_payment_form_request(&arena, invoice, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_getPaymentForm);
    CHECK_EQ_INT(exteria_gift_invoice_upgrade(&arena, 0, 1, &invoice), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_invoice_transfer(&arena, 8, &user, &invoice), EXTERIA_OK);
    CHECK_EQ_INT(exteria_payment_send_request(&arena, 1, invoice, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_sendStarsForm);
    CHECK_EQ_INT(exteria_gift_invoice_transfer(&arena, 8, &bad, &invoice), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_payment_form_request(&arena, NULL, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_payment_send_request(&arena, 0, invoice, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_gift_save_request(&arena, 8, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "unsave"), 1);
    roundtrip(request, EXTERIA_TL_ID_payments_saveStarGift);
    CHECK_EQ_INT(exteria_gift_save_request(&arena, 8, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "unsave"), 0);
    CHECK_EQ_INT(exteria_gift_convert_request(&arena, 8, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_convertStarGift);
    CHECK_EQ_INT(exteria_gift_upgrade_request(&arena, 8, 0, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_upgradeStarGift);
    CHECK_EQ_INT(exteria_gift_transfer_request(&arena, 8, &user, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_transferStarGift);
    CHECK_EQ_INT(exteria_gift_pin_request(&arena, ids, 2, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_toggleStarGiftsPinnedToTop);
    CHECK_EQ_INT(exteria_gift_pin_request(&arena, NULL, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_gift_pin_request(&arena, zero, 2, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_pin_request(&arena, ids, 7, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_convert_request(&arena, -1, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

static void test_service_message(void) {
    exteria_message_row *row = calloc(1, sizeof(*row));
    exteria_tl_value *m = obj("messageService"), *action = obj("messageActionStarGift"), *note = obj("textWithEntities");
    CHECK(row != NULL);
    i32(m, "id", 7);
    i32(m, "date", 100);
    flag(m, "out");
    str(note, "text", "enjoy");
    set(note, "entities", exteria_tl_new_vec(&arena, 0));
    set(action, "gift", gift(10, 100, 0, 0));
    set(action, "message", note);
    set(m, "action", action);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->service, EXTERIA_SERVICE_GIFT + 1);
    CHECK_EQ_INT(row->gift.id, 10);
    CHECK_EQ_INT(row->gift.stars, 100);
    CHECK_EQ_INT(row->gift.sticker.ref.id, 1010);
    CHECK(!strcmp(row->text, "enjoy"));
    CHECK_EQ_INT(row->media.kind, EXTERIA_PREVIEW_SERVICE);

    m = obj("messageService");
    action = obj("messageActionStarGiftUnique");
    i32(m, "id", 8);
    i32(m, "date", 100);
    set(action, "gift", unique(31));
    set(m, "action", action);
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->service, EXTERIA_SERVICE_GIFT + 1);
    CHECK_EQ_INT(row->gift.unique, 1);
    CHECK_EQ_INT(row->text[0], 0);

    /* an unreadable gift keeps the line but loses the picture */
    set(action, "gift", gift(0, 5, 0, 0));
    CHECK_EQ_INT(exteria_message_read(m, row), EXTERIA_OK);
    CHECK_EQ_INT(row->gift.id, 0);
    free(row);
}

static exteria_tl_value *folder(int32_t id, const char *title, int32_t count) {
    exteria_tl_value *c = obj("starGiftCollection");
    i32(c, "collection_id", id);
    str(c, "title", title);
    i32(c, "gifts_count", count);
    i64(c, "hash", 9);
    return c;
}

/* the folders a profile shows its gifts by, and the requests that read and change them */
static void test_collections(void) {
    exteria_peer_ref self = {1, 1, 0, 1, 0}, bad = {1, 5, 0, 0, 0};
    exteria_gift_collection rows[4], one;
    exteria_tl_value *items[3], *answer, *request;
    int32_t ids[] = {4, 5}, zero[] = {4, 0};
    size_t count = 9;
    char big[EXTERIA_GIFT_COLLECTION_TITLE_MAX + 8];

    items[0] = folder(3, "Rare", 12);
    items[1] = folder(0, "No id", 1);
    items[2] = folder(8, "Cats", -4);
    answer = obj("payments.starGiftCollections");
    set(answer, "collections", vec_of(items, 3));
    CHECK_EQ_INT(exteria_gift_collections_parse(answer, rows, 4, &count), EXTERIA_OK);
    /* the folder without a usable id is skipped, a negative count reads as empty */
    CHECK_EQ_INT((int)count, 2);
    CHECK_EQ_INT(rows[0].id, 3);
    CHECK(strcmp(rows[0].title, "Rare") == 0);
    CHECK_EQ_INT(rows[0].count, 12);
    CHECK_EQ_INT(rows[1].id, 8);
    CHECK_EQ_INT(rows[1].count, 0);
    CHECK_EQ_INT(exteria_gift_collections_parse(obj("payments.starGiftCollectionsNotModified"), rows, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_gift_collections_parse(obj("messages.chats"), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_gift_collections_parse(answer, rows, 0, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_collections_parse(answer, rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT((int)count, 1);

    /* a title that does not fit is cut on a character, never in the middle of one */
    memset(big, 'a', sizeof(big));
    big[EXTERIA_GIFT_COLLECTION_TITLE_MAX - 3] = 0;
    strcat(big, "\xD0\xB1\xD0\xB1");
    CHECK_EQ_INT(exteria_gift_collection_read(folder(2, big, 1), &one), EXTERIA_OK);
    /* the second letter would cross the end of the buffer, so only the first stays, whole */
    CHECK_EQ_INT((int)strlen(one.title), EXTERIA_GIFT_COLLECTION_TITLE_MAX - 1);
    CHECK_EQ_INT((unsigned char)one.title[EXTERIA_GIFT_COLLECTION_TITLE_MAX - 3], 0xD0);
    CHECK_EQ_INT((unsigned char)one.title[EXTERIA_GIFT_COLLECTION_TITLE_MAX - 2], 0xB1);
    CHECK_EQ_INT(exteria_gift_collection_read(obj("messageEmpty"), &one), EXTERIA_E_MALFORMED);

    CHECK_EQ_INT(exteria_gift_collections_request(&arena, &self, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_getStarGiftCollections);
    CHECK_EQ_INT(exteria_gift_collections_request(&arena, &bad, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_gifts_in_collection_request(&arena, &self, 3, "", 30, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "collection_id"), 1);
    roundtrip(request, EXTERIA_TL_ID_payments_getSavedStarGifts);
    CHECK_EQ_INT(exteria_saved_gifts_in_collection_request(&arena, &self, 0, "", 30, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_saved_gifts_in_collection_request(&arena, &self, 3, "", 0, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_gift_collection_create_request(&arena, &self, "Rare", ids, 2, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_createStarGiftCollection);
    CHECK_EQ_INT(exteria_gift_collection_create_request(&arena, &self, "Empty", NULL, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_gift_collection_create_request(&arena, &self, "", ids, 2, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_collection_create_request(&arena, &self, NULL, ids, 2, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_collection_create_request(&arena, &self, "Rare", zero, 2, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_collection_create_request(&arena, &self, "Rare", ids, EXTERIA_GIFT_COLLECTION_BATCH_MAX + 1, &request), EXTERIA_E_ARG);
    memset(big, 'a', sizeof(big));
    big[EXTERIA_GIFT_COLLECTION_TITLE_MAX] = 0;
    CHECK_EQ_INT(exteria_gift_collection_create_request(&arena, &self, big, ids, 2, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_gift_collection_update_request(&arena, &self, 3, NULL, ids, 2, NULL, 0, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "add_stargift"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "delete_stargift"), 0);
    CHECK_EQ_INT(exteria_tl_has(request, "title"), 0);
    roundtrip(request, EXTERIA_TL_ID_payments_updateStarGiftCollection);
    CHECK_EQ_INT(exteria_gift_collection_update_request(&arena, &self, 3, "New", NULL, 0, ids, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "delete_stargift"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "title"), 1);
    CHECK_EQ_INT(exteria_gift_collection_update_request(&arena, &self, 3, NULL, NULL, 0, NULL, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_collection_update_request(&arena, &self, 0, "x", NULL, 0, NULL, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_gift_collection_delete_request(&arena, &self, 3, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_deleteStarGiftCollection);
    CHECK_EQ_INT(exteria_gift_collection_delete_request(&arena, &self, -1, &request), EXTERIA_E_ARG);
}

static void test_convert_period(void) {
    exteria_saved_gift gift;
    int32_t seconds = -1;
    exteria_tl_value *answer = obj("help.appConfig"), *config = obj("jsonObject"), *entry = obj("jsonObjectValue"), *number = obj("jsonNumber");
    exteria_tl_value *entries[] = {entry};
    i32(answer, "hash", 1);
    str(entry, "key", "stargifts_convert_period_max");
    CHECK_EQ_INT(exteria_tl_set_f64(&arena, number, "value", 604800), EXTERIA_OK);
    set(entry, "value", number);
    set(config, "value", vec_of(entries, 1));
    set(answer, "config", config);
    CHECK_EQ_INT(exteria_gift_convert_period_parse(answer, &seconds), EXTERIA_OK);
    CHECK_EQ_INT(seconds, 604800);
    CHECK_EQ_INT(exteria_tl_set_f64(&arena, number, "value", 3.5), EXTERIA_OK);
    CHECK_EQ_INT(exteria_gift_convert_period_parse(answer, &seconds), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(seconds, 0);
    str(entry, "key", "another_setting");
    CHECK_EQ_INT(exteria_gift_convert_period_parse(answer, &seconds), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(seconds, 0);
    CHECK_EQ_INT(exteria_gift_convert_period_parse(NULL, &seconds), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_gift_convert_period_parse(answer, NULL), EXTERIA_E_MALFORMED);
    memset(&gift, 0, sizeof(gift));
    gift.date = 1000;
    gift.convert_stars = 1;
    CHECK(exteria_gift_can_convert(&gift, 1000, 60));
    CHECK(exteria_gift_can_convert(&gift, 1059, 60));
    CHECK(!exteria_gift_can_convert(&gift, 1060, 60));
    CHECK(!exteria_gift_can_convert(&gift, 999, 60));
    gift.gift.unique = 1;
    CHECK(!exteria_gift_can_convert(&gift, 1001, 60));
    gift.gift.unique = 0;
    gift.gift.auction = 1;
    CHECK(!exteria_gift_can_convert(&gift, 1001, 60));
    gift.gift.auction = 0;
    gift.refunded = 1;
    CHECK(!exteria_gift_can_convert(&gift, 1001, 60));
    CHECK(!exteria_gift_can_convert(NULL, 1001, 60));
}

int main(void) {
    exteria_arena_init(&arena, 16u * 1024u * 1024u);
    test_gift_read();
    test_catalog();
    test_saved();
    test_payment_parse();
    test_requests();
    test_service_message();
    test_collections();
    test_convert_period();
    exteria_arena_free(&arena);
    return test_finish("test_gifts");
}
