#include "test_util.h"

#include "exteria_passcode.h"

static const uint8_t salt[EXTERIA_PASSCODE_SALT_LEN] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};

static void test_valid(void) {
    char long_code[EXTERIA_PASSCODE_MAX_LEN + 2];
    memset(long_code, 'a', sizeof(long_code));
    CHECK(exteria_passcode_valid(EXTERIA_PASSCODE_PIN, "1234", 4));
    CHECK(!exteria_passcode_valid(EXTERIA_PASSCODE_PIN, "123", 3));
    CHECK(!exteria_passcode_valid(EXTERIA_PASSCODE_PIN, "12345", 5));
    CHECK(!exteria_passcode_valid(EXTERIA_PASSCODE_PIN, "12a4", 4));
    CHECK(!exteria_passcode_valid(EXTERIA_PASSCODE_PIN, NULL, 4));
    CHECK(exteria_passcode_valid(EXTERIA_PASSCODE_PASSWORD, "pass word", 9));
    CHECK(!exteria_passcode_valid(EXTERIA_PASSCODE_PASSWORD, "", 0));
    CHECK(!exteria_passcode_valid(EXTERIA_PASSCODE_PASSWORD, "a\nb", 3));
    CHECK(exteria_passcode_valid(EXTERIA_PASSCODE_PASSWORD, long_code, EXTERIA_PASSCODE_MAX_LEN));
    CHECK(!exteria_passcode_valid(EXTERIA_PASSCODE_PASSWORD, long_code, EXTERIA_PASSCODE_MAX_LEN + 1));
    CHECK(!exteria_passcode_valid((exteria_passcode_type)7, "1234", 4));
}

static void test_hash(void) {
    char hex[EXTERIA_PASSCODE_HEX_LEN + 1];
    uint8_t other[EXTERIA_PASSCODE_SALT_LEN] = {0};
    CHECK_EQ_INT(exteria_passcode_hash(salt, "1234", 4, hex), EXTERIA_OK);
    CHECK(strcmp(hex, "67c6a388ec17e10c2fe3d8a6cc5766c296f34fed8761aa3616f54c26bd2519a5") == 0);
    CHECK_EQ_INT(exteria_passcode_hash(salt, "pass word", 9, hex), EXTERIA_OK);
    CHECK(strcmp(hex, "9ec445d07deae1c0c8ef7c72704e3326fc84658c26e78ea337228227697f6951") == 0);
    CHECK_EQ_INT(exteria_passcode_hash(salt, "", 0, hex), EXTERIA_E_ARG);
    CHECK_EQ_INT(hex[0], 0);
    CHECK_EQ_INT(exteria_passcode_hash(NULL, "1234", 4, hex), EXTERIA_E_ARG);

    CHECK(exteria_passcode_matches(salt, "1234", 4, "67c6a388ec17e10c2fe3d8a6cc5766c296f34fed8761aa3616f54c26bd2519a5"));
    CHECK(!exteria_passcode_matches(salt, "1235", 4, "67c6a388ec17e10c2fe3d8a6cc5766c296f34fed8761aa3616f54c26bd2519a5"));
    CHECK(!exteria_passcode_matches(other, "1234", 4, "67c6a388ec17e10c2fe3d8a6cc5766c296f34fed8761aa3616f54c26bd2519a5"));
    CHECK(!exteria_passcode_matches(salt, "1234", 4, "67c6a388"));
    CHECK(!exteria_passcode_matches(salt, "1234", 4, ""));
    CHECK(!exteria_passcode_matches(salt, "1234", 4, NULL));
    CHECK(!exteria_passcode_matches(salt, "", 0, "67c6a388ec17e10c2fe3d8a6cc5766c296f34fed8761aa3616f54c26bd2519a5"));
}

static void test_wait(void) {
    CHECK_EQ_INT(exteria_passcode_wait_seconds(0), 0);
    CHECK_EQ_INT(exteria_passcode_wait_seconds(4), 0);
    CHECK_EQ_INT(exteria_passcode_wait_seconds(5), 5);
    CHECK_EQ_INT(exteria_passcode_wait_seconds(6), 10);
    CHECK_EQ_INT(exteria_passcode_wait_seconds(7), 20);
    CHECK_EQ_INT(exteria_passcode_wait_seconds(10), 160);
    CHECK_EQ_INT(exteria_passcode_wait_seconds(11), 300);
    CHECK_EQ_INT(exteria_passcode_wait_seconds(UINT32_MAX), 300);
}

static void test_lock(void) {
    CHECK(!exteria_passcode_should_lock(0, 100, 100000));
    CHECK(exteria_passcode_should_lock(1, 100, 100));
    CHECK(!exteria_passcode_should_lock(60, 100, 159));
    CHECK(exteria_passcode_should_lock(60, 100, 160));
    CHECK(exteria_passcode_should_lock(60, 0, 160));
    CHECK(exteria_passcode_should_lock(60, 100, 99));
    CHECK(exteria_passcode_should_lock(3600, -5, 10));
}

int main(void) {
    test_valid();
    test_hash();
    test_wait();
    test_lock();
    return test_finish("test_passcode");
}
