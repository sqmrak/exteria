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
#import "exteria_imported_theme.h"
#import "exteria_time.h"
#import "exteria_topic_icon.h"
#import "exteria_developers.h"
#import "exteria_custom_emoji.h"
#import "exteria_name_badge.h"

/* the interface scale of the chat settings: the row, the picture and the places of the lines in it grow with the fonts */
#define SCALED(v) ((v) * ExteriaInterfaceScale())
#define MINI_SIDE 16.0
#define ROW_HEIGHT SCALED(64.0)
#define AVATAR_SIZE SCALED(48.0)
#define RING_OUTSET 4.0
#define ONLINE_SIDE 14.0
#define ONLINE_BORDER 2.0
#define SIDE_MARGIN 14.0
#define BADGE_HEIGHT SCALED(18.0)
#define ICON_SIZE 14.0
#define FORWARD_SIDE 14.0
#define FORUM_TOPIC_ICON 15.0
/* a forum row stands taller: the name, a line of topics and the last message, each of the last two in a capsule */
#define FORUM_ROW_HEIGHT SCALED(86.0)
#define PILL_HEIGHT SCALED(24.0)
#define PILL_PAD 9.0
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
    ExteriaOnlineDotView *_onlineDot;
    /* the small picture of who wrote the last message of a group, when the setting asks for it */
    ExteriaAvatarView *_mini;
    UIImageView *_topicIcon;
    /* a forum row names the topic of its last message between the name and the preview */
    UIImageView *_forumTopicIcon;
    ExteriaEmojiLabel *_forumTopic;
    UIView *_topicPill;
    UIView *_messagePill;
    UIImageView *_pillChevron;
    UIImageView *_secondIcon;
    /* a folded community names its newest chats in the capsules with their pictures, where a forum has the icons of its topics */
    ExteriaAvatarView *_capsuleAvatar;
    ExteriaAvatarView *_capsuleSecondAvatar;
    BOOL _communityCapsules;
    ExteriaEmojiLabel *_secondTopic;
    CGFloat _rowHeight;
    UIImageView *_communityBadge;
    UIButton *_communityHit;
    void (^_communityHandler)(void);
    ExteriaEmojiLabel *_title;
    UIButton *_markHit;
    NSString *_markName;
    long long _markUserId;
    NSUInteger _marks;
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
    UILabel *_reaction;
    UIImageView *_pin;
    UIView *_line;
}
@end

@implementation ExteriaDialogCell

@synthesize swipeDelegate = _swipeDelegate;
@synthesize media = _media;

- (void)markTapped:(UIControl *)control event:(UIEvent *)event {
    UITouch *touch = [[event touchesForView:control] anyObject];
    if (!touch) return;
    CGPoint point = [touch locationInView:_title];
    NSUInteger mark = ExteriaMarkForDocument([_title customEmojiAtPoint:point]);
    if (mark) ExteriaShowMarkNoticeForUser(_markName, mark, _markUserId);
}

+ (CGFloat)rowHeight {
    return ROW_HEIGHT;
}

static BOOL ExteriaDialogShowsTopics(ExteriaDialog *dialog) {
    return (dialog.forum || dialog.communityChats.count > 0) && dialog.forumTopicTitle.length > 0;
}

+ (CGFloat)rowHeightForDialog:(ExteriaDialog *)dialog {
    return ExteriaDialogShowsTopics(dialog) ? FORUM_ROW_HEIGHT : ROW_HEIGHT;
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

/* on the plate of a chosen row the green dot is white, with the ring in the color of the plate; elsewhere it is green on the ring of the screen */
- (void)refreshOnlineDot {
    BOOL chosen = self.selected || self.highlighted;
    _onlineDot.inverted = chosen;
    _onlineDot.layer.borderColor = (chosen ? ExteriaColorField() : ExteriaColorScreen()).CGColor;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [self refreshOnlineDot];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [self refreshOnlineDot];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = ExteriaImportedThemeColor("chatList.itemHighlightedBg") ?: ExteriaColorField();
    self.selectedBackgroundView = selected;

    /* the row slides inside the content view, which the cell resets to its own frame on every layout */
    _actionButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _actionButton.backgroundColor = ExteriaColorAccent();
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
    _storyRing.followsAvatarShape = YES;
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
    _rowHeight = ROW_HEIGHT;
    _topicPill = [[UIView alloc] init];
    _topicPill.layer.cornerRadius = PILL_HEIGHT / 2;
    _topicPill.hidden = YES;
    [_slider addSubview:_topicPill];
    _messagePill = [[UIView alloc] init];
    _messagePill.layer.cornerRadius = PILL_HEIGHT / 2;
    _messagePill.hidden = YES;
    [_slider addSubview:_messagePill];
    _pillChevron = [[UIImageView alloc] init];
    _pillChevron.hidden = YES;
    [_slider addSubview:_pillChevron];
    _secondIcon = [[UIImageView alloc] init];
    _secondIcon.contentMode = UIViewContentModeScaleAspectFit;
    _secondIcon.hidden = YES;
    [_slider addSubview:_secondIcon];
    _secondTopic = [ExteriaCellEmojiLabel(ExteriaFontRegular(14), ExteriaColorSecondary(), ExteriaTextAlignmentLeft) retain];
    _secondTopic.dropsUndrawable = YES;
    _secondTopic.hidden = YES;
    [_slider addSubview:_secondTopic];
    _forumTopicIcon = [[UIImageView alloc] init];
    _forumTopicIcon.contentMode = UIViewContentModeScaleAspectFit;
    _forumTopicIcon.hidden = YES;
    [_slider addSubview:_forumTopicIcon];
    _capsuleAvatar = [[ExteriaAvatarView alloc] init];
    _capsuleAvatar.hidden = YES;
    [_slider addSubview:_capsuleAvatar];
    _capsuleSecondAvatar = [[ExteriaAvatarView alloc] init];
    _capsuleSecondAvatar.hidden = YES;
    [_slider addSubview:_capsuleSecondAvatar];
    _forumTopic = [ExteriaCellEmojiLabel(ExteriaFontSemibold(14), ExteriaColorAccent(), ExteriaTextAlignmentLeft) retain];
    _forumTopic.dropsUndrawable = YES;
    _forumTopic.hidden = YES;
    [_slider addSubview:_forumTopic];
    _communityBadge = [[UIImageView alloc] initWithImage:ExteriaCommunityBadgeImage()];
    _communityBadge.hidden = YES;
    [_slider addSubview:_communityBadge];
    _communityHit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _communityHit.hidden = YES;
    [_communityHit addTarget:self action:@selector(communityTapped) forControlEvents:UIControlEventTouchUpInside];
    [_slider addSubview:_communityHit];
    _title = [ExteriaCellEmojiLabel(ExteriaFontSemibold(15.5), ExteriaImportedThemeColor("chatList.title") ?: ExteriaColorTitle(), ExteriaTextAlignmentLeft) retain];
    _title.dropsUndrawable = YES;
    [_slider addSubview:_title];
    _markHit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_markHit addTarget:self action:@selector(markTapped:event:) forControlEvents:UIControlEventTouchUpInside];
    [_slider addSubview:_markHit];
    _mutedIcon = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolBellSlash, 13, ExteriaColorMuted())];
    [_slider addSubview:_mutedIcon];
    _time = [ExteriaCellLabel(ExteriaFontRegular(12.5), ExteriaImportedThemeColor("chatList.dateText") ?: ExteriaColorSecondary(), ExteriaTextAlignmentRight) retain];
    [_slider addSubview:_time];
    _checks = [[UIImageView alloc] init];
    [_slider addSubview:_checks];
    _preview = [ExteriaCellEmojiLabel(ExteriaFontRegular(14), ExteriaImportedThemeColor("chatList.messageText") ?: ExteriaColorSecondary(), ExteriaTextAlignmentLeft) retain];
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
    [_mention addSubview:atMark];
    [_slider addSubview:_mention];
    _reaction = [ExteriaCellPill(ExteriaFontSemibold(11.5), [UIColor whiteColor], ExteriaTextAlignmentCenter) retain];
    _reaction.layer.cornerRadius = BADGE_HEIGHT / 2;
    _reaction.layer.masksToBounds = YES;
    _reaction.backgroundColor = [UIColor colorWithRed:230.0 / 255 green:62.0 / 255 blue:72.0 / 255 alpha:1];
    UIImageView *heartMark = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolHeart, 11, [UIColor whiteColor])] autorelease];
    heartMark.center = CGPointMake(BADGE_HEIGHT / 2, BADGE_HEIGHT / 2);
    [_reaction addSubview:heartMark];
    [_slider addSubview:_reaction];
    _pin = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPin, 14, ExteriaColorMuted())];
    [_slider addSubview:_pin];
    _line = [[UIView alloc] init];
    _line.backgroundColor = ExteriaImportedThemeColor("chatList.itemSeparator") ?: ExteriaColorHairline();
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
    [_forumTopicIcon release];
    [_capsuleAvatar release];
    [_capsuleSecondAvatar release];
    [_forumTopic release];
    [_topicPill release];
    [_messagePill release];
    [_pillChevron release];
    [_secondIcon release];
    [_secondTopic release];
    [_communityBadge release];
    [_communityHit release];
    [_communityHandler release];
    [_title release];
    [_markHit release];
    [_markName release];
    [_mutedIcon release];
    [_time release];
    [_checks release];
    [_preview release];
    [_typing release];
    [_thumb release];
    [_forwardIcon release];
    [_badge release];
    [_mention release];
    [_reaction release];
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
    _avatar.accent = dialog.saved || dialog.folder || dialog.replies;
    _avatar.symbol = dialog.folder ? ExteriaSymbolArchive : (dialog.replies ? ExteriaSymbolReply : ExteriaSymbolBookmark);
    _avatar.showsSymbol = dialog.saved || dialog.folder || dialog.replies;
    [_avatar setPhoto:dialog.saved || dialog.folder || dialog.replies ? nil : dialog.photo cache:avatars];
    /* a topic has the icon of its own in the place of the group's photo */
    BOOL topic = dialog.topicId > 0;
    _avatar.hidden = topic;
    _topicIcon.hidden = !topic;
    _topicIcon.image = topic ? ExteriaTopicIconImage(dialog) : nil;
    BOOL forumTopic = ExteriaDialogShowsTopics(dialog);
    _rowHeight = forumTopic ? FORUM_ROW_HEIGHT : ROW_HEIGHT;
    _forumTopicIcon.hidden = _forumTopic.hidden = _topicPill.hidden = _messagePill.hidden = _pillChevron.hidden = !forumTopic;
    UIColor *pill = ExteriaColorField();
    _topicPill.backgroundColor = pill;
    _messagePill.backgroundColor = pill;
    _pillChevron.image = forumTopic ? ExteriaSymbolImage(ExteriaSymbolChevronRight, 12, ExteriaColorSecondary()) : nil;
    BOOL second = forumTopic && dialog.forumSecondTitle.length > 0;
    _secondIcon.hidden = _secondTopic.hidden = !second;
    _secondIcon.image = second ? ExteriaTopicIconImageOf(dialog.forumSecondEmoji, dialog.forumSecondColor) : nil;
    _secondTopic.text = second ? dialog.forumSecondTitle : @"";
    _forumTopicIcon.image = forumTopic ? ExteriaTopicIconImageOf(dialog.forumTopicEmoji, dialog.forumTopicColor) : nil;
    _forumTopic.text = forumTopic ? dialog.forumTopicTitle : @"";
    _forumTopic.textColor = ExteriaColorAccent();
    _communityCapsules = forumTopic && dialog.communityChats.count > 0;
    if (_communityCapsules) {
        ExteriaDialog *first = [dialog.communityChats objectAtIndex:0];
        _capsuleAvatar.seed = first.avatarSeed;
        _capsuleAvatar.initials = first.initials;
        [_capsuleAvatar setPhoto:first.photo cache:avatars];
        ExteriaDialog *next = dialog.communityChats.count > 1 ? [dialog.communityChats objectAtIndex:1] : nil;
        _capsuleSecondAvatar.seed = next.avatarSeed;
        _capsuleSecondAvatar.initials = next.initials;
        [_capsuleSecondAvatar setPhoto:next.photo cache:avatars];
    } else {
        [_capsuleAvatar setPhoto:nil cache:nil];
        [_capsuleSecondAvatar setPhoto:nil cache:nil];
    }
    /* only a private chat with a live account has a presence; the saved messages row would show the own one */
    _onlineDot.hidden = topic || dialog.kind != EXTERIA_DIALOG_USER || dialog.saved || dialog.presence != EXTERIA_PRESENCE_ONLINE;
    [self refreshOnlineDot];
    _storyRing.hidden = YES;
    /* a chat that was added to a community wears the arrow of its avatar too, and the arrow opens the community */
    _communityBadge.hidden = !(dialog.community || dialog.linkedCommunityId);
    _communityHit.hidden = !dialog.linkedCommunityId;
    [_communityHandler release];
    _communityHandler = nil;
    NSArray *badge = nil;
    _marks = ExteriaDialogIsDeveloper(dialog);
    [_markName release];
    _markName = [dialog.title copy];
    _markUserId = dialog.peerId;
    _title.text = ExteriaNameWithBadges(dialog.title, ExteriaDialogBadgeDocument(dialog), _marks, &badge);
    self.backgroundColor = ExteriaImportedThemeColor(dialog.pinned ? "chatList.pinnedItemBg" : "chatList.itemBg") ?: [UIColor clearColor];
    self.selectedBackgroundView.backgroundColor = ExteriaImportedThemeColor(dialog.pinned ? "chatList.pinnedItemHighlightedBg" : "chatList.itemHighlightedBg") ?: ExteriaColorField();
    _title.entities = badge;
    _mutedIcon.hidden = !dialog.muted;
    _time.text = ExteriaListTimeText(dialog.date);
    _preview.text = dialog.preview;
    _preview.entities = dialog.previewEntities;
    _preview.textColor = ExteriaImportedThemeColor("chatList.messageText") ?: ExteriaColorSecondary();
    [_preview setPrefixLength:0 color:nil];
    _preview.hidden = NO;
    /* the capsule of a forum row has no room for the picture of the sender */
    BOOL mini = dialog.showsSender && !forumTopic && ExteriaChatFlagGet(ExteriaChatFlagSenderAvatars);
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
        _checks.image = ExteriaCheckImage(dialog.read, ICON_SIZE, ExteriaImportedThemeColor("chatList.checkmark") ?: ExteriaColorAccent());
        _checks.hidden = NO;
    } else {
        _checks.hidden = YES;
    }
    BOOL showsBadge = dialog.unreadCount > 0 || (dialog.unread && dialog.unreadCount == 0);
    _badge.hidden = !showsBadge;
    _badge.text = dialog.unreadCount > 999 ? @"999+" : (dialog.unreadCount > 0 ? [NSString stringWithFormat:@"%ld", (long)dialog.unreadCount] : @"");
    /* a chat with its notifications off counts in grey, as in the official clients, not in the accent that says something new is waiting; an imported theme may name its own */
    _badge.backgroundColor = ExteriaImportedThemeColor(dialog.muted ? "chatList.unreadBadgeInactiveBg" : "chatList.unreadBadgeActiveBg") ?: (dialog.muted ? ExteriaColorMuted() : ExteriaColorAccent());
    _badge.textColor = ExteriaImportedThemeColor(dialog.muted ? "chatList.unreadBadgeInactiveText" : "chatList.unreadBadgeActiveText") ?: [UIColor whiteColor];
    _mention.hidden = dialog.mentions <= 0;
    _reaction.hidden = dialog.reactions <= 0;
    _pin.hidden = !dialog.pinned || showsBadge || !_mention.hidden || !_reaction.hidden;
    self.accessibilityLabel = forumTopic ? [NSString stringWithFormat:@"%@, %@, %@", dialog.title, dialog.forumTopicTitle, dialog.preview]
                                         : [NSString stringWithFormat:@"%@, %@", dialog.title, dialog.preview];
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
    _preview.entities = nil;
    [_preview setPrefixLength:label.length color:ExteriaImportedThemeColor("chatList.messageDraftText") ?: ExteriaColorBadgeRed()];
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
    case ExteriaChatSwipeFolders: return ExteriaDialogActionNone;
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
    /* deleting is the one swipe that is red; the others, the archive among them, take the accent of the app */
    _actionButton.backgroundColor = action == ExteriaDialogActionDeleteChat ? [UIColor colorWithRed:0.89 green:0.31 blue:0.31 alpha:1] : ExteriaColorAccent();
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
    _slider.frame = CGRectMake(-_offset, 0, width, _rowHeight);
    _actionButton.hidden = _offset <= 0;
    _actionButton.frame = CGRectMake(width - _offset, 0, _offset, _rowHeight);
    /* the icon keeps to the moving edge until the button is wide enough to center it */
    CGFloat slot = MAX(_offset, ACTION_WIDTH);
    _actionContent.frame = CGRectMake(0, 0, slot, _rowHeight);
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
    _avatar.frame = CGRectMake(SIDE_MARGIN, _rowHeight > ROW_HEIGHT ? SCALED(10) : (ROW_HEIGHT - AVATAR_SIZE) / 2, AVATAR_SIZE, AVATAR_SIZE);
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
    /* a reaction we have not seen gets a red disc with a heart, left of the @ */
    if (!_reaction.hidden) trailing += BADGE_HEIGHT + (trailing ? 4 : 8);
    /* a preview that wraps pulls the nick up and leaves a wider gap under it; a one line preview sits close under the nick */
    CGFloat thumbRoom = _thumb.hidden ? 0 : [ExteriaPreviewThumb room];
    /* the small picture of the sender stands first in the line, and what follows it moves over */
    CGFloat miniRoom = _mini.hidden ? 0 : MINI_SIDE + 5;
    thumbRoom += miniRoom;
    /* the arrow of a forward comes before the picture and the words, so they move over by its width */
    CGFloat forwardRoom = _forwardIcon.hidden ? 0 : FORWARD_SIDE + 4;
    thumbRoom += forwardRoom;
    /* the two line row of the chat settings keeps the preview to one line; the three line row lets it take a second */
    /* the topic line takes the second line of the row, so the preview keeps to one line under it */
    BOOL topicLine = !_forumTopic.hidden;
    BOOL singleLine = topicLine || ExteriaChatListStyleStored() == ExteriaChatListTwoLines;
    _preview.numberOfLines = singleLine ? 1 : 2;
    /* the last message of a forum sits in a capsule that has a chevron at its end, so the words start and stop inside it */
    CGFloat previewX = topicLine ? textX + PILL_PAD : textX;
    CGFloat chevronRoom = topicLine ? PILL_PAD + 12 + 4 : 0;
    CGSize previewSize = [_preview sizeThatFits:CGSizeMake(MAX(0, width - SIDE_MARGIN - previewX - trailing - thumbRoom - chevronRoom), 40)];
    BOOL wraps = !singleLine && previewSize.height > _preview.font.lineHeight * 1.5;
    CGFloat topicY = SCALED(33), pillY = SCALED(33) + PILL_HEIGHT + 2;
    CGFloat titleY = topicLine ? SCALED(8) : (wraps ? SCALED(6) : SCALED(12));
    CGFloat previewY = topicLine ? pillY + (PILL_HEIGHT - ceil(_preview.font.lineHeight) - 1) / 2 : (wraps ? SCALED(31) : SCALED(33));
    CGFloat previewHeight = wraps ? SCALED(34) : ceil(_preview.font.lineHeight) + 1;

    CGSize timeSize = [_time sizeThatFits:CGSizeMake(120, SCALED(20))];
    CGFloat timeX = width - SIDE_MARGIN - timeSize.width;
    _time.frame = CGRectMake(timeX, titleY + 1, timeSize.width, SCALED(18));
    CGFloat titleRight = timeX - 6;
    if (!_checks.hidden) {
        CGSize checkSize = _checks.image.size;
        CGFloat checkX = timeX - 4 - checkSize.width;
        _checks.frame = CGRectMake(checkX, titleY + 1 + (SCALED(18) - checkSize.height) / 2, checkSize.width, checkSize.height);
        titleRight = checkX - 6;
    }
    CGFloat iconSpace = _mutedIcon.hidden ? 0 : _mutedIcon.image.size.width + 4;
    CGFloat titleMax = MAX(0, titleRight - textX - iconSpace);
    CGSize titleSize = [_title sizeThatFits:CGSizeMake(titleMax, SCALED(20))];
    CGFloat titleWidth = MIN(titleSize.width, titleMax);
    _title.frame = CGRectMake(textX, titleY, titleWidth, SCALED(20));
    CGFloat fullTitleWidth = [_title sizeThatFits:CGSizeMake(4096, 20)].width;
    NSUInteger markCount = 0;
    for (NSUInteger bit = 1; bit <= ExteriaMarkFlawSeer; bit <<= 1) if (_marks & bit) ++markCount;
    CGFloat markWidth = markCount * 30.0 + (_marks & ExteriaMarkCaution ? 24.0 * (EXTERIA_CAUTION_BADGE_RATIO - 1) : 0);
    _markHit.hidden = !markCount || fullTitleWidth > titleMax;
    _markHit.frame = CGRectMake(textX + MAX(0, titleWidth - markWidth), titleY - 4, MIN(titleWidth, markWidth), 28);
    _mutedIcon.frame = CGRectMake(textX + titleWidth + 4, titleY + (SCALED(20) - _mutedIcon.image.size.height) / 2,
                                  _mutedIcon.image.size.width, _mutedIcon.image.size.height);

    /* the topic of the last message stands in a capsule, and the topic before it follows in plain words as far as the row reaches */
    CGFloat topicHeight = ceil(_forumTopic.font.lineHeight) + 1;
    CGFloat rowRight = width - SIDE_MARGIN;
    CGFloat nameX = textX + PILL_PAD + FORUM_TOPIC_ICON + 4;
    CGFloat nameWidth = MIN([_forumTopic sizeThatFits:CGSizeMake(4096, topicHeight)].width, MAX(0, rowRight - PILL_PAD - nameX));
    CGFloat pillRight = nameX + nameWidth + PILL_PAD;
    _topicPill.frame = CGRectMake(textX, topicY, pillRight - textX, PILL_HEIGHT);
    _forumTopicIcon.frame = CGRectMake(textX + PILL_PAD, topicY + (PILL_HEIGHT - FORUM_TOPIC_ICON) / 2, FORUM_TOPIC_ICON, FORUM_TOPIC_ICON);
    _forumTopic.frame = CGRectMake(nameX, topicY + (PILL_HEIGHT - topicHeight) / 2, nameWidth, topicHeight);
    CGFloat secondX = pillRight + 8;
    CGFloat secondNameX = secondX + FORUM_TOPIC_ICON + 4;
    BOOL secondFits = !_secondTopic.hidden && rowRight - secondNameX >= 36;
    _secondIcon.hidden = _secondTopic.hidden ? YES : !secondFits;
    _secondIcon.frame = CGRectMake(secondX, topicY + (PILL_HEIGHT - FORUM_TOPIC_ICON) / 2, FORUM_TOPIC_ICON, FORUM_TOPIC_ICON);
    /* the pictures of the chats take the places of the icons of the topics */
    BOOL secondPicture = _communityCapsules && !_secondIcon.hidden;
    _capsuleAvatar.hidden = !_communityCapsules;
    _capsuleAvatar.frame = _forumTopicIcon.frame;
    _capsuleSecondAvatar.hidden = !secondPicture;
    _capsuleSecondAvatar.frame = _secondIcon.frame;
    if (_communityCapsules) _forumTopicIcon.hidden = _secondIcon.hidden = YES;
    _secondTopic.frame = CGRectMake(secondNameX, topicY + (PILL_HEIGHT - topicHeight) / 2, MAX(0, rowRight - secondNameX), topicHeight);
    CGFloat messageRight = width - SIDE_MARGIN - trailing;
    _messagePill.frame = CGRectMake(textX, pillY, MAX(0, messageRight - textX), PILL_HEIGHT);
    _pillChevron.frame = CGRectMake(messageRight - PILL_PAD - 12, pillY + (PILL_HEIGHT - 12) / 2, 12, 12);

    CGFloat markCenter = topicLine ? pillY + PILL_HEIGHT / 2 : previewY + (wraps ? SCALED(16) : SCALED(9));
    CGFloat badgesRight = width - SIDE_MARGIN - (_badge.hidden ? 0 : badgeSize.width + 4);
    if (!_mention.hidden) {
        _mention.frame = CGRectMake(badgesRight - BADGE_HEIGHT, markCenter - BADGE_HEIGHT / 2, BADGE_HEIGHT, BADGE_HEIGHT);
        badgesRight -= BADGE_HEIGHT + 4;
    }
    if (!_reaction.hidden) _reaction.frame = CGRectMake(badgesRight - BADGE_HEIGHT, markCenter - BADGE_HEIGHT / 2, BADGE_HEIGHT, BADGE_HEIGHT);
    if (!_badge.hidden) {
        _badge.layer.cornerRadius = badgeSize.height / 2;
        _badge.frame = CGRectMake(width - SIDE_MARGIN - badgeSize.width, markCenter - badgeSize.height / 2, badgeSize.width, badgeSize.height);
    } else if (!_pin.hidden) {
        CGSize pinSize = _pin.image.size;
        _pin.frame = CGRectMake(width - SIDE_MARGIN - pinSize.width, markCenter - pinSize.height / 2, pinSize.width, pinSize.height);
    }
    _preview.frame = CGRectMake(previewX + thumbRoom, previewY, MAX(0, width - SIDE_MARGIN - previewX - trailing - thumbRoom - chevronRoom), previewHeight);
    _typing.frame = CGRectMake(previewX, previewY, MAX(0, width - SIDE_MARGIN - previewX - trailing - chevronRoom), ceil(_preview.font.lineHeight) + 1);
    _forwardIcon.frame = CGRectMake(previewX + miniRoom, previewY + (ceil(_preview.font.lineHeight) + 1 - FORWARD_SIDE) / 2, FORWARD_SIDE, FORWARD_SIDE);
    _thumb.frame = CGRectMake(previewX + miniRoom + forwardRoom, previewY + (ceil(_preview.font.lineHeight) + 1 - [ExteriaPreviewThumb side]) / 2, [ExteriaPreviewThumb side], [ExteriaPreviewThumb side]);
    _mini.frame = CGRectMake(previewX, previewY + (ceil(_preview.font.lineHeight) + 1 - MINI_SIDE) / 2, MINI_SIDE, MINI_SIDE);
    _line.frame = CGRectMake(textX, _rowHeight - hairline, width - textX, hairline);
    [self layoutSwipe];
}

@end
