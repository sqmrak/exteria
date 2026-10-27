#import "exteria_lite_mode.h"

#import <UIKit/UIKit.h>

NSString *const ExteriaLiteModeDidChangeNotification = @"ExteriaLiteModeDidChange";

static NSString *const ExteriaLiteFlagsKey = @"exteria.lite";
static NSString *const ExteriaLiteLevelKey = @"exteria.lite.level";
static NSString *const ExteriaLiteSmoothKey = @"exteria.lite.smooth";
static NSString *const ExteriaLiteClassKey = @"exteria.lite.class";
static NSString *const ExteriaLitePremiumKey = @"exteria.lite.premium";

/* the level the power saver starts at for a person who never set one; takes 10 percent for every class */
#define DEFAULT_LEVEL 10

static BOOL sApplied;
static BOOL sStarted;

static NSUserDefaults *Defaults(void) {
    return [NSUserDefaults standardUserDefaults];
}

static void Announce(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaLiteModeDidChangeNotification object:nil];
}

exteria_lite_class ExteriaLiteMeasuredClass(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    return exteria_lite_measure_class((uint64_t)[info physicalMemory], (unsigned)[info processorCount]);
}

int ExteriaLiteClassChoice(void) {
    NSInteger choice = [Defaults() integerForKey:ExteriaLiteClassKey];
    return choice >= 0 && choice <= 3 ? (int)choice : 0;
}

exteria_lite_class ExteriaLiteClass(void) {
    switch (ExteriaLiteClassChoice()) {
    case 1: return EXTERIA_LITE_CLASS_HIGH;
    case 2: return EXTERIA_LITE_CLASS_AVERAGE;
    case 3: return EXTERIA_LITE_CLASS_LOW;
    default: return ExteriaLiteMeasuredClass();
    }
}

void ExteriaLiteSetClassChoice(int choice) {
    [Defaults() setInteger:choice forKey:ExteriaLiteClassKey];
    Announce();
}

NSString *ExteriaLiteClassName(exteria_lite_class device_class) {
    switch (device_class) {
    case EXTERIA_LITE_CLASS_LOW: return NSLocalizedString(@"lite.class.low", nil);
    case EXTERIA_LITE_CLASS_AVERAGE: return NSLocalizedString(@"lite.class.average", nil);
    default: return NSLocalizedString(@"lite.class.high", nil);
    }
}

NSUInteger ExteriaLiteStickerLimit(void) {
    switch (ExteriaLiteClass()) {
    case EXTERIA_LITE_CLASS_LOW: return 1;
    case EXTERIA_LITE_CLASS_AVERAGE: return 2;
    default: return 3;
    }
}

/* the stored flags, or what the class gives to a person who never changed one */
static uint32_t StoredValue(void) {
    id stored = [Defaults() objectForKey:ExteriaLiteFlagsKey];
    return [stored isKindOfClass:[NSNumber class]] ? (uint32_t)[stored unsignedIntValue] : exteria_lite_default_value(ExteriaLiteClass());
}

int ExteriaLitePowerSaverLevel(void) {
    id stored = [Defaults() objectForKey:ExteriaLiteLevelKey];
    return [stored isKindOfClass:[NSNumber class]] ? exteria_lite_clamp_level([stored intValue]) : DEFAULT_LEVEL;
}

int ExteriaLiteBatteryPercent(void) {
    UIDevice *device = [UIDevice currentDevice];
    if (!device.batteryMonitoringEnabled) return -1;
    float level = device.batteryLevel;
    return level < 0 ? -1 : (int)(level * 100.0f + 0.5f);
}

/* the answer for now, which also tells the screens when it changed */
static BOOL AppliedNow(void) {
    return exteria_lite_power_saver_applied(ExteriaLitePowerSaverLevel(), ExteriaLiteBatteryPercent()) != 0;
}

static void Recheck(void) {
    BOOL applied = AppliedNow();
    if (applied == sApplied) return;
    sApplied = applied;
    Announce();
}

BOOL ExteriaLitePowerSaverApplied(void) {
    return sStarted ? sApplied : AppliedNow();
}

static BOOL Premium(void) {
    return [Defaults() boolForKey:ExteriaLitePremiumKey];
}

BOOL ExteriaLiteEnabled(uint32_t flag) {
    return exteria_lite_enabled(StoredValue(), ExteriaLitePowerSaverApplied(), flag, Premium()) != 0;
}

void ExteriaLiteSetFlag(uint32_t flag, BOOL on) {
    /* the whole mask is set or cleared, so a Premium account and a plain one see the same switch */
    uint32_t value = exteria_lite_with(StoredValue(), flag, on);
    [Defaults() setObject:[NSNumber numberWithUnsignedInt:value] forKey:ExteriaLiteFlagsKey];
    Announce();
}

void ExteriaLiteSetPowerSaverLevel(int level) {
    [Defaults() setInteger:exteria_lite_clamp_level(level) forKey:ExteriaLiteLevelKey];
    Recheck();
}

void ExteriaLiteSetPremium(BOOL premium) {
    if (premium == Premium()) return;
    [Defaults() setBool:premium forKey:ExteriaLitePremiumKey];
    Announce();
}

BOOL ExteriaLiteSmoothTransitions(void) {
    id stored = [Defaults() objectForKey:ExteriaLiteSmoothKey];
    return [stored isKindOfClass:[NSNumber class]] ? [stored boolValue] : YES;
}

/* UIKit animates its own transitions and sheets through UIView, and this switch stops all of them at once */
static void ApplySmooth(void) {
    [UIView setAnimationsEnabled:ExteriaLiteSmoothTransitions()];
}

void ExteriaLiteSetSmoothTransitions(BOOL on) {
    [Defaults() setBool:on forKey:ExteriaLiteSmoothKey];
    ApplySmooth();
    Announce();
}

@interface ExteriaLiteObserver : NSObject
@end

@implementation ExteriaLiteObserver

- (void)batteryChanged {
    Recheck();
}

/* UIKit turns the animations back on after some system transitions, so the choice is made again when the app comes forward */
- (void)becameActive {
    ApplySmooth();
    Recheck();
}

@end

void ExteriaLiteModeStart(void) {
    if (sStarted) return;
    sStarted = YES;
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    static ExteriaLiteObserver *observer;
    observer = [[ExteriaLiteObserver alloc] init];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:observer selector:@selector(batteryChanged) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [center addObserver:observer selector:@selector(batteryChanged) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [center addObserver:observer selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    sApplied = AppliedNow();
    ApplySmooth();
}
