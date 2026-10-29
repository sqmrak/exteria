#ifndef EXTERIA_APP_CONFIG_H
#define EXTERIA_APP_CONFIG_H

#include "exteria_tl.h"

/* a nonnegative integer from help.appConfig; absent keys return EXTERIA_E_NOTFOUND */
exteria_status exteria_app_config_i32(const exteria_tl_value *answer, const char *key, int32_t *out);

#endif
