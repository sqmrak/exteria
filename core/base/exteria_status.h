#ifndef EXTERIA_STATUS_H
#define EXTERIA_STATUS_H

typedef enum exteria_status {
    EXTERIA_OK = 0,
    EXTERIA_E_ARG = -1,
    EXTERIA_E_MALFORMED = -2,
    EXTERIA_E_TRUNCATED = -3,   /* incomplete frames can resume, malformed frames cannot */
    EXTERIA_E_UNSUPPORTED = -4,
    EXTERIA_E_LIMIT = -5,
    EXTERIA_E_NOMEM = -6,
    EXTERIA_E_CRYPTO = -7,
    EXTERIA_E_SECURITY = -8,
    EXTERIA_E_STATE = -9,
    EXTERIA_E_TIMEOUT = -10,
    EXTERIA_E_IO = -11,
    EXTERIA_E_EOF = -12,
    EXTERIA_E_RETRY = -13,
    EXTERIA_E_NOTFOUND = -14,
    EXTERIA_E_RPC = -15,
    EXTERIA_E_STORAGE = -16
} exteria_status;

const char *exteria_status_name(exteria_status status);

#endif
