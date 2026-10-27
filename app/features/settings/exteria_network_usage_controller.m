#import "exteria_network_usage_controller.h"

#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_traffic_store.h"
#import "exteria_weak_reference.h"

/* "12.3 MB" the way the cache screen writes sizes, with kilobytes and bytes for the small ones */
static NSString *ExteriaTrafficSize(unsigned long long bytes) {
    if (bytes >= 1024ull * 1024ull * 1024ull) return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    if (bytes >= 1024ull * 1024ull) return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    if (bytes >= 1024ull) return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
    return [NSString stringWithFormat:@"%llu B", bytes];
}

@interface ExteriaNetworkUsageController () {
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaNetworkUsageController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"netusage.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaNetworkUsageController alloc] init] autorelease];
}

- (ExteriaSettingsSection *)sectionNamed:(NSString *)header sent:(unsigned long long)sent received:(unsigned long long)received {
    ExteriaSettingsRow *up = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSendArrow tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"netusage.sent", nil) subtitle:nil
                                                         value:ExteriaTrafficSize(sent) tap:nil];
    ExteriaSettingsRow *down = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolArrowDown tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"netusage.received", nil) subtitle:nil
                                                           value:ExteriaTrafficSize(received) tap:nil];
    ExteriaSettingsRow *all = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"netusage.total", nil) value:ExteriaTrafficSize(sent + received) tap:nil];
    return [ExteriaSettingsSection sectionWithHeader:header footer:nil rows:[NSArray arrayWithObjects:up, down, all, nil]];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaTrafficTotals totals = ExteriaTrafficRead();
    NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
    format.dateStyle = NSDateFormatterMediumStyle;
    format.timeStyle = NSDateFormatterNoStyle;
    NSString *since = totals.since > 0 ? [NSString stringWithFormat:NSLocalizedString(@"netusage.since", nil), [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:totals.since]]] : nil;
    ExteriaSettingsRow *reset = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolBroom title:NSLocalizedString(@"netusage.reset", nil) destructive:YES tap:^{
        ExteriaNetworkUsageController *me = weak.target;
        if (!me) return;
        ExteriaConfirmAction(me, NSLocalizedString(@"netusage.reset.confirm", nil), NSLocalizedString(@"netusage.reset", nil), ^{
            ExteriaTrafficReset();
            [(ExteriaNetworkUsageController *)weak.target rebuild];
        });
    }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self sectionNamed:NSLocalizedString(@"netusage.wifi", nil) sent:totals.sent[0] received:totals.received[0]]];
    [sections addObject:[self sectionNamed:NSLocalizedString(@"netusage.cell", nil) sent:totals.sent[1] received:totals.received[1]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:since rows:[NSArray arrayWithObject:reset]]];
    self.sections = sections;
    [self reloadSettings];
}

@end
