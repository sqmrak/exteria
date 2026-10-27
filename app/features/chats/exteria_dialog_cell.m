#import "exteria_emoji_label.h"
#import "exteria_dialog_cell.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_community_badge.h"
#import "exteria_lottie_view.h"
#import "exteria_pill_label.h"
#import "exteria_platform.h"
#import "exteria_chat_settings.h"
#import "exteria_draft.h"
#import "exteria_preview_thumb.h"
#import "exteria_status_label.h"
#import "exteria_story_ring.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_topic_icon.h"
#import "exteria_developers.h"
#import "exteria_name_badge.h"

#define MINI_SIDE 16.0
#define ROW_HEIGHT 64.0
#define AVATAR_SIZE 48.0
#define RING_OUTSET 4.0
#define ONLINE_SIDE 14.0
#define ONLINE_BORDER 2.0
#define SIDE_MARGIN 14.0
#define BADGE_HEIGHT 18.0
#define ICON_SIZE 14.0
#define FORWARD_SIDE 14.0
#define ACTION_WIDTH 80.0
#define ACTION_ICON_SIZE 32.0
/* a drag this far across the row, or a fast flick past half the button, performs the action without a tap */
#define COMMIT_FRACTION 0.6
#define COMMIT_FLICK 900.0
#define SETTLE_SECONDS 0.22

@interface ExteriaDialogCell () <UIGestureRecognizerDelegate> {
    UIView *_slider;
    UIButton *_actionButton;
    UIView *_actionContent;
    UILabel *_actionLabel;
    ExteriaLottieView *_actionIcon;
    UIPanGestureRecognizer *_pan;
    NSArray *_folderPaging;
    ExteriaDialogAction _action;
    ExteriaMediaCache *_media;
    CGFloat _offset;
    CGFloat _dragStart;
    BOOL _played;
    /* a settle or commit still running must not act on a row that was reused meanwhile */
    NSUInteger _generation;
    ExteriaAvatarView *_avatar;
    ExteriaStoryRing *_storyRing;
    /* the green dot on the corner of the avatar of a user who is on line */
    UIView *_onlineDot;
    /* the small picture of who wrote the last message of a group, when the setting asks for it */
    ExteriaAvatarView *_mini;
    UIImageView *_topicIcon;
    UIImageView *_communityBadge;
    UIButton *_communityHit;
    void (^_communityHandler)(void);
    ExteriaEmojiLabel *_title;
    UIImageView *_mutedIcon;
    UILabel *_time;
    UIImageView *_checks;
    ExteriaEmojiLabel *_preview;
    /* the words of what someone is typing, with the three dots before them; it lies over the preview while a chat is acted in */
    ExteriaStatusLabel *_typing;
    ExteriaPreviewThumb *_thumb;
    /* the arrow before the preview of a forwarded message */
    UIImageView *_forwardIcon;
    UILabel *_badge;
    UILabel *_mention;
    UIImageView *_pin;
    UIView *_line;
}
@end

@implementation ExteriaDialogCell

@synthesize swipeDelegate = _swipeDelegate;
@synthesize media = _media;

+ (CGFloat)rowHeight {
    return ROW_HEIGHT;
}

static ExteriaEmojiLabel *ExteriaCellEmojiLabel(UIFont *font, UIColor *color, NSInteger alignment) {
    ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

static UILabel *ExteriaCellPill(UIFont *font, UIColor *color, NSInteger alignment) {
    UILabel *label = [[[ExteriaPillLabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

static UILabel *ExteriaCellLabel(UIFont *font, UIColor *color, NSInteger alignment) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

@synthesize communityHandler = _communityHandler;

- (void)communityTapped {
    if (_communityHandler) _communityHandler();
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = ExteriaColorField();
    self.selectedBackgroundView = selected;

    /* the row slides inside the content view, which the cell resets to its own frame on every layout */
    _actionButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _actionButton.backgroundColor = [UIColor colorWithRed:0.682 green:0.702 blue:0.725 alpha:1];
    _actionButton.clipsToBounds = YES;
    _actionButton.hidden = YES;
    [_actionButton addTarget:self action:@selector(commitSwipe) forControlEvents:UIControlEventTouchUpInside];
    _actionContent = [[UIView alloc] init];
    _actionContent.userInteractionEnabled = NO;
    [_actionButton addSubview:_actionContent];
    _actionLabel = [ExteriaCellLabel(ExteriaFontMedium(12), [UIColor whiteColor], ExteriaTextAlignmentCenter) retain];
    [_actionContent addSubview:_actionLabel];
    [self.contentView addSubview:_actionButton];
    _slider = [[UIView alloc] init];
    _slider.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:_slider];
    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    _pan.delegate = self;
    [self addGestureRecognizer:_pan];

    _avatar = [[ExteriaAvatarView alloc] init];
    [_slider addSubview:_avatar];
    _storyRing = [[ExteriaStoryRing alloc] init];
    _storyRing.hidden = YES;
    [_slider addSubview:_storyRing];
    _onlineDot = [[ExteriaOnlineDotView alloc] init];
    _onlineDot.hidden = YES;
    _onlineDot.userInteractionEnabled = NO;
    _onlineDot.layer.cornerRadius = ONLINE_SIDE / 2;
    _onlineDot.layer.borderWidth = ONLINE_BORDER;
    [_slider addSubview:_onlineDot];
    _mini = [[ExteriaAvatarView alloc] init];
    _mini.circular = YES;
    _mini.hidden = YES;
    [_slider addSubview:_mini];
    _topicIcon = [[UIImageView alloc] init];
    _topicIcon.contentMode = UIViewContentModeScaleAspectFit;
    _topicIcon.hidden = YES;
    [_slider addSubview:_topicIcon];
    _communityBadge = [[UIImageView alloc] initWithImage:ExteriaCommunityBadgeImage()];
    _communityBadge.hidden = YES;
    [_slider addSubview:_communityBadge];
    _communityHit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _communityHit.hidden = YES;
    [_communityHit addTarget:self action:@selector(communityTapped) forControlEvents:UIControlEventTouchUpInside];
    [_slider addSubview:_communityHit];
    _title = [ExteriaCellEmojiLabel(ExteriaFontSemibold(15.5), ExteriaColorTitle(), ExteriaTextAlignmentLeft) retain];
    _title.dropsUndrawable = YES;
    [_slider addSubview:_title];
    _mutedIcon = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolBellSlash, 13, ExteriaColorMuted())];
    [_slider addSubview:_mutedIcon];
    _time = [ExteriaCellLabel(ExteriaFontRegular(12.5), ExteriaColorSecondary(), ExteriaTextAlignmentRight) retain];
    [_slider addSubview:_time];
    _checks = [[UIImageView alloc] init];
    [_slider addSubview:_checks];
    _preview = [ExteriaCellEmojiLabel(ExteriaFontRegular(14), ExteriaColorSecondary(), ExteriaTextAlignmentLeft) retain];
    _preview.numberOfLines = 2;
    [_slider addSubview:_preview];
    _typing = [[ExteriaStatusLabel alloc] init];
    _typing.backgroundColor = [UIColor clearColor];
    _typing.font = ExteriaFontRegular(14);
    _typing.activeColor = ExteriaColorAccent();
    _typing.hidden = YES;
    [_slider addSubview:_typing];
    _thumb = [[ExteriaPreviewThumb alloc] init];
    [_slider addSubview:_thumb];
    _forwardIcon = [[UIImageView alloc] init];
    _forwardIcon.hidden = YES;
    [_slider addSubview:_forwardIcon];
    _badge = [ExteriaCellPill(ExteriaFontSemibold(11.5), [UIColor whiteColor], ExteriaTextAlignmentCenter) retain];
    _badge.layer.cornerRadius = BADGE_HEIGHT / 2;
    /* a label's own background is not cut by the corner radius on its own, which left the count in a square */
    _badge.layer.masksToBounds = YES;
    [_slider addSubview:_badge];
    _mention = [ExteriaCellPill(ExteriaFontSemibold(11.5), [UIColor whiteColor], ExteriaTextAlignmentCenter) retain];
    _mention.layer.cornerRadius = BADGE_HEIGHT / 2;
    _mention.layer.masksToBounds = YES;
    _mention.backgroundColor = ExteriaColorAccent();
    /* the at sign is a picture set on the middle of the disc: the glyph of a font sits low and to the left in a label, whatever the alignment says */
    UIImageView *atMark = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolAt, 12, [UIColor whiteColor])] autorelease];
    atMark.center = CGPointMake(BADGE_HEIGHT / 2, BADGE_HEIGHT / 2);
    atMark.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [_mention addSubview:atMark];
    [_slider addSubview:_mention];
    _pin = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPin, 14, ExteriaColorMuted())];
    [_slider addSubview:_pin];
    _line = [[UIView alloc] init];
    _line.backgroundColor = ExteriaColorHairline();
    [_slider addSubview:_line];
    return self;
}

- (void)dealloc {
    [_folderPaging release];
    _pan.delegate = nil;
    [_pan release];
    [_actionIcon release];
    [_actionLabel release];
    [_actionContent release];
    [_actionButton release];
    [_slider release];
    [_avatar release];
    [_storyRing release];
    [_onlineDot release];
    [_mini release];
    [_topicIcon release];
    [_communityBadge release];
    [_communityHit release];
    [_communityHandler release];
    [_title release];
    [_mutedIcon release];
    [_time release];
    [_checks release];
    [_preview release];
    [_typing release];
    [_thumb release];
    [_forwardIcon release];
    [_badge release];
    [_mention release];
    [_pin release];
    [_line release];
    [super dealloc];
}

- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars action:(ExteriaDialogAction)action {
    ++_generation;
    _offset = 0;
    [self setSwipeAction:action];
    _avatar.seed = dialog.avatarSeed;
    _avatar.initials = dialog.initials;
    _avatar.deleted = dialog.deleted;
    _avatar.accent = dialog.saved || dialog.folder;
    _avatar.symbol = dialog.folder ? ExteriaSymbolArchive : ExteriaSymbolBookmark;
    _avatar.showsSymbol = dialog.saved || dialog.folder;
    [_avatar setPhoto:dialog.saved || dialog.folder ? nil : dialog.photo cache:avatars];
    /* a topic has the icon of its own in the place of the group's photo */
    BOOL topic = dialog.topicId > 0;
    _avatar.hidden = topic;
    _topicIcon.hidden = !topic;
    _topicIcon.image = topic ? ExteriaTopicIconImage(dialog) : nil;
    /* only a private chat with a live account has a presence; the saved messages row would show the own one */
    _onlineDot.hidden = topic || dialog.kind != EXTERIA_DIALOG_USER || dialog.saved || dialog.presence != EXTERIA_PRESENCE_ONLINE;
    _onlineDot.layer.borderColor = ExteriaColorScreen().CGColor;
    _storyRing.hidden = YES;
    /* a chat that was added to a community wears the arrow of its avatar too, and the arrow opens the community */
    _communityBadge.hidden = !(dialog.community || dialog.linkedCommunityId);
    _communityHit.hidden = !dialog.linkedCommunityId;
    [_communityHandler release];
    _communityHandler = nil;
    NSArray *badge = nil;
    _title.text = ExteriaNameWithBadges(dialog.title, dialog.saved ? 0 : ExteriaBadgeDocument(dialog.emojiStatus, dialog.premium), ExteriaDialogIsDeveloper(dialog), &badge);
    _title.entities = badge;
    _mutedIcon.hidden = !dialog.muted;
    _time.text = ExteriaListTimeText(dialog.date);
    _preview.text = dialog.preview;
    _preview.textColor = ExteriaColorSecondary();
    [_preview setPrefixLength:0 color:nil];
    _preview.hidden = NO;
    BOOL mini = dialog.showsSender && ExteriaChatFlagGet(ExteriaChatFlagSenderAvatars);
    _mini.hidden = !mini;
    if (mini) {
        _mini.seed = (NSUInteger)(dialog.senderId % 1000003);
        _mini.initials = dialog.senderInitials;
        [_mini setPhoto:dialog.senderPhoto cache:avatars];
    } else {
        [_mini setPhoto:nil cache:nil];
    }
    [_typing setStatus:@"" kind:ExteriaStatusPlain];
    _typing.hidden = YES;
    [_thumb showFile:dialog.previewFile cache:_media];
    _forwardIcon.hidden = !dialog.forwarded;
    if (dialog.forwarded) _forwardIcon.image = ExteriaSymbolImage(ExteriaSymbolForward, FORWARD_SIDE, ExteriaColorSecondary());
    if (dialog.outgoing && dialog.date > 0) {
        _checks.image = ExteriaCheckImage(dialog.read, ICON_SIZE, ExteriaColorAccent());
        _checks.hidden = NO;
    } else {
        _checks.hidden = YES;
    }
    BOOL showsBadge = dialog.unreadCount > 0 || (dialog.unread && dialog.unreadCount == 0);
    _badge.hidden = !showsBadge;
    _badge.text = dialog.unreadCount > 999 ? @"999+" : (dialog.unreadCount > 0 ? [NSString stringWithFormat:@"%ld", (long)dialog.unreadCount] : @"");
    _badge.backgroundColor = ExteriaColorAccent();
    _mention.hidden = dialog.mentions <= 0;
    _pin.hidden = !dialog.pinned || showsBadge || !_mention.hidden;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", dialog.title, dialog.preview];
    [self setNeedsLayout];
}

- (void)setStoryPeer:(ExteriaStoryPeer *)peer {
    _storyRing.hidden = !peer || _avatar.hidden;
    if (peer) [_storyRing setPeer:peer];
    [self setNeedsLayout];
}

- (void)showDraft:(ExteriaDraft *)draft {
    if (!draft) return;
    NSString *label = NSLocalizedString(@"chats.draft", nil);
    _preview.text = [NSString stringWithFormat:@"%@ %@", label, ExteriaDraftPreviewText(draft)];
    [_preview setPrefixLength:label.length color:ExteriaColorBadgeRed()];
    _time.text = ExteriaListTimeText(draft.date);
    _checks.hidden = YES;
    _mini.hidden = YES;
    _forwardIcon.hidden = YES;
    [_thumb showFile:nil cache:_media];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", _title.text, _preview.text];
    [self setNeedsLayout];
}

- (void)showTypingText:(NSString *)text {
    if (!text) return;
    _typing.activeColor = ExteriaColorAccent();
    [_typing setStatus:text kind:ExteriaStatusTyping];
    _typing.hidden = NO;
    _preview.hidden = YES;
    _mini.hidden = YES;
    _forwardIcon.hidden = YES;
    [_thumb showFile:nil cache:_media];
    [self setNeedsLayout];
}

#pragma mark swipe

static NSString *ExteriaActionAnimation(ExteriaDialogAction action) {
    switch (action) {
    case ExteriaDialogActionArchive: return @"swipe_archive";
    case ExteriaDialogActionUnarchive: return @"swipe_unarchive";
    case ExteriaDialogActionHide: return @"swipe_hide";
    case ExteriaDialogActionPin: return @"swipe_unhide";
    case ExteriaDialogActionPinChat: return @"swipe_pin";
    case ExteriaDialogActionUnpinChat: return @"swipe_unpin";
    case ExteriaDialogActionMarkRead: return @"swipe_read";
    case ExteriaDialogActionMarkUnread: return @"swipe_unread";
    case ExteriaDialogActionMute: return @"swipe_mute";
    case ExteriaDialogActionUnmute: return @"swipe_unmute";
    case ExteriaDialogActionDeleteChat: return @"swipe_delete";
    case ExteriaDialogActionNone: break;
    }
    return nil;
}

ExteriaDialogAction ExteriaDialogSwipeAction(ExteriaDialog *dialog, NSInteger folderId) {
    if (folderId > 0) return ExteriaChatFlagGet(ExteriaChatFlagNoUnarchiveSwipe) ? ExteriaDialogActionNone : ExteriaDialogActionUnarchive;
    switch (ExteriaChatSwipeStored()) {
    case ExteriaChatSwipePin: return dialog.pinned ? ExteriaDialogActionUnpinChat : ExteriaDialogActionPinChat;
    case ExteriaChatSwipeRead: return dialog.unread ? ExteriaDialogActionMarkRead : ExteriaDialogActionMarkUnread;
    case ExteriaChatSwipeMute: return dialog.muted ? ExteriaDialogActionUnmute : ExteriaDialogActionMute;
    case ExteriaChatSwipeDelete: return ExteriaDialogActionDeleteChat;
    case ExteriaChatSwipeArchive: break;
    }
    return dialog.saved ? ExteriaDialogActionNone : ExteriaDialogActionArchive;
}

NSString *ExteriaDialogActionText(ExteriaDialogAction action) {
    switch (action) {
    case ExteriaDialogActionArchive: return NSLocalizedString(@"chats.archive.action", nil);
    case ExteriaDialogActionUnarchive: return NSLocalizedString(@"chats.unarchive.action", nil);
    case ExteriaDialogActionHide: return NSLocalizedString(@"chats.hide.action", nil);
    case ExteriaDialogActionPin: return NSLocalizedString(@"chats.pin.action", nil);
    case ExteriaDialogActionPinChat: return NSLocalizedString(@"chats.swipe.pin", nil);
    case ExteriaDialogActionUnpinChat: return NSLocalizedString(@"chats.swipe.unpin", nil);
    case ExteriaDialogActionMarkRead: return NSLocalizedString(@"chats.swipe.read", nil);
    case ExteriaDialogActionMarkUnread: return NSLocalizedString(@"chats.swipe.unread", nil);
    case ExteriaDialogActionMute: return NSLocalizedString(@"chats.swipe.mute", nil);
    case ExteriaDialogActionUnmute: return NSLocalizedString(@"chats.swipe.unmute", nil);
    case ExteriaDialogActionDeleteChat: return NSLocalizedString(@"chats.swipe.delete", nil);
    case ExteriaDialogActionNone: break;
    }
    return @"";
}

- (void)setSwipeAction:(ExteriaDialogAction)action {
    _action = action;
    _pan.enabled = action != ExteriaDialogActionNone;
    _actionLabel.text = ExteriaDialogActionText(action);
    /* deleting is the one swipe that is red; the others share the grey of the archive */
    _actionButton.backgroundColor = action == ExteriaDialogActionDeleteChat ? [UIColor colorWithRed:0.89 green:0.31 blue:0.31 alpha:1]
                                                                            : [UIColor colorWithRed:0.682 green:0.702 blue:0.725 alpha:1];
    [self releaseActionIcon];
    [self layoutSwipe];
}

/* the lottie document is parsed when a swipe starts, so a screenful of idle rows holds none */
- (void)prepareActionIcon {
    if (_actionIcon || _action == ExteriaDialogActionNone) return;
    _actionIcon = [[ExteriaLottieView alloc] initWithAnimationNamed:ExteriaActionAnimation(_action)];
    [_actionContent addSubview:_actionIcon];
    _played = NO;
    [self layoutSwipe];
    [_actionIcon rewind];
}

- (void)releaseActionIcon {
    [_actionIcon removeFromSuperview];
    [_actionIcon release];
    _actionIcon = nil;
    _played = NO;
}

- (void)layoutSwipe {
    CGFloat width = self.contentView.bounds.size.width;
    _slider.frame = CGRectMake(-_offset, 0, width, ROW_HEIGHT);
    _actionButton.hidden = _offset <= 0;
    _actionButton.frame = CGRectMake(width - _offset, 0, _offset, ROW_HEIGHT);
    /* the icon keeps to the moving edge until the button is wide enough to center it */
    CGFloat slot = MAX(_offset, ACTION_WIDTH);
    _actionContent.frame = CGRectMake(0, 0, slot, ROW_HEIGHT);
    _actionIcon.frame = CGRectMake((slot - ACTION_ICON_SIZE) / 2, 9, ACTION_ICON_SIZE, ACTION_ICON_SIZE);
    _actionLabel.frame = CGRectMake(0, 43, slot, 15);
}

- (BOOL)swipeOpen {
    return _offset > 0;
}

- (void)moveSwipeTo:(CGFloat)offset animated:(BOOL)animated completion:(void (^)(void))completion {
    void (^change)(void) = ^{
        _offset = offset;
        [self layoutSwipe];
    };
    if (!animated) {
        change();
        if (completion) completion();
        return;
    }
    NSUInteger generation = _generation;
    [UIView animateWithDuration:SETTLE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:change
                     completion:^(BOOL finished) {
        (void)finished;
        if (generation == _generation && completion) completion();
    }];
}

- (void)closeSwipeAnimated:(BOOL)animated {
    if (_offset <= 0) return;
    [self moveSwipeTo:0 animated:animated completion:^{ [self releaseActionIcon]; }];
}

- (void)commitSwipe {
    if (_action == ExteriaDialogActionNone) return;
    ExteriaDialogAction action = _action;
    NSUInteger generation = _generation;
    [self prepareActionIcon];
    if (!_played) {
        _played = YES;
        [_actionIcon playOnce];
    }
    [self moveSwipeTo:self.contentView.bounds.size.width animated:YES completion:^{
        if (generation == _generation) [_swipeDelegate dialogCell:self didTriggerAction:action];
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != _pan) return YES;
    CGPoint velocity = [_pan velocityInView:self];
    if (fabs(velocity.x) <= fabs(velocity.y)) return NO;
    return velocity.x < 0 || _offset > 0;
}

- (void)yieldSwipeToRecognizers:(NSArray *)recognizers {
    if (recognizers == _folderPaging) return;
    [_folderPaging release];
    _folderPaging = [recognizers copy];
    for (UIGestureRecognizer *recognizer in _folderPaging) [_pan requireGestureRecognizerToFail:recognizer];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGFloat width = self.contentView.bounds.size.width;
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
        _dragStart = _offset;
        [_swipeDelegate dialogCellDidBeginSwipe:self];
        [self prepareActionIcon];
        break;
    case UIGestureRecognizerStateChanged: {
        _offset = MIN(width, MAX(0, _dragStart - [pan translationInView:self].x));
        [self layoutSwipe];
        if (!_played && _offset >= ACTION_WIDTH * 0.9) {
            _played = YES;
            [_actionIcon playOnce];
        }
        break;
    }
    case UIGestureRecognizerStateEnded: {
        CGFloat velocity = [pan velocityInView:self].x;
        if (_offset >= width * COMMIT_FRACTION || (velocity < -COMMIT_FLICK && _offset >= ACTION_WIDTH / 2)) {
            [self commitSwipe];
        } else if (_offset >= ACTION_WIDTH / 2 && velocity < COMMIT_FLICK) {
            [self moveSwipeTo:ACTION_WIDTH animated:YES completion:NULL];
        } else {
            [self closeSwipeAnimated:YES];
        }
        break;
    }
    default:
        [self closeSwipeAnimated:YES];
        break;
    }
}

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat textX = SIDE_MARGIN * 2 + 2 + AVATAR_SIZE - 2;
    CGFloat hairline = 1.0 / ExteriaScreenScale();
    _avatar.frame = CGRectMake(SIDE_MARGIN, (ROW_HEIGHT - AVATAR_SIZE) / 2, AVATAR_SIZE, AVATAR_SIZE);
    _topicIcon.frame = _avatar.frame;
    _storyRing.frame = CGRectInset(_avatar.frame, -RING_OUTSET, -RING_OUTSET);
    _onlineDot.frame = CGRectMake(CGRectGetMaxX(_avatar.frame) - ONLINE_SIDE + 1, CGRectGetMaxY(_avatar.frame) - ONLINE_SIDE + 1, ONLINE_SIDE, ONLINE_SIDE);
    _communityBadge.frame = CGRectMake(CGRectGetMaxX(_avatar.frame) - EXTERIA_COMMUNITY_BADGE_SIDE + 2, CGRectGetMaxY(_avatar.frame) - EXTERIA_COMMUNITY_BADGE_SIDE + 2,
                                       EXTERIA_COMMUNITY_BADGE_SIDE, EXTERIA_COMMUNITY_BADGE_SIDE);
    _communityHit.frame = CGRectInset(_communityBadge.frame, -10, -10);

    CGSize badgeSize = CGSizeZero;
    CGFloat trailing = 0;
    if (!_badge.hidden) {
        CGSize fit = [_badge sizeThatFits:CGSizeMake(80, BADGE_HEIGHT)];
        badgeSize.width = _badge.text.length ? MAX(BADGE_HEIGHT, fit.width + 12) : 10;
        badgeSize.height = _badge.text.length ? BADGE_HEIGHT : 10;
        trailing = badgeSize.width + 8;
    } else if (!_pin.hidden) {
        trailing = _pin.image.size.width + 8;
    }
    /* a chat that mentions the person marks it with an @ next to the count */
    if (!_mention.hidden) trailing += BADGE_HEIGHT + (trailing ? 4 : 8);
    /* a preview that wraps pulls the nick up and leaves a wider gap under it; a one line preview sits close under the nick */
    CGFloat thumbRoom = _thumb.hidden ? 0 : [ExteriaPreviewThumb room];
    /* the small picture of the sender stands first in the line, and what follows it moves over */
    CGFloat miniRoom = _mini.hidden ? 0 : MINI_SIDE + 5;
    thumbRoom += miniRoom;
    /* the arrow of a forward comes before the picture and the words, so they move over by its width */
    CGFloat forwardRoom = _forwardIcon.hidden ? 0 : FORWARD_SIDE + 4;
    thumbRoom += forwardRoom;
    /* the two line row of the chat settings keeps the preview to one line; the three line row lets it take a second */
    BOOL singleLine = ExteriaChatListStyleStored() == ExteriaChatListTwoLines;
    _preview.numberOfLines = singleLine ? 1 : 2;
    CGSize previewSize = [_preview sizeThatFits:CGSizeMake(MAX(0, width - SIDE_MARGIN - textX - trailing - thumbRoom), 40)];
    BOOL wraps = !singleLine && previewSize.height > _preview.font.lineHeight * 1.5;
    CGFloat titleY = wraps ? 6 : 12;
    CGFloat previewY = wraps ? 31 : 33;
    CGFloat previewHeight = wraps ? 34 : ceil(_preview.font.lineHeight) + 1;

    CGSize timeSize = [_time sizeThatFits:CGSizeMake(120, 20)];
    CGFloat timeX = width - SIDE_MARGIN - timeSize.width;
    _time.frame = CGRectMake(timeX, titleY + 1, timeSize.width, 18);
    CGFloat titleRight = timeX - 6;
    if (!_checks.hidden) {
        CGSize checkSize = _checks.image.size;
        CGFloat checkX = timeX - 4 - checkSize.width;
        _checks.frame = CGRectMake(checkX, titleY + 1 + (18 - checkSize.height) / 2, checkSize.width, checkSize.height);
        titleRight = checkX - 6;
    }
    CGFloat iconSpace = _mutedIcon.hidden ? 0 : _mutedIcon.image.size.width + 4;
    CGFloat titleMax = MAX(0, titleRight - textX - iconSpace);
    CGSize titleSize = [_title sizeThatFits:CGSizeMake(titleMax, 20)];
    CGFloat titleWidth = MIN(titleSize.width, titleMax);
    _title.frame = CGRectMake(textX, titleY, titleWidth, 20);
    _mutedIcon.frame = CGRectMake(textX + titleWidth + 4, titleY + (20 - _mutedIcon.image.size.height) / 2,
                                  _mutedIcon.image.size.width, _mutedIcon.image.size.height);

    CGFloat markCenter = previewY + (wraps ? 16 : 9);
    if (!_mention.hidden) {
        CGFloat right = width - SIDE_MARGIN - (_badge.hidden ? 0 : badgeSize.width + 4);
        _mention.frame = CGRectMake(right - BADGE_HEIGHT, markCenter - BADGE_HEIGHT / 2, BADGE_HEIGHT, BADGE_HEIGHT);
    }
    if (!_badge.hidden) {
        _badge.layer.cornerRadius = badgeSize.height / 2;
        _badge.frame = CGRectMake(width - SIDE_MARGIN - badgeSize.width, markCenter - badgeSize.height / 2, badgeSize.width, badgeSize.height);
    } else if (!_pin.hidden) {
        CGSize pinSize = _pin.image.size;
        _pin.frame = CGRectMake(width - SIDE_MARGIN - pinSize.width, markCenter - pinSize.height / 2, pinSize.width, pinSize.height);
    }
    _preview.frame = CGRectMake(textX + thumbRoom, previewY, MAX(0, width - SIDE_MARGIN - textX - trailing - thumbRoom), previewHeight);
    _typing.frame = CGRectMake(textX, previewY, MAX(0, width - SIDE_MARGIN - textX - trailing), ceil(_preview.font.lineHeight) + 1);
    _forwardIcon.frame = CGRectMake(textX + miniRoom, previewY + (ceil(_preview.font.lineHeight) + 1 - FORWARD_SIDE) / 2, FORWARD_SIDE, FORWARD_SIDE);
    _thumb.frame = CGRectMake(textX + miniRoom + forwardRoom, previewY + (ceil(_preview.font.lineHeight) + 1 - [ExteriaPreviewThumb side]) / 2, [ExteriaPreviewThumb side], [ExteriaPreviewThumb side]);
    _mini.frame = CGRectMake(textX, previewY + (ceil(_preview.font.lineHeight) + 1 - MINI_SIDE) / 2, MINI_SIDE, MINI_SIDE);
    _line.frame = CGRectMake(textX, ROW_HEIGHT - hairline, width - textX, hairline);
    [self layoutSwipe];
}

@end
