#import "exteria_traffic_store.h"

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>

#include "exteria_mt_traffic.h"

static NSString *const ExteriaTrafficKey = @"exteria.traffic";
static NSTimer *ExteriaTrafficTimer;

BOOL ExteriaNetworkOnCellular(void) {
    struct ifaddrs *list = NULL;
    BOOL wifi = NO;
    if (getifaddrs(&list) != 0) return NO;
    for (struct ifaddrs *at = list; at; at = at->ifa_next) {
        if (!at->ifa_addr || at->ifa_addr->sa_family != AF_INET || strcmp(at->ifa_name, "en0") != 0) continue;
        if ((at->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) continue;
        struct in_addr address = ((struct sockaddr_in *)at->ifa_addr)->sin_addr;
        /* a link-local address (169.254) means the Wi-Fi has no network behind it */
        if (address.s_addr != 0 && (ntohl(address.s_addr) >> 16) != 0xA9FE) wifi = YES;
    }
    freeifaddrs(list);
    return !wifi;
}

static NSDictionary *ExteriaTrafficStored(void) {
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:ExteriaTrafficKey];
    return stored ? stored : [NSDictionary dictionary];
}

static unsigned long long ExteriaTrafficNumber(NSDictionary *stored, NSString *key) {
    return [[stored objectForKey:key] unsignedLongLongValue];
}

void ExteriaTrafficFlush(void) {
    exteria_traffic taken;
    exteria_traffic_take(&taken);
    exteria_traffic_set_cellular(ExteriaNetworkOnCellular());
    NSDictionary *stored = ExteriaTrafficStored();
    NSMutableDictionary *next = [NSMutableDictionary dictionaryWithDictionary:stored];
    static NSString *const sentKeys[2] = {@"sent.wifi", @"sent.cell"};
    static NSString *const receivedKeys[2] = {@"received.wifi", @"received.cell"};
    for (int i = 0; i < 2; ++i) {
        [next setObject:[NSNumber numberWithUnsignedLongLong:ExteriaTrafficNumber(stored, sentKeys[i]) + taken.sent[i]] forKey:sentKeys[i]];
        [next setObject:[NSNumber numberWithUnsignedLongLong:ExteriaTrafficNumber(stored, receivedKeys[i]) + taken.received[i]] forKey:receivedKeys[i]];
    }
    if (![next objectForKey:@"since"]) [next setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:@"since"];
    [[NSUserDefaults standardUserDefaults] setObject:next forKey:ExteriaTrafficKey];
}

ExteriaTrafficTotals ExteriaTrafficRead(void) {
    ExteriaTrafficFlush();
    NSDictionary *stored = ExteriaTrafficStored();
    ExteriaTrafficTotals totals;
    totals.sent[0] = ExteriaTrafficNumber(stored, @"sent.wifi");
    totals.sent[1] = ExteriaTrafficNumber(stored, @"sent.cell");
    totals.received[0] = ExteriaTrafficNumber(stored, @"received.wifi");
    totals.received[1] = ExteriaTrafficNumber(stored, @"received.cell");
    totals.since = [[stored objectForKey:@"since"] doubleValue];
    return totals;
}

void ExteriaTrafficReset(void) {
    exteria_traffic taken;
    exteria_traffic_take(&taken);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaTrafficKey];
    ExteriaTrafficFlush();
}

@interface ExteriaTrafficTicker : NSObject
- (void)tick;
@end

@implementation ExteriaTrafficTicker
- (void)tick {
    ExteriaTrafficFlush();
}
@end

void ExteriaTrafficStart(void) {
    if (ExteriaTrafficTimer) return;
    exteria_traffic_set_cellular(ExteriaNetworkOnCellular());
    /* the timer keeps its ticker for as long as it runs, which is the life of the app */
    ExteriaTrafficTimer = [[NSTimer scheduledTimerWithTimeInterval:30 target:[[[ExteriaTrafficTicker alloc] init] autorelease] selector:@selector(tick)
                                                          userInfo:nil repeats:YES] retain];
}
