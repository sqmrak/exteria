#import "exteria_emoji_text_view.h"

#import "exteria_emoji_store.h"
#include "exteria_text_class.h"
#include <math.h>

#define INPUT_RENDER_UNITS_MAX 16384

@class ExteriaEmojiInputOverlay;

@interface ExteriaEmojiTextView () {
    ExteriaEmojiInputOverlay *_emojiOverlay;
    NSString *_renderedText;
    NSData *_units;
    NSData *_spans;
    NSArray *_inputPositions;
    BOOL _offsetFailureLogged;
    UIColor *_emojiBackgroundColor;
    void (^_formatHandler)(void);
}
- (void)drawEmoji;
@end

@interface ExteriaEmojiInputOverlay : UIView
@property (nonatomic, assign) ExteriaEmojiTextView *textView;
@end

@implementation ExteriaEmojiInputOverlay
@synthesize textView = _textView;
- (void)drawRect:(CGRect)rect {
    (void)rect;
    [_textView drawEmoji];
}
@end

@implementation ExteriaEmojiTextView
@synthesize emojiBackgroundColor = _emojiBackgroundColor;
@synthesize formatHandler = _formatHandler;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _emojiOverlay = [[ExteriaEmojiInputOverlay alloc] initWithFrame:self.bounds];
    _emojiOverlay.textView = self;
    _emojiOverlay.backgroundColor = [UIColor clearColor];
    _emojiOverlay.opaque = NO;
    _emojiOverlay.userInteractionEnabled = NO;
    _emojiOverlay.isAccessibilityElement = NO;
    [self addSubview:_emojiOverlay];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshEmoji)
        name:UITextViewTextDidChangeNotification object:self];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _emojiOverlay.textView = nil;
    [_emojiOverlay release];
    [_renderedText release];
    [_units release];
    [_spans release];
    [_inputPositions release];
    [_emojiBackgroundColor release];
    [_formatHandler release];
    [super dealloc];
}

- (BOOL)becomeFirstResponder {
    BOOL became = [super becomeFirstResponder];
    if (became && _formatHandler) {
        UIMenuItem *item = [[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"fmt.menu", nil) action:@selector(exteriaFormat:)] autorelease];
        [UIMenuController sharedMenuController].menuItems = [NSArray arrayWithObject:item];
    }
    return became;
}

- (BOOL)resignFirstResponder {
    if ([UIMenuController sharedMenuController].menuItems.count) [UIMenuController sharedMenuController].menuItems = nil;
    return [super resignFirstResponder];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(exteriaFormat:)) return _formatHandler != nil && self.text.length > 0;
    return [super canPerformAction:action withSender:sender];
}

- (void)exteriaFormat:(id)sender {
    (void)sender;
    if (_formatHandler) _formatHandler();
}

- (void)setEmojiBackgroundColor:(UIColor *)color {
    if (color == _emojiBackgroundColor) return;
    [_emojiBackgroundColor release];
    _emojiBackgroundColor = [color retain];
    [_emojiOverlay setNeedsDisplay];
}

- (void)refreshEmoji {
    NSString *text = self.text;
    if (![_renderedText isEqualToString:text]) {
        [_renderedText release];
        _renderedText = [text copy];
        [_spans release];
        _spans = nil;
        [_units release];
        _units = nil;
        [_inputPositions release];
        _inputPositions = nil;
        _offsetFailureLogged = NO;
        NSUInteger length = text.length;
        if (length && length <= INPUT_RENDER_UNITS_MAX) {
            NSMutableData *units = [NSMutableData dataWithLength:length * sizeof(uint16_t)];
            NSMutableData *spans = [NSMutableData dataWithLength:length * sizeof(exteria_emoji_span)];
            [text getCharacters:units.mutableBytes range:NSMakeRange(0, length)];
            size_t count = exteria_emoji_scan(units.bytes, length, spans.mutableBytes, length);
            [spans setLength:count * sizeof(exteria_emoji_span)];
            _units = [units retain];
            _spans = [spans retain];
        } else if (length) {
            NSLog(@"exteria: input emoji rendering exceeds %d UTF-16 units", INPUT_RENDER_UNITS_MAX);
        }
    }
    [_emojiOverlay setNeedsDisplay];
}

- (void)setText:(NSString *)text {
    [_inputPositions release];
    _inputPositions = nil;
    [super setText:text];
    [self refreshEmoji];
}

- (void)insertText:(NSString *)text {
    [_inputPositions release];
    _inputPositions = nil;
    [super insertText:text];
    [self refreshEmoji];
}

- (void)deleteBackward {
    [_inputPositions release];
    _inputPositions = nil;
    [super deleteBackward];
    [self refreshEmoji];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _emojiOverlay.frame = self.bounds;
    [self bringSubviewToFront:_emojiOverlay];
    [_emojiOverlay setNeedsDisplay];
}

- (BOOL)mapInputPositions {
    if (_inputPositions) return YES;
    NSUInteger length = _renderedText.length;
    NSMutableArray *positions = [NSMutableArray arrayWithCapacity:length + 1];
    UITextPosition *current = self.beginningOfDocument;
    if (current) [positions addObject:current];
    NSUInteger at = 0;
    while (current && at < length) {
        UITextPosition *next = [self positionFromPosition:current offset:1];
        if (!next || [self comparePosition:current toPosition:next] != NSOrderedAscending) break;
        UITextRange *range = [self textRangeFromPosition:current toPosition:next];
        NSString *fragment = range ? [self textInRange:range] : nil;
        NSUInteger units = fragment.length;
        if (!units || units > length - at ||
            [_renderedText compare:fragment options:NSLiteralSearch range:NSMakeRange(at, units)] != NSOrderedSame) break;
        /* ios 6 steps over a whole emoji even though offsetFromPosition reports its UTF-16 length */
        for (NSUInteger part = 1; part < units; ++part) [positions addObject:current];
        [positions addObject:next];
        at += units;
        current = next;
    }
    UITextPosition *end = self.endOfDocument;
    if (at != length || !current || !end || [self comparePosition:current toPosition:end] != NSOrderedSame) {
        if (!_offsetFailureLogged) NSLog(@"exteria: input positions cover %lu of %lu UTF-16 units", (unsigned long)at, (unsigned long)length);
        _offsetFailureLogged = YES;
        return NO;
    }
    _inputPositions = [positions copy];
    return YES;
}

- (CGRect)emojiRectForRange:(NSRange)range {
    if (range.location >= _inputPositions.count || range.length >= _inputPositions.count - range.location) return CGRectZero;
    UITextPosition *from = [_inputPositions objectAtIndex:range.location];
    UITextPosition *to = [_inputPositions objectAtIndex:NSMaxRange(range)];
    if ([self comparePosition:from toPosition:to] == NSOrderedSame) return CGRectZero;
    UITextRange *textRange = [self textRangeFromPosition:from toPosition:to];
    if (!textRange) return CGRectZero;
    CGRect rect = [self firstRectForRange:textRange];
    UIView *input = [self respondsToSelector:@selector(textInputView)] ? self.textInputView : self;
    return [_emojiOverlay convertRect:rect fromView:input ? input : self];
}

- (void)drawEmoji {
    if (!_emojiBackgroundColor || !_spans.length || ![self mapInputPositions]) return;
    const exteria_emoji_span *spans = _spans.bytes;
    const uint16_t *units = _units.bytes;
    size_t length = _units.length / sizeof(uint16_t);
    NSUInteger misses = ExteriaEmojiMissCount();
    for (size_t i = 0; i < _spans.length / sizeof(*spans); ++i) {
        exteria_emoji_span span = spans[i];
        if (!ExteriaEmojiHasPicture(span.entry)) continue;
        CGRect rectangles[32];
        size_t count = 0;
        /* ios 5 can lay an unsupported ZWJ sequence out as several glyphs */
        for (size_t at = span.start; at < span.start + span.length && count < 32;) {
            uint32_t point;
            size_t used = exteria_utf16_next(units, length, at, &point);
            if (!used) break;
            CGRect rect = [self emojiRectForRange:NSMakeRange(at, used)];
            at += used;
            if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
                !isfinite(rect.size.width) || !isfinite(rect.size.height) || CGRectIsEmpty(rect)) continue;
            if (count && fabs(CGRectGetMidY(rectangles[count - 1]) - CGRectGetMidY(rect)) < 2) {
                rectangles[count - 1] = CGRectUnion(rectangles[count - 1], rect);
            } else rectangles[count++] = rect;
        }
        if (!count) continue;
        /* the pack decodes on a queue; a blank frame would leave the glyph's empty box showing until it lands */
        UIImage *image = ExteriaEmojiImageNow(span.entry);
        for (size_t part = 0; part < count; ++part) {
            CGRect rect = rectangles[part];
            if (!CGRectIntersectsRect(_emojiOverlay.bounds, rect)) continue;
            /* the native glyph is replaced only in its own room, without changing Unicode offsets */
            [_emojiBackgroundColor setFill];
            UIRectFill(rect);
            if (NSIntersectionRange(self.selectedRange, NSMakeRange(span.start, span.length)).length) {
                [[UIColor colorWithRed:0.3 green:0.6 blue:1 alpha:0.3] setFill];
                UIRectFillUsingBlendMode(rect, kCGBlendModeNormal);
            }
            if (!part && image) {
                CGFloat side = MIN(MIN(rect.size.width, rect.size.height), ceil(self.font.lineHeight));
                [image drawInRect:CGRectMake(CGRectGetMidX(rect) - side / 2, CGRectGetMidY(rect) - side / 2, side, side)];
            }
        }
    }
    if (ExteriaEmojiMissCount() != misses) ExteriaEmojiRedrawWhenLoaded(_emojiOverlay);
}
@end
