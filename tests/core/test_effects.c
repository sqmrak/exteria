#include <string.h>

#include "exteria_effects.h"
#include "exteria_tl_ids.h"
#include "test_util.h"

static exteria_tl_value *effect(exteria_arena *arena, int64_t id, const char *emoticon, int premium) {
    exteria_tl_value *item = exteria_tl_new_obj(arena, "availableEffect");
    exteria_tl_set_i64(arena, item, "id", id);
    exteria_tl_set_str(arena, item, "emoticon", emoticon);
    exteria_tl_set_i64(arena, item, "effect_sticker_id", 99);
    if (premium) exteria_tl_set_flag(item, "premium_required");
    return item;
}

static exteria_tl_value *answer(exteria_arena *arena, exteria_tl_value **items, uint32_t count) {
    exteria_tl_value *result = exteria_tl_new_obj(arena, "messages.availableEffects");
    exteria_tl_value *list = exteria_tl_new_vec(arena, count);
    for (uint32_t i = 0; i < count; ++i) exteria_tl_vec_set(list, i, items[i]);
    exteria_tl_set(result, "effects", list);
    exteria_tl_set_i32(arena, result, "hash", 7);
    exteria_tl_set(result, "documents", exteria_tl_new_vec(arena, 0));
    return result;
}

static void test_request(void) {
    exteria_arena arena;
    exteria_tl_value *request = NULL;
    int32_t hash = -1;
    exteria_arena_init(&arena, 1u << 16);
    CHECK_EQ_INT(exteria_effects_request(&arena, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getAvailableEffects);
    CHECK_EQ_INT(exteria_tl_get_i32(request, "hash", &hash), EXTERIA_OK);
    CHECK_EQ_INT(hash, 0);
    CHECK_EQ_INT(exteria_effects_request(&arena, NULL), EXTERIA_E_ARG);
    exteria_arena_free(&arena);
}

static void test_parse(void) {
    exteria_arena arena;
    exteria_tl_value *items[4];
    exteria_effect rows[8];
    size_t count = 99;
    exteria_arena_init(&arena, 1u << 16);
    items[0] = effect(&arena, 5159385139981059251LL, "\xf0\x9f\x94\xa5", 0);
    items[1] = effect(&arena, 5104841245755180586LL, "\xf0\x9f\x8e\x89", 1);
    /* no id and no emoji are left out, and so is an emoji that does not fit */
    items[2] = effect(&arena, 0, "\xf0\x9f\x91\x8d", 0);
    items[3] = effect(&arena, 12, "", 0);
    CHECK_EQ_INT(exteria_effects_parse(answer(&arena, items, 4), rows, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].id, 5159385139981059251LL);
    CHECK(!strcmp(rows[0].emoticon, "\xf0\x9f\x94\xa5"));
    CHECK_EQ_INT(rows[0].premium, 0);
    CHECK_EQ_INT(rows[1].premium, 1);
    /* the cap cuts the list */
    CHECK_EQ_INT(exteria_effects_parse(answer(&arena, items, 2), rows, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    /* an answer of another kind, and bad arguments */
    CHECK_EQ_INT(exteria_effects_parse(exteria_tl_new_obj(&arena, "messages.availableEffectsNotModified"), rows, 8, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_effects_parse(NULL, rows, 8, &count), EXTERIA_E_ARG);
    exteria_arena_free(&arena);
}

static void test_documents_are_matched(void) {
    exteria_arena arena;
    exteria_tl_value *items[1], *result, *docs, *document;
    exteria_effect rows[2];
    size_t count = 0;
    exteria_arena_init(&arena, 1u << 16);
    items[0] = effect(&arena, 7, "\xf0\x9f\x94\xa5", 0);
    exteria_tl_set_i64(&arena, items[0], "effect_animation_id", 4242);
    result = answer(&arena, items, 1);
    docs = exteria_tl_new_vec(&arena, 1);
    document = exteria_tl_new_obj(&arena, "document");
    exteria_tl_set_i64(&arena, document, "id", 4242);
    exteria_tl_set_i64(&arena, document, "access_hash", 9);
    exteria_tl_set_str(&arena, document, "mime_type", "application/x-tgsticker");
    exteria_tl_vec_set(docs, 0, document);
    exteria_tl_set(result, "documents", docs);
    CHECK_EQ_INT(exteria_effects_parse(result, rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(rows[0].animation_id, 4242);
    CHECK_EQ_INT(rows[0].animation.id, 4242);
    CHECK_EQ_INT(rows[0].animation.format, EXTERIA_STICKER_ANIMATED);
    /* the sticker document is not in the answer, so it stays empty */
    CHECK_EQ_INT(rows[0].sticker.id, 0);
    exteria_arena_free(&arena);
}

static void test_set_effect(void) {
    exteria_arena arena;
    exteria_tl_value *request;
    int64_t id = 0;
    exteria_arena_init(&arena, 1u << 16);
    request = exteria_tl_new_obj(&arena, "messages.sendMessage");
    CHECK_EQ_INT(exteria_set_effect(&arena, request, 555), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i64(request, "effect", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 555);
    CHECK_EQ_INT(exteria_set_effect(&arena, request, 0), EXTERIA_E_ARG);
    exteria_arena_free(&arena);
}

int main(void) {
    test_request();
    test_parse();
    test_documents_are_matched();
    test_set_effect();
    return test_finish("test_effects");
}
