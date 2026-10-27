#include "exteria_phone.h"
#include "test_util.h"

#include <stdio.h>

static void digits_only(void) {
    char out[8];
    CHECK_EQ_INT(exteria_phone_digits("+7 (912) 345-67-89", out, sizeof(out)), 7);
    CHECK(strcmp(out, "7912345") == 0);
    CHECK_EQ_INT(exteria_phone_digits("abc", out, sizeof(out)), 0);
    CHECK(out[0] == '\0');
    CHECK_EQ_INT(exteria_phone_digits(NULL, out, sizeof(out)), 0);
    CHECK_EQ_INT(exteria_phone_digits("123", out, 1), 0);
    CHECK_EQ_INT(exteria_phone_digits("123", NULL, 4), 0);
    /* arabic indic digits are not ascii digits and must not reach the server */
    CHECK_EQ_INT(exteria_phone_digits("\xd9\xa1\xd9\xa2", out, sizeof(out)), 0);
}

static void format_cases(void) {
    static const struct {
        const char *pattern, *digits, *expected;
    } cases[] = {
        {"XXX XXX XXXX", "", ""},
        {"XXX XXX XXXX", "9", "9"},
        {"XXX XXX XXXX", "912", "912"},
        {"XXX XXX XXXX", "9123", "912 3"},
        {"XXX XXX XXXX", "9123456789", "912 345 6789"},
        {"XXX XXX XXXX", "91234567890", "912 345 67890"},
        {"(XXX) XXX-XXXX", "5", "(5"},
        {"(XXX) XXX-XXXX", "5551", "(555) 1"},
        {"(XXX) XXX-XXXX", "5551234567", "(555) 123-4567"},
        {"XXX", "12345", "123 45" + 0},
        {"", "12345", "12345"},
        {"XX XX", "1234", "12 34"},
        {"(XX)", "123", "(12)3"},
    };
    size_t i;
    char out[40];
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        const char *expected = cases[i].expected;
        /* a pattern with fewer letters than digits runs the rest on without a space */
        if (strcmp(cases[i].pattern, "XXX") == 0) expected = "12345";
        CHECK_EQ_INT(exteria_phone_format(cases[i].pattern, cases[i].digits, out, sizeof(out)), EXTERIA_OK);
        if (strcmp(out, expected) != 0) fprintf(stderr, "format %s %s -> '%s' expected '%s'\n",
                                                cases[i].pattern, cases[i].digits, out, expected);
        CHECK(strcmp(out, expected) == 0);
    }
}

static void format_limits(void) {
    char out[6];
    CHECK_EQ_INT(exteria_phone_format("XXX XXX", "123456", out, sizeof(out)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_phone_format("XXX XXX", "12345", out, sizeof(out)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_phone_format("XXX XXX", "1234", out, sizeof(out)), EXTERIA_OK);
    CHECK(strcmp(out, "123 4") == 0);
    CHECK_EQ_INT(exteria_phone_format("XXX", "1234567", out, sizeof(out)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_phone_format("X", "1", NULL, 4), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_phone_format("X", "1", out, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_phone_format(NULL, "1", out, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_phone_format("X", NULL, out, sizeof(out)), EXTERIA_E_ARG);
    CHECK(out[0] == '\0');
}

static void validity(void) {
    CHECK(!exteria_phone_valid(0, 10));
    CHECK(!exteria_phone_valid(1, 3));
    CHECK(!exteria_phone_valid(1, 5));
    CHECK(exteria_phone_valid(1, 6));
    CHECK(exteria_phone_valid(1, 10));
    CHECK(exteria_phone_valid(3, 12));
    CHECK(!exteria_phone_valid(3, 13));
    CHECK(!exteria_phone_valid(5, 10));
    CHECK(exteria_phone_valid(4, 11));
    CHECK(!exteria_phone_valid(2, 5 + 12));
}

static void parse_fixture(void) {
    static const char text[] =
        "1876;JM;Jamaica;XXX XXXX\r\n"
        "\n"
        "265;MW;Malawi;77 XXX XXXX\n"
        "961;LB;Lebanon\n"
        "7;RU;Russian Federation;XXX XXX XXXX\n"
        "1;US;USA;XXX XXX XXXX";
    exteria_country list[8];
    size_t count = 99;
    CHECK_EQ_INT(exteria_country_parse(text, sizeof(text) - 1, list, 8, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 5);
    CHECK(strcmp(list[0].code, "1876") == 0 && strcmp(list[0].iso, "JM") == 0);
    CHECK(strcmp(list[0].pattern, "XXX XXXX") == 0);
    CHECK(strcmp(list[1].pattern, "XXX XXXX") == 0);
    CHECK(strcmp(list[2].name, "Lebanon") == 0 && list[2].pattern[0] == '\0');
    CHECK(strcmp(list[4].iso, "US") == 0);
}

static void parse_rejects(void) {
    static const char *const bad[] = {
        "7;RU\n", "x7;RU;Name\n", "12345;RU;Name\n", ";RU;Name\n", "7;ru;Name\n", "7;RUS;Name\n",
        "7;R;Name\n", "7;RU;\n", "7;RU;Name;XXX#\n", "7;RU;Name;XXX;extra\n",
        "7;RU;0123456789012345678901234567890123456789012345678\n",
        "7;RU;Name;XXXXXXXXXXXXXXXXXXXXXXXXXXXX\n"
    };
    size_t i, count;
    exteria_country list[4];
    for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        CHECK_EQ_INT(exteria_country_parse(bad[i], strlen(bad[i]), list, 4, &count), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(count, 0);
    }
    CHECK_EQ_INT(exteria_country_parse("1;US;A\n2;UU;B\n3;UV;C\n", 21, list, 2, &count), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_country_parse(NULL, 0, list, 4, &count), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_country_parse("", 0, list, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 0);
}

static void match_prefers_longest_then_last(void) {
    static const char text[] = "7;KZ;Kazakhstan\n7;RU;Russia\n1868;TT;Trinidad\n1;CA;Canada\n1;US;USA\n44;GB;UK\n";
    exteria_country list[8];
    size_t count, used;
    const exteria_country *hit;
    CHECK_EQ_INT(exteria_country_parse(text, sizeof(text) - 1, list, 8, &count), EXTERIA_OK);
    hit = exteria_country_match(list, count, "79123456789", &used);
    CHECK(hit && strcmp(hit->iso, "RU") == 0 && used == 1);
    hit = exteria_country_match(list, count, "18685551234", &used);
    CHECK(hit && strcmp(hit->iso, "TT") == 0 && used == 4);
    hit = exteria_country_match(list, count, "1868", &used);
    CHECK(hit && strcmp(hit->iso, "TT") == 0);
    hit = exteria_country_match(list, count, "186", &used);
    CHECK(hit && strcmp(hit->iso, "US") == 0 && used == 1);
    hit = exteria_country_match(list, count, "447700", &used);
    CHECK(hit && strcmp(hit->iso, "GB") == 0 && used == 2);
    hit = exteria_country_match(list, count, "9", &used);
    CHECK(hit == NULL && used == 0);
    hit = exteria_country_match(list, count, "", &used);
    CHECK(hit == NULL);
    CHECK(exteria_country_match(NULL, 0, "7", &used) == NULL);
    CHECK(exteria_country_match(list, count, NULL, &used) == NULL);
}

static void shipped_list(void) {
    static exteria_country list[EXTERIA_COUNTRY_MAX];
    char *text;
    long size;
    size_t count, used, i;
    const exteria_country *hit;
    FILE *file = fopen("../resources/phone/countries.txt", "rb");
    CHECK(file != NULL);
    if (!file) return;
    fseek(file, 0, SEEK_END);
    size = ftell(file);
    fseek(file, 0, SEEK_SET);
    text = malloc((size_t)size + 1);
    CHECK(text && fread(text, 1, (size_t)size, file) == (size_t)size);
    fclose(file);
    if (!text) return;
    CHECK_EQ_INT(exteria_country_parse(text, (size_t)size, list, EXTERIA_COUNTRY_MAX, &count), EXTERIA_OK);
    CHECK(count > 200);
    for (i = 0; i < count; ++i) {
        char out[40];
        CHECK_EQ_INT(exteria_phone_format(list[i].pattern, "12345678901", out, sizeof(out)), EXTERIA_OK);
    }
    hit = exteria_country_match(list, count, "79001234567", &used);
    CHECK(hit && strcmp(hit->iso, "RU") == 0);
    hit = exteria_country_match(list, count, "12025550123", &used);
    CHECK(hit && strcmp(hit->iso, "US") == 0);
    hit = exteria_country_match(list, count, "380501234567", &used);
    CHECK(hit && strcmp(hit->iso, "UA") == 0 && used == 3);
    hit = exteria_country_match(list, count, "447911123456", &used);
    CHECK(hit && strcmp(hit->iso, "GB") == 0);
    free(text);
}

int main(void) {
    digits_only();
    format_cases();
    format_limits();
    validity();
    parse_fixture();
    parse_rejects();
    match_prefers_longest_then_last();
    shipped_list();
    return test_finish("test_phone");
}
