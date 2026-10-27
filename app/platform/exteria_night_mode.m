#import "exteria_night_mode.h"

#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

#import <objc/message.h>

#import "exteria_theme.h"

NSString *const ExteriaNightModeDidChangeNotification = @"ExteriaNightModeDidChange";

static NSString *const ExteriaNightModeKey = @"exteria.night.mode";
static NSString *const ExteriaNightFromKey = @"exteria.night.from";
static NSString *const ExteriaNightToKey = @"exteria.night.to";
static NSString *const ExteriaNightThresholdKey = @"exteria.night.threshold";
static NSString *const ExteriaNightBySunKey = @"exteria.night.bysun";
static NSString *const ExteriaNightSunsetKey = @"exteria.night.sunset";
static NSString *const ExteriaNightSunriseKey = @"exteria.night.sunrise";
static NSString *const ExteriaNightSunStateKey = @"exteria.night.sunstate";
/* the place the phone was last found at, and the day (year * 10000 + month * 100 + day) the sun times were worked out for */
static NSString *const ExteriaNightLatitudeKey = @"exteria.night.latitude";
static NSString *const ExteriaNightLongitudeKey = @"exteria.night.longitude";
static NSString *const ExteriaNightSunDayKey = @"exteria.night.sunday";
#define NIGHT_LOOK_SECONDS 30.0
/* the brightness slider of the system moves in many small steps, and one look after the last of them is enough */
#define NIGHT_BRIGHTNESS_DELAY 2.0

/* the decision of the last look that had one; -1 before it */
static int ExteriaNightLast = -1;
static NSTimer *ExteriaNightTimer;
static BOOL (^ExteriaNightGate)(void);

@interface ExteriaNightObserver : NSObject
+ (ExteriaNightObserver *)shared;
- (void)look;
- (void)brightnessChanged;
@end

exteria_night_config ExteriaNightConfig(void) {
    exteria_night_config config;
    exteria_night_config_default(&config);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    exteria_night_config stored = config;
    if ([defaults objectForKey:ExteriaNightModeKey]) stored.mode = (int32_t)[defaults integerForKey:ExteriaNightModeKey];
    if ([defaults objectForKey:ExteriaNightFromKey]) stored.from_minute = (int32_t)[defaults integerForKey:ExteriaNightFromKey];
    if ([defaults objectForKey:ExteriaNightToKey]) stored.to_minute = (int32_t)[defaults integerForKey:ExteriaNightToKey];
    if ([defaults objectForKey:ExteriaNightThresholdKey]) stored.threshold_percent = (int32_t)[defaults integerForKey:ExteriaNightThresholdKey];
    if ([defaults objectForKey:ExteriaNightBySunKey]) stored.by_sun = (int32_t)[defaults integerForKey:ExteriaNightBySunKey];
    if ([defaults objectForKey:ExteriaNightSunsetKey]) stored.sunset_minute = (int32_t)[defaults integerForKey:ExteriaNightSunsetKey];
    if ([defaults objectForKey:ExteriaNightSunriseKey]) stored.sunrise_minute = (int32_t)[defaults integerForKey:ExteriaNightSunriseKey];
    if ([defaults objectForKey:ExteriaNightSunStateKey]) stored.sun_state = (int32_t)[defaults integerForKey:ExteriaNightSunStateKey];
    /* a stored value that is out of range (a file edited by hand) falls back to the default as a whole */
    return exteria_night_config_valid(&stored) ? stored : config;
}

void ExteriaNightSetConfig(exteria_night_config config) {
    if (!exteria_night_config_valid(&config)) {
        NSLog(@"exteria: the night mode setup is out of range and was not stored");
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:config.mode forKey:ExteriaNightModeKey];
    [defaults setInteger:config.from_minute forKey:ExteriaNightFromKey];
    [defaults setInteger:config.to_minute forKey:ExteriaNightToKey];
    [defaults setInteger:config.threshold_percent forKey:ExteriaNightThresholdKey];
    [defaults setInteger:config.by_sun forKey:ExteriaNightBySunKey];
    [defaults setInteger:config.sunset_minute forKey:ExteriaNightSunsetKey];
    [defaults setInteger:config.sunrise_minute forKey:ExteriaNightSunriseKey];
    [defaults setInteger:config.sun_state forKey:ExteriaNightSunStateKey];
    if (![defaults synchronize]) NSLog(@"exteria: the night mode setup was not saved");
    /* a new setup is looked at fresh: what the last setup decided says nothing about this one */
    ExteriaNightLast = -1;
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaNightModeDidChangeNotification object:nil];
}

BOOL ExteriaNightSystemAvailable(void) {
    return [UIView instancesRespondToSelector:NSSelectorFromString(@"overrideUserInterfaceStyle")];
}

/* the appearance the system is in: 1 dark, 0 light, -1 where it has none or has not decided (UIUserInterfaceStyle is 1 for light and 2 for dark) */
static int ExteriaSystemDark(void) {
    if (!ExteriaNightSystemAvailable()) return -1;
    id traits = [[UIScreen mainScreen] valueForKey:@"traitCollection"];
    NSInteger style = [[traits valueForKey:@"userInterfaceStyle"] integerValue];
    return style == 2 ? 1 : (style == 1 ? 0 : -1);
}

static int32_t ExteriaDayNumber(NSDate *date) {
    NSDateComponents *day = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:date];
    return (int32_t)(day.year * 10000 + day.month * 100 + day.day);
}

/* the sun times of a schedule by the sun are worked out for today from the stored place; they are only worked out
   again when the day has turned */
static void ExteriaNightRefreshSun(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    exteria_night_config config = ExteriaNightConfig();
    if (config.mode != EXTERIA_NIGHT_SCHEDULED || !config.by_sun || ![defaults objectForKey:ExteriaNightLatitudeKey]) return;
    NSDate *now = [NSDate date];
    int32_t today = ExteriaDayNumber(now);
    if ([defaults integerForKey:ExteriaNightSunDayKey] == today) return;
    NSDateComponents *day = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:now];
    int offset = (int)([[NSTimeZone localTimeZone] secondsFromGMTForDate:now] / 60);
    int32_t rise = 0, set = 0, state = 0;
    if (exteria_sun_times([defaults doubleForKey:ExteriaNightLatitudeKey], [defaults doubleForKey:ExteriaNightLongitudeKey], (int)day.year, (int)day.month, (int)day.day, offset,
                          &rise, &set, &state) != 0) {
        NSLog(@"exteria: the sun times could not be worked out for the stored place");
        return;
    }
    config.sunrise_minute = rise;
    config.sunset_minute = set;
    config.sun_state = state;
    /* stored without the notification of a change of setup: nothing the person did changed, and the check that asked is the one that goes on */
    [defaults setInteger:config.sunset_minute forKey:ExteriaNightSunsetKey];
    [defaults setInteger:config.sunrise_minute forKey:ExteriaNightSunriseKey];
    [defaults setInteger:config.sun_state forKey:ExteriaNightSunStateKey];
    [defaults setInteger:today forKey:ExteriaNightSunDayKey];
}

int ExteriaNightDecision(void) {
    ExteriaNightRefreshSun();
    exteria_night_config config = ExteriaNightConfig();
    NSDateComponents *now = [[NSCalendar currentCalendar] components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:[NSDate date]];
    int32_t minute = (int32_t)(now.hour * 60 + now.minute);
    int32_t brightness = (int32_t)([UIScreen mainScreen].brightness * 100.0f + 0.5f);
    return exteria_night_decide(&config, minute, brightness, ExteriaSystemDark());
}

#pragma mark location

@interface ExteriaNightLocator : NSObject <CLLocationManagerDelegate> {
    CLLocationManager *_manager;
    /* everyone who asked while a request was out, answered together */
    NSMutableArray *_waiters;
}
- (void)requestWithCompletion:(void (^)(BOOL known))completion;
@end

@implementation ExteriaNightLocator

- (void)dealloc {
    _manager.delegate = nil;
    [_manager release];
    [_waiters release];
    [super dealloc];
}

- (void)finish:(BOOL)known {
    [_manager stopUpdatingLocation];
    _manager.delegate = nil;
    [_manager release];
    _manager = nil;
    NSArray *waiters = [_waiters autorelease];
    _waiters = nil;
    for (void (^done)(BOOL) in waiters) done(known);
}

- (void)requestWithCompletion:(void (^)(BOOL known))completion {
    if (_manager) {
        [_waiters addObject:[[completion copy] autorelease]];
        return;
    }
    if (![CLLocationManager locationServicesEnabled]) {
        completion(NO);
        return;
    }
    _waiters = [[NSMutableArray alloc] initWithObjects:[[completion copy] autorelease], nil];
    _manager = [[CLLocationManager alloc] init];
    _manager.delegate = self;
    _manager.desiredAccuracy = kCLLocationAccuracyKilometer;
    SEL ask = NSSelectorFromString(@"requestWhenInUseAuthorization");
    if ([_manager respondsToSelector:ask]) ((void (*)(id, SEL))objc_msgSend)(_manager, ask);
    [_manager startUpdatingLocation];
}

/* a place was found: kept, and the sun times are worked out again from it at the next look */
- (void)useLocation:(CLLocation *)place {
    if (!place || place.horizontalAccuracy < 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:place.coordinate.latitude forKey:ExteriaNightLatitudeKey];
    [defaults setDouble:place.coordinate.longitude forKey:ExteriaNightLongitudeKey];
    [defaults removeObjectForKey:ExteriaNightSunDayKey];
    if (![defaults synchronize]) NSLog(@"exteria: the place of the night schedule was not saved");
    [self finish:YES];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    (void)manager;
    [self useLocation:[locations lastObject]];
}

/* ios 5 calls this older method instead of the one above, which came with ios 6 */
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)place fromLocation:(CLLocation *)old {
    (void)manager;
    (void)old;
    [self useLocation:place];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager;
    /* the first answer can be "not yet", and the manager goes on looking; only a refusal ends the request */
    if (error.code == kCLErrorDenied) [self finish:NO];
}

@end

static ExteriaNightLocator *ExteriaNightLocatorShared;

void ExteriaNightRequestLocation(void (^completion)(BOOL known)) {
    if (!ExteriaNightLocatorShared) ExteriaNightLocatorShared = [[ExteriaNightLocator alloc] init];
    [ExteriaNightLocatorShared requestWithCompletion:completion];
}

BOOL ExteriaNightHasLocation(void) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaNightLatitudeKey] != nil;
}

BOOL ExteriaNightCheck(BOOL announce) {
    int decision = ExteriaNightDecision();
    if (decision == -1) {
        ExteriaNightLast = -1;
        return NO;
    }
    BOOL change = exteria_night_should_switch(decision, ExteriaNightLast, ExteriaThemeStoredDark()) != 0;
    ExteriaNightLast = decision;
    if (!change) return NO;
    ExteriaThemeStoreDark(decision == 1);
    if (announce) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil];
    return YES;
}

@implementation ExteriaNightObserver

+ (ExteriaNightObserver *)shared {
    static ExteriaNightObserver *observer;
    if (!observer) observer = [[ExteriaNightObserver alloc] init];
    return observer;
}

/* a look that cannot be shown is not counted: the decision stays unseen, and the next look finds the change again */
- (void)look {
    if (ExteriaNightGate && !ExteriaNightGate()) return;
    ExteriaNightCheck(YES);
}

/* the timer fires in the background too while the app is kept awake for its link, and a theme nobody sees is not worth the wake */
- (void)enteredBackground {
    [ExteriaNightTimer invalidate];
    [ExteriaNightTimer release];
    ExteriaNightTimer = nil;
}

- (void)becameActive {
    if (!ExteriaNightTimer) ExteriaNightTimer = [[NSTimer scheduledTimerWithTimeInterval:NIGHT_LOOK_SECONDS target:self selector:@selector(look) userInfo:nil repeats:YES] retain];
    [self look];
}

- (void)brightnessChanged {
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(look) object:nil];
    [self performSelector:@selector(look) withObject:nil afterDelay:NIGHT_BRIGHTNESS_DELAY];
}

@end

void ExteriaNightStart(BOOL (^gate)(void)) {
    ExteriaNightStop();
    ExteriaNightGate = [gate copy];
    ExteriaNightObserver *observer = [ExteriaNightObserver shared];
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground)
        ExteriaNightTimer = [[NSTimer scheduledTimerWithTimeInterval:NIGHT_LOOK_SECONDS target:observer selector:@selector(look) userInfo:nil repeats:YES] retain];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:observer selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:observer selector:@selector(enteredBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:observer selector:@selector(brightnessChanged) name:UIScreenBrightnessDidChangeNotification object:nil];
    /* a change of the setup is looked at at once */
    [center addObserver:observer selector:@selector(look) name:ExteriaNightModeDidChangeNotification object:nil];
}

void ExteriaNightStop(void) {
    ExteriaNightObserver *observer = [ExteriaNightObserver shared];
    [NSObject cancelPreviousPerformRequestsWithTarget:observer];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [ExteriaNightTimer invalidate];
    [ExteriaNightTimer release];
    ExteriaNightTimer = nil;
    [ExteriaNightGate release];
    ExteriaNightGate = nil;
}
