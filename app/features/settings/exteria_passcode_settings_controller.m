#import "exteria_passcode_settings_controller.h"

#import "exteria_passcode_flow_controller.h"
#import "exteria_passcode_store.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

/* the choices: never, at every return, and after a minute, five minutes, an hour or five hours away */
static const uint32_t ExteriaAutoLockSeconds[] = {0, EXTERIA_PASSCODE_AT_ONCE, 60, 5 * 60, 60 * 60, 5 * 60 * 60};
static NSString *const ExteriaAutoLockKeys[] = {@"passcode.auto.never", @"passcode.auto.now", @"passcode.auto.1m", @"passcode.auto.5m", @"passcode.auto.1h", @"passcode.auto.5h"};
#define AUTO_LOCK_CHOICES (sizeof(ExteriaAutoLockSeconds) / sizeof(ExteriaAutoLockSeconds[0]))

static NSString *ExteriaAutoLockTitle(uint32_t seconds) {
    for (NSUInteger i = 0; i < AUTO_LOCK_CHOICES; ++i) {
        if (ExteriaAutoLockSeconds[i] == seconds) return NSLocalizedString(ExteriaAutoLockKeys[i], nil);
    }
    return [NSString stringWithFormat:NSLocalizedString(@"passcode.auto.seconds", nil), (unsigned long)seconds];
}

@interface ExteriaPasscodeSettingsController () {
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaPasscodeSettingsController

+ (void)openFrom:(UIViewController *)host push:(void (^)(UIViewController *))push {
    void (^open)(void) = ^{ push([[[ExteriaPasscodeSettingsController alloc] init] autorelease]); };
    if (!ExteriaPasscodeEnabled()) {
        open();
        return;
    }
    ExteriaPasscodeFlowController *flow = [[[ExteriaPasscodeFlowController alloc] initWithMode:ExteriaPasscodeFlowVerify completion:^(BOOL done) {
        if (done) open();
    }] autorelease];
    [host presentViewController:flow animated:YES completion:nil];
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"passcode.title", nil);
    return self;
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

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaPasscodeSettingsController alloc] init] autorelease];
}

- (void)setUpCode {
    ExteriaWeakReference *weak = _weak;
    ExteriaPasscodeFlowController *flow = [[[ExteriaPasscodeFlowController alloc] initWithMode:ExteriaPasscodeFlowSetup completion:^(BOOL done) {
        (void)done;
        [(ExteriaPasscodeSettingsController *)weak.target rebuild];
    }] autorelease];
    [self presentViewController:flow animated:YES completion:nil];
}

- (void)chooseAutoLock {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *options = [NSMutableArray array];
    for (NSUInteger i = 0; i < AUTO_LOCK_CHOICES; ++i) [options addObject:NSLocalizedString(ExteriaAutoLockKeys[i], nil)];
    ExteriaSettingsChoose(self, NSLocalizedString(@"passcode.auto", nil), options, ^(NSUInteger index) {
        if (index >= AUTO_LOCK_CHOICES) return;
        ExteriaPasscodeSetAutoLock(ExteriaAutoLockSeconds[index]);
        [(ExteriaPasscodeSettingsController *)weak.target rebuild];
    });
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    BOOL enabled = ExteriaPasscodeEnabled();
    NSMutableArray *sections = [NSMutableArray array];
    ExteriaSettingsRow *toggle = [ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolLock tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"passcode.title", nil)
                                                                subtitle:nil on:enabled toggle:^(BOOL on) {
        ExteriaPasscodeSettingsController *me = weak.target;
        if (!me) return;
        if (on) {
            [me setUpCode];
            return;
        }
        ExteriaPasscodeClear();
        [me rebuild];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"passcode.info", nil) rows:[NSArray arrayWithObject:toggle]]];
    if (enabled) {
        ExteriaSettingsRow *change = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolLock tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"passcode.change", nil)
                                                              subtitle:nil value:nil tap:^{ [(ExteriaPasscodeSettingsController *)weak.target setUpCode]; }];
        ExteriaSettingsRow *auto_ = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolClock tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"passcode.auto", nil)
                                                             subtitle:nil value:ExteriaAutoLockTitle(ExteriaPasscodeAutoLock())
                                                                  tap:^{ [(ExteriaPasscodeSettingsController *)weak.target chooseAutoLock]; }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"passcode.auto.info", nil)
                                                                 rows:[NSArray arrayWithObjects:change, auto_, nil]]];
    }
    self.sections = sections;
    [self reloadSettings];
}

@end
