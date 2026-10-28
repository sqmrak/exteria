#ifndef EXTERIA_PROXY_H
#define EXTERIA_PROXY_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_links.h"
#include "exteria_status.h"

#define EXTERIA_PROXY_SECRET_LEN 16
#define EXTERIA_PROXY_DOMAIN_MAX 120

typedef enum exteria_proxy_kind {
    EXTERIA_PROXY_MTPROTO = 1,  /* an MTProto proxy: the obfuscated stream of the transport, keyed by a secret */
    EXTERIA_PROXY_SOCKS5        /* a SOCKS5 proxy, with a user and a password or without */
} exteria_proxy_kind;

typedef struct exteria_proxy {
    exteria_proxy_kind kind;
    char server[EXTERIA_LINK_SERVER_MAX];
    uint16_t port;
    uint8_t secret[EXTERIA_PROXY_SECRET_LEN];
    uint8_t padded;             /* the secret began with dd: the padded intermediate transport, which proxies of the current kind ask for */
    char tls_domain[EXTERIA_PROXY_DOMAIN_MAX + 1];
    char user[EXTERIA_LINK_CREDENTIAL_MAX];
    char password[EXTERIA_LINK_CREDENTIAL_MAX];
} exteria_proxy;

/* the secret of an MTProto proxy as a link or a person types it, hex or base64url: 16 bytes, or dd and 16 bytes for the padded transport. EXTERIA_E_UNSUPPORTED
   for ee and a domain, the fake TLS secrets this client does not speak, EXTERIA_E_MALFORMED for anything else */
exteria_status exteria_proxy_secret_decode(const char *text, uint8_t secret[EXTERIA_PROXY_SECRET_LEN], uint8_t *padded);

/* a name or an IPv4 address in the form a server field takes: letters, digits, dots and hyphens, 1 to 253 characters, no empty label */
int exteria_proxy_server_valid(const char *server);

/* the proxy a tg://proxy, tg://socks, t.me/proxy or t.me/socks link names. EXTERIA_E_ARG for a link of another kind, EXTERIA_E_UNSUPPORTED or
   EXTERIA_E_MALFORMED as the secret decode says */
exteria_status exteria_proxy_from_link(const exteria_tg_link *link, exteria_proxy *out);

/* the link that adds this proxy in another client: tg://proxy?server=&port=&secret= (secret in hex, with dd when padded) or tg://socks?..., into out;
   EXTERIA_E_LIMIT when it does not fit */
exteria_status exteria_proxy_link(const exteria_proxy *proxy, char *out, size_t cap);

#endif
