#include "test_util.h"
#include "exteria_theme_link.h"
#include "exteria_tl_ids.h"

#include <string.h>

static exteria_arena arena;

static exteria_tl_value *document_of(int64_t id) {
    static const uint8_t reference[] = {9, 8, 7};
    exteria_tl_value *d = exteria_tl_new_obj(&arena, "document");
    CHECK(d != NULL);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, d, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, d, "access_hash", id * 3), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, d, "file_reference", reference, sizeof(reference)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, d, "dc_id", 4), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, d, "size", 5120), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, d, "mime_type", "application/x-tgtheme-ios"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(d, "attributes", exteria_tl_new_vec(&arena, 0)), EXTERIA_OK);
    return d;
}

static exteria_tl_value *theme_of(const char *title, exteria_tl_value *document) {
    exteria_tl_value *t = exteria_tl_new_obj(&arena, "theme");
    CHECK(t != NULL);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, t, "id", 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, t, "access_hash", 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, t, "slug", "EUv1TXVWMHmXclaj"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, t, "title", title), EXTERIA_OK);
    if (document) CHECK_EQ_INT(exteria_tl_set(t, "document", document), EXTERIA_OK);
    return t;
}

static exteria_tl_value *colors_of(const char *title, const char *base, int32_t accent) {
    exteria_tl_value *t = theme_of(title, NULL), *settings = exteria_tl_new_obj(&arena, "themeSettings"), *list = exteria_tl_new_vec(&arena, 1);
    CHECK(settings != NULL && list != NULL);
    if (base) CHECK_EQ_INT(exteria_tl_set(settings, "base_theme", exteria_tl_new_obj(&arena, base)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, settings, "accent_color", accent), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(list, 0, settings), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(t, "settings", list), EXTERIA_OK);
    return t;
}

static void test_request(void) {
    exteria_tl_value *request = NULL, *decoded = NULL;
    exteria_writer writer;
    CHECK_EQ_INT(exteria_theme_link_request(&arena, "EUv1TXVWMHmXclaj", &request), EXTERIA_OK);
    exteria_writer_init(&writer, 256);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, writer.data, writer.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), EXTERIA_TL_ID_account_getTheme);
    exteria_writer_free(&writer);
    CHECK_EQ_INT(exteria_theme_link_request(&arena, "a-b_C9", &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_theme_link_request(&arena, "", &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_theme_link_request(&arena, "bad slug", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_theme_link_request(&arena, "x;y", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_theme_link_request(NULL, "abc", &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_theme_link_request(&arena, NULL, &request), EXTERIA_E_ARG);
}

static void test_request_slug_length(void) {
    char slug[EXTERIA_THEME_SLUG_MAX + 2];
    exteria_tl_value *request = NULL;
    memset(slug, 'a', sizeof(slug));
    slug[EXTERIA_THEME_SLUG_MAX] = 0;
    CHECK_EQ_INT(exteria_theme_link_request(&arena, slug, &request), EXTERIA_OK);
    slug[EXTERIA_THEME_SLUG_MAX] = 'a';
    slug[EXTERIA_THEME_SLUG_MAX + 1] = 0;
    CHECK_EQ_INT(exteria_theme_link_request(&arena, slug, &request), EXTERIA_E_ARG);
}

static void test_parse(void) {
    exteria_theme_link_info info;
    char long_title[300];
    CHECK_EQ_INT(exteria_theme_link_parse(theme_of("Night", document_of(77)), &info), EXTERIA_OK);
    CHECK(!strcmp(info.title, "Night"));
    CHECK_EQ_INT(info.has_file, 1);
    CHECK_EQ_INT(info.file.ref.source, EXTERIA_MEDIA_SOURCE_DOCUMENT);
    CHECK_EQ_INT(info.file.ref.id, 77);
    CHECK_EQ_INT(info.file.ref.dc, 4);
    CHECK_EQ_INT(info.file.size, 5120);
    /* a theme with accent settings only has no file to import */
    CHECK_EQ_INT(exteria_theme_link_parse(theme_of("Accent", NULL), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.has_file, 0);
    CHECK(!strcmp(info.title, "Accent"));
    CHECK_EQ_INT(info.has_colors, 0);
    /* a theme of colors: the base look and the accent, with the alpha byte a signed value carries cut off */
    CHECK_EQ_INT(exteria_theme_link_parse(colors_of("Moon", "baseThemeNight", (int32_t)0xFF3A7BD5u), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.has_file, 0);
    CHECK_EQ_INT(info.has_colors, 1);
    CHECK_EQ_INT(info.dark, 1);
    CHECK_EQ_INT(info.accent, 0x3A7BD5u);
    CHECK_EQ_INT(exteria_theme_link_parse(colors_of("Sun", "baseThemeDay", 0x112233), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.dark, 0);
    CHECK_EQ_INT(info.accent, 0x112233u);
    CHECK_EQ_INT(exteria_theme_link_parse(colors_of("Dusk", "baseThemeTinted", 0x445566), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.dark, 1);
    /* settings with no base look are no colors */
    CHECK_EQ_INT(exteria_theme_link_parse(colors_of("Odd", NULL, 0x445566), &info), EXTERIA_OK);
    CHECK_EQ_INT(info.has_colors, 0);
    /* a document that is not a fetchable file */
    CHECK_EQ_INT(exteria_theme_link_parse(theme_of("Gone", exteria_tl_new_obj(&arena, "documentEmpty")), &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(info.has_file, 0);
    CHECK_EQ_INT(info.title[0], 0);
    CHECK_EQ_INT(exteria_theme_link_parse(exteria_tl_new_obj(&arena, "themeSettings"), &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_theme_link_parse(NULL, &info), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_theme_link_parse(theme_of("x", NULL), NULL), EXTERIA_E_ARG);
    /* a title that does not fit is cut on a character boundary, never inside a two byte letter */
    memset(long_title, 0, sizeof(long_title));
    for (size_t i = 0; i + 1 < 200; i += 2) memcpy(long_title + i, "\xd0\xaf", 2);
    CHECK_EQ_INT(exteria_theme_link_parse(theme_of(long_title, NULL), &info), EXTERIA_OK);
    CHECK(strlen(info.title) < EXTERIA_THEME_TITLE_MAX);
    CHECK_EQ_INT(strlen(info.title) % 2, 0);
}

int main(void) {
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    test_request();
    test_request_slug_length();
    test_parse();
    exteria_arena_free(&arena);
    return test_finish("test_theme_link");
}
