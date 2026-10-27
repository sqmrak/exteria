#import <Foundation/Foundation.h>

#include "exteria_mt_socket.h"

typedef enum {
    ExteriaShiroStateOff = 0,
    /* the first start has no account yet and asks the registration API for one */
    ExteriaShiroStateRegistering,
    /* the servers of the account are tried one after another */
    ExteriaShiroStateConnecting,
    ExteriaShiroStateUp,
    ExteriaShiroStateFailed
} ExteriaShiroState;

typedef enum {
    ExteriaShiroFailureNone = 0,
    /* the WARP account could not be made or read: no answer, a refused call, a reply that is not what the API returns */
    ExteriaShiroFailureAccount,
    /* every server that was tried stayed silent */
    ExteriaShiroFailureServer,
    /* a server answered with something that does not authenticate against the account's key */
    ExteriaShiroFailureKey
} ExteriaShiroFailure;

/* where the traffic of the app goes: straight out, through the tunnel, or nowhere because the tunnel is wanted and
   not up */
typedef enum {
    ExteriaShiroRouteDirect = 0,
    ExteriaShiroRouteTunnel,
    ExteriaShiroRouteBlocked
} ExteriaShiroRoute;

typedef struct {
    unsigned long long bytesIn, bytesOut;
    unsigned long long ageMs;
    unsigned handshakes;
} ExteriaShiroStats;

/* main thread: posted after every change of the state or the failure */
extern NSString *const ExteriaShiroStateDidChangeNotification;

/* the VPN of this app and no other: a WireGuard tunnel to Cloudflare WARP that lives in the process; nothing is
   routed on the phone; only the connections that the app itself opens through ExteriaShiroConnectSocket use it */
@interface ExteriaShiro : NSObject

/* main thread only */
@property (nonatomic, readonly) ExteriaShiroState state;
@property (nonatomic, readonly) ExteriaShiroFailure failure;
/* what stopped the last run, in the words of the core ("registration: security"), nil without a failure; shown under the message of the failure so that a report of it
   says where it broke */
@property (nonatomic, readonly, copy) NSString *failureDetail;
/* the failure in words for the person, with what to do about it; nil without a failure */
@property (nonatomic, readonly, copy) NSString *failureText;
/* whether the person wants the tunnel; kept across launches */
@property (nonatomic, readonly) BOOL enabled;

/* any thread */
@property (nonatomic, readonly) ExteriaShiroRoute route;

- (id)initWithDirectory:(NSString *)directory;

/* brings the tunnel back at launch when it was on when the app closed; call before the session starts, so that no connection is made in the clear
   in between */
- (void)resume;
- (void)setEnabled:(BOOL)enabled;
/* the journal of the tunnel for a report: the device and the app, the state, and the last lines of what the runs
   did */
- (NSString *)logText;
/* after a failure: tries the account and the servers again from the start */
- (void)retry;
/* NO when the tunnel is not up or the engine is busy; the figures are the ones of the last YES */
- (BOOL)stats:(ExteriaShiroStats *)stats;
/* the stream to ip:port on the far side of the tunnel, for a thread that is not the main one */
- (exteria_status)openStreamToHost:(const char *)host port:(uint16_t)port timeout:(int)timeoutMs descriptor:(int *)fd;
- (exteria_status)openStreamToAddress:(uint32_t)ip port:(uint16_t)port timeout:(int)timeoutMs descriptor:(int *)fd;
/* the UDP payload bytes that went to the server and came from it, for a trace; NO when the tunnel is not up or the
   engine is busy */
- (BOOL)transferredIn:(unsigned long long *)bytesIn out:(unsigned long long *)bytesOut;
/* a datagram socket of the tunnel for UDP, any thread */
- (exteria_status)openDatagramDescriptor:(int *)fd;

@end

/* the one place where the app connects to Telegram */
exteria_status ExteriaShiroConnectSocket(ExteriaShiro *shiro, exteria_mt_socket *socket, const char *host, uint16_t port, int timeoutMs, BOOL *tunneled);

/* the VPN that the call library and the other code without an object reach through exteria_shiro_network.h; nil
   clears it */
void ExteriaShiroSetActive(ExteriaShiro *shiro);
