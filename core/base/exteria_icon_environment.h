#ifndef EXTERIA_ICON_ENVIRONMENT_H
#define EXTERIA_ICON_ENVIRONMENT_H

#include <stddef.h>

/* the ios 7 uicache reads HOME instead of the app's sandbox directory */
int exteria_icon_cache_environment(char *const *source, char **out, size_t capacity);

#endif
