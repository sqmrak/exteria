#include "test_util.h"
#include "exteria_sticker_manage.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static void test_uninstall(void) {
    exteria_tl_value *request = NULL;
    const exteria_tl_value *set;
    exteria_writer wire;
    int64_t id = 0, hash = 0;
    CHECK_EQ_INT(exteria_sticker_uninstall_request(&arena, 77, 99, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_uninstallStickerSet);
    set = exteria_tl_get(request, "stickerset");
    CHECK(exteria_tl_is(set, EXTERIA_TL_ID_inputStickerSetID));
    CHECK_EQ_INT(exteria_tl_get_i64(set, "id", &id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_i64(set, "access_hash", &hash), EXTERIA_OK);
    CHECK_EQ_INT(id, 77);
    CHECK_EQ_INT(hash, 99);
    exteria_writer_init(&wire, 128);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_sticker_uninstall_request(&arena, 0, 99, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_sticker_uninstall_request(&arena, -5, 99, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_uninstall_request(NULL, 5, 99, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_uninstall_request(&arena, 5, 99, NULL), EXTERIA_E_ARG);
}

static void test_install(void) {
    exteria_tl_value *request = NULL, *answer;
    const exteria_tl_value *set;
    exteria_writer wire;
    int64_t id = 0;
    CHECK_EQ_INT(exteria_sticker_install_request(&arena, 77, 99, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_installStickerSet);
    set = exteria_tl_get(request, "stickerset");
    CHECK(exteria_tl_is(set, EXTERIA_TL_ID_inputStickerSetID));
    CHECK_EQ_INT(exteria_tl_get_i64(set, "id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, 77);
    CHECK(exteria_tl_is(exteria_tl_get(request, "archived"), EXTERIA_TL_ID_boolFalse));
    exteria_writer_init(&wire, 128);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_sticker_install_request(&arena, 0, 99, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_sticker_install_request(&arena, 5, 99, NULL), EXTERIA_E_ARG);
    answer = exteria_tl_new_obj(&arena, "messages.stickerSetInstallResultSuccess");
    CHECK_EQ_INT(exteria_sticker_install_parse(answer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_sticker_install_parse(exteria_tl_new_obj(&arena, "boolTrue")), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_sticker_install_parse(NULL), EXTERIA_E_MALFORMED);
}

static void test_reorder(void) {
    exteria_tl_value *request = NULL;
    const exteria_tl_value *order = NULL;
    exteria_writer wire;
    const int64_t ids[] = {30, 10, 20};
    const int64_t twice[] = {30, 10, 30};
    const int64_t bad[] = {30, 0};
    CHECK_EQ_INT(exteria_sticker_reorder_request(&arena, ids, 3, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_reorderStickerSets);
    CHECK_EQ_INT(exteria_tl_get_vec(request, "order", &order), EXTERIA_OK);
    CHECK_EQ_INT(order->u.vec.count, 3);
    CHECK_EQ_INT(order->u.vec.items[0]->u.i64, 30);
    CHECK_EQ_INT(order->u.vec.items[2]->u.i64, 20);
    CHECK(!exteria_tl_has(request, "masks"));
    exteria_writer_init(&wire, 128);
    CHECK_EQ_INT(exteria_tl_encode(request, &wire, NULL), EXTERIA_OK);
    exteria_writer_free(&wire);
    CHECK_EQ_INT(exteria_sticker_reorder_request(&arena, twice, 3, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_sticker_reorder_request(&arena, bad, 2, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_reorder_request(&arena, ids, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_reorder_request(&arena, ids, EXTERIA_STICKER_ORDER_MAX + 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_reorder_request(&arena, NULL, 3, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_sticker_reorder_request(&arena, ids, 3, NULL), EXTERIA_E_ARG);
}

static void test_parse(void) {
    exteria_tl_value *yes = exteria_tl_new_obj(&arena, "boolTrue"), *no = exteria_tl_new_obj(&arena, "boolFalse"), *other = exteria_tl_new_obj(&arena, "updates");
    CHECK_EQ_INT(exteria_sticker_manage_parse(yes), EXTERIA_OK);
    CHECK_EQ_INT(exteria_sticker_manage_parse(no), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_sticker_manage_parse(other), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_sticker_manage_parse(NULL), EXTERIA_E_MALFORMED);
}

int main(void) {
    exteria_arena_init(&arena, 1024u * 1024u);
    test_uninstall();
    test_install();
    test_reorder();
    test_parse();
    exteria_arena_free(&arena);
    return test_finish("test_sticker_manage");
}
