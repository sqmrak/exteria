#import "exteria_power_notice.h"

#import <UIKit/UIKit.h>
#import "exteria_inapp_banner.h"
#import "exteria_lite_mode.h"

@interface ExteriaPowerNotice : NSObject {
    exteria_power_notice_state _state;
}
- (void)check;
@end

@implementation ExteriaPowerNotice
- (void)check {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    int battery = ExteriaLiteBatteryPercent();
    int saver = exteria_lite_power_saver_applied(ExteriaLitePowerSaverLevel(), battery);
    uint32_t events = exteria_power_notice_update(&_state, battery, saver);
    if (!events) return;
    NSString *title = NSLocalizedString((events & EXTERIA_POWER_NOTICE_LOW) ? @"power.notice.low" : @"power.notice.saver", nil);
    NSString *body = (events & EXTERIA_POWER_NOTICE_SAVER) ? NSLocalizedString(@"power.notice.active", nil) : NSLocalizedString(@"power.notice.charge", nil);
    [ExteriaInAppBanner showPowerTitle:title body:body];
}
@end

void ExteriaPowerNoticeStart(void) {
    static ExteriaPowerNotice *notice;
    if (notice) return;
    notice = [[ExteriaPowerNotice alloc] init];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:notice selector:@selector(check) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [center addObserver:notice selector:@selector(check) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [center addObserver:notice selector:@selector(check) name:ExteriaLiteModeDidChangeNotification object:nil];
    [center addObserver:notice selector:@selector(check) name:UIApplicationDidBecomeActiveNotification object:nil];
    [notice check];
}
