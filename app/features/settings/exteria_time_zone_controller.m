#import "exteria_time_zone_controller.h"

#import "exteria_time.h"
#import "exteria_weak_reference.h"

@interface ExteriaTimeZoneController () {
    ExteriaWeakReference *_weak;
    BOOL _positioned;
}
@end

@implementation ExteriaTimeZoneController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"time.zone.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)chooseOffset:(int32_t)minutes {
    ExteriaTimeZoneSetChoice(minutes);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    int32_t chosen = ExteriaTimeZoneChoice();
    ExteriaSettingsRow *automatic = [ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"time.zone.auto", nil) subtitle:nil
                                                                 checked:chosen == EXTERIA_TIME_ZONE_AUTO tap:^{
        [(ExteriaTimeZoneController *)weak.target chooseOffset:EXTERIA_TIME_ZONE_AUTO];
    }];
    NSMutableArray *offsets = [NSMutableArray array];
    for (int32_t minutes = EXTERIA_TIME_ZONE_MIN; minutes <= EXTERIA_TIME_ZONE_MAX; minutes += EXTERIA_TIME_ZONE_STEP) {
        [offsets addObject:[ExteriaSettingsRow checkRowWithTitle:ExteriaTimeZoneOffsetText(minutes) subtitle:nil checked:chosen == minutes tap:^{
            [(ExteriaTimeZoneController *)weak.target chooseOffset:minutes];
        }]];
    }
    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"time.zone.auto.info", nil) rows:[NSArray arrayWithObject:automatic]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"time.zone.manual", nil) footer:NSLocalizedString(@"time.zone.manual.info", nil) rows:offsets], nil];
    [self reloadSettings];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    int32_t chosen = ExteriaTimeZoneChoice();
    if (!_positioned && chosen != EXTERIA_TIME_ZONE_AUTO) {
        NSInteger row = (chosen - EXTERIA_TIME_ZONE_MIN) / EXTERIA_TIME_ZONE_STEP;
        [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
    _positioned = YES;
}

- (void)themeDidChange { [self rebuild]; }

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaTimeZoneController alloc] init] autorelease];
}

@end
