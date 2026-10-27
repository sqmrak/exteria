#import "exteria_chat_bots.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_chat_settings.h"
#import "exteria_bot_keyboard_view.h"
#import "exteria_dialog_picker_controller.h"
#import "exteria_emoji_label.h"
#import "exteria_remote_file.h"
#import "exteria_session_channels.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#include "exteria_links.h"
#include "exteria_mention.h"

#define INLINE_DELAY 0.4
#define PANEL_MAX_FRACTION 0.6
#define CARD_WIDTH_MAX 300.0
#define MENTION_ROWS_MAX 30
/* the typing pauses this long before the members of a supergroup are searched for the name */
#define MENTION_SEARCH_DELAY 0.3

typedef enum { ExteriaPanelNone, ExteriaPanelCommands, ExteriaPanelInline, ExteriaPanelMention } ExteriaPanelMode;

/* a name looked up for inline mode: the bot, or NSNull when the name is no bot that answers queries */
@interface ExteriaInlineBot : NSObject {
@public
    ExteriaPerson *person;
    ExteriaDialog *dialog;
}
@end

@implementation ExteriaInlineBot
- (void)dealloc {
    [person release];
    [dialog release];
    [super dealloc];
}
@end

@interface ExteriaChatBots () {
    ExteriaPerson *_bot;
    ExteriaBotInfo *_info;
    BOOL _infoRequested;
    NSArray *_messages;
    BOOL _loaded;
    BOOL _starting;
    BOOL _autoStarted;

    ExteriaMarkup *_keyboard;
    int32_t _keyboardMessageId;
    int32_t _seenKeyboardId;
    BOOL _keyboardOpen;
    ExteriaBotKeyboardView *_keyboardView;

    ExteriaSuggestionPanel *_panel;
    ExteriaPanelMode _mode;
    NSMutableDictionary *_inlineBots;
    ExteriaInlineBot *_inlineBot;
    NSString *_inlineQuery;
    NSString *_nextOffset;
    NSUInteger _inlineToken;
    long long _inlineQueryId;
    BOOL _loadingMore;
    /* the members of a supergroup the server named for the name typed after an @, and which search they answer */
    NSArray *_mentionRemote;
    NSUInteger _mentionToken;

    ExteriaMarkupButton *_busyButton;
    ExteriaMessageCell *_busyCell;
    UIView *_card;
    NSString *_startParam;
    NSString *_cardKey;
    BOOL _cardShown;
    BOOL _keyboardOpenedOnce;
}
@end

@implementation ExteriaChatBots

@synthesize host = _host;
@synthesize panel = _panel;
@synthesize card = _card;
@synthesize startParam = _startParam;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog router:(ExteriaLinkRouter *)router media:(ExteriaMediaCache *)media
                 host:(id<ExteriaChatBotsHost>)host {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _router = [router retain];
    _media = [media retain];
    _host = host;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _inlineBots = [[NSMutableDictionary alloc] init];
    if (dialog.kind == EXTERIA_DIALOG_BOT && dialog.peerKind == 1) {
        exteria_person_row row;
        memset(&row, 0, sizeof(row));
        row.id = dialog.peerId;
        row.access_hash = dialog.peerHash;
        row.bot = 1;
        snprintf(row.name, sizeof(row.name), "%s", dialog.title.UTF8String);
        _bot = [[ExteriaPerson alloc] initWithRow:&row];
    }
    return self;
}

- (void)dealloc {
    [self teardown];
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_router release];
    [_media release];
    [_bot release];
    [_info release];
    [_messages release];
    [_keyboard release];
    [_keyboardView release];
    [_panel release];
    [_inlineBots release];
    [_mentionRemote release];
    [_inlineBot release];
    [_inlineQuery release];
    [_nextOffset release];
    [_busyButton release];
    [_busyCell release];
    [_card release];
    [_startParam release];
    [_cardKey release];
    [super dealloc];
}

- (void)teardown {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    ++_inlineToken;
    ++_mentionToken;
}

- (ExteriaInputBar *)bar { return [_host botsInputBar]; }

#pragma mark bot info

- (void)start {
    if (!_bot || _infoRequested) return;
    _infoRequested = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadBotInfoOfPerson:_bot completion:^(ExteriaBotInfo *info, NSString *errorName) {
        ExteriaChatBots *bots = weak.target;
        if (!bots) return;
        if (!info) {
            NSLog(@"exteria: bot info of %lld did not load: %@", bots->_dialog.peerId, errorName);
            return;
        }
        [bots->_info release];
        bots->_info = [info retain];
        [bots infoLoaded];
    }];
}

- (void)infoLoaded {
    ExteriaInputBar *bar = [self bar];
    bar.menuTitle = _info.commands.count ? NSLocalizedString(@"bots.menu", nil) : nil;
    [self refreshCard];
    [_host botsRelayout];
}

#pragma mark state from messages

/* the newest message of the bot that says something about the keyboard decides what the keyboard is; a single use keyboard
   is gone once the person has answered it, and one the bot hid is gone for good */
- (void)messagesChanged:(NSArray *)messages loaded:(BOOL)loaded {
    [_messages release];
    _messages = [messages retain];
    _loaded = loaded;
    [self updateKeyboard];
    [self updateStart];
    [self refreshCard];
    [self autoStartIfNeeded];
}

- (void)updateKeyboard {
    ExteriaMarkup *found = nil;
    int32_t foundId = 0;
    for (NSInteger i = (NSInteger)_messages.count - 1; i >= 0; --i) {
        ExteriaMessage *message = [_messages objectAtIndex:(NSUInteger)i];
        if (message.outgoing || message.service || !message.markup) continue;
        exteria_markup_kind kind = message.markup.kind;
        if (kind == EXTERIA_MARKUP_INLINE) continue;
        found = message.markup;
        foundId = message.messageId;
        break;
    }
    BOOL answered = NO;
    if (found && (found.singleUse || found.kind == EXTERIA_MARKUP_FORCE_REPLY)) {
        for (ExteriaMessage *message in _messages) if (message.outgoing && (message.messageId > foundId || message.messageId <= 0)) answered = YES;
    }
    if (found && (found.kind == EXTERIA_MARKUP_HIDE || answered)) found = nil;
    BOOL changed = (found == nil) != (_keyboard == nil) || foundId != _keyboardMessageId;
    if (!changed && found && ![found isEqualMarkup:_keyboard]) changed = YES;
    if (!changed) {
        /* the page that came from the network settles what the cached one showed */
        if (_keyboard.kind == EXTERIA_MARKUP_KEYBOARD && _loaded && !_keyboardOpenedOnce) {
            _keyboardOpenedOnce = YES;
            [self openKeyboard];
        }
        return;
    }
    BOOL fresh = foundId > _seenKeyboardId;
    [_keyboard release];
    _keyboard = [found retain];
    _keyboardMessageId = foundId;
    if (found) _seenKeyboardId = MAX(_seenKeyboardId, foundId);
    ExteriaInputBar *bar = [self bar];
    if (_keyboard.kind == EXTERIA_MARKUP_FORCE_REPLY) {
        bar.botKeyboardState = ExteriaBotKeyboardNone;
        bar.placeholderText = _keyboard.placeholder.length ? _keyboard.placeholder : nil;
        [self closeKeyboard];
        if (fresh && _loaded) [bar.textView becomeFirstResponder];
        return;
    }
    bar.placeholderText = _keyboard.placeholder.length ? _keyboard.placeholder : nil;
    if (!_keyboard) {
        [self closeKeyboard];
        bar.botKeyboardState = ExteriaBotKeyboardNone;
        return;
    }
    [self fillKeyboard];
    /* a keyboard that has just arrived opens by itself, as the other clients do, and so does the one a chat has when it is opened; one
       that was there already stays as the person left it */
    if (_loaded && (fresh || !_keyboardOpenedOnce)) {
        _keyboardOpenedOnce = YES;
        [self openKeyboard];
    } else {
        bar.botKeyboardState = _keyboardOpen ? ExteriaBotKeyboardOpen : ExteriaBotKeyboardOffered;
    }
}

- (ExteriaBotKeyboardView *)keyboardView {
    if (!_keyboardView) {
        _keyboardView = [[ExteriaBotKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 216)];
        ExteriaWeakReference *weak = _weak;
        _keyboardView.pressHandler = ^(ExteriaMarkupButton *button) {
            ExteriaChatBots *bots = weak.target;
            if (bots) [bots pressKey:button];
        };
    }
    return _keyboardView;
}

- (void)fillKeyboard {
    ExteriaBotKeyboardView *view = [self keyboardView];
    [view setMarkup:_keyboard];
    CGFloat width = [UIScreen mainScreen].bounds.size.width;
    CGFloat height = [view preferredHeightForWidth:width maxHeight:[_host botsKeyboardMaxHeight]];
    view.frame = CGRectMake(0, 0, width, MAX(height, 1));
}

- (void)openKeyboard {
    if (!_keyboard || _keyboard.kind != EXTERIA_MARKUP_KEYBOARD) return;
    _keyboardOpen = YES;
    [self fillKeyboard];
    [self bar].botKeyboardState = ExteriaBotKeyboardOpen;
    [_host botsSetInputView:_keyboardView];
}

- (void)closeKeyboard {
    if (!_keyboardOpen) return;
    _keyboardOpen = NO;
    [_host botsSetInputView:nil];
}

- (void)emojiPanelWillChange {
    if (!_keyboardOpen) return;
    _keyboardOpen = NO;
    [self bar].botKeyboardState = ExteriaBotKeyboardOffered;
}

- (void)keyboardButtonTapped {
    if (_keyboardOpen) {
        _keyboardOpen = NO;
        [self bar].botKeyboardState = ExteriaBotKeyboardOffered;
        [_host botsSetInputView:nil];
    } else {
        [self openKeyboard];
    }
}

- (int32_t)replyTargetForText {
    return _keyboard.kind == EXTERIA_MARKUP_FORCE_REPLY ? _keyboardMessageId : 0;
}

- (void)didSendText {
    [self hidePanel];
    /* a keyboard of one use goes away with the answer */
    if (_keyboard.singleUse && _keyboardOpen) {
        _keyboardOpen = NO;
        [self bar].botKeyboardState = ExteriaBotKeyboardNone;
        [_host botsSetInputView:nil];
    }
}

#pragma mark start and menu

- (void)updateStart {
    ExteriaInputBar *bar = [self bar];
    BOOL empty = _loaded && _messages.count == 0 && _bot && !_starting;
    bar.actionTitle = empty ? NSLocalizedString(@"bots.start", nil) : nil;
}

/* a link that carried a parameter into a chat that already has a conversation starts the bot with it at once */
- (void)autoStartIfNeeded {
    if (!_bot || !_loaded || _autoStarted || !_startParam.length || _messages.count == 0) return;
    _autoStarted = YES;
    [self startWithParam:_startParam];
}

- (void)startWithParam:(NSString *)param {
    if (!_bot || _starting) return;
    _starting = YES;
    [self bar].actionTitle = nil;
    ExteriaWeakReference *weak = _weak;
    [_session startBot:_bot inDialog:_dialog param:param ? param : @"" randomId:[_host botsRandomId] completion:^(int32_t messageId, NSString *errorName) {
        (void)messageId;
        ExteriaChatBots *bots = weak.target;
        if (!bots) return;
        bots->_starting = NO;
        if (errorName) {
            [bots->_router showNote:[ExteriaLinkRouter textForError:errorName]];
            [bots updateStart];
            [bots->_host botsRelayout];
        }
    }];
    [_host botsRelayout];
}

- (void)actionTapped {
    NSString *param = [[_startParam retain] autorelease];
    [_startParam release];
    _startParam = nil;
    _autoStarted = YES;
    [self startWithParam:param];
}

- (void)menuTapped {
    if (_mode == ExteriaPanelCommands) {
        [self hidePanel];
        return;
    }
    [self showCommandsMatching:@""];
}

#pragma mark description card

/* the empty chat of a bot says what the bot does, in the words and with the picture the bot gave */
- (void)refreshCard {
    BOOL show = _bot && _loaded && _messages.count == 0 && (_info.botDescription.length || _info.picture);
    if (!show) {
        _card.hidden = YES;
        _cardShown = NO;
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%@|%d", _info.botDescription, _info.picture != nil];
    if (!_card || ![key isEqualToString:_cardKey]) {
        [_card removeFromSuperview];
        [_card release];
        _card = [[UIView alloc] init];
        _card.backgroundColor = ExteriaColorBubbleIn();
        _card.layer.cornerRadius = 14;
        [_cardKey release];
        _cardKey = [key copy];
        UILabel *title = [[[UILabel alloc] init] autorelease];
        title.tag = 1;
        title.backgroundColor = [UIColor clearColor];
        title.font = ExteriaFontSemibold(16);
        title.textColor = ExteriaColorTitle();
        title.textAlignment = ExteriaTextAlignmentCenter;
        title.text = NSLocalizedString(@"bots.card.title", nil);
        [_card addSubview:title];
        /* a bot's description is written by its author, with emoji the system font may lack */
        ExteriaEmojiLabel *body = [[[ExteriaEmojiLabel alloc] init] autorelease];
        body.tag = 2;
        body.font = ExteriaFontRegular(15);
        body.textColor = ExteriaColorTitle();
        body.numberOfLines = 0;
        body.text = _info.botDescription;
        [_card addSubview:body];
        UIImageView *picture = [[[UIImageView alloc] init] autorelease];
        picture.tag = 3;
        picture.contentMode = UIViewContentModeScaleAspectFill;
        picture.clipsToBounds = YES;
        picture.layer.cornerRadius = 8;
        picture.hidden = _info.picture == nil;
        [_card addSubview:picture];
        ExteriaRemoteFile *file = _info.picture.previewFile ? _info.picture.previewFile : _info.picture.file;
        if (file) {
            ExteriaWeakReference *weak = _weak;
            [_media loadImageForFile:file maxSide:600 completion:^(UIImage *image) {
                ExteriaChatBots *bots = weak.target;
                UIImageView *view = (UIImageView *)[bots->_card viewWithTag:3];
                if (image && view) view.image = image;
            }];
        }
        [[_host botsContainerView] addSubview:_card];
    }
    _card.hidden = NO;
    if (!_cardShown) {
        _cardShown = YES;
        [_host botsRelayout];
    }
}

- (void)layoutCardInRect:(CGRect)rect {
    if (!_card || _card.hidden) return;
    CGFloat width = MIN(CARD_WIDTH_MAX, rect.size.width - 40);
    UILabel *title = (UILabel *)[_card viewWithTag:1];
    ExteriaEmojiLabel *body = (ExteriaEmojiLabel *)[_card viewWithTag:2];
    UIImageView *picture = (UIImageView *)[_card viewWithTag:3];
    CGFloat y = 14;
    title.frame = CGRectMake(14, y, width - 28, 22);
    y += 30;
    if (!picture.hidden) {
        CGFloat side = width - 28;
        picture.frame = CGRectMake(14, y, side, MIN(side * 0.6, 170));
        y += picture.frame.size.height + 10;
    }
    CGSize fit = [body sizeThatFits:CGSizeMake(width - 28, 1000)];
    body.frame = CGRectMake(14, y, width - 28, MIN(fit.height, MAX(40, rect.size.height - y - 30)));
    y += body.frame.size.height + 14;
    _card.frame = CGRectMake(CGRectGetMidX(rect) - width / 2, CGRectGetMidY(rect) - y / 2, width, y);
}

#pragma mark panel

- (ExteriaSuggestionPanel *)ensurePanel {
    if (_panel) return _panel;
    _panel = [[ExteriaSuggestionPanel alloc] initWithSession:_session media:_media];
    ExteriaWeakReference *weak = _weak;
    _panel.pickHandler = ^(ExteriaSuggestion *suggestion) {
        ExteriaChatBots *bots = weak.target;
        if (bots) [bots pickSuggestion:suggestion];
    };
    _panel.moreHandler = ^{
        ExteriaChatBots *bots = weak.target;
        if (bots) [bots loadMoreInline];
    };
    [[_host botsContainerView] addSubview:_panel];
    return _panel;
}

- (void)hidePanel {
    ++_inlineToken;
    ++_mentionToken;
    _mode = ExteriaPanelNone;
    [_panel removeFromSuperview];
    [_panel release];
    _panel = nil;
    [_host botsRelayout];
}

- (CGFloat)panelHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight {
    if (!_panel) return 0;
    return [_panel preferredHeightForWidth:width maxHeight:maxHeight * PANEL_MAX_FRACTION];
}

#pragma mark commands

- (void)showCommandsMatching:(NSString *)prefix {
    if (!_info.commands.count) {
        if (_mode == ExteriaPanelCommands) [self hidePanel];
        return;
    }
    NSMutableArray *rows = [NSMutableArray array];
    NSString *needle = prefix.lowercaseString;
    for (ExteriaBotCommand *command in _info.commands) {
        if (needle.length && ![command.name.lowercaseString hasPrefix:needle]) continue;
        [rows addObject:[[[ExteriaSuggestion alloc] initWithTitle:[@"/" stringByAppendingString:command.name] subtitle:command.text media:nil webFile:nil
                                                         payload:command] autorelease]];
    }
    if (!rows.count) {
        if (_mode == ExteriaPanelCommands) [self hidePanel];
        return;
    }
    ++_inlineToken;
    _mode = ExteriaPanelCommands;
    ExteriaSuggestionPanel *panel = [self ensurePanel];
    [panel setHeaderTitle:nil handler:nil];
    [panel setLoading:NO];
    [panel setSuggestions:rows gallery:NO];
    [_host botsRelayout];
}

- (void)pickSuggestion:(ExteriaSuggestion *)suggestion {
    if (_mode == ExteriaPanelMention) {
        [self insertMention:suggestion.payload];
        return;
    }
    if (_mode == ExteriaPanelCommands) {
        ExteriaBotCommand *command = suggestion.payload;
        ExteriaInputBar *bar = [self bar];
        [bar clear];
        [self hidePanel];
        [_host botsSendText:[@"/" stringByAppendingString:command.name] replyTo:0];
        return;
    }
    if (_mode == ExteriaPanelInline) [self sendInlineResult:suggestion.payload];
}

#pragma mark mentions

/* the "@query" the caret stands at the end of in the field, with the UTF-16 range it takes there */
- (BOOL)mentionTokenInField:(exteria_mention_token *)token range:(NSRange *)range {
    UITextView *view = [self bar].textView;
    NSRange selection = view.selectedRange;
    NSString *text = view.text;
    if (selection.length || selection.location == 0 || selection.location > text.length) return NO;
    const char *bytes = text.UTF8String;
    size_t caret = [[text substringToIndex:selection.location] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (!bytes || !exteria_mention_scan(bytes, caret, token)) return NO;
    NSString *before = [[[NSString alloc] initWithBytes:bytes length:token->start encoding:NSUTF8StringEncoding] autorelease];
    if (!before || before.length >= selection.location) return NO;
    *range = NSMakeRange(before.length, selection.location - before.length);
    return YES;
}

/* the rows for a query: whoever has a public name (a mention is only that name in the text) and a name or public
   name that starts with the query, public names first */
- (NSArray *)mentionRowsMatching:(NSString *)query {
    NSString *needle = query.lowercaseString;
    NSMutableArray *named = [NSMutableArray array], *byName = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *pool = [NSMutableArray arrayWithArray:[_host botsMentionCandidates]];
    [pool addObjectsFromArray:_mentionRemote];
    for (ExteriaPerson *person in pool) {
        NSNumber *key = [NSNumber numberWithLongLong:person.userId];
        if (!person.username.length || [seen containsObject:key]) continue;
        [seen addObject:key];
        if (!needle.length) {
            [named addObject:person];
            continue;
        }
        if ([person.username.lowercaseString hasPrefix:needle]) {
            [named addObject:person];
            continue;
        }
        for (NSString *word in [person.name.lowercaseString componentsSeparatedByString:@" "]) {
            if ([word hasPrefix:needle]) {
                [byName addObject:person];
                break;
            }
        }
    }
    [named addObjectsFromArray:byName];
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaPerson *person in named) {
        if (rows.count >= MENTION_ROWS_MAX) break;
        [rows addObject:[[[ExteriaSuggestion alloc] initWithTitle:person.name subtitle:[@"@" stringByAppendingString:person.username] media:nil webFile:nil
                                                          payload:person] autorelease]];
    }
    return rows;
}

- (void)showMentionRowsMatching:(NSString *)query {
    NSArray *rows = [self mentionRowsMatching:query];
    if (!rows.count) {
        if (_mode == ExteriaPanelMention) [self hidePanel];
        return;
    }
    ++_inlineToken;
    _mode = ExteriaPanelMention;
    ExteriaSuggestionPanel *panel = [self ensurePanel];
    [panel setHeaderTitle:nil handler:nil];
    [panel setLoading:NO];
    [panel setSuggestions:rows gallery:NO];
    [_host botsRelayout];
}

/* YES while the caret ends a name typed after an @ in a group, whether or not anyone matched */
- (BOOL)updateMentions {
    if (_dialog.kind != EXTERIA_DIALOG_GROUP) return NO;
    exteria_mention_token token;
    NSRange range;
    if (![self mentionTokenInField:&token range:&range]) {
        if (_mode == ExteriaPanelMention) [self hidePanel];
        [_mentionRemote release];
        _mentionRemote = nil;
        return NO;
    }
    NSString *query = [NSString stringWithUTF8String:token.query];
    [self showMentionRowsMatching:query];
    /* a supergroup knows more people than the history shows, and the server searches them */
    if (_dialog.peerKind == 3) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchMentionMembers:) object:nil];
        [self performSelector:@selector(searchMentionMembers:) withObject:query afterDelay:MENTION_SEARCH_DELAY];
    }
    return YES;
}

- (void)searchMentionMembers:(NSString *)query {
    NSUInteger token = ++_mentionToken;
    ExteriaWeakReference *weak = _weak;
    [_session loadMembersOfDialog:_dialog list:ExteriaChannelListSubscribers query:query.length ? query : nil offset:0
                       completion:^(NSArray *members, NSInteger total, NSString *errorName) {
        (void)total;
        ExteriaChatBots *bots = weak.target;
        if (!bots || token != bots->_mentionToken) return;
        if (!members) {
            NSLog(@"exteria: the members to mention did not load: %@", errorName);
            return;
        }
        NSMutableArray *people = [NSMutableArray arrayWithCapacity:members.count];
        for (ExteriaChannelMember *member in members) if (!member.isSelf) [people addObject:member.person];
        [bots->_mentionRemote release];
        bots->_mentionRemote = [people retain];
        /* the field may have moved on while the server thought */
        exteria_mention_token current;
        NSRange range;
        if (![bots mentionTokenInField:&current range:&range]) return;
        [bots showMentionRowsMatching:[NSString stringWithUTF8String:current.query]];
    }];
}

/* the typed "@query" becomes "@name ", with a space already after it used instead of a second one */
- (void)insertMention:(ExteriaPerson *)person {
    exteria_mention_token token;
    NSRange range;
    if (!person.username.length || ![self mentionTokenInField:&token range:&range]) {
        [self hidePanel];
        return;
    }
    NSString *text = [self bar].textView.text;
    if (NSMaxRange(range) < text.length && [text characterAtIndex:NSMaxRange(range)] == ' ') ++range.length;
    [self hidePanel];
    /* at the start of a message the name addresses the one who reads it, which a comma after it says */
    BOOL comma = range.location == 0 && ExteriaChatFlagGet(ExteriaChatFlagCommaAfterMention);
    [[self bar] replaceRange:range withText:[NSString stringWithFormat:comma ? @"@%@, " : @"@%@ ", person.username]];
}

#pragma mark inline mode

/* "@name " with the query after it; the name must have the shape of a public name */
static BOOL ExteriaInlineParse(NSString *text, NSString **name, NSString **query) {
    if (![text hasPrefix:@"@"]) return NO;
    NSRange space = [text rangeOfString:@" "];
    if (space.location == NSNotFound) return NO;
    char buffer[EXTERIA_LINK_NAME_MAX];
    NSString *candidate = [text substringWithRange:NSMakeRange(1, space.location - 1)];
    if (exteria_mention_name(candidate.UTF8String, buffer, sizeof(buffer)) != EXTERIA_OK || [candidate hasPrefix:@"@"]) return NO;
    *name = candidate;
    *query = [text substringFromIndex:space.location + 1];
    return YES;
}

- (void)inputTextChanged {
    /* a name being typed after an @ in a group lists the people who can be mentioned */
    if ([self updateMentions]) return;
    NSString *text = [self bar].textView.text;
    if (_mode == ExteriaPanelInline && ![text hasPrefix:@"@"]) {
        [self hidePanel];
    }
    /* a slash at the start of the field in a chat with a bot lists its commands */
    if (_bot && [text hasPrefix:@"/"] && [text rangeOfString:@" "].location == NSNotFound && [text rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location == NSNotFound) {
        [self showCommandsMatching:[text substringFromIndex:1]];
        return;
    }
    if (_mode == ExteriaPanelCommands) [self hidePanel];
    NSString *name = nil, *query = nil;
    if (!ExteriaInlineParse(text, &name, &query)) {
        if (_mode == ExteriaPanelInline) [self hidePanel];
        return;
    }
    [self lookupInlineBot:name query:query];
}

- (void)lookupInlineBot:(NSString *)name query:(NSString *)query {
    NSString *key = name.lowercaseString;
    id known = [_inlineBots objectForKey:key];
    if ([known isKindOfClass:[NSNull class]]) {
        if (_mode == ExteriaPanelInline) [self hidePanel];
        return;
    }
    if (known) {
        [self scheduleInline:known query:query];
        return;
    }
    NSUInteger token = ++_inlineToken;
    ExteriaWeakReference *weak = _weak;
    [_session resolveUsername:name completion:^(ExteriaDialog *dialog, ExteriaPerson *person, NSString *errorName) {
        (void)errorName;
        ExteriaChatBots *bots = weak.target;
        if (!bots) return;
        if (!person.botInline) {
            [bots->_inlineBots setObject:[NSNull null] forKey:key];
            return;
        }
        ExteriaInlineBot *bot = [[[ExteriaInlineBot alloc] init] autorelease];
        bot->person = [person retain];
        bot->dialog = [dialog retain];
        [bots->_inlineBots setObject:bot forKey:key];
        /* the field may have moved on while the name was looked up */
        if (token != bots->_inlineToken) return;
        NSString *current = nil, *currentQuery = nil;
        if (ExteriaInlineParse([bots bar].textView.text, &current, &currentQuery) && [current.lowercaseString isEqualToString:key])
            [bots scheduleInline:bot query:currentQuery];
    }];
}

- (void)scheduleInline:(ExteriaInlineBot *)bot query:(NSString *)query {
    BOOL sameBot = bot == _inlineBot;
    [_inlineBot release];
    _inlineBot = [bot retain];
    if (sameBot && [query isEqualToString:_inlineQuery] && _mode == ExteriaPanelInline) return;
    [_inlineQuery release];
    _inlineQuery = [query copy];
    ++_inlineToken;
    _mode = ExteriaPanelInline;
    ExteriaSuggestionPanel *panel = [self ensurePanel];
    [panel setLoading:YES];
    [panel setEmptyText:nil];
    [panel setHeaderTitle:nil handler:nil];
    [panel setSuggestions:[NSArray array] gallery:NO];
    [_host botsRelayout];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runInline) object:nil];
    [self performSelector:@selector(runInline) withObject:nil afterDelay:INLINE_DELAY];
}

- (void)runInline {
    if (_mode != ExteriaPanelInline || !_inlineBot) return;
    NSUInteger token = _inlineToken;
    ExteriaWeakReference *weak = _weak;
    [_nextOffset release];
    _nextOffset = nil;
    _loadingMore = NO;
    [_session searchInline:_inlineQuery bot:_inlineBot->person inDialog:_dialog offset:@"" completion:^(ExteriaInlinePage *page, NSString *errorName) {
        ExteriaChatBots *bots = weak.target;
        if (!bots || token != bots->_inlineToken || bots->_mode != ExteriaPanelInline) return;
        ExteriaSuggestionPanel *panel = bots->_panel;
        [panel setLoading:NO];
        if (!page) {
            [panel setEmptyText:[ExteriaLinkRouter textForError:errorName]];
            [bots->_host botsRelayout];
            return;
        }
        bots->_inlineQueryId = page.queryId;
        bots->_nextOffset = page.nextOffset.length ? [page.nextOffset copy] : nil;
        [panel setSuggestions:[bots suggestionsOfPage:page] gallery:page.gallery];
        [panel setEmptyText:page.results.count ? nil : NSLocalizedString(@"bots.inline.empty", nil)];
        [bots configureInlineHeader:page];
        [bots->_host botsRelayout];
    }];
}

- (NSArray *)suggestionsOfPage:(ExteriaInlinePage *)page {
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:page.results.count];
    for (ExteriaInlineResult *result in page.results) {
        NSString *title = result.title.length ? result.title : nil;
        if (!title) {
            switch (result.kind) {
            case EXTERIA_INLINE_PHOTO: title = NSLocalizedString(@"bots.inline.photo", nil); break;
            case EXTERIA_INLINE_GIF: title = NSLocalizedString(@"bots.inline.gif", nil); break;
            case EXTERIA_INLINE_STICKER: title = NSLocalizedString(@"bots.inline.sticker", nil); break;
            default: title = result.subtitle.length ? result.subtitle : @"-"; break;
            }
        }
        NSString *subtitle = result.title.length ? result.subtitle : nil;
        [rows addObject:[[[ExteriaSuggestion alloc] initWithTitle:title subtitle:subtitle media:result.media webFile:result.thumb payload:result] autorelease]];
    }
    return rows;
}

/* the bot's own button above the results: connect */
- (void)configureInlineHeader:(ExteriaInlinePage *)page {
    ExteriaWeakReference *weak = _weak;
    ExteriaPerson *person = _inlineBot->person;
    ExteriaDialog *dialog = _inlineBot->dialog;
    if (page.switchText.length) {
        NSString *param = page.switchParam;
        [_panel setHeaderTitle:page.switchText handler:^{
            ExteriaChatBots *bots = weak.target;
            if (!bots) return;
            [bots hidePanel];
            [[bots bar] clear];
            [bots->_router openDialog:dialog person:person draft:nil startParam:param.length ? param : @""];
        }];
    } else {
        [_panel setHeaderTitle:nil handler:nil];
    }
}

- (void)loadMoreInline {
    if (_mode != ExteriaPanelInline || _loadingMore || !_nextOffset.length || !_inlineBot) return;
    _loadingMore = YES;
    NSUInteger token = _inlineToken;
    ExteriaWeakReference *weak = _weak;
    [_session searchInline:_inlineQuery bot:_inlineBot->person inDialog:_dialog offset:_nextOffset completion:^(ExteriaInlinePage *page, NSString *errorName) {
        ExteriaChatBots *bots = weak.target;
        if (!bots || token != bots->_inlineToken) return;
        bots->_loadingMore = NO;
        if (!page) {
            NSLog(@"exteria: next inline page not loaded: %@", errorName);
            [bots->_nextOffset release];
            bots->_nextOffset = nil;
            return;
        }
        [bots->_nextOffset release];
        bots->_nextOffset = page.nextOffset.length ? [page.nextOffset copy] : nil;
        [bots->_panel appendSuggestions:[bots suggestionsOfPage:page]];
        [bots->_host botsRelayout];
    }];
}

- (void)sendInlineResult:(ExteriaInlineResult *)result {
    long long queryId = _inlineQueryId;
    ExteriaWeakReference *weak = _weak;
    [[self bar] clear];
    [self hidePanel];
    [_session sendInlineResult:result queryId:queryId toDialog:_dialog randomId:[_host botsRandomId] completion:^(int32_t messageId, NSString *errorName) {
        (void)messageId;
        ExteriaChatBots *bots = weak.target;
        if (bots && errorName) [bots->_router showNote:[ExteriaLinkRouter textForError:errorName]];
    }];
}

#pragma mark keys of the bot's keyboard

- (ExteriaPerson *)senderBotOfMessage:(ExteriaMessage *)message {
    if (_bot) return _bot;
    ExteriaPerson *person = [_host botsPersonForUserId:message.viaBotId ? message.viaBotId : message.fromId];
    return person.bot ? person : nil;
}

- (void)pressKey:(ExteriaMarkupButton *)button {
    ExteriaWeakReference *weak = _weak;
    switch (button.kind) {
    case EXTERIA_BUTTON_TEXT:
        [_host botsSendText:button.text replyTo:_keyboard.selective ? _keyboardMessageId : 0];
        break;
    case EXTERIA_BUTTON_REQUEST_PHONE:
        ExteriaConfirm(nil, NSLocalizedString(@"bots.phone.ask", nil), NSLocalizedString(@"bots.share", nil), ^{
            ExteriaChatBots *bots = weak.target;
            if (bots) [bots sharePhone];
        });
        return;
    case EXTERIA_BUTTON_REQUEST_GEO:
        ExteriaConfirm(nil, NSLocalizedString(@"bots.location.ask", nil), NSLocalizedString(@"bots.share", nil), ^{
            ExteriaChatBots *bots = weak.target;
            if (bots) [bots->_host botsRequestLocation];
        });
        return;
    case EXTERIA_BUTTON_REQUEST_POLL:
        [_router showNote:NSLocalizedString(@"bots.poll.unsupported", nil)];
        return;
    case EXTERIA_BUTTON_REQUEST_PEER:
        [self pickPeerForButton:button];
        return;
    default:
        return;
    }
    if (_keyboard.singleUse) [self didSendText];
}

- (void)sharePhone {
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaChatBots *bots = weak.target;
        if (!bots) return;
        ExteriaPerson *me = (items.count ? [items objectAtIndex:0] : nil);
        if (!me || !me.phone.length) {
            [bots->_router showNote:[ExteriaLinkRouter textForError:errorName ? errorName : @"INTERNAL"]];
            return;
        }
        NSString *phone = [me.phone hasPrefix:@"+"] ? me.phone : [@"+" stringByAppendingString:me.phone];
        [bots->_session sendContactPhone:phone name:me.name toDialog:bots->_dialog randomId:[bots->_host botsRandomId] completion:^(int32_t messageId, NSString *sendError) {
            (void)messageId;
            ExteriaChatBots *again = weak.target;
            if (again && sendError) [again->_router showNote:[ExteriaLinkRouter textForError:sendError]];
        }];
    }];
}

- (void)pickPeerForButton:(ExteriaMarkupButton *)button {
    exteria_markup_button row = button.row;
    if (row.choice == EXTERIA_CHOICE_CREATE_BOT) {
        [_router showNote:NSLocalizedString(@"bots.peer.unsupported", nil)];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    int32_t messageId = _keyboardMessageId;
    [_router pickDialogsWithFilter:^BOOL(ExteriaDialog *dialog) {
        switch (row.choice) {
        case EXTERIA_CHOICE_USER:
            if (dialog.kind != EXTERIA_DIALOG_USER && dialog.kind != EXTERIA_DIALOG_BOT) return NO;
            if (dialog.saved) return NO;
            if (row.want_bot == EXTERIA_WANT_YES && dialog.kind != EXTERIA_DIALOG_BOT) return NO;
            if (row.want_bot == EXTERIA_WANT_NO && dialog.kind == EXTERIA_DIALOG_BOT) return NO;
            return YES;
        case EXTERIA_CHOICE_GROUP: return dialog.kind == EXTERIA_DIALOG_GROUP;
        case EXTERIA_CHOICE_CHANNEL: return dialog.kind == EXTERIA_DIALOG_CHANNEL;
        default: return NO;
        }
    } limit:row.max_quantity completion:^(NSArray *dialogs) {
        ExteriaChatBots *bots = weak.target;
        if (!bots || !dialogs.count) return;
        [bots->_session sendRequestedDialogs:dialogs buttonId:row.button_id ofMessage:messageId inDialog:bots->_dialog completion:^(NSString *errorName) {
            ExteriaChatBots *again = weak.target;
            if (again && errorName) [again->_router showNote:[ExteriaLinkRouter textForError:errorName]];
        }];
    }];
}

#pragma mark buttons under messages

- (void)setBusy:(ExteriaMarkupButton *)button cell:(ExteriaMessageCell *)cell {
    [self clearBusy];
    _busyButton = [button retain];
    _busyCell = [cell retain];
    [cell setBusyMarkupButton:button];
}

- (void)clearBusy {
    [_busyCell setBusyMarkupButton:nil];
    [_busyButton release];
    _busyButton = nil;
    [_busyCell release];
    _busyCell = nil;
}

- (void)pressButton:(ExteriaMarkupButton *)button ofMessage:(ExteriaMessage *)message cell:(ExteriaMessageCell *)cell {
    ExteriaWeakReference *weak = _weak;
    switch (button.kind) {
    case EXTERIA_BUTTON_CALLBACK:
    case EXTERIA_BUTTON_GAME:
        [self sendCallback:button ofMessage:message cell:cell password:nil];
        break;
    case EXTERIA_BUTTON_URL:
        [_router openLink:button.argument];
        break;
    case EXTERIA_BUTTON_URL_AUTH:
        [self signInWithButton:button ofMessage:message cell:cell];
        break;
    case EXTERIA_BUTTON_SWITCH_INLINE:
        [self switchInlineWithButton:button ofMessage:message];
        break;
    case EXTERIA_BUTTON_COPY:
        [UIPasteboard generalPasteboard].string = button.argument;
        [_router showNote:NSLocalizedString(@"bots.copied", nil)];
        break;
    case EXTERIA_BUTTON_BUY:
        [_router payInvoiceOfMessage:message.messageId inDialog:_dialog completion:nil];
        break;
    case EXTERIA_BUTTON_USER_PROFILE:
        [_router openProfileOfUser:button.row.user_id inMessage:message.messageId dialog:_dialog];
        break;
    default:
        (void)weak;
        break;
    }
}

- (void)sendCallback:(ExteriaMarkupButton *)button ofMessage:(ExteriaMessage *)message cell:(ExteriaMessageCell *)cell password:(NSString *)password {
    if (_busyButton) return;
    [self setBusy:button cell:cell];
    ExteriaWeakReference *weak = _weak;
    [_session pressButton:button ofMessage:message.messageId inDialog:_dialog password:password completion:^(ExteriaCallbackAnswer *answer, NSString *errorName) {
        ExteriaChatBots *bots = weak.target;
        if (!bots) return;
        [bots clearBusy];
        if ([errorName isEqualToString:@"PASSWORD_REQUIRED"] || [errorName isEqualToString:@"PASSWORD_HASH_INVALID"]) {
            if ([errorName isEqualToString:@"PASSWORD_HASH_INVALID"]) [bots->_router showNote:[ExteriaLinkRouter textForError:errorName]];
            [bots askPasswordForButton:button ofMessage:message cell:cell];
            return;
        }
        if (!answer) {
            /* a bot that does not answer a press in time is common and not worth an alert */
            [bots->_router showNote:[ExteriaLinkRouter textForError:errorName]];
            return;
        }
        [bots showAnswer:answer forButton:button];
    }];
}

- (void)askPasswordForButton:(ExteriaMarkupButton *)button ofMessage:(ExteriaMessage *)message cell:(ExteriaMessageCell *)cell {
    ExteriaWeakReference *weak = _weak;
    ExteriaShowAlert(NSLocalizedString(@"bots.password.title", nil), NSLocalizedString(@"bots.password.message", nil),
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"notice.ok", nil), nil], 0, YES,
                     ^(NSInteger index, NSString *text) {
        ExteriaChatBots *bots = weak.target;
        if (!bots || index != 1 || !text.length) return;
        [bots sendCallback:button ofMessage:message cell:cell password:text];
    });
}

- (void)showAnswer:(ExteriaCallbackAnswer *)answer forButton:(ExteriaMarkupButton *)button {
    if (answer.url.length) {
        /* a game is a page of the bot's, which the system browser shows */
        [_router openLink:answer.url];
        return;
    }
    if (!answer.message.length) return;
    if (answer.alert) ExteriaShowNotice(nil, answer.message);
    else [_router showNote:answer.message];
}

- (void)signInWithButton:(ExteriaMarkupButton *)button ofMessage:(ExteriaMessage *)message cell:(ExteriaMessageCell *)cell {
    if (_busyButton) return;
    [self setBusy:button cell:cell];
    ExteriaWeakReference *weak = _weak;
    [_session requestUrlAuthForButton:button ofMessage:message.messageId inDialog:_dialog completion:^(ExteriaUrlAuth *auth, NSString *errorName) {
        ExteriaChatBots *bots = weak.target;
        if (!bots) return;
        [bots clearBusy];
        if (!auth) {
            [bots->_router showNote:[ExteriaLinkRouter textForError:errorName]];
            return;
        }
        switch (auth.kind) {
        case EXTERIA_URL_AUTH_OPEN:
            [bots->_router openLink:button.argument];
            break;
        case EXTERIA_URL_AUTH_DONE:
            [bots->_router openLink:auth.url.length ? auth.url : button.argument];
            break;
        case EXTERIA_URL_AUTH_ASK:
            [bots confirmSignIn:auth button:button ofMessage:message];
            break;
        }
    }];
}

- (void)confirmSignIn:(ExteriaUrlAuth *)auth button:(ExteriaMarkupButton *)button ofMessage:(ExteriaMessage *)message {
    ExteriaWeakReference *weak = _weak;
    NSString *question = [NSString stringWithFormat:NSLocalizedString(@"bots.auth.ask", nil), auth.domain, auth.botName.length ? auth.botName : @"?"];
    void (^accept)(BOOL, NSString *) = ^(BOOL write, NSString *code) {
        ExteriaChatBots *bots = weak.target;
        if (!bots) return;
        [bots->_session acceptUrlAuth:auth button:button ofMessage:message.messageId inDialog:bots->_dialog writeAllowed:write code:code
                           completion:^(ExteriaUrlAuth *result, NSString *errorName) {
            ExteriaChatBots *again = weak.target;
            if (!again) return;
            if (!result) {
                [again->_router showNote:[ExteriaLinkRouter textForError:errorName]];
                return;
            }
            [again->_router openLink:result.url.length ? result.url : button.argument];
        }];
    };
    void (^accepted)(BOOL) = [^(BOOL write) {
        if (!auth.codes.count) {
            accept(write, nil);
            return;
        }
        /* the site shows one of these codes and the person says which, which proves they are looking at both */
        ExteriaChoose(NSLocalizedString(@"bots.auth.code", nil), auth.codes, -1, ^(NSInteger index) { accept(write, [auth.codes objectAtIndex:(NSUInteger)index]); });
    } copy];
    NSMutableArray *buttons = [NSMutableArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"bots.auth.login", nil), nil];
    if (auth.requestWrite) [buttons addObject:NSLocalizedString(@"bots.auth.login.write", nil)];
    ExteriaShowAlert(nil, question, buttons, 0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1) accepted(NO);
        else if (index == 2) accepted(YES);
        [accepted release];
    });
}

- (void)switchInlineWithButton:(ExteriaMarkupButton *)button ofMessage:(ExteriaMessage *)message {
    ExteriaPerson *bot = [self senderBotOfMessage:message];
    if (!bot.username.length) {
        [_router showNote:NSLocalizedString(@"bots.error.app", nil)];
        return;
    }
    NSString *draft = [NSString stringWithFormat:@"@%@ %@", bot.username, button.argument];
    if (button.row.same_peer) {
        [_host botsSetDraft:draft];
        return;
    }
    ExteriaLinkRouter *router = _router;
    [router pickDialogWithTypes:0 completion:^(ExteriaDialog *dialog) {
        if (dialog) [router openDialog:dialog person:nil draft:draft startParam:nil];
    }];
}

#pragma mark links in text

- (BOOL)openLink:(NSString *)url {
    static NSString *const commandPrefix = @"exteria-command:";
    if ([url hasPrefix:commandPrefix]) {
        NSString *command = [url substringFromIndex:commandPrefix.length];
        char name[40], bot[EXTERIA_LINK_NAME_MAX];
        if (exteria_bot_command_split(command.UTF8String, name, sizeof(name), bot, sizeof(bot)) == EXTERIA_OK) [_host botsSendText:command replyTo:0];
        return YES;
    }
    [_router openLink:url];
    return YES;
}

@end
