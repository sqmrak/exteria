#include <string.h>

#include "exteria_id3.h"
#include "test_util.h"

static const uint8_t JPEG[] = {0xFF, 0xD8, 0xFF, 0xE0, 'j', 'f', 'i', 'f', 1, 2, 3};

typedef struct tag_builder {
    uint8_t bytes[4096];
    size_t len;
    uint8_t version;
} tag_builder;

static void put(tag_builder *t, const void *data, size_t len) {
    CHECK(t->len + len <= sizeof(t->bytes));
    memcpy(t->bytes + t->len, data, len);
    t->len += len;
}

static void start(tag_builder *t, uint8_t version, uint8_t flags) {
    uint8_t header[10] = {'I', 'D', '3', 0, 0, 0, 0, 0, 0, 0};
    memset(t, 0, sizeof(*t));
    t->version = version;
    header[3] = version;
    header[5] = flags;
    put(t, header, sizeof(header));
}

static void frame(tag_builder *t, const char *id, uint16_t flags, const uint8_t *body, size_t len) {
    uint8_t header[10];
    size_t n = t->version == 2 ? 6 : 10;
    memcpy(header, id, t->version == 2 ? 3 : 4);
    if (t->version == 2) {
        header[3] = (uint8_t)(len >> 16);
        header[4] = (uint8_t)(len >> 8);
        header[5] = (uint8_t)len;
    } else if (t->version == 4) {
        header[4] = (uint8_t)((len >> 21) & 0x7F);
        header[5] = (uint8_t)((len >> 14) & 0x7F);
        header[6] = (uint8_t)((len >> 7) & 0x7F);
        header[7] = (uint8_t)(len & 0x7F);
        header[8] = (uint8_t)(flags >> 8);
        header[9] = (uint8_t)flags;
    } else {
        header[4] = (uint8_t)(len >> 24);
        header[5] = (uint8_t)(len >> 16);
        header[6] = (uint8_t)(len >> 8);
        header[7] = (uint8_t)len;
        header[8] = (uint8_t)(flags >> 8);
        header[9] = (uint8_t)flags;
    }
    put(t, header, n);
    put(t, body, len);
}

/* the tag size of the header covers everything put after it, plus padding bytes */
static void finish(tag_builder *t, size_t padding) {
    size_t size, i;
    for (i = 0; i < padding; ++i) {
        uint8_t zero = 0;
        put(t, &zero, 1);
    }
    size = t->len - 10;
    t->bytes[6] = (uint8_t)((size >> 21) & 0x7F);
    t->bytes[7] = (uint8_t)((size >> 14) & 0x7F);
    t->bytes[8] = (uint8_t)((size >> 7) & 0x7F);
    t->bytes[9] = (uint8_t)(size & 0x7F);
}

/* an APIC body: encoding, mime, picture type, description (already encoded and ended), then the picture */
static size_t apic(uint8_t *out, uint8_t encoding, const char *mime, uint8_t type, const uint8_t *description, size_t description_len) {
    size_t n = 0;
    out[n++] = encoding;
    memcpy(out + n, mime, strlen(mime) + 1);
    n += strlen(mime) + 1;
    out[n++] = type;
    memcpy(out + n, description, description_len);
    n += description_len;
    memcpy(out + n, JPEG, sizeof(JPEG));
    return n + sizeof(JPEG);
}

static void expect_cover(const tag_builder *t, size_t len) {
    size_t offset = 0, size = 0;
    CHECK_EQ_INT(exteria_id3_cover(t->bytes, len, &offset, &size), EXTERIA_OK);
    CHECK_EQ_INT(size, sizeof(JPEG));
    CHECK(memcmp(t->bytes + offset, JPEG, sizeof(JPEG)) == 0);
}

static void versions(void) {
    tag_builder t;
    uint8_t body[256];
    static const uint8_t title[] = {0, 'S', 'o', 'n', 'g'};
    static const uint8_t latin[] = {'c', 0};
    static const uint8_t utf16[] = {0xFF, 0xFE, 'a', 0, 0, 0};
    size_t n, tag_size = 0;

    start(&t, 3, 0);
    frame(&t, "TIT2", 0, title, sizeof(title));
    n = apic(body, 0, "image/jpeg", 3, latin, sizeof(latin));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 20);
    CHECK_EQ_INT(exteria_id3_tag_size(t.bytes, t.len, &tag_size), EXTERIA_OK);
    CHECK_EQ_INT(tag_size, t.len);
    expect_cover(&t, t.len);

    /* 2.4: synchsafe frame sizes and a description in UTF-16, whose end is two zero bytes on an even position */
    start(&t, 4, 0);
    n = apic(body, 1, "image/jpeg", 3, utf16, sizeof(utf16));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 0);
    expect_cover(&t, t.len);

    /* 2.2: a three letter identifier, a three letter image format and a 24 bit frame size */
    start(&t, 2, 0);
    {
        size_t m = 0;
        body[m++] = 0;
        memcpy(body + m, "JPG", 3);
        m += 3;
        body[m++] = 3;
        body[m++] = 0;
        memcpy(body + m, JPEG, sizeof(JPEG));
        m += sizeof(JPEG);
        frame(&t, "PIC", 0, body, m);
    }
    finish(&t, 4);
    expect_cover(&t, t.len);
}

static void frame_flags(void) {
    tag_builder t;
    uint8_t body[256], wrapped[300];
    static const uint8_t latin[] = {0};
    size_t n;

    /* 2.4 with a group byte and a data length indicator in front of the body */
    start(&t, 4, 0);
    n = apic(body, 0, "image/jpeg", 3, latin, sizeof(latin));
    wrapped[0] = 9;
    wrapped[1] = 0;
    wrapped[2] = 0;
    wrapped[3] = 0;
    wrapped[4] = 0;
    memcpy(wrapped + 5, body, n);
    frame(&t, "APIC", 0x0041, wrapped, n + 5);
    finish(&t, 0);
    expect_cover(&t, t.len);

    /* 2.3 with a group byte */
    start(&t, 3, 0);
    wrapped[0] = 9;
    memcpy(wrapped + 1, body, n);
    frame(&t, "APIC", 0x0020, wrapped, n + 1);
    finish(&t, 0);
    expect_cover(&t, t.len);

    /* a compressed picture cannot be read, and the tag then has none */
    start(&t, 3, 0);
    frame(&t, "APIC", 0x0080, body, n);
    finish(&t, 0);
    {
        size_t offset = 1, size = 1;
        CHECK_EQ_INT(exteria_id3_cover(t.bytes, t.len, &offset, &size), EXTERIA_E_NOTFOUND);
        CHECK_EQ_INT(offset, 0);
        CHECK_EQ_INT(size, 0);
    }
}

static void extended_header(void) {
    tag_builder t;
    uint8_t body[256];
    static const uint8_t latin[] = {0};
    static const uint8_t extended23[] = {0, 0, 0, 6, 0, 0, 0, 0, 0, 0};
    static const uint8_t extended24[] = {0, 0, 0, 6, 1, 0};
    size_t n = apic(body, 0, "image/png", 3, latin, sizeof(latin));

    start(&t, 3, 0x40);
    put(&t, extended23, sizeof(extended23));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 0);
    expect_cover(&t, t.len);

    start(&t, 4, 0x40);
    put(&t, extended24, sizeof(extended24));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 0);
    expect_cover(&t, t.len);
}

static void picture_choice(void) {
    tag_builder t;
    uint8_t body[256];
    static const uint8_t latin[] = {0};
    size_t n, offset = 0, size = 0;

    /* the front cover wins over an earlier picture of another kind */
    start(&t, 3, 0);
    n = apic(body, 0, "image/jpeg", 0, latin, sizeof(latin));
    body[n - sizeof(JPEG)] = 0xAA;
    frame(&t, "APIC", 0, body, n);
    n = apic(body, 0, "image/jpeg", 3, latin, sizeof(latin));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 0);
    CHECK_EQ_INT(exteria_id3_cover(t.bytes, t.len, &offset, &size), EXTERIA_OK);
    CHECK_EQ_INT(t.bytes[offset], 0xFF);

    /* with no front cover the first picture is taken */
    start(&t, 3, 0);
    n = apic(body, 0, "image/jpeg", 4, latin, sizeof(latin));
    body[n - sizeof(JPEG)] = 0xAA;
    frame(&t, "APIC", 0, body, n);
    n = apic(body, 0, "image/jpeg", 0, latin, sizeof(latin));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 0);
    CHECK_EQ_INT(exteria_id3_cover(t.bytes, t.len, &offset, &size), EXTERIA_OK);
    CHECK_EQ_INT(t.bytes[offset], 0xAA);

    /* a link is not a picture */
    start(&t, 3, 0);
    n = apic(body, 0, "-->", 3, latin, sizeof(latin));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 0);
    CHECK_EQ_INT(exteria_id3_cover(t.bytes, t.len, &offset, &size), EXTERIA_E_NOTFOUND);
}

static void cut_and_broken(void) {
    tag_builder t;
    uint8_t body[256];
    static const uint8_t latin[] = {0};
    static const uint8_t title[] = {0, 'S'};
    size_t n, tag_size = 0, offset = 7, size = 7;

    start(&t, 3, 0);
    frame(&t, "TIT2", 0, title, sizeof(title));
    n = apic(body, 0, "image/jpeg", 3, latin, sizeof(latin));
    frame(&t, "APIC", 0, body, n);
    finish(&t, 0);
    CHECK_EQ_INT(exteria_id3_tag_size(t.bytes, 10, &tag_size), EXTERIA_OK);
    CHECK_EQ_INT(tag_size, t.len);
    /* every cut of the tag asks for more bytes, and the whole tag answers */
    for (n = 10; n < t.len; ++n) {
        CHECK_EQ_INT(exteria_id3_cover(t.bytes, n, &offset, &size), EXTERIA_E_TRUNCATED);
        CHECK_EQ_INT(offset, 0);
        CHECK_EQ_INT(size, 0);
    }
    expect_cover(&t, t.len);
    CHECK_EQ_INT(exteria_id3_cover(t.bytes, 9, &offset, &size), EXTERIA_E_TRUNCATED);

    /* a frame that claims more than the tag holds */
    start(&t, 3, 0);
    n = apic(body, 0, "image/jpeg", 3, latin, sizeof(latin));
    frame(&t, "APIC", 0, body, n);
    t.bytes[14] = 0x7F;
    finish(&t, 0);
    CHECK_EQ_INT(exteria_id3_cover(t.bytes, t.len, &offset, &size), EXTERIA_E_MALFORMED);

    /* a tag that is all padding, and one with no frames at all */
    start(&t, 3, 0);
    finish(&t, 5);
    CHECK_EQ_INT(exteria_id3_cover(t.bytes, t.len, &offset, &size), EXTERIA_E_NOTFOUND);
    start(&t, 3, 0);
    finish(&t, 0);
    CHECK_EQ_INT(exteria_id3_cover(t.bytes, t.len, &offset, &size), EXTERIA_E_NOTFOUND);
}

static void headers(void) {
    uint8_t head[10] = {'I', 'D', '3', 3, 0, 0, 0, 0, 1, 0};
    size_t tag_size = 5, offset, size;
    uint8_t plain[10] = {'R', 'I', 'F', 'F', 0, 0, 0, 0, 0, 0};

    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, &tag_size), EXTERIA_OK);
    CHECK_EQ_INT(tag_size, 10 + 128);
    CHECK_EQ_INT(exteria_id3_tag_size(plain, 10, &tag_size), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(tag_size, 0);
    CHECK_EQ_INT(exteria_id3_tag_size(head, 9, &tag_size), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_id3_tag_size(NULL, 10, &tag_size), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, NULL), EXTERIA_E_ARG);
    head[8] = 0x80;
    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, &tag_size), EXTERIA_E_MALFORMED);
    head[8] = 1;
    head[3] = 5;
    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, &tag_size), EXTERIA_E_MALFORMED);
    head[3] = 3;
    head[5] = 0x80;
    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, &tag_size), EXTERIA_E_UNSUPPORTED);
    head[3] = 2;
    head[5] = 0x40;
    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, &tag_size), EXTERIA_E_UNSUPPORTED);
    head[3] = 3;
    head[5] = 0;
    /* one mebibyte of tag and the ten bytes of its header is over the bound; the bound itself is allowed */
    head[6] = 0;
    head[7] = 0x40;
    head[8] = 0;
    head[9] = 0;
    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, &tag_size), EXTERIA_E_LIMIT);
    head[7] = 0x3F;
    head[8] = 0x7F;
    head[9] = 0x76;
    CHECK_EQ_INT(exteria_id3_tag_size(head, 10, &tag_size), EXTERIA_OK);
    CHECK_EQ_INT(tag_size, EXTERIA_ID3_TAG_MAX);
    CHECK_EQ_INT(exteria_id3_cover(NULL, 10, &offset, &size), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_id3_cover(head, 10, NULL, &size), EXTERIA_E_ARG);
}

int main(void) {
    versions();
    frame_flags();
    extended_header();
    picture_choice();
    cut_and_broken();
    headers();
    return test_finish("test_id3");
}
