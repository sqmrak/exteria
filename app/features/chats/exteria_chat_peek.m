#import "exteria_chat_peek.h"
#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_avatar_view.h"
#import "exteria_developers.h"
#import "exteria_emoji_label.h"
#import "exteria_name_badge.h"
#import "exteria_ayu.h"
#import "exteria_chat_item.h"
#import "exteria_message_cell.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define PEEK_COUNT 12
#define PEEK_ACTION_HEIGHT 42.0

@interface ExteriaChatPeek : UIView <UITableViewDataSource, UITableViewDelegate> {
    ExteriaDialog *_dialog;
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    UIView *_dim;
    UIView *_card;
    UIView *_header;
    ExteriaAvatarView *_avatar;
    ExteriaEmojiLabel *_title;
    UILabel *_status;
    UITableView *_table;
    UIView *_menu;
    NSArray *_items;
    NSArray *_buttons;
    BOOL _networkFinished;
    CGFloat _layoutWidth;
    BOOL _closing;
    void (^_handler)(ExteriaChatPeekAction);
}
- (id)initWithDialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
           canSelect:(BOOL)canSelect handler:(void (^)(ExteriaChatPeekAction))handler;
- (void)showInView:(UIView *)host source:(CGRect)source;
@end

@implementation ExteriaChatPeek
- (id)initWithDialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
           canSelect:(BOOL)canSelect handler:(void (^)(ExteriaChatPeekAction))handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _dialog = [dialog retain]; _session = [session retain]; _avatars = [avatars retain]; _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _handler = [handler copy];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorScreen();
    _card.layer.cornerRadius = 18;
    _card.layer.masksToBounds = YES;
    [_card addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)] autorelease]];
    [self addSubview:_card];
    _header = [[UIView alloc] init];
    _header.backgroundColor = ExteriaColorCard();
    [_card addSubview:_header];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES; _avatar.initials = dialog.initials; _avatar.seed = dialog.avatarSeed;
    [_avatar setPhoto:dialog.photo cache:avatars];
    [_header addSubview:_avatar];
    /* the name is drawn as in the chat header: emoji as pictures, the marks and the status after it */
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.backgroundColor = [UIColor clearColor]; _title.textColor = ExteriaColorTitle();
    _title.font = ExteriaFontSemibold(16); _title.dropsUndrawable = YES;
    NSArray *titleBadges = nil;
    _title.text = ExteriaNameWithBadges(dialog.title, ExteriaDialogBadgeDocument(dialog), ExteriaDialogIsDeveloper(dialog), &titleBadges);
    _title.entities = titleBadges;
    [_header addSubview:_title];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor]; _status.textColor = ExteriaColorSecondary();
    _status.textAlignment = ExteriaTextAlignmentCenter; _status.numberOfLines = 0; _status.font = ExteriaFontRegular(14);
    _status.text = NSLocalizedString(@"peek.loading", nil);
    [_card addSubview:_status];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    ExteriaScrollViewOwnsInsets(_table);
    ExteriaTableUsesExactHeights(_table);
    _table.backgroundColor = [UIColor clearColor]; _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self; _table.delegate = self; _table.userInteractionEnabled = NO;
    [_card addSubview:_table];
    _menu = [[UIView alloc] init];
    _menu.backgroundColor = ExteriaColorCard(); _menu.layer.cornerRadius = 14; _menu.clipsToBounds = YES;
    [self addSubview:_menu];
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(dialog.pinned ? @"chats.unpin" : @"chats.pin", nil),
        NSLocalizedString(dialog.muted ? @"chats.unmute" : @"chats.mute", nil),
        NSLocalizedString(dialog.folderId ? @"chats.unarchive.action" : @"chats.archive.action", nil), NSLocalizedString(@"peek.select", nil), nil];
    ExteriaSymbol symbols[] = {ExteriaSymbolPin, dialog.muted ? ExteriaSymbolBell : ExteriaSymbolBellMuted, ExteriaSymbolArchive, ExteriaSymbolCheck};
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < (canSelect ? 4u : 3u); ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = (NSInteger)i + 1;
        button.accessibilityLabel = [titles objectAtIndex:i];
        [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(symbols[i], 20, ExteriaColorAccent())] autorelease];
        icon.frame = CGRectMake(14, 11, 20, 20); icon.userInteractionEnabled = NO;
        [button addSubview:icon];
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(46, 0, 150, PEEK_ACTION_HEIGHT)] autorelease];
        label.backgroundColor = [UIColor clearColor]; label.textColor = ExteriaColorTitle(); label.font = ExteriaFontMedium(15);
        label.text = [titles objectAtIndex:i]; label.autoresizingMask = UIViewAutoresizingFlexibleWidth; label.userInteractionEnabled = NO;
        [button addSubview:label];
        [_menu addSubview:button]; [buttons addObject:button];
    }
    _buttons = [buttons copy];
    return self;
}
- (void)dealloc {
    [_weak clear]; [_weak release]; _table.delegate = nil; _table.dataSource = nil;
    [_dialog release]; [_session release]; [_avatars release]; [_media release]; [_handler release];
    [_dim release]; [_card release]; [_header release]; [_avatar release]; [_title release]; [_status release]; [_table release]; [_menu release];
    [_items release]; [_buttons release]; [super dealloc];
}
- (void)showInView:(UIView *)host source:(CGRect)source {
    self.frame = host.bounds;
    [host addSubview:self]; [self layoutIfNeeded];
    CGFloat scale = 0.35;
    CGPoint center = _card.center;
    CGAffineTransform start = CGAffineTransformMake(scale, 0, 0, scale, CGRectGetMidX(source) - center.x, CGRectGetMidY(source) - center.y);
    if (ExteriaReduceMotionEnabled()) start = CGAffineTransformIdentity;
    _card.transform = start; _card.alpha = 0;
    _menu.transform = CGAffineTransformMakeTranslation(0, 12); _menu.alpha = 0;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 animations:^{ _dim.alpha = 1; }];
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
    ExteriaAnimateViewAfter(_menu, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, 0.06, nil);
    ExteriaWeakReference *weak = _weak;
    if (_dialog.emojiStatus) {
        ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:_dialog.emojiStatus]], _session, _media, ^{
            ExteriaChatPeek *peek = weak.target;
            if (peek) [peek->_title setNeedsDisplay];
        });
    }
    [_session loadCachedHistoryOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *error) {
        (void)error;
        ExteriaChatPeek *peek = weak.target;
        if (peek && !peek->_networkFinished && messages.count) [peek showMessages:messages people:people];
    }];
    [_session loadHistoryOfDialog:_dialog beforeId:0 limit:PEEK_COUNT completion:^(NSArray *messages, NSDictionary *people, NSString *error) {
        ExteriaChatPeek *peek = weak.target;
        if (!peek) return;
        peek->_networkFinished = messages != nil;
        if (messages) [peek showMessages:messages people:people];
        else {
            NSLog(@"exteria: chat preview failed: %@", error);
            if (!peek->_items.count) peek->_status.text = NSLocalizedString(@"peek.error", nil);
        }
    }];
}
- (void)showMessages:(NSArray *)messages people:(NSDictionary *)people {
    NSArray *ordered = [messages sortedArrayUsingComparator:^NSComparisonResult(ExteriaMessage *a, ExteriaMessage *b) {
        return a.messageId < b.messageId ? NSOrderedAscending : (a.messageId > b.messageId ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray *items = [NSMutableArray array];
    NSUInteger start = ordered.count > PEEK_COUNT ? ordered.count - PEEK_COUNT : 0;
    for (NSUInteger i = start; i < ordered.count; ++i) {
        ExteriaMessage *message = [ordered objectAtIndex:i];
        if (!message.outgoing && ExteriaAyuHidesText(message.text)) continue;
        ExteriaChatItem *item = [ExteriaChatItem itemForMessage:message group:_dialog.kind == EXTERIA_DIALOG_GROUP people:people];
        if (item) [items addObject:item];
    }
    [_items release]; _items = [items copy];
    _status.text = _items.count ? @"" : NSLocalizedString(@"peek.empty", nil);
    [_table reloadData]; [_table layoutIfNeeded];
    CGFloat end = MAX(0, _table.contentSize.height - _table.bounds.size.height);
    [_table setContentOffset:CGPointMake(0, end) animated:NO];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _dim.frame = self.bounds;
    UIEdgeInsets insets = ExteriaSafeInsets(self);
    CGFloat width = MAX(100, MIN(350, self.bounds.size.width - insets.left - insets.right - 32));
    CGFloat available = MAX(100, self.bounds.size.height - insets.top - insets.bottom - 32);
    CGFloat menuHeight = _buttons.count * PEEK_ACTION_HEIGHT;
    CGFloat cardHeight = MAX(100, MIN(440, available - menuHeight - 12));
    CGFloat top = insets.top + MAX(0, floor((available - cardHeight - menuHeight - 12) / 2)) + 16;
    _card.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), top, width, cardHeight);
    _header.frame = CGRectMake(0, 0, width, 56); _avatar.frame = CGRectMake(12, 9, 38, 38);
    _title.frame = CGRectMake(60, 0, width - 72, 56);
    _table.frame = CGRectMake(0, 56, width, MAX(0, cardHeight - 56));
    if (_items.count && _layoutWidth != width) {
        _layoutWidth = width;
        [_table reloadData];
        [_table layoutIfNeeded];
        [_table setContentOffset:CGPointMake(0, MAX(0, _table.contentSize.height - _table.bounds.size.height)) animated:NO];
    }
    _status.frame = CGRectMake(16, 56, width - 32, MAX(0, cardHeight - 56));
    _menu.frame = CGRectMake(CGRectGetMaxX(_card.frame) - MIN(width, 230), CGRectGetMaxY(_card.frame) + 12, MIN(width, 230), menuHeight);
    for (NSUInteger i = 0; i < _buttons.count; ++i) ((UIView *)[_buttons objectAtIndex:i]).frame = CGRectMake(0, i * PEEK_ACTION_HEIGHT, _menu.bounds.size.width, PEEK_ACTION_HEIGHT);
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return (NSInteger)_items.count; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    ExteriaChatItem *item = [_items objectAtIndex:(NSUInteger)path.row]; [item layoutForWidth:table.bounds.size.width]; return item.height;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    ExteriaMessageCell *cell = (ExteriaMessageCell *)[table dequeueReusableCellWithIdentifier:@"peek"];
    if (!cell) cell = [[[ExteriaMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"peek"] autorelease];
    ExteriaChatItem *item = [_items objectAtIndex:(NSUInteger)path.row]; [item layoutForWidth:table.bounds.size.width];
    cell.activationDeferred = YES; [cell configureWithItem:item media:_media avatars:_avatars];
    return cell;
}
- (void)leaveWithAction:(NSInteger)action {
    if (_closing) return;
    _closing = YES; self.userInteractionEnabled = NO;
    void (^handler)(ExteriaChatPeekAction) = [_handler copy];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 animations:^{ _dim.alpha = 0; }];
    ExteriaAnimateView(_menu, CGAffineTransformMakeTranslation(0, 10), 0, EXTERIA_MOTION_DISMISS, nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeScale(0.94, 0.94), 0, EXTERIA_MOTION_DISMISS, ^(BOOL finished) {
        (void)finished; [self removeFromSuperview]; if (handler && action >= 0) handler((ExteriaChatPeekAction)action); [handler release];
    });
}
- (void)open { [self leaveWithAction:ExteriaChatPeekOpen]; }
- (void)dismiss { [self leaveWithAction:-1]; }
- (void)picked:(UIButton *)button { [self leaveWithAction:button.tag]; }
@end

void ExteriaShowChatPeek(UIView *host, CGRect source, ExteriaDialog *dialog, ExteriaSession *session,
                         ExteriaAvatarCache *avatars, ExteriaMediaCache *media, BOOL canSelect,
                         void (^handler)(ExteriaChatPeekAction)) {
    if (!host || !dialog || !session) return;
    for (UIView *view in host.subviews) if ([view isKindOfClass:[ExteriaChatPeek class]]) return;
    ExteriaChatPeek *peek = [[[ExteriaChatPeek alloc] initWithDialog:dialog session:session avatars:avatars media:media canSelect:canSelect handler:handler] autorelease];
    [peek showInView:host source:source];
}
