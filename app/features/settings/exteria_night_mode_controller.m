#import "exteria_night_mode_controller.h"

#import "exteria_gift_screen.h"
#import "exteria_night_mode.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

/* the times the schedule can be set to: every half hour, the grid the default times (22:00 and 08:00) lie on */
#define TIME_STEP 30
#define TIMES_PER_DAY (24 * 60 / TIME_STEP)

@interface ExteriaNightModeController () {
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaNightModeController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.night", nil);
    return self;
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaNightModeController alloc] init] autorelease];
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

static NSString *ExteriaClockText(int32_t minute) {
    return [NSString stringWithFormat:@"%02d:%02d", (int)(minute / 60), (int)(minute % 60)];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    /* the sun times of today are worked out by a look at the decision, so a schedule by the sun shows what it will use */
    (void)ExteriaNightDecision();
    exteria_night_config config = ExteriaNightConfig();
    NSMutableArray *sections = [NSMutableArray array];

    NSMutableArray *titles = [NSMutableArray arrayWithObjects:NSLocalizedString(@"chatset.night.off", nil), NSLocalizedString(@"chatset.night.scheduled", nil),
                              NSLocalizedString(@"chatset.night.adaptive", nil), nil];
    if (ExteriaNightSystemAvailable()) [titles addObject:NSLocalizedString(@"chatset.night.system", nil)];
    NSMutableArray *modes = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; ++i) {
        [modes addObject:[ExteriaSettingsRow checkRowWithTitle:[titles objectAtIndex:i] subtitle:nil checked:(NSUInteger)config.mode == i tap:^{
            [(ExteriaNightModeController *)weak.target chooseMode:(int32_t)i];
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"night.type.info", nil) rows:modes]];

    if (config.mode == EXTERIA_NIGHT_SCHEDULED) {
        ExteriaSettingsRow *sun = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"night.sun", nil) subtitle:nil on:config.by_sun != 0 toggle:^(BOOL on) {
            [(ExteriaNightModeController *)weak.target setBySun:on];
        }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"night.schedule.header", nil) footer:nil rows:[NSArray arrayWithObject:sun]]];
    }
    if (config.mode == EXTERIA_NIGHT_SCHEDULED && config.by_sun) {
        NSString *set = ExteriaClockText(config.sunset_minute), *rise = ExteriaClockText(config.sunrise_minute);
        NSString *info = config.sun_state == EXTERIA_SUN_NEVER_RISES ? NSLocalizedString(@"night.sun.polarnight", nil)
                       : (config.sun_state == EXTERIA_SUN_NEVER_SETS ? NSLocalizedString(@"night.sun.polarday", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"night.sun.info", nil), set, rise]);
        ExteriaSettingsRow *update = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolMapPin title:NSLocalizedString(@"night.sun.update", nil) destructive:NO tap:^{
            [(ExteriaNightModeController *)weak.target updateLocation];
        }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:info rows:[NSArray arrayWithObject:update]]];
    } else if (config.mode == EXTERIA_NIGHT_SCHEDULED) {
        ExteriaSettingsRow *from = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"night.from", nil) value:ExteriaClockText(config.from_minute) tap:^{
            [(ExteriaNightModeController *)weak.target chooseTimeForStart:YES];
        }];
        ExteriaSettingsRow *to = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"night.to", nil) value:ExteriaClockText(config.to_minute) tap:^{
            [(ExteriaNightModeController *)weak.target chooseTimeForStart:NO];
        }];
        NSString *info = [NSString stringWithFormat:NSLocalizedString(@"night.schedule.info", nil), ExteriaClockText(config.from_minute), ExteriaClockText(config.to_minute)];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:info rows:[NSArray arrayWithObjects:from, to, nil]]];
    } else if (config.mode == EXTERIA_NIGHT_ADAPTIVE) {
        ExteriaSettingsRow *slider = [ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"night.brightness.row", nil) format:@"%.0f%%" value:(float)config.threshold_percent
                                                                    minimum:0 maximum:100 change:^(float value) {
            [(ExteriaNightModeController *)weak.target thresholdMoved:value];
        }];
        NSString *info = [NSString stringWithFormat:NSLocalizedString(@"night.brightness.info", nil), (int)config.threshold_percent];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"night.brightness.header", nil) footer:info rows:[NSArray arrayWithObject:slider]]];
    }
    self.sections = sections;
    [self reloadSettings];
}

- (void)themeDidChange {
    [self rebuild];
}

/* a setup that turns the theme at this moment is applied as a switch of the settings is: the colors spread from the row that was touched, and this page
   stays, made again in the new colors */
- (void)applySetup {
    if (ExteriaNightCheck(NO)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                          userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:ExteriaThemeOriginKey]];
        return;
    }
    [self rebuild];
}

/* the place comes from the system, which asks the person the first time; a refusal leaves the schedule on its two times, and says why */
- (void)setBySun:(BOOL)on {
    exteria_night_config config = ExteriaNightConfig();
    if (!on || ExteriaNightHasLocation()) {
        config.by_sun = on ? 1 : 0;
        ExteriaNightSetConfig(config);
        [self applySetup];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    ExteriaNightRequestLocation(^(BOOL known) {
        ExteriaNightModeController *me = weak.target;
        if (!me) return;
        if (!known) {
            ExteriaGiftAlert(nil, NSLocalizedString(@"night.sun.denied", nil));
            [me rebuild];
            return;
        }
        exteria_night_config next = ExteriaNightConfig();
        next.by_sun = 1;
        ExteriaNightSetConfig(next);
        [me applySetup];
    });
}

- (void)updateLocation {
    ExteriaWeakReference *weak = _weak;
    ExteriaNightRequestLocation(^(BOOL known) {
        ExteriaNightModeController *me = weak.target;
        if (!me) return;
        if (!known) ExteriaGiftAlert(nil, NSLocalizedString(@"night.sun.denied", nil));
        else [me applySetup];
    });
}

- (void)chooseMode:(int32_t)mode {
    exteria_night_config config = ExteriaNightConfig();
    if (config.mode == mode) return;
    config.mode = mode;
    ExteriaNightSetConfig(config);
    [self applySetup];
}

- (void)chooseTimeForStart:(BOOL)start {
    NSMutableArray *options = [NSMutableArray array];
    for (int i = 0; i < TIMES_PER_DAY; ++i) [options addObject:ExteriaClockText(i * TIME_STEP)];
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsChoose(self, NSLocalizedString(start ? @"night.from" : @"night.to", nil), options, ^(NSUInteger index) {
        ExteriaNightModeController *me = weak.target;
        if (!me) return;
        exteria_night_config next = ExteriaNightConfig();
        if (start) next.from_minute = (int32_t)(index * TIME_STEP);
        else next.to_minute = (int32_t)(index * TIME_STEP);
        ExteriaNightSetConfig(next);
        [me applySetup];
    });
}

/* the slider moves in many steps; each is stored, and the theme follows at the next look, so the page does not leave from under the finger */
- (void)thresholdMoved:(float)value {
    exteria_night_config config = ExteriaNightConfig();
    int32_t percent = (int32_t)(value + 0.5f);
    if (percent == config.threshold_percent) return;
    config.threshold_percent = percent;
    ExteriaNightSetConfig(config);
    NSString *info = [NSString stringWithFormat:NSLocalizedString(@"night.brightness.info", nil), (int)percent];
    [self setFooter:info forSectionAtIndex:1];
}

@end
