#import "exteria_progress_bar.h"

#import <QuartzCore/QuartzCore.h>

@interface ExteriaProgressBar () {
    CALayer *_track;
    CALayer *_fill;
    float _progress;
    UIColor *_fillColor;
}
@end

@implementation ExteriaProgressBar

@synthesize progress = _progress;
@synthesize fillColor = _fillColor;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    _fillColor = [[UIColor whiteColor] retain];
    _track = [[CALayer layer] retain];
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.28f].CGColor;
    [self.layer addSublayer:_track];
    _fill = [[CALayer layer] retain];
    _fill.backgroundColor = _fillColor.CGColor;
    [self.layer addSublayer:_fill];
    return self;
}

- (void)dealloc {
    [_track release];
    [_fill release];
    [_fillColor release];
    [super dealloc];
}

- (void)setFillColor:(UIColor *)color {
    if (color == _fillColor) return;
    [_fillColor release];
    _fillColor = [color retain];
    _fill.backgroundColor = _fillColor.CGColor;
}

- (void)setProgress:(float)progress {
    _progress = MAX(0, MIN(1, progress));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat radius = size.height / 2;
    /* the fill follows the figure at once: a layer animates its own frame, and a bar that glides behind the numbers lags the download it shows */
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _track.frame = self.bounds;
    _track.cornerRadius = radius;
    _fill.frame = CGRectMake(0, 0, MAX(_progress > 0 ? size.height : 0, size.width * _progress), size.height);
    _fill.cornerRadius = radius;
    [CATransaction commit];
}

@end
