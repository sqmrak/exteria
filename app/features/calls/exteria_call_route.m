#import "exteria_call_route.h"

#import "exteria_audio_session.h"
#import "exteria_settings_kit.h"

/* the routes the call can take now, in the order the sheet lists them, with the names they carry */
static void ExteriaCallRouteOptions(NSMutableArray *names, NSMutableArray *routes, BOOL *headset) {
    NSString *bluetoothName = nil, *wiredName = nil;
    BOOL bluetooth = ExteriaAudioSessionBluetoothInputAvailable(&bluetoothName);
    BOOL wired = ExteriaAudioSessionWiredAvailable(&wiredName);
    [names addObject:NSLocalizedString(@"call.route.phone", nil)];
    [routes addObject:[NSNumber numberWithInt:ExteriaAudioRouteEarpiece]];
    [names addObject:NSLocalizedString(@"call.route.speaker", nil)];
    [routes addObject:[NSNumber numberWithInt:ExteriaAudioRouteSpeaker]];
    if (wired) {
        [names addObject:wiredName.length ? wiredName : NSLocalizedString(@"call.route.wired", nil)];
        [routes addObject:[NSNumber numberWithInt:ExteriaAudioRouteWired]];
    }
    if (bluetooth) {
        [names addObject:bluetoothName.length ? bluetoothName : NSLocalizedString(@"call.route.bluetooth", nil)];
        [routes addObject:[NSNumber numberWithInt:ExteriaAudioRouteBluetooth]];
    }
    if (headset) *headset = wired || bluetooth;
}

static BOOL ExteriaCallPresentRoutes(UIViewController *host, BOOL always, void (^done)(ExteriaAudioRoute route)) {
    NSMutableArray *names = [NSMutableArray array], *routes = [NSMutableArray array];
    BOOL headset = NO;
    ExteriaCallRouteOptions(names, routes, &headset);
    if (!host || (!headset && !always)) return NO;
    void (^finished)(ExteriaAudioRoute) = [done copy];
    ExteriaSettingsChoose(host, NSLocalizedString(@"call.route.title", nil), names, ^(NSUInteger index) {
        if (index >= routes.count) return;
        ExteriaAudioRoute route = (ExteriaAudioRoute)[[routes objectAtIndex:index] intValue];
        if (!ExteriaAudioSessionSelectRoute(route)) NSLog(@"exteria: the call route %d was not applied", (int)route);
        if (finished) finished(route);
    });
    [finished release];
    return YES;
}

BOOL ExteriaCallPresentRouteSheet(UIViewController *host, void (^done)(ExteriaAudioRoute route)) {
    return ExteriaCallPresentRoutes(host, NO, done);
}

BOOL ExteriaCallPresentRouteChoices(UIViewController *host, void (^done)(ExteriaAudioRoute route)) {
    return ExteriaCallPresentRoutes(host, YES, done);
}
