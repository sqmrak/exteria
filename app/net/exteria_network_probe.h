#import <Foundation/Foundation.h>

#import "exteria_shiro.h"

typedef enum {
    /* a Telegram server took the connection */
    ExteriaProbeReachable = 0,
    /* every server stayed silent or refused */
    ExteriaProbeUnreachable,
    /* the VPN is wanted and not up, so the app does not connect at all; this says nothing about the network */
    ExteriaProbeBlocked
} ExteriaProbeResult;

/* asks whether Telegram can be reached from here, before there is a session to find out */
@interface ExteriaNetworkProbe : NSObject

+ (void)probeWithShiro:(ExteriaShiro *)shiro completion:(void (^)(ExteriaProbeResult result))completion;

@end
