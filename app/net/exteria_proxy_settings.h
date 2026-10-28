#import <Foundation/Foundation.h>
#import "exteria_proxy.h"
#import "exteria_shiro.h"
#include "exteria_mt_client.h"

extern NSString *const ExteriaProxyDidChangeNotification;

/* the selected proxy is stored in the keychain; reads are safe on the link workers */
exteria_status ExteriaProxyRead(exteria_proxy *proxy, BOOL *enabled);
exteria_status ExteriaProxyStoreLink(NSString *link);
exteria_status ExteriaProxySetEnabled(BOOL enabled);
NSString *ExteriaProxyDisplay(void);
exteria_status ExteriaProxyConnect(ExteriaShiro *shiro, exteria_mt_socket *socket, const char *host, uint16_t port,
                                   int timeout, exteria_mt_client_config *config, BOOL *tunneled);
