#import "exteria_quick_reaction_controller.h"

#import "exteria_chat_settings.h"
#import "exteria_gift_screen.h"
#import "exteria_weak_reference.h"

@interface ExteriaQuickReactionController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    NSArray *_choices;
    NSString *_error;
    BOOL _loaded;
}
@end

@implementation ExteriaQuickReactionController
- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.quickreaction", nil);
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_choices release];
    [_error release];
    [super dealloc];
}
- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaQuickReactionController alloc] initWithSession:_session] autorelease];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    long long account = [ExteriaSession accountIdInDirectory:_session.directory];
    ExteriaDialog *saved = account > 0 ? [ExteriaDialog savedMessagesOfUserId:account] : nil;
    if (!saved) { _loaded = YES; _error = [@"INTERNAL" copy]; [self rebuild]; return; }
    ExteriaWeakReference *weak = _weak;
    [_session loadAvailableReactionsForDialog:saved premium:NO completion:^(NSArray *choices, NSString *errorName) {
        ExteriaQuickReactionController *screen = weak.target;
        if (!screen) return;
        screen->_loaded = YES;
        [screen->_choices release]; screen->_choices = [choices copy];
        [screen->_error release]; screen->_error = [errorName copy];
        [screen rebuild];
    }];
}
- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    ExteriaWeakReference *weak = _weak;
    for (ExteriaReaction *choice in _choices) {
        if (choice.row.kind != EXTERIA_REACTION_EMOJI || !choice.emoji.length) continue;
        NSString *emoji = choice.emoji;
        ExteriaSettingsRow *row = [ExteriaSettingsRow checkRowWithTitle:emoji subtitle:nil checked:[ExteriaChatQuickReaction() isEqualToString:emoji] tap:^{
            ExteriaChatSetQuickReaction(emoji);
            [(ExteriaQuickReactionController *)weak.target rebuild];
        }];
        [rows addObject:row];
    }
    NSString *footer = !_loaded ? NSLocalizedString(@"profile.loading", nil) : (_error ? ExteriaGiftErrorText(_error) : (rows.count ? nil : NSLocalizedString(@"chats.nothing", nil)));
    self.sections = [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    [self reloadSettings];
}
@end
