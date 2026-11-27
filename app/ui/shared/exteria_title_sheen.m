#import "exteria_title_sheen.h"
#import <QuartzCore/QuartzCore.h>

#import "exteria_lite_mode.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

/* one crossing takes this long, and the band rests until the cycle is over */
#define SHEEN_SWEEP 1.6
#define SHEEN_CYCLE 8.0

@implementation ExteriaTitleSheen {
    CAGradientLayer *_band;
    CALayer *_cut;
    CGSize _cutSize;
    BOOL _dirty;
    BOOL _enabled;
}

@synthesize enabled = _enabled;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    self.hidden = YES;
    _enabled = YES;
    _dirty = YES;
    _band = [[CAGradientLayer layer] retain];
    _band.startPoint = CGPointMake(0, 0.5);
    _band.endPoint = CGPointMake(1, 0.5);
    _band.locations = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.42f], [NSNumber numberWithFloat:0.5f], [NSNumber numberWithFloat:0.58f], nil];
    [self.layer addSublayer:_band];
    _cut = [[CALayer layer] retain];
    self.layer.mask = _cut;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(conditionsChanged) name:ExteriaLiteModeDidChangeNotification object:nil];
    /* the name is nil where the system has no such notification, and a nil name would hear every notification of the app on ios 5 */
    NSString *motion = ExteriaReduceMotionChangedNotification();
    if (motion) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(conditionsChanged) name:motion object:nil];
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) return;
    _enabled = enabled;
    [self update];
}

- (void)invalidateMask {
    _dirty = YES;
}

- (void)refreshFromView:(UIView *)source {
    CGSize size = source.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    if (!_dirty && CGSizeEqualToSize(size, _cutSize)) return;
    _dirty = NO;
    _cutSize = size;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context) [source.layer renderInContext:context];
    UIImage *letters = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _cut.frame = CGRectMake(0, 0, size.width, size.height);
    _cut.contents = (id)letters.CGImage;
    _cut.contentsScale = letters.scale;
    CGFloat width = size.width;
    /* three widths wide, resting with its middle just off the left edge, so a crossing is a slide of 1.4 widths */
    _band.frame = CGRectMake(-1.7 * width, 0, 3 * width, size.height);
    [CATransaction commit];
    [self restart];
}

- (void)conditionsChanged {
    [self update];
}

- (BOOL)mayRun {
    return _enabled && ExteriaThemeIsOLED() && self.window && !ExteriaReduceMotionEnabled() && ExteriaLiteEnabled(EXTERIA_LITE_PARTICLES) &&
           ExteriaLiteClass() != EXTERIA_LITE_CLASS_LOW && _cutSize.width >= 1;
}

- (void)restart {
    [_band removeAnimationForKey:@"sheen"];
    [self update];
}

- (void)update {
    BOOL run = [self mayRun];
    BOOL running = [_band animationForKey:@"sheen"] != nil;
    self.hidden = !run;
    if (run && !running) {
        UIColor *accent = ExteriaColorAccent();
        _band.colors = [NSArray arrayWithObjects:(id)[accent colorWithAlphaComponent:0].CGColor, (id)[accent colorWithAlphaComponent:0.95f].CGColor,
                                                 (id)[accent colorWithAlphaComponent:0].CGColor, nil];
        CABasicAnimation *cross = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        cross.fromValue = [NSNumber numberWithFloat:0];
        cross.toValue = [NSNumber numberWithFloat:(float)(1.4 * _cutSize.width)];
        cross.duration = SHEEN_SWEEP;
        cross.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        /* the group is longer than the crossing, so the band waits off the title until the next one */
        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = [NSArray arrayWithObject:cross];
        group.duration = SHEEN_CYCLE;
        group.repeatCount = HUGE_VALF;
        [_band addAnimation:group forKey:@"sheen"];
    } else if (!run && running) {
        [_band removeAnimationForKey:@"sheen"];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self update];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_band release];
    [_cut release];
    [super dealloc];
}

@end
