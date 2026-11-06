#import "exteria_call_route.h"

#import "exteria_audio_session.h"
#import "exteria_settings_kit.h"

BOOL ExteriaCallPresentRouteSheet(UIViewController *host, void (^done)(ExteriaAudioRoute route)) {
    NSString *headset = nil;
    if (!host || !ExteriaAudioSessionBluetoothInputAvailable(&headset)) return NO;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"call.route.phone", nil), NSLocalizedString(@"call.route.speaker", nil),
                        headset.length ? headset : NSLocalizedString(@"call.route.bluetooth", nil), nil];
    void (^finished)(ExteriaAudioRoute) = [done copy];
    ExteriaSettingsChoose(host, NSLocalizedString(@"call.route.title", nil), options, ^(NSUInteger index) {
        ExteriaAudioRoute route = index == 1 ? ExteriaAudioRouteSpeaker : index == 2 ? ExteriaAudioRouteBluetooth : ExteriaAudioRouteEarpiece;
        if (!ExteriaAudioSessionSelectRoute(route)) NSLog(@"exteria: the call route %d was not applied", (int)route);
        if (finished) finished(route);
    });
    [finished release];
    return YES;
}
