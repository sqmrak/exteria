#import "exteria_ayu_controller.h"

#import "exteria_alert.h"
#import "exteria_ayu.h"
#import "exteria_chat_settings.h"
#import "exteria_gift_screen.h"
#import "exteria_session_saved.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"

static ExteriaSettingsRow *ExteriaAyuSwitch(NSString *titleKey, NSString *infoKey, ExteriaChatFlag flag, void (^changed)(void)) {
    return [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil on:ExteriaChatFlagGet(flag) toggle:^(BOOL on) {
        ExteriaChatFlagSet(flag, on);
        if (changed) changed();
    }];
}

#pragma mark ghost mode

@implementation ExteriaGhostController

- (id)init {
    self = [super init];
    if (!self) return nil;
    self.pageTitle = NSLocalizedString(@"ayu.ghost", nil);
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaGhostController alloc] init] autorelease];
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:ExteriaAyuSwitch(@"ayu.ghost.noread", @"ayu.ghost.noread.info", ExteriaChatFlagGhostNoRead, nil)];
    [rows addObject:ExteriaAyuSwitch(@"ayu.ghost.nostories", @"ayu.ghost.nostories.info", ExteriaChatFlagGhostNoStories, nil)];
    [rows addObject:ExteriaAyuSwitch(@"ayu.ghost.offline", @"ayu.ghost.offline.info", ExteriaChatFlagGhostOffline, nil)];
    self.sections = [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"ayu.ghost.info", nil) rows:rows]];
    [self reloadSettings];
}

@end

#pragma mark filters

@interface ExteriaRegexFiltersController () {
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaRegexFiltersController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"ayu.regex.title", nil);
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
    return [[[ExteriaRegexFiltersController alloc] init] autorelease];
}

- (void)store:(NSArray *)patterns {
    ExteriaAyuSetRegexList(patterns);
    /* an open chat takes the new list the next time its messages are put in order */
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
    [self rebuild];
}

- (void)addOrChange:(NSString *)old {
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(old ? @"ayu.regex.change" : @"ayu.regex.add", nil), NSLocalizedString(@"ayu.regex.hint", nil), old, NSLocalizedString(@"ayu.regex.placeholder", nil), ^(NSString *text) {
        ExteriaRegexFiltersController *me = weak.target;
        if (!me) return;
        NSString *pattern = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *problem = ExteriaAyuRegexProblem(pattern);
        if (problem) {
            ExteriaGiftAlert(nil, problem);
            return;
        }
        NSMutableArray *list = [NSMutableArray arrayWithArray:ExteriaAyuRegexList()];
        NSUInteger at = old ? [list indexOfObject:old] : NSNotFound;
        if (at != NSNotFound) [list replaceObjectAtIndex:at withObject:pattern];
        else [list addObject:pattern];
        [me store:list];
    });
}

- (void)choose:(NSString *)pattern {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsChoose(self, pattern, [NSArray arrayWithObjects:NSLocalizedString(@"ayu.regex.change", nil), NSLocalizedString(@"ayu.regex.remove", nil), nil], ^(NSUInteger index) {
        ExteriaRegexFiltersController *me = weak.target;
        if (!me) return;
        if (index == 0) {
            [me addOrChange:pattern];
            return;
        }
        NSMutableArray *list = [NSMutableArray arrayWithArray:ExteriaAyuRegexList()];
        [list removeObject:pattern];
        [me store:list];
    });
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *pattern in ExteriaAyuRegexList()) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:pattern value:nil tap:^{ [(ExteriaRegexFiltersController *)weak.target choose:pattern]; }]];
    }
    [rows addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolPlusCircle title:NSLocalizedString(@"ayu.regex.add", nil) destructive:NO tap:^{
        [(ExteriaRegexFiltersController *)weak.target addOrChange:nil];
    }]];
    self.sections = [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"ayu.regex.info", nil) rows:rows]];
    [self reloadSettings];
}

@end

#pragma mark AyuMoments

@interface ExteriaAyuController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    NSInteger _savedCount;
}
@end

@implementation ExteriaAyuController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _savedCount = -1;
    self.pageTitle = NSLocalizedString(@"ayu.title", nil);
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ExteriaWeakReference *weak = _weak;
    [_session countSavedMessages:^(NSInteger count, NSString *errorName) {
        ExteriaAyuController *me = weak.target;
        if (!me) return;
        if (errorName) NSLog(@"exteria: the saved messages were not counted: %@", errorName);
        me->_savedCount = errorName ? -1 : count;
        [me rebuild];
    }];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaAyuController alloc] initWithSession:_session] autorelease];
}

/* the keeping of messages is read by the part that handles the updates, so it is told at once; the open chats are not touched */
- (void)savingChanged {
    [_session setSavingSettingsFromDefaults];
    [self rebuild];
}

- (void)disableAll {
    static const ExteriaChatFlag flags[] = {ExteriaChatFlagGhostNoRead, ExteriaChatFlagGhostNoStories, ExteriaChatFlagGhostOffline, ExteriaChatFlagAyuRegex,
                                            ExteriaChatFlagAyuSaveDeleted, ExteriaChatFlagAyuSaveEdits};
    for (size_t i = 0; i < sizeof(flags) / sizeof(flags[0]); ++i) ExteriaChatFlagSet(flags[i], NO);
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
    [self savingChanged];
}

- (void)clearSaved {
    ExteriaWeakReference *weak = _weak;
    [_session clearSavedMessages:^(NSString *errorName) {
        ExteriaAyuController *me = weak.target;
        if (!me) return;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        me->_savedCount = 0;
        [me rebuild];
    }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    void (^saving)(void) = ^{ [(ExteriaAyuController *)weak.target savingChanged]; };
    NSMutableArray *sections = [NSMutableArray array];

    ExteriaSettingsRow *ghost = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolEyeSlash tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"ayu.ghost", nil) subtitle:nil value:nil tap:^{
        [[(ExteriaAyuController *)weak.target navigationController] pushViewController:[[[ExteriaGhostController alloc] init] autorelease] animated:YES];
    }];
    NSMutableArray *main = [NSMutableArray arrayWithObject:ghost];
    [main addObject:ExteriaAyuSwitch(@"ayu.regex.switch", nil, ExteriaChatFlagAyuRegex, ^{ [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil]; })];
    NSUInteger count = ExteriaAyuRegexList().count;
    [main addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"ayu.regex.title", nil) value:count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil tap:^{
        [[(ExteriaAyuController *)weak.target navigationController] pushViewController:[[[ExteriaRegexFiltersController alloc] init] autorelease] animated:YES];
    }]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"ayu.info", nil) rows:main]];

    NSMutableArray *saving1 = [NSMutableArray array];
    [saving1 addObject:ExteriaAyuSwitch(@"ayu.savedeleted", @"ayu.savedeleted.info", ExteriaChatFlagAyuSaveDeleted, saving)];
    if (ExteriaChatFlagGet(ExteriaChatFlagAyuSaveDeleted)) {
        [saving1 addObject:ExteriaAyuSwitch(@"ayu.deleted.private", nil, ExteriaChatFlagAyuDeletedPrivate, saving)];
        [saving1 addObject:ExteriaAyuSwitch(@"ayu.deleted.groups", nil, ExteriaChatFlagAyuDeletedGroups, saving)];
        [saving1 addObject:ExteriaAyuSwitch(@"ayu.deleted.channels", nil, ExteriaChatFlagAyuDeletedChannels, saving)];
        [saving1 addObject:ExteriaAyuSwitch(@"ayu.deleted.bots", nil, ExteriaChatFlagAyuDeletedBots, saving)];
        [saving1 addObject:ExteriaAyuSwitch(@"ayu.translucent", nil, ExteriaChatFlagAyuTranslucent, ^{ [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil]; })];
        [saving1 addObject:ExteriaAyuSwitch(@"ayu.replyquote", @"ayu.replyquote.info", ExteriaChatFlagAyuReplyQuote, nil)];
    }
    [saving1 addObject:ExteriaAyuSwitch(@"ayu.saveedits", @"ayu.saveedits.info", ExteriaChatFlagAyuSaveEdits, saving)];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"ayu.saving.header", nil) footer:nil rows:saving1]];

    NSMutableArray *danger = [NSMutableArray array];
    [danger addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolBlock title:NSLocalizedString(@"ayu.disableall", nil) destructive:YES tap:^{
        ExteriaAyuController *me = weak.target;
        if (!me) return;
        ExteriaConfirmAction(me, NSLocalizedString(@"ayu.disableall.confirm", nil), NSLocalizedString(@"ayu.disableall", nil), ^{ [(ExteriaAyuController *)weak.target disableAll]; });
    }]];
    NSString *cleared = _savedCount >= 0 ? [NSString stringWithFormat:NSLocalizedString(@"ayu.clear.count", nil), (long)_savedCount] : nil;
    [danger addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolTrash tone:ExteriaSettingsToneRed title:NSLocalizedString(@"ayu.clear", nil) subtitle:cleared value:nil tap:^{
        ExteriaAyuController *me = weak.target;
        if (!me) return;
        ExteriaConfirmAction(me, NSLocalizedString(@"ayu.clear.confirm", nil), NSLocalizedString(@"ayu.clear", nil), ^{ [(ExteriaAyuController *)weak.target clearSaved]; });
    }]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:danger]];

    self.sections = sections;
    [self reloadSettings];
}

@end
