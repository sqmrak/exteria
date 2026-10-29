#import "exteria_more_settings_controller.h"

#import "exteria_alert.h"
#import "exteria_ayu_controller.h"
#import "exteria_chat_settings.h"
#import "exteria_gift_screen.h"
#import "exteria_problem_report.h"
#import "exteria_proxy_settings.h"
#import "exteria_session_data.h"
#import "exteria_settings_reset.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"
#include "exteria_bytes.h"

@interface ExteriaMoreSettingsController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    BOOL _deleting;
}
@end

@implementation ExteriaMoreSettingsController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"about.more", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
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
    return [[[ExteriaMoreSettingsController alloc] initWithSession:_session] autorelease];
}

/* the screens read these settings when they are built, so the main controller builds them again, from the row that was touched */
- (void)apply {
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:ExteriaThemeOriginKey]];
}

#pragma mark deleting the account

/* two questions, the second asking for the word, since nothing brings the account back */
- (void)askDeleteAccount {
    if (_deleting) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"more.delete.confirm", nil), NSLocalizedString(@"more.delete.action", nil), ^{
        ExteriaPromptText(NSLocalizedString(@"more.delete.title", nil), [NSString stringWithFormat:NSLocalizedString(@"more.delete.type", nil), NSLocalizedString(@"more.delete.word", nil)], nil, nil, ^(NSString *text) {
            ExteriaMoreSettingsController *me = weak.target;
            if (!me) return;
            NSString *typed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([typed caseInsensitiveCompare:NSLocalizedString(@"more.delete.word", nil)] != NSOrderedSame) {
                ExteriaGiftAlert(nil, NSLocalizedString(@"more.delete.mismatch", nil));
                return;
            }
            [me deleteAccountNow];
        });
    });
}

static NSString *ExteriaDeleteErrorText(NSString *errorName) {
    /* an account with a cloud password has to wait for the deletion; the wait starts with the first try */
    if ([errorName hasPrefix:@"2FA_CONFIRM_WAIT"]) return NSLocalizedString(@"more.delete.wait", nil);
    if ([errorName hasPrefix:@"2FA_RECENT_CONFIRM"]) return NSLocalizedString(@"more.delete.recent", nil);
    return ExteriaGiftErrorText(errorName);
}

- (void)deleteAccountNow {
    _deleting = YES;
    ExteriaWeakReference *weak = _weak;
    [_session deleteAccountWithReason:@"Deleted from Exteria" completion:^(NSString *errorName) {
        ExteriaMoreSettingsController *me = weak.target;
        if (!me) return;
        me->_deleting = NO;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaDeleteErrorText(errorName));
            return;
        }
        /* the server dropped the account, and the connection tells the app, which goes to the next account or to the welcome screen */
        ExteriaGiftAlert(nil, NSLocalizedString(@"more.delete.done", nil));
    }];
}

#pragma mark rows

- (ExteriaSettingsRow *)flagRow:(NSString *)titleKey info:(NSString *)infoKey flag:(ExteriaChatFlag)flag rebuild:(BOOL)rebuild {
    ExteriaWeakReference *weak = _weak;
    return [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil on:ExteriaChatFlagGet(flag)
                                           toggle:^(BOOL on) {
        ExteriaChatFlagSet(flag, on);
        if (rebuild) [(ExteriaMoreSettingsController *)weak.target apply];
    }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    ExteriaSettingsRow *reports = [self flagRow:@"more.reports" info:nil flag:ExteriaChatFlagCrashReports rebuild:NO];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"more.reports.header", nil)
                                                           footer:nil
                                                             rows:[NSArray arrayWithObject:reports]]];

    exteria_proxy proxy;
    BOOL proxyEnabled = NO;
    exteria_status proxyStatus = ExteriaProxyRead(&proxy, &proxyEnabled);
    exteria_wipe(&proxy, sizeof(proxy));
    ExteriaSettingsRow *proxyToggle = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"proxy.current", nil)
        subtitle:ExteriaProxyDisplay() on:proxyEnabled toggle:^(BOOL on) {
            exteria_status status = ExteriaProxySetEnabled(on);
            if (status != EXTERIA_OK) ExteriaGiftAlert(nil, NSLocalizedString(status == EXTERIA_E_NOTFOUND ? @"proxy.invalid" : @"proxy.savefailed", nil));
            [(ExteriaMoreSettingsController *)weak.target rebuild];
        }];
    if (proxyStatus != EXTERIA_OK) NSLog(@"exteria: proxy settings unavailable: %s", exteria_status_name(proxyStatus));
    ExteriaSettingsRow *proxyAdd = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"proxy.add", nil) value:nil tap:^{
        ExteriaPromptText(NSLocalizedString(@"proxy.add", nil), nil, nil, NSLocalizedString(@"proxy.link.hint", nil), ^(NSString *text) {
            if (!text.length) return;
            exteria_status status = ExteriaProxyStoreLink([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
            if (status != EXTERIA_OK) ExteriaGiftAlert(nil, NSLocalizedString(status == EXTERIA_E_LIMIT ? @"proxy.limit" : status == EXTERIA_E_STORAGE ? @"proxy.savefailed" : @"proxy.invalid", nil));
            [(ExteriaMoreSettingsController *)weak.target rebuild];
        });
    }];
    NSMutableArray *proxyRows = [NSMutableArray arrayWithObject:proxyToggle];
    NSArray *savedProxies = nil;
    exteria_status listStatus = ExteriaProxyList(&savedProxies);
    if (listStatus != EXTERIA_OK) {
        NSLog(@"exteria: saved proxies unavailable: %s", exteria_status_name(listStatus));
        [proxyRows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"proxy.savefailed", nil) value:nil tap:nil]];
    }
    for (NSUInteger i = 0; i < savedProxies.count; ++i) {
        NSDictionary *entry = [savedProxies objectAtIndex:i];
        NSString *address = [entry objectForKey:@"address"];
        BOOL selected = [[entry objectForKey:@"selected"] boolValue];
        [proxyRows addObject:[ExteriaSettingsRow checkRowWithTitle:address subtitle:nil checked:selected tap:^{
            ExteriaMoreSettingsController *page = weak.target;
            if (!page) return;
            ExteriaSettingsChoose(page, address, [NSArray arrayWithObjects:NSLocalizedString(@"proxy.select", nil), NSLocalizedString(@"proxy.remove", nil), nil], ^(NSUInteger action) {
                exteria_status status = action == 0 ? ExteriaProxySelect(i) : ExteriaProxyRemove(i);
                if (status != EXTERIA_OK) ExteriaGiftAlert(nil, NSLocalizedString(@"proxy.savefailed", nil));
                [(ExteriaMoreSettingsController *)weak.target rebuild];
            });
        }]];
    }
    [proxyRows addObject:proxyAdd];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"proxy.title", nil) footer:NSLocalizedString(@"proxy.info", nil) rows:proxyRows]];

    ExteriaSettingsRow *ayu = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolEyeSlash tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"ayu.title", nil) subtitle:nil value:nil tap:^{
        ExteriaMoreSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[ExteriaAyuController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"more.ayu.header", nil) footer:NSLocalizedString(@"ayu.info", nil) rows:[NSArray arrayWithObject:ayu]]];

    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"more.experimental", nil) footer:NSLocalizedString(@"more.localpremium.info", nil)
                                                             rows:[NSArray arrayWithObject:[self flagRow:@"more.localpremium" info:nil flag:ExteriaChatFlagLocalPremium rebuild:YES]]]];

    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"more.other", nil) footer:NSLocalizedString(@"more.boykisser.info", nil)
                                                             rows:[NSArray arrayWithObject:[self flagRow:@"more.boykisser" info:nil flag:ExteriaChatFlagBoykisser rebuild:YES]]]];

    ExteriaSettingsRow *reset = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolRotate title:NSLocalizedString(@"more.reset", nil) destructive:YES tap:^{
        ExteriaMoreSettingsController *me = weak.target;
        if (!me) return;
        ExteriaConfirmAction(me, NSLocalizedString(@"more.reset.info", nil), NSLocalizedString(@"more.reset", nil), ^{
            ExteriaResetSettings();
            [(ExteriaMoreSettingsController *)weak.target apply];
        });
    }];
    ExteriaSettingsRow *delete = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolTrash title:NSLocalizedString(@"more.delete", nil) destructive:YES tap:^{
        [(ExteriaMoreSettingsController *)weak.target askDeleteAccount];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"more.reset.footer", nil) rows:[NSArray arrayWithObjects:reset, delete, nil]]];

    self.sections = sections;
    [self reloadSettings];
}

@end
