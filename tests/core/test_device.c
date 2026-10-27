#include "exteria_device.h"
#include "test_util.h"

static void known_models(void) {
    CHECK(!strcmp(exteria_device_name("iPhone4,1"), "iPhone 4S"));
    CHECK(!strcmp(exteria_device_name("iPhone3,3"), "iPhone 4"));
    CHECK(!strcmp(exteria_device_name("iPhone6,2"), "iPhone 5s"));
    CHECK(!strcmp(exteria_device_name("iPad2,5"), "iPad mini"));
    CHECK(!strcmp(exteria_device_name("iPad5,3"), "iPad Air 2"));
    CHECK(!strcmp(exteria_device_name("iPod5,1"), "iPod touch (5th generation)"));
    CHECK(!strcmp(exteria_device_name("iPhone17,5"), "iPhone 16e"));
}

static void unknown_input(void) {
    /* a prefix, an extension or another case of a known identifier is a different string */
    CHECK(exteria_device_name(NULL) == NULL);
    CHECK(exteria_device_name("") == NULL);
    CHECK(exteria_device_name("iPhone4,") == NULL);
    CHECK(exteria_device_name("iPhone4,11") == NULL);
    CHECK(exteria_device_name("iphone4,1") == NULL);
    CHECK(exteria_device_name("iPhone") == NULL);
    CHECK(exteria_device_name("x86_64") == NULL);
    CHECK(exteria_device_name("arm64") == NULL);
}

int main(void) {
    known_models();
    unknown_input();
    return test_finish("test_device");
}
