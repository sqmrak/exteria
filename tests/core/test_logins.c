#include "test_util.h"
#include "exteria_logins.h"
#include "exteria_tl_ids.h"

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void str(exteria_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, field, x), EXTERIA_OK);
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

/* one session of the list: unconfirmed or not, this one or another */
static exteria_tl_value *session(int64_t hash, int unconfirmed, int current, int32_t date, const char *device, const char *region, const char *country) {
    exteria_tl_value *v = obj("authorization");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "hash", hash), EXTERIA_OK);
    if (unconfirmed) CHECK_EQ_INT(exteria_tl_set_flag(v, "unconfirmed"), EXTERIA_OK);
    if (current) CHECK_EQ_INT(exteria_tl_set_flag(v, "current"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "date_created", date), EXTERIA_OK);
    str(v, "device_model", device);
    str(v, "app_name", "Telegram iOS");
    str(v, "region", region);
    str(v, "country", country);
    return v;
}

static exteria_tl_value *answer(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *a = obj("account.authorizations"), *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, a, "authorization_ttl_days", 180), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "authorizations", vec), EXTERIA_OK);
    return a;
}

static void test_parse(void) {
    exteria_unconfirmed_login rows[4];
    exteria_tl_value *items[6];
    size_t count = 99;
    items[0] = session(1, 0, 1, 100, "This phone", "Berlin", "Germany");
    items[1] = session(2, 1, 0, 200, "iPhone4,1", "Frankfurt am Main", "Germany");
    items[2] = session(3, 0, 0, 300, "Pixel", "Paris", "France");
    items[3] = session(4, 1, 0, 500, "iPad2,1", "Moscow", "Moscow");
    items[4] = session(5, 1, 1, 600, "This one is current", "X", "Y");
    items[5] = session(0, 1, 0, 700, "no hash", "X", "Y");
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 6), rows, 4, &count), EXTERIA_OK);
    /* only the unconfirmed ones that are not this session, with a hash, newest first */
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].hash, 4);
    CHECK_EQ_INT(rows[0].date, 500);
    CHECK(!strcmp(rows[0].device, "iPad2,1"));
    /* a region that only repeats the country is said once */
    CHECK(!strcmp(rows[0].place, "Moscow"));
    CHECK_EQ_INT(rows[1].hash, 2);
    CHECK(!strcmp(rows[1].device, "iPhone4,1"));
    CHECK(!strcmp(rows[1].place, "Frankfurt am Main, Germany"));

    /* the cap keeps the newest, wherever the older ones stand in the list */
    items[0] = session(11, 1, 0, 10, "a", "", "");
    items[1] = session(12, 1, 0, 30, "b", "", "");
    items[2] = session(13, 1, 0, 20, "c", "", "");
    items[3] = session(14, 1, 0, 5, "d", "", "");
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 4), rows, 2, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(rows[0].hash, 12);
    CHECK_EQ_INT(rows[1].hash, 13);
    CHECK_EQ_INT(rows[0].place[0], 0);
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 4), rows, 0, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);

    /* an empty device name falls back to the app, a place with one half has only that half */
    items[0] = session(21, 1, 0, 10, "", "", "Japan");
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 1), rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK(!strcmp(rows[0].device, "Telegram iOS"));
    CHECK(!strcmp(rows[0].place, "Japan"));
    items[0] = session(22, 1, 0, 10, "x", "Osaka", "");
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 1), rows, 4, &count), EXTERIA_OK);
    CHECK(!strcmp(rows[0].place, "Osaka"));
    /* long names are cut at a character, not in the middle of one */
    {
        char longname[300];
        size_t i;
        for (i = 0; i + 2 < sizeof(longname); i += 2) {
            longname[i] = (char)0xd0;
            longname[i + 1] = (char)0xb0;
        }
        longname[sizeof(longname) - 2] = 0;
        items[0] = session(23, 1, 0, 10, longname, longname, "Z");
        CHECK_EQ_INT(exteria_logins_parse(answer(items, 1), rows, 4, &count), EXTERIA_OK);
        CHECK_EQ_INT(strlen(rows[0].device) % 2, 0);
        CHECK(strlen(rows[0].device) < EXTERIA_LOGIN_DEVICE_MAX);
        CHECK(strlen(rows[0].place) < EXTERIA_LOGIN_PLACE_MAX);
        CHECK_EQ_INT(strlen(rows[0].place) % 2 == 0 || strstr(rows[0].place, ", Z") != NULL, 1);
    }
    /* nothing to say, the wrong answer and the wrong arguments */
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 0), rows, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_logins_parse(obj("boolTrue"), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_logins_parse(obj("account.authorizations"), rows, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 1), NULL, 4, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_logins_parse(answer(items, 1), rows, 4, NULL), EXTERIA_E_ARG);
}

static void test_requests(void) {
    exteria_tl_value *request = NULL;
    CHECK_EQ_INT(exteria_logins_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_getAuthorizations);
    CHECK_EQ_INT(exteria_logins_request(&arena, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_login_confirm_request(&arena, -7777777777ll, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "confirmed"), 1);
    roundtrip(request, EXTERIA_TL_ID_account_changeAuthorizationSettings);
    {
        /* constructor, flags with only confirmed (bit 3), then the hash: what the server must read to take the answer as a confirmation */
        static const uint8_t wire[] = {0x62, 0x84, 0xf4, 0x40, 0x08, 0, 0, 0, 0x8f, 0x87, 0x68, 0x30, 0xfe, 0xff, 0xff, 0xff};
        exteria_writer writer;
        exteria_writer_init(&writer, 256);
        CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
        CHECK_EQ_INT(writer.len, sizeof(wire));
        CHECK(writer.len == sizeof(wire) && memcmp(writer.data, wire, sizeof(wire)) == 0);
        exteria_writer_free(&writer);
    }
    CHECK_EQ_INT(exteria_login_reset_request(&arena, -7777777777ll, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "confirmed"), 0);
    roundtrip(request, EXTERIA_TL_ID_account_resetAuthorization);
    CHECK_EQ_INT(exteria_login_confirm_request(&arena, 0, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_login_reset_request(&arena, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_login_reset_request(NULL, 5, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_login_reset_request(&arena, 5, NULL), EXTERIA_E_ARG);
}

int main(void) {
    exteria_arena_init(&arena, 16u * 1024u * 1024u);
    test_parse();
    test_requests();
    exteria_arena_free(&arena);
    return test_finish("test_logins");
}
