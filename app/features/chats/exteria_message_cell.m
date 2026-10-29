#import "exteria_message_cell.h"
#import "exteria_map_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_avatar_view.h"
#import "exteria_developers.h"
#import "exteria_emoji_store.h"
#import "exteria_sticker_library.h"
#import "exteria_music_player.h"
#import "exteria_image_decoder.h"
#import "exteria_lottie_view.h"
#import "exteria_gift_card.h"
#import "exteria_media_action_view.h"
#import "exteria_markup_view.h"
#import "exteria_reactions_view.h"
#import "exteria_audio_session.h"
#import "exteria_weak_reference.h"
#import "exteria_lite_mode.h"
#import "exteria_platform.h"
#import "exteria_string_drawing.h"
#import "exteria_symbol.h"
#import "exteria_wave.h"
#import "exteria_chat_settings.h"
#import "exteria_theme.h"
#import "exteria_burn_effect.h"

#define JOIN_RADIUS 5.0
/* the corner of a modern bubble, which the person sets in the chat settings; the corner that tucks in against a neighbour is never larger than it */
static CGFloat ExteriaBubbleRadius(void) {
    return (CGFloat)ExteriaChatBubbleRadius();
}
#define MEDIA_BUTTON 48.0
#define VOICE_BUTTON 44.0
#define CLASSIC_TAIL 6.0
#define PAD_X_POLL 11.0
#define META_HEIGHT_POLL 14.0
/* how far a swipe to reply pulls the row before it counts, and how far the row can be pulled at most */
#define SWIPE_TRIGGER 64.0
#define SWIPE_MAX 92.0
#define SWIPE_DISC 32.0
/* how far the rows of others step right to leave room for the selection circle, and the circle's side */
#define SELECT_SHIFT 32.0
#define SELECT_MARK 24.0
static char ExteriaGifStatusContext;
/* the comments row of a post: the side padding, the pictures of the commenters and how far each is set over the one before */
#define PAD_X_COMMENTS 11.0
#define COMMENTER_SIDE 24.0
#define COMMENTER_STEP 16.0

/* a view whose layer plays a video, for a round message that plays in its own circle */
@interface ExteriaRoundVideoView : UIView
@end

@implementation ExteriaRoundVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

typedef enum { ExteriaBubbleLayerBody, ExteriaBubbleLayerOverlay, ExteriaBubbleLayerReply } ExteriaBubbleLayer;

/* draws the bubble with its text, or the time capsule over a picture */
@interface ExteriaBubbleView : UIView {
    ExteriaChatItem *_item;
    ExteriaBubbleLayer _layerKind;
    CGFloat _tailWidth;
    NSString *_fileProgressText;
}
@property (nonatomic, retain) ExteriaChatItem *item;
/* the room a classic bubble keeps beside itself for its tail, on the side the bubble leans to; zero without a tail */
@property (nonatomic, assign) CGFloat tailWidth;
@property (nonatomic, assign) ExteriaBubbleLayer layerKind;
@property (nonatomic, copy) NSString *fileProgressText;
/* where the bars of a voice note and its speed chip are, in the bubble's coordinates */
- (CGRect)waveRect;
- (CGRect)speedChipRect;
@end

@implementation ExteriaBubbleView

@synthesize item = _item;
@synthesize layerKind = _layerKind;
@synthesize tailWidth = _tailWidth;
@synthesize fileProgressText = _fileProgressText;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)dealloc {
    [_item release];
    [_fileProgressText release];
    [super dealloc];
}

static void ExteriaAddCorners(CGContextRef context, CGRect rect, CGFloat topLeft, CGFloat topRight, CGFloat bottomRight, CGFloat bottomLeft) {
    CGFloat x0 = CGRectGetMinX(rect), y0 = CGRectGetMinY(rect), x1 = CGRectGetMaxX(rect), y1 = CGRectGetMaxY(rect);
    CGContextMoveToPoint(context, x0 + topLeft, y0);
    CGContextAddLineToPoint(context, x1 - topRight, y0);
    CGContextAddArcToPoint(context, x1, y0, x1, y0 + topRight, topRight);
    CGContextAddLineToPoint(context, x1, y1 - bottomRight);
    CGContextAddArcToPoint(context, x1, y1, x1 - bottomRight, y1, bottomRight);
    CGContextAddLineToPoint(context, x0 + bottomLeft, y1);
    CGContextAddArcToPoint(context, x0, y1, x0, y1 - bottomLeft, bottomLeft);
    CGContextAddLineToPoint(context, x0, y0 + topLeft);
    CGContextAddArcToPoint(context, x0, y0, x0 + topLeft, y0, topLeft);
    CGContextClosePath(context);
}

static void ExteriaFillCapsule(CGContextRef context, CGRect rect, UIColor *color) {
    [color setFill];
    ExteriaAddCorners(context, rect, rect.size.height / 2, rect.size.height / 2, rect.size.height / 2, rect.size.height / 2);
    CGContextFillPath(context);
}

/* the time and, on our own messages, the delivery mark; color is the one the text beside it uses */
- (void)drawMetaAt:(CGPoint)origin color:(UIColor *)color context:(CGContextRef)context {
    ExteriaMessage *message = _item.message;
    [color set];
    CGFloat textWidth = _item.timeSize.width - (message.outgoing ? 20 : 0);
    if (_layerKind == ExteriaBubbleLayerOverlay) textWidth = _item.timeSize.width - 10 - (message.outgoing ? 20 : 0);
    CGFloat timeX = origin.x;
    if (_item.viewsText.length) {
        /* the view count of a post: a small eye, the count, then the time */
        UIImage *eye = ExteriaSymbolImage(ExteriaSymbolEye, 12, color);
        [eye drawAtPoint:CGPointMake(origin.x, origin.y + 1.5)];
        ExteriaDrawStringAt(_item.viewsText, ExteriaFontRegular(11), CGPointMake(origin.x + 15.5, origin.y));
        timeX = origin.x + _item.viewsWidth;
    }
    if (_item.deletedWidth > 0) {
        UIImage *can = ExteriaSymbolImage(ExteriaSymbolTrashCan, 12, color);
        [can drawAtPoint:CGPointMake(timeX, origin.y + 1 + (12 - can.size.height) / 2)];
        timeX += _item.deletedWidth;
    }
    ExteriaDrawStringAt(_item.timeText, ExteriaFontRegular(11), CGPointMake(timeX, origin.y));
    if (!message.outgoing) return;
    CGFloat markX = origin.x + ceil(textWidth) + 3;
    CGFloat markY = origin.y + 1;
    if (message.state == ExteriaMessageStateFailed) {
        CGRect badge = CGRectMake(markX - 1, markY - 1, 14, 14);
        [ExteriaColorBadgeRed() setFill];
        CGContextFillEllipseInRect(context, badge);
        [[UIColor whiteColor] set];
        ExteriaDrawStringIn(@"!", ExteriaFontBold(10), CGRectMake(badge.origin.x, badge.origin.y - 0.5, badge.size.width, badge.size.height),
                            ExteriaStringClip, ExteriaTextAlignmentCenter);
        return;
    }
    UIImage *mark;
    if (message.state == ExteriaMessageStateSending) mark = ExteriaSymbolImage(ExteriaSymbolClock, 11, color);
    else mark = ExteriaCheckImage(_item.read, 11, color);
    /* the slot fits the double check, a single one sits at its right edge */
    CGFloat slot = 11 * 25.0 / 16.0;
    [mark drawAtPoint:CGPointMake(markX + slot - mark.size.width, markY + 0.5 - (mark.size.height - 11) / 2)];
}

- (void)drawPill:(CGContextRef)context {
    CGRect rect = self.bounds;
    ExteriaTextLayout *text = _item.pillLayout;
    if (ExteriaThemeIsClassic()) {
        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, CGSizeMake(0, ExteriaThemeIsDark() ? -1 : 1), 0,
                                    (ExteriaThemeIsDark() ? [UIColor colorWithWhite:0 alpha:0.7] : [UIColor colorWithWhite:1 alpha:0.8]).CGColor);
        [text drawAtPoint:CGPointMake(11 - _item.pillShift, (rect.size.height - text.size.height) / 2)];
        CGContextRestoreGState(context);
        return;
    }
    ExteriaFillCapsule(context, rect, ExteriaColorBubbleCapsule());
    [text drawAtPoint:CGPointMake(11 - _item.pillShift, (rect.size.height - text.size.height) / 2)];
}

#define WAVE_BAR 2.5
#define WAVE_GAP 2.0
#define CHIP_WIDTH 38.0

/* where the bars of a voice note lie in the bubble, and its speed chip, in the bubble's coordinates */
- (CGRect)waveRect {
    CGRect frame = _item.fileFrame;
    return CGRectMake(frame.origin.x + 44 + 10, frame.origin.y + 2, frame.size.width - 44 - 10, 24);
}

- (CGRect)speedChipRect {
    CGRect frame = _item.fileFrame;
    return CGRectMake(CGRectGetMaxX(frame) - CHIP_WIDTH, frame.origin.y + 28, CHIP_WIDTH, 16);
}

/* the note as bars, the part already heard in the strong color, the time and, while it plays, the speed under
   them; a note that came without a waveform gets a flat even row so it still reads as a voice */
- (void)drawVoiceRow:(CGContextRef)context {
    ExteriaMessage *message = _item.message;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    BOOL current = [player isCurrentTrack:message.media] && player.state != ExteriaMusicStateFailed;
    NSTimeInterval length = current && player.duration > 0 ? player.duration : message.media.duration;
    float heard = current && length > 0 ? (float)MIN(1, player.position / length) : 0;
    CGRect wave = [self waveRect];
    NSData *bars = message.media.waveformBars;
    NSUInteger count = (NSUInteger)MAX(1, floor((wave.size.width + WAVE_GAP) / (WAVE_BAR + WAVE_GAP)));
    UIColor *strong = message.outgoing && !ExteriaThemeIsClassic() ? [UIColor whiteColor] : ExteriaColorAccent();
    UIColor *quiet = ExteriaColorBubbleMeta(message.outgoing);
    const uint8_t *levels = bars.bytes;
    for (NSUInteger i = 0; i < count; ++i) {
        CGFloat level = 0.35;
        if (levels && bars.length) {
            /* each drawn bar shows the loudest of the source bars it covers */
            NSUInteger from = i * bars.length / count, to = MAX(from + 1, (i + 1) * bars.length / count);
            uint8_t peak = 0;
            for (NSUInteger j = from; j < to && j < bars.length; ++j) if (levels[j] > peak) peak = levels[j];
            level = MAX(0.12, peak / 31.0);
        }
        CGFloat height = MAX(3, level * wave.size.height);
        CGFloat x = wave.origin.x + (CGFloat)i * (WAVE_BAR + WAVE_GAP);
        [((CGFloat)(i + 0.5) / (CGFloat)count <= heard ? strong : quiet) setFill];
        ExteriaAddCorners(context, CGRectMake(x, CGRectGetMidY(wave) - height / 2, WAVE_BAR, height), WAVE_BAR / 2, WAVE_BAR / 2, WAVE_BAR / 2, WAVE_BAR / 2);
        CGContextFillPath(context);
    }
    NSInteger shown = (NSInteger)(current ? player.position : message.media.duration);
    NSString *time = [NSString stringWithFormat:@"%ld:%02ld", (long)(shown / 60), (long)(shown % 60)];
    [quiet set];
    ExteriaDrawStringAt(time, ExteriaFontRegular(12), CGPointMake(wave.origin.x, _item.fileFrame.origin.y + 29));
    if (current) {
        CGRect chip = [self speedChipRect];
        [strong setFill];
        ExteriaAddCorners(context, chip, 8, 8, 8, 8);
        CGContextFillPath(context);
        [(message.outgoing && !ExteriaThemeIsClassic() ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn()) set];
        ExteriaDrawStringIn(ExteriaSpeedText(player.speed), ExteriaFontSemibold(11), CGRectInset(chip, 0, 1), ExteriaStringClip, ExteriaTextAlignmentCenter);
    }
}

/* the arrow before the second line of a call: up and right for a call of ours, down and left for one that came in */
static void ExteriaDrawCallArrow(CGContextRef context, CGPoint origin, BOOL incoming, UIColor *color) {
    const CGFloat side = 10;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, origin.x + side / 2, origin.y + side / 2);
    if (incoming) CGContextRotateCTM(context, (CGFloat)M_PI);
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, 1.6);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextMoveToPoint(context, -side / 2 + 1, side / 2 - 1);
    CGContextAddLineToPoint(context, side / 2 - 1, -side / 2 + 1);
    CGContextMoveToPoint(context, side / 2 - 5.5f, -side / 2 + 1);
    CGContextAddLineToPoint(context, side / 2 - 1, -side / 2 + 1);
    CGContextAddLineToPoint(context, side / 2 - 1, side / 2 - 5.5f);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

/* a call: its title, under it the arrow and the time with the length, and the phone or the camera at the end of the row */
- (void)drawCallRow:(CGContextRef)context {
    ExteriaMessage *message = _item.message;
    CGRect frame = _item.fileFrame;
    UIColor *text = ExteriaColorBubbleText(message.outgoing);
    UIColor *line = _item.callFailed ? ExteriaColorBadgeRed() : text;
    [_item.fileTitleLayout drawAtPoint:CGPointMake(frame.origin.x, frame.origin.y + 2)];
    ExteriaDrawCallArrow(context, CGPointMake(frame.origin.x, frame.origin.y + 28), _item.callIncoming, line);
    [line set];
    ExteriaDrawStringIn(_item.fileDetail, ExteriaFontRegular(13), CGRectMake(frame.origin.x + 16, frame.origin.y + 25, frame.size.width - 16 - 30, 18), ExteriaStringTailTruncate, ExteriaTextAlignmentLeft);
    UIImage *glyph = ExteriaSymbolImage(_item.callVideo ? ExteriaSymbolVideoCamera : ExteriaSymbolPhone, 22, text);
    [glyph drawAtPoint:CGPointMake(CGRectGetMaxX(frame) - glyph.size.width, CGRectGetMidY(frame) - glyph.size.height / 2)];
}

- (void)drawFileRow:(CGContextRef)context {
    ExteriaMessage *message = _item.message;
    CGRect frame = _item.fileFrame;
    CGRect icon = CGRectMake(frame.origin.x, frame.origin.y, 44, 44);
    if (_item.call) {
        [self drawCallRow:context];
        return;
    }
    /* a one-time file is a card: a disc with a dashed ring and the figure one, whatever the file is */
    if (ExteriaMessageIsViewOnce(message)) {
        BOOL expired = ExteriaViewOnceExpired(message);
        UIColor *ink = [UIColor whiteColor];
        [(message.outgoing && !ExteriaThemeIsClassic() ? [UIColor colorWithWhite:1 alpha:0.22] : ExteriaColorAccent()) setFill];
        CGContextFillEllipseInRect(context, icon);
        CGContextSaveGState(context);
        CGContextSetStrokeColorWithColor(context, [ink colorWithAlphaComponent:expired ? 0.45 : 0.95].CGColor);
        CGContextSetLineWidth(context, 1.6);
        CGFloat dashes[2] = {3.2, 3.2};
        CGContextSetLineDash(context, 0, dashes, 2);
        CGContextStrokeEllipseInRect(context, CGRectInset(icon, 6, 6));
        CGContextRestoreGState(context);
        [ink set];
        ExteriaDrawStringIn(@"1", ExteriaFontBold(17), CGRectMake(icon.origin.x, icon.origin.y + 11, 44, 22), ExteriaStringClip, ExteriaTextAlignmentCenter);
        UIColor *quiet = ExteriaColorBubbleMeta(message.outgoing);
        CGFloat textX = icon.origin.x + 44 + 10, textWidth = frame.size.width - 44 - 10;
        [_item.fileTitleLayout drawAtPoint:CGPointMake(textX, frame.origin.y + 6)];
        [quiet set];
        ExteriaDrawStringIn(_item.fileDetail, ExteriaFontRegular(13), CGRectMake(textX, frame.origin.y + 25, textWidth, 18), ExteriaStringTailTruncate, ExteriaTextAlignmentLeft);
        return;
    }
    /* the button of a voice note, a song or a document is a view of its own over this corner of the row, which animates between its glyphs */
    BOOL ownButton = message.media.kind == EXTERIA_PREVIEW_VOICE || message.media.kind == EXTERIA_PREVIEW_AUDIO || message.media.kind == EXTERIA_PREVIEW_FILE;
    if (!ownButton) {
        [(message.outgoing && !ExteriaThemeIsClassic() ? [UIColor colorWithWhite:1 alpha:0.22] : ExteriaColorAccent()) setFill];
        CGContextFillEllipseInRect(context, icon);
        ExteriaSymbol glyph = ExteriaSymbolDocument;
        switch (message.media.kind) {
        case EXTERIA_PREVIEW_FILE: glyph = ExteriaSymbolArrowDown; break;
        case EXTERIA_PREVIEW_VIDEO:
        case EXTERIA_PREVIEW_VIDEO_MESSAGE:
        case EXTERIA_PREVIEW_GIF: glyph = ExteriaSymbolPlay; break;
        default: break;
        }
        UIImage *symbol = ExteriaSymbolImage(glyph, 22, [UIColor whiteColor]);
        [symbol drawAtPoint:CGPointMake(icon.origin.x + (44 - symbol.size.width) / 2, icon.origin.y + (44 - symbol.size.height) / 2)];
    }
    if (message.media.kind == EXTERIA_PREVIEW_VOICE) {
        [self drawVoiceRow:context];
        return;
    }
    UIColor *quiet = ExteriaColorBubbleMeta(message.outgoing);
    CGFloat textX = icon.origin.x + 44 + 10, textWidth = frame.size.width - 44 - 10;
    [_item.fileTitleLayout drawAtPoint:CGPointMake(textX, frame.origin.y + 6)];
    [quiet set];
    if (!_fileProgressText && _item.fileDetailLayout) [_item.fileDetailLayout drawAtPoint:CGPointMake(textX, frame.origin.y + 25)];
    else ExteriaDrawStringIn(_fileProgressText ? _fileProgressText : _item.fileDetail, ExteriaFontRegular(13), CGRectMake(textX, frame.origin.y + 25, textWidth, 18), ExteriaStringTailTruncate, ExteriaTextAlignmentLeft);
}

/* the outline of a classic bubble; with a tail the outer bottom corner runs out into a small point beside the bubble */
static void ExteriaClassicBubblePath(CGContextRef context, CGRect rect, BOOL outgoing, CGFloat topLeft, CGFloat topRight,
                                     CGFloat bottomRight, CGFloat bottomLeft, CGFloat tail) {
    CGFloat x0 = CGRectGetMinX(rect), y0 = CGRectGetMinY(rect), x1 = CGRectGetMaxX(rect), y1 = CGRectGetMaxY(rect);
    if (tail <= 0) {
        ExteriaAddCorners(context, rect, topLeft, topRight, bottomRight, bottomLeft);
        return;
    }
    CGContextMoveToPoint(context, x0 + topLeft, y0);
    CGContextAddLineToPoint(context, x1 - topRight, y0);
    CGContextAddArcToPoint(context, x1, y0, x1, y0 + topRight, topRight);
    if (outgoing) {
        CGContextAddLineToPoint(context, x1, y1 - 16);
        CGContextAddCurveToPoint(context, x1, y1 - 6, x1 + 1.5, y1 - 1.5, x1 + tail, y1);
        CGContextAddCurveToPoint(context, x1 + tail - 3, y1 - 0.5, x1 - 4, y1, x1 - 12, y1);
    } else {
        CGContextAddLineToPoint(context, x1, y1 - bottomRight);
        CGContextAddArcToPoint(context, x1, y1, x1 - bottomRight, y1, bottomRight);
        CGContextAddLineToPoint(context, x0 + 12, y1);
        CGContextAddCurveToPoint(context, x0 + 4, y1, x0 - tail + 3, y1 - 0.5, x0 - tail, y1);
        CGContextAddCurveToPoint(context, x0 - 1.5, y1 - 1.5, x0, y1 - 6, x0, y1 - 16);
    }
    if (outgoing) {
        CGContextAddLineToPoint(context, x0 + bottomLeft, y1);
        CGContextAddArcToPoint(context, x0, y1, x0, y1 - bottomLeft, bottomLeft);
    }
    CGContextAddLineToPoint(context, x0, y0 + topLeft);
    CGContextAddArcToPoint(context, x0, y0, x0 + topLeft, y0, topLeft);
    CGContextClosePath(context);
}

/* the old Messages look: a soft shadow, a gradient, a lit top edge and a thin outline */
static void ExteriaDrawClassicBubble(CGContextRef context, CGRect rect, BOOL outgoing, CGFloat topLeft, CGFloat topRight,
                                     CGFloat bottomRight, CGFloat bottomLeft, CGFloat tail) {
    UIColor *top, *bottom, *outline;
    ExteriaClassicBubbleColors(outgoing, &top, &bottom, &outline);
    CGFloat from[4], to[4];
    [top getRed:&from[0] green:&from[1] blue:&from[2] alpha:&from[3]];
    [bottom getRed:&to[0] green:&to[1] blue:&to[2] alpha:&to[3]];
    CGRect body = CGRectInset(rect, 0.5, 0.5);
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0, 1), 2, [UIColor colorWithWhite:0 alpha:0.3].CGColor);
    ExteriaClassicBubblePath(context, body, outgoing, topLeft, topRight, bottomRight, bottomLeft, tail);
    [bottom setFill];
    CGContextFillPath(context);
    CGContextRestoreGState(context);
    CGContextSaveGState(context);
    ExteriaClassicBubblePath(context, body, outgoing, topLeft, topRight, bottomRight, bottomLeft, tail);
    CGContextClip(context);
    CGFloat colors[8] = {from[0], from[1], from[2], from[3], to[0], to[1], to[2], to[3]};
    ExteriaFillGradient(context, CGPointMake(0, CGRectGetMinY(body)), CGPointMake(0, CGRectGetMaxY(body)), colors, 2);
    /* a one point light line under the top edge, as a bevel */
    [[UIColor colorWithWhite:1 alpha:ExteriaThemeIsDark() ? 0.18 : 0.6] setFill];
    CGContextFillRect(context, CGRectMake(CGRectGetMinX(body) + topLeft, CGRectGetMinY(body) + 1, CGRectGetWidth(body) - topLeft - topRight, 1));
    CGContextRestoreGState(context);
    ExteriaClassicBubblePath(context, body, outgoing, topLeft, topRight, bottomRight, bottomLeft, tail);
    [outline setStroke];
    CGContextSetLineWidth(context, 1);
    CGContextStrokePath(context);
}

- (void)drawReply {
    if (CGRectIsEmpty(_item.replyFrame)) return;
    CGRect frame = _layerKind == ExteriaBubbleLayerReply ? self.bounds : _item.replyFrame;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:10] addClip];
    UIColor *bubbleColor = _item.message.outgoing ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn();
    if (_layerKind == ExteriaBubbleLayerReply) {
        [bubbleColor setFill];
        UIRectFill(frame);
    }
    if (ExteriaChatFlagGet(ExteriaChatFlagReplyBackground)) {
        [ExteriaMixedColor(bubbleColor, _item.replyColor, 0.3) setFill];
        UIRectFill(frame);
    }
    CGContextRestoreGState(context);
    /* the bar is a pill inset from the edge of the plate */
    [_item.replyColor setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(frame.origin.x + 6, frame.origin.y + 6, 3, MAX(0, frame.size.height - 12)) cornerRadius:1.5] fill];
    CGPoint at = CGPointMake(frame.origin.x + 17, frame.origin.y + 6);
    [_item.replyTitleLayout drawAtPoint:at];
    at.y += _item.replyTitleLayout.size.height + 2;
    [_item.replyTextLayout drawAtPoint:at];
}

- (void)drawBody:(CGContextRef)context {
    ExteriaMessage *message = _item.message;
    BOOL outgoing = message.outgoing;
    BOOL classic = ExteriaThemeIsClassic();
    CGRect rect = self.bounds;
    CGFloat inner = classic ? (CGFloat)ExteriaChatClassicBubbleRadius() : ExteriaBubbleRadius();
    CGFloat join = MIN(JOIN_RADIUS, inner);
    CGFloat joinTop = _item.joinsPrevious ? join : inner, joinBottom = _item.joinsNext ? join : inner;
    if (_tailWidth > 0) {
        /* the content is laid out from the bubble's own corner, so a bubble with its tail on the left slides over by the tail */
        rect.size.width -= _tailWidth;
        if (!outgoing) {
            CGContextTranslateCTM(context, _tailWidth, 0);
            rect.origin.x = 0;
        }
    }
    /* the corner on the side the bubble leans towards is the one that tucks in against its neighbour */
    if (classic) {
        ExteriaDrawClassicBubble(context, rect, outgoing, outgoing ? inner : joinTop, outgoing ? joinTop : inner, outgoing ? joinBottom : inner,
                                 outgoing ? inner : joinBottom, _tailWidth);
    } else {
        ExteriaAddCorners(context, rect, outgoing ? inner : joinTop, outgoing ? joinTop : inner, outgoing ? joinBottom : inner, outgoing ? inner : joinBottom);
        [(outgoing ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn()) setFill];
        CGContextFillPath(context);
    }
    if (_item.senderName.length) {
        [_item.senderLayout drawAtPoint:_item.senderOrigin];
        [_item.senderTagLayout drawAtPoint:_item.senderTagOrigin];
    }
    if (_item.forwardText.length) {
        [_item.forwardLayout drawAtPoint:_item.forwardOrigin];
    }
    [self drawReply];
    if (_item.content == ExteriaChatItemContentFile) [self drawFileRow:context];
    if (_item.content == ExteriaChatItemContentPoll) [self drawPoll:context];
    if (_item.textLayout) [_item.textLayout drawAtPoint:_item.textOrigin];
    BOOL overPicture = _item.content == ExteriaChatItemContentPicture && !_item.textLayout;
    /* the time of a call is in its second line */
    if (!overPicture && !_item.call) [self drawMetaAt:_item.timeOrigin color:ExteriaColorBubbleMeta(outgoing) context:context];
    if (_item.commentsText.length) [self drawCommentsRow:context];
}

/* a check or a cross in a filled disc, 20 points wide */
static void ExteriaDrawPollMark(CGContextRef context, CGRect mark, UIColor *fill, UIColor *glyphColor, ExteriaSymbol symbol, BOOL square) {
    [fill setFill];
    if (square) {
        ExteriaAddCorners(context, mark, 5, 5, 5, 5);
        CGContextFillPath(context);
    } else {
        CGContextFillEllipseInRect(context, mark);
    }
    UIImage *glyph = ExteriaSymbolImage(symbol, 13, glyphColor);
    [glyph drawAtPoint:CGPointMake(CGRectGetMidX(mark) - glyph.size.width / 2, CGRectGetMidY(mark) - glyph.size.height / 2)];
}


- (void)drawPoll:(CGContextRef)context {
    ExteriaMessage *message = _item.message;
    ExteriaPoll *poll = message.poll;
    BOOL outgoing = message.outgoing;
    UIColor *text = ExteriaColorBubbleText(outgoing), *quiet = ExteriaColorBubbleMeta(outgoing), *accent = ExteriaColorBubbleLink(outgoing);
    UIColor *good = [UIColor colorWithRed:0.30f green:0.73f blue:0.35f alpha:1], *bad = ExteriaColorBadgeRed();
    /* the mark of a chosen answer is a light disc on the purple of an outgoing bubble, where a white check would vanish, so its glyph takes the color of the bubble */
    UIColor *glyph = outgoing ? ExteriaColorBubbleOut() : [UIColor whiteColor];
    [_item.pollQuestionLayout drawAtPoint:_item.pollQuestionOrigin];
    [_item.pollKindLayout drawAtPoint:_item.pollKindOrigin];
    BOOL results = _item.pollShowsResults;
    int32_t most = 0;
    for (ExteriaPollAnswer *answer in poll.answers) most = MAX(most, answer.voters);
    for (NSUInteger i = 0; i < poll.answers.count; ++i) {
        ExteriaPollAnswer *answer = [poll.answers objectAtIndex:i];
        ExteriaTextLayout *layout = [_item.pollAnswerLayouts objectAtIndex:i];
        CGRect row = [[_item.pollAnswerFrames objectAtIndex:i] CGRectValue];
        CGRect mark = CGRectMake(row.origin.x, row.origin.y + 8, 20, 20);
        BOOL picked = [poll.picked containsIndex:i];
        BOOL show = results && poll.voted;
        if (poll.quiz && show && answer.correct) ExteriaDrawPollMark(context, mark, good, [UIColor whiteColor], ExteriaSymbolCheck, NO);
        else if (poll.quiz && show && answer.chosen) ExteriaDrawPollMark(context, mark, bad, [UIColor whiteColor], ExteriaSymbolClose, NO);
        else if (answer.chosen || picked) ExteriaDrawPollMark(context, mark, accent, glyph, ExteriaSymbolCheck, poll.multiple);
        else {
            [quiet setStroke];
            CGContextSetLineWidth(context, 1.5);
            CGRect ring = CGRectInset(mark, 0.75, 0.75);
            if (poll.multiple) {
                ExteriaAddCorners(context, ring, 5, 5, 5, 5);
                CGContextStrokePath(context);
            } else {
                CGContextStrokeEllipseInRect(context, ring);
            }
        }
        CGFloat textX = row.origin.x + 20 + 8;
        [layout drawAtPoint:CGPointMake(textX, row.origin.y + 8)];
        if (!results) continue;
        int32_t total = MAX(poll.totalVoters, 1);
        CGFloat share = (CGFloat)answer.voters / (CGFloat)total;
        NSString *percent = [NSString stringWithFormat:@"%d%%", (int)(share * 100 + 0.5f)];
        [text set];
        ExteriaDrawStringIn(percent, ExteriaFontSemibold(13), CGRectMake(CGRectGetMaxX(row) - 38, row.origin.y + 8, 38, 20), ExteriaStringClip, ExteriaTextAlignmentRight);
        /* the bar is as long as the answer's share of the longest, so a poll of one answer still reads as a full bar */
        CGFloat barWidth = row.size.width - 20 - 8 - 38;
        CGFloat barY = CGRectGetMaxY(row) - 8 - 4;
        CGFloat fraction = most > 0 ? (CGFloat)answer.voters / (CGFloat)most : 0;
        UIColor *barColor = poll.quiz && show && answer.correct ? good : (poll.quiz && show && answer.chosen ? bad : accent);
        [[barColor colorWithAlphaComponent:0.25f] setFill];
        ExteriaAddCorners(context, CGRectMake(textX, barY, barWidth, 4), 2, 2, 2, 2);
        CGContextFillPath(context);
        if (fraction > 0) {
            [barColor setFill];
            ExteriaAddCorners(context, CGRectMake(textX, barY, MAX(4, barWidth * fraction), 4), 2, 2, 2, 2);
            CGContextFillPath(context);
        }
    }
    if (_item.pollButtonTitle.length) {
        CGRect button = _item.pollButtonFrame;
        [[quiet colorWithAlphaComponent:0.25f] setFill];
        CGContextFillRect(context, CGRectMake(button.origin.x, button.origin.y, button.size.width, 1.0 / ExteriaScreenScale()));
        [accent set];
        ExteriaDrawStringIn(_item.pollButtonTitle, ExteriaFontSemibold(15), CGRectMake(button.origin.x, button.origin.y + 8, button.size.width, 20), ExteriaStringClip, ExteriaTextAlignmentCenter);
    }
    [quiet set];
    CGFloat footerY = _item.pollFooterOwnRow ? _item.pollFooterY : _item.timeOrigin.y;
    ExteriaDrawStringAt(_item.pollFooterText, ExteriaFontRegular(12), CGPointMake(PAD_X_POLL + ExteriaPollVotersWidth(MIN(_item.pollVoterPeople.count, (NSUInteger)3)), footerY));
}

/* the comments of a post: a hairline over the row, the newest commenters' pictures at the left (views of their own), the count in the
   accent color, and a chevron at the right end */
- (void)drawCommentsRow:(CGContextRef)context {
    CGRect row = _item.commentsFrame;
    BOOL outgoing = _item.message.outgoing;
    [[ExteriaColorBubbleMeta(outgoing) colorWithAlphaComponent:0.25] setFill];
    CGContextFillRect(context, CGRectMake(row.origin.x + PAD_X_COMMENTS, row.origin.y, row.size.width - 2 * PAD_X_COMMENTS, 1.0 / ExteriaScreenScale()));
    NSUInteger shown = MIN(_item.commenterPeople.count, (NSUInteger)3);
    CGFloat textX = row.origin.x + PAD_X_COMMENTS + (shown ? COMMENTER_SIDE + (CGFloat)(shown - 1) * COMMENTER_STEP + 8 : 0);
    UIColor *accent = ExteriaColorBubbleLink(outgoing);
    [accent set];
    CGSize text = ExteriaStringSize(_item.commentsText, ExteriaFontSemibold(14));
    ExteriaDrawStringAt(_item.commentsText, ExteriaFontSemibold(14), CGPointMake(textX, row.origin.y + (row.size.height - text.height) / 2));
    UIImage *chevron = ExteriaSymbolImage(ExteriaSymbolChevronRight, 14, accent);
    [chevron drawAtPoint:CGPointMake(CGRectGetMaxX(row) - PAD_X_COMMENTS - chevron.size.width, row.origin.y + (row.size.height - chevron.size.height) / 2)];
}

- (void)drawOverlay:(CGContextRef)context {
    CGRect capsule = CGRectMake(0, 0, _item.timeSize.width, _item.timeSize.height);
    ExteriaFillCapsule(context, capsule, ExteriaColorBubbleCapsule());
    [self drawMetaAt:CGPointMake(5, 2.5) color:[UIColor whiteColor] context:context];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_item) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    NSUInteger misses = ExteriaEmojiMissCount();
    if (_layerKind == ExteriaBubbleLayerReply) [self drawReply];
    else if (_layerKind == ExteriaBubbleLayerOverlay) [self drawOverlay:context];
    else if (_item.kind == ExteriaChatItemPill && !_item.giftCard) [self drawPill:context];
    else if (_item.kind == ExteriaChatItemBubble) [self drawBody:context];
    else if (_item.commentsText.length) {
        CGRect row = _item.commentsFrame;
        [(_item.message.outgoing ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn()) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:row cornerRadius:ExteriaBubbleRadius()] fill];
        [self drawCommentsRow:context];
    }
    if (ExteriaEmojiMissCount() != misses) ExteriaEmojiRedrawWhenLoaded(self);
    /* a sticker has no bubble, its picture and the time capsule over it are other views */
}

@end

/* the spoiler over a photo or a video its sender hid */
#define SPOILER_FPS_INTERVAL 2
#define SPOILER_SPECK 1.4
#define SPOILER_LEVELS 3

@interface ExteriaSpoilerTicker : NSObject {
    ExteriaWeakReference *_target;
}
- (id)initWithTarget:(id)target;
- (void)tick:(CADisplayLink *)link;
@end

@interface ExteriaSpoilerCover : UIView {
    UIImageView *_source;
    UIImage *_blurred;
    UIImage *_blurredFrom;
    CADisplayLink *_link;
    ExteriaSpoilerTicker *_ticker;
    CGPoint *_position;
    CGPoint *_motion;
    float *_age;
    float *_life;
    uint8_t *_level;
    NSUInteger _count;
    CFTimeInterval _last;
    BOOL _revealing;
    CFTimeInterval _revealStart;
    CFTimeInterval _revealLength;
    CGPoint _revealCenter;
    CGFloat _revealReach;
    void (^_revealDone)(void);
}
/* the picture that is covered; its image is blurred for the plate and follows it when it arrives late */
@property (nonatomic, assign) UIImageView *source;
/* lifts the cover from a point in its own coordinates, and runs done when the circle has covered it all */
- (void)revealFromPoint:(CGPoint)point done:(void (^)(void))done;
- (void)step:(CADisplayLink *)link;
@end

@implementation ExteriaSpoilerTicker
- (id)initWithTarget:(id)target {
    self = [super init];
    if (!self) return nil;
    _target = [[ExteriaWeakReference referenceTo:target] retain];
    return self;
}
- (void)dealloc {
    [_target release];
    [super dealloc];
}
- (void)tick:(CADisplayLink *)link {
    [(ExteriaSpoilerCover *)_target.target step:link];
}
@end

@implementation ExteriaSpoilerCover

@synthesize source = _source;

static float ExteriaSpoilerRandom(void) {
    return (float)arc4random() / 4294967296.0f;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.clipsToBounds = YES;
    self.contentMode = UIViewContentModeRedraw;
    _ticker = [[ExteriaSpoilerTicker alloc] initWithTarget:self];
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_ticker release];
    [_blurred release];
    [_blurredFrom release];
    [_revealDone release];
    free(_position);
    free(_motion);
    free(_age);
    free(_life);
    free(_level);
    [super dealloc];
}

/* a speck starts somewhere in the plate and goes off at a speed of eight to twenty points a second in a direction of its own */
- (void)respawn:(NSUInteger)index {
    CGSize size = self.bounds.size;
    float angle = ExteriaSpoilerRandom() * 2 * (float)M_PI;
    float speed = (4 + ExteriaSpoilerRandom() * 6) * 2;
    _position[index] = CGPointMake(ExteriaSpoilerRandom() * (float)size.width, ExteriaSpoilerRandom() * (float)size.height);
    _motion[index] = CGPointMake(cosf(angle) * speed, sinf(angle) * speed);
    _age[index] = 0;
    _life[index] = 1 + ExteriaSpoilerRandom() * 2;
    _level[index] = (uint8_t)(arc4random() % SPOILER_LEVELS);
}

/* a speck for about every hundred and fifty square points, as many as an old phone draws at thirty frames */
- (void)resizeSwarm {
    CGSize size = self.bounds.size;
    NSUInteger want = (NSUInteger)MIN(450.0, MAX(0.0, size.width * size.height / 150.0));
    if (want == _count) return;
    free(_position); free(_motion); free(_age); free(_life); free(_level);
    _count = want;
    _position = calloc(want ? want : 1, sizeof(CGPoint));
    _motion = calloc(want ? want : 1, sizeof(CGPoint));
    _age = calloc(want ? want : 1, sizeof(float));
    _life = calloc(want ? want : 1, sizeof(float));
    _level = calloc(want ? want : 1, sizeof(uint8_t));
    if (!_position || !_motion || !_age || !_life || !_level) {
        _count = 0;
        return;
    }
    for (NSUInteger i = 0; i < want; ++i) {
        [self respawn:i];
        /* the first frame has them at every point of their life, so the swarm does not pulse in step */
        _age[i] = ExteriaSpoilerRandom() * _life[i];
    }
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self resizeSwarm];
}

- (BOOL)animates {
    return ExteriaLiteEnabled(EXTERIA_LITE_CHAT_SPOILER) && !ExteriaReduceMotionEnabled();
}

- (void)updateLink {
    BOOL run = self.window && !self.hidden && (_revealing || [self animates]);
    if (run && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:_ticker selector:@selector(tick:)];
        _link.frameInterval = SPOILER_FPS_INTERVAL;
        _last = 0;
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else if (!run && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateLink];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updateLink];
}

- (void)step:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CFTimeInterval dt = _last ? MIN(0.1, now - _last) : 0;
    _last = now;
    CGSize size = self.bounds.size;
    for (NSUInteger i = 0; i < _count; ++i) {
        _age[i] += (float)dt;
        _position[i].x += _motion[i].x * (float)dt;
        _position[i].y += _motion[i].y * (float)dt;
        if (_age[i] >= _life[i] || _position[i].x < 0 || _position[i].y < 0 || _position[i].x > size.width || _position[i].y > size.height) [self respawn:i];
    }
    if (_revealing && now - _revealStart >= _revealLength) {
        _revealing = NO;
        void (^done)(void) = [_revealDone retain];
        [_revealDone release];
        _revealDone = nil;
        [self updateLink];
        if (done) done();
        [done release];
        return;
    }
    [self setNeedsDisplay];
}

- (void)revealFromPoint:(CGPoint)point done:(void (^)(void))done {
    CGSize size = self.bounds.size;
    CGFloat reach = 0;
    CGPoint corners[4] = {CGPointMake(0, 0), CGPointMake(size.width, 0), CGPointMake(0, size.height), CGPointMake(size.width, size.height)};
    for (int i = 0; i < 4; ++i) reach = MAX(reach, hypot(corners[i].x - point.x, corners[i].y - point.y));
    _revealCenter = point;
    _revealReach = reach;
    /* the time: three tenths of a millisecond for each point of reach, between a quarter and just over half a
       second */
    _revealLength = MIN(550.0, MAX(250.0, reach * 0.3)) / 1000.0;
    _revealStart = CACurrentMediaTime();
    _revealing = YES;
    [_revealDone release];
    _revealDone = [done copy];
    [self updateLink];
    [self setNeedsDisplay];
}

/* the picture shrunk to a few dozen points and drawn large again with smoothing, which is a blur that costs nothing at draw time */
- (UIImage *)blurredPlate {
    UIImage *image = _source.image;
    if (!image || !ExteriaLiteEnabled(EXTERIA_LITE_CHAT_BLUR)) return nil;
    if (image == _blurredFrom && _blurred) return _blurred;
    CGSize size = image.size;
    if (size.width < 1 || size.height < 1) return nil;
    CGFloat scale = MIN(1, 28.0 / MAX(size.width, size.height));
    CGSize small = CGSizeMake(MAX(2, floor(size.width * scale)), MAX(2, floor(size.height * scale)));
    UIGraphicsBeginImageContextWithOptions(small, YES, 1);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [image drawInRect:CGRectMake(0, 0, small.width, small.height)];
    UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [_blurred release];
    _blurred = [made retain];
    [_blurredFrom release];
    _blurredFrom = [image retain];
    return _blurred;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat progress = 0;
    CGContextSaveGState(context);
    if (_revealing) {
        progress = MIN(1, (CACurrentMediaTime() - _revealStart) / _revealLength);
        /* what stays is everything outside the circle that grows from the finger */
        CGContextBeginPath(context);
        CGContextAddRect(context, bounds);
        CGContextAddEllipseInRect(context, CGRectMake(_revealCenter.x - _revealReach * progress, _revealCenter.y - _revealReach * progress,
                                                      2 * _revealReach * progress, 2 * _revealReach * progress));
        CGContextEOClip(context);
    }
    UIImage *plate = [self blurredPlate];
    if (plate) {
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        /* the plate fills the frame the way the picture does, cropped at its long side */
        CGFloat fill = MAX(bounds.size.width / plate.size.width, bounds.size.height / plate.size.height);
        CGSize drawn = CGSizeMake(plate.size.width * fill, plate.size.height * fill);
        [plate drawInRect:CGRectMake((bounds.size.width - drawn.width) / 2, (bounds.size.height - drawn.height) / 2, drawn.width, drawn.height)];
        [[UIColor colorWithWhite:0 alpha:0.28] setFill];
        CGContextFillRect(context, bounds);
    } else {
        [[UIColor colorWithRed:0.18 green:0.19 blue:0.22 alpha:1] setFill];
        CGContextFillRect(context, bounds);
    }
    static const CGFloat strengths[SPOILER_LEVELS] = {0.3, 0.6, 1.0};
    for (int level = 0; level < SPOILER_LEVELS; ++level) {
        [[UIColor colorWithWhite:1 alpha:strengths[level] * (1 - progress)] setFill];
        for (NSUInteger i = 0; i < _count; ++i) {
            if (_level[i] != level) continue;
            CGContextFillRect(context, CGRectMake(_position[i].x, _position[i].y, SPOILER_SPECK, SPOILER_SPECK));
        }
    }
    CGContextRestoreGState(context);
}

@end

@interface ExteriaMessageCell () <UIGestureRecognizerDelegate> {
    ExteriaSpoilerCover *_spoilerCover;
    /* the band that lights the row of a message the list scrolled to */
    UIView *_flash;
    UIPanGestureRecognizer *_swipe;
    UIPanGestureRecognizer *_seekPan;
    UIView *_swipeDisc;
    BOOL _swipeCrossed;
    UIControl *_selectCover;
    UIView *_selectMark;
    UIImageView *_selectCheck;
    BOOL _selecting;
    BOOL _selected;
    ExteriaChatItem *_item;
    ExteriaBubbleView *_body;
    ExteriaBubbleView *_replyPreview;
    ExteriaBubbleView *_overlay;
    UIImageView *_picture;
    ExteriaMapView *_map;
    UILabel *_gifLabel;
    /* the button over a video, a round message and a picture that is still on its way */
    ExteriaMediaActionView *_play;
    /* the button of a voice note or a song, at the front of its row */
    ExteriaMediaActionView *_voiceAction;
    ExteriaRoundVideoView *_gifView;
    AVPlayer *_gifPlayer;
    AVPlayerItem *_gifItem;
    NSURL *_gifURL;
    BOOL _gifFailed;
    BOOL _gifPlayRequested;
    /* the file behind the button: where it is once it is here, the request that brings it, and what a tap does when it arrives */
    NSString *_loadedPath;
    NSUInteger _loadRequest;
    NSUInteger _loadToken;
    BOOL _loadAsked;
    BOOL _loadFailed;
    float _loadProgress;
    BOOL _playWhenLoaded;
    BOOL _photoLoadShown;
    ExteriaLottieView *_lottie;
    ExteriaGiftCardView *_giftCardView;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickerLibrary;
    BOOL _emojiPlayed;
    BOOL _replayRequested;
    BOOL _animationLoading;
    ExteriaAvatarView *_avatar;
    UIButton *_avatarButton;
    UIButton *_senderButton;
    ExteriaAvatarCache *_avatars;
    NSUInteger _token;
    BOOL _animating;
    ExteriaRoundVideoView *_roundView;
    AVPlayer *_roundPlayer;
    AVPlayerItem *_roundItem;
    UIButton *_roundSpeed;
    CAShapeLayer *_roundRing;
    NSTimer *_roundTimer;
    NSUInteger _roundToken;
    ExteriaReactionsView *_reactions;
    int32_t _reactionsMessageId;
    NSString *_reactionsKey;
    /* the pictures of an album, one view each, made as albums come and shown as far as the album has pictures */
    NSMutableArray *_albumViews;
    NSMutableArray *_albumMarks;
    ExteriaMessage *_tappedMedia;
    UITapGestureRecognizer *_doubleTap;
    ExteriaMarkupView *_markupView;
    NSMutableArray *_commenters;
    NSMutableArray *_pollVoters;
    UIButton *_share;
    UIButton *_sharingAccept;
    UIButton *_sharingDecline;
    ExteriaWeakReference *_weak;
    BOOL _activationDeferred;
    /* the sticker file that arrived while activation was deferred */
    NSData *_pendingLottie;
    NSString *_pendingLottieKey;
}
@end

@implementation ExteriaMessageCell

@synthesize delegate = _delegate;
@synthesize item = _item;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _body = [[ExteriaBubbleView alloc] init];
    [self.contentView addSubview:_body];
    _replyPreview = [[ExteriaBubbleView alloc] init];
    _replyPreview.layerKind = ExteriaBubbleLayerReply;
    _replyPreview.userInteractionEnabled = NO;
    [self.contentView addSubview:_replyPreview];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES;
    _avatar.hidden = YES;
    [self.contentView addSubview:_avatar];
    _avatarButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_avatarButton addTarget:self action:@selector(senderTapped:event:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_avatarButton];
    _senderButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_senderButton addTarget:self action:@selector(senderTapped:event:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_senderButton];
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    [self.contentView addSubview:_picture];
    _play = [[ExteriaMediaActionView alloc] initWithFrame:CGRectMake(0, 0, MEDIA_BUTTON, MEDIA_BUTTON)];
    _play.hidden = YES;
    [self.contentView addSubview:_play];
    _voiceAction = [[ExteriaMediaActionView alloc] initWithFrame:CGRectMake(0, 0, VOICE_BUTTON, VOICE_BUTTON)];
    _voiceAction.hidden = YES;
    [self.contentView addSubview:_voiceAction];
    _overlay = [[ExteriaBubbleView alloc] init];
    _overlay.layerKind = ExteriaBubbleLayerOverlay;
    [self.contentView addSubview:_overlay];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _reactions = [[ExteriaReactionsView alloc] init];
    ExteriaWeakReference *weak = _weak;
    _reactions.pickHandler = ^(ExteriaReaction *reaction) {
        ExteriaMessageCell *cell = weak.target;
        if (cell) [cell.delegate messageCell:cell didTapReaction:reaction];
    };
    [self.contentView addSubview:_reactions];
    UILongPressGestureRecognizer *press = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)] autorelease];
    [self.contentView addGestureRecognizer:press];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    tap.cancelsTouchesInView = NO;
    [tap requireGestureRecognizerToFail:press];
    [self.contentView addGestureRecognizer:tap];
    /* off while the chat has no double tap action, since a recognizer that waits for a second tap would hold every single tap back */
    _doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    _doubleTap.numberOfTapsRequired = 2;
    _doubleTap.enabled = NO;
    [self.contentView addGestureRecognizer:_doubleTap];
    [tap requireGestureRecognizerToFail:_doubleTap];
    /* the disc appears on the right as the row is pulled left */
    _swipeDisc = [[UIView alloc] initWithFrame:CGRectMake(0, 0, SWIPE_DISC, SWIPE_DISC)];
    _swipeDisc.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    _swipeDisc.layer.cornerRadius = SWIPE_DISC / 2;
    _swipeDisc.userInteractionEnabled = NO;
    _swipeDisc.alpha = 0;
    UIImageView *arrow = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolReply, 18, [UIColor whiteColor])] autorelease];
    arrow.center = CGPointMake(SWIPE_DISC / 2, SWIPE_DISC / 2);
    [_swipeDisc addSubview:arrow];
    [self insertSubview:_swipeDisc belowSubview:self.contentView];
    /* while messages are picked a clear cover takes every touch of the row, so no link, button or player under it answers */
    _selectCover = [[UIControl alloc] init];
    _selectCover.hidden = YES;
    [_selectCover addTarget:self action:@selector(selectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_selectCover];
    _selectMark = [[UIView alloc] initWithFrame:CGRectMake(0, 0, SELECT_MARK, SELECT_MARK)];
    _selectMark.layer.cornerRadius = SELECT_MARK / 2;
    _selectMark.layer.borderWidth = 2;
    _selectMark.userInteractionEnabled = NO;
    _selectMark.hidden = YES;
    _selectCheck = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolCheck, 14, [UIColor whiteColor])];
    _selectCheck.contentMode = UIViewContentModeCenter;
    _selectCheck.frame = _selectMark.bounds;
    [_selectMark addSubview:_selectCheck];
    [self addSubview:_selectMark];
    _swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    _swipe.delegate = self;
    [self.contentView addGestureRecognizer:_swipe];
    _seekPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(seekDragged:)];
    _seekPan.delegate = self;
    [self.contentView addGestureRecognizer:_seekPan];
    [_swipe requireGestureRecognizerToFail:_seekPan];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerTicked:) name:ExteriaMusicPlayerDidTickNotification object:nil];
    return self;
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    if (_roundSpeed) [self applyRoundSpeed];
    exteria_preview_kind kind = _item.message.media.kind;
    if (kind == EXTERIA_PREVIEW_AUDIO || kind == EXTERIA_PREVIEW_VOICE) {
        [_body setNeedsDisplay];
        [self syncVoiceActionAnimated:YES];
    }
}

/* the bars of the note that plays fill as it goes */
- (void)playerTicked:(NSNotification *)note {
    (void)note;
    if (_item.message.media.kind == EXTERIA_PREVIEW_VOICE && [[ExteriaMusicPlayer sharedPlayer] isCurrentTrack:_item.message.media]) [_body setNeedsDisplay];
}

/* the round message that plays now; only one does, and it stops the song and the other round message */
static ExteriaMessageCell *sPlayingRound = nil;

- (void)dealloc {
    [_weak clear];
    [self stopGif];
    _swipe.delegate = nil;
    [_swipe release];
    _seekPan.delegate = nil;
    [_seekPan release];
    [_swipeDisc release];
    [_flash release];
    [_selectCover release];
    [_selectMark release];
    [_selectCheck release];
    [_markupView release];
    [self stopRound];
    [self cancelMediaLoad];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_reactions release];
    [_reactionsKey release];
    [_albumViews release];
    [_albumMarks release];
    [_tappedMedia release];
    [_spoilerCover release];
    [_doubleTap release];
    [_commenters release];
    [_pollVoters release];
    [_share release];
    [_sharingAccept release];
    [_sharingDecline release];
    [_item release];
    [_body release];
    [_replyPreview release];
    [_overlay release];
    [_picture release];
    [_map release];
    [_gifLabel release];
    [_play release];
    [_voiceAction release];
    [_loadedPath release];
    [_giftCardView release];
    [_lottie release];
    [_pendingLottie release];
    [_pendingLottieKey release];
    [_media release];
    [_stickerLibrary release];
    [_avatar release];
    [_avatarButton release];
    [_senderButton release];
    [_avatars release];
    [super dealloc];
}

/* an emoji or sticker that can play, also before its file arrives, so the visible ones start when it does */
- (BOOL)animatedSticker {
    if (_item.message.media.kind == EXTERIA_PREVIEW_GIF) return _item.content == ExteriaChatItemContentPicture && _item.message.media.file && !_gifFailed && (_gifPlayRequested || [self playsOnItsOwn]) && ![self spoilerHidesItem:_item];
    return [self playsOnItsOwn] && (_item.kind == ExteriaChatItemEmoji || (_item.kind == ExteriaChatItemSticker &&
        (_item.message.media.stickerFormat == EXTERIA_STICKER_ANIMATED || _item.message.media.stickerFormat == EXTERIA_STICKER_VIDEO) && _item.message.media.file != nil));
}

/* the power saving settings decide whether stickers and the big emoji play as they come into view; when they do not, the picture stands still and a tap plays
   it once */
- (BOOL)playsOnItsOwn {
    if (_item.message.media.kind == EXTERIA_PREVIEW_GIF) return !ExteriaReduceMotionEnabled() && ExteriaLiteEnabled(EXTERIA_LITE_AUTOPLAY_GIFS);
    return ExteriaLiteEnabled(_item.kind == ExteriaChatItemEmoji ? EXTERIA_LITE_EMOJI_CHAT : EXTERIA_LITE_STICKERS_CHAT);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    /* the slide of a new message runs on the layer of the cell, and a cell taken for another row in the middle of it would carry the slide to that row */
    ExteriaCancelEnter(self);
    [self hideAlbumViews];
    [self resetSwipe];
    [self stopGif];
    [self stopRound];
    [self cancelMediaLoad];
    ++_token;
    [self discardLottie];
    [_giftCardView discard];
    _giftCardView.hidden = YES;
    _animationLoading = NO;
    _animating = NO;
    _gifPlayRequested = NO;
    _gifLabel.hidden = YES;
    _picture.image = nil;
    [_map cancelTiles]; _map.hidden=YES;
    _markupView.hidden = YES;
}

/* where a photo stands while it loads: a quiet tint of the bubble it will sit in */
- (UIColor *)placeholderColor {
    return ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.08] : [UIColor colorWithWhite:0 alpha:0.06];
}

/* the files behind the picture of a row: the picture itself, and the preview that stands in while there is none;
   the cell that shows a row and the preparation ahead of it both ask here */
static void ExteriaPictureSources(ExteriaChatItem *item, ExteriaRemoteFile **file, ExteriaRemoteFile **preview) {
    ExteriaMedia *content = item.message.media;
    *file = nil;
    *preview = nil;
    if (item.kind == ExteriaChatItemSticker) {
        if (content.stickerFormat == EXTERIA_STICKER_STATIC && content.file) *file = content.file;
        *preview = content.previewFile;
        if (!*file && !*preview) *preview = content.file;
    } else if (item.kind == ExteriaChatItemRound) {
        *preview = content.previewFile;
    } else if (item.content == ExteriaChatItemContentPicture) {
        if (content.kind != EXTERIA_PREVIEW_PHOTO) *preview = content.previewFile;
        else *file = content.file;
    }
}

static CGFloat ExteriaPictureSide(ExteriaChatItem *item) {
    return MAX(item.pictureFrame.size.width, item.pictureFrame.size.height) * ExteriaScreenScale();
}

+ (void)prepareItem:(ExteriaChatItem *)item media:(ExteriaMediaCache *)media {
    ExteriaRemoteFile *file = nil;
    ExteriaRemoteFile *preview = nil;
    ExteriaPictureSources(item, &file, &preview);
    ExteriaRemoteFile *shown = file ? file : preview;
    if (shown) [media prepareImageForFile:shown maxSide:ExteriaPictureSide(item)];
}

/* a hidden picture is covered at its frame until it is tapped; an album and the other kinds of content have no such cover */
- (BOOL)spoilerHidesItem:(ExteriaChatItem *)item {
    ExteriaMessage *message = item.message;
    if (item.content != ExteriaChatItemContentPicture || item.albumFrames.count || message.spoilersRevealed) return NO;
    ExteriaOutgoing *pending = message.pendingSend;
    return message.media.spoiler || (pending && pending->spoiler);
}

- (void)refreshSpoilerCoverForItem:(ExteriaChatItem *)item {
    if (![self spoilerHidesItem:item]) {
        _spoilerCover.hidden = YES;
        return;
    }
    if (!_spoilerCover) {
        _spoilerCover = [[ExteriaSpoilerCover alloc] init];
        _spoilerCover.source = _picture;
    }
    _spoilerCover.frame = _picture.frame;
    _spoilerCover.layer.cornerRadius = _picture.layer.cornerRadius;
    _spoilerCover.hidden = NO;
    _spoilerCover.alpha = 1;
    [self.contentView insertSubview:_spoilerCover aboveSubview:_picture];
    [_spoilerCover setNeedsDisplay];
}

- (void)loadPictureForItem:(ExteriaChatItem *)item {
    ExteriaRemoteFile *file = nil;
    ExteriaRemoteFile *preview = nil;
    ExteriaPictureSources(item, &file, &preview);
    CGFloat side = ExteriaPictureSide(item);
    NSUInteger token = _token;
    /* a photo or video on its way up shows its own small picture, so the bubble is the picture from the first moment and not a file line */
    UIImage *local = item.message.pendingSend ? item.message.pendingSend->preview : nil;
    if (local && !file && !preview) {
        _picture.image = local;
        [_spoilerCover setNeedsDisplay];
        _picture.backgroundColor = [UIColor clearColor];
        return;
    }
    UIImage *ready = [_media cachedImageForFile:file maxSide:side];
    if (ready) {
        _picture.image = ready;
        [_spoilerCover setNeedsDisplay];
        return;
    }
    _picture.backgroundColor = item.kind == ExteriaChatItemSticker ? [UIColor clearColor] : [self placeholderColor];
    if (preview && !file) {
        [_media loadImageForFile:preview maxSide:side completion:^(UIImage *image) {
            if (token != _token) return;
            if (image) { _picture.image = image; [_spoilerCover setNeedsDisplay]; }
            else if (item.kind == ExteriaChatItemSticker && preview != item.message.media.file) {
                [_media loadImageForFile:item.message.media.file maxSide:side completion:^(UIImage *poster) {
                    if (token == _token && poster) { _picture.image = poster; [_spoilerCover setNeedsDisplay]; }
                }];
            }
        }];
        return;
    }
    /* a photo that takes a moment shows the ring turning on its button; one that comes at once shows nothing, so a scroll does not flash it */
    BOOL ringed = item.content == ExteriaChatItemContentPicture && item.message.media.kind == EXTERIA_PREVIEW_PHOTO;
    if (ringed) [self performSelector:@selector(showPhotoLoading) withObject:nil afterDelay:0.25];
    [_media loadImageForFile:file maxSide:side completion:^(UIImage *image) {
        if (token != _token) return;
        if (image) {
            _picture.image = image;
            [_spoilerCover setNeedsDisplay];
            _picture.backgroundColor = [UIColor clearColor];
        }
        if (ringed) [self photoFinished];
    }];
}

- (void)showPhotoLoading {
    if (_photoLoadShown || _picture.image) return;
    _photoLoadShown = YES;
    [self placeMediaButtonOver:_picture.frame];
    [_play setIcon:ExteriaMediaIconCancel animated:NO];
    [_play setProgress:0];
}

/* the picture is in: the ring and the cross shrink away, and the button leaves when they are gone */
- (void)photoFinished {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showPhotoLoading) object:nil];
    if (!_photoLoadShown) return;
    _photoLoadShown = NO;
    [_play setIcon:ExteriaMediaIconNone animated:YES];
    [self performSelector:@selector(hidePhotoLoading) withObject:nil afterDelay:0.3];
}

- (void)hidePhotoLoading {
    if (_item.kind != ExteriaChatItemRound && _item.message.media.kind == EXTERIA_PREVIEW_PHOTO) _play.hidden = YES;
}

- (void)loadLottieFile:(ExteriaRemoteFile *)file {
    if (!file || _animationLoading || _lottie) return;
    _animationLoading = YES;
    NSUInteger token = _token;
    NSString *key = file.key;
    ExteriaWeakReference *weak = _weak;
    [_media loadDataForFile:file completion:^(NSData *data) {
        ExteriaMessageCell *cell = weak.target;
        if (!cell || token != cell->_token) return;
        cell->_animationLoading = NO;
        if (!data || (ExteriaFileFormatOfData(data) != ExteriaFileFormatGzip && ExteriaFileFormatOfData(data) != ExteriaFileFormatMatroska)) {
            NSLog(@"exteria: animation %@ did not load as tgs or webm", key);
            return;
        }
        if (cell->_activationDeferred) {
            [cell->_pendingLottie release];
            cell->_pendingLottie = [data retain];
            [cell->_pendingLottieKey release];
            cell->_pendingLottieKey = [key copy];
            return;
        }
        [cell showLottieWithData:data key:key];
    }];
}

- (void)loadLottieForItem:(ExteriaChatItem *)item {
    /* the thumbnail fills in until the animation has its first frame */
    [self loadPictureForItem:item];
    [self loadLottieFile:item.message.media.file];
}

/* the outline the person chose for stickers: the picture is clipped to it, and the third shape puts a plate of the bubble's color under the picture */
- (void)applyStickerShape {
    if (_item.kind != ExteriaChatItemSticker) return;
    ExteriaStickerShape shape = ExteriaChatStickerShape();
    CGFloat radius = shape == ExteriaStickerShapeNone ? 0 : (shape == ExteriaStickerShapeRounded ? floor(_picture.frame.size.width * 0.12) : (CGFloat)ExteriaBubbleRadius());
    UIColor *plate = shape == ExteriaStickerShapeBubble ? (_item.message.outgoing ? ExteriaColorBubbleOut() : ExteriaColorBubbleIn()) : [UIColor clearColor];
    _picture.layer.cornerRadius = radius;
    _picture.layer.masksToBounds = YES;
    _picture.backgroundColor = plate;
    _lottie.layer.cornerRadius = radius;
    _lottie.layer.masksToBounds = YES;
    _lottie.backgroundColor = plate;
}

- (void)loadEmojiAnimation {
    if (!_stickerLibrary || _animationLoading || _lottie) return;
    _animationLoading = YES;
    NSUInteger token = _token;
    ExteriaWeakReference *weak = _weak;
    [_stickerLibrary loadAnimationForEmoji:_item.message.text completion:^(ExteriaSticker *sticker, NSString *error) {
        (void)error;
        ExteriaMessageCell *cell = weak.target;
        if (!cell || token != cell->_token) return;
        cell->_animationLoading = NO;
        if (sticker) [cell loadLottieFile:sticker.media.file];
    }];
}

/* parsing the animation and building its renderer is the heaviest step of a sticker row, so it waits out a scroll */
- (void)showLottieWithData:(NSData *)data key:(NSString *)key {
    if (_lottie) return;
    if (ExteriaFileFormatOfData(data) == ExteriaFileFormatMatroska && !_animating) {
        [_pendingLottie release]; _pendingLottie = [data retain];
        [_pendingLottieKey release]; _pendingLottieKey = [key copy];
        return;
    }
    _lottie = [[ExteriaLottieView alloc] initWithPackedData:data key:key];
    NSUInteger token = _token;
    ExteriaWeakReference *weak = _weak;
    _lottie.firstFrameHandler = ^{
        ExteriaMessageCell *cell = weak.target;
        if (cell && token == cell->_token) cell->_picture.hidden = YES;
    };
    _lottie.frame = _picture.frame;
    [_lottie setLoaded:YES];
    [self.contentView insertSubview:_lottie aboveSubview:_picture];
    [self applyStickerShape];
    if (_replayRequested) {
        _replayRequested = NO;
        _emojiPlayed = YES;
        [_lottie playOnce];
    } else [self setAnimating:_animating];
}

- (BOOL)activationDeferred {
    return _activationDeferred;
}

- (void)setActivationDeferred:(BOOL)deferred {
    _activationDeferred = deferred;
    if (!deferred && _animating && _item.message.media.kind == EXTERIA_PREVIEW_GIF) [self startGif];
    if (deferred || !_pendingLottie) return;
    NSData *data = [_pendingLottie autorelease];
    NSString *key = [_pendingLottieKey autorelease];
    _pendingLottie = nil;
    _pendingLottieKey = nil;
    [self showLottieWithData:data key:key];
}

- (void)discardLottie {
    [_pendingLottie release];
    _pendingLottie = nil;
    [_pendingLottieKey release];
    _pendingLottieKey = nil;
    [_lottie removeFromSuperview];
    [_lottie setPlaying:NO];
    [_lottie release];
    _lottie = nil;
}

/* the sender's picture stands at the left edge, level with the bottom of the last bubble of a run */
- (void)configureAvatarForItem:(ExteriaChatItem *)item bubble:(CGRect)bubble {
    _senderButton.hidden = !item.senderPerson || !item.senderName.length || !item.senderLayout;
    _senderButton.frame = CGRectMake(bubble.origin.x + item.senderOrigin.x, bubble.origin.y + item.senderOrigin.y - 3,
        item.senderLayout.size.width, 23);
    _senderButton.accessibilityLabel = item.senderName;
    _avatarButton.hidden = !item.showsAvatar || !item.senderPerson;
    _avatarButton.accessibilityLabel = item.senderName;
    if (!item.showsAvatar || item.kind == ExteriaChatItemPill) {
        _avatar.hidden = YES;
        return;
    }
    ExteriaPerson *person = item.senderPerson;
    _avatar.hidden = NO;
    _avatar.frame = CGRectMake(8, CGRectGetMaxY(bubble) - 34, 34, 34);
    _avatarButton.frame = CGRectInset(_avatar.frame, -4, -4);
    _avatar.seed = (NSUInteger)(llabs(item.message.senderKey) % 1000003);
    _avatar.initials = person.initials;
    _avatar.deleted = person.deleted;
    [_avatar setPhoto:person.photo cache:_avatars];
}

- (void)senderTapped:(UIControl *)control event:(UIEvent *)event {
    /* the marks are the last of the name, and a tap on one says why it is there instead of opening the profile */
    if (_item.senderDeveloper && control == _senderButton) {
        CGPoint point = [[[event touchesForView:control] anyObject] locationInView:control];
        point.y -= 3;
        NSUInteger mark = ExteriaMarkForDocument([_item.senderLayout customEmojiAtPoint:point]);
        if (mark) {
            ExteriaShowMarkNotice(_item.senderName, mark);
            return;
        }
    }
    [_delegate messageCellDidTapSender:self];
}

/* the pictures of the last voters of a public poll stand before the count of votes, in views made when the first such poll needs them */
- (void)configurePollVotersForItem:(ExteriaChatItem *)item bubble:(CGRect)bubble {
    NSUInteger shown = item.content == ExteriaChatItemContentPoll ? MIN(item.pollVoterPeople.count, (NSUInteger)3) : 0;
    if (shown && !_pollVoters) {
        _pollVoters = [[NSMutableArray alloc] init];
        for (int i = 0; i < 3; ++i) {
            ExteriaAvatarView *view = [[[ExteriaAvatarView alloc] init] autorelease];
            view.circular = YES;
            [self.contentView addSubview:view];
            [_pollVoters addObject:view];
        }
    }
    CGFloat footerY = item.pollFooterOwnRow ? item.pollFooterY : item.timeOrigin.y;
    for (NSUInteger i = 0; i < _pollVoters.count; ++i) {
        ExteriaAvatarView *view = [_pollVoters objectAtIndex:i];
        view.hidden = i >= shown;
        if (i >= shown) continue;
        ExteriaPerson *person = [item.pollVoterPeople objectAtIndex:i];
        view.frame = CGRectMake(bubble.origin.x + PAD_X_POLL + (CGFloat)i * EXTERIA_POLL_VOTER_STEP,
                                bubble.origin.y + footerY + (META_HEIGHT_POLL - EXTERIA_POLL_VOTER_SIDE) / 2, EXTERIA_POLL_VOTER_SIDE, EXTERIA_POLL_VOTER_SIDE);
        view.seed = (NSUInteger)(person.userId % 1000003);
        view.initials = person.initials;
        view.deleted = person.deleted;
        [view setPhoto:person.photo cache:_avatars];
    }
}

/* what a channel post adds around its bubble: the pictures of the newest commenters on its comments row, and the
   round share button on the right */
- (void)configurePostExtrasForItem:(ExteriaChatItem *)item bubble:(CGRect)bubble {
    NSUInteger shown = item.commentsText.length ? MIN(item.commenterPeople.count, (NSUInteger)3) : 0;
    if (shown && !_commenters) {
        _commenters = [[NSMutableArray alloc] init];
        for (int i = 0; i < 3; ++i) {
            ExteriaAvatarView *view = [[[ExteriaAvatarView alloc] init] autorelease];
            view.circular = YES;
            [self.contentView addSubview:view];
            [_commenters addObject:view];
        }
    }
    for (NSUInteger i = 0; i < _commenters.count; ++i) {
        ExteriaAvatarView *view = [_commenters objectAtIndex:i];
        view.hidden = i >= shown;
        if (i >= shown) continue;
        ExteriaPerson *person = [item.commenterPeople objectAtIndex:i];
        CGRect row = item.commentsFrame;
        view.frame = CGRectMake(bubble.origin.x + row.origin.x + PAD_X_COMMENTS + (CGFloat)i * COMMENTER_STEP,
                                bubble.origin.y + row.origin.y + (row.size.height - COMMENTER_SIDE) / 2, COMMENTER_SIDE, COMMENTER_SIDE);
        view.seed = (NSUInteger)(person.userId % 1000003);
        view.initials = person.initials;
        view.deleted = person.deleted;
        [view setPhoto:person.photo cache:_avatars];
    }
    if (item.showsShare && !_share) {
        _share = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _share.backgroundColor = ExteriaColorBubbleCapsule();
        _share.layer.cornerRadius = 16;
        [_share setImage:ExteriaSymbolImage(ExteriaSymbolShare, 16, [UIColor whiteColor]) forState:UIControlStateNormal];
        [_share addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_share];
    }
    _share.hidden = !item.showsShare;
    if (item.showsShare) _share.frame = CGRectOffset(item.shareFrame, bubble.origin.x, bubble.origin.y);
}

/* the keyboard under a bot's message is a view made when the first such row needs it, hidden for every other row */
- (void)configureMarkupForItem:(ExteriaChatItem *)item {
    if (!item.markup) {
        _markupView.hidden = YES;
        return;
    }
    if (!_markupView) {
        _markupView = [[ExteriaMarkupView alloc] init];
        ExteriaWeakReference *weak = _weak;
        _markupView.pressHandler = ^(ExteriaMarkupButton *button) {
            ExteriaMessageCell *cell = weak.target;
            if (cell) [cell.delegate messageCell:cell didPressButton:button];
        };
        [self.contentView addSubview:_markupView];
    }
    _markupView.hidden = NO;
    _markupView.frame = item.markupFrame;
    [_markupView setMarkup:item.markup frames:item.markupButtons];
}

- (void)setBusyMarkupButton:(ExteriaMarkupButton *)button {
    [_markupView setBusyButton:button];
}

- (void)configureWithItem:(ExteriaChatItem *)item media:(ExteriaMediaCache *)media avatars:(ExteriaAvatarCache *)avatars {
    [self resetSwipe];
    BOOL sameFile = _item && [_item isSameRowAs:item] && _item.message.media.kind == item.message.media.kind &&
        [_item.message.media.file.key isEqualToString:item.message.media.file.key];
    BOOL keepMedia = sameFile && (_loadRequest || _loadedPath || _gifPlayer || _lottie);
    BOOL played = _item && [_item isSameRowAs:item] && _emojiPlayed;
    if (!keepMedia) {
        ++_token;
        [self stopGif];
        [self stopRound];
        [self cancelMediaLoad];
        [self discardLottie];
        _gifFailed = NO;
        _gifPlayRequested = NO;
        _animationLoading = NO;
        _animating = NO;
    }
    _emojiPlayed = played;
    _replayRequested = NO;
    [item retain];
    [_item release];
    _item = item;
    /* a kept message the other side deleted is faded, if the person likes it so */
    self.contentView.alpha = item.message.deletedLocally && ExteriaChatFlagGet(ExteriaChatFlagAyuTranslucent) ? 0.75f : 1.0f;
    _body.alpha = 1;
    [_flash.layer removeAllAnimations];
    _flash.alpha = 0;
    [_media release];
    _media = [media retain];
    [_avatars release];
    _avatars = [avatars retain];
    CGRect bubble = item.bubbleFrame;
    [self configureAvatarForItem:item bubble:bubble];
    _body.item = item;
    _replyPreview.item = item;
    _replyPreview.hidden = item.kind == ExteriaChatItemBubble || CGRectIsEmpty(item.replyFrame);
    _replyPreview.frame = CGRectOffset(item.replyFrame, bubble.origin.x, bubble.origin.y);
    [_replyPreview setNeedsDisplay];
    /* a classic bubble ends its run with a tail, which takes a few points beside it */
    CGFloat tail = ExteriaThemeIsClassic() && item.kind == ExteriaChatItemBubble && !item.joinsNext && !ExteriaChatFlagGet(ExteriaChatFlagRemoveTail) ? CLASSIC_TAIL : 0;
    _body.tailWidth = tail;
    CGRect bodyFrame = bubble;
    if (item.kind != ExteriaChatItemBubble && !CGRectIsEmpty(item.commentsFrame)) {
        bodyFrame.origin.x += MIN(0, item.commentsFrame.origin.x);
        bodyFrame.size.width = MAX(CGRectGetMaxX(bubble), bubble.origin.x + CGRectGetMaxX(item.commentsFrame)) - bodyFrame.origin.x;
        bodyFrame.size.height = CGRectGetMaxY(item.commentsFrame);
    }
    bodyFrame.size.width += tail;
    if (!item.message.outgoing) bodyFrame.origin.x -= tail;
    _body.frame = bodyFrame;
    _body.bounds = CGRectMake(bodyFrame.origin.x - bubble.origin.x + (!item.message.outgoing ? tail : 0), 0, bodyFrame.size.width, bodyFrame.size.height);
    [_body setNeedsDisplay];
    _picture.hidden = YES;
    _map.hidden = YES;
    if (item.message.media.kind != EXTERIA_PREVIEW_LOCATION) [_map cancelTiles];
    _gifLabel.hidden = YES;
    _spoilerCover.hidden = YES;
    [self hideAlbumViews];
    if (!keepMedia) _picture.image = nil;
    _picture.layer.cornerRadius = 0;
    _play.hidden = YES;
    _voiceAction.hidden = YES;
    _overlay.hidden = YES;
    _doubleTap.enabled = item.message && item.kind != ExteriaChatItemPill && item.message.messageId > 0 && ExteriaChatDoubleTap(item.message.outgoing) != ExteriaDoubleTapNone;
    _reactions.avatars = avatars;
    /* a chip pops in only when this same message got a reaction while it was on screen, not when a reused row is filled with another message */
    NSString *reactionKey = [item.message.reactionKey copy];
    BOOL reactionsChanged = _reactionsMessageId == item.message.messageId && item.message.messageId > 0 && _reactionsKey && ![_reactionsKey isEqualToString:reactionKey ? reactionKey : @""];
    [_reactionsKey release];
    _reactionsKey = [(reactionKey ? reactionKey : @"") copy];
    _reactionsMessageId = item.message.messageId;
    [reactionKey release];
    _reactions.inBubble = item.reactionsInside;
    _reactions.outgoing = item.message.outgoing;
    [_reactions setReactions:[item shownReactions] counts:YES animated:reactionsChanged];
    _reactions.alignRight = item.message.outgoing && !item.reactionsInside && !item.giftCard;
    _reactions.frame = item.reactionFrame;
    _reactions.hidden = ![item shownReactions].count && !_reactions.animatingOut;
    [self configureMarkupForItem:item];
    [self configurePostExtrasForItem:item bubble:bubble];
    [self configurePollVotersForItem:item bubble:bubble];
    if (item.giftCard) {
        if (!_giftCardView) {
            _giftCardView = [[ExteriaGiftCardView alloc] init];
            [self.contentView addSubview:_giftCardView];
        }
        _giftCardView.hidden = NO;
        _giftCardView.frame = item.bubbleFrame;
        [_giftCardView configureWithLayout:item.giftCard media:media];
        [_giftCardView setActive:_animating];
    } else _giftCardView.hidden = YES;
    BOOL sharingOffer = item.message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1 && !item.message.outgoing && !item.sharingExpired && item.message.messageId > 0;
    if (sharingOffer && !_sharingAccept) {
        _sharingAccept = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _sharingDecline = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        for (UIButton *button in [NSArray arrayWithObjects:_sharingDecline, _sharingAccept, nil]) {
            button.titleLabel.font = ExteriaFontMedium(13);
            button.backgroundColor = ExteriaColorAccent();
            button.layer.cornerRadius = 8;
            [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [self.contentView addSubview:button];
        }
        [_sharingAccept setTitle:NSLocalizedString(@"chat.sharing.accept", nil) forState:UIControlStateNormal];
        [_sharingDecline setTitle:NSLocalizedString(@"chat.sharing.decline", nil) forState:UIControlStateNormal];
        [_sharingAccept addTarget:self action:@selector(acceptSharing) forControlEvents:UIControlEventTouchUpInside];
        [_sharingDecline addTarget:self action:@selector(declineSharing) forControlEvents:UIControlEventTouchUpInside];
    }
    _sharingAccept.hidden = !sharingOffer;
    _sharingDecline.hidden = !sharingOffer;
    if (sharingOffer) {
        CGFloat width = MIN(260, self.contentView.bounds.size.width - 24);
        CGFloat x = floor((self.contentView.bounds.size.width - width) / 2);
        _sharingDecline.frame = CGRectMake(x, CGRectGetMaxY(bubble) + 4, (width - 4) / 2, 36);
        _sharingAccept.frame = CGRectMake(x + (width + 4) / 2, CGRectGetMaxY(bubble) + 4, (width - 4) / 2, 36);
    }
    if (item.kind == ExteriaChatItemPill) return;
    ExteriaMedia *content = item.message.media;
    BOOL pictureOnly = item.content == ExteriaChatItemContentPicture && !item.textLayout;
    if (item.kind == ExteriaChatItemEmoji) {
        _picture.hidden = NO;
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        _picture.backgroundColor = [UIColor clearColor];
        _picture.image = ExteriaEmojiImageNow(item.singleEmoji);
        if ([self playsOnItsOwn]) [self loadEmojiAnimation];
        pictureOnly = YES;
    } else if (item.kind == ExteriaChatItemSticker) {
        _picture.hidden = NO;
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        _picture.backgroundColor = [UIColor clearColor];
        if ((content.stickerFormat == EXTERIA_STICKER_ANIMATED || content.stickerFormat == EXTERIA_STICKER_VIDEO) && content.file && [self playsOnItsOwn]) [self loadLottieForItem:item];
        else [self loadPictureForItem:item];
        [self applyStickerShape];
        pictureOnly = YES;
    } else if (item.kind == ExteriaChatItemRound) {
        _picture.hidden = NO;
        _picture.contentMode = UIViewContentModeScaleAspectFill;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        _picture.layer.cornerRadius = item.pictureFrame.size.width / 2;
        [self loadPictureForItem:item];
        [self placeMediaButtonOver:_picture.frame];
        /* a round message starts to come as soon as it is on screen, with the ring turning on its button */
        [self prepareMediaButtonLoading:YES];
        pictureOnly = YES;
    } else if (item.albumFrames.count) {
        [self showAlbumForItem:item bubble:bubble];
    } else if (item.content == ExteriaChatItemContentPicture && content.kind == EXTERIA_PREVIEW_LOCATION) {
        if (!_map) {
            _map=[[ExteriaMapView alloc] initWithFrame:CGRectZero]; _map.compact=YES; _map.userInteractionEnabled=NO;
            [self.contentView insertSubview:_map belowSubview:_overlay];
        }
        _map.hidden=NO;
        _map.frame=CGRectOffset(item.pictureFrame,bubble.origin.x,bubble.origin.y);
        _map.layer.cornerRadius=MAX(0,ExteriaBubbleRadius()-3);
        [_map showLocation:content.location zoom:15];
        _picture.frame=_map.frame;
    } else if (item.content == ExteriaChatItemContentPicture) {
        _picture.hidden = NO;
        _picture.contentMode = UIViewContentModeScaleAspectFill;
        _picture.frame = CGRectOffset(item.pictureFrame, bubble.origin.x, bubble.origin.y);
        _picture.layer.cornerRadius = MAX(0, ExteriaBubbleRadius() - 3);
        BOOL video = content.kind != EXTERIA_PREVIEW_PHOTO;
        [self loadPictureForItem:item];
        if (video || [self uploading]) {
            [self placeMediaButtonOver:_picture.frame];
            /* a video waits for a tap, which brings it and shows the ring; the arrow says it is not here */
            [self prepareMediaButtonLoading:content.kind == EXTERIA_PREVIEW_GIF];
        }
    }
    _gifView.frame = _picture.frame;
    if (content.kind == EXTERIA_PREVIEW_GIF && item.content == ExteriaChatItemContentPicture && !item.albumFrames.count) {
        if (!_gifLabel) {
            _gifLabel = [[UILabel alloc] init];
            _gifLabel.text = @"GIF";
            _gifLabel.font = ExteriaFontMedium(12);
            _gifLabel.textColor = [UIColor whiteColor];
            _gifLabel.textAlignment = ExteriaTextAlignmentCenter;
            _gifLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
            _gifLabel.layer.cornerRadius = 10;
            _gifLabel.clipsToBounds = YES;
            _gifLabel.userInteractionEnabled = NO;
            [self.contentView insertSubview:_gifLabel aboveSubview:_overlay];
        }
        _gifLabel.frame = CGRectMake(_picture.frame.origin.x + 6, _picture.frame.origin.y + 6, 36, 20);
        _gifLabel.hidden = NO;
    }
    _lottie.frame = _picture.frame;
    _roundView.frame = _picture.frame;
    if (_gifPlayer && _gifItem.status == AVPlayerItemStatusReadyToPlay) _play.hidden = YES;
    [self refreshSpoilerCoverForItem:item];
    [self prepareVoiceActionForItem:item bubble:bubble];
    if (pictureOnly && !(item.kind == ExteriaChatItemSticker && ExteriaChatFlagGet(ExteriaChatFlagHideStickerTime))) {
        _overlay.hidden = NO;
        _overlay.item = item;
        _overlay.frame = CGRectMake(bubble.origin.x + item.timeOrigin.x, bubble.origin.y + item.timeOrigin.y, item.timeSize.width, item.timeSize.height);
        [_overlay setNeedsDisplay];
    }
}

#pragma mark album

- (ExteriaMessage *)tappedMediaMessage {
    return _tappedMedia ? _tappedMedia : _item.message;
}

- (void)hideAlbumViews {
    for (UIView *view in _albumViews) view.hidden = YES;
    for (UIView *view in _albumMarks) view.hidden = YES;
}

/* the picture of a video in an album is its thumbnail, and of a photo the photo; each is its own view cut to its cell of the collage */
- (void)showAlbumForItem:(ExteriaChatItem *)item bubble:(CGRect)bubble {
    if (!_albumViews) {
        _albumViews = [[NSMutableArray alloc] init];
        _albumMarks = [[NSMutableArray alloc] init];
    }
    NSUInteger token = _token;
    CGFloat radius = MAX(0, ExteriaBubbleRadius() - 3);
    /* a list that holds only some of an album (the pinned messages, a search) gives frames and messages of different counts, and each view needs both */
    NSUInteger shown = MIN(item.albumFrames.count, item.albumMessages.count);
    for (NSUInteger i = 0; i < shown; ++i) {
        while (_albumViews.count <= i) {
            UIImageView *view = [[[UIImageView alloc] init] autorelease];
            view.contentMode = UIViewContentModeScaleAspectFill;
            view.clipsToBounds = YES;
            [self.contentView insertSubview:view aboveSubview:_picture];
            [_albumViews addObject:view];
            UIImageView *mark = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPlay, 26, [UIColor whiteColor])] autorelease];
            mark.contentMode = UIViewContentModeCenter;
            [self.contentView insertSubview:mark aboveSubview:view];
            [_albumMarks addObject:mark];
        }
        UIImageView *view = [_albumViews objectAtIndex:i], *mark = [_albumMarks objectAtIndex:i];
        ExteriaMessage *message = [item.albumMessages objectAtIndex:i];
        CGRect frame = CGRectOffset([[item.albumFrames objectAtIndex:i] CGRectValue], bubble.origin.x, bubble.origin.y);
        view.frame = frame;
        view.hidden = NO;
        view.image = nil;
        view.backgroundColor = [self placeholderColor];
        view.layer.cornerRadius = 0;
        mark.frame = frame;
        mark.hidden = message.media.kind == EXTERIA_PREVIEW_PHOTO;
        /* the outer corners of the collage follow the bubble; the cells inside stay square */
        if (i == 0 || i == shown - 1) view.layer.cornerRadius = radius;
        ExteriaMedia *media = message.media;
        ExteriaRemoteFile *file = media.kind == EXTERIA_PREVIEW_PHOTO ? media.file : media.previewFile;
        UIImage *local = message.pendingSend ? message.pendingSend->preview : nil;
        CGFloat side = frame.size.width * ExteriaScreenScale();
        if (local && !file) {
            view.image = local;
            view.backgroundColor = [UIColor clearColor];
            continue;
        }
        if (!file) continue;
        UIImage *ready = [_media cachedImageForFile:file maxSide:side];
        if (ready) {
            view.image = ready;
            view.backgroundColor = [UIColor clearColor];
            continue;
        }
        [_media loadImageForFile:file maxSide:side completion:^(UIImage *image) {
            if (token != _token || !image) return;
            view.image = image;
            view.backgroundColor = [UIColor clearColor];
        }];
    }
    for (NSUInteger i = shown; i < _albumViews.count; ++i) {
        [[_albumViews objectAtIndex:i] setHidden:YES];
        [[_albumMarks objectAtIndex:i] setHidden:YES];
    }
}

#pragma mark media button

/* the button sits in the middle of the picture, on the dark capsule of the bubbles */
- (void)placeMediaButtonOver:(CGRect)frame {
    _play.frame = CGRectMake(CGRectGetMidX(frame) - MEDIA_BUTTON / 2, CGRectGetMidY(frame) - MEDIA_BUTTON / 2, MEDIA_BUTTON, MEDIA_BUTTON);
    _play.discColor = ExteriaColorBubbleCapsule();
    _play.hidden = NO;
}

/* the action that stands for the file of this row: the voice button of a note, the media button of the rest */
- (ExteriaMediaActionView *)loadAction {
    exteria_preview_kind kind = _item.message.media.kind;
    return kind == EXTERIA_PREVIEW_VOICE || kind == EXTERIA_PREVIEW_AUDIO || kind == EXTERIA_PREVIEW_FILE ? _voiceAction : _play;
}

/* a photo, video or document of ours that is still going up: its button is a cross with the ring of the upload, not the arrow of a file to fetch */
- (BOOL)uploading {
    ExteriaMessage *message = _item.message;
    ExteriaOutgoing *pending = message.pendingSend;
    return message.outgoing && message.state == ExteriaMessageStateSending && pending &&
           (pending->kind == ExteriaOutgoingPhoto || pending->kind == ExteriaOutgoingVideo || pending->kind == ExteriaOutgoingFile);
}

- (void)showUploadProgress {
    if ([self uploading]) [[self loadAction] setProgress:_item.message.uploadProgress];
}

/* the card burns: sparks over it while it fades, and the owner rebuilds the row as an expired one when the animation is over */
- (void)playBurnWithCompletion:(void (^)(void))completion {
    if (!ExteriaMessageIsViewOnce(_item.message) || _item.content != ExteriaChatItemContentFile) {
        if (completion) completion();
        return;
    }
    CGRect card = [self.contentView convertRect:CGRectInset(_item.fileFrame, -6, -4) fromView:_body];
    [UIView animateWithDuration:0.8 delay:0.1 options:UIViewAnimationOptionCurveEaseIn animations:^{ _body.alpha = 0.25f; } completion:nil];
    [ExteriaBurnEffect burnRect:card inView:self.contentView duration:0.9 completion:completion];
}

- (void)flashHighlight {
    if (!_flash) {
        _flash = [[UIView alloc] init];
        _flash.userInteractionEnabled = NO;
        [self.contentView insertSubview:_flash atIndex:0];
    }
    _flash.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:ExteriaThemeIsDark() ? 0.26f : 0.2f];
    CGRect bubble = _item.bubbleFrame;
    CGFloat top = MAX(0, CGRectGetMinY(bubble));
    CGFloat bottom = MIN(self.contentView.bounds.size.height, CGRectGetMaxY(bubble));
    _flash.frame = CGRectMake(0, top, self.contentView.bounds.size.width, MAX(0, bottom - top));
    [_flash.layer removeAllAnimations];
    _flash.alpha = 0;
    UIView *flash = _flash;
    [UIView animateWithDuration:0.14 animations:^{ flash.alpha = 1; } completion:^(BOOL finished) {
        if (!finished) return;
        [UIView animateWithDuration:0.7 delay:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{ flash.alpha = 0; } completion:nil];
    }];
}

- (void)cancelSending {
    if ([_delegate respondsToSelector:@selector(messageCellDidCancelSending:)]) [_delegate messageCellDidCancelSending:self];
}

/* the glyph a file shows before anything is asked of it: the triangle when it is on the disk, the ring when it is
   coming, the arrow when it has to be asked for */
- (void)prepareMediaButtonLoading:(BOOL)startAtOnce {
    ExteriaMedia *content = _item.message.media;
    if ([self uploading]) {
        [[self loadAction] setIcon:ExteriaMediaIconCancel animated:NO];
        [[self loadAction] setProgress:_item.message.uploadProgress];
        return;
    }
    if (_loadRequest) {
        [[self loadAction] setIcon:ExteriaMediaIconCancel animated:NO];
        [[self loadAction] setProgress:_loadProgress];
        [self showFileProgress:_loadProgress];
        return;
    }
    NSString *path = _loadedPath ? _loadedPath : [_media cachedPathForFile:content.file size:content.size];
    if (path) {
        if (!_loadedPath) _loadedPath = [path copy];
        [[self loadAction] setIcon:ExteriaMediaIconPlay animated:NO];
        return;
    }
    [[self loadAction] setIcon:ExteriaMediaIconDownload animated:NO];
    if (startAtOnce) [self startMediaLoad:NO];
}

- (void)startMediaLoad:(BOOL)asked {
    ExteriaMedia *content = _item.message.media;
    if (_loadRequest || _loadedPath || !content.file) return;
    ExteriaMediaActionView *action = [self loadAction];
    /* a tap asks again for a file that did not come, without waiting out the pause the cache keeps after a failure */
    if (_loadFailed) [_media retryFile:content.file];
    _loadFailed = NO;
    _loadAsked = asked;
    [action setIcon:ExteriaMediaIconCancel animated:YES];
    _loadProgress = 0;
    [action setProgress:0];
    [self showFileProgress:0];
    NSUInteger token = ++_loadToken;
    ExteriaWeakReference *weak = _weak;
    NSUInteger request = [_media loadPathForFile:content.file size:content.size progress:^(float fraction) {
        ExteriaMessageCell *cell = weak.target;
        if (cell && token == cell->_loadToken) {
            cell->_loadProgress = fraction;
            [[cell loadAction] setProgress:fraction];
            [cell showFileProgress:fraction];
        }
    } completion:^(NSString *path) {
        ExteriaMessageCell *cell = weak.target;
        if (!cell || token != cell->_loadToken) return;
        cell->_loadRequest = 0;
        if (!path) {
            NSLog(@"exteria: media %@ did not arrive", content.file.key);
            cell->_loadFailed = YES;
            cell->_playWhenLoaded = NO;
            cell->_body.fileProgressText = nil;
            [cell->_body setNeedsDisplay];
            [[cell loadAction] setIcon:ExteriaMediaIconDownload animated:YES];
            return;
        }
        [cell->_loadedPath release];
        cell->_loadedPath = [path copy];
        [cell mediaArrived];
    }];
    if (request && token == _loadToken && !_loadedPath && !_loadFailed) _loadRequest = request;
}

/* the file is on the disk: the ring turns into the triangle, and a round message that was asked to play does */
- (void)mediaArrived {
    _body.fileProgressText = nil;
    [_body setNeedsDisplay];
    exteria_preview_kind kind = _item.message.media.kind;
    if (kind == EXTERIA_PREVIEW_FILE) {
        [_voiceAction setProgress:1];
        [_voiceAction setIcon:ExteriaMediaIconFile animated:YES];
        return;
    }
    if (kind == EXTERIA_PREVIEW_VOICE || kind == EXTERIA_PREVIEW_AUDIO) {
        [self syncVoiceActionAnimated:YES];
        return;
    }
    [_play setProgress:1];
    if (kind == EXTERIA_PREVIEW_GIF && _animating && ![self spoilerHidesItem:_item]) {
        [self startGif];
        return;
    }
    if (_item.kind == ExteriaChatItemRound && _playWhenLoaded) {
        _playWhenLoaded = NO;
        [self beginRoundAtPath:_loadedPath];
        return;
    }
    [_play setIcon:ExteriaMediaIconPlay animated:YES];
}

- (void)cancelMediaTransfer {
    ++_loadToken;
    [_media cancelPathRequest:_loadRequest];
    _loadRequest = 0;
    _playWhenLoaded = NO;
    _body.fileProgressText = nil;
    [_body setNeedsDisplay];
}

- (void)showFileProgress:(float)fraction {
    ExteriaMedia *content = _item.message.media;
    if (content.kind != EXTERIA_PREVIEW_FILE || content.size <= 0) return;
    long long loaded = (long long)((double)content.size * MAX(0, MIN(1, fraction)));
    _body.fileProgressText = [NSString stringWithFormat:@"%@ / %@", ExteriaFileSizeText(loaded), ExteriaFileSizeText(content.size)];
    [_body setNeedsDisplay];
}

/* the cell goes to another row, or ends */
- (void)cancelMediaLoad {
    /* a download the user asked for by a tap goes on in the cache when the row or the chat goes away, its bytes are
       wanted; the token drop below only mutes the callbacks of this cell */
    if (_loadRequest && _loadAsked) {
        ++_loadToken;
        _loadRequest = 0;
        _playWhenLoaded = NO;
        _body.fileProgressText = nil;
    } else {
        [self cancelMediaTransfer];
    }
    _loadAsked = NO;
    [_loadedPath release];
    _loadedPath = nil;
    _loadFailed = NO;
    _loadProgress = 0;
    _photoLoadShown = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showPhotoLoading) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hidePhotoLoading) object:nil];
}

/* a tap on a video that is not here yet brings it, with the ring turning on the button, and a second tap lets it
   go; a video that cannot be brought here (it is past the limit of the cache, or the file did not come) opens at
   once */
- (BOOL)tappedMediaButton {
    exteria_preview_kind kind = _item.message.media.kind;
    if (kind == EXTERIA_PREVIEW_PHOTO || _play.hidden || _loadedPath) return NO;
    if (_loadRequest) {
        [self cancelMediaTransfer];
        [_play setIcon:ExteriaMediaIconDownload animated:YES];
        return YES;
    }
    if (_loadFailed) return NO;
    [self startMediaLoad:YES];
    return !_loadFailed;
}

/* a tap on a document that is here opens it; on one that is not, it brings it with the ring turning on the button,
   and a second tap lets it go */
- (void)tappedFileButton {
    if ([self uploading]) {
        [self cancelSending];
        return;
    }
    if (_loadedPath) {
        [_delegate messageCell:self didOpenFileAtPath:_loadedPath name:_item.message.media.name];
        return;
    }
    if (_loadRequest) {
        [self cancelMediaTransfer];
        [_voiceAction setIcon:ExteriaMediaIconDownload animated:YES];
        return;
    }
    [self startMediaLoad:YES];
}

#pragma mark voice button

- (void)prepareVoiceActionForItem:(ExteriaChatItem *)item bubble:(CGRect)bubble {
    exteria_preview_kind kind = item.message.media.kind;
    if (item.call || item.content != ExteriaChatItemContentFile || ExteriaMessageIsViewOnce(item.message) || (kind != EXTERIA_PREVIEW_VOICE && kind != EXTERIA_PREVIEW_AUDIO && kind != EXTERIA_PREVIEW_FILE)) return;
    CGRect icon = item.fileFrame;
    _voiceAction.frame = CGRectMake(bubble.origin.x + icon.origin.x, bubble.origin.y + icon.origin.y, VOICE_BUTTON, VOICE_BUTTON);
    _voiceAction.discColor = item.message.outgoing && !ExteriaThemeIsClassic() ? [UIColor colorWithWhite:1 alpha:0.22] : ExteriaColorAccent();
    _voiceAction.hidden = NO;
    /* a voice note comes by itself, a song waits to be played, and a document waits to be asked for: the arrow, then the page once it is here */
    [self prepareMediaButtonLoading:kind == EXTERIA_PREVIEW_VOICE];
    if (kind == EXTERIA_PREVIEW_FILE) [_voiceAction setIcon:_loadRequest || [self uploading] ? ExteriaMediaIconCancel : (_loadedPath ? ExteriaMediaIconFile : ExteriaMediaIconDownload) animated:NO];
    else [self syncVoiceActionAnimated:NO];
}

/* the glyph follows the player when this is its song, and the file when it is not */
- (void)syncVoiceActionAnimated:(BOOL)animated {
    ExteriaMedia *media = _item.message.media;
    if (_voiceAction.hidden) return;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if ([player isCurrentTrack:media] && player.state != ExteriaMusicStateFailed) {
        switch (player.state) {
        case ExteriaMusicStateLoading:
            [_voiceAction setIcon:ExteriaMediaIconCancel animated:animated];
            [_voiceAction setProgress:player.loadProgress];
            break;
        case ExteriaMusicStatePlaying: [_voiceAction setIcon:ExteriaMediaIconPause animated:animated]; break;
        default: [_voiceAction setIcon:ExteriaMediaIconPlay animated:animated]; break;
        }
        return;
    }
    if (_loadRequest) [_voiceAction setIcon:ExteriaMediaIconCancel animated:animated];
    else [_voiceAction setIcon:_loadedPath ? ExteriaMediaIconPlay : ExteriaMediaIconDownload animated:animated];
}

#pragma mark round message

/* a circle that plays pauses when the app goes away, if the person asked for that; the sound of a circle is not a background audio */
+ (void)initialize {
    if (self != [ExteriaMessageCell class]) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        (void)note;
        if (sPlayingRound && [sPlayingRound roundPlaying] && ExteriaChatFlagGet(ExteriaChatFlagPauseRoundOnMinimize)) [sPlayingRound toggleRound];
    }];
}

- (BOOL)roundPlaying {
    return _roundPlayer != nil && _roundPlayer.rate > 0;
}

/* the playback goes; the file stays, and the button goes back to the triangle */
- (void)stopRound {
    ++_roundToken;
    [_roundTimer invalidate];
    _roundTimer = nil;
    if (_roundItem) [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_roundItem];
    [_roundPlayer pause];
    ((AVPlayerLayer *)_roundView.layer).player = nil;
    [_roundView removeFromSuperview];
    [_roundView release];
    _roundView = nil;
    [_roundPlayer release];
    _roundPlayer = nil;
    [_roundItem release];
    _roundItem = nil;
    [_roundRing removeFromSuperlayer];
    [_roundRing release];
    _roundRing = nil;
    [_roundSpeed removeFromSuperview];
    [_roundSpeed release];
    _roundSpeed = nil;
    if (_item.kind == ExteriaChatItemRound) {
        _play.hidden = NO;
        [_play setIcon:_loadedPath ? ExteriaMediaIconPlay : ExteriaMediaIconDownload animated:_play.window != nil];
    }
    if (sPlayingRound == self) sPlayingRound = nil;
}

- (void)startRound {
    if (_roundPlayer) return;
    [self toggleRound];
}

/* the speed chip on a playing circle, and the rate of the video follow the speed the player keeps */
- (void)applyRoundSpeed {
    float speed = [ExteriaMusicPlayer sharedPlayer].speed;
    [_roundSpeed setTitle:ExteriaSpeedText(speed) forState:UIControlStateNormal];
    if ([self roundPlaying]) _roundPlayer.rate = speed;
}

- (void)cycleRoundSpeed {
    [[ExteriaMusicPlayer sharedPlayer] cycleSpeed];
}

/* a tap on the circle starts the video, pauses it and resumes it; one that was let go or never arrived is asked
   for again by a tap */
- (void)toggleRound {
    if (_roundPlayer) {
        if ([self roundPlaying]) {
            [_roundPlayer pause];
            [_play setIcon:ExteriaMediaIconPlay animated:YES];
        } else {
            if (!ExteriaAudioSessionBeginPlayback()) return;
            [_roundPlayer play];
            [self applyRoundSpeed];
            [_play setIcon:ExteriaMediaIconNone animated:YES];
        }
        return;
    }
    if (!_item.message.media.file) return;
    if (_loadedPath) {
        [self beginRoundAtPath:_loadedPath];
        return;
    }
    if (_loadRequest) {
        if (_playWhenLoaded) {
            [self cancelMediaTransfer];
            [_play setIcon:ExteriaMediaIconDownload animated:YES];
        } else {
            _playWhenLoaded = YES;
        }
        return;
    }
    _playWhenLoaded = YES;
    [self startMediaLoad:YES];
}

- (void)beginRoundAtPath:(NSString *)path {
    NSURL *url = ExteriaPlayableLink(path, @"mp4", @"round");
    if (!url || !ExteriaAudioSessionBeginPlayback()) {
        [self stopRound];
        return;
    }
    if (sPlayingRound && sPlayingRound != self) [sPlayingRound stopRound];
    sPlayingRound = self;
    [[ExteriaMusicPlayer sharedPlayer] pauseForMedia];
    [_play setIcon:ExteriaMediaIconNone animated:YES];
    _roundItem = [[AVPlayerItem playerItemWithURL:url] retain];
    _roundPlayer = [[AVPlayer playerWithPlayerItem:_roundItem] retain];
    _roundView = [[ExteriaRoundVideoView alloc] initWithFrame:_picture.frame];
    _roundView.userInteractionEnabled = NO;
    _roundView.layer.cornerRadius = _picture.frame.size.width / 2;
    _roundView.layer.masksToBounds = YES;
    ((AVPlayerLayer *)_roundView.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
    ((AVPlayerLayer *)_roundView.layer).player = _roundPlayer;
    [self.contentView insertSubview:_roundView aboveSubview:_picture];
    _roundRing = [[CAShapeLayer layer] retain];
    /* the layer is the size of the picture and stands on it, so the turn that starts the stroke at the top is
       about the middle of the picture */
    _roundRing.frame = _picture.frame;
    CGRect ring = CGRectInset(_roundRing.bounds, 1.5, 1.5);
    _roundRing.path = [UIBezierPath bezierPathWithOvalInRect:ring].CGPath;
    _roundRing.fillColor = NULL;
    _roundRing.strokeColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    _roundRing.lineWidth = 3;
    _roundRing.lineCap = kCALineCapRound;
    _roundRing.strokeEnd = 0;
    /* the stroke starts at the top and runs clockwise, which a path from three o'clock does not */
    _roundRing.transform = CATransform3DMakeRotation((CGFloat)(-M_PI / 2), 0, 0, 1);
    [self.contentView.layer addSublayer:_roundRing];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roundEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_roundItem];
    _roundSpeed = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _roundSpeed.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    _roundSpeed.layer.cornerRadius = 11;
    _roundSpeed.titleLabel.font = ExteriaFontSemibold(12);
    _roundSpeed.frame = CGRectMake(CGRectGetMidX(_picture.frame) - 20, CGRectGetMaxY(_picture.frame) - 34, 40, 22);
    [_roundSpeed addTarget:self action:@selector(cycleRoundSpeed) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_roundSpeed];
    [_roundPlayer play];
    [self applyRoundSpeed];
    _roundTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(roundTick:) userInfo:nil repeats:YES];
}

- (void)roundTick:(NSTimer *)timer {
    (void)timer;
    if (_roundItem.status == AVPlayerItemStatusFailed) {
        NSLog(@"exteria: round video does not play: %@", _roundItem.error);
        [self stopRound];
        return;
    }
    NSTimeInterval length = CMTimeGetSeconds(_roundItem.duration);
    NSTimeInterval at = CMTimeGetSeconds(_roundPlayer.currentTime);
    if (length > 0 && length < 1e9 && at >= 0) _roundRing.strokeEnd = (CGFloat)MIN(1, at / length);
}

- (void)roundEnded:(NSNotification *)note {
    (void)note;
    [self stopRound];
    [_delegate messageCellDidFinishRound:self];
}

- (void)setAnimating:(BOOL)animating {
    if (_item.giftCard) {
        _animating = animating;
        [_giftCardView setActive:animating];
        return;
    }
    if (_item.message.media.kind == EXTERIA_PREVIEW_GIF) {
        _animating = animating && (_gifPlayRequested || [self playsOnItsOwn]) && ![self spoilerHidesItem:_item];
        if (_animating) [self startGif];
        else [self stopGif];
        return;
    }
    if (animating && (_item.kind == ExteriaChatItemEmoji || _item.kind == ExteriaChatItemSticker) && ![self playsOnItsOwn]) animating = NO;
    _animating = animating;
    if (animating && !_activationDeferred && _pendingLottie) [self setActivationDeferred:NO];
    if (_item.kind == ExteriaChatItemSticker && _item.message.media.stickerFormat == EXTERIA_STICKER_VIDEO) {
        if (!animating && _lottie) { [self discardLottie]; _picture.hidden = NO; }
        else if (animating && !_lottie && !_pendingLottie) [self loadLottieFile:_item.message.media.file];
    }
    if (_item.kind == ExteriaChatItemEmoji) {
        /* an emoji plays once when it comes into view, a tap plays it again */
        if (animating && _lottie && !_emojiPlayed) {
            _emojiPlayed = YES;
            [_lottie playOnce];
        } else if (!animating) [_lottie setPlaying:NO];
    } else [_lottie setPlaying:animating];
}

- (void)tappedGif {
    if (_gifPlayer) return;
    if (_loadRequest) {
        _gifPlayRequested = NO;
        [self cancelMediaTransfer];
        [_play setIcon:ExteriaMediaIconDownload animated:YES];
        return;
    }
    if (!_item.message.media.file) return;
    _gifFailed = NO;
    _gifPlayRequested = YES;
    [self setAnimating:YES];
    if (!_loadedPath) [self startMediaLoad:YES];
}

/* telegram animations are silent mp4 documents; AVFoundation on ios 5-10 needs an extension on their cache files */
- (void)startGif {
    if (_gifPlayer || _gifFailed || !_animating || _activationDeferred || !_loadedPath || [self spoilerHidesItem:_item]) return;
    NSString *slot = [NSString stringWithFormat:@"gif-%p", self];
    _gifURL = [ExteriaPlayableLink(_loadedPath, @"mp4", slot) retain];
    if (!_gifURL) { _gifFailed = YES; return; }
    _gifItem = [[AVPlayerItem playerItemWithURL:_gifURL] retain];
    NSMutableArray *parameters = [NSMutableArray array];
    for (AVAssetTrack *track in [_gifItem.asset tracksWithMediaType:AVMediaTypeAudio]) {
        AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [input setVolume:0 atTime:kCMTimeZero];
        [parameters addObject:input];
    }
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    mix.inputParameters = parameters;
    _gifItem.audioMix = mix;
    _gifPlayer = [[AVPlayer playerWithPlayerItem:_gifItem] retain];
    _gifPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    _gifView = [[ExteriaRoundVideoView alloc] initWithFrame:_picture.frame];
    _gifView.userInteractionEnabled = NO;
    _gifView.layer.cornerRadius = _picture.layer.cornerRadius;
    _gifView.clipsToBounds = YES;
    ((AVPlayerLayer *)_gifView.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
    ((AVPlayerLayer *)_gifView.layer).player = _gifPlayer;
    [self.contentView insertSubview:_gifView aboveSubview:_picture];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gifEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_gifItem];
    [_gifItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:&ExteriaGifStatusContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &ExteriaGifStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    dispatch_async(dispatch_get_main_queue(), ^{
        ExteriaMessageCell *cell = weak.target;
        if (!cell || object != cell->_gifItem) return;
        if (cell->_gifItem.status == AVPlayerItemStatusReadyToPlay) {
            cell->_play.hidden = YES;
            if (cell->_animating) [cell->_gifPlayer play];
        } else if (cell->_gifItem.status == AVPlayerItemStatusFailed) {
            NSLog(@"exteria: inline animation failed: %@", cell->_gifItem.error);
            cell->_gifFailed = YES;
            [cell stopGif];
        }
    });
}

- (void)gifEnded:(NSNotification *)note {
    if (note.object != _gifItem || !_animating) return;
    [_gifPlayer seekToTime:kCMTimeZero];
    [_gifPlayer play];
}

- (void)stopGif {
    if (_gifItem) {
        [_gifItem removeObserver:self forKeyPath:@"status" context:&ExteriaGifStatusContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_gifItem];
    }
    [_gifPlayer pause];
    ((AVPlayerLayer *)_gifView.layer).player = nil;
    [_gifView removeFromSuperview];
    [_gifView release]; _gifView = nil;
    [_gifPlayer release]; _gifPlayer = nil;
    [_gifItem release]; _gifItem = nil;
    if (_gifURL) [[NSFileManager defaultManager] removeItemAtPath:_gifURL.path.stringByDeletingLastPathComponent error:NULL];
    [_gifURL release]; _gifURL = nil;
    if (_item.message.media.kind == EXTERIA_PREVIEW_GIF) {
        _play.hidden = NO;
        [_play setIcon:_loadRequest ? ExteriaMediaIconCancel : (_loadedPath ? ExteriaMediaIconPlay : ExteriaMediaIconDownload) animated:NO];
    }
}

#pragma mark swipe to reply

- (BOOL)replySwipeActive {
    return _swipe.state == UIGestureRecognizerStateBegan || _swipe.state == UIGestureRecognizerStateChanged;
}

/* every message is answered by a leftward swipe; vertical movement stays with the table */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer == _seekPan) {
        if (_selecting || !_item.message) return NO;
        CGPoint point = [recognizer locationInView:self.contentView];
        if (_item.kind == ExteriaChatItemRound && _roundPlayer) {
            CGFloat x = point.x - CGRectGetMidX(_picture.frame), y = point.y - CGRectGetMidY(_picture.frame);
            CGFloat radius = _picture.frame.size.width / 2;
            CGFloat distance = hypot(x, y);
            return distance >= MAX(0, radius - 32) && distance <= radius + 12;
        }
        if (_item.content == ExteriaChatItemContentFile && _item.message.media.kind == EXTERIA_PREVIEW_VOICE) {
            ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
            CGPoint body = [recognizer locationInView:_body];
            if (!_item.message.outgoing) body.x -= _body.tailWidth;
            return [player isCurrentTrack:_item.message.media] &&
                (player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStatePaused) &&
                CGRectContainsPoint(CGRectInset([_body waveRect], 0, -8), body);
        }
        return NO;
    }
    if (recognizer != _swipe) return YES;
    if (_selecting || !_item.message || _item.kind == ExteriaChatItemPill || ![_delegate messageCellCanSwipeReply:self]) return NO;
    CGPoint velocity = [_swipe velocityInView:self];
    return exteria_motion_reply_swipe_begins(velocity.x, velocity.y);
}

- (void)seekDragged:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateBegan && pan.state != UIGestureRecognizerStateChanged && pan.state != UIGestureRecognizerStateEnded) return;
    if (_item.kind == ExteriaChatItemRound && _roundPlayer) {
        CGPoint point = [pan locationInView:self.contentView];
        CGFloat angle = atan2(point.y - CGRectGetMidY(_picture.frame), point.x - CGRectGetMidX(_picture.frame)) + (CGFloat)M_PI / 2;
        if (angle < 0) angle += (CGFloat)(2 * M_PI);
        NSTimeInterval duration = CMTimeGetSeconds(_roundItem.duration);
        if (isfinite(duration) && duration > 0) {
            CGFloat fraction = angle / (CGFloat)(2 * M_PI);
            _roundRing.strokeEnd = fraction;
            [_roundPlayer seekToTime:CMTimeMakeWithSeconds(duration * fraction, 600)];
        }
    } else if (_item.message.media.kind == EXTERIA_PREVIEW_VOICE) {
        CGPoint point = [pan locationInView:_body];
        if (!_item.message.outgoing) point.x -= _body.tailWidth;
        CGRect wave = [_body waveRect];
        if (wave.size.width > 0) [[ExteriaMusicPlayer sharedPlayer] seekToFraction:(float)((point.x - wave.origin.x) / wave.size.width)];
    }
}

/* the row of somebody else sits right of the selection circle while messages are picked */
- (CGAffineTransform)restingTransform {
    return _selecting && !_item.message.outgoing && [self selectable] ? CGAffineTransformMakeTranslation(SELECT_SHIFT, 0) : CGAffineTransformIdentity;
}

- (void)resetSwipe {
    [self.contentView.layer removeAllAnimations];
    [_swipeDisc.layer removeAllAnimations];
    _swipeCrossed = NO;
    self.contentView.transform = [self restingTransform];
    _swipeDisc.alpha = 0;
}

/* a message that has a number on the server can be picked; a date, a service line and a message still on its way cannot */
- (BOOL)selectable {
    return _item.message && _item.kind != ExteriaChatItemPill && _item.message.messageId > 0;
}

- (void)selectTapped {
    if ([_delegate respondsToSelector:@selector(messageCellDidToggleSelection:)]) [_delegate messageCellDidToggleSelection:self];
}

- (UIImage *)contentSnapshot {
    CGSize size = self.contentView.bounds.size;
    if (size.width <= 0 || size.height <= 0) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [self.contentView.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)setSelecting:(BOOL)selecting selected:(BOOL)selected animated:(BOOL)animated {
    _selecting = selecting;
    _selected = selected;
    BOOL show = selecting && [self selectable];
    _selectCover.hidden = !show;
    _selectCover.frame = self.bounds;
    _selectMark.hidden = !show;
    CGRect bubble = _item.bubbleFrame;
    _selectMark.center = CGPointMake(8 + SELECT_MARK / 2, CGRectGetMidY(bubble));
    void (^apply)(void) = ^{
        self.contentView.transform = [self restingTransform];
        _selectMark.backgroundColor = selected ? ExteriaColorAccent() : [UIColor colorWithWhite:0 alpha:0.15];
        _selectMark.layer.borderColor = (selected ? ExteriaColorAccent() : [UIColor colorWithWhite:1 alpha:0.85]).CGColor;
        _selectCheck.alpha = selected ? 1 : 0;
    };
    if (animated) [UIView animateWithDuration:0.18 animations:apply];
    else apply();
}

- (void)swiped:(UIPanGestureRecognizer *)pan {
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
    case UIGestureRecognizerStateChanged: {
        CGFloat pull = (CGFloat)exteria_motion_reply_swipe_pull([pan translationInView:self].x);
        /* past the trigger the row gives less for every point, so it is clear the answer is armed */
        CGFloat shown = pull <= SWIPE_TRIGGER ? pull : SWIPE_TRIGGER + (pull - SWIPE_TRIGGER) * 0.3;
        shown = MIN(shown, SWIPE_MAX);
        self.contentView.transform = CGAffineTransformMakeTranslation(-shown, 0);
        CGFloat progress = MIN(1, shown / SWIPE_TRIGGER);
        CGFloat gap = 10;
        CGRect bubble = _item.bubbleFrame;
        CGFloat x = CGRectGetMaxX(bubble) - shown + gap + SWIPE_DISC / 2;
        x = MAX(SWIPE_DISC / 2, MIN(self.bounds.size.width - SWIPE_DISC / 2, x));
        _swipeDisc.center = CGPointMake(x, CGRectGetMidY(bubble));
        CGFloat scale = 0.6 + 0.4 * progress;
        CGFloat room = self.bounds.size.width - CGRectGetMaxX(bubble) + shown;
        _swipeDisc.alpha = room >= gap + SWIPE_DISC ? progress : 0;
        CGFloat flip = 1;
        BOOL crossed = pull >= SWIPE_TRIGGER;
        if (crossed != _swipeCrossed) {
            /* the disc swells as the answer becomes armed, and settles when it is let go, the way the reply icon of the original client pops */
            [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^{
                _swipeDisc.transform = CGAffineTransformMakeScale(flip * (crossed ? scale * 1.18 : scale), crossed ? scale * 1.18 : scale);
            } completion:nil];
        } else if (!crossed) {
            _swipeDisc.transform = CGAffineTransformMakeScale(flip * scale, scale);
        }
        _swipeCrossed = crossed;
        break;
    }
    case UIGestureRecognizerStateEnded: {
        BOOL answer = _swipeCrossed;
        _swipeCrossed = NO;
        /* the row springs back, through the helper that has the spring on every system the app runs on */
        ExteriaAnimateView(self.contentView, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
        [UIView animateWithDuration:0.2 animations:^{ _swipeDisc.alpha = 0; }];
        if (answer) [_delegate messageCellDidSwipeReply:self];
        break;
    }
    default:
        _swipeCrossed = NO;
        [UIView animateWithDuration:0.2 animations:^{
            self.contentView.transform = CGAffineTransformIdentity;
            _swipeDisc.alpha = 0;
        }];
        break;
    }
}

- (void)longPressed:(UILongPressGestureRecognizer *)press {
    /* the controller knows what can be done to the message, so a message that offers nothing just shows no menu */
    if (press.state != UIGestureRecognizerStateBegan || !_item.message || _item.kind == ExteriaChatItemPill) return;
    CGPoint point = [press locationInView:self.contentView];
    if (CGRectContainsPoint(_item.bubbleFrame, point)) [_delegate messageCellDidLongPress:self];
}

- (void)doubleTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded || _selecting || !_item.message) return;
    if ([_delegate respondsToSelector:@selector(messageCellDidDoubleTap:)]) [_delegate messageCellDidDoubleTap:self];
}

- (void)shareTapped {
    [_delegate messageCellDidTapShare:self];
}

- (void)acceptSharing {
    if ([_delegate respondsToSelector:@selector(messageCell:answerSharingRequest:)]) [_delegate messageCell:self answerSharingRequest:YES];
}

- (void)declineSharing {
    if ([_delegate respondsToSelector:@selector(messageCell:answerSharingRequest:)]) [_delegate messageCell:self answerSharingRequest:NO];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (_item.giftCard && CGRectContainsPoint(_item.bubbleFrame, [tap locationInView:self.contentView]) && [_delegate respondsToSelector:@selector(messageCellDidTapGift:)]) {
        [_delegate messageCellDidTapGift:self];
        return;
    }
    if (!_item || _item.kind == ExteriaChatItemPill) return;
    CGPoint point = [tap locationInView:self.contentView];
    if (_item.content == ExteriaChatItemContentPoll && [_delegate respondsToSelector:@selector(messageCell:didTapPollAnswer:)]) {
        CGPoint inPoll = CGPointMake(point.x - _item.bubbleFrame.origin.x, point.y - _item.bubbleFrame.origin.y);
        if (_item.pollButtonTitle.length && CGRectContainsPoint(_item.pollButtonFrame, inPoll)) {
            [_delegate messageCell:self didTapPollAnswer:-1];
            return;
        }
        NSUInteger answer = [_item pollAnswerAtPoint:inPoll];
        if (answer != NSNotFound) {
            [_delegate messageCell:self didTapPollAnswer:(NSInteger)answer];
            return;
        }
    }
    if (!_reactions.hidden && CGRectContainsPoint(_reactions.frame, point)) return;
    if (_markupView && !_markupView.hidden && CGRectContainsPoint(_markupView.frame, point)) return;
    if (_item.albumFrames.count) {
        CGPoint inBubble = [tap locationInView:self.contentView];
        inBubble.x -= _item.bubbleFrame.origin.x;
        inBubble.y -= _item.bubbleFrame.origin.y;
        ExteriaMessage *picked = [_item albumMessageAtPoint:inBubble];
        if (picked) {
            [_tappedMedia release];
            _tappedMedia = [picked retain];
            [_delegate messageCellDidTapMedia:self];
            return;
        }
    }
    [_tappedMedia release];
    _tappedMedia = nil;
    if (!_selecting && _item.message.media.kind == EXTERIA_PREVIEW_LOCATION && _item.message.media.location.valid &&
        CGRectContainsPoint(_map.frame,[tap locationInView:self.contentView])) {
        [_delegate messageCellDidTapMedia:self];
        return;
    }
    /* the first tap on a hidden picture shows it and nothing more; the cover does not exist until the first spoiler, and a nil cover reads as not hidden, which
       swallowed every tap on a picture, a sticker, a gif and a round video */
    if (_spoilerCover && !_spoilerCover.hidden && CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        _item.message.spoilersRevealed = YES;
        ExteriaSpoilerCover *cover = _spoilerCover;
        NSUInteger token = _token;
        ExteriaWeakReference *weak = _weak;
        [cover revealFromPoint:[tap locationInView:cover] done:^{
            ExteriaMessageCell *cell = weak.target;
            if (!cell || token != cell->_token) return;
            cover.hidden = YES;
            if ([cell.delegate respondsToSelector:@selector(messageCellDidRevealSpoiler:)]) [cell.delegate messageCellDidRevealSpoiler:cell];
        }];
        return;
    }
    if (_item.content == ExteriaChatItemContentPicture &&
        _item.message.media.kind == EXTERIA_PREVIEW_GIF &&
        CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        [self tappedGif];
        return;
    }
    if (_item.content == ExteriaChatItemContentPicture && [self uploading] && !_play.hidden &&
        CGRectContainsPoint(CGRectInset(_play.frame, -8, -8), [tap locationInView:self.contentView])) {
        [self cancelSending];
        return;
    }
    if (_item.content == ExteriaChatItemContentPicture && exteria_media_opens_viewer(_item.message.media.kind) &&
        CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        if (![self tappedMediaButton]) [_delegate messageCellDidTapMedia:self];
        return;
    }
    if (_item.kind == ExteriaChatItemRound && CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        [self toggleRound];
        return;
    }
    /* a sticker of a pack opens the pack, as in the other clients; the animation of one that moves plays when it comes up, not on a tap */
    if (_item.kind == ExteriaChatItemSticker && _item.message.media.stickerSetId && [_delegate respondsToSelector:@selector(messageCellDidTapSticker:)] &&
        CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        [_delegate messageCellDidTapSticker:self];
        return;
    }
    BOOL animatedKind = _item.kind == ExteriaChatItemEmoji ||
        (_item.kind == ExteriaChatItemSticker && (_item.message.media.stickerFormat == EXTERIA_STICKER_ANIMATED || _item.message.media.stickerFormat == EXTERIA_STICKER_VIDEO));
    if (animatedKind && CGRectContainsPoint(_picture.frame, [tap locationInView:self.contentView])) {
        if (_lottie) {
            _emojiPlayed = YES;
            [_lottie playOnce];
        } else {
            _replayRequested = YES;
            if (_item.kind == ExteriaChatItemEmoji) [self loadEmojiAnimation];
            else [self loadLottieFile:_item.message.media.file];
        }
        return;
    }
    CGPoint inBody = [tap locationInView:_body];
    /* a bubble with its tail on the left is drawn that much to the right of its view's edge */
    if (!_item.message.outgoing) inBody.x -= _body.tailWidth;
    ExteriaMessage *message = _item.message;
    CGPoint inReply = _item.kind == ExteriaChatItemBubble ? inBody : [tap locationInView:self.contentView];
    CGRect replyFrame = _item.kind == ExteriaChatItemBubble ? _item.replyFrame : _replyPreview.frame;
    if (!CGRectIsEmpty(replyFrame) && CGRectContainsPoint(replyFrame, inReply)) {
        [_delegate messageCellDidTapReply:self];
        return;
    }
    /* the line "forwarded from" takes to the one who wrote it, or says that they hid their account */
    if (_item.kind == ExteriaChatItemBubble && _item.forwardText.length && [_delegate respondsToSelector:@selector(messageCellDidTapForward:)]) {
        CGRect line = CGRectInset(CGRectMake(_item.forwardOrigin.x, _item.forwardOrigin.y, _item.forwardLayout.size.width, _item.forwardLayout.size.height), -8, -6);
        if (CGRectContainsPoint(line, inBody)) {
            [_delegate messageCellDidTapForward:self];
            return;
        }
    }
    if (_item.commentsText.length && CGRectContainsPoint(_item.commentsFrame, inBody)) {
        [_delegate messageCellDidTapComments:self];
        return;
    }
    if (message.outgoing && message.state == ExteriaMessageStateFailed && CGRectContainsPoint(CGRectInset(CGRectMake(_item.timeOrigin.x, _item.timeOrigin.y, _item.timeSize.width, _item.timeSize.height), -10, -10), inBody)) {
        [_delegate messageCellDidTapFailed:self];
        return;
    }
    if (_item.content == ExteriaChatItemContentFile && ExteriaMessageIsViewOnce(message) && CGRectContainsPoint(_item.fileFrame, inBody)) {
        if ([_delegate respondsToSelector:@selector(messageCellDidTapViewOnce:)]) [_delegate messageCellDidTapViewOnce:self];
        return;
    }
    if (_item.content == ExteriaChatItemContentFile && message.media.kind == EXTERIA_PREVIEW_FILE && !_voiceAction.hidden && CGRectContainsPoint(_item.fileFrame, inBody)) {
        [self tappedFileButton];
        return;
    }
    if (_item.content == ExteriaChatItemContentFile && (message.media.kind == EXTERIA_PREVIEW_AUDIO || message.media.kind == EXTERIA_PREVIEW_VOICE) &&
        CGRectContainsPoint(_item.fileFrame, inBody)) {
        ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
        BOOL current = [player isCurrentTrack:message.media] && (player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStatePaused);
        if (message.media.kind == EXTERIA_PREVIEW_VOICE && current) {
            CGRect wave = [_body waveRect];
            if (CGRectContainsPoint(CGRectInset([_body speedChipRect], -6, -6), inBody)) {
                [player cycleSpeed];
                return;
            }
            /* a tap in the bars jumps there; the play button and the time still pause */
            if (CGRectContainsPoint(wave, inBody) && wave.size.width > 0) {
                [player seekToFraction:(float)((inBody.x - wave.origin.x) / wave.size.width)];
                return;
            }
        }
        [_delegate messageCellDidTapAudio:self];
        return;
    }
    NSString *url = _item.textLayout ? [_item.textLayout linkAtPoint:CGPointMake(inBody.x - _item.textOrigin.x, inBody.y - _item.textOrigin.y)] : nil;
    if ([url isEqualToString:ExteriaSpoilerTarget]) {
        message.spoilersRevealed = YES;
        _item.textLayout.spoilersRevealed = YES;
        [_body setNeedsDisplay];
        return;
    }
    if (url) [_delegate messageCell:self didTapLink:url];
    else if ([_delegate respondsToSelector:@selector(messageCellDidTapBody:)]) [_delegate messageCellDidTapBody:self];
}

@end
