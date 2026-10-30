#import "exteria_quick_reaction_controller.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_chat_settings.h"
#import "exteria_chat_preview_view.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_emoji_label.h"
#import "exteria_gift_screen.h"
#import "exteria_person.h"
#import "exteria_reaction_picker.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"
#include "exteria_reactions.h"

void ExteriaLoadQuickReactionPicture(ExteriaSession *session, ExteriaMediaCache *media, void (^picture)(void)) {
    long long document = exteria_quick_reaction_document(ExteriaChatQuickReaction().UTF8String);
    if (document && session && media)
        [ExteriaCustomEmojiLoader loadDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:document]] session:session media:media documents:nil picture:picture];
}

@interface ExteriaQuickReactionController () {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    ExteriaReactionPicker *_picker;
    NSArray *_choices;
    NSString *_error;
    BOOL _loaded;
    BOOL _premiumKnown;
    BOOL _premium;
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
    [_picker dismissAnimated:NO];
    [_picker release];
    [_weak release]; [_media release]; [_session release]; [_choices release]; [_error release];
    [super dealloc];
}
- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaQuickReactionController alloc] initWithSession:_session] autorelease];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    _media = [[ExteriaMediaCache alloc] initWithSession:_session directory:[[caches stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"media"]];
    [self rebuild];
    [self load];
}
- (void)load {
    _loaded = NO;
    _premiumKnown = NO;
    [_error release]; _error = nil;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaQuickReactionController *screen = weak.target;
        if (!screen) return;
        ExteriaPerson *person = items.count ? [items objectAtIndex:0] : nil;
        if (!person) {
            screen->_loaded = YES;
            screen->_error = [(errorName ? errorName : @"INTERNAL") copy];
            [screen rebuild];
            return;
        }
        screen->_premiumKnown = YES;
        screen->_premium = ExteriaPremiumEffective(person.premium);
        long long account = [ExteriaSession accountIdInDirectory:screen->_session.directory];
        ExteriaDialog *saved = account > 0 ? [ExteriaDialog savedMessagesOfUserId:account] : nil;
        if (!saved) { screen->_loaded = YES; screen->_error = [@"INTERNAL" copy]; [screen rebuild]; return; }
        [screen->_session loadAvailableReactionsForDialog:saved premium:screen->_premium completion:^(NSArray *choices, NSString *failure) {
            ExteriaQuickReactionController *page = weak.target;
            if (!page) return;
            page->_loaded = YES;
            [page->_choices release]; page->_choices = [choices copy];
            [page->_error release]; page->_error = [failure copy];
            [page rebuild];
        }];
    }];
    long long document = exteria_quick_reaction_document(ExteriaChatQuickReaction().UTF8String);
    if (document) [ExteriaCustomEmojiLoader loadDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:document]] session:_session media:_media documents:nil picture:^{
        [(ExteriaQuickReactionController *)weak.target rebuild];
    }];
}
- (void)closePicker {
    [_picker dismissAnimated:self.view.window != nil];
    [_picker release];
    _picker = nil;
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self closePicker];
}
- (void)openPicker {
    if (_picker || !_choices || !_premiumKnown) return;
    _picker = [[ExteriaReactionPicker alloc] initWithFrame:self.view.bounds];
    _picker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_picker attachSession:_session media:_media premium:_premium];
    NSMutableArray *marked = [NSMutableArray array];
    for (ExteriaReaction *choice in _choices) {
        exteria_reaction row = choice.row;
        row.chosen = (row.kind == EXTERIA_REACTION_EMOJI && [choice.emoji isEqualToString:ExteriaChatQuickReaction()]) ||
            (row.kind == EXTERIA_REACTION_CUSTOM && row.document_id == exteria_quick_reaction_document(ExteriaChatQuickReaction().UTF8String));
        [marked addObject:[ExteriaReaction reactionWithRow:&row]];
    }
    [_picker setReactions:marked];
    ExteriaWeakReference *weak = _weak;
    _picker.cancelHandler = ^{ [(ExteriaQuickReactionController *)weak.target closePicker]; };
    _picker.pickHandler = ^(ExteriaReaction *reaction) {
        ExteriaQuickReactionController *page = weak.target;
        if (!page) return;
        if (reaction.row.kind == EXTERIA_REACTION_CUSTOM && !page->_premium) { ExteriaGiftAlert(nil, NSLocalizedString(@"chat.reaction.premium", nil)); return; }
        if (reaction.row.kind == EXTERIA_REACTION_EMOJI && reaction.emoji.length) ExteriaChatSetQuickReaction(reaction.emoji);
        else if (reaction.row.kind == EXTERIA_REACTION_CUSTOM && reaction.row.document_id > 0)
            ExteriaChatSetQuickCustomReaction(reaction.row.document_id, reaction.displayText);
        else return;
        [page closePicker];
        [page rebuild];
    };
    _picker.customPickHandler = ^(ExteriaCustomEmojiDocument *emoji) {
        ExteriaQuickReactionController *page = weak.target;
        if (!page || emoji.documentId <= 0) return;
        if (!page->_premium) { ExteriaGiftAlert(nil, NSLocalizedString(@"chat.reaction.premium", nil)); return; }
        ExteriaChatSetQuickCustomReaction(emoji.documentId, emoji.alt);
        [page closePicker];
        [page rebuild];
    };
    [self.view addSubview:_picker];
}
- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaChatPreviewView *preview = [[[ExteriaChatPreviewView alloc] initWithTalk:ExteriaChatPreviewTalkQuickReaction] autorelease];
    [preview setQuickReaction:ExteriaChatQuickReaction() display:ExteriaChatQuickReactionDisplay()];
    preview.heightHandler = ^{ [(ExteriaQuickReactionController *)weak.target updateRowHeights]; };
    ExteriaSettingsRow *previewRow = [ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }];
    NSMutableArray *sections = [NSMutableArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil
        footer:NSLocalizedString(@"chatset.quickreaction.info", nil) rows:[NSArray arrayWithObject:previewRow]]];
    NSMutableArray *rows = [NSMutableArray array];
    if (_premiumKnown && _choices) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chatset.quickreaction", nil) value:nil tap:^{
            [(ExteriaQuickReactionController *)weak.target openPicker];
        }]];
    }
    if (_error) [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"list.retry", nil) value:nil tap:^{
        [(ExteriaQuickReactionController *)weak.target load];
    }]];
    NSString *footer = !_loaded ? NSLocalizedString(@"profile.loading", nil) : (_error ? ExteriaGiftErrorText(_error) : (rows.count ? nil : NSLocalizedString(@"chats.nothing", nil)));
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}
@end
