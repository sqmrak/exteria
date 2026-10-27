#import "exteria_data_settings_controller.h"

#import "exteria_draft.h"
#import "exteria_gift_screen.h"
#import "exteria_memory_controller.h"
#import "exteria_network_usage_controller.h"
#import "exteria_session_data.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_traffic_store.h"
#import "exteria_weak_reference.h"

static NSString *ExteriaDataSize(unsigned long long bytes) {
    if (!bytes) return nil;
    if (bytes >= 1024ull * 1024ull * 1024ull) return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    if (bytes >= 1024ull * 1024ull) return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
}

@interface ExteriaDataSettingsController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    BOOL _busy;
}
@end

@implementation ExteriaDataSettingsController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.data", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
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
    return [[[ExteriaDataSettingsController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
}

- (void)clearDrafts {
    if (_busy) return;
    _busy = YES;
    ExteriaWeakReference *weak = _weak;
    [_session clearAllDraftsWithCompletion:^(NSString *errorName) {
        ExteriaDataSettingsController *me = weak.target;
        if (!me) return;
        me->_busy = NO;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [me->_session.drafts removeAll];
        ExteriaGiftAlert(nil, NSLocalizedString(@"data.drafts.done", nil));
    }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaTrafficTotals totals = ExteriaTrafficRead();
    unsigned long long network = totals.sent[0] + totals.sent[1] + totals.received[0] + totals.received[1];
    ExteriaSettingsRow *memory = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolBroom tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"memory.title", nil) subtitle:nil
                                                             value:ExteriaDataSize([_avatars diskBytes] + [_media diskBytes]) tap:^{
        ExteriaDataSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[ExteriaMemoryController alloc] initWithAvatars:me->_avatars media:me->_media] autorelease] animated:YES];
    }];
    ExteriaSettingsRow *usage = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolGlobe tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"netusage.title", nil) subtitle:nil
                                                            value:ExteriaDataSize(network) tap:^{
        [[(ExteriaDataSettingsController *)weak.target navigationController] pushViewController:[[[ExteriaNetworkUsageController alloc] init] autorelease] animated:YES];
    }];
    ExteriaSettingsRow *drafts = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolTrash title:NSLocalizedString(@"data.drafts", nil) destructive:YES tap:^{
        ExteriaDataSettingsController *me = weak.target;
        if (!me) return;
        ExteriaConfirmAction(me, NSLocalizedString(@"data.drafts.confirm", nil), NSLocalizedString(@"data.drafts.action", nil), ^{ [(ExteriaDataSettingsController *)weak.target clearDrafts]; });
    }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"data.usage", nil) footer:nil rows:[NSArray arrayWithObjects:memory, usage, nil]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"data.drafts.header", nil) footer:NSLocalizedString(@"data.drafts.info", nil) rows:[NSArray arrayWithObject:drafts]]];
    self.sections = sections;
    [self reloadSettings];
}

@end
