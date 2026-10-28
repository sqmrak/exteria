#include "test_util.h"
#include "exteria_messages.h"
#include "exteria_tl_ids.h"

static exteria_tl_value *uploaded_file(exteria_arena *arena) {
    exteria_tl_value *file = exteria_tl_new_obj(arena, "inputFile");
    CHECK(file != NULL);
    CHECK_EQ_INT(exteria_tl_set_i64(arena, file, "id", 44), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(arena, file, "parts", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(arena, file, "name", "once.jpg"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(arena, file, "md5_checksum", ""), EXTERIA_OK);
    return file;
}

/* the ttl of a one-time photo, video, voice note or round video reaches the input media, and an ordinary send carries none */
static void check_send(exteria_arena *arena, const exteria_peer_ref *peer, exteria_upload_spec *spec, int once) {
    exteria_tl_value *request = NULL;
    int32_t ttl = 0;
    spec->view_once = (uint8_t)once;
    CHECK_EQ_INT(exteria_send_upload_request(arena, peer, uploaded_file(arena), spec, 52, &request), EXTERIA_OK);
    const exteria_tl_value *media = exteria_tl_get(request, "media");
    CHECK_EQ_INT(exteria_tl_has(media, "ttl_seconds"), once);
    if (once) {
        CHECK_EQ_INT(exteria_tl_get_i32(media, "ttl_seconds", &ttl), EXTERIA_OK);
        CHECK_EQ_INT(ttl, EXTERIA_VIEW_ONCE_TTL);
    }
    exteria_writer writer;
    exteria_writer_init(&writer, 8192);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    exteria_writer_free(&writer);
}

static void check_read(exteria_arena *arena, const char *constructor, int32_t ttl, int32_t expected) {
    exteria_tl_value *media = exteria_tl_new_obj(arena, constructor);
    exteria_media_info info;
    CHECK(media != NULL);
    if (ttl) CHECK_EQ_INT(exteria_tl_set_i32(arena, media, "ttl_seconds", ttl), EXTERIA_OK);
    exteria_media_classify(media, &info);
    CHECK_EQ_INT(info.ttl_seconds, expected);
}

int main(void) {
    exteria_arena arena;
    exteria_arena_init(&arena, 4 * 1024 * 1024);
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = 1; peer.id = 12; peer.access_hash = 34;
    exteria_upload_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.kind = EXTERIA_UPLOAD_PHOTO;
    check_send(&arena, &peer, &spec, 1);
    check_send(&arena, &peer, &spec, 0);
    spec.kind = EXTERIA_UPLOAD_VIDEO; spec.duration_ms = 2000; spec.width = 640; spec.height = 480;
    check_send(&arena, &peer, &spec, 1);
    check_send(&arena, &peer, &spec, 0);
    spec.kind = EXTERIA_UPLOAD_ROUND; spec.width = 384; spec.height = 0;
    check_send(&arena, &peer, &spec, 1);
    uint8_t wave[EXTERIA_WAVEFORM_BYTES] = {1, 2, 3, 4};
    memset(&spec, 0, sizeof(spec));
    spec.kind = EXTERIA_UPLOAD_VOICE; spec.duration_ms = 3000; spec.waveform = wave; spec.waveform_len = sizeof(wave);
    check_send(&arena, &peer, &spec, 1);
    /* a file is kept for good, so a one-time file is refused instead of sent as a normal one */
    memset(&spec, 0, sizeof(spec));
    spec.kind = EXTERIA_UPLOAD_FILE; spec.view_once = 1;
    snprintf(spec.name, sizeof(spec.name), "a.bin"); snprintf(spec.mime, sizeof(spec.mime), "application/octet-stream");
    exteria_tl_value *refused = NULL;
    CHECK_EQ_INT(exteria_send_upload_request(&arena, &peer, uploaded_file(&arena), &spec, 52, &refused), EXTERIA_E_ARG);
    CHECK(refused == NULL);
    /* what arrives: the ttl of a photo and a document is kept, an ordinary one has none, and a negative one is not trusted */
    check_read(&arena, "messageMediaPhoto", EXTERIA_VIEW_ONCE_TTL, EXTERIA_VIEW_ONCE_TTL);
    check_read(&arena, "messageMediaPhoto", 10, 10);
    check_read(&arena, "messageMediaPhoto", 0, 0);
    check_read(&arena, "messageMediaPhoto", -5, 0);
    check_read(&arena, "messageMediaDocument", EXTERIA_VIEW_ONCE_TTL, EXTERIA_VIEW_ONCE_TTL);
    check_read(&arena, "messageMediaDocument", 0, 0);
    /* a video of which only the flag is left once it was opened still reads as a video */
    exteria_tl_value *expired = exteria_tl_new_obj(&arena, "messageMediaDocument");
    exteria_media_info info;
    CHECK(expired != NULL);
    CHECK_EQ_INT(exteria_tl_set_flag(expired, "video"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, expired, "ttl_seconds", EXTERIA_VIEW_ONCE_TTL), EXTERIA_OK);
    exteria_media_classify(expired, &info);
    CHECK_EQ_INT(info.kind, EXTERIA_PREVIEW_VIDEO);
    CHECK_EQ_INT(info.ref.source, EXTERIA_MEDIA_SOURCE_NONE);
    exteria_arena_free(&arena);
    return test_finish("test_view_once");
}
