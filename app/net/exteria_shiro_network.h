#ifndef EXTERIA_SHIRO_NETWORK_H
#define EXTERIA_SHIRO_NETWORK_H

#include <stdint.h>

#include "exteria_status.h"
struct exteria_mt_socket;

#ifdef __cplusplus
extern "C" {
#endif

/* the VPN for code that has no object to ask, such as the call library: it reads the route of the app and opens
   sockets through the tunnel */
int ExteriaShiroNetworkRoute(void);
/* follows the app's selected route, including DNS through the tunnel, and never bypasses a blocked route */
exteria_status ExteriaShiroNetworkConnectSocket(struct exteria_mt_socket *socket, const char *host, uint16_t port, int timeout_ms);

/* the UDP payload bytes the tunnel has sent to its server and received from it; 0 when it is not up */
int ExteriaShiroNetworkTransferred(unsigned long long *bytes_in, unsigned long long *bytes_out);

/* a datagram socket of the tunnel (see exteria_shiro_engine_open_udp for its frames); EXTERIA_E_STATE unless the route is the tunnel */
exteria_status ExteriaShiroNetworkOpenDatagram(int *fd);

/* a stream to ip:port (host order) through the tunnel, connected and non blocking; EXTERIA_E_STATE unless the route is the tunnel */
exteria_status ExteriaShiroNetworkOpenStream(uint32_t ip, uint16_t port, int timeout_ms, int *fd);

#ifdef __cplusplus
}
#endif

#endif
