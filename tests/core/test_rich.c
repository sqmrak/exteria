#include "test_util.h"
#include "exteria_rich.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}

static void set_i32(exteria_tl_value *v, const char *f, int32_t x) { CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, f, x), EXTERIA_OK); }
static void set_i64(exteria_tl_value *v, const char *f, int64_t x) { CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, f, x), EXTERIA_OK); }
static void set_str(exteria_tl_value *v, const char *f, const char *x) { CHECK_EQ_INT(exteria_tl_set_str(&arena, v, f, x), EXTERIA_OK); }
static void set_flag(exteria_tl_value *v, const char *f) { CHECK_EQ_INT(exteria_tl_set_flag(v, f), EXTERIA_OK); }
static void set(exteria_tl_value *v, const char *f, exteria_tl_value *x) { CHECK_EQ_INT(exteria_tl_set(v, f, x), EXTERIA_OK); }

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *v = exteria_tl_new_vec(&arena, n);
    CHECK(v != NULL);
    for (uint32_t i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(v, i, items[i]), EXTERIA_OK);
    return v;
}

static exteria_tl_value *plain(const char *text) {
    exteria_tl_value *t = obj("textPlain");
    set_str(t, "text", text);
    return t;
}

static exteria_tl_value *wrap(const char *name, exteria_tl_value *inner) {
    exteria_tl_value *t = obj(name);
    set(t, "text", inner);
    return t;
}

static exteria_tl_value *concat(exteria_tl_value **parts, uint32_t n) {
    exteria_tl_value *t = obj("textConcat");
    set(t, "texts", vec_of(parts, n));
    return t;
}

static exteria_tl_value *text_block(const char *name, exteria_tl_value *text) {
    exteria_tl_value *b = obj(name);
    set(b, "text", text);
    return b;
}

static exteria_tl_value *caption(const char *text) {
    exteria_tl_value *c = obj("pageCaption");
    set(c, "text", plain(text));
    set(c, "credit", obj("textEmpty"));
    return c;
}

static exteria_tl_value *photo(int64_t id) {
    static const uint8_t reference[] = {9, 8, 7};
    exteria_tl_value *p = obj("photo"), *size = obj("photoSize"), *sizes[1];
    set_i64(p, "id", id);
    set_i64(p, "access_hash", id + 1);
    CHECK_EQ_INT(exteria_tl_set_bytes(&arena, p, "file_reference", reference, sizeof(reference)), EXTERIA_OK);
    set_i32(p, "date", 100);
    set_str(size, "type", "x");
    set_i32(size, "w", 800);
    set_i32(size, "h", 600);
    set_i32(size, "size", 50000);
    sizes[0] = size;
    set(p, "sizes", vec_of(sizes, 1));
    set_i32(p, "dc_id", 2);
    return p;
}

static exteria_tl_value *cell(const char *text, int header, int32_t colspan, int32_t rowspan) {
    exteria_tl_value *c = obj("pageTableCell");
    if (text) set(c, "text", plain(text));
    if (header) set_flag(c, "header");
    if (colspan > 1) set_i32(c, "colspan", colspan);
    if (rowspan > 1) set_i32(c, "rowspan", rowspan);
    return c;
}

static exteria_tl_value *row_of(exteria_tl_value **cells, uint32_t n) {
    exteria_tl_value *r = obj("pageTableRow");
    set(r, "cells", vec_of(cells, n));
    return r;
}

static exteria_tl_value *rich_message_of(exteria_tl_value **blocks, uint32_t n, exteria_tl_value **photos, uint32_t photo_count) {
    exteria_tl_value *m = obj("message"), *peer = obj("peerUser"), *rich = obj("richMessage");
    set_i64(peer, "user_id", 5);
    set_i32(m, "id", 7);
    set(m, "peer_id", peer);
    set_i32(m, "date", 1000);
    set_str(m, "message", "");
    set(rich, "blocks", vec_of(blocks, n));
    set(rich, "photos", vec_of(photos, photo_count));
    set(rich, "documents", vec_of(NULL, 0));
    set(m, "rich_message", rich);
    return m;
}

static int block_text_is(const exteria_rich_doc *doc, const exteria_rich_block *b, const char *text) {
    return b->text_length == strlen(text) && !memcmp(doc->text + b->text_offset, text, b->text_length);
}

static void test_article(void) {
    exteria_rich_doc *doc = calloc(1, sizeof(*doc));
    exteria_tl_value *blocks[12], *parts[4], *items[2], *item, *rows[2], *cells[3], *photos[1], *details_blocks[1], *link;
    const exteria_rich_block *b;
    const exteria_entity *e;
    CHECK(doc != NULL);
    blocks[0] = text_block("pageBlockTitle", plain("Title"));
    /* Cyrillic is one UTF-16 unit a letter and the emoji two, so the link starts at unit 6 and covers 2 units */
    link = wrap("textUrl", plain("\xF0\x9F\x98\x80"));
    set_str(link, "url", "https://example.org/a");
    set_i64(link, "webpage_id", 0);
    parts[0] = plain("\xD0\x9F\xD1\x80\xD0\xB8 ");
    parts[1] = wrap("textBold", plain("ab"));
    parts[2] = link;
    parts[3] = plain("!");
    blocks[1] = text_block("pageBlockParagraph", concat(parts, 4));
    items[0] = obj("pageListOrderedItemText");
    set_str(items[0], "num", "IV.");
    set(items[0], "text", plain("first"));
    items[1] = obj("pageListOrderedItemText");
    set_flag(items[1], "checkbox");
    set_flag(items[1], "checked");
    set(items[1], "text", plain("second"));
    blocks[2] = obj("pageBlockOrderedList");
    set_i32(blocks[2], "start", 3);
    set(blocks[2], "items", vec_of(items, 2));
    blocks[3] = obj("pageBlockBlockquote");
    set(blocks[3], "text", plain("quoted"));
    set(blocks[3], "caption", plain("who"));
    /* row 0: a header over two columns and a cell two rows tall; row 1 starts in the first column and skips the third */
    cells[0] = cell("Head", 1, 2, 1);
    cells[1] = cell("Tall", 0, 1, 2);
    rows[0] = row_of(cells, 2);
    cells[0] = cell("a", 0, 1, 1);
    cells[1] = cell("b", 0, 1, 1);
    cells[2] = cell("c", 0, 1, 1);
    rows[1] = row_of(cells, 3);
    blocks[4] = obj("pageBlockTable");
    set_flag(blocks[4], "bordered");
    set(blocks[4], "title", obj("textEmpty"));
    set(blocks[4], "rows", vec_of(rows, 2));
    blocks[5] = obj("pageBlockPhoto");
    set_i64(blocks[5], "photo_id", 40);
    set(blocks[5], "caption", caption("pic"));
    /* a photo the message does not carry shows nothing, and its caption still does */
    blocks[6] = obj("pageBlockPhoto");
    set_i64(blocks[6], "photo_id", 41);
    set(blocks[6], "caption", caption("lost"));
    blocks[7] = obj("pageBlockDivider");
    details_blocks[0] = text_block("pageBlockParagraph", plain("inside"));
    blocks[8] = obj("pageBlockDetails");
    set(blocks[8], "title", plain("More"));
    set(blocks[8], "blocks", vec_of(details_blocks, 1));
    /* an empty paragraph leaves no block, and broken UTF-8 becomes U+FFFD */
    blocks[9] = text_block("pageBlockParagraph", obj("textEmpty"));
    blocks[10] = text_block("pageBlockParagraph", plain("x\xFFy"));
    item = obj("pageListItemText");
    set(item, "text", plain("dot"));
    blocks[11] = obj("pageBlockList");
    set(blocks[11], "items", vec_of(&item, 1));
    photos[0] = photo(40);
    CHECK_EQ_INT(exteria_rich_read(rich_message_of(blocks, 12, photos, 1), doc), EXTERIA_OK);
    CHECK_EQ_INT(doc->truncated, 0);
    CHECK_EQ_INT(doc->block_count, 20);

    b = &doc->blocks[0];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_HEADING);
    CHECK_EQ_INT(b->level, 1);
    CHECK(block_text_is(doc, b, "Title"));

    b = &doc->blocks[1];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_PARAGRAPH);
    CHECK(block_text_is(doc, b, "\xD0\x9F\xD1\x80\xD0\xB8 ab\xF0\x9F\x98\x80!"));
    CHECK_EQ_INT(b->entity_count, 2);
    e = &doc->entities[b->entity_start];
    CHECK_EQ_INT(e->kind, EXTERIA_ENTITY_BOLD);
    CHECK_EQ_INT(e->offset, 4);
    CHECK_EQ_INT(e->length, 2);
    e = &doc->entities[b->entity_start + 1];
    CHECK_EQ_INT(e->kind, EXTERIA_ENTITY_TEXT_URL);
    CHECK_EQ_INT(e->offset, 6);
    CHECK_EQ_INT(e->length, 2);
    CHECK(e->url_offset >= 0 && !strcmp(doc->urls + e->url_offset, "https://example.org/a"));

    b = &doc->blocks[2];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_LIST_ITEM);
    CHECK(!strcmp(b->label, "IV."));
    CHECK(block_text_is(doc, b, "first"));
    b = &doc->blocks[3];
    CHECK(!strcmp(b->label, "4."));
    CHECK_EQ_INT(b->flags, EXTERIA_RICH_CHECKBOX | EXTERIA_RICH_CHECKED);

    b = &doc->blocks[4];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_PARAGRAPH);
    CHECK_EQ_INT(b->quote, 1);
    b = &doc->blocks[5];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_CAPTION);
    CHECK_EQ_INT(b->quote, 1);
    CHECK(block_text_is(doc, b, "who"));

    b = &doc->blocks[6];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_TABLE);
    CHECK_EQ_INT(b->quote, 0);
    CHECK_EQ_INT(b->row, 2);
    CHECK_EQ_INT(b->column, 4);
    CHECK_EQ_INT(b->flags, EXTERIA_RICH_BORDERED);
    CHECK_EQ_INT(b->text_length, 0);
    b = &doc->blocks[7];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_CELL);
    CHECK_EQ_INT(b->column, 0);
    CHECK_EQ_INT(b->colspan, 2);
    CHECK_EQ_INT(b->flags, EXTERIA_RICH_HEADER_CELL);
    b = &doc->blocks[8];
    CHECK_EQ_INT(b->column, 2);
    CHECK_EQ_INT(b->rowspan, 2);
    b = &doc->blocks[9];
    CHECK_EQ_INT(b->row, 1);
    CHECK_EQ_INT(b->column, 0);
    b = &doc->blocks[10];
    CHECK_EQ_INT(b->column, 1);
    /* the third cell of row 1 finds column 2 held by the tall cell and moves past it */
    b = &doc->blocks[11];
    CHECK_EQ_INT(b->column, 3);
    CHECK(block_text_is(doc, b, "c"));

    b = &doc->blocks[12];
    CHECK_EQ_INT(b->kind, EXTERIA_RICH_MEDIA);
    CHECK_EQ_INT(b->media, 0);
    CHECK_EQ_INT(doc->media_count, 1);
    CHECK_EQ_INT(doc->media[0].kind, EXTERIA_PREVIEW_PHOTO);
    CHECK_EQ_INT(doc->media[0].width, 800);
    CHECK(doc->media[0].ref.id == 40);
    CHECK(block_text_is(doc, &doc->blocks[13], "pic"));
    CHECK_EQ_INT(doc->blocks[14].kind, EXTERIA_RICH_CAPTION);
    CHECK(block_text_is(doc, &doc->blocks[14], "lost"));

    CHECK_EQ_INT(doc->blocks[15].kind, EXTERIA_RICH_DIVIDER);
    CHECK_EQ_INT(doc->blocks[16].kind, EXTERIA_RICH_DETAILS);
    CHECK_EQ_INT(doc->blocks[17].kind, EXTERIA_RICH_PARAGRAPH);
    CHECK_EQ_INT(doc->blocks[17].indent, 1);
    CHECK(block_text_is(doc, &doc->blocks[17], "inside"));
    CHECK(block_text_is(doc, &doc->blocks[18], "x\xEF\xBF\xBDy"));
    CHECK_EQ_INT(doc->blocks[19].kind, EXTERIA_RICH_LIST_ITEM);
    CHECK(!strcmp(doc->blocks[19].label, "\xE2\x80\xA2"));
    free(doc);
}

static void test_extras(void) {
    exteria_rich_doc *doc = calloc(1, sizeof(*doc));
    exteria_tl_value *blocks[6], *geo = obj("geoPoint"), *chat = obj("channel"), *articles[2], *inner[1];
    CHECK(doc != NULL);
    blocks[0] = obj("pageBlockMap");
    CHECK_EQ_INT(exteria_tl_set_f64(&arena, geo, "lat", 55.75), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_f64(&arena, geo, "long", 37.62), EXTERIA_OK);
    set_i64(geo, "access_hash", 1);
    set(blocks[0], "geo", geo);
    set_i32(blocks[0], "zoom", 12);
    set_i32(blocks[0], "w", 400);
    set_i32(blocks[0], "h", 200);
    set(blocks[0], "caption", caption("here"));
    /* an embed with only html: the address comes from the frame, past a data: source before it */
    blocks[1] = obj("pageBlockEmbed");
    set_str(blocks[1], "html", "<img src='data:x'><iframe SRC=\"//www.youtube.com/embed/abc\"></iframe>");
    set(blocks[1], "caption", caption(""));
    blocks[2] = obj("pageBlockChannel");
    set_str(chat, "title", "News");
    set_str(chat, "username", "news");
    set(blocks[2], "channel", chat);
    articles[0] = obj("pageRelatedArticle");
    set_str(articles[0], "url", "https://a.example/1");
    set_str(articles[0], "title", "One");
    set_str(articles[0], "description", "about one");
    articles[1] = obj("pageRelatedArticle");
    set_str(articles[1], "url", "https://a.example/2");
    blocks[3] = obj("pageBlockRelatedArticles");
    set(blocks[3], "title", plain("Related"));
    set(blocks[3], "articles", vec_of(articles, 2));
    inner[0] = text_block("pageBlockParagraph", plain("hidden"));
    blocks[4] = obj("pageBlockDetails");
    set_flag(blocks[4], "open");
    set(blocks[4], "title", plain("Open one"));
    set(blocks[4], "blocks", vec_of(inner, 1));
    /* an embed whose html has no frame shows its caption alone */
    blocks[5] = obj("pageBlockEmbed");
    set_str(blocks[5], "html", "<b>bold</b>");
    set(blocks[5], "caption", caption("only words"));
    CHECK_EQ_INT(exteria_rich_read(rich_message_of(blocks, 6, NULL, 0), doc), EXTERIA_OK);
    CHECK_EQ_INT(doc->block_count, 11);
    CHECK_EQ_INT(doc->blocks[0].kind, EXTERIA_RICH_MEDIA);
    CHECK_EQ_INT(doc->blocks[0].level, 12);
    CHECK_EQ_INT(doc->media[0].kind, EXTERIA_PREVIEW_LOCATION);
    CHECK_EQ_INT(doc->media[0].location.valid, 1);
    CHECK(doc->media[0].location.latitude > 55.7 && doc->media[0].location.latitude < 55.8);
    CHECK_EQ_INT(doc->media[0].width, 400);
    CHECK(block_text_is(doc, &doc->blocks[1], "here"));
    CHECK(block_text_is(doc, &doc->blocks[2], "\xF0\x9F\x94\x97 //www.youtube.com/embed/abc"));
    CHECK_EQ_INT(doc->blocks[2].entity_count, 1);
    CHECK(!strcmp(doc->urls + doc->entities[doc->blocks[2].entity_start].url_offset, "https://www.youtube.com/embed/abc"));
    CHECK(block_text_is(doc, &doc->blocks[3], "\xF0\x9F\x93\xA2 News"));
    CHECK_EQ_INT(doc->blocks[3].entity_count, 2);
    CHECK(!strcmp(doc->urls + doc->entities[doc->blocks[3].entity_start + 1].url_offset, "https://t.me/news"));
    CHECK_EQ_INT(doc->blocks[4].kind, EXTERIA_RICH_HEADING);
    CHECK(block_text_is(doc, &doc->blocks[5], "One"));
    CHECK_EQ_INT(doc->blocks[6].kind, EXTERIA_RICH_CAPTION);
    CHECK_EQ_INT(doc->blocks[6].indent, 1);
    CHECK(block_text_is(doc, &doc->blocks[7], "https://a.example/2"));
    CHECK_EQ_INT(doc->blocks[8].kind, EXTERIA_RICH_DETAILS);
    CHECK_EQ_INT(doc->blocks[8].flags, EXTERIA_RICH_OPEN);
    CHECK_EQ_INT(doc->blocks[9].indent, 1);
    CHECK(block_text_is(doc, &doc->blocks[10], "only words"));
    free(doc);
}

static void test_bounds(void) {
    exteria_rich_doc *doc = calloc(1, sizeof(*doc));
    exteria_tl_value *blocks[EXTERIA_RICH_BLOCKS_MAX + 4], *m;
    CHECK(doc != NULL);
    for (uint32_t i = 0; i < EXTERIA_RICH_BLOCKS_MAX + 4; ++i) blocks[i] = text_block("pageBlockParagraph", plain("p"));
    CHECK_EQ_INT(exteria_rich_read(rich_message_of(blocks, EXTERIA_RICH_BLOCKS_MAX + 4, NULL, 0), doc), EXTERIA_OK);
    CHECK_EQ_INT(doc->block_count, EXTERIA_RICH_BLOCKS_MAX);
    CHECK_EQ_INT(doc->truncated, 1);
    /* a message without rich_message, and one whose blocks show nothing */
    m = obj("message");
    set_i32(m, "id", 1);
    CHECK_EQ_INT(exteria_rich_read(m, doc), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(doc->block_count, 0);
    blocks[0] = obj("pageBlockUnsupported");
    CHECK_EQ_INT(exteria_rich_read(rich_message_of(blocks, 1, NULL, 0), doc), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_rich_read(NULL, doc), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_rich_read(m, NULL), EXTERIA_E_ARG);
    free(doc);
}

int main(void) {
    exteria_arena_init(&arena, 8u << 20);
    test_article();
    test_extras();
    test_bounds();
    exteria_arena_free(&arena);
    if (g_failures) {
        fprintf(stderr, "test_rich: %d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("test_rich: %d checks passed\n", g_checks);
    return 0;
}
