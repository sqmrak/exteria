#import "exteria_chat_item.h"
#import "exteria_platform.h"

#import "exteria_person.h"
#import "exteria_service_line.h"
#import "exteria_plural.h"
#import "exteria_reactions_view.h"
#import "exteria_string_drawing.h"
#import "exteria_gift_screen.h"
#import "exteria_chat_settings.h"
#import "exteria_peer_colors.h"
#import "exteria_theme.h"
#import "exteria_emoji_store.h"
#import "exteria_music_player.h"
#import "exteria_developers.h"
#import "exteria_name_badge.h"
#import "exteria_time.h"

#define SIDE_MARGIN 8.0
#define AVATAR_SIDE 34.0
/* the picture and the gap after it */
#define AVATAR_COLUMN 40.0
#define PAD_X 11.0
#define PAD_TOP 6.0
#define PAD_BOTTOM 6.0
#define PICTURE_INSET 3.0
#define TIME_GAP 7.0
/* the plate of a quote: where the text starts, the room right of it, and the room above and below */
#define QUOTE_LEFT 17.0
#define QUOTE_RIGHT 10.0
#define QUOTE_PAD_Y 6.0
/* the room between the words of a bubble and the chips of its reactions */
#define REACTIONS_GAP 5.0
#define CHECK_WIDTH 20.0
#define META_HEIGHT 14.0
/* the eye before a view count, the gap after the count, the row of comments under a post, the round share button beside it and the
   room that button takes from the width of the bubble */
#define DELETED_MARK 12.0
#define VIEWS_EYE 13.0
#define VIEWS_GAP 8.0
#define COMMENTS_HEIGHT 38.0
#define SHARE_SIDE 32.0
#define SHARE_ROOM 44.0
#define COMMENTS_MIN_WIDTH 214.0
#define FILE_HEIGHT 44.0
#define CALL_ICON 26.0
#define STICKER_SIDE 150.0
#define ROUND_SIDE_MAX 220.0
#define PHOTO_WIDTH_MAX 232.0
#define PHOTO_HEIGHT_MAX 320.0
#define PHOTO_WIDTH_MAX_PAD 360.0
#define PHOTO_HEIGHT_MAX_PAD 480.0
#define PHOTO_WIDTH_MIN 120.0
/* a tall picture is shown at least this share of the widest a picture goes, cut to fit, so its bubble and the words under it are not a thin column */
#define PHOTO_WIDTH_MIN_SHARE 0.72
#define SPACING_FAR 8.0
#define SPACING_NEAR 2.0
#define PILL_HEIGHT 24.0
#define TIME_SIZE 11.0
#define NAME_SIZE 13.0
#define MAX_BUBBLE_FRACTION 0.8
/* the widest a bubble gets; the text of a tablet is two points larger and its column wider */
#define BUBBLE_CAP_PHONE 380.0
#define BUBBLE_CAP_PAD 480.0
#define MARKUP_ROW 36.0
#define MARKUP_GAP 4.0
#define MARKUP_MIN_WIDTH 220.0

@implementation ExteriaChatItem

@synthesize kind = _kind;
@synthesize singleEmoji = _singleEmoji;
@synthesize content = _content;
@synthesize message = _message;
@synthesize pillText = _pillText;
@synthesize sharingExpired = _sharingExpired;
@synthesize giftCard = _giftCard;
@synthesize senderName = _senderName;
@synthesize transcript = _transcript;
@synthesize senderTag = _senderTag;
@synthesize senderTagLayout = _senderTagLayout;
@synthesize senderTagOrigin = _senderTagOrigin;
@synthesize senderColor = _senderColor;
@synthesize forwardText = _forwardText;
@synthesize replyTitle = _replyTitle;
@synthesize replyText = _replyText;
@synthesize replyEntities = _replyEntities;
@synthesize replyColor = _replyColor;
@synthesize replyFrame = _replyFrame;
@synthesize replyTitleLayout = _replyTitleLayout;
@synthesize replyTextLayout = _replyTextLayout;
@synthesize timeText = _timeText;
@synthesize viewsText = _viewsText;
@synthesize viewsWidth = _viewsWidth;
@synthesize deletedWidth = _deletedWidth;
@synthesize commentsText = _commentsText;
@synthesize commenterPeople = _commenterPeople;
@synthesize showsShare = _showsShare;
@synthesize albumMessages = _albumMessages;
@synthesize albumFrames = _albumFrames;
@synthesize pollQuestionLayout = _pollQuestionLayout;
@synthesize pollQuestionOrigin = _pollQuestionOrigin;
@synthesize pollKindLayout = _pollKindLayout;
@synthesize pollVoterPeople = _pollVoterPeople;
@synthesize pollFooterOwnRow = _pollFooterOwnRow;
@synthesize pollFooterY = _pollFooterY;
@synthesize pollKindOrigin = _pollKindOrigin;
@synthesize pollAnswerLayouts = _pollAnswerLayouts;
@synthesize pollAnswerFrames = _pollAnswerFrames;
@synthesize pollShowsResults = _pollShowsResults;
@synthesize pollButtonFrame = _pollButtonFrame;
@synthesize pollButtonTitle = _pollButtonTitle;
@synthesize pollFooterText = _pollFooterText;
@synthesize reactionsHidden = _reactionsHidden;
@synthesize commentsFrame = _commentsFrame;
@synthesize shareFrame = _shareFrame;
@synthesize fileTitle = _fileTitle;
@synthesize fileDetail = _fileDetail;
@synthesize joinsPrevious = _joinsPrevious;
@synthesize joinsNext = _joinsNext;
@synthesize read = _read;
@synthesize textLayout = _textLayout;
@synthesize pillLayout = _pillLayout;
@synthesize pillShift = _pillShift;
@synthesize senderLayout = _senderLayout;
@synthesize forwardLayout = _forwardLayout;
@synthesize fileTitleLayout = _fileTitleLayout;
@synthesize fileDetailLayout = _fileDetailLayout;
@synthesize timeSize = _timeSize;
@synthesize height = _height;
@synthesize bubbleFrame = _bubbleFrame;
@synthesize senderPerson = _senderPerson;
@synthesize senderDeveloper = _senderDeveloper;
@synthesize pictureFrame = _pictureFrame;
@synthesize reactionFrame = _reactionFrame;
@synthesize reactionsInside = _reactionsInside;
@synthesize markup = _markup;
@synthesize markupFrame = _markupFrame;
@synthesize markupButtons = _markupButtons;
@synthesize fileFrame = _fileFrame;
@synthesize call = _call;
@synthesize callIncoming = _callIncoming;
@synthesize callFailed = _callFailed;
@synthesize callVideo = _callVideo;
@synthesize senderOrigin = _senderOrigin;
@synthesize forwardOrigin = _forwardOrigin;
@synthesize textOrigin = _textOrigin;
@synthesize timeOrigin = _timeOrigin;

+ (ExteriaChatItem *)pillWithText:(NSString *)text {
    ExteriaChatItem *item = [[[ExteriaChatItem alloc] init] autorelease];
    item->_kind = ExteriaChatItemPill;
    item->_pillText = [text copy];
    return item;
}

static NSString *ExteriaDurationText(int32_t seconds) {
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

NSString *ExteriaFileSizeText(long long bytes) {
    if (bytes <= 0) return @"0 B";
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
}

/* the names of the people in a group take the color each person chose, or the one their id gives them (the classic theme keeps to the app's purple
   family, so no name comes out green or orange there) */
static UIColor *ExteriaSenderColor(ExteriaPerson *person, long long userId) {
    if (!ExteriaThemeIsClassic()) return ExteriaNameColor(person.nameColor, userId, ExteriaThemeIsDark());
    static const CGFloat purples[][3] = {{0.52, 0.30, 0.78}, {0.68, 0.32, 0.74}, {0.42, 0.38, 0.84}, {0.78, 0.36, 0.64},
                                         {0.58, 0.26, 0.62}, {0.38, 0.44, 0.78}, {0.64, 0.44, 0.84}};
    NSUInteger index = (NSUInteger)ExteriaDefaultNameColorId(userId);
    CGFloat boost = ExteriaThemeIsDark() ? 0.12 : 0;
    return [UIColor colorWithRed:MIN(1, purples[index][0] + boost) green:MIN(1, purples[index][1] + boost) blue:MIN(1, purples[index][2] + boost) alpha:1];
}

/* what a gift service message says: who gave what, and the note that came with it */
static NSString *ExteriaGiftText(ExteriaMessage *message, NSString *who) {
    NSString *what = message.giftNumber > 0 ? [NSString stringWithFormat:@"%@ #%d", message.giftTitle, (int)message.giftNumber]
                                           : (message.giftTitle.length ? message.giftTitle : NSLocalizedString(@"gifts.gift", nil));
    NSString *price = message.giftStars > 0 ? [NSString stringWithFormat:@" (%@)", ExteriaStarsText(message.giftStars)] : @"";
    NSString *line = message.outgoing ? [NSString stringWithFormat:NSLocalizedString(@"chat.service.gift.out", nil), what, price]
                                      : [NSString stringWithFormat:NSLocalizedString(@"chat.service.gift.in", nil), who, what, price];
    return message.text.length ? [NSString stringWithFormat:@"%@\n\u201c%@\u201d", line, message.text] : line;
}

/* the two lines over the note of a gift card: who gave it, and what it is */
static void ExteriaGiftCardLines(ExteriaMessage *message, NSString *who, NSString **title, NSString **subtitle) {
    ExteriaStarGift *gift = message.gift;
    *title = message.outgoing ? NSLocalizedString(@"gifts.card.out", nil) : [NSString stringWithFormat:NSLocalizedString(@"gifts.card.from", nil), who];
    if (gift.unique) {
        *subtitle = [NSString stringWithFormat:@"%@ #%d", gift.title, (int)gift.number];
        return;
    }
    NSString *name = gift.title.length ? gift.title : NSLocalizedString(@"gifts.gift", nil);
    *subtitle = gift.stars > 0 ? [NSString stringWithFormat:@"%@ \u00b7 %@", name, ExteriaStarsText(gift.stars)] : name;
}

static NSString *ExteriaServiceText(ExteriaMessage *message, NSDictionary *people) {
    ExteriaPerson *actor = [people objectForKey:[NSNumber numberWithLongLong:message.fromId]];
    ExteriaPerson *target = [people objectForKey:[NSNumber numberWithLongLong:message.targetId]];
    NSString *who = actor.name.length ? actor.name : NSLocalizedString(@"chat.someone", nil);
    if (message.service - 1 == EXTERIA_SERVICE_GIFT) return ExteriaGiftText(message, who);
    if (message.outgoing && message.service - 1 == EXTERIA_SERVICE_SHARING_REQUEST && !(message.serviceValue & 4))
        return NSLocalizedString((message.serviceValue & 2) ? @"chat.sharing.request.out.disable" : @"chat.sharing.request.out.enable", nil);
    if (message.outgoing && message.service - 1 == EXTERIA_SERVICE_SHARING_TOGGLE && !!(message.serviceValue & 1) != !!(message.serviceValue & 2))
        return NSLocalizedString((message.serviceValue & 2) ? @"chat.sharing.changed.out.disable" : @"chat.sharing.changed.out.enable", nil);
    return ExteriaServiceLine((exteria_service_kind)(message.service - 1), actor.name, target.name, message.text, message.serviceValue,
                              message.fromId == message.targetId);
}

BOOL ExteriaMessageIsViewOnce(ExteriaMessage *message) {
    ExteriaMedia *media = message.media;
    if (!media.viewOnce) return NO;
    return media.kind == EXTERIA_PREVIEW_PHOTO || media.kind == EXTERIA_PREVIEW_VIDEO || media.kind == EXTERIA_PREVIEW_VOICE || media.kind == EXTERIA_PREVIEW_VIDEO_MESSAGE;
}

BOOL ExteriaViewOnceExpired(ExteriaMessage *message) {
    if (message.viewOnceOpened) return YES;
    return !message.media.file && !(message.outgoing && message.pendingSend);
}

/* the words of a card of a one-time file: what it is, and whether it can still be opened */
static void ExteriaViewOnceCaptions(ExteriaMessage *message, NSString **title, NSString **detail) {
    NSString *key = @"viewonce.photo";
    switch (message.media.kind) {
    case EXTERIA_PREVIEW_VIDEO: key = @"viewonce.video"; break;
    case EXTERIA_PREVIEW_VOICE: key = @"viewonce.voice"; break;
    case EXTERIA_PREVIEW_VIDEO_MESSAGE: key = @"viewonce.round"; break;
    default: break;
    }
    *title = NSLocalizedString(key, nil);
    BOOL expired = ExteriaViewOnceExpired(message);
    if (message.outgoing) *detail = NSLocalizedString(expired ? @"viewonce.opened" : @"viewonce.sent", nil);
    else *detail = NSLocalizedString(expired ? @"viewonce.expired" : @"viewonce.tap", nil);
}

- (void)setSharingExpired:(BOOL)expired {
    _sharingExpired = expired;
    if (expired && _message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1) {
        [_pillText release];
        _pillText = [NSLocalizedString(@"chat.service.sharing.expired", nil) copy];
    }
}

- (void)captureMessage:(ExteriaMessage *)message {
    _message = [message retain];
    _builtMessageId = message.messageId;
    _builtRandomId = message.randomId;
    _builtState = message.state;
    _builtEdited = message.edited;
    _builtDeleted = message.deletedLocally;
    _builtOnceExpired = ExteriaMessageIsViewOnce(message) && ExteriaViewOnceExpired(message);
    _builtService = message.service;
    _builtServiceValue = message.serviceValue;
    _builtText = [message.text copy];
    _builtReactionKey = [message.reactionKey copy];
    _builtMarkupKey = [message.markupKey copy];
    _builtPollKey = [message.pollKey copy];
}

static BOOL ExteriaSameString(NSString *a, NSString *b) {
    return a == b || [a isEqualToString:b];
}

- (BOOL)reflectsMessage:(ExteriaMessage *)message {
    return _message && _message.replyTo == message.replyTo && _message.sendReplyTo == message.sendReplyTo &&
           _message.replyPeerKind == message.replyPeerKind && _message.replyPeerId == message.replyPeerId && ExteriaSameString(_message.replyQuote, message.replyQuote) &&
           _message.senderKey == message.senderKey && ExteriaSameString(_message.senderRank, message.senderRank) &&
           _builtMessageId == message.messageId && _builtRandomId == message.randomId &&
           _builtState == message.state && _builtEdited == message.edited && _builtDeleted == message.deletedLocally && _builtService == message.service && _builtServiceValue == message.serviceValue &&
           _builtOnceExpired == (ExteriaMessageIsViewOnce(message) && ExteriaViewOnceExpired(message)) &&
           ExteriaSameString(_builtText, message.text) && ExteriaSameString(_builtReactionKey, message.reactionKey) &&
           ExteriaSameString(_builtMarkupKey, message.markupKey) && ExteriaSameString(_builtPollKey, message.pollKey);
}

static NSString *ExteriaSenderTag(ExteriaMessage *message, ExteriaPerson *person, NSString *role) {
    NSString *tag = message.senderRank.length ? message.senderRank : role;
    if (person.bot) {
        NSString *bot = NSLocalizedString(@"chat.status.bot", nil);
        return tag.length ? [NSString stringWithFormat:@"%@ \u00b7 %@", tag, bot] : bot;
    }
    return tag;
}

/* the color of the tag after a name goes by the role in the group and nothing else: the owner is purple and an administrator green, and every other tag (a title
   the owners gave, a bot) keeps the quiet grey; a title on an administrator is still green, since the role is what it says */
static UIColor *ExteriaSenderTagColor(NSString *role) {
    if ([role isEqualToString:NSLocalizedString(@"chat.role.owner", nil)]) return [UIColor colorWithRed:0.60f green:0.34f blue:0.88f alpha:1];
    if ([role isEqualToString:NSLocalizedString(@"chat.role.admin", nil)]) return [UIColor colorWithRed:0.16f green:0.68f blue:0.40f alpha:1];
    return ExteriaColorSecondary();
}

- (BOOL)reflectsPeople:(NSDictionary *)people role:(NSString *)role {
    if (!_avatarColumn) return YES;
    ExteriaPerson *sender = [people objectForKey:[NSNumber numberWithLongLong:_message.senderKey]];
    return ExteriaSameString(_senderTag, ExteriaSenderTag(_message, sender, role)) &&
           ExteriaSameString(_senderPerson.name, sender.name) && ExteriaSameString(_senderPerson.initials, sender.initials) &&
           _senderBadge == ExteriaBadgeDocument(ExteriaChatFlagGet(ExteriaChatFlagShowMessageEmojiStatus) ? sender.emojiStatus : 0, sender.premium) && _senderDeveloper == ExteriaPersonIsDeveloper(sender) &&
           ExteriaSameString(_senderPerson.photo.key, sender.photo.key);
}

- (BOOL)isSameRowAs:(ExteriaChatItem *)other {
    if (!_message || !other->_message) return !_message && !other->_message && ExteriaSameString(_pillText, other->_pillText);
    if (_builtRandomId || other->_builtRandomId) return _builtRandomId == other->_builtRandomId;
    return _builtMessageId == other->_builtMessageId;
}

- (BOOL)displaysSameAs:(ExteriaChatItem *)other {
    if (self == other) {
        return _joinsPrevious == _shownJoinsPrevious && _joinsNext == _shownJoinsNext && _read == _shownRead;
    }
    return !_message && !other->_message && ExteriaSameString(_pillText, other->_pillText);
}

- (BOOL)hasDifferentReactionsFrom:(ExteriaChatItem *)other {
    return other && _message && other->_message && !ExteriaSameString(_builtReactionKey, other->_builtReactionKey);
}

- (void)markDisplayed {
    _shownJoinsPrevious = _joinsPrevious;
    _shownJoinsNext = _joinsNext;
    _shownRead = _read;
}

/* 79 as "79", 1234 as "1.2K", 1500000 as "1.5M" */
static NSString *ExteriaShortCount(int32_t count) {
    if (count < 1000 || ExteriaChatFlagGet(ExteriaChatFlagExactNumbers)) return [NSString stringWithFormat:@"%d", (int)count];
    if (count < 1000000) return count < 10000 ? [NSString stringWithFormat:@"%d.%dK", (int)(count / 1000), (int)(count % 1000 / 100)] : [NSString stringWithFormat:@"%dK", (int)(count / 1000)];
    return [NSString stringWithFormat:@"%d.%dM", (int)(count / 1000000), (int)(count % 1000000 / 100000)];
}

/* "10 comments" with the plural form the language wants */
static NSString *ExteriaCommentsLine(int32_t count) {
    if (count <= 0) return NSLocalizedString(@"channel.comments.none", nil);
    return [NSString stringWithFormat:NSLocalizedString([@"channel.comments." stringByAppendingString:ExteriaPluralForm(count)], nil), (int)count];
}

/* what only a channel post has: the view count, the comments row and the button that shares it */
- (void)captureChannelPost:(ExteriaMessage *)message people:(NSDictionary *)people {
    if (!message.post || message.messageId <= 0) return;
    _showsShare = !ExteriaChatFlagGet(ExteriaChatFlagHideShare);
    if (message.views > 0) {
        _viewsText = [ExteriaShortCount(message.views) copy];
        _viewsWidth = ceil(ExteriaStringSize(_viewsText, ExteriaTimeFont()).width) + VIEWS_EYE + 3 + VIEWS_GAP;
    }
    if (message.hasComments) {
        _commentsText = [ExteriaCommentsLine(message.comments) copy];
        NSMutableArray *commenters = [NSMutableArray array];
        for (NSNumber *id in message.commenters) {
            ExteriaPerson *person = [people objectForKey:id];
            if (person) [commenters addObject:person];
        }
        _commenterPeople = [commenters copy];
    }
}

+ (ExteriaChatItem *)itemForMessage:(ExteriaMessage *)message group:(BOOL)group people:(NSDictionary *)people {
    return [self itemForMessage:message group:group people:people role:nil];
}

NSString *ExteriaForwardName(ExteriaMessage *message, NSDictionary *people) {
    if (message.forwardName.length) return message.forwardName;
    ExteriaPerson *origin = message.forwardKey ? [people objectForKey:[NSNumber numberWithLongLong:message.forwardKey]] : nil;
    return origin.name.length ? origin.name : @"";
}

/* how a call is named: who made it, how it ended, and whether it had video */
static NSString *ExteriaCallTitle(ExteriaMessage *message, BOOL *incoming, BOOL *failed) {
    BOOL missed = message.callOutcome == EXTERIA_OUTCOME_MISSED;
    BOOL busy = message.callOutcome == EXTERIA_OUTCOME_BUSY;
    BOOL video = message.callVideo;
    *incoming = !message.outgoing;
    *failed = *incoming && (missed || busy);
    NSString *kind = message.outgoing ? (missed ? @"cancelled" : @"out") : (missed ? @"missed" : (busy ? @"declined" : @"in"));
    NSString *key = [NSString stringWithFormat:video ? @"chat.call.video.%@" : @"chat.call.%@", kind];
    return NSLocalizedString(key, nil);
}

/* 20 seconds as "20 sec.", 65 as "1 min. 5 sec.", 3700 as "1 h. 1 min." */
static NSString *ExteriaCallLength(int32_t seconds) {
    if (seconds < 60) return [NSString stringWithFormat:NSLocalizedString(@"chat.call.sec", nil), (int)seconds];
    if (seconds < 3600) {
        NSString *minutes = [NSString stringWithFormat:NSLocalizedString(@"chat.call.min", nil), (int)(seconds / 60)];
        return seconds % 60 ? [NSString stringWithFormat:@"%@ %@", minutes, [NSString stringWithFormat:NSLocalizedString(@"chat.call.sec", nil), (int)(seconds % 60)]] : minutes;
    }
    NSString *hours = [NSString stringWithFormat:NSLocalizedString(@"chat.call.hour", nil), (int)(seconds / 3600)];
    return seconds % 3600 >= 60 ? [NSString stringWithFormat:@"%@ %@", hours, [NSString stringWithFormat:NSLocalizedString(@"chat.call.min", nil), (int)(seconds % 3600 / 60)]] : hours;
}

static NSString *ExteriaAlbumKey(NSArray *messages) {
    NSMutableString *key = [NSMutableString string];
    for (ExteriaMessage *message in messages) [key appendFormat:@"%d:%lld;", message.messageId, message.randomId];
    return key;
}

+ (ExteriaChatItem *)itemForAlbum:(NSArray *)messages group:(BOOL)group people:(NSDictionary *)people role:(NSString *)role {
    ExteriaMessage *primary = [messages objectAtIndex:0];
    for (ExteriaMessage *message in messages) if (message.text.length) { primary = message; break; }
    ExteriaChatItem *item = [self itemForMessage:primary group:group people:people role:role];
    if (messages.count < 2) return item;
    item->_albumMessages = [messages copy];
    item->_builtAlbumKey = [ExteriaAlbumKey(messages) copy];
    item->_content = ExteriaChatItemContentPicture;
    return item;
}

- (BOOL)reflectsAlbum:(NSArray *)messages {
    if (!_albumMessages) return messages.count < 2;
    return messages.count == _albumMessages.count && ExteriaSameString(_builtAlbumKey, ExteriaAlbumKey(messages));
}

- (ExteriaMessage *)albumMessageAtPoint:(CGPoint)point {
    for (NSUInteger i = 0; i < _albumFrames.count; ++i) {
        if (CGRectContainsPoint([[_albumFrames objectAtIndex:i] CGRectValue], point)) return [_albumMessages objectAtIndex:i];
    }
    return nil;
}

+ (ExteriaChatItem *)itemForMessage:(ExteriaMessage *)message group:(BOOL)group people:(NSDictionary *)people role:(NSString *)role {
    BOOL isCall = message.service - 1 == EXTERIA_SERVICE_CALL;
    if (message.service && !isCall) {
        ExteriaChatItem *pill = [ExteriaChatItem pillWithText:ExteriaServiceText(message, people)];
        [pill captureMessage:message];
        pill.sharingExpired = (message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1 && (message.serviceValue & 4));
        if (message.service - 1 == EXTERIA_SERVICE_GIFT && message.gift) {
            ExteriaPerson *actor = [people objectForKey:[NSNumber numberWithLongLong:message.fromId]];
            NSString *who = actor.name.length ? actor.name : NSLocalizedString(@"chat.someone", nil);
            ExteriaGiftCardLines(message, who, &pill->_giftTitle, &pill->_giftSubtitle);
            [pill->_giftTitle retain];
            [pill->_giftSubtitle retain];
        }
        return pill;
    }
    ExteriaChatItem *item = [[[ExteriaChatItem alloc] init] autorelease];
    [item captureMessage:message];
    /* a pencil takes less of the bubble than the word */
    NSString *editedMark = ExteriaChatFlagGet(ExteriaChatFlagEditedIcon) ? @"\u270E" : NSLocalizedString(@"chat.edited", nil);
    NSString *clock = message.edited ? [NSString stringWithFormat:@"%@ %@", editedMark, ExteriaClockText(message.date)] : ExteriaClockText(message.date);
    /* a message the other side deleted and the phone kept has a trash can before its time */
    item->_timeText = [clock copy];
    if (message.deletedLocally) item->_deletedWidth = DELETED_MARK + 3;
    [item captureChannelPost:message people:people];
    ExteriaMedia *media = message.media;
    BOOL sticker = media.kind == EXTERIA_PREVIEW_STICKER && (media.file || media.previewFile);
    BOOL once = ExteriaMessageIsViewOnce(message);
    BOOL round = media.kind == EXTERIA_PREVIEW_VIDEO_MESSAGE && !message.text.length && !once;
    item->_kind = sticker ? ExteriaChatItemSticker : (round ? ExteriaChatItemRound : ExteriaChatItemBubble);
    if ((media.kind == EXTERIA_PREVIEW_NONE || media.kind == EXTERIA_PREVIEW_TEXT) &&
        !message.entities.count && !message.forwarded && !message.post && !message.markup && message.text.length <= 32 && ExteriaChatLargeEmoji()) {
        uint16_t units[32];
        size_t entry = 0;
        [message.text getCharacters:units range:NSMakeRange(0, message.text.length)];
        if (exteria_emoji_single(units, message.text.length, &entry)) {
            item->_kind = ExteriaChatItemEmoji;
            item->_singleEmoji = entry;
        }
    }
    /* anonymous admin messages use the group identity stored at key zero */
    if (group && !message.outgoing && !message.post) {
        ExteriaPerson *person = [people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
        item->_avatarColumn = YES;
        item->_senderPerson = [person retain];
        if (person.name.length) {
            item->_senderName = [person.name copy];
            item->_senderBadge = ExteriaBadgeDocument(ExteriaChatFlagGet(ExteriaChatFlagShowMessageEmojiStatus) ? person.emojiStatus : 0, person.premium);
            item->_senderDeveloper = ExteriaPersonIsDeveloper(person);
            item->_senderTag = [ExteriaSenderTag(message, person, role) copy];
            item->_senderTagColor = [ExteriaSenderTagColor(role) retain];
            item->_senderColor = [ExteriaSenderColor(person, llabs(message.senderKey)) retain];
        }
    }
    if (message.forwarded) {
        NSString *origin = ExteriaForwardName(message, people);
        NSString *line = origin.length ? [NSString stringWithFormat:NSLocalizedString(@"chat.forwarded.from", nil), origin] : NSLocalizedString(@"chat.forwarded", nil);
        if (message.forwardDate > 0 && ExteriaChatFlagGet(ExteriaChatFlagForwardDate)) line = [NSString stringWithFormat:@"%@ \u00b7 %@", line, ExteriaDayText(message.forwardDate)];
        item->_forwardText = [line copy];
    }
    if (isCall) {
        BOOL incoming = NO, failed = NO;
        item->_call = YES;
        item->_content = ExteriaChatItemContentFile;
        item->_fileTitle = [ExteriaCallTitle(message, &incoming, &failed) copy];
        item->_callIncoming = incoming;
        item->_callFailed = failed;
        item->_callVideo = message.callVideo;
        item->_fileDetail = [(message.serviceValue > 0 ? [NSString stringWithFormat:@"%@, %@", ExteriaClockText(message.date), ExteriaCallLength(message.serviceValue)]
                                                       : ExteriaClockText(message.date)) copy];
        return item;
    }
    /* what stands in the bubble above the text */
    BOOL picture = exteria_media_uses_picture(media.kind, media.file != nil, media.previewFile != nil,
                                            message.pendingSend && message.pendingSend->preview);
    if (once) {
        NSString *title = nil, *detail = nil;
        ExteriaViewOnceCaptions(message, &title, &detail);
        item->_content = ExteriaChatItemContentFile;
        item->_fileTitle = [title copy];
        item->_fileDetail = [detail copy];
    } else switch (media.kind) {
    case EXTERIA_PREVIEW_PHOTO:
        if (picture) item->_content = ExteriaChatItemContentPicture;
        else { item->_content = ExteriaChatItemContentFile; item->_fileTitle = [NSLocalizedString(@"preview.photo", nil) copy]; }
        break;
    case EXTERIA_PREVIEW_VIDEO:
    case EXTERIA_PREVIEW_VIDEO_MESSAGE:
    case EXTERIA_PREVIEW_GIF:
        if (picture) item->_content = ExteriaChatItemContentPicture;
        else {
            item->_content = ExteriaChatItemContentFile;
            item->_fileTitle = [(media.kind == EXTERIA_PREVIEW_GIF ? NSLocalizedString(@"preview.gif", nil) : NSLocalizedString(@"preview.video", nil)) copy];
            item->_fileDetail = [(media.duration ? ExteriaDurationText(media.duration) : @"") copy];
        }
        break;
    case EXTERIA_PREVIEW_VOICE:
        item->_content = ExteriaChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"preview.voice", nil) copy];
        item->_fileDetail = [ExteriaDurationText(media.duration) copy];
        break;
    case EXTERIA_PREVIEW_AUDIO:
        item->_content = ExteriaChatItemContentFile;
        item->_fileTitle = [ExteriaTrackTitle(media) copy];
        item->_fileDetail = [(ExteriaTrackPerformer(media).length ? [NSString stringWithFormat:@"%@, %@", ExteriaTrackPerformer(media), ExteriaDurationText(media.duration)]
                                                                 : ExteriaDurationText(media.duration)) copy];
        break;
    case EXTERIA_PREVIEW_FILE:
        item->_content = ExteriaChatItemContentFile;
        item->_fileTitle = [(media.name.length ? media.name : NSLocalizedString(@"preview.file", nil)) copy];
        item->_fileDetail = [ExteriaFileSizeText(media.size) copy];
        break;
    case EXTERIA_PREVIEW_LOCATION:
        item->_content = media.location.valid ? ExteriaChatItemContentPicture : ExteriaChatItemContentFile;
        if (!media.location.valid) item->_fileTitle = [NSLocalizedString(@"map.invalid", nil) copy];
        break;
    case EXTERIA_PREVIEW_CONTACT:
        item->_content = ExteriaChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"preview.contact", nil) copy];
        break;
    case EXTERIA_PREVIEW_POLL:
        /* a poll the reader could not use keeps the plain line */
        if (message.poll) {
            item->_content = ExteriaChatItemContentPoll;
            NSMutableArray *voters = [NSMutableArray array];
            for (NSNumber *voter in message.poll.recentVoters) {
                ExteriaPerson *person = [people objectForKey:voter];
                if (person) [voters addObject:person];
            }
            item->_pollVoterPeople = [voters copy];
        } else {
            item->_content = ExteriaChatItemContentFile;
            item->_fileTitle = [NSLocalizedString(@"preview.poll", nil) copy];
        }
        break;
    case EXTERIA_PREVIEW_STICKER:
        if (!sticker) { item->_content = ExteriaChatItemContentFile; item->_fileTitle = [NSLocalizedString(@"preview.sticker", nil) copy]; }
        break;
    case EXTERIA_PREVIEW_OTHER:
        item->_content = ExteriaChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"chat.unsupported", nil) copy];
        break;
    case EXTERIA_PREVIEW_NONE:
    case EXTERIA_PREVIEW_TEXT:
    case EXTERIA_PREVIEW_SERVICE:
        break;
    }
    return item;
}

- (void)dealloc {
    [_message release];
    [_builtText release];
    [_builtReactionKey release];
    [_builtMarkupKey release];
    [_markup release];
    [_markupButtons release];
    [_pillText release];
    [_giftTitle release];
    [_giftSubtitle release];
    [_giftCard release];
    [_senderName release];
    [_transcript release];
    [_senderTag release];
    [_senderTagColor release];
    [_senderTagLayout release];
    [_senderPerson release];
    [_senderColor release];
    [_forwardText release];
    [_replyTitle release];
    [_replyText release];
    [_replyEntities release];
    [_replyColor release];
    [_replyTitleLayout release];
    [_replyTextLayout release];
    [_timeText release];
    [_viewsText release];
    [_commentsText release];
    [_commenterPeople release];
    [_pollQuestionLayout release];
    [_pollKindLayout release];
    [_pollVoterPeople release];
    [_pollAnswerLayouts release];
    [_pollAnswerFrames release];
    [_pollButtonTitle release];
    [_pollFooterText release];
    [_builtPollKey release];
    [_albumMessages release];
    [_albumFrames release];
    [_builtAlbumKey release];
    [_fileTitle release];
    [_fileDetail release];
    [_textLayout release];
    [_pillLayout release];
    [_senderLayout release];
    [_forwardLayout release];
    [_fileTitleLayout release];
    [_fileDetailLayout release];
    [super dealloc];
}

- (BOOL)hasAvatarColumn {
    return _avatarColumn;
}

/* the picture stands under the last message of a run by one person, the others of the run leave its place empty */
- (BOOL)showsAvatar {
    return _avatarColumn && !_joinsNext;
}

- (CGFloat)incomingLeft {
    return _avatarColumn ? SIDE_MARGIN + AVATAR_COLUMN : SIDE_MARGIN;
}

- (void)invalidateLayout {
    _layoutWidth = 0;
}

static UIFont *ExteriaTimeFont(void) { return ExteriaFontRegular(TIME_SIZE); }

/* the picture's size at the width the bubble allows, in the proportions the file reports */
/* how many pictures stand in each row of a collage of this many; one picture in a row is wider than tall, two or three are square */
static const int ExteriaAlbumRows[11][4] = {{0}, {0}, {2}, {1, 2}, {2, 2}, {2, 3}, {3, 3}, {1, 3, 3}, {2, 3, 3}, {3, 3, 3}, {1, 3, 3, 3}};
#define ALBUM_GAP 2.0
#define ALBUM_WIDTH_MAX 260.0

static CGFloat ExteriaAlbumFill(NSMutableArray *frames, CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    [frames addObject:[NSValue valueWithCGRect:CGRectMake(x, y, width, height)]];
    return height;
}

/* a column or a row of pictures split by their proportions; each takes a share of the length that is in step with
   how much room its picture needs, so the pictures of a collage keep close to their own shape and are not all cut
   to squares. ratios are width over height */
static void ExteriaAlbumStack(NSMutableArray *frames, NSArray *ratios, NSUInteger first, NSUInteger count, CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    CGFloat total = 0;
    for (NSUInteger i = 0; i < count; ++i) total += 1 / [[ratios objectAtIndex:first + i] floatValue];
    CGFloat room = height - (CGFloat)(count - 1) * ALBUM_GAP, used = 0;
    for (NSUInteger i = 0; i < count; ++i) {
        CGFloat part = i + 1 == count ? room - used : round(room * (1 / [[ratios objectAtIndex:first + i] floatValue]) / total);
        ExteriaAlbumFill(frames, x, y + used + (CGFloat)i * ALBUM_GAP, width, part);
        used += part;
    }
}

/* the rows of a collage in a width, as rects from the top left, and the height they take */
static CGFloat ExteriaAlbumLayout(NSArray *ratios, CGFloat width, NSMutableArray *frames) {
    NSUInteger count = ratios.count;
    if (count < 2 || count > 10) return 0;
    CGFloat limit = floor(width * 1.0);
    CGFloat r0 = [[ratios objectAtIndex:0] floatValue], r1 = [[ratios objectAtIndex:1] floatValue];
    BOOL wide0 = r0 > 1.2, tall0 = r0 < 0.8;
    if (count == 2) {
        CGFloat average = (r0 + r1) / 2;
        if (r0 > 1.2 && r1 > 1.2 && average > 1.4) {
            /* two wide pictures stand one over the other */
            CGFloat h0 = round(MIN(width / r0, (limit - ALBUM_GAP) / 2)), h1 = round(MIN(width / r1, (limit - ALBUM_GAP) / 2));
            ExteriaAlbumFill(frames, 0, 0, width, h0);
            ExteriaAlbumFill(frames, 0, h0 + ALBUM_GAP, width, h1);
            return h0 + ALBUM_GAP + h1;
        }
        CGFloat room = width - ALBUM_GAP;
        CGFloat second = MAX(round(0.4 * room), round(room / r0 / (1 / r0 + 1 / r1)));
        CGFloat firstWidth = room - second;
        CGFloat height = MIN(limit, round(MIN(firstWidth / r0, second / r1)));
        ExteriaAlbumFill(frames, 0, 0, firstWidth, height);
        ExteriaAlbumFill(frames, firstWidth + ALBUM_GAP, 0, second, height);
        return height;
    }
    if (count == 3) {
        CGFloat r2 = [[ratios objectAtIndex:2] floatValue];
        if (tall0) {
            /* a tall one on the left, the other two stacked on its right */
            CGFloat left = round(MIN(limit * r0, 0.6 * width));
            CGFloat height = MIN(limit, round(left / r0));
            ExteriaAlbumFill(frames, 0, 0, left, height);
            ExteriaAlbumStack(frames, ratios, 1, 2, left + ALBUM_GAP, 0, width - left - ALBUM_GAP, height);
            return height;
        }
        CGFloat top = round(MIN(width / r0, limit * 0.55));
        ExteriaAlbumFill(frames, 0, 0, width, top);
        CGFloat half = floor((width - ALBUM_GAP) / 2);
        CGFloat row = MIN(round(MIN(half / r1, half / r2)), limit - top - ALBUM_GAP);
        ExteriaAlbumFill(frames, 0, top + ALBUM_GAP, half, row);
        ExteriaAlbumFill(frames, half + ALBUM_GAP, top + ALBUM_GAP, width - half - ALBUM_GAP, row);
        return top + ALBUM_GAP + row;
    }
    if (count == 4) {
        if (wide0) {
            /* a wide one on top, the other three in a row under it */
            CGFloat top = round(MIN(width / r0, limit * 0.5));
            ExteriaAlbumFill(frames, 0, 0, width, top);
            CGFloat each = floor((width - 2 * ALBUM_GAP) / 3), row = 0;
            for (NSUInteger i = 1; i < 4; ++i) {
                CGFloat h = round(each / [[ratios objectAtIndex:i] floatValue]);
                row = row ? MIN(row, h) : h;
            }
            row = MIN(row, limit - top - ALBUM_GAP);
            for (NSUInteger i = 0; i < 3; ++i) {
                CGFloat w = i == 2 ? width - 2 * (each + ALBUM_GAP) : each;
                ExteriaAlbumFill(frames, (CGFloat)i * (each + ALBUM_GAP), top + ALBUM_GAP, w, row);
            }
            return top + ALBUM_GAP + row;
        }
        CGFloat left = round(MIN(limit * r0, 0.55 * width));
        CGFloat height = MIN(limit, round(left / r0));
        ExteriaAlbumFill(frames, 0, 0, left, height);
        ExteriaAlbumStack(frames, ratios, 1, 3, left + ALBUM_GAP, 0, width - left - ALBUM_GAP, height);
        return height;
    }
    CGFloat y = 0;
    NSUInteger at = 0;
    for (int row = 0; row < 4 && ExteriaAlbumRows[count][row]; ++row) {
        int columns = ExteriaAlbumRows[count][row];
        CGFloat side = floor((width - (CGFloat)(columns - 1) * ALBUM_GAP) / (CGFloat)columns);
        CGFloat height = columns == 1 ? floor(width * 0.66) : side;
        for (int column = 0; column < columns; ++column, ++at) {
            [frames addObject:[NSValue valueWithCGRect:CGRectMake((side + ALBUM_GAP) * (CGFloat)column, y, columns == 1 ? width : side, height)]];
        }
        y += height + ALBUM_GAP;
    }
    return y - ALBUM_GAP;
}

static CGSize ExteriaPictureSize(ExteriaMedia *media, CGFloat widthMax) {
    CGFloat w = media.width > 0 ? media.width : 4, h = media.height > 0 ? media.height : 3;
    CGFloat limit = MIN(widthMax, ExteriaIsPad() ? PHOTO_WIDTH_MAX_PAD : PHOTO_WIDTH_MAX);
    CGFloat heightMax = ExteriaIsPad() ? PHOTO_HEIGHT_MAX_PAD : PHOTO_HEIGHT_MAX;
    CGFloat scale = MIN(limit / w, heightMax / h);
    CGFloat width = MAX(MIN(w * scale, limit), MIN(MAX(PHOTO_WIDTH_MIN, limit * PHOTO_WIDTH_MIN_SHARE), limit));
    CGFloat height = MIN(h * scale, heightMax);
    if (width > w * scale) height = MIN(height * width / (w * scale), heightMax);
    return CGSizeMake(ceil(width), ceil(height));
}

- (void)layoutGiftCardForWidth:(CGFloat)width {
    CGFloat cardWidth = floor(MIN(width - 2 * SIDE_MARGIN, MAX(200.0, MIN(260.0, width * 0.66))));
    [_giftCard release];
    _giftCard = [[ExteriaGiftCardLayout layoutForGift:_message.gift title:_giftTitle subtitle:_giftSubtitle note:_message.text width:cardWidth] retain];
    _bubbleFrame = CGRectMake(floor((width - cardWidth) / 2), 6, cardWidth, _giftCard.size.height);
    _height = _giftCard.size.height + 12;
}

- (void)layoutPillForWidth:(CGFloat)width {
    if (_giftTitle && _message.gift) {
        [self layoutGiftCardForWidth:width];
        return;
    }
    [_pillLayout release];
    /* on the linen the dark capsule with white text reads as a stain, so a classic date is plain grey text with a shadow */
    UIColor *pillColor = ExteriaThemeIsClassic() ? (ExteriaThemeIsDark() ? [UIColor colorWithWhite:0.78 alpha:1] : [UIColor colorWithWhite:0.33 alpha:1])
                                                 : [UIColor whiteColor];
    _pillLayout = [[ExteriaTextLayout layoutForText:_pillText entities:nil font:ExteriaFontMedium(12) color:pillColor
                                          linkColor:pillColor width:width - 2 * SIDE_MARGIN - 24 maxLines:2 flush:0.5] retain];
    _pillShift = floor((width - 2 * SIDE_MARGIN - 24 - _pillLayout.size.width) / 2);
    CGFloat pillWidth = ceil(_pillLayout.size.width) + 22;
    CGFloat pillHeight = MAX(PILL_HEIGHT, ceil(_pillLayout.size.height) + 10);
    _bubbleFrame = CGRectMake(floor((width - pillWidth) / 2), 6, pillWidth, pillHeight);
    _height = pillHeight + 10;
    if (_message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1 && !_message.outgoing && !_sharingExpired && _message.messageId > 0)
        _height += 45;
}

- (NSArray *)shownReactions {
    return _reactionsHidden ? nil : _message.reactions;
}

- (void)layoutStickerForWidth:(CGFloat)width {
    ExteriaMedia *media = _message.media;
    CGFloat w = _kind != ExteriaChatItemEmoji && media.width > 0 ? media.width : 512;
    CGFloat h = _kind != ExteriaChatItemEmoji && media.height > 0 ? media.height : 512;
    /* only a sticker follows the size setting; the large emoji keep theirs */
    CGFloat side = _kind == ExteriaChatItemSticker ? STICKER_SIDE * ExteriaChatStickerScale() / 100.0 : STICKER_SIDE;
    CGFloat scale = MIN(side, width - 2 * SIDE_MARGIN) / MAX(w, h);
    CGSize picture = CGSizeMake(MAX(60, floor(w * scale)), MAX(60, floor(h * scale)));
    CGFloat top = _joinsPrevious ? SPACING_NEAR : SPACING_FAR;
    CGFloat x = _message.outgoing ? width - SIDE_MARGIN - picture.width : [self incomingLeft];
    _bubbleFrame = CGRectMake(x, top, picture.width, picture.height);
    _pictureFrame = CGRectMake(0, 0, picture.width, picture.height);
    CGFloat metaWidth = ExteriaStringSize(_timeText, ExteriaTimeFont()).width + _deletedWidth + (_message.outgoing ? CHECK_WIDTH : 0);
    _timeSize = CGSizeMake(ceil(metaWidth) + 10, 18);
    _timeOrigin = CGPointMake(picture.width - _timeSize.width - 4, picture.height - _timeSize.height - 4);
    _height = top + picture.height + 1;
}

/* the time sits below the circle, clear of the playback ring */
- (void)layoutRoundForWidth:(CGFloat)width {
    CGFloat side = MIN(ROUND_SIDE_MAX, floor(width * 0.62));
    CGFloat top = _joinsPrevious ? SPACING_NEAR : SPACING_FAR;
    CGFloat x = _message.outgoing ? width - SIDE_MARGIN - side : [self incomingLeft];
    _bubbleFrame = CGRectMake(x, top, side, side);
    _pictureFrame = CGRectMake(0, 0, side, side);
    CGFloat metaWidth = ExteriaStringSize(_timeText, ExteriaTimeFont()).width + _deletedWidth + (_message.outgoing ? CHECK_WIDTH : 0);
    _timeSize = CGSizeMake(ceil(metaWidth) + 10, 18);
    _timeOrigin = CGPointMake(side - _timeSize.width, side + 2);
    _height = top + side + _timeSize.height + 3;
}

#pragma mark poll

#define POLL_MARK 20.0
#define POLL_PERCENT_WIDTH 38.0
#define POLL_BAR_HEIGHT 4.0
#define POLL_BUTTON_HEIGHT 36.0
#define POLL_ROW_PAD 8.0

CGFloat ExteriaPollVotersWidth(NSUInteger count) {
    return count ? EXTERIA_POLL_VOTER_SIDE + (CGFloat)(count - 1) * EXTERIA_POLL_VOTER_STEP + 6 : 0;
}

/* "1 vote", "5 votes", or the line for a poll nobody has answered */
static NSString *ExteriaPollVotesLine(ExteriaPoll *poll) {
    if (poll.totalVoters <= 0) return NSLocalizedString(poll.quiz ? @"poll.answers.none" : @"poll.votes.none", nil);
    NSString *prefix = poll.quiz ? @"poll.answers." : @"poll.votes.";
    return [NSString stringWithFormat:NSLocalizedString([prefix stringByAppendingString:ExteriaPluralForm(poll.totalVoters)], nil), (int)poll.totalVoters];
}

static NSString *ExteriaPollKindLine(ExteriaPoll *poll) {
    if (poll.closed) return NSLocalizedString(@"poll.final", nil);
    if (poll.quiz) return NSLocalizedString(poll.publicVoters ? @"poll.quiz" : @"poll.quiz.anonymous", nil);
    if (poll.multiple) return NSLocalizedString(poll.publicVoters ? @"poll.public.multiple" : @"poll.anonymous.multiple", nil);
    return NSLocalizedString(poll.publicVoters ? @"poll.public" : @"poll.anonymous", nil);
}

/* the poll from y down: the question, what kind it is, an answer per row and the button; returns the y under them;
   the rows are as wide as the bubble may be, since an answer reads better with room */
- (CGFloat)layoutPollAt:(CGFloat)y width:(CGFloat)width color:(UIColor *)textColor contentWidth:(CGFloat *)contentWidth metaWidth:(CGFloat)metaWidth {
    ExteriaPoll *poll = _message.poll;
    CGFloat rowWidth = MAX(150, width);
    [_pollQuestionLayout release];
    _pollQuestionLayout = [[ExteriaTextLayout layoutForText:poll.question entities:nil font:ExteriaFontSemibold(16) color:textColor linkColor:textColor
                                                      width:rowWidth maxLines:0 flush:0] retain];
    _pollQuestionOrigin = CGPointMake(PAD_X, y);
    y += _pollQuestionLayout.size.height + 3;
    /* the line wraps, since "public poll, choose one or more" is wider than a narrow bubble */
    [_pollKindLayout release];
    _pollKindLayout = [[ExteriaTextLayout layoutForText:ExteriaPollKindLine(poll) entities:nil font:ExteriaFontRegular(12) color:ExteriaColorBubbleMeta(_message.outgoing)
                                              linkColor:ExteriaColorBubbleMeta(_message.outgoing) width:rowWidth maxLines:0 flush:0] retain];
    _pollKindOrigin = CGPointMake(PAD_X, y);
    y += _pollKindLayout.size.height + 4;
    _pollShowsResults = [poll showsResultsEarly:ExteriaChatFlagGet(ExteriaChatFlagPollResultsFirst)];
    [_pollAnswerLayouts release];
    [_pollAnswerFrames release];
    _pollAnswerLayouts = [[NSMutableArray alloc] initWithCapacity:poll.answers.count];
    _pollAnswerFrames = [[NSMutableArray alloc] initWithCapacity:poll.answers.count];
    CGFloat textWidth = rowWidth - POLL_MARK - 8 - (_pollShowsResults ? POLL_PERCENT_WIDTH : 0);
    for (ExteriaPollAnswer *answer in poll.answers) {
        ExteriaTextLayout *layout = [ExteriaTextLayout layoutForText:answer.text entities:nil font:ExteriaFontRegular(15) color:textColor linkColor:textColor
                                                               width:MAX(40, textWidth) maxLines:3 flush:0];
        CGFloat height = MAX(POLL_MARK, layout.size.height) + (_pollShowsResults ? POLL_BAR_HEIGHT + 4 : 0) + 2 * POLL_ROW_PAD;
        [_pollAnswerLayouts addObject:layout];
        [_pollAnswerFrames addObject:[NSValue valueWithCGRect:CGRectMake(PAD_X, y, rowWidth, height)]];
        y += height;
    }
    [_pollButtonTitle release];
    _pollButtonTitle = nil;
    _pollButtonFrame = CGRectZero;
    BOOL voted = poll.voted;
    if (!poll.closed && poll.multiple && !voted && poll.picked.count > 0) _pollButtonTitle = [NSLocalizedString(@"poll.vote", nil) copy];
    else if (!poll.closed && voted && !poll.quiz && !poll.revotingDisabled) _pollButtonTitle = [NSLocalizedString(@"poll.retract", nil) copy];
    if (_pollButtonTitle) {
        _pollButtonFrame = CGRectMake(PAD_X, y + 2, rowWidth, POLL_BUTTON_HEIGHT);
        y += POLL_BUTTON_HEIGHT + 4;
    }
    [_pollFooterText release];
    _pollFooterText = [ExteriaPollVotesLine(poll) copy];
    CGFloat footerWidth = ceil(ExteriaStringSize(_pollFooterText, ExteriaFontRegular(12)).width);
    if (_pollVoterPeople.count) footerWidth += ExteriaPollVotersWidth(_pollVoterPeople.count);
    /* the count shares the row of the time when both fit, and the bubble is as wide as the rows */
    *contentWidth = MAX(*contentWidth, MAX(rowWidth, footerWidth + TIME_GAP + metaWidth));
    return y + 2;
}

- (NSUInteger)pollAnswerAtPoint:(CGPoint)point {
    for (NSUInteger i = 0; i < _pollAnswerFrames.count; ++i) {
        if (CGRectContainsPoint([[_pollAnswerFrames objectAtIndex:i] CGRectValue], point)) return i;
    }
    return NSNotFound;
}

- (void)setReplyTitle:(NSString *)title text:(NSString *)text color:(UIColor *)color {
    [_replyTitle release];
    _replyTitle = [title copy];
    [_replyText release];
    _replyText = [text copy];
    [_replyColor release];
    _replyColor = [color retain];
    [self invalidateLayout];
}

- (void)layoutReplyAt:(CGPoint)origin width:(CGFloat)width {
    [_replyTitleLayout release];
    [_replyTextLayout release];
    _replyTitleLayout = nil;
    _replyTextLayout = nil;
    _replyFrame = CGRectZero;
    if (!_replyTitle.length) return;
    /* the quote is a plate: a rounded bar inset 6 points from its left edge, then the name and a line of the message, with 6 points above and below */
    CGFloat room = MAX(1, width - QUOTE_LEFT - QUOTE_RIGHT);
    _replyTitleLayout = [[ExteriaTextLayout layoutForName:_replyTitle font:ExteriaFontSemibold((CGFloat)ExteriaChatTextSize() - 1) color:_replyColor width:room] retain];
    UIColor *ink = ExteriaColorBubbleText(_message.outgoing);
    _replyTextLayout = [[ExteriaTextLayout layoutForText:_replyText entities:_replyEntities font:ExteriaFontRegular((CGFloat)ExteriaChatTextSize() - 1) color:ink linkColor:ink width:room maxLines:1 flush:0] retain];
    CGFloat height = 2 * QUOTE_PAD_Y + _replyTitleLayout.size.height + 2 + _replyTextLayout.size.height;
    CGFloat used = MAX(_replyTitleLayout.size.width, _replyTextLayout.size.width) + QUOTE_LEFT + QUOTE_RIGHT;
    _replyFrame = CGRectMake(origin.x, origin.y, MIN(width, MAX(64, used)), height);
}

/* width over height of each picture of the collage, as the files report them; a picture that does not say is taken as square */
- (NSArray *)albumRatios {
    NSMutableArray *ratios = [NSMutableArray arrayWithCapacity:_albumMessages.count];
    for (ExteriaMessage *message in _albumMessages) {
        ExteriaMedia *media = message.media;
        CGFloat ratio = media.width > 0 && media.height > 0 ? (CGFloat)media.width / (CGFloat)media.height : 1;
        [ratios addObject:[NSNumber numberWithFloat:(float)MAX(0.4, MIN(2.5, ratio))]];
    }
    return ratios;
}

- (void)layoutBubbleForWidth:(CGFloat)width {
    ExteriaMedia *media = _message.media;
    BOOL outgoing = _message.outgoing;
    CGFloat maxBubble = floor(MIN((width - (_avatarColumn && !outgoing ? AVATAR_COLUMN : 0) - (_showsShare ? SHARE_ROOM : 0)) * MAX_BUBBLE_FRACTION, ExteriaIsPad() ? BUBBLE_CAP_PAD : BUBBLE_CAP_PHONE));
    CGFloat metaWidth = ceil(ExteriaStringSize(_timeText, ExteriaTimeFont()).width) + (outgoing ? CHECK_WIDTH : 0) + _viewsWidth + _deletedWidth;
    /* a voice message has no words of its own, so what the server heard in it takes their place */
    BOOL ownText = _message.text.length > 0;
    NSString *bodyText = ownText ? _message.text : _transcript;
    BOOL hasText = bodyText.length > 0;
    BOOL picture = _content == ExteriaChatItemContentPicture;
    BOOL file = _content == ExteriaChatItemContentFile;
    BOOL poll = _content == ExteriaChatItemContentPoll;
    CGSize pictureSize = CGSizeZero;
    if (picture && _albumMessages.count > 1) {
        CGFloat albumWidth = MIN(maxBubble - 2 * PICTURE_INSET, ExteriaIsPad() ? PHOTO_WIDTH_MAX_PAD : ALBUM_WIDTH_MAX);
        pictureSize = CGSizeMake(albumWidth, ExteriaAlbumLayout([self albumRatios], albumWidth, [NSMutableArray array]));
    } else if (picture) {
        pictureSize = ExteriaPictureSize(media, maxBubble - 2 * PICTURE_INSET);
    }
    CGFloat textMax = (picture ? pictureSize.width + 2 * PICTURE_INSET : maxBubble) - 2 * PAD_X;
    CGFloat contentWidth = 0;
    CGFloat y = PAD_TOP;
    UIColor *textColor = ExteriaColorBubbleText(outgoing);
    UIColor *linkColor = ExteriaColorBubbleLink(outgoing);

    [_textLayout release];
    _textLayout = hasText ? [[ExteriaTextLayout layoutForText:bodyText entities:ownText ? _message.entities : nil font:ExteriaFontRegular((CGFloat)ExteriaChatTextSize())
                                                        color:textColor linkColor:linkColor width:MAX(40, textMax) maxLines:0 flush:0] retain] : nil;
    _textLayout.spoilersRevealed = _message.spoilersRevealed;

    /* a run of messages from one person names them once, on the first bubble, and the picture stands under the last */
    [_senderLayout release];
    _senderLayout = nil;
    [_senderTagLayout release];
    _senderTagLayout = nil;
    if (_senderName.length && !_joinsPrevious) {
        /* the name takes the whole line it needs, and the tag after it takes what is left, cut to fit or left out when there is hardly any: a long nick that was
           cut to make room for a tag lost its end to dots */
        NSArray *badge = nil;
        NSString *named = ExteriaNameWithBadges(_senderName, _senderBadge, _senderDeveloper, &badge);
        _senderLayout = [[ExteriaTextLayout layoutForName:named entities:badge font:ExteriaFontSemibold(NAME_SIZE) color:_senderColor
                                                    width:MAX(1, textMax)] retain];
        CGFloat room = textMax - _senderLayout.size.width - 6;
        CGFloat tagWidth = 0;
        if (_senderTag.length && room >= 36) {
            UIColor *tagColor = _senderTagColor ? _senderTagColor : ExteriaColorSecondary();
            _senderTagLayout = [[ExteriaTextLayout layoutForText:_senderTag entities:nil font:ExteriaFontSemibold(11)
                color:tagColor linkColor:tagColor width:MIN(room, textMax * 0.45) maxLines:1 flush:0] retain];
            tagWidth = _senderTagLayout.size.width;
        }
        _senderOrigin = CGPointMake(PAD_X, y);
        _senderTagOrigin = CGPointMake(PAD_X + _senderLayout.size.width + 6, y + 1);
        contentWidth = MAX(contentWidth, _senderLayout.size.width + (tagWidth > 0 ? tagWidth + 6 : 0));
        y += 17;
    }
    if (_forwardText.length) {
        UIColor *forwardColor = ExteriaColorBubbleLink(outgoing);
        [_forwardLayout release];
        /* the line may take a second row, so a long name does not push the date of the original off its end as three dots */
        _forwardLayout = [[ExteriaTextLayout layoutForText:_forwardText entities:nil font:ExteriaFontRegular(12) color:forwardColor
                                                 linkColor:forwardColor width:textMax maxLines:2 flush:0 dropsUndrawable:YES] retain];
        _forwardOrigin = CGPointMake(PAD_X, y);
        contentWidth = MAX(contentWidth, _forwardLayout.size.width);
        y += 16 + (_forwardLayout.lineCount > 1 ? ceil(_forwardLayout.size.height / _forwardLayout.lineCount) * (_forwardLayout.lineCount - 1) : 0);
    }
    [self layoutReplyAt:CGPointMake(PAD_X, y) width:textMax];
    if (!CGRectIsEmpty(_replyFrame)) {
        contentWidth = MAX(contentWidth, _replyFrame.size.width);
        y += _replyFrame.size.height + 5;
    }
    CGFloat pictureTop = 0;
    if (picture) {
        /* a picture runs edge to edge, so the lines above it need the text padding and it needs none */
        pictureTop = y == PAD_TOP ? PICTURE_INSET : y;
        y = pictureTop + pictureSize.height + (hasText ? 5 : PICTURE_INSET);
        contentWidth = MAX(contentWidth, pictureSize.width + 2 * PICTURE_INSET - 2 * PAD_X);
    } else if (file) {
        [_fileTitleLayout release];
        _fileTitleLayout = [[ExteriaTextLayout layoutForText:_fileTitle entities:nil font:ExteriaFontMedium(15) color:textColor
                                                   linkColor:textColor width:MAX(40, textMax - 54) maxLines:1 flush:0] retain];
        [_fileDetailLayout release];
        _fileDetailLayout = nil;
        if (_message.media.kind == EXTERIA_PREVIEW_AUDIO) {
            UIColor *detailColor = ExteriaColorBubbleMeta(outgoing);
            _fileDetailLayout = [[ExteriaTextLayout layoutForText:_fileDetail entities:nil font:ExteriaFontRegular(13) color:detailColor
                linkColor:detailColor width:MAX(40, textMax - 54) maxLines:1 flush:0] retain];
        }
        CGFloat titleWidth = ceil(_fileTitleLayout.size.width);
        CGFloat detailWidth = _fileDetailLayout ? ceil(_fileDetailLayout.size.width) : ceil(ExteriaStringSize(_fileDetail, ExteriaFontRegular(13)).width);
        if (_message.media.kind == EXTERIA_PREVIEW_FILE) {
            NSString *progress = [NSString stringWithFormat:@"%@ / %@", _fileDetail, _fileDetail];
            detailWidth = MAX(detailWidth, ceil(ExteriaStringSize(progress, ExteriaFontRegular(13)).width));
        }
        CGFloat rowWidth = 44 + 10 + MAX(titleWidth, detailWidth);
        /* a call has no button in front: the arrow stands before the second line and the phone at the end of the row */
        if (_call) rowWidth = MAX(titleWidth, 18 + detailWidth) + 14 + CALL_ICON;
        /* a voice note needs room for its bars, and the bars are the same hundred for a note of any length, so the bubble is the same width too: the width the
           longest notes had, which the shorter ones used to fall short of */
        if (_message.media.kind == EXTERIA_PREVIEW_VOICE) rowWidth = 54 + 150;
        _fileFrame = CGRectMake(PAD_X, y + 1, MIN(textMax, MAX(rowWidth, 150)), FILE_HEIGHT);
        contentWidth = MAX(contentWidth, _fileFrame.size.width);
        y += FILE_HEIGHT + 4;
    }
    BOOL timeOverPicture = picture && !hasText;
    /* the chips of the reactions stand in the bubble, between the words and the time; a picture with the time over it has no such row, and keeps them under it */
    BOOL chipsInside = [self shownReactions].count && !timeOverPicture;
    _reactionsInside = chipsInside;
    _pollFooterOwnRow = NO;
    if (poll) {
        y = [self layoutPollAt:y width:textMax color:textColor contentWidth:&contentWidth metaWidth:metaWidth];
        /* the chips take the row the count of votes shares with the time, so the count gets a row above them */
        if (chipsInside) {
            _pollFooterOwnRow = YES;
            _pollFooterY = y;
            y += META_HEIGHT;
        }
    }
    if (hasText) {
        _textOrigin = CGPointMake(PAD_X, y);
        contentWidth = MAX(contentWidth, _textLayout.size.width);
        y += _textLayout.size.height;
        if (chipsInside) {
            /* the time is placed with the chips below */
        } else if (_textLayout.lastLineWidth + TIME_GAP + metaWidth <= MAX(textMax, contentWidth)) {
            /* the time fits beside the last line, so the bubble does not grow a row for it */
            contentWidth = MAX(contentWidth, _textLayout.lastLineWidth + TIME_GAP + metaWidth);
        } else {
            y += META_HEIGHT - 3;
            contentWidth = MAX(contentWidth, metaWidth);
        }
    } else if (!timeOverPicture && !_call && !chipsInside) {
        /* a bubble of a file alone keeps a row of its own for the time */
        y += META_HEIGHT - 2;
        contentWidth = MAX(contentWidth, metaWidth);
    }
    _reactionFrame = CGRectZero;
    if (chipsInside) {
        CGFloat used = 0, lastRow = 0;
        CGFloat chipsHeight = ExteriaReactionsMetrics([self shownReactions], textMax, YES, &used, &lastRow);
        y += REACTIONS_GAP;
        _reactionFrame = CGRectMake(PAD_X, y, used, chipsHeight);
        y += chipsHeight;
        contentWidth = MAX(contentWidth, used);
        if (lastRow + TIME_GAP + metaWidth <= MAX(textMax, contentWidth)) {
            /* the time fits right of the last row of chips, so the bubble does not grow a row for it */
            contentWidth = MAX(contentWidth, lastRow + TIME_GAP + metaWidth);
        } else {
            y += META_HEIGHT - 3;
            contentWidth = MAX(contentWidth, metaWidth);
        }
    }
    CGFloat bubbleWidth = picture ? pictureSize.width + 2 * PICTURE_INSET : contentWidth + 2 * PAD_X;
    if (picture && contentWidth + 2 * PAD_X > bubbleWidth) bubbleWidth = contentWidth + 2 * PAD_X;
    bubbleWidth = MAX(bubbleWidth, 56);
    if (!CGRectIsEmpty(_replyFrame)) _replyFrame.size.width = bubbleWidth - 2 * PAD_X;
    if (_commentsText.length) bubbleWidth = MAX(bubbleWidth, MIN(COMMENTS_MIN_WIDTH, maxBubble));
    CGFloat bubbleHeight = timeOverPicture ? y : y + PAD_BOTTOM;
    /* the comments row takes the foot of the bubble, under the line with the time */
    CGFloat commentsRoom = _commentsText.length ? COMMENTS_HEIGHT : 0;
    bubbleHeight += commentsRoom;
    CGFloat top = _joinsPrevious ? SPACING_NEAR : SPACING_FAR;
    CGFloat x = outgoing ? width - SIDE_MARGIN - bubbleWidth : [self incomingLeft];
    _bubbleFrame = CGRectMake(x, top, bubbleWidth, bubbleHeight);
    if (picture) _pictureFrame = CGRectMake(PICTURE_INSET, pictureTop, bubbleWidth - 2 * PICTURE_INSET, pictureSize.height);
    [_albumFrames release];
    _albumFrames = nil;
    if (picture && _albumMessages.count > 1) {
        NSMutableArray *frames = [NSMutableArray array];
        ExteriaAlbumLayout([self albumRatios], _pictureFrame.size.width, frames);
        for (NSUInteger i = 0; i < frames.count; ++i) {
            CGRect frame = [[frames objectAtIndex:i] CGRectValue];
            [frames replaceObjectAtIndex:i withObject:[NSValue valueWithCGRect:CGRectOffset(frame, _pictureFrame.origin.x, _pictureFrame.origin.y)]];
        }
        _albumFrames = [frames retain];
    }
    _timeSize = CGSizeMake(metaWidth, META_HEIGHT);
    if (timeOverPicture) {
        _timeSize = CGSizeMake(metaWidth + 10, 18);
        _timeOrigin = CGPointMake(bubbleWidth - PICTURE_INSET - _timeSize.width - 5, bubbleHeight - commentsRoom - PICTURE_INSET - _timeSize.height - 5);
    } else {
        _timeOrigin = CGPointMake(bubbleWidth - PAD_X - metaWidth, bubbleHeight - commentsRoom - PAD_BOTTOM - META_HEIGHT + 1);
    }
    _commentsFrame = _commentsText.length ? CGRectMake(0, bubbleHeight - COMMENTS_HEIGHT, bubbleWidth, COMMENTS_HEIGHT) : CGRectZero;
    _shareFrame = _showsShare ? CGRectMake(bubbleWidth + 6, bubbleHeight - SHARE_SIDE, SHARE_SIDE, SHARE_SIDE) : CGRectZero;
    _height = top + bubbleHeight;
}

/* the buttons of an inline keyboard stand under the bubble, as wide as the bubble or as a short one's minimum, on the bubble's side */
- (void)layoutMarkupForWidth:(CGFloat)width {
    [_markup release];
    _markup = nil;
    [_markupButtons release];
    _markupButtons = nil;
    _markupFrame = CGRectZero;
    ExteriaMarkup *markup = _message.markup;
    if (!markup || markup.kind != EXTERIA_MARKUP_INLINE || _kind == ExteriaChatItemPill) return;
    CGFloat available = width - 2 * SIDE_MARGIN - (_avatarColumn && !_message.outgoing ? AVATAR_COLUMN : 0);
    CGFloat keyboardWidth = MIN(available, MAX(_bubbleFrame.size.width, MARKUP_MIN_WIDTH));
    CGFloat height = 0;
    NSData *frames = [markup framesForWidth:keyboardWidth rowHeight:MARKUP_ROW gap:MARKUP_GAP height:&height];
    if (!frames.length) return;
    CGFloat x = _message.outgoing ? width - SIDE_MARGIN - keyboardWidth : [self incomingLeft];
    _markup = [markup retain];
    _markupButtons = [frames retain];
    _markupFrame = CGRectMake(x, _height + MARKUP_GAP, keyboardWidth, height);
    _height += height + MARKUP_GAP;
}

- (void)layoutForWidth:(CGFloat)width {
    if (width == _layoutWidth) return;
    _layoutWidth = width;
    _reactionsInside = NO;
    _reactionFrame = CGRectZero;
    switch (_kind) {
    case ExteriaChatItemPill: [self layoutPillForWidth:width]; break;
    case ExteriaChatItemSticker: [self layoutStickerForWidth:width]; break;
    case ExteriaChatItemEmoji: [self layoutStickerForWidth:width]; break;
    case ExteriaChatItemRound: [self layoutRoundForWidth:width]; break;
    case ExteriaChatItemBubble: [self layoutBubbleForWidth:width]; break;
    }
    if (_kind != ExteriaChatItemBubble && _kind != ExteriaChatItemPill) {
        [self layoutReplyAt:CGPointZero width:MAX(100, _bubbleFrame.size.width)];
        if (!CGRectIsEmpty(_replyFrame)) {
            CGFloat extra = _replyFrame.size.height + 5;
            _bubbleFrame.origin.y += extra;
            _replyFrame.origin.y = -extra;
            if (_message.outgoing) _replyFrame.origin.x = _bubbleFrame.size.width - _replyFrame.size.width;
            _height += extra;
        }
    }
    if (_reactionsInside) {
        _reactionFrame = CGRectOffset(_reactionFrame, _bubbleFrame.origin.x, _bubbleFrame.origin.y);
    } else if ([self shownReactions].count) {
        /* the chips hang from the bubble: they start at its left edge for a message of somebody else, which in a
           group is right of the picture column, and end at its right edge for ours */
        CGFloat edge = 8;
        CGFloat x, chipsWidth;
        if (_message.outgoing) {
            chipsWidth = MIN(CGRectGetMaxX(_bubbleFrame) - edge, 380);
            x = CGRectGetMaxX(_bubbleFrame) - chipsWidth;
        } else {
            x = _bubbleFrame.origin.x;
            chipsWidth = MIN(width - edge - x, 380);
        }
        CGFloat chipsHeight = ExteriaReactionsHeight([self shownReactions], chipsWidth, YES);
        _reactionFrame = CGRectMake(x, _height + 4, chipsWidth, chipsHeight);
        _height += chipsHeight + 4;
    }
    if (_kind != ExteriaChatItemBubble && _kind != ExteriaChatItemPill) {
        if (_commentsText.length) {
            CGFloat available = _message.outgoing ? CGRectGetMaxX(_bubbleFrame) - SIDE_MARGIN : width - SIDE_MARGIN - _bubbleFrame.origin.x;
            CGFloat rowWidth = MIN(available, MAX(_bubbleFrame.size.width, COMMENTS_MIN_WIDTH));
            CGFloat rowX = _message.outgoing ? _bubbleFrame.size.width - rowWidth : 0;
            _commentsFrame = CGRectMake(rowX, _height + 4 - _bubbleFrame.origin.y, rowWidth, COMMENTS_HEIGHT);
            _height += COMMENTS_HEIGHT + 4;
        }
        if (_showsShare) _shareFrame = CGRectMake(_bubbleFrame.size.width + 6, _bubbleFrame.size.height - SHARE_SIDE, SHARE_SIDE, SHARE_SIDE);
    }
    [self layoutMarkupForWidth:width];
}

@end
