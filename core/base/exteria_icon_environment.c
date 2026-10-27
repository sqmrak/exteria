#include "exteria_icon_environment.h"

#include <string.h>

int exteria_icon_cache_environment(char *const *source, char **out, size_t capacity) {
    size_t count = 0;
    if (!source || !out || capacity < 3) return 0;
    while (*source) {
        if (strncmp(*source, "HOME=", 5) && strncmp(*source, "CFFIXED_USER_HOME=", 18)) {
            if (count >= capacity - 3) return 0;
            out[count++] = *source;
        }
        ++source;
    }
    out[count++] = "HOME=/var/mobile";
    out[count++] = "CFFIXED_USER_HOME=/var/mobile";
    out[count] = NULL;
    return 1;
}
