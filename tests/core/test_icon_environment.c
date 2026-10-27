#include "test_util.h"
#include "exteria_icon_environment.h"

int main(void) {
    char *source[] = {"HOME=/sandbox", "PATH=/bin", "CFFIXED_USER_HOME=/sandbox", "LANG=en", NULL};
    char *out[5];
    CHECK(!exteria_icon_cache_environment(source, out, 4));
    CHECK(exteria_icon_cache_environment(source, out, 5));
    CHECK(!strcmp(out[0], "PATH=/bin"));
    CHECK(!strcmp(out[1], "LANG=en"));
    CHECK(!strcmp(out[2], "HOME=/var/mobile"));
    CHECK(!strcmp(out[3], "CFFIXED_USER_HOME=/var/mobile"));
    CHECK(out[4] == NULL);
    CHECK(!exteria_icon_cache_environment(NULL, out, 5));
    return test_finish("test_icon_environment");
}
