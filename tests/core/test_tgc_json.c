#include "exteria_tgc_json.h"
#include "test_util.h"

static exteria_json_doc *parse_ok(const char *text) {
    exteria_json_doc *doc = NULL;
    CHECK_EQ_INT(exteria_json_parse(text, strlen(text), &doc), EXTERIA_OK);
    CHECK(doc != NULL);
    return doc;
}

static void parse_bad(const char *text, exteria_status want) {
    exteria_json_doc *doc = (exteria_json_doc *)1;
    exteria_status got = exteria_json_parse(text, strlen(text), &doc);
    if (got != want) fprintf(stderr, "  input: %s\n", text);
    CHECK_EQ_INT(got, want);
    CHECK(doc == NULL);
}

static void values_and_lookup(void) {
    exteria_json_doc *doc = parse_ok(
        " {\"@type\":\"NegotiateChannels\",\"exchangeId\":\"123\",\"n\":-42,\"big\":9223372036854775807,\"low\":-9223372036854775808,"
        "\"yes\":true,\"no\":false,\"nothing\":null,\"list\":[1,\"two\",[3],{\"k\":4}],\"obj\":{\"a\":{\"b\":[]}},\"e\":{}}\n ");
    const exteria_json *root = exteria_json_root(doc), *list, *item;
    const char *s;
    size_t len = 0;
    int64_t i = 0;
    int b = 7;
    CHECK_EQ_INT(exteria_json_kind(root), EXTERIA_JSON_OBJECT);
    CHECK_EQ_INT(exteria_json_count(root), 11);
    s = exteria_json_string(exteria_json_get(root, "@type"), &len);
    CHECK(s && strcmp(s, "NegotiateChannels") == 0 && len == 17);
    CHECK_EQ_INT(exteria_json_int(exteria_json_get(root, "n"), &i), EXTERIA_OK);
    CHECK_EQ_INT(i, -42);
    CHECK_EQ_INT(exteria_json_int(exteria_json_get(root, "big"), &i), EXTERIA_OK);
    CHECK(i == INT64_MAX);
    CHECK_EQ_INT(exteria_json_int(exteria_json_get(root, "low"), &i), EXTERIA_OK);
    CHECK(i == INT64_MIN);
    CHECK_EQ_INT(exteria_json_bool(exteria_json_get(root, "yes"), &b), EXTERIA_OK);
    CHECK_EQ_INT(b, 1);
    CHECK_EQ_INT(exteria_json_bool(exteria_json_get(root, "no"), &b), EXTERIA_OK);
    CHECK_EQ_INT(b, 0);
    CHECK_EQ_INT(exteria_json_kind(exteria_json_get(root, "nothing")), EXTERIA_JSON_NULL);
    CHECK(exteria_json_get(root, "missing") == NULL);
    CHECK(exteria_json_get(exteria_json_get(root, "list"), "k") == NULL);
    /* kind checks: a string is no number, a number no string */
    CHECK_EQ_INT(exteria_json_int(exteria_json_get(root, "exchangeId"), &i), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(i, 0);
    CHECK(exteria_json_string(exteria_json_get(root, "n"), &len) == NULL);
    CHECK_EQ_INT(exteria_json_bool(exteria_json_get(root, "n"), &b), EXTERIA_E_MALFORMED);
    list = exteria_json_get(root, "list");
    CHECK_EQ_INT(exteria_json_count(list), 4);
    item = exteria_json_first(list);
    CHECK_EQ_INT(exteria_json_int(item, &i), EXTERIA_OK);
    CHECK_EQ_INT(i, 1);
    item = exteria_json_next(item);
    CHECK(strcmp(exteria_json_string(item, &len), "two") == 0);
    item = exteria_json_next(item);
    CHECK_EQ_INT(exteria_json_kind(item), EXTERIA_JSON_ARRAY);
    CHECK(exteria_json_key(item) == NULL);
    item = exteria_json_next(item);
    CHECK_EQ_INT(exteria_json_kind(item), EXTERIA_JSON_OBJECT);
    CHECK(exteria_json_next(item) == NULL);
    CHECK(exteria_json_first(exteria_json_get(root, "e")) == NULL);
    /* members come back in document order with their keys */
    item = exteria_json_first(root);
    CHECK(strcmp(exteria_json_key(item), "@type") == 0);
    CHECK(strcmp(exteria_json_key(exteria_json_next(item)), "exchangeId") == 0);
    exteria_json_free(doc);
    /* null handling of every accessor */
    CHECK(exteria_json_root(NULL) == NULL);
    CHECK_EQ_INT(exteria_json_kind(NULL), EXTERIA_JSON_NULL);
    CHECK(exteria_json_get(NULL, "a") == NULL);
    CHECK(exteria_json_first(NULL) == NULL && exteria_json_next(NULL) == NULL);
    CHECK_EQ_INT(exteria_json_count(NULL), 0);
    CHECK(exteria_json_key(NULL) == NULL);
    exteria_json_free(NULL);
}

static void bare_values_and_duplicates(void) {
    exteria_json_doc *doc = parse_ok("\"just text\"");
    size_t len;
    CHECK(strcmp(exteria_json_string(exteria_json_root(doc), &len), "just text") == 0);
    exteria_json_free(doc);
    doc = parse_ok("17");
    {
        int64_t i;
        CHECK_EQ_INT(exteria_json_int(exteria_json_root(doc), &i), EXTERIA_OK);
        CHECK_EQ_INT(i, 17);
    }
    exteria_json_free(doc);
    /* the last of two members with one key wins, as in the std::map of json11 */
    doc = parse_ok("{\"a\":1,\"a\":2}");
    {
        int64_t i;
        CHECK_EQ_INT(exteria_json_int(exteria_json_get(exteria_json_root(doc), "a"), &i), EXTERIA_OK);
        CHECK_EQ_INT(i, 2);
        CHECK_EQ_INT(exteria_json_count(exteria_json_root(doc)), 2);
    }
    exteria_json_free(doc);
}

static void numbers(void) {
    static const struct { const char *text; int is_int; long long value; } cases[] = {
        {"0", 1, 0}, {"-0", 1, 0}, {"7", 1, 7}, {"-7", 1, -7}, {"1234567890123", 1, 1234567890123LL},
        {"1.5", 0, 0}, {"1e3", 0, 0}, {"1E+3", 0, 0}, {"-2.5e-2", 0, 0}, {"0.0", 0, 0},
        {"9223372036854775808", 0, 0}, {"-9223372036854775809", 0, 0}, {"99999999999999999999999999", 0, 0},
        {"1234567890123456789012345678901234567890", 0, 0}
    };
    size_t i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        exteria_json_doc *doc = parse_ok(cases[i].text);
        int64_t v = 0;
        exteria_status s = exteria_json_int(exteria_json_root(doc), &v);
        CHECK_EQ_INT(exteria_json_kind(exteria_json_root(doc)), EXTERIA_JSON_NUMBER);
        if (cases[i].is_int) {
            CHECK_EQ_INT(s, EXTERIA_OK);
            CHECK_EQ_INT(v, cases[i].value);
        } else {
            CHECK_EQ_INT(s, EXTERIA_E_MALFORMED);
        }
        exteria_json_free(doc);
    }
    parse_bad("01", EXTERIA_E_MALFORMED);
    parse_bad("-", EXTERIA_E_MALFORMED);
    parse_bad("+1", EXTERIA_E_MALFORMED);
    parse_bad(".5", EXTERIA_E_MALFORMED);
    parse_bad("1.", EXTERIA_E_MALFORMED);
    parse_bad("1e", EXTERIA_E_MALFORMED);
    parse_bad("1e+", EXTERIA_E_MALFORMED);
    parse_bad("0x10", EXTERIA_E_MALFORMED);
    parse_bad("1 2", EXTERIA_E_MALFORMED);
    parse_bad("NaN", EXTERIA_E_MALFORMED);
    parse_bad("Infinity", EXTERIA_E_MALFORMED);
}

static void strings(void) {
    exteria_json_doc *doc = parse_ok("[\"a\\\"b\\\\c\\/d\\b\\f\\n\\r\\t\",\"\\u0041\\u00e9\\u20ac\\ud83d\\ude00\",\"caf\xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80\",\"\"]");
    const exteria_json *item = exteria_json_first(exteria_json_root(doc));
    size_t len = 0;
    const char *s = exteria_json_string(item, &len);
    CHECK(strcmp(s, "a\"b\\c/d\b\f\n\r\t") == 0);
    item = exteria_json_next(item);
    s = exteria_json_string(item, &len);
    CHECK(strcmp(s, "A\xC3\xA9\xE2\x82\xAC\xF0\x9F\x98\x80") == 0);
    CHECK_EQ_INT(len, 1 + 2 + 3 + 4);
    item = exteria_json_next(item);
    CHECK(strcmp(exteria_json_string(item, &len), "caf\xC3\xA9 \xE2\x82\xAC \xF0\x9F\x98\x80") == 0);
    item = exteria_json_next(item);
    CHECK(exteria_json_string(item, &len) != NULL);
    CHECK_EQ_INT(len, 0);
    exteria_json_free(doc);

    parse_bad("\"unterminated", EXTERIA_E_MALFORMED);
    parse_bad("\"bad \\x escape\"", EXTERIA_E_MALFORMED);
    parse_bad("\"tab\there\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\\u12\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\\u12g4\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\\u0000\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\\ud800\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\\ud800\\u0041\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\\udc00\"", EXTERIA_E_MALFORMED);
    /* invalid UTF-8: a lone continuation byte, a truncated sequence, an overlong form, a surrogate, past U+10FFFF */
    parse_bad("\"\x80\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\xC3\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\xC0\xAF\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\xE0\x80\xAF\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\xED\xA0\x80\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\xF4\x90\x80\x80\"", EXTERIA_E_MALFORMED);
    parse_bad("\"\xFF\"", EXTERIA_E_MALFORMED);
    /* a NUL byte inside the text */
    {
        exteria_json_doc *bad = (exteria_json_doc *)1;
        const char text[] = "\"a\0b\"";
        CHECK_EQ_INT(exteria_json_parse(text, sizeof(text) - 1, &bad), EXTERIA_E_MALFORMED);
        CHECK(bad == NULL);
    }
}

static void structure(void) {
    parse_bad("", EXTERIA_E_MALFORMED);
    parse_bad("   ", EXTERIA_E_MALFORMED);
    parse_bad("{", EXTERIA_E_MALFORMED);
    parse_bad("}", EXTERIA_E_MALFORMED);
    parse_bad("[", EXTERIA_E_MALFORMED);
    parse_bad("[1,]", EXTERIA_E_MALFORMED);
    parse_bad("[,1]", EXTERIA_E_MALFORMED);
    parse_bad("[1 2]", EXTERIA_E_MALFORMED);
    parse_bad("{\"a\"}", EXTERIA_E_MALFORMED);
    parse_bad("{\"a\":}", EXTERIA_E_MALFORMED);
    parse_bad("{\"a\":1,}", EXTERIA_E_MALFORMED);
    parse_bad("{a:1}", EXTERIA_E_MALFORMED);
    parse_bad("{\"a\" 1}", EXTERIA_E_MALFORMED);
    parse_bad("{1:2}", EXTERIA_E_MALFORMED);
    parse_bad("[1}", EXTERIA_E_MALFORMED);
    parse_bad("{\"a\":1]", EXTERIA_E_MALFORMED);
    parse_bad("tru", EXTERIA_E_MALFORMED);
    parse_bad("truex", EXTERIA_E_MALFORMED);
    parse_bad("nul", EXTERIA_E_MALFORMED);
    parse_bad("fals", EXTERIA_E_MALFORMED);
    parse_bad("{} {}", EXTERIA_E_MALFORMED);
    parse_bad("[] x", EXTERIA_E_MALFORMED);
    parse_bad("// c\n{}", EXTERIA_E_MALFORMED);
}

static void limits(void) {
    char text[EXTERIA_JSON_MAX_TEXT + 2];
    size_t i, n;
    exteria_json_doc *doc = NULL;
    /* depth: 12 levels pass, 13 do not */
    for (i = 0; i < 12; ++i) text[i] = '[';
    for (i = 0; i < 12; ++i) text[12 + i] = ']';
    text[24] = '\0';
    doc = parse_ok(text);
    exteria_json_free(doc);
    for (i = 0; i < 13; ++i) text[i] = '[';
    for (i = 0; i < 13; ++i) text[13 + i] = ']';
    text[26] = '\0';
    parse_bad(text, EXTERIA_E_LIMIT);
    /* a very deep document must not run the stack out: the parser refuses it at the cap */
    memset(text, '[', 60000);
    text[60000] = '\0';
    parse_bad(text, EXTERIA_E_LIMIT);
    /* the text size */
    memset(text, ' ', sizeof(text));
    text[0] = '1';
    CHECK_EQ_INT(exteria_json_parse(text, EXTERIA_JSON_MAX_TEXT, &doc), EXTERIA_OK);
    exteria_json_free(doc);
    CHECK_EQ_INT(exteria_json_parse(text, EXTERIA_JSON_MAX_TEXT + 1, &doc), EXTERIA_E_LIMIT);
    CHECK(doc == NULL);
    /* the number of values: an array of 4095 ones is the root and 4095 children, one more is too many */
    n = 0;
    text[n++] = '[';
    for (i = 0; i < 4095; ++i) {
        if (i) text[n++] = ',';
        text[n++] = '1';
    }
    text[n++] = ']';
    text[n] = '\0';
    doc = parse_ok(text);
    CHECK_EQ_INT(exteria_json_count(exteria_json_root(doc)), 4095);
    exteria_json_free(doc);
    n = 0;
    text[n++] = '[';
    for (i = 0; i < 4096; ++i) {
        if (i) text[n++] = ',';
        text[n++] = '1';
    }
    text[n++] = ']';
    text[n] = '\0';
    parse_bad(text, EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_json_parse(NULL, 5, &doc), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_json_parse("1", 1, NULL), EXTERIA_E_ARG);
}

static void writer(void) {
    char buf[256];
    exteria_json_out o;
    size_t len = 0;
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_object(&o);
    exteria_json_out_key(&o, "@type");
    exteria_json_out_string(&o, "InitialSetup");
    exteria_json_out_key(&o, "renomination");
    exteria_json_out_bool(&o, 1);
    exteria_json_out_key(&o, "list");
    exteria_json_out_array(&o);
    exteria_json_out_int(&o, -5);
    exteria_json_out_string(&o, "a\"b\\c\n\x01");
    exteria_json_out_object(&o);
    exteria_json_out_end(&o);
    exteria_json_out_array(&o);
    exteria_json_out_end(&o);
    exteria_json_out_end(&o);
    exteria_json_out_key(&o, "n");
    exteria_json_out_int(&o, 9223372036854775807LL);
    exteria_json_out_end(&o);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_OK);
    CHECK(strcmp(buf, "{\"@type\":\"InitialSetup\",\"renomination\":true,\"list\":[-5,\"a\\\"b\\\\c\\n\\u0001\",{},[]],\"n\":9223372036854775807}") == 0);
    CHECK_EQ_INT(len, strlen(buf));
    /* what the writer makes the reader takes back */
    {
        exteria_json_doc *doc = parse_ok(buf);
        const char *s = exteria_json_string(exteria_json_first(exteria_json_get(exteria_json_root(doc), "list")), &len);
        CHECK(s == NULL);
        CHECK_EQ_INT(exteria_json_count(exteria_json_get(exteria_json_root(doc), "list")), 4);
        exteria_json_free(doc);
    }
    /* misuse sticks */
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_object(&o);
    exteria_json_out_string(&o, "value with no key");
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_STATE);
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_array(&o);
    exteria_json_out_key(&o, "k");
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_STATE);
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_object(&o);
    exteria_json_out_key(&o, "k");
    exteria_json_out_end(&o);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_STATE);
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_end(&o);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_STATE);
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_int(&o, 1);
    exteria_json_out_int(&o, 2);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_STATE);
    /* unfinished and empty */
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_array(&o);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_STATE);
    exteria_json_out_init(&o, buf, sizeof(buf));
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_STATE);
    /* a buffer that is too small, to the byte */
    exteria_json_out_init(&o, buf, 8);
    exteria_json_out_string(&o, "abcdef");
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_LIMIT);
    exteria_json_out_init(&o, buf, 9);
    exteria_json_out_string(&o, "abcdef");
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_OK);
    CHECK_EQ_INT(len, 8);
    exteria_json_out_init(&o, NULL, 9);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_ARG);
    exteria_json_out_init(&o, buf, 1);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_ARG);
    /* nesting of the writer is bounded too */
    exteria_json_out_init(&o, buf, sizeof(buf));
    {
        int i;
        for (i = 0; i < 13; ++i) exteria_json_out_array(&o);
    }
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_LIMIT);
    exteria_json_out_init(&o, buf, sizeof(buf));
    exteria_json_out_string(&o, NULL);
    CHECK_EQ_INT(exteria_json_out_finish(&o, &len), EXTERIA_E_ARG);
}

int main(void) {
    values_and_lookup();
    bare_values_and_duplicates();
    numbers();
    strings();
    structure();
    limits();
    writer();
    return test_finish("test_tgc_json");
}
