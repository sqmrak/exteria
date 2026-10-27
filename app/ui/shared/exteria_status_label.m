#import "exteria_status_label.h"
#import "exteria_string_drawing.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_store.h"
#import "exteria_text_layout.h"
#import "exteria_theme.h"

#include "exteria_typing.h"

#define DOT_COUNT 3
#define DOT_PERIOD 1.2
#define DOT_STAGGER 0.2
#define STATUS_MIN_SIZE 10.0

static NSString *const ExteriaDotKey = @"exteria.status.dot";

@implementation ExteriaStatusLabel

@synthesize kind = _kind;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _plainColor = [ExteriaColorSecondary() retain];
    _activeColor = [ExteriaColorAccent() retain];
    ExteriaLabelFitToWidth(self, 10);
    return self;
}

- (void)dealloc {
    [_plainColor release];
    [_activeColor release];
    [_dots release];
    [super dealloc];
}

- (UIColor *)plainColor {
    return _plainColor;
}

- (void)setPlainColor:(UIColor *)color {
    if (color == _plainColor) return;
    [_plainColor release];
    _plainColor = [color retain];
    [self applyColor];
}

- (UIColor *)activeColor {
    return _activeColor;
}

- (void)setActiveColor:(UIColor *)color {
    if (color == _activeColor) return;
    [_activeColor release];
    _activeColor = [color retain];
    [self applyColor];
}

- (void)applyColor {
    UIColor *color = _kind == ExteriaStatusPlain ? _plainColor : _activeColor;
    self.textColor = color;
    for (CALayer *dot in _dots) dot.backgroundColor = color.CGColor;
}

- (void)setStatus:(NSString *)text kind:(ExteriaStatusKind)kind {
    if ([self.text isEqualToString:text] && kind == _kind) return;
    BOOL dotsChange = (kind == ExteriaStatusTyping) != (_kind == ExteriaStatusTyping);
    _kind = kind;
    self.text = text;
    [self applyColor];
    if (dotsChange) [self setNeedsDisplay];
    if (kind == ExteriaStatusTyping) [self makeDots];
    else [self dropDots];
    [self setNeedsLayout];
}

#pragma mark dots

- (CGFloat)dotSide {
    return MAX(3, floor(self.font.pointSize * 0.28));
}

- (CGFloat)dotGap {
    return MAX(2, floor(self.font.pointSize * 0.16));
}

/* the room the dots take, with the space between them and the words */
- (CGFloat)dotsWidth {
    if (_kind != ExteriaStatusTyping) return 0;
    return [self dotGap] * 1.5 + DOT_COUNT * [self dotSide] + (DOT_COUNT - 1) * [self dotGap];
}

- (void)makeDots {
    if (_dots) return;
    NSMutableArray *dots = [NSMutableArray array];
    for (int i = 0; i < DOT_COUNT; ++i) {
        CALayer *dot = [CALayer layer];
        dot.backgroundColor = _activeColor.CGColor;
        dot.opacity = 0.3f;
        [self.layer addSublayer:dot];
        [dots addObject:dot];
    }
    _dots = [dots retain];
    [self startDots];
}

- (void)dropDots {
    for (CALayer *dot in _dots) [dot removeFromSuperlayer];
    [_dots release];
    _dots = nil;
}

/* each dot lights up and fades in turn; the animation runs on the render server, so the label itself is not redrawn */
- (void)startDots {
    CFTimeInterval now = CACurrentMediaTime();
    for (NSUInteger i = 0; i < _dots.count; ++i) {
        CALayer *dot = [_dots objectAtIndex:i];
        CAKeyframeAnimation *light = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        light.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.3f], [NSNumber numberWithFloat:1], [NSNumber numberWithFloat:0.3f],
                        [NSNumber numberWithFloat:0.3f], nil];
        light.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.25f], [NSNumber numberWithFloat:0.5f],
                          [NSNumber numberWithFloat:1], nil];
        light.duration = DOT_PERIOD;
        light.repeatCount = HUGE_VALF;
        light.beginTime = now + i * DOT_STAGGER;
        light.fillMode = kCAFillModeBackwards;
        [dot removeAnimationForKey:ExteriaDotKey];
        [dot addAnimation:light forKey:ExteriaDotKey];
    }
}

/* the system drops layer animations when the app goes to the background, so the dots start again when the label is on a window */
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && _dots) [self startDots];
}

#pragma mark drawing

/* UILabel draws a box for every character of a name that the system font lacks (styled letters, rare symbols), so
   the words go through the text layout that the names use */
- (ExteriaTextLayout *)layoutForWidth:(CGFloat)width {
    CGFloat size = self.font.pointSize;
    while (size > STATUS_MIN_SIZE && ExteriaStringSize(self.text, [self.font fontWithSize:size]).width > width) size -= 1;
    return [ExteriaTextLayout layoutForName:self.text font:[self.font fontWithSize:size] color:self.textColor width:MAX(1, width)];
}

/* where the words stand inside area, by the alignment of the label */
- (CGRect)textRectInArea:(CGRect)area layout:(ExteriaTextLayout *)layout {
    CGFloat room = area.size.width - layout.size.width;
    CGFloat x = area.origin.x;
    if (self.textAlignment == ExteriaTextAlignmentCenter) x += floor(room / 2);
    else if (self.textAlignment == ExteriaTextAlignmentRight) x += room;
    return CGRectMake(x, area.origin.y + floor((area.size.height - layout.size.height) / 2), layout.size.width, layout.size.height);
}

- (void)drawTextInRect:(CGRect)rect {
    if (!self.text.length) return;
    CGRect area = self.bounds;
    CGFloat dots = MIN([self dotsWidth], area.size.width);
    area.size.width -= dots;
    area.origin.x += dots;
    ExteriaTextLayout *layout = [self layoutForWidth:area.size.width];
    NSUInteger misses = ExteriaEmojiMissCount();
    [layout drawAtPoint:[self textRectInArea:area layout:layout].origin];
    if (ExteriaEmojiMissCount() != misses) ExteriaEmojiRedrawWhenLoaded(self);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_dots.count) return;
    CGRect area = self.bounds;
    CGFloat dots = MIN([self dotsWidth], area.size.width);
    area.origin.x += dots;
    area.size.width -= dots;
    CGRect text = [self textRectInArea:area layout:[self layoutForWidth:area.size.width]];
    CGFloat side = [self dotSide], gap = [self dotGap];
    CGFloat x = CGRectGetMinX(text) - dots;
    CGFloat y = CGRectGetMidY(text) - side / 2;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _dots.count; ++i) {
        CALayer *dot = [_dots objectAtIndex:i];
        dot.frame = CGRectMake(x + i * (side + gap), y, side, side);
        dot.cornerRadius = side / 2;
    }
    [CATransaction commit];
}

@end

NSString *ExteriaTypingStatusText(int action, NSUInteger count) {
    if (count == 0 || action == EXTERIA_TYPING_CANCEL) return nil;
    if (count > 1) return [NSString stringWithFormat:NSLocalizedString(@"status.typing.many", nil), (unsigned long)count];
    switch ((exteria_typing_action)action) {
    case EXTERIA_TYPING_VOICE: return NSLocalizedString(@"status.typing.voice", nil);
    case EXTERIA_TYPING_PHOTO: return NSLocalizedString(@"status.typing.photo", nil);
    case EXTERIA_TYPING_VIDEO: return NSLocalizedString(@"status.typing.video", nil);
    case EXTERIA_TYPING_FILE: return NSLocalizedString(@"status.typing.file", nil);
    case EXTERIA_TYPING_STICKER: return NSLocalizedString(@"status.typing.sticker", nil);
    default: return NSLocalizedString(@"status.typing", nil);
    }
}

NSString *ExteriaTypingStatusTextNamed(int action, NSUInteger count, NSArray *names) {
    if (count == 0 || action == EXTERIA_TYPING_CANCEL) return nil;
    if (count == 2 && names.count == 2) return [NSString stringWithFormat:NSLocalizedString(@"status.named.two", nil), [names objectAtIndex:0], [names objectAtIndex:1]];
    if (count != 1 || names.count != 1) return ExteriaTypingStatusText(action, count);
    NSString *key;
    switch ((exteria_typing_action)action) {
    case EXTERIA_TYPING_VOICE: key = @"status.named.voice"; break;
    case EXTERIA_TYPING_PHOTO: key = @"status.named.photo"; break;
    case EXTERIA_TYPING_VIDEO: key = @"status.named.video"; break;
    case EXTERIA_TYPING_FILE: key = @"status.named.file"; break;
    case EXTERIA_TYPING_STICKER: key = @"status.named.sticker"; break;
    default: key = @"status.named.typing"; break;
    }
    return [NSString stringWithFormat:NSLocalizedString(key, nil), [names objectAtIndex:0]];
}

/* a private chat is the person itself, so its row says only what they do; a group names who */
NSString *ExteriaTypingTextForDialog(ExteriaTypingBoard *board, ExteriaDialog *dialog) {
    NSUInteger count = [board countInDialog:dialog];
    int action = [board actionInDialog:dialog];
    if (dialog.peerKind == 1) return ExteriaTypingStatusText(action, count);
    return ExteriaTypingStatusTextNamed(action, count, [board namesInDialog:dialog]);
}
