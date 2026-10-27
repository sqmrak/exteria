#include "test_util.h"
#include "exteria_messages.h"
#include "exteria_tl_ids.h"

static void check_caption(exteria_arena *arena, const exteria_peer_ref *peer, exteria_upload_spec *spec, const char *text) {
    exteria_tl_value *file = exteria_tl_new_obj(arena, "inputFile"), *request = NULL;
    const uint8_t *bytes = NULL;
    size_t length = 0;
    CHECK(file != NULL);
    CHECK_EQ_INT(exteria_tl_set_i64(arena, file, "id", 44), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(arena, file, "parts", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(arena, file, "name", "photo.jpg"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(arena, file, "md5_checksum", ""), EXTERIA_OK);
    snprintf(spec->caption, sizeof(spec->caption), "%s", text);
    CHECK_EQ_INT(exteria_send_upload_request(arena, peer, file, spec, 52, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "message", &bytes, &length), EXTERIA_OK);
    CHECK_EQ_INT(length, strlen(text));
    CHECK_MEM(bytes, text, length);
    exteria_writer writer;
    exteria_writer_init(&writer, 8192);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK(writer.len > length);
    exteria_writer_free(&writer);
    const exteria_tl_value *reply = exteria_tl_get(request, "reply_to");
    int32_t id = 0;
    CHECK_EQ_INT(exteria_tl_get_i32(reply, "reply_to_msg_id", &id), EXTERIA_OK);
    CHECK_EQ_INT(id, peer->topic_id);
    memset(spec->caption, 'a', sizeof(spec->caption));
    CHECK_EQ_INT(exteria_send_upload_request(arena, peer, file, spec, 52, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
}

/* the spoiler flag reaches the media of a photo and of a video, and of nothing else */
static void check_spoiler(exteria_arena *arena, const exteria_peer_ref *peer, exteria_upload_spec *spec, int expected) {
    exteria_tl_value *file = exteria_tl_new_obj(arena, "inputFile"), *request = NULL;
    CHECK_EQ_INT(exteria_tl_set_i64(arena, file, "id", 44), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(arena, file, "parts", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(arena, file, "name", "photo.jpg"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(arena, file, "md5_checksum", ""), EXTERIA_OK);
    spec->caption[0] = 0;
    CHECK_EQ_INT(exteria_send_upload_request(arena, peer, file, spec, 52, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(exteria_tl_get(request, "media"), "spoiler"), expected);
}

int main(void) {
    exteria_arena arena;
    exteria_arena_init(&arena, 1024 * 1024);
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = 3; peer.id = 12; peer.access_hash = 34; peer.topic_id = 56;
    exteria_upload_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.kind = EXTERIA_UPLOAD_PHOTO;
    check_caption(&arena, &peer, &spec, "");
    check_caption(&arena, &peer, &spec, "Фото 🌅\nвторая строка");
    char maximum[EXTERIA_UPLOAD_CAPTION_MAX + 1];
    memset(maximum, 'x', sizeof(maximum) - 1); maximum[sizeof(maximum) - 1] = 0;
    check_caption(&arena, &peer, &spec, maximum);
    spec.kind = EXTERIA_UPLOAD_VIDEO; spec.duration_ms = 1000; spec.width = 640; spec.height = 480;
    check_caption(&arena, &peer, &spec, "Видео 🎥");
    spec.spoiler = 1;
    check_spoiler(&arena, &peer, &spec, 1);
    spec.kind = EXTERIA_UPLOAD_PHOTO; spec.duration_ms = 0; spec.width = 0; spec.height = 0;
    check_spoiler(&arena, &peer, &spec, 1);
    spec.spoiler = 0;
    check_spoiler(&arena, &peer, &spec, 0);
    /* a file has no blurred mode, so the flag is left off even when asked for */
    spec.kind = EXTERIA_UPLOAD_FILE; spec.spoiler = 1;
    snprintf(spec.name, sizeof(spec.name), "a.jpg"); snprintf(spec.mime, sizeof(spec.mime), "image/jpeg");
    check_spoiler(&arena, &peer, &spec, 0);
    exteria_arena_free(&arena);
    return test_finish("test_media_caption");
}
