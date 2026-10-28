#ifndef EXTERIA_MT_SOCKET_H
#define EXTERIA_MT_SOCKET_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

typedef struct exteria_mt_socket {
    int fd;
    /* set by exteria_mt_socket_start_faketls: what the records of the fake TLS layer keep between reads; owned by the socket */
    struct exteria_mt_faketls *tls;
} exteria_mt_socket;

void exteria_mt_socket_init(exteria_mt_socket *s);
exteria_status exteria_mt_socket_connect(exteria_mt_socket *s, const char *host, uint16_t port, int timeout_ms);
/* takes over a connected non blocking stream socket that another part of the program opened, such as a stream of
   the tunnel */
exteria_status exteria_mt_socket_adopt(exteria_mt_socket *s, int fd);
exteria_status exteria_mt_socket_connect_socks5(exteria_mt_socket *s, const char *proxy_host, uint16_t proxy_port,
                                                const char *user, const char *pass,
                                                const char *dest_host, uint16_t dest_port, int timeout_ms);
/* negotiates on an already connected stream, including one opened through shiro; closes it on failure */
exteria_status exteria_mt_socket_negotiate_socks5(exteria_mt_socket *s, const char *user, const char *pass,
                                                  const char *dest_host, uint16_t dest_port, int timeout_ms);
/* the fake TLS handshake of an "ee" proxy, on a socket that is connected to it (directly, through the tunnel or through a SOCKS5 proxy): the hello that proves
   the secret, and the proxy's reply that proves it back (EXTERIA_E_SECURITY when it does not, EXTERIA_E_MALFORMED for a reply that is not TLS, EXTERIA_E_EOF
   when the proxy closes, which is how it refuses a hello). From then on writes and reads carry the records, so what the caller sends and receives is the
   payload alone. The socket is closed on a failure */
exteria_status exteria_mt_socket_start_faketls(exteria_mt_socket *s, const uint8_t secret[16], const char *domain, int timeout_ms);
exteria_status exteria_mt_socket_write_all(exteria_mt_socket *s, const uint8_t *data, size_t len, int timeout_ms);
exteria_status exteria_mt_socket_read(exteria_mt_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms);
void exteria_mt_socket_close(exteria_mt_socket *s);

#endif
