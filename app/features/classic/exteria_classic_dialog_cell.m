#import "exteria_classic_dialog_cell.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_chat_settings.h"
#import "exteria_classic_chrome.h"
#import "exteria_community_badge.h"
#import "exteria_emoji_label.h"
#import "exteria_draft.h"
#import "exteria_preview_thumb.h"
#import "exteria_status_label.h"
#import "exteria_story_ring.h"
#import "exteria_string_drawing.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_topic_icon.h"
#import "exteria_developers.h"
#import "exteria_mutual_icon.h"
#import "exteria_name_badge.h"

#define ROW_HEIGHT 72.0
#define AVATAR_SIZE 52.0
#define RING_OUTSET 3.0
#define FORWARD_SIDE 14.0
#define ONLINE_SIDE 14.0
#define ONLINE_BORDER 2.0
#define SIDE 8.0
#define ACCESSORY_WIDTH 62.0
/* a forum row has the name, a plate with the topic of the last message and a plate with the message */
#define FORUM_ROW_HEIGHT 90.0
#define FORUM_TITLE_Y 9.0
#define FORUM_TOPIC_Y 32.0
#define PLATE_HEIGHT 22.0
#define PLATE_GAP 3.0
#define PLATE_PAD 7.0
#define PLATE_RADIUS 6.0
#define FORUM_TOPIC_ICON 14.0
#define CHEVRON_SIDE 12.0

@interface ExteriaClassicDialogCell () {
    ExteriaAvatarView *_avatar;
    ExteriaStoryRing *_storyRing;
    /* the green dot on the corner of the avatar of a user who is on line */
    UIView *_onlineDot;
    UIImageView *_topicIcon;
    /* the plates of a forum row and what stands in them; hidden for every other row */
    UIView *_topicPlate;
    UIView *_messagePlate;
    UIImageView *_plateChevron;
    UIImageView *_forumTopicIcon;
    ExteriaEmojiLabel *_forumTopic;
    UIImageView *_secondIcon;
    ExteriaEmojiLabel *_secondTopic;
    BOOL _forumLine;
    UIImageView *_communityBadge;
    UIButton *_communityHit;
    void (^_communityHandler)(void);
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_preview;
    ExteriaStatusLabel *_typing;
    ExteriaPreviewThumb *_thumb;
    /* the arrow before the preview of a forwarded message */
    UIImageView *_forwardIcon;
    /* the characters of the preview that read "Draft:", zero while the row shows a message */
    NSUInteger _draftPrefix;
    ExteriaMediaCache *_media;
    UIImageView *_muted;
    UIView *_accessory;
    UIButton *_mutualButton;
    UILabel *_time;
    UIImageView *_check;
    UIView *_mark;
    UIColor *_titleColor;
    UIColor *_previewColor;
    UIColor *_timeColor;
}
@end

@implementation ExteriaClassicDialogCell

@synthesize communityHandler = _communityHandler;

- (void)mutualTapped {
    ExteriaShowMutualNotice();
}

- (void)communityTapped {
    if (_communityHandler) _communityHandler();
}

@synthesize media = _media;

+ (CGFloat)rowHeight {
    return ROW_HEIGHT;
}

static BOOL ExteriaClassicShowsTopics(ExteriaDialog *dialog) {
    return dialog.forum && dialog.forumTopicTitle.length > 0;
}

+ (CGFloat)rowHeightForDialog:(ExteriaDialog *)dialog {
    return ExteriaClassicShowsTopics(dialog) ? FORUM_ROW_HEIGHT : ROW_HEIGHT;
}

static UIView *ExteriaClassicPlate(void) {
    UIView *plate = [[UIView alloc] init];
    plate.layer.cornerRadius = PLATE_RADIUS;
    plate.layer.borderWidth = 1;
    plate.hidden = YES;
    plate.userInteractionEnabled = NO;
    return plate;
}

static UIImageView *ExteriaClassicTopicImageView(void) {
    UIImageView *view = [[UIImageView alloc] init];
    view.contentMode = UIViewContentModeScaleAspectFit;
    view.hidden = YES;
    return view;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    ExteriaClassicStyleCell(self);
    UIView *selection = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    selection.backgroundColor = ExteriaClassicSelectionColor();
    self.selectedBackgroundView = selection;
    _avatar = [[ExteriaAvatarView alloc] init];
    [self.contentView addSubview:_avatar];
    _storyRing = [[ExteriaStoryRing alloc] init];
    _storyRing.hidden = YES;
    _storyRing.followsAvatarShape = YES;
    [self.contentView addSubview:_storyRing];
    _onlineDot = [[ExteriaOnlineDotView alloc] init];
    _onlineDot.hidden = YES;
    _onlineDot.userInteractionEnabled = NO;
    _onlineDot.layer.cornerRadius = ONLINE_SIDE / 2;
    _onlineDot.layer.borderWidth = ONLINE_BORDER;
    _onlineDot.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.contentView addSubview:_onlineDot];
    _topicIcon = [[UIImageView alloc] init];
    _topicIcon.contentMode = UIViewContentModeScaleAspectFit;
    _topicIcon.hidden = YES;
    [self.contentView addSubview:_topicIcon];
    _topicPlate = ExteriaClassicPlate();
    [self.contentView addSubview:_topicPlate];
    _messagePlate = ExteriaClassicPlate();
    [self.contentView addSubview:_messagePlate];
    _communityBadge = [[UIImageView alloc] initWithImage:ExteriaCommunityBadgeImage()];
    _communityBadge.hidden = YES;
    _communityHit.hidden = YES;
    [self.contentView addSubview:_communityBadge];
    _communityHit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _communityHit.hidden = YES;
    [_communityHit addTarget:self action:@selector(communityTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_communityHit];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.dropsUndrawable = YES;
    /* the font of the modern list, whose nicks with emoji lay on the line; the plain bold system font drew them oversized in the classic list */
    _title.font = ExteriaFontSemibold(16);
    [self.contentView addSubview:_title];
    _preview = [[ExteriaEmojiLabel alloc] init];
    _preview.font = [UIFont systemFontOfSize:14];
    _preview.numberOfLines = 2;
    [self.contentView addSubview:_preview];
    _typing = [[ExteriaStatusLabel alloc] init];
    _typing.backgroundColor = [UIColor clearColor];
    _typing.font = [UIFont systemFontOfSize:14];
    _typing.activeColor = ExteriaColorAccent();
    _typing.hidden = YES;
    [self.contentView addSubview:_typing];
    _thumb = [[ExteriaPreviewThumb alloc] init];
    [self.contentView addSubview:_thumb];
    _forwardIcon = [[UIImageView alloc] init];
    _forwardIcon.hidden = YES;
    [self.contentView addSubview:_forwardIcon];
    _plateChevron = ExteriaClassicTopicImageView();
    [self.contentView addSubview:_plateChevron];
    _forumTopicIcon = ExteriaClassicTopicImageView();
    [self.contentView addSubview:_forumTopicIcon];
    _forumTopic = [[ExteriaEmojiLabel alloc] init];
    _forumTopic.dropsUndrawable = YES;
    _forumTopic.font = ExteriaFontSemibold(14);
    _forumTopic.hidden = YES;
    [self.contentView addSubview:_forumTopic];
    _secondIcon = ExteriaClassicTopicImageView();
    [self.contentView addSubview:_secondIcon];
    _secondTopic = [[ExteriaEmojiLabel alloc] init];
    _secondTopic.dropsUndrawable = YES;
    _secondTopic.font = [UIFont systemFontOfSize:14];
    _secondTopic.hidden = YES;
    [self.contentView addSubview:_secondTopic];
    _muted = [[UIImageView alloc] init];
    [self.contentView addSubview:_muted];
    _accessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ACCESSORY_WIDTH, ROW_HEIGHT - 20)];
    _time = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, ACCESSORY_WIDTH, 16)];
    ExteriaLabelFitToWidth(_time, 9);
    _time.font = [UIFont systemFontOfSize:13];
    _time.textAlignment = ExteriaTextAlignmentRight;
    _time.backgroundColor = [UIColor clearColor];
    [_accessory addSubview:_time];
    _check = [[UIImageView alloc] init];
    [_accessory addSubview:_check];
    _mutualButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _mutualButton.hidden = YES;
    _mutualButton.frame = CGRectMake(ACCESSORY_WIDTH - 40, 0, 40, ROW_HEIGHT - 20);
    [_mutualButton setImage:ExteriaMutualIconImage(24, [UIColor grayColor]) forState:UIControlStateNormal];
    _mutualButton.accessibilityLabel = NSLocalizedString(@"contact.mutual", nil);
    [_mutualButton addTarget:self action:@selector(mutualTapped) forControlEvents:UIControlEventTouchUpInside];
    [_accessory addSubview:_mutualButton];
    self.accessoryView = _accessory;
    _titleColor = [(ExteriaThemeIsDark() ? ExteriaColorTitle() : [UIColor blackColor]) retain];
    _previewColor = [[UIColor grayColor] retain];
    _timeColor = [ExteriaThemeTinted([UIColor colorWithRed:0.52 green:0.30 blue:0.78 alpha:1]) retain];
    return self;
}

- (void)dealloc {
    [_avatar release];
    [_storyRing release];
    [_onlineDot release];
    [_topicIcon release];
    [_topicPlate release];
    [_messagePlate release];
    [_plateChevron release];
    [_forumTopicIcon release];
    [_forumTopic release];
    [_secondIcon release];
    [_secondTopic release];
    [_communityBadge release];
    [_communityHit release];
    [_communityHandler release];
    [_title release];
    [_preview release];
    [_typing release];
    [_thumb release];
    [_forwardIcon release];
    [_muted release];
    [_accessory release];
    [_mutualButton release];
    [_time release];
    [_check release];
    [_mark release];
    [_titleColor release];
    [_previewColor release];
    [_timeColor release];
    [super dealloc];
}

/* the accessory is centered in the row, so its height follows the row to keep the time and the count level with the lines they belong to */
- (void)setForumLine:(BOOL)on dialog:(ExteriaDialog *)dialog {
    _forumLine = on;
    BOOL dark = ExteriaThemeIsDark();
    UIColor *fill = [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.08 : 0.05];
    CGColorRef border = [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.12 : 0.10].CGColor;
    for (UIView *plate in [NSArray arrayWithObjects:_topicPlate, _messagePlate, nil]) {
        plate.hidden = !on;
        plate.backgroundColor = fill;
        plate.layer.borderColor = border;
    }
    _plateChevron.hidden = !on;
    _plateChevron.image = on ? ExteriaSymbolImage(ExteriaSymbolChevronRight, CHEVRON_SIDE, [UIColor grayColor]) : nil;
    _forumTopic.hidden = _forumTopicIcon.hidden = !on;
    _forumTopic.text = on ? dialog.forumTopicTitle : @"";
    _forumTopic.textColor = ExteriaColorAccent();
    _forumTopicIcon.image = on ? ExteriaTopicIconImageOf(dialog.forumTopicEmoji, dialog.forumTopicColor) : nil;
    BOOL second = on && dialog.forumSecondTitle.length > 0;
    _secondIcon.hidden = _secondTopic.hidden = !second;
    _secondTopic.text = second ? dialog.forumSecondTitle : @"";
    _secondTopic.textColor = [UIColor grayColor];
    _secondIcon.image = second ? ExteriaTopicIconImageOf(dialog.forumSecondEmoji, dialog.forumSecondColor) : nil;
    CGFloat height = (on ? FORUM_ROW_HEIGHT : ROW_HEIGHT) - 20;
    _accessory.frame = CGRectMake(0, 0, ACCESSORY_WIDTH, height);
    _mutualButton.frame = CGRectMake(ACCESSORY_WIDTH - 40, 0, 40, height);
}

- (void)updateTextColors {
    _title.textColor = _titleColor;
    _preview.textColor = _previewColor;
    [_preview setPrefixLength:_draftPrefix color:ExteriaColorBadgeRed()];
    _time.textColor = _timeColor;
}

- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars {
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
    /* only a private chat with a live account has a presence; the saved messages row would show the own one */
    _onlineDot.hidden = topic || dialog.kind != EXTERIA_DIALOG_USER || dialog.saved || dialog.presence != EXTERIA_PRESENCE_ONLINE;
    _storyRing.hidden = YES;
    /* a chat that was added to a community wears the arrow of its avatar too, and the arrow opens the community */
    _communityBadge.hidden = !(dialog.community || dialog.linkedCommunityId);
    _communityHit.hidden = !dialog.linkedCommunityId;
    _mutualButton.hidden = YES;
    [_communityHandler release];
    _communityHandler = nil;
    NSArray *badge = nil;
    _title.text = ExteriaNameWithBadges(dialog.title, ExteriaDialogBadgeDocument(dialog), ExteriaDialogIsDeveloper(dialog), &badge);
    _title.entities = badge;
    _preview.text = dialog.preview;
    _preview.entities = dialog.previewEntities;
    _draftPrefix = 0;
    _preview.hidden = NO;
    [_typing setStatus:@"" kind:ExteriaStatusPlain];
    _typing.hidden = YES;
    BOOL forumLine = ExteriaClassicShowsTopics(dialog);
    [self setForumLine:forumLine dialog:dialog];
    _preview.numberOfLines = forumLine || ExteriaChatListStyleStored() == ExteriaChatListTwoLines ? 1 : 2;
    [_thumb showFile:dialog.previewFile cache:_media];
    _forwardIcon.hidden = !dialog.forwarded;
    if (dialog.forwarded) _forwardIcon.image = ExteriaSymbolImage(ExteriaSymbolForward, FORWARD_SIDE, [UIColor grayColor]);
    [_previewColor release];
    _previewColor = [[UIColor grayColor] retain];
    _time.text = ExteriaListTimeText(dialog.date);
    _muted.image = dialog.muted ? ExteriaSymbolImage(ExteriaSymbolBellSlash, 13, [UIColor grayColor]) : nil;
    if (dialog.outgoing && dialog.date > 0) {
        _check.image = ExteriaCheckImage(dialog.read, 12, ExteriaThemeTinted([UIColor colorWithRed:0.52 green:0.30 blue:0.78 alpha:1]));
        _check.hidden = NO;
    } else {
        _check.hidden = YES;
    }
    [_mark removeFromSuperview];
    [_mark release];
    _mark = nil;
    BOOL unread = dialog.unreadCount > 0 || dialog.unread;
    if (unread) {
        NSString *count = dialog.unreadCount > 999 ? @"999+" : (dialog.unreadCount > 0 ? [NSString stringWithFormat:@"%ld", (long)dialog.unreadCount] : @" ");
        /* the badge draws its own capsule and color; a background set on it would fill the whole rectangle */
        UILabel *badge = ExteriaClassicBadge(count, dialog.muted);
        _mark = [badge retain];
    } else if (dialog.pinned) {
        UIImageView *pin = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPin, 16, [UIColor grayColor])] autorelease];
        _mark = [pin retain];
    }
    if (_mark) {
        CGRect frame = _mark.frame;
        /* in a forum row the count sits level with the plate of the message */
        CGFloat markY = _forumLine ? FORUM_TOPIC_Y + PLATE_HEIGHT + PLATE_GAP + (PLATE_HEIGHT - frame.size.height) / 2 - 10 : 26;
        frame.origin = CGPointMake(ACCESSORY_WIDTH - frame.size.width, markY);
        _mark.frame = frame;
        [_accessory addSubview:_mark];
    }
    [self updateTextColors];
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
    _preview.entities = nil;
    _draftPrefix = label.length;
    _time.text = ExteriaListTimeText(draft.date);
    _check.hidden = YES;
    _forwardIcon.hidden = YES;
    [_thumb showFile:nil cache:_media];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", _title.text, _preview.text];
    [self updateTextColors];
    [self setNeedsLayout];
}

- (void)showTypingText:(NSString *)text {
    if (!text) return;
    _typing.activeColor = ExteriaColorAccent();
    [_typing setStatus:text kind:ExteriaStatusTyping];
    _typing.hidden = NO;
    _preview.hidden = YES;
    _forwardIcon.hidden = YES;
    [_previewColor release];
    _previewColor = [ExteriaColorAccent() retain];
    [_thumb showFile:nil cache:_media];
    [self updateTextColors];
    [self setNeedsLayout];
}

- (void)configureWithPerson:(ExteriaPerson *)person avatars:(ExteriaAvatarCache *)avatars {
    [self setForumLine:NO dialog:nil];
    _avatar.hidden = NO;
    _storyRing.hidden = YES;
    _onlineDot.hidden = person.presence != EXTERIA_PRESENCE_ONLINE;
    _topicIcon.hidden = YES;
    _communityBadge.hidden = YES;
    _communityHit.hidden = YES;
    _avatar.seed = (NSUInteger)(person.userId % 1000003);
    _avatar.initials = person.initials;
    _avatar.deleted = person.deleted;
    _avatar.accent = NO;
    _avatar.showsSymbol = NO;
    [_avatar setPhoto:person.photo cache:avatars];
    _mutualButton.hidden = !person.mutual;
    /* the star of Premium and the marks of Exteria follow the name here as in the contact row of the other style, which lists the same people */
    NSArray *personBadge = nil;
    _title.text = ExteriaNameWithBadges(person.name, ExteriaBadgeDocument(0, person.premium), ExteriaPersonIsDeveloper(person), &personBadge);
    _title.entities = personBadge;
    _preview.text = person.bot ? NSLocalizedString(@"seen.bot", nil) : ExteriaLastSeenText(person.presence, person.seen);
    _preview.entities = nil;
    _preview.hidden = NO;
    _typing.hidden = YES;
    _preview.numberOfLines = 1;
    _forwardIcon.hidden = YES;
    [_thumb showFile:nil cache:nil];
    _time.text = @"";
    _muted.image = nil;
    _check.hidden = YES;
    [_mark removeFromSuperview];
    [_mark release];
    _mark = nil;
    /* someone on line shows it in the accent color, as the contact list of the other style does */
    [_previewColor release];
    _previewColor = [(person.presence == EXTERIA_PRESENCE_ONLINE ? ExteriaColorAccent() : [UIColor grayColor]) retain];
    [self updateTextColors];
    [self setNeedsLayout];
}

- (void)configureWithCall:(ExteriaCallLogEntry *)call avatars:(ExteriaAvatarCache *)avatars {
    [self setForumLine:NO dialog:nil];
    _mutualButton.hidden = YES;
    _avatar.hidden = NO;
    _storyRing.hidden = YES;
    _onlineDot.hidden = YES;
    _topicIcon.hidden = YES;
    _communityBadge.hidden = YES;
    _communityHit.hidden = YES;
    _avatar.seed = (NSUInteger)(call.userId % 1000003);
    _avatar.initials = call.initials;
    _avatar.deleted = call.deleted;
    _avatar.accent = NO;
    _avatar.showsSymbol = NO;
    [_avatar setPhoto:call.photo cache:avatars];
    NSArray *callBadge = nil;
    _title.text = ExteriaNameWithBadges(call.name, 0, ExteriaMarksOfId(call.userId), &callBadge);
    _title.entities = callBadge;
    _preview.text = [call summaryText];
    _preview.entities = nil;
    _preview.hidden = NO;
    _typing.hidden = YES;
    _preview.numberOfLines = 1;
    _forwardIcon.hidden = YES;
    [_thumb showFile:nil cache:nil];
    _time.text = ExteriaListTimeText(call.date);
    _muted.image = nil;
    _check.hidden = YES;
    [_mark removeFromSuperview];
    [_mark release];
    _mark = nil;
    /* a call nobody answered shows its line in red */
    [_previewColor release];
    _previewColor = [(call.missed && !call.outgoing ? ExteriaColorBadgeRed() : [UIColor grayColor]) retain];
    [self updateTextColors];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat rowHeight = _forumLine ? FORUM_ROW_HEIGHT : ROW_HEIGHT;
    _avatar.frame = CGRectMake(SIDE, (rowHeight - AVATAR_SIZE) / 2, AVATAR_SIZE, AVATAR_SIZE);
    _topicIcon.frame = _avatar.frame;
    _storyRing.frame = CGRectInset(_avatar.frame, -RING_OUTSET, -RING_OUTSET);
    _onlineDot.frame = CGRectMake(CGRectGetMaxX(_avatar.frame) - ONLINE_SIDE + 1, CGRectGetMaxY(_avatar.frame) - ONLINE_SIDE + 1, ONLINE_SIDE, ONLINE_SIDE);
    _communityBadge.frame = CGRectMake(CGRectGetMaxX(_avatar.frame) - EXTERIA_COMMUNITY_BADGE_SIDE + 2, CGRectGetMaxY(_avatar.frame) - EXTERIA_COMMUNITY_BADGE_SIDE + 2,
                                       EXTERIA_COMMUNITY_BADGE_SIDE, EXTERIA_COMMUNITY_BADGE_SIDE);
    _communityHit.frame = CGRectInset(_communityBadge.frame, -10, -10);
    CGFloat textX = SIDE * 2 + AVATAR_SIZE;
    CGFloat textWidth = MAX(0, width - textX - 4);
    CGSize titleSize = [_title sizeThatFits:CGSizeMake(textWidth - (_muted.image ? 20 : 0), 20)];
    CGFloat titleY = _forumLine ? FORUM_TITLE_Y : 10;
    _title.frame = CGRectMake(textX, titleY, MIN(titleSize.width, textWidth - (_muted.image ? 20 : 0)), 20);
    _muted.frame = CGRectMake(CGRectGetMaxX(_title.frame) + 4, titleY + (20 - _muted.image.size.height) / 2, _muted.image.size.width, _muted.image.size.height);
    /* a label centers its text in its frame, so a one line preview in the full height of two sat far below the name; it gets
       a frame of its own line, which also puts it nearer the name */
    CGFloat thumbRoom = _thumb.hidden ? 0 : [ExteriaPreviewThumb room];
    /* the arrow of a forward comes before the picture and the words, so they move over by its width */
    CGFloat forwardRoom = _forwardIcon.hidden ? 0 : FORWARD_SIDE + 4;
    thumbRoom += forwardRoom;
    CGSize previewSize = [_preview sizeThatFits:CGSizeMake(textWidth - thumbRoom, 36)];
    BOOL wraps = !_forumLine && previewSize.height > _preview.font.lineHeight * 1.5;
    CGFloat lineHeight = ceil(_preview.font.lineHeight) + 1;
    /* the message of a forum stands inside its plate, between the padding and the chevron */
    CGFloat messageY = FORUM_TOPIC_Y + PLATE_HEIGHT + PLATE_GAP;
    CGFloat previewX = _forumLine ? textX + PLATE_PAD : textX;
    CGFloat chevronRoom = _forumLine ? PLATE_PAD + CHEVRON_SIDE + 4 : 0;
    CGFloat previewY = _forumLine ? messageY + (PLATE_HEIGHT - lineHeight) / 2 : (wraps ? 31 : 35);
    CGFloat lineWidth = MAX(0, textWidth - (previewX - textX) - chevronRoom);
    _preview.frame = CGRectMake(previewX + thumbRoom, previewY, MAX(0, lineWidth - thumbRoom), wraps ? 36 : lineHeight);
    _typing.frame = CGRectMake(previewX, previewY, lineWidth, lineHeight);
    _forwardIcon.frame = CGRectMake(previewX, previewY + (lineHeight - FORWARD_SIDE) / 2, FORWARD_SIDE, FORWARD_SIDE);
    _thumb.frame = CGRectMake(previewX + forwardRoom, previewY + (lineHeight - [ExteriaPreviewThumb side]) / 2, [ExteriaPreviewThumb side], [ExteriaPreviewThumb side]);
    if (_forumLine) {
        CGFloat rowRight = textX + textWidth;
        CGFloat topicHeight = ceil(_forumTopic.font.lineHeight) + 1;
        CGFloat nameX = textX + PLATE_PAD + FORUM_TOPIC_ICON + 4;
        CGFloat nameWidth = MIN([_forumTopic sizeThatFits:CGSizeMake(4096, topicHeight)].width, MAX(0, rowRight - PLATE_PAD - nameX));
        CGFloat plateRight = nameX + nameWidth + PLATE_PAD;
        CGFloat iconY = FORUM_TOPIC_Y + (PLATE_HEIGHT - FORUM_TOPIC_ICON) / 2;
        CGFloat textY = FORUM_TOPIC_Y + (PLATE_HEIGHT - topicHeight) / 2;
        _topicPlate.frame = CGRectMake(textX, FORUM_TOPIC_Y, plateRight - textX, PLATE_HEIGHT);
        _forumTopicIcon.frame = CGRectMake(textX + PLATE_PAD, iconY, FORUM_TOPIC_ICON, FORUM_TOPIC_ICON);
        _forumTopic.frame = CGRectMake(nameX, textY, nameWidth, topicHeight);
        /* the topic before it follows in plain words as far as the row reaches */
        CGFloat secondX = plateRight + 8;
        CGFloat secondNameX = secondX + FORUM_TOPIC_ICON + 4;
        _secondIcon.hidden = _secondTopic.hidden || rowRight - secondNameX < 36;
        _secondIcon.frame = CGRectMake(secondX, iconY, FORUM_TOPIC_ICON, FORUM_TOPIC_ICON);
        _secondTopic.frame = CGRectMake(secondNameX, textY, MAX(0, rowRight - secondNameX), topicHeight);
        _messagePlate.frame = CGRectMake(textX, messageY, textWidth, PLATE_HEIGHT);
        _plateChevron.frame = CGRectMake(rowRight - PLATE_PAD - CHEVRON_SIDE, messageY + (PLATE_HEIGHT - CHEVRON_SIDE) / 2, CHEVRON_SIDE, CHEVRON_SIDE);
    }
    CGFloat timeWidth = ceil(ExteriaStringSize(_time.text, _time.font).width);
    _check.frame = CGRectMake(ACCESSORY_WIDTH - timeWidth - 4 - _check.image.size.width, 4 + (12 - _check.image.size.height) / 2, _check.image.size.width, _check.image.size.height);
}

@end
