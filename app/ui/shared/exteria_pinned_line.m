#import "exteria_pinned_line.h"

#import "exteria_theme.h"

#define PINNED_LINE_PADDING 7.0
#define PINNED_LINE_VISIBLE 3
#define PINNED_LINE_GAP 0.7

@implementation ExteriaPinnedLine

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)setPosition:(NSInteger)position total:(NSInteger)total {
    if (position == _position && total == _total) return;
    _position = position;
    _total = total;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (_total <= 0 || _position < 0 || _position >= _total) return;
    CGFloat height = self.bounds.size.height;
    CGFloat width = self.bounds.size.width;
    CGFloat segment = (height - PINNED_LINE_PADDING * 2) / (CGFloat)MIN(_total, PINNED_LINE_VISIBLE);
    if (segment <= 0) return;
    /* the shown pin sits in the middle of the three, and the list stops sliding at either end */
    CGFloat offset = (_position - 1) * segment;
    CGFloat maxOffset = (_total - PINNED_LINE_VISIBLE) * segment;
    if (offset > maxOffset) offset = maxOffset;
    if (offset < 0) offset = 0;
    /* on the glossy blue plate of the classic bar the accent would sink into it, so the segments are the light blue of its status text */
    UIColor *accent = ExteriaThemeIsClassic() ? [UIColor colorWithRed:0.82 green:0.94 blue:1 alpha:1] : ExteriaColorAccent();
    for (NSInteger i = 0; i < _total; i++) {
        CGFloat y = PINNED_LINE_PADDING + i * segment - offset;
        if (y + segment < 0 || y > height) continue;
        CGRect box = CGRectMake(0, y + PINNED_LINE_GAP, width, segment - PINNED_LINE_GAP * 2);
        [(i == _position ? accent : [accent colorWithAlphaComponent:0.44]) set];
        [[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:width / 2] fill];
    }
}

@end
