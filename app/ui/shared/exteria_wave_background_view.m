#import "exteria_wave_background_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_settings.h"
#import "exteria_falling_view.h"
#import "exteria_lite_mode.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_wave.h"

#define TOP_DRIFT_SECONDS 7.0
#define BOTTOM_DRIFT_SECONDS 9.0
#define TOP_RIPPLE_SECONDS 3.2
#define BOTTOM_RIPPLE_SECONDS 4.0
/* a drifting wave must never uncover its screen edge, so the layer reaches this far past it */
#define WAVE_BLEED 0.09
#define RIPPLE_AMPLITUDE 0.03

/* one wave: a gradient seen through a shape; the ripple moves the shape, the drift moves the whole layer */
@interface ExteriaWaveLayer : CAGradientLayer {
    CAShapeLayer *_shape;
}
@end

@implementation ExteriaWaveLayer

- (id)init {
    self = [super init];
    if (!self) return nil;
    _shape = [[CAShapeLayer layer] retain];
    _shape.fillColor = [UIColor blackColor].CGColor;
    self.mask = _shape;
    self.anchorPoint = CGPointMake(0, 0);
    return self;
}

- (void)dealloc {
    [_shape release];
    [super dealloc];
}

- (CAShapeLayer *)shape {
    return _shape;
}

@end

@interface ExteriaWaveBackgroundView () {
    BOOL _animated;
    BOOL _plain;
    BOOL _scrolling;
    ExteriaWaveLayer *_top;
    ExteriaWaveLayer *_bottom;
    CGSize _builtSize;
    BOOL _observing;
    CALayer *_snapshotLayer;
    BOOL _topHiddenBeforeSnapshot;
    BOOL _bottomHiddenBeforeSnapshot;
    ExteriaFallingView *_boys;
}
@end

@implementation ExteriaWaveBackgroundView

@synthesize animated = _animated;
@synthesize plain = _plain;
@synthesize scrolling = _scrolling;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.opaque = YES;
    self.backgroundColor = [UIColor whiteColor];
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    /* the bleed of a wave only keeps a drifting wave from uncovering the edges of this view; unclipped it also showed above the view, as a stripe
       across a transparent bar that sits over its top edge */
    self.clipsToBounds = YES;
    _top =[[ExteriaWaveLayer alloc] init];
    _bottom = [[ExteriaWaveLayer alloc] init];
    [self.layer addSublayer:_top];
    [self.layer addSublayer:_bottom];
    /* the classic style is flat, so the login of that style has no waves either */
    [self syncWaveVisibility];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_boys stop];
    [_boys release];
    [_snapshotLayer release];
    [_top release];
    [_bottom release];
    [super dealloc];
}

- (void)setAnimated:(BOOL)animated {
    if (animated == _animated) return;
    _animated = animated;
    [self refreshMotion];
}

- (void)setPlain:(BOOL)plain {
    if (plain == _plain) return;
    _plain = plain;
    [self syncWaveVisibility];
    [self configureTopColors];
    [self refreshMotion];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (ExteriaThemeIsClassic()) {
        [ExteriaColorScreen() setFill];
        UIRectFill(self.bounds);
        return;
    }
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    /* tools/make_assets.py paints the launch images with the first pair of colours */
    static const CGFloat welcome[] = {0.988, 0.980, 1.0, 1.0, 0.910, 0.839, 0.957, 1.0};
    static const CGFloat signedIn[] = {0.984, 0.980, 0.996, 1.0, 0.965, 0.957, 0.992, 1.0};
    static const CGFloat signedInDark[] = {0.094, 0.080, 0.137, 1.0, 0.070, 0.060, 0.106, 1.0};
    static const CGFloat welcomeDark[] = {0.110, 0.086, 0.165, 1.0, 0.160, 0.098, 0.220, 1.0};
    ExteriaFillGradient(UIGraphicsGetCurrentContext(), CGPointMake(0, 0), CGPointMake(0, h), _plain ? (ExteriaThemeIsDark() ? signedInDark : signedIn) : (ExteriaThemeIsDark() ? welcomeDark : welcome), 2);
    (void)w;
}

/* the outline of one wave in coordinates local to its layer; the amplitude is the ripple height, and its sign picks the phase */
- (CGPathRef)newPathForTop:(BOOL)top amplitude:(CGFloat)amplitude {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat bleed = WAVE_BLEED * w;
    /* the waves keep the proportions of a 4:3 tablet, so a tall phone gets shorter waves, not stretched ones */
    CGFloat span = MIN(h, w * 4.0 / 3.0);
    CGMutablePathRef path = CGPathCreateMutable();
    if (top) {
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, 0.46 * w + bleed, 0);
        ExteriaAddWaveEdge(path, CGPointMake(0.46 * w + bleed, bleed), CGPointMake(0.30 * w + bleed, 0.28 * span + bleed),
                           CGPointMake(bleed, 0.36 * span + bleed), amplitude, 3.5);
        CGPathAddLineToPoint(path, NULL, 0, 0.36 * span + bleed);
    } else {
        CGFloat bw = 0.42 * w + bleed, bh = 0.45 * span + bleed;
        CGPathMoveToPoint(path, NULL, bw, bh);
        CGPathAddLineToPoint(path, NULL, bw, 0);
        CGPathAddLineToPoint(path, NULL, 0.42 * w, 0);
        ExteriaAddWaveEdge(path, CGPointMake(0.42 * w, 0), CGPointMake(0.16 * w, 0.17 * span),
                           CGPointMake(0, 0.45 * span), amplitude, 3.5);
        CGPathAddLineToPoint(path, NULL, 0, bh);
    }
    CGPathCloseSubpath(path);
    return path;
}

/* on the near white lists the corner is a pale lilac wash, so the status bar and title stay readable over it */
- (NSArray *)colorsForTop:(BOOL)top {
    if (top && _plain && ExteriaThemeIsDark()) {
        return [NSArray arrayWithObjects:(id)ExteriaThemeTinted([UIColor colorWithRed:0.42 green:0.22 blue:0.62 alpha:0.60]).CGColor,
                (id)ExteriaThemeTinted([UIColor colorWithRed:0.30 green:0.18 blue:0.48 alpha:0.10]).CGColor, nil];
    }
    if (top && _plain) {
        return [NSArray arrayWithObjects:(id)ExteriaThemeTinted([UIColor colorWithRed:0.80 green:0.62 blue:0.90 alpha:0.62]).CGColor,
                (id)ExteriaThemeTinted([UIColor colorWithRed:0.90 green:0.80 blue:0.96 alpha:0.18]).CGColor, nil];
    }
    if (ExteriaThemeIsDark()) {
        return [NSArray arrayWithObjects:(id)ExteriaThemeTinted([UIColor colorWithRed:0.40 green:0.20 blue:0.55 alpha:0.85]).CGColor,
                (id)ExteriaThemeTinted([UIColor colorWithRed:0.28 green:0.16 blue:0.44 alpha:0.40]).CGColor, nil];
    }
    return [NSArray arrayWithObjects:(id)ExteriaThemeTinted([UIColor colorWithRed:0.70 green:0.40 blue:0.76 alpha:0.92]).CGColor,
            (id)ExteriaThemeTinted([UIColor colorWithRed:0.82 green:0.64 blue:0.88 alpha:0.50]).CGColor, nil];
}

- (void)configureTopColors {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _top.colors = [self colorsForTop:YES];
    [CATransaction commit];
}

/* from and to are the gradient ends in view coordinates */
- (void)configure:(ExteriaWaveLayer *)layer top:(BOOL)top box:(CGRect)box from:(CGPoint)from to:(CGPoint)to {
    layer.frame = box;
    layer.colors = [self colorsForTop:top];
    layer.startPoint = CGPointMake((from.x - box.origin.x) / box.size.width, (from.y - box.origin.y) / box.size.height);
    layer.endPoint = CGPointMake((to.x - box.origin.x) / box.size.width, (to.y - box.origin.y) / box.size.height);
    layer.shape.frame = layer.bounds;
    CGPathRef path = [self newPathForTop:top amplitude:RIPPLE_AMPLITUDE * self.bounds.size.width];
    layer.shape.path = path;
    CGPathRelease(path);
}

- (void)rebuildWaves {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat bleed = WAVE_BLEED * w;
    CGFloat span = MIN(h, w * 4.0 / 3.0);
    [self configure:_top top:YES box:CGRectMake(-bleed, -bleed, 0.46 * w + bleed, 0.36 * span + bleed)
               from:CGPointMake(0, 0) to:CGPointMake(0.4 * w, 0.3 * span)];
    [self configure:_bottom top:NO box:CGRectMake(0.58 * w, h - 0.45 * span, 0.42 * w + bleed, 0.45 * span + bleed)
               from:CGPointMake(w, h) to:CGPointMake(0.6 * w, h - 0.35 * span)];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (CGSizeEqualToSize(_builtSize, self.bounds.size)) return;
    _builtSize = self.bounds.size;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self rebuildWaves];
    [CATransaction commit];
    [self refreshMotion];
}

static void ExteriaDrift(CALayer *layer, CGFloat dx, CGFloat dy, CFTimeInterval seconds) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position"];
    animation.fromValue = [NSValue valueWithCGPoint:CGPointZero];
    animation.toValue = [NSValue valueWithCGPoint:CGPointMake(dx, dy)];
    animation.additive = YES;
    animation.autoreverses = YES;
    animation.repeatCount = HUGE_VALF;
    animation.duration = seconds;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:animation forKey:@"drift"];
}

/* the edge swings between its ripple and the opposite one: the same points, so the path interpolates */
static void ExteriaRipple(ExteriaWaveLayer *layer, CGPathRef opposite, CFTimeInterval seconds) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
    animation.fromValue = (id)layer.shape.path;
    animation.toValue = (id)opposite;
    animation.autoreverses = YES;
    animation.repeatCount = HUGE_VALF;
    animation.duration = seconds;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer.shape addAnimation:animation forKey:@"ripple"];
}

/* the opposite ripple is the same outline with the ripple amplitude negated */
- (void)rippleLayer:(ExteriaWaveLayer *)layer seconds:(CFTimeInterval)seconds {
    if (!layer.shape.path) return;
    CGPathRef opposite = [self newPathForTop:layer == _top amplitude:-RIPPLE_AMPLITUDE * _builtSize.width];
    ExteriaRipple(layer, opposite, seconds);
    CGPathRelease(opposite);
}

/* one pause on the layer of the backdrop holds the drift and the ripple of both waves and their masks together */
- (void)applyScrolling {
    BOOL hold = _scrolling && (_top.animationKeys.count || _bottom.animationKeys.count);
    CALayer *layer = self.layer;
    if (hold) {
        if (layer.speed == 0) return;
        CFTimeInterval now = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
        layer.speed = 0;
        layer.timeOffset = now;
        return;
    }
    if (layer.speed != 0) return;
    CFTimeInterval held = layer.timeOffset;
    layer.speed = 1;
    layer.timeOffset = 0;
    layer.beginTime = 0;
    layer.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - held;
}

- (void)setScrolling:(BOOL)scrolling {
    if (scrolling == _scrolling) return;
    _scrolling = scrolling;
    [self applyScrolling];
}

/* the classic style is flat and the setting of the person can take the waves away; the plain look keeps only the top one */
- (void)syncWaveVisibility {
    BOOL none = ExteriaThemeIsClassic() || ExteriaChatFlagGet(ExteriaChatFlagHideWaves);
    _top.hidden = none;
    _bottom.hidden = none || _plain;
}

/* the setting of the person gives the corners of the screen to boykissers that fall in place of the waves */
- (void)syncBoykisser {
    BOOL on = ExteriaChatFlagGet(ExteriaChatFlagBoykisser) && self.window &&
        [UIApplication sharedApplication].applicationState == UIApplicationStateActive &&
        !ExteriaReduceMotionEnabled() && ExteriaLiteEnabled(EXTERIA_LITE_PARTICLES);
    if (on) {
        _top.hidden = _bottom.hidden = YES;
        if (!_boys) {
            _boys = [[ExteriaFallingView alloc] initWithFrame:self.bounds spriteNamed:@"boykisser"];
            _boys.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self addSubview:_boys];
        }
        _boys.frame = self.bounds;
        [_boys start];
        return;
    }
    [_boys stop];
    if (_boys) {
        [_boys removeFromSuperview];
        [_boys release];
        _boys = nil;
        /* the waves come back as the plain or the welcome look wants them */
        [self syncWaveVisibility];
    }
}

/* backgrounding drops running core animations, so they start again when the app becomes active */
- (void)refreshMotion {
    [self syncBoykisser];
    /* new animations start on a layer that runs, and are held again below when a list is still moving */
    _scrolling = NO;
    [self applyScrolling];
    [_top removeAnimationForKey:@"drift"];
    [_bottom removeAnimationForKey:@"drift"];
    [_top.shape removeAnimationForKey:@"ripple"];
    [_bottom.shape removeAnimationForKey:@"ripple"];
    if (ExteriaThemeIsClassic() || !_animated || !self.window || ExteriaReduceMotionEnabled() || !ExteriaLiteEnabled(EXTERIA_LITE_CHAT_BACKGROUND) ||
        _builtSize.width <= 0) return;
    CGFloat reach = 0.8 * WAVE_BLEED * _builtSize.width;
    ExteriaDrift(_top, reach, reach, TOP_DRIFT_SECONDS);
    [self rippleLayer:_top seconds:TOP_RIPPLE_SECONDS];
    /* the signed in screens keep only the top corner */
    if (_plain) return;
    ExteriaDrift(_bottom, -reach, -reach, BOTTOM_DRIFT_SECONDS);
    [self rippleLayer:_bottom seconds:BOTTOM_RIPPLE_SECONDS];
}

/* one wave as it is on the screen at this moment: the shape of its mask now and its place with the drift, filled with its gradient */
- (void)drawWave:(ExteriaWaveLayer *)wave inContext:(CGContextRef)context {
    if (wave.hidden || !wave.colors.count) return;
    CALayer *placed = wave.presentationLayer ? wave.presentationLayer : wave;
    CAShapeLayer *shape = wave.shape.presentationLayer ? (CAShapeLayer *)wave.shape.presentationLayer : wave.shape;
    CGPathRef path = shape.path;
    if (!path) return;
    CGSize size = wave.bounds.size;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (CFArrayRef)wave.colors, NULL);
    CGColorSpaceRelease(space);
    if (!gradient) return;
    CGContextSaveGState(context);
    /* the wave's anchor is its top left corner, so its position is where that corner is */
    CGContextTranslateCTM(context, placed.position.x, placed.position.y);
    CGContextAddPath(context, path);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(wave.startPoint.x * size.width, wave.startPoint.y * size.height),
                                CGPointMake(wave.endPoint.x * size.width, wave.endPoint.y * size.height),
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
}

- (void)beginSnapshot {
    if (_snapshotLayer || CGRectIsEmpty(self.bounds)) return;
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self drawWave:_top inContext:context];
    [self drawWave:_bottom inContext:context];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _snapshotLayer = [[CALayer layer] retain];
    _snapshotLayer.frame = self.bounds;
    _snapshotLayer.contents = (id)image.CGImage;
    _snapshotLayer.contentsScale = image.scale;
    [self.layer addSublayer:_snapshotLayer];
    _topHiddenBeforeSnapshot = _top.hidden;
    _bottomHiddenBeforeSnapshot = _bottom.hidden;
    _top.hidden = YES;
    _bottom.hidden = YES;
    [CATransaction commit];
}

- (void)endSnapshot {
    if (!_snapshotLayer) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_snapshotLayer removeFromSuperlayer];
    [_snapshotLayer release];
    _snapshotLayer = nil;
    _top.hidden = _topHiddenBeforeSnapshot;
    _bottom.hidden = _bottomHiddenBeforeSnapshot;
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_observing) [center removeObserver:self];
    _observing = NO;
    if (self.window) {
        [center addObserver:self selector:@selector(refreshMotion)
                       name:UIApplicationDidBecomeActiveNotification object:nil];
        NSString *motion = ExteriaReduceMotionChangedNotification();
        if (motion) [center addObserver:self selector:@selector(refreshMotion) name:motion object:nil];
        [center addObserver:self selector:@selector(refreshMotion) name:ExteriaLiteModeDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(refreshMotion) name:ExteriaChatSettingsDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(refreshMotion) name:UIApplicationDidEnterBackgroundNotification object:nil];
        _observing = YES;
    }
    [self refreshMotion];
}

@end
