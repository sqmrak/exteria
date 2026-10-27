#include "test_util.h"
#include "exteria_translate_html.h"

#include <string.h>

/* ascii and a few BMP units are written as char strings, widened here */
static size_t widen(const char *text, uint16_t *out) {
    size_t n = strlen(text), i;
    for (i = 0; i < n; ++i) out[i] = (uint16_t)(unsigned char)text[i];
    return n;
}

static int same(const uint16_t *units, size_t len, const char *text) {
    size_t i;
    if (strlen(text) != len) return 0;
    for (i = 0; i < len; ++i) {
        if (units[i] != (uint16_t)(unsigned char)text[i]) return 0;
    }
    return 1;
}

static void encode_case(const char *text, const exteria_th_span *spans, size_t count, const char *expected) {
    uint16_t in[256], out[512];
    size_t len = widen(text, in), out_len = 0;
    CHECK_EQ_INT(exteria_th_encode(in, len, spans, count, out, 512, &out_len), EXTERIA_OK);
    CHECK(same(out, out_len, expected));
}

static void test_encode(void) {
    exteria_th_span one[] = {{EXTERIA_TH_BOLD, 6, 5}};
    exteria_th_span nested[] = {{EXTERIA_TH_ITALIC, 2, 3}, {EXTERIA_TH_BOLD, 0, 8}};
    exteria_th_span cross[] = {{EXTERIA_TH_BOLD, 0, 4}, {EXTERIA_TH_ITALIC, 2, 4}};
    exteria_th_span all_kinds[] = {{EXTERIA_TH_BOLD, 0, 1}, {EXTERIA_TH_UNDERLINE, 1, 1}, {EXTERIA_TH_STRIKE, 2, 1}, {EXTERIA_TH_CODE, 3, 1}, {EXTERIA_TH_LINK, 4, 1}};
    exteria_th_span bad[] = {{EXTERIA_TH_BOLD, 0, 0}, {EXTERIA_TH_BOLD, 3, 99}, {99, 0, 2}, {EXTERIA_TH_BOLD, 9, 1}, {EXTERIA_TH_ITALIC, 0, 2}};
    exteria_th_span same_end[] = {{EXTERIA_TH_BOLD, 0, 4}, {EXTERIA_TH_ITALIC, 2, 2}};
    encode_case("hello world", one, 1, "hello <b>world</b>");
    encode_case("hello world", NULL, 0, "hello world");
    encode_case("abcdefgh", nested, 2, "<b>ab<i>cde</i>fgh</b>");
    /* spans that cross close and open again, so the tags stay nested */
    encode_case("abcdef", cross, 2, "<b>ab<i>cd</i></b><i>ef</i>");
    encode_case("abcde", all_kinds, 5, "<b>a</b><u>b</u><s>c</s><tt>d</tt><a>e</a>");
    encode_case("abcd", bad, 5, "<i>ab</i>cd");
    encode_case("abcd", same_end, 2, "<b>ab<i>cd</i></b>");
}

static void test_encode_text_rules(void) {
    uint16_t in[8] = {'a', '<', 'b'}, out[32];
    size_t out_len = 0;
    CHECK_EQ_INT(exteria_th_encode(in, 3, NULL, 0, out, 32, &out_len), EXTERIA_OK);
    CHECK_EQ_INT(out_len, 3);
    CHECK_EQ_INT(out[1], 0x2027);
    /* a surrogate pair passes through untouched */
    in[0] = 0xD83D;
    in[1] = 0xDE00;
    CHECK_EQ_INT(exteria_th_encode(in, 2, NULL, 0, out, 32, &out_len), EXTERIA_OK);
    CHECK_EQ_INT(out[0], 0xD83D);
    CHECK_EQ_INT(out[1], 0xDE00);
}

static void test_encode_bounds(void) {
    uint16_t in[16], out[8];
    size_t out_len = 99;
    exteria_th_span span = {EXTERIA_TH_BOLD, 0, 4};
    widen("abcd", in);
    CHECK_EQ_INT(exteria_th_encode(in, 4, &span, 1, out, 8, &out_len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_th_encode(in, 4, &span, 1, out, 0, &out_len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_th_encode(NULL, 4, NULL, 0, out, 8, &out_len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_th_encode(in, EXTERIA_TH_TEXT_MAX + 1u, NULL, 0, out, 8, &out_len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_th_encode(in, 4, &span, EXTERIA_TH_SPAN_MAX + 1u, out, 8, &out_len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(out_len, 0);
}

static exteria_status decode_case(const char *markup, char *plain, size_t plain_cap, exteria_th_span *spans, size_t *count) {
    uint16_t in[512], out[512];
    size_t len = widen(markup, in), out_len = 0, i;
    exteria_status status = exteria_th_decode(in, len, out, 512, &out_len, spans, 16, count);
    for (i = 0; i < out_len && i + 1 < plain_cap; ++i) plain[i] = (char)out[i];
    plain[i < plain_cap ? i : plain_cap - 1] = 0;
    return status;
}

static void test_decode(void) {
    char plain[256];
    exteria_th_span spans[16];
    size_t count = 0;
    CHECK_EQ_INT(decode_case("hello <b>world</b>", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "hello world"));
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(spans[0].kind, EXTERIA_TH_BOLD);
    CHECK_EQ_INT(spans[0].offset, 6);
    CHECK_EQ_INT(spans[0].length, 5);
    /* a translator changes the case, pads the brackets and adds attributes */
    CHECK_EQ_INT(decode_case("< B >x</ B >< i class=\"y\">z</i >", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "xz"));
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(spans[0].kind, EXTERIA_TH_BOLD);
    CHECK_EQ_INT(spans[1].kind, EXTERIA_TH_ITALIC);
    CHECK_EQ_INT(spans[1].offset, 1);
    CHECK_EQ_INT(decode_case("<strong>a</strong><em>b</em><del>c</del><code>d</code><a href=\"x\">e</a>", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "abcde"));
    CHECK_EQ_INT(count, 5);
    CHECK_EQ_INT(spans[4].kind, EXTERIA_TH_LINK);
}

static void test_decode_nesting(void) {
    char plain[256];
    exteria_th_span spans[16];
    size_t count = 0;
    /* an outer span comes before the inner one that starts at the same place */
    CHECK_EQ_INT(decode_case("<b><i>ab</i>c</b>", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "abc"));
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(spans[0].kind, EXTERIA_TH_BOLD);
    CHECK_EQ_INT(spans[0].length, 3);
    CHECK_EQ_INT(spans[1].kind, EXTERIA_TH_ITALIC);
    CHECK_EQ_INT(spans[1].length, 2);
    /* a close tag that does not match the innermost one closes what is above it too */
    CHECK_EQ_INT(decode_case("<b>a<i>b</b>c</i>", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "abc"));
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(spans[0].kind, EXTERIA_TH_BOLD);
    CHECK_EQ_INT(spans[0].length, 2);
    CHECK_EQ_INT(spans[1].kind, EXTERIA_TH_ITALIC);
    CHECK_EQ_INT(spans[1].length, 1);
    /* a close with no open is dropped, an open with no close ends with the text */
    CHECK_EQ_INT(decode_case("a</b>b<u>c", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "abc"));
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(spans[0].kind, EXTERIA_TH_UNDERLINE);
    CHECK_EQ_INT(spans[0].offset, 2);
    CHECK_EQ_INT(spans[0].length, 1);
    /* an empty pair makes no span */
    CHECK_EQ_INT(decode_case("a<b></b>b", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
}

static void test_decode_text(void) {
    char plain[256];
    exteria_th_span spans[16];
    size_t count = 0;
    CHECK_EQ_INT(decode_case("a &amp; b &lt; c &gt; &quot;d&quot; &#39;e&#39; &#x41;&#66; &nbsp;", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strncmp(plain, "a & b < c > \"d\" 'e' AB ", 23));
    /* a reference that is none stays as typed */
    CHECK_EQ_INT(decode_case("fish &chips; &#; & x &#0;", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "fish &chips; &#; & x &#0;"));
    /* a bracket that opens no tag is text */
    CHECK_EQ_INT(decode_case("1 < 2 and 3 <", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "1 < 2 and 3 <"));
    CHECK_EQ_INT(decode_case("a<br>b<br/>c<BR />d", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "a\nb\nc\nd"));
    CHECK_EQ_INT(decode_case("a<span style=\"x\">b</span><font>c</font>", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "abc"));
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(decode_case("last\n", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "last"));
    CHECK_EQ_INT(decode_case("<b>last\n</b>", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "last"));
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(spans[0].length, 4);
}

static void test_decode_spaces(void) {
    char plain[256];
    exteria_th_span spans[16];
    size_t count = 0;
    /* one of the two spaces around a tag is the translator's */
    CHECK_EQ_INT(decode_case("a <b> c</b> d", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "a c d"));
    CHECK_EQ_INT(spans[0].offset, 2);
    CHECK_EQ_INT(spans[0].length, 1);
    CHECK_EQ_INT(decode_case("a <b>c </b> d", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "a c d"));
    CHECK_EQ_INT(spans[0].length, 1);
    /* a single space is the author's */
    CHECK_EQ_INT(decode_case("a <b>c</b> d", plain, sizeof(plain), spans, &count), EXTERIA_OK);
    CHECK(!strcmp(plain, "a c d"));
}

static void test_decode_special_units(void) {
    uint16_t in[8] = {'a', 0x2027, 'b', 0x2029, 'c'}, out[16];
    exteria_th_span spans[4];
    size_t out_len = 0, count = 0;
    CHECK_EQ_INT(exteria_th_decode(in, 5, out, 16, &out_len, spans, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(out_len, 5);
    CHECK_EQ_INT(out[1], '<');
    CHECK_EQ_INT(out[3], '\n');
    /* numeric references above the BMP become a surrogate pair */
    {
        const char *text = "&#128512;";
        uint16_t emoji[16];
        size_t len = widen(text, emoji);
        CHECK_EQ_INT(exteria_th_decode(emoji, len, out, 16, &out_len, spans, 4, &count), EXTERIA_OK);
        CHECK_EQ_INT(out_len, 2);
        CHECK_EQ_INT(out[0], 0xD83D);
        CHECK_EQ_INT(out[1], 0xDE00);
    }
}

static void test_decode_bounds(void) {
    uint16_t in[64], out[4];
    exteria_th_span spans[2];
    size_t out_len = 9, count = 9, len = widen("<b>abcdefghij</b>", in);
    CHECK_EQ_INT(exteria_th_decode(in, len, out, 4, &out_len, spans, 2, &count), EXTERIA_E_LIMIT);
    len = widen("<b>a</b><i>b</i><u>c</u>", in);
    {
        uint16_t big[8];
        CHECK_EQ_INT(exteria_th_decode(in, len, big, 8, &out_len, spans, 2, &count), EXTERIA_E_LIMIT);
    }
    CHECK_EQ_INT(exteria_th_decode(in, len, NULL, 4, &out_len, spans, 2, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_th_decode(in, len, out, 0, &out_len, spans, 2, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_th_decode(NULL, 3, out, 4, &out_len, spans, 2, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_th_decode(in, EXTERIA_TH_TEXT_MAX * 2u + 1u, out, 4, &out_len, spans, 2, &count), EXTERIA_E_LIMIT);
    /* an empty markup is an empty text */
    {
        uint16_t big[8];
        CHECK_EQ_INT(exteria_th_decode(in, 0, big, 8, &out_len, spans, 2, &count), EXTERIA_OK);
        CHECK_EQ_INT(out_len, 0);
        CHECK_EQ_INT(count, 0);
    }
    /* more tags open than the stack holds do not crash or leak spans */
    {
        uint16_t deep[400], flat[400];
        exteria_th_span many[EXTERIA_TH_SPAN_MAX];
        size_t n = 0, i, got = 0, flat_len = 0;
        for (i = 0; i < 80; ++i) {
            deep[n++] = '<';
            deep[n++] = 'b';
            deep[n++] = '>';
        }
        deep[n++] = 'x';
        CHECK_EQ_INT(exteria_th_decode(deep, n, flat, 400, &flat_len, many, EXTERIA_TH_SPAN_MAX, &got), EXTERIA_OK);
        CHECK_EQ_INT(flat_len, 1);
        CHECK(got <= 64);
    }
}

static void test_round_trip(void) {
    const char *text = "bold italic mix code link end";
    exteria_th_span spans[] = {{EXTERIA_TH_BOLD, 0, 4}, {EXTERIA_TH_ITALIC, 5, 6}, {EXTERIA_TH_BOLD, 12, 3}, {EXTERIA_TH_CODE, 17, 4}, {EXTERIA_TH_LINK, 22, 4}};
    uint16_t in[64], markup[256], out[256];
    exteria_th_span back[16];
    size_t len = widen(text, in), markup_len = 0, out_len = 0, count = 0, i;
    CHECK_EQ_INT(exteria_th_encode(in, len, spans, 5, markup, 256, &markup_len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_th_decode(markup, markup_len, out, 256, &out_len, back, 16, &count), EXTERIA_OK);
    CHECK_EQ_INT(out_len, len);
    CHECK_MEM(out, in, len * sizeof(uint16_t));
    CHECK_EQ_INT(count, 5);
    for (i = 0; i < count; ++i) {
        CHECK_EQ_INT(back[i].kind, spans[i].kind);
        CHECK_EQ_INT(back[i].offset, spans[i].offset);
        CHECK_EQ_INT(back[i].length, spans[i].length);
    }
}

int main(void) {
    test_encode();
    test_encode_text_rules();
    test_encode_bounds();
    test_decode();
    test_decode_nesting();
    test_decode_text();
    test_decode_spaces();
    test_decode_special_units();
    test_decode_bounds();
    test_round_trip();
    return test_finish("test_translate_html");
}
