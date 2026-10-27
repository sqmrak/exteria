#ifndef EXTERIA_SOCKS_H
#define EXTERIA_SOCKS_H

#include "exteria_bytes.h"

typedef enum exteria_socks_state {
    EXTERIA_SOCKS_METHOD = 0,
    EXTERIA_SOCKS_AUTH,
    EXTERIA_SOCKS_CONNECT,
    EXTERIA_SOCKS_READY,
    EXTERIA_SOCKS_FAILED
} exteria_socks_state;

typedef struct exteria_socks {
    exteria_socks_state state;
    uint8_t target[260];
    size_t target_len;
    uint8_t credentials[513];
    size_t credentials_len;
    uint8_t response[262];
    size_t response_len;
    size_t need;
    uint8_t reply;
} exteria_socks;

exteria_status exteria_socks_start(exteria_socks *s, const char *host, uint16_t port,
                                  const char *username, const char *password, exteria_writer *out);
exteria_status exteria_socks_feed(exteria_socks *s, const uint8_t *data, size_t len,
                                 size_t *consumed, exteria_writer *out);
void exteria_socks_free(exteria_socks *s);

#endif
