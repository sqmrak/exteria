#import "exteria_network_probe.h"

#include "exteria_session_file.h"

/* the first data centers of the list: two different ones, so one that is blocked alone does not look like a dead network */
static const int32_t ExteriaProbeDatacenters[] = {2, 4};
#define PROBE_TIMEOUT_MS 5000

@implementation ExteriaNetworkProbe

+ (void)probeWithShiro:(ExteriaShiro *)shiro completion:(void (^)(ExteriaProbeResult))completion {
    void (^done)(ExteriaProbeResult) = [completion copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ExteriaProbeResult result = ExteriaProbeUnreachable;
        for (size_t i = 0; i < sizeof(ExteriaProbeDatacenters) / sizeof(ExteriaProbeDatacenters[0]); ++i) {
            const char *host = exteria_dc_host(ExteriaProbeDatacenters[i]);
            if (!host) continue;
            exteria_mt_socket socket;
            exteria_mt_socket_init(&socket);
            BOOL tunneled = NO;
            exteria_status status = ExteriaShiroConnectSocket(shiro, &socket, host, exteria_dc_port(), PROBE_TIMEOUT_MS, &tunneled);
            exteria_mt_socket_close(&socket);
            if (status == EXTERIA_OK) {
                result = ExteriaProbeReachable;
                break;
            }
            /* a tunnel that is wanted and not up refuses every connection in the same way, so there is no second server to try */
            if (status == EXTERIA_E_STATE) {
                result = ExteriaProbeBlocked;
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            done(result);
            [done release];
        });
    });
}

@end
