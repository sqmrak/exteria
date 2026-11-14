#import "exteria_developer_settings.h"
#import "exteria_logs_controller.h"

#import "exteria_alert.h"
#import "exteria_crash_prompt.h"
#import "exteria_developer_badges_controller.h"
#import "exteria_developers.h"
#import "exteria_inapp_banner.h"
#import "exteria_cleaning.h"
#import "exteria_popup_menu.h"
#import "exteria_release_check.h"
#import "exteria_senko_popup.h"
#import "exteria_shiro.h"
#import "exteria_shiro_failure_prompt.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_welcome_toast.h"
#import "exteria_platform.h"
#import "exteria_weak_reference.h"

NSString *const ExteriaDeveloperModeDidChangeNotification = @"ExteriaDeveloperModeDidChange";

static NSString *const ExteriaDeveloperModeKey = @"exteria.developer.mode";

BOOL ExteriaDeveloperModeEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaDeveloperModeKey];
}

void ExteriaDeveloperModeSet(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ExteriaDeveloperModeKey];
}

@interface ExteriaDeveloperSettingsController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    ExteriaSenkoPopup *_senko;
    ExteriaWelcomeToast *_toast;
}
@end

@implementation ExteriaDeveloperSettingsController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"developer.settings", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    _senko.dismissHandler = nil;
    [_senko dismiss];
    [_senko release];
    _toast.dismissHandler = nil;
    [_toast dismiss];
    [_toast release];
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
    return [[[ExteriaDeveloperSettingsController alloc] initWithSession:_session] autorelease];
}

/* the windows come up over the whole app, which is the host the app itself uses for them */
static UIView *ExteriaDeveloperHost(void) {
    return ExteriaOverlayHost();
}

- (void)showSenko {
    if (_senko.isShown) return;
    [_senko release];
    _senko = [[ExteriaSenkoPopup alloc] init];
    _senko.titleText = NSLocalizedString(@"welcome.senko.title", nil);
    _senko.messageText = NSLocalizedString(@"welcome.senko.message", nil);
    _senko.buttonTitle = NSLocalizedString(@"welcome.senko.ok", nil);
    ExteriaWeakReference *weak = _weak;
    _senko.dismissHandler = ^{
        ExteriaDeveloperSettingsController *me = weak.target;
        if (!me) return;
        [me->_senko release];
        me->_senko = nil;
    };
    [_senko showInView:ExteriaDeveloperHost()];
}

- (void)showToast {
    if (_toast.isShown) return;
    [_toast release];
    _toast = [[ExteriaWelcomeToast alloc] init];
    _toast.titleText = NSLocalizedString(@"developer.popup.toast", nil);
    _toast.messageText = NSLocalizedString(@"developer.popup.toast.text", nil);
    _toast.primaryTitle = NSLocalizedString(@"notice.ok", nil);
    _toast.secondaryTitle = NSLocalizedString(@"notice.cancel", nil);
    _toast.lifetime = 8;
    ExteriaWeakReference *weak = _weak;
    _toast.dismissHandler = ^{
        ExteriaDeveloperSettingsController *me = weak.target;
        if (!me) return;
        [me->_toast release];
        me->_toast = nil;
    };
    [_toast showInView:ExteriaDeveloperHost() inset:ExteriaStatusBarHeight()];
}

/* every chat of the main list and of the archive that holds unread messages or carries the manual unread mark is read on the server, one call after another so the
   server is not flooded; the person is told how many went through and how many failed */
- (void)markEverythingRead {
    ExteriaDeveloperSettingsController *me = self;
    [_session loadDialogsInFolder:0 completion:^(NSArray *main, NSString *mainError) {
        if (mainError) {
            ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"developer.readall.failed", nil), mainError]);
            return;
        }
        [me->_session loadDialogsInFolder:1 completion:^(NSArray *archived, NSString *archiveError) {
            if (archiveError) NSLog(@"exteria: the archive was not read by mark everything: %@", archiveError);
            NSMutableArray *queue = [NSMutableArray array];
            for (ExteriaDialog *dialog in [main arrayByAddingObjectsFromArray:archived ? archived : [NSArray array]]) {
                if (dialog.unreadCount > 0 || dialog.unread) [queue addObject:dialog];
            }
            if (!queue.count) {
                ExteriaShowNotice(nil, NSLocalizedString(@"developer.readall.none", nil));
                return;
            }
            [me markNextRead:queue done:0 failed:0];
        }];
    }];
}

- (void)markNextRead:(NSMutableArray *)queue done:(NSUInteger)done failed:(NSUInteger)failed {
    if (!queue.count) {
        ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"developer.readall.done", nil), (unsigned long)done, (unsigned long)failed]);
        return;
    }
    ExteriaDialog *dialog = [[[queue objectAtIndex:0] retain] autorelease];
    [queue removeObjectAtIndex:0];
    ExteriaChatCommand command = dialog.unreadCount > 0 ? ExteriaChatCommandMarkRead : ExteriaChatCommandClearUnreadMark;
    [_session performAction:command onDialog:dialog completion:^(NSString *errorName) {
        if (errorName) NSLog(@"exteria: %@ was not marked read: %@", dialog.title, errorName);
        [self markNextRead:queue done:done + (errorName ? 0 : 1) failed:failed + (errorName ? 1 : 0)];
    }];
}

- (void)showMarkNotices {
    static const struct { NSUInteger mark; NSString *key; } marks[] = {
        {ExteriaMarkDeveloper, @"developer.mark.developer"}, {ExteriaMarkLead, @"developer.mark.lead"}, {ExteriaMarkSenko, @"developer.mark.senko"},
        {ExteriaMarkTester, @"developer.mark.tester"}, {ExteriaMarkOfficialTester, @"developer.mark.official"}, {ExteriaMarkBugHunter, @"developer.mark.hunter"}, {ExteriaMarkFlawSeer, @"developer.mark.flawseer"},
        {ExteriaMarkManager, @"developer.mark.manager"}, {ExteriaMarkVideoFix, @"developer.mark.videofix"}, {ExteriaMarkPromotion, @"developer.mark.promotion"}
    };
    NSMutableArray *titles = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(marks) / sizeof(marks[0]); ++i) [titles addObject:NSLocalizedString(marks[i].key, nil)];
    ExteriaChoose(NSLocalizedString(@"developer.popup.mark", nil), titles, -1, ^(NSInteger index) {
        if (index < 0 || (size_t)index >= sizeof(marks) / sizeof(marks[0])) return;
        ExteriaShowMarkNotice(NSLocalizedString(@"developer.popup.someone", nil), marks[index].mark);
    });
}

- (void)showMenuAt:(CGPoint)point {
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"developer.menu.one", nil), NSLocalizedString(@"developer.menu.two", nil), NSLocalizedString(@"developer.menu.three", nil), nil];
    ExteriaSymbol symbols[] = {ExteriaSymbolPerson, ExteriaSymbolStar, ExteriaSymbolBookmark};
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) { (void)index; }] autorelease];
    [menu showInView:self.view anchor:point];
}

- (void)showCleaning {
    NSArray *steps = [NSArray arrayWithObjects:[ExteriaCleaningStep stepNamed:NSLocalizedString(@"developer.popup.cleaning.one", nil) work:^{ [NSThread sleepForTimeInterval:0.8]; }],
                      [ExteriaCleaningStep stepNamed:NSLocalizedString(@"developer.popup.cleaning.two", nil) work:^{ [NSThread sleepForTimeInterval:0.8]; }], nil];
    ExteriaRunCleaning(steps, ^{});
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
#define ME ((ExteriaDeveloperSettingsController *)weak.target)
#define POPUP(symbol, titleKey, subtitleKey, body) \
    [ExteriaSettingsRow rowWithSymbol:symbol tone:ExteriaSettingsToneBlack title:NSLocalizedString(titleKey, nil) subtitle:NSLocalizedString(subtitleKey, nil) value:nil tap:^{ body }]
    NSArray *popups = [NSArray arrayWithObjects:
        POPUP(ExteriaSymbolReport, @"developer.popup.crash", @"developer.popup.crash.info", {
            if (!ExteriaAskCrashReport(^(BOOL send) { (void)send; })) ExteriaShowNotice(nil, NSLocalizedString(@"developer.popup.busy", nil));
        }),
        POPUP(ExteriaSymbolGlobe, @"developer.popup.shiro", @"developer.popup.shiro.info", {
            ExteriaShiro *shiro = ExteriaShiroActive();
            if (shiro) ExteriaShowShiroFailure(shiro);
            else ExteriaShowNotice(nil, NSLocalizedString(@"developer.popup.noshiro", nil));
        }),
        POPUP(ExteriaSymbolHeart, @"developer.popup.senko", @"developer.popup.senko.info", { [ME showSenko]; }),
        POPUP(ExteriaSymbolExternalLink, @"developer.popup.release", @"developer.popup.release.info", { ExteriaShowReleasePreview(ExteriaDeveloperHost()); }),
        POPUP(ExteriaSymbolMember, @"developer.popup.mark", @"developer.popup.mark.info", { [ME showMarkNotices]; }),
        POPUP(ExteriaSymbolChats, @"developer.popup.toast", @"developer.popup.toast.info", { [ME showToast]; }),
        POPUP(ExteriaSymbolBell, @"developer.popup.banner", @"developer.popup.banner.info", {
            [ExteriaInAppBanner showTitle:NSLocalizedString(@"developer.popup.banner", nil) body:NSLocalizedString(@"developer.popup.banner.text", nil) dialog:nil avatars:nil tap:^{}];
        }),
        POPUP(ExteriaSymbolStar, @"developer.popup.power", @"developer.popup.power.info", {
            [ExteriaInAppBanner showPowerTitle:NSLocalizedString(@"developer.popup.power", nil) body:NSLocalizedString(@"developer.popup.power.text", nil)];
        }),
        POPUP(ExteriaSymbolBroom, @"developer.popup.cleaning", @"developer.popup.cleaning.info", { [ME showCleaning]; }),
        nil];
    NSArray *system = [NSArray arrayWithObjects:
        POPUP(ExteriaSymbolInfo, @"developer.popup.notice", @"developer.popup.notice.info", {
            ExteriaShowNotice(NSLocalizedString(@"developer.popup.notice", nil), NSLocalizedString(@"developer.popup.notice.text", nil));
        }),
        POPUP(ExteriaSymbolCheckMark(), @"developer.popup.confirm", @"developer.popup.confirm.info", {
            ExteriaConfirm(NSLocalizedString(@"developer.popup.confirm", nil), NSLocalizedString(@"developer.popup.confirm.text", nil), NSLocalizedString(@"notice.ok", nil), ^{});
        }),
        POPUP(ExteriaSymbolEllipsis, @"developer.popup.choose", @"developer.popup.choose.info", {
            ExteriaChoose(NSLocalizedString(@"developer.popup.choose", nil), [NSArray arrayWithObjects:@"A", @"B", @"C", nil], -1, ^(NSInteger index) { (void)index; });
        }),
        POPUP(ExteriaSymbolCompose, @"developer.popup.prompt", @"developer.popup.prompt.info", {
            ExteriaPromptText(NSLocalizedString(@"developer.popup.prompt", nil), nil, @"", @"...", ^(NSString *text) { (void)text; });
        }),
        POPUP(ExteriaSymbolEllipsisVertical, @"developer.popup.menu", @"developer.popup.menu.info", {
            ExteriaDeveloperSettingsController *me = ME;
            [me showMenuAt:CGPointMake(me.view.bounds.size.width - 16, 120)];
        }),
        nil];
#undef POPUP
#undef ME
    /* the badges of the team on his own name, to see them where they are drawn */
    ExteriaSettingsRow *badges = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolStar tone:ExteriaSettingsToneBlack title:NSLocalizedString(@"developer.badges", nil)
                                                          subtitle:NSLocalizedString(@"developer.badges.row.info", nil) value:nil tap:^{
        ExteriaDeveloperSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[ExteriaDeveloperBadgesController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    ExteriaSettingsRow *logs = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolDocument tone:ExteriaSettingsToneBlack title:NSLocalizedString(@"logs.title", nil)
                                                        subtitle:NSLocalizedString(@"logs.row.info", nil) value:nil tap:^{
        ExteriaDeveloperSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[ExteriaLogsController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    ExteriaSettingsRow *readAll = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolCheckMark() tone:ExteriaSettingsToneBlack title:NSLocalizedString(@"developer.readall", nil)
                                                           subtitle:NSLocalizedString(@"developer.readall.info", nil) value:nil tap:^{
        ExteriaDeveloperSettingsController *me = weak.target;
        if (!me) return;
        ExteriaConfirm(NSLocalizedString(@"developer.readall", nil), NSLocalizedString(@"developer.readall.confirm", nil), NSLocalizedString(@"notice.ok", nil), ^{
            ExteriaDeveloperSettingsController *again = weak.target;
            if (again) [again markEverythingRead];
        });
    }];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    ExteriaSettingsRow *classic = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"developer.classic", nil) subtitle:NSLocalizedString(@"developer.classic.info", nil)
                                                                      on:[defaults boolForKey:ExteriaClassicAnywhereKey] toggle:^(BOOL on) {
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:ExteriaClassicAnywhereKey];
        /* the stored choice is dropped by the theme when the classic style is gone, and the screens are rebuilt */
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil];
    }];
    ExteriaSettingsRow *pad = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"developer.pad", nil) subtitle:NSLocalizedString(@"developer.pad.info", nil)
                                                                  on:[defaults boolForKey:ExteriaPadInterfaceKey] toggle:^(BOOL on) {
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:ExteriaPadInterfaceKey];
        /* the two switches name opposite interfaces, so one that goes on puts the other off */
        if (on) [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaPhoneInterfaceKey];
        [(ExteriaDeveloperSettingsController *)weak.target rebuild];
    }];
    ExteriaSettingsRow *phone = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"developer.phone", nil) subtitle:NSLocalizedString(@"developer.phone.info", nil)
                                                                    on:[defaults boolForKey:ExteriaPhoneInterfaceKey] toggle:^(BOOL on) {
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:ExteriaPhoneInterfaceKey];
        if (on) [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaPadInterfaceKey];
        [(ExteriaDeveloperSettingsController *)weak.target rebuild];
    }];
    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"developer.interface.header", nil) footer:NSLocalizedString(@"developer.interface.footer", nil) rows:[NSArray arrayWithObjects:classic, pad, phone, nil]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"logs.header", nil) footer:nil rows:[NSArray arrayWithObject:logs]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"developer.readall.header", nil) footer:nil rows:[NSArray arrayWithObject:readAll]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"developer.badges.header", nil) footer:nil rows:[NSArray arrayWithObject:badges]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"developer.popups", nil) footer:NSLocalizedString(@"developer.popups.info", nil) rows:popups],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"developer.system", nil) footer:nil rows:system],
        [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
            [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolCloseMark() title:NSLocalizedString(@"developer.hide", nil) destructive:YES tap:^{
                ExteriaDeveloperModeSet(NO);
                /* the switches belong to the page, so hiding it puts the interface back */
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaClassicAnywhereKey];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaPadInterfaceKey];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaPhoneInterfaceKey];
                [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDeveloperModeDidChangeNotification object:nil];
                [((ExteriaDeveloperSettingsController *)weak.target).navigationController popViewControllerAnimated:YES];
            }]]], nil];
}

@end
