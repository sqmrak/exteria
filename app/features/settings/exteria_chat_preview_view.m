#import "exteria_chat_preview_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_settings.h"
#import "exteria_peer_colors.h"
#import "exteria_emoji_label.h"
#import "exteria_string_drawing.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_wallpaper.h"
#import "exteria_reactions_view.h"
#include "exteria_reactions.h"

#define PREVIEW_RADIUS 22.0
#define PREVIEW_PAD 12.0
#define BUBBLE_PAD_X 12.0
#define BUBBLE_PAD_Y 8.0
#define BUBBLE_GAP 6.0
#define BUBBLE_MAX_FRACTION 0.82
#define META_SIZE 11.0
#define CHECK_WIDTH 16.0
#define WALLPAPER_HEIGHT 420.0
#define PREVIEW_ITEMS 2
#define STICKER_SIDE 150.0
#define QUOTE_BAR 3.0
#define QUOTE_FONT 15.0
#define QUOTE_PAD 6.0
/* where the text of a quote starts and the room right of it, as in the chat */
#define QUOTE_LEFT 17.0
#define QUOTE_RIGHT 10.0

typedef struct { BOOL outgoing; BOOL sticker; NSString *key; NSString *time; NSString *quoteName; NSString *quoteKey; NSInteger quoteColor; } ExteriaPreviewLine;

/* the talk of the Exteria screen: the person sends a sticker, and the other one answers it with a quote that carries the nick of the author, in the color of the
   name */
static const ExteriaPreviewLine ExteriaPreviewExteria[PREVIEW_ITEMS] = {
    {YES, YES, nil, @"10:47", nil, nil, 0},
    {NO, NO, @"chat.preview.line2", @"10:48", @"sqmrak", @"preview.sticker", 5},
};

/* the talk of the settings of chats: somebody asks, with a quote of an earlier message of the person in the plain link color, and the person answers with a sticker */
static const ExteriaPreviewLine ExteriaPreviewSettings[PREVIEW_ITEMS] = {
    {NO, NO, @"chat.preview.question", @"10:46", @"sqmrak", @"chat.preview.quote", -1},
    {YES, YES, nil, @"10:47", nil, nil, 0},
};

static const ExteriaPreviewLine ExteriaPreviewQuickReaction[PREVIEW_ITEMS] = {
    {NO, NO, @"chatset.quickreaction.preview.in", @"10:46", @"sqmrak", @"chatset.quickreaction.preview.quote", -1},
    {YES, YES, nil, @"10:47", nil, nil, 0},
};

/* one item of the preview: a bubble with its box, the gradient of the classic style, the quote of the message it
   answers, the words */
@interface ExteriaPreviewBubble : NSObject {
@public
    BOOL outgoing;
    BOOL sticker;
    NSInteger quoteColorId;
    UIView *box;
    CAGradientLayer *fill;
    UIView *quotePlate;
    UIView *quoteBar;
    UILabel *quoteName;
    UILabel *quoteText;
    ExteriaEmojiLabel *text;
    UIImageView *picture;
    UIView *capsule;
    UILabel *time;
    UIImageView *checks;
}
@end

@implementation ExteriaPreviewBubble
- (void)dealloc {
    [box release];
    [fill release];
    [quotePlate release];
    [quoteBar release];
    [quoteName release];
    [quoteText release];
    [picture release];
    [capsule release];
    [checks release];
    [super dealloc];
}
@end

@interface ExteriaChatPreviewView () {
    const ExteriaPreviewLine *_lines;
    NSString *_stickerName;
    UIImageView *_wallpaper;
    CGFloat _wallpaperWidth;
    NSMutableArray *_bubbles;
    CGFloat _reportedHeight;
    void (^_heightHandler)(void);
    ExteriaReactionsView *_quickReaction;
}
@end

@implementation ExteriaChatPreviewView

@synthesize heightHandler = _heightHandler;

- (id)initWithFrame:(CGRect)frame {
    return [self initWithTalk:ExteriaChatPreviewTalkSettings];
}

- (id)initWithTalk:(ExteriaChatPreviewTalk)talk {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _lines = talk == ExteriaChatPreviewTalkExteria ? ExteriaPreviewExteria : (talk == ExteriaChatPreviewTalkQuickReaction ? ExteriaPreviewQuickReaction : ExteriaPreviewSettings);
    _stickerName = talk == ExteriaChatPreviewTalkExteria ? @"preview_fox" : (talk == ExteriaChatPreviewTalkQuickReaction ? @"preview_quick_fox" : @"preview_sticker");
    self.layer.cornerRadius = ExteriaThemeIsClassic() ? 0 : PREVIEW_RADIUS;
    self.layer.masksToBounds = YES;
    /* the rounded clip is drawn once and kept while the preview scrolls with its table; a change of a slider draws it again */
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.accessibilityElementsHidden = YES;
    _wallpaper = [[UIImageView alloc] init];
    ExteriaApplyWallpaperStyle(_wallpaper, ExteriaThemeIsClassic(), ExteriaThemeIsDark());
    [self addSubview:_wallpaper];

    _bubbles = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < PREVIEW_ITEMS; ++i) {
        ExteriaPreviewBubble *bubble = [[[ExteriaPreviewBubble alloc] init] autorelease];
        bubble->outgoing = _lines[i].outgoing;
        bubble->sticker = _lines[i].sticker;
        bubble->quoteColorId = _lines[i].quoteColor;
        bubble->time = [[[UILabel alloc] init] autorelease];
        bubble->time.backgroundColor = [UIColor clearColor];
        bubble->time.font = ExteriaFontRegular(META_SIZE);
        bubble->time.text = _lines[i].time;
        if (bubble->outgoing) bubble->checks = [[UIImageView alloc] init];
        /* a message that answers another shows what it answers: a plate with the bar, the nick and a line */
        UIView *host = nil;
        if (_lines[i].quoteName) {
            bubble->quotePlate = [[UIView alloc] init];
            bubble->quotePlate.layer.cornerRadius = 10;
            bubble->quotePlate.layer.masksToBounds = YES;
            bubble->quoteBar = [[UIView alloc] init];
            bubble->quoteName = [[UILabel alloc] init];
            bubble->quoteName.backgroundColor = [UIColor clearColor];
            bubble->quoteName.font = ExteriaFontSemibold(QUOTE_FONT);
            bubble->quoteName.text = _lines[i].quoteName;
            bubble->quoteText = [[UILabel alloc] init];
            bubble->quoteText.backgroundColor = [UIColor clearColor];
            bubble->quoteText.font = ExteriaFontRegular(QUOTE_FONT);
            bubble->quoteText.text = NSLocalizedString(_lines[i].quoteKey, nil);
            [bubble->quotePlate addSubview:bubble->quoteBar];
            [bubble->quotePlate addSubview:bubble->quoteName];
            [bubble->quotePlate addSubview:bubble->quoteText];
        }
        if (bubble->sticker) {
            bubble->picture = [[UIImageView alloc] initWithImage:[UIImage imageNamed:_stickerName]];
            bubble->picture.contentMode = UIViewContentModeScaleAspectFit;
            [self addSubview:bubble->picture];
            bubble->capsule = [[UIView alloc] init];
            bubble->capsule.layer.masksToBounds = YES;
            [self addSubview:bubble->capsule];
            [bubble->capsule addSubview:bubble->time];
            if (bubble->checks) [bubble->capsule addSubview:bubble->checks];
            host = self;
        } else {
            bubble->box = [[UIView alloc] init];
            [self addSubview:bubble->box];
            /* the classic bubble is a gradient with an outline, as the old Messages drew it */
            bubble->fill = [[CAGradientLayer alloc] init];
            bubble->fill.hidden = !ExteriaThemeIsClassic();
            [bubble->box.layer insertSublayer:bubble->fill atIndex:0];
            bubble->text = [[[ExteriaEmojiLabel alloc] init] autorelease];
            bubble->text.numberOfLines = 0;
            bubble->text.text = NSLocalizedString(_lines[i].key, nil);
            [bubble->box addSubview:bubble->text];
            [bubble->box addSubview:bubble->time];
            if (bubble->checks) [bubble->box addSubview:bubble->checks];
            host = bubble->box;
        }
        if (bubble->quotePlate) [host addSubview:bubble->quotePlate];
        [_bubbles addObject:bubble];
    }

    if (talk == ExteriaChatPreviewTalkQuickReaction) {
        ExteriaPreviewBubble *bubble = [_bubbles objectAtIndex:0];
        _quickReaction = [[ExteriaReactionsView alloc] init];
        _quickReaction.inBubble = YES;
        _quickReaction.userInteractionEnabled = NO;
        [bubble->box addSubview:_quickReaction];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged) name:ExteriaChatSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wallpaperChanged) name:ExteriaWallpaperDidChangeNotification object:nil];
    [self applyColors];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyWallpaper) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reportHeight) object:nil];
    [_wallpaper release];
    [_bubbles release];
    [_heightHandler release];
    [_quickReaction release];
    [super dealloc];
}

- (void)setQuickReaction:(NSString *)value display:(NSString *)display {
    if (!_quickReaction) return;
    exteria_reaction row;
    memset(&row, 0, sizeof(row));
    row.chosen = 1; row.count = 1;
    row.document_id = exteria_quick_reaction_document(value.UTF8String);
    if (row.document_id) {
        row.kind = EXTERIA_REACTION_CUSTOM;
        if (display.length) [ExteriaReaction rememberCustomTexts:[NSDictionary dictionaryWithObject:display forKey:[NSNumber numberWithLongLong:row.document_id]]];
    } else {
        row.kind = EXTERIA_REACTION_EMOJI;
        snprintf(row.emoji, sizeof(row.emoji), "%s", value.UTF8String ?: "");
    }
    [_quickReaction setReactions:[NSArray arrayWithObject:[ExteriaReaction reactionWithRow:&row]] counts:YES];
    [self setNeedsLayout];
}

/* the colors of the quote follow the switches of the screen: the color of the author's name or the plain link color, and a solid plate or none */
- (void)applyQuoteForBubble:(ExteriaPreviewBubble *)bubble bubbleColor:(UIColor *)bubbleColor {
    if (!bubble->quotePlate) return;
    BOOL out = bubble->outgoing;
    /* a quote with no color of its own is the plain one of the settings of chats: the link color, with no plate */
    BOOL plain = bubble->quoteColorId < 0;
    UIColor *tint = !plain && ExteriaChatFlagGet(ExteriaChatFlagReplyColors) && !ExteriaThemeIsClassic()
        ? ExteriaNameColor(bubble->quoteColorId, 0, ExteriaThemeIsDark()) : ExteriaColorBubbleLink(out);
    bubble->quotePlate.backgroundColor = !plain && ExteriaChatFlagGet(ExteriaChatFlagReplyBackground) ? ExteriaMixedColor(bubbleColor, tint, 0.3) : [UIColor clearColor];
    bubble->quoteBar.backgroundColor = tint;
    bubble->quoteName.textColor = tint;
    bubble->quoteText.textColor = bubble->sticker ? ExteriaColorBubbleText(out) : ExteriaColorBubbleText(out);
}

- (void)applyColors {
    for (ExteriaPreviewBubble *bubble in _bubbles) {
        BOOL out = bubble->outgoing;
        if (bubble->sticker) {
            /* the time of a sticker stands on a dark capsule, white as in the chat */
            bubble->capsule.backgroundColor = ExteriaColorBubbleCapsule();
            bubble->time.textColor = [UIColor whiteColor];
            bubble->checks.image = ExteriaSymbolImage(ExteriaSymbolCheckDouble, 14, [UIColor whiteColor]);
            [self applyQuoteForBubble:bubble bubbleColor:out ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn()];
            continue;
        }
        if (ExteriaThemeIsClassic()) {
            UIColor *top, *bottom, *outline;
            ExteriaClassicBubbleColors(out, &top, &bottom, &outline);
            bubble->fill.colors = [NSArray arrayWithObjects:(id)top.CGColor, (id)bottom.CGColor, nil];
            bubble->box.backgroundColor = [UIColor clearColor];
            bubble->box.layer.borderColor = outline.CGColor;
            bubble->box.layer.borderWidth = 1;
        } else {
            bubble->box.backgroundColor = out ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn();
        }
        bubble->text.textColor = ExteriaColorBubbleText(out);
        bubble->time.textColor = ExteriaColorBubbleMeta(out);
        [self applyQuoteForBubble:bubble bubbleColor:out ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn()];
        bubble->checks.image = ExteriaSymbolImage(ExteriaSymbolCheckDouble, 14, ExteriaColorBubbleMeta(out));
    }
}

/* the intensity and the dimming change at every step of a slider, and the picture is made once for the steps that come together */
- (void)wallpaperChanged {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyWallpaper) object:nil];
    [self performSelector:@selector(applyWallpaper) withObject:nil afterDelay:0];
}

/* the picture is made for the width of the preview and a height that the text size never outgrows, so a slider that changes the height does not make it again */
- (void)applyWallpaper {
    CGFloat width = self.bounds.size.width > 1 ? self.bounds.size.width : 320;
    _wallpaperWidth = width;
    ExteriaApplyChatWallpaperSized(_wallpaper, ExteriaThemeIsDark(), CGSizeMake(width, WALLPAPER_HEIGHT));
    [self setNeedsLayout];
}

- (void)settingsChanged {
    [self applyColors];
    [self setNeedsLayout];
}

/* the items are stacked from the top; with apply they are also put in place; the time sits beside the last line of
   the words when the line leaves room for it */
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply {
    UIFont *body = ExteriaFontRegular((CGFloat)ExteriaChatTextSize());
    CGFloat radius = (CGFloat)ExteriaChatBubbleRadius();
    CGFloat limit = floor((width - 2 * PREVIEW_PAD) * BUBBLE_MAX_FRACTION) - 2 * BUBBLE_PAD_X;
    CGFloat meta = META_SIZE + 4;
    /* only the talk of the Exteria screen follows the switches of the stickers */
    BOOL live = _lines == ExteriaPreviewExteria;
    /* the quote follows the text size as it does in the chat */
    CGFloat quoteSize = (CGFloat)ExteriaChatTextSize() - 1;
    CGFloat quoteLine = ceil(quoteSize + 4);
    CGFloat quoteHeight = 2 * quoteLine + 2 * QUOTE_PAD - 4;
    CGFloat y = PREVIEW_PAD;
    for (ExteriaPreviewBubble *bubble in _bubbles) {
        bubble->quoteName.font = ExteriaFontSemibold(quoteSize);
        bubble->quoteText.font = ExteriaFontRegular(quoteSize);
        CGFloat timeText = ceil(ExteriaStringSize(bubble->time.text, bubble->time.font).width);
        CGFloat timeWidth = timeText + (bubble->outgoing ? CHECK_WIDTH : 0);
        CGFloat quoteNameWidth = bubble->quotePlate ? ceil(ExteriaStringSize(bubble->quoteName.text, bubble->quoteName.font).width) : 0;
        CGFloat quoteTextWidth = bubble->quotePlate ? ceil(ExteriaStringSize(bubble->quoteText.text, bubble->quoteText.font).width) : 0;
        CGFloat quoteWidth = bubble->quotePlate ? MIN(limit, QUOTE_LEFT + MAX(quoteNameWidth, quoteTextWidth) + QUOTE_RIGHT) : 0;
        if (bubble->sticker) {
            /* the sticker follows the slider of its size, as the stickers of the chat do */
            CGFloat side = MIN(STICKER_SIDE, floor((width - 2 * PREVIEW_PAD) * 0.6)) * (live ? (CGFloat)ExteriaChatStickerScale() / 100.0 : 1);
            side = floor(MIN(side, width - 2 * PREVIEW_PAD));
            CGFloat x = bubble->outgoing ? width - PREVIEW_PAD - side : PREVIEW_PAD;
            ExteriaStickerShape shape = live ? ExteriaChatStickerShape() : ExteriaStickerShapeNone;
            CGFloat shapeRadius = shape == ExteriaStickerShapeNone ? 0 : (shape == ExteriaStickerShapeRounded ? floor(side * 0.12) : radius);
            if (bubble->quotePlate) {
                /* the quote stands at the left edge of the preview while the sticker under it stays on the right */
                CGFloat plateWidth = MAX(quoteWidth, 64);
                CGFloat plateX = PREVIEW_PAD;
                if (apply) {
                    bubble->quotePlate.frame = CGRectMake(plateX, y, plateWidth, quoteHeight);
                    [self layoutQuote:bubble width:plateWidth height:quoteHeight line:quoteLine];
                }
                /* the quote sits right on the sticker */
                y += quoteHeight;
            }
            if (apply) {
                bubble->picture.frame = CGRectMake(x, y, side, side);
                bubble->picture.layer.cornerRadius = shapeRadius;
                bubble->picture.layer.masksToBounds = shapeRadius > 0;
                bubble->picture.backgroundColor = shape == ExteriaStickerShapeBubble ? (bubble->outgoing ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn()) : [UIColor clearColor];
                BOOL timeShown = !live || !ExteriaChatFlagGet(ExteriaChatFlagHideStickerTime);
                bubble->capsule.hidden = !timeShown;
                CGFloat capsuleWidth = timeWidth + 12, capsuleHeight = meta + 4;
                bubble->capsule.frame = CGRectMake(x + side - 8 - capsuleWidth, y + side - 8 - capsuleHeight, capsuleWidth, capsuleHeight);
                bubble->capsule.layer.cornerRadius = capsuleHeight / 2;
                bubble->time.frame = CGRectMake(6, 2, timeText, meta);
                bubble->checks.frame = CGRectMake(6 + timeText + 2, 4, 14, 10);
            }
            y += side + BUBBLE_GAP;
            continue;
        }
        bubble->text.font = body;
        CGSize textSize = [bubble->text sizeThatFits:CGSizeMake(limit, 1000)];
        CGFloat textWidth = ceil(textSize.width);
        CGFloat quoteBlock = bubble->quotePlate ? quoteHeight + 4 : 0;
        /* the last line shares its row with the time only when both fit within the limit */
        BOOL beside = textWidth + 6 + timeWidth <= limit;
        CGFloat contentWidth = MAX(MAX(textWidth, quoteWidth), beside ? textWidth + 6 + timeWidth : timeWidth);
        CGFloat boxWidth = MIN(limit, contentWidth) + 2 * BUBBLE_PAD_X;
        CGFloat reactionHeight = _quickReaction && bubble == [_bubbles objectAtIndex:0] ? 38 : 0;
        CGFloat boxHeight = BUBBLE_PAD_Y + quoteBlock + ceil(textSize.height) + (beside || reactionHeight ? 0 : meta - 2) + BUBBLE_PAD_Y + reactionHeight;
        if (apply) {
            CGFloat corner = ExteriaThemeIsClassic() ? (CGFloat)ExteriaChatClassicBubbleRadius() : MIN(radius, MIN(boxWidth, boxHeight) / 2);
            CGFloat x = bubble->outgoing ? width - PREVIEW_PAD - boxWidth : PREVIEW_PAD;
            bubble->box.layer.cornerRadius = corner;
            bubble->box.frame = CGRectMake(x, y, boxWidth, boxHeight);
            bubble->fill.frame = bubble->box.bounds;
            bubble->fill.cornerRadius = corner;
            CGFloat inner = boxWidth - 2 * BUBBLE_PAD_X;
            if (bubble->quotePlate) {
                bubble->quotePlate.frame = CGRectMake(BUBBLE_PAD_X, BUBBLE_PAD_Y, inner, quoteHeight);
                [self layoutQuote:bubble width:inner height:quoteHeight line:quoteLine];
            }
            bubble->text.frame = CGRectMake(BUBBLE_PAD_X, BUBBLE_PAD_Y + quoteBlock, inner, ceil(textSize.height));
            if (reactionHeight) _quickReaction.frame = CGRectMake(BUBBLE_PAD_X, boxHeight - reactionHeight, inner, reactionHeight);
            bubble->time.frame = CGRectMake(boxWidth - BUBBLE_PAD_X - timeWidth, boxHeight - BUBBLE_PAD_Y - meta + 2, timeText, meta);
            bubble->checks.frame = CGRectMake(boxWidth - BUBBLE_PAD_X - CHECK_WIDTH + 2, boxHeight - BUBBLE_PAD_Y - meta + 4, 14, 10);
        }
        y += boxHeight + BUBBLE_GAP;
    }
    CGFloat total = y - BUBBLE_GAP + PREVIEW_PAD;
    if (apply) _wallpaper.frame = CGRectMake(0, 0, width, total);
    return total;
}

/* the bar, the nick and the line of a quote inside its plate */
- (void)layoutQuote:(ExteriaPreviewBubble *)bubble width:(CGFloat)width height:(CGFloat)height line:(CGFloat)line {
    bubble->quoteBar.frame = CGRectMake(6, 6, QUOTE_BAR, MAX(0, height - 12));
    bubble->quoteBar.layer.cornerRadius = QUOTE_BAR / 2;
    bubble->quoteName.frame = CGRectMake(QUOTE_LEFT, QUOTE_PAD - 1, MAX(0, width - QUOTE_LEFT - QUOTE_RIGHT), line);
    bubble->quoteText.frame = CGRectMake(QUOTE_LEFT, QUOTE_PAD - 1 + line, MAX(0, width - QUOTE_LEFT - QUOTE_RIGHT), line);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    _reportedHeight = [self layoutForWidth:width apply:NO];
    return _reportedHeight;
}

- (void)reportHeight {
    if (_heightHandler) _heightHandler();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    if (width < 1) return;
    if (fabs(width - _wallpaperWidth) > 1) [self applyWallpaper];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat total = [self layoutForWidth:width apply:YES];
    [CATransaction commit];
    if (fabs(total - _reportedHeight) > 0.5) {
        _reportedHeight = total;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reportHeight) object:nil];
        [self performSelector:@selector(reportHeight) withObject:nil afterDelay:0];
    }
}

@end
