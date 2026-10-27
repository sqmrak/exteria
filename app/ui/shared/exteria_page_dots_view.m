#import "exteria_page_dots_view.h"

#import "exteria_theme.h"
#import "exteria_welcome.h"

@interface ExteriaPageDotsView () {
    NSInteger _pages;
    CGFloat _diameter;
    double _progress;
}
@end

@implementation ExteriaPageDotsView

@synthesize pages = _pages;
@synthesize diameter = _diameter;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    return self;
}

- (void)setProgress:(double)progress {
    if (progress == _progress) return;
    _progress = progress;
    [self setNeedsDisplay];
}

- (void)setPages:(NSInteger)pages {
    _pages = pages;
    [self setNeedsDisplay];
}

- (void)setDiameter:(CGFloat)diameter {
    _diameter = diameter;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (_pages < 1) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat pitch = self.bounds.size.width / _pages;
    CGFloat red[2], green[2], blue[2], alpha[2];
    [ExteriaColorDotOff() getRed:&red[0] green:&green[0] blue:&blue[0] alpha:&alpha[0]];
    [ExteriaColorAccent() getRed:&red[1] green:&green[1] blue:&blue[1] alpha:&alpha[1]];
    for (NSInteger i = 0; i < _pages; ++i) {
        CGFloat weight = (CGFloat)exteria_pager_dot_weight(_progress, (int)i);
        CGFloat size = _diameter * (1 + 0.2 * weight);
        CGContextSetRGBFillColor(context,
                                 red[0] + (red[1] - red[0]) * weight,
                                 green[0] + (green[1] - green[0]) * weight,
                                 blue[0] + (blue[1] - blue[0]) * weight, 1.0);
        CGContextFillEllipseInRect(context, CGRectMake((i + 0.5) * pitch - size / 2,
                                                       (self.bounds.size.height - size) / 2, size, size));
    }
}

@end
