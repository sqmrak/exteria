#import "exteria_media_action_view.h"

#import <QuartzCore/QuartzCore.h>

#include <math.h>

#import "exteria_platform.h"

/* the drawing is laid out for a 48 point button, and every length below is in those points */
#define BASE_SIDE 48.0
#define LINE_WIDTH 3.0
#define RING_INSET 4.0
#define RING_PERIOD 2.5
#define RING_START_DEGREES 112.0
#define MIN_ARC_DEGREES 4.0

#define DOWNLOAD_TO_CANCEL_STAGE1 0.5
#define DOWNLOAD_TO_CANCEL_STAGE2 0.2
#define DOWNLOAD_TO_CANCEL_STAGE3 0.3

static NSString *const ExteriaRingTurnKey = @"media.ring.turn";

static CGFloat ExteriaEase(CGFloat t) {
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    return t * t * (3 - 2 * t);
}

@interface ExteriaMediaActionView () {
    UIColor *_discColor;
    UIColor *_inkColor;
    ExteriaMediaIcon _current;
    ExteriaMediaIcon _next;
    CGFloat _transition;
    BOOL _animating;
    CFTimeInterval _duration;
    CFTimeInterval _lastTick;
    CADisplayLink *_link;
    CAShapeLayer *_ring;
    float _progress;
    CGSize _ringSize;
}
@end

@implementation ExteriaMediaActionView

@synthesize discColor = _discColor;
@synthesize inkColor = _inkColor;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    _inkColor = [[UIColor whiteColor] retain];
    _current = _next = ExteriaMediaIconPlay;
    _transition = 1;
    _ring = [[CAShapeLayer alloc] init];
    _ring.fillColor = NULL;
    _ring.lineCap = kCALineCapRound;
    _ring.opacity = 0;
    _ring.strokeEnd = MIN_ARC_DEGREES / 360.0;
    [self.layer addSublayer:_ring];
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_discColor release];
    [_inkColor release];
    [_ring release];
    [super dealloc];
}

- (ExteriaMediaIcon)icon {
    return _next;
}

- (CGFloat)unit {
    return MIN(self.bounds.size.width, self.bounds.size.height) / BASE_SIDE;
}

/* the disc goes with the glyph when the button leaves (a round message that plays) and comes back with it */
- (CGFloat)discAlpha {
    if (!_animating) return _next == ExteriaMediaIconNone ? 0 : 1;
    if (_next == ExteriaMediaIconNone) return 1 - _transition;
    if (_current == ExteriaMediaIconNone) return _transition;
    return 1;
}

- (void)applyDisc {
    CGFloat alpha = [self discAlpha];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.backgroundColor = _discColor ? [_discColor colorWithAlphaComponent:CGColorGetAlpha(_discColor.CGColor) * alpha].CGColor : NULL;
    [CATransaction commit];
}

- (void)setDiscColor:(UIColor *)color {
    if (color == _discColor) return;
    [_discColor release];
    _discColor = [color retain];
    [self applyDisc];
}

- (void)setInkColor:(UIColor *)color {
    if (color == _inkColor) return;
    [_inkColor release];
    _inkColor = [color retain];
    _ring.strokeColor = _inkColor.CGColor;
    [self setNeedsDisplay];
}

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _ringSize)) return;
    _ringSize = size;
    CGFloat unit = [self unit];
    self.layer.cornerRadius = MIN(size.width, size.height) / 2;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ring.bounds = self.bounds;
    _ring.position = CGPointMake(size.width / 2, size.height / 2);
    _ring.lineWidth = LINE_WIDTH * unit;
    _ring.strokeColor = _inkColor.CGColor;
    _ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(size.width / 2, size.height / 2) radius:MIN(size.width, size.height) / 2 - RING_INSET * unit
                                            startAngle:0 endAngle:(CGFloat)(M_PI * 2) clockwise:YES].CGPath;
    [CATransaction commit];
    [self syncRing];
}

#pragma mark ring

/* how much of the ring shows: the cross and the ring come together, and a ring that leaves goes with the cross */
- (CGFloat)ringAlpha {
    BOOL from = _current == ExteriaMediaIconCancel, to = _next == ExteriaMediaIconCancel;
    if (!_animating || (from && to)) return to ? 1 : 0;
    if (to) return _current == ExteriaMediaIconDownload ? MAX(0, (_transition - DOWNLOAD_TO_CANCEL_STAGE1) / (1 - DOWNLOAD_TO_CANCEL_STAGE1)) : _transition;
    if (from) return _next == ExteriaMediaIconDownload ? MAX(0, 1 - _transition / (DOWNLOAD_TO_CANCEL_STAGE2 + DOWNLOAD_TO_CANCEL_STAGE3)) : MAX(0, 1 - _transition * 2);
    return 0;
}

- (void)syncRing {
    CGFloat alpha = [self ringAlpha];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ring.opacity = (float)alpha;
    [CATransaction commit];
    BOOL turning = (_next == ExteriaMediaIconCancel || _current == ExteriaMediaIconCancel) && self.window != nil && !ExteriaReduceMotionEnabled() && alpha > 0;
    if (!turning) {
        [_ring removeAnimationForKey:ExteriaRingTurnKey];
        return;
    }
    if ([_ring animationForKey:ExteriaRingTurnKey]) return;
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    turn.fromValue = [NSNumber numberWithDouble:RING_START_DEGREES * M_PI / 180];
    turn.toValue = [NSNumber numberWithDouble:RING_START_DEGREES * M_PI / 180 + M_PI * 2];
    turn.duration = RING_PERIOD;
    turn.repeatCount = HUGE_VALF;
    turn.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_ring addAnimation:turn forKey:ExteriaRingTurnKey];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self endTransition];
        [self applyDisc];
        [self setNeedsDisplay];
    }
    [self syncRing];
}

- (void)setProgress:(float)progress {
    progress = progress < 0 ? 0 : (progress > 1 ? 1 : progress);
    if (progress == _progress) return;
    BOOL grows = progress > _progress;
    _progress = progress;
    CGFloat end = MAX(MIN_ARC_DEGREES / 360.0, progress);
    [CATransaction begin];
    if (grows && self.window && !ExteriaReduceMotionEnabled()) {
        [CATransaction setAnimationDuration:0.2];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    } else {
        [CATransaction setDisableActions:YES];
    }
    _ring.strokeEnd = end;
    [CATransaction commit];
}

#pragma mark transitions

/* how long a change takes, by the pair of glyphs */
static CFTimeInterval ExteriaTransitionSeconds(ExteriaMediaIcon from, ExteriaMediaIcon to) {
    if ((from == ExteriaMediaIconPlay && to == ExteriaMediaIconPause) || (from == ExteriaMediaIconPause && to == ExteriaMediaIconPlay)) return 0.3;
    if (from == ExteriaMediaIconDownload && to == ExteriaMediaIconCancel) return 0.4;
    return 0.22;
}

- (void)setIcon:(ExteriaMediaIcon)icon animated:(BOOL)animated {
    if (icon == _next) return;
    if (animated && self.window && !ExteriaReduceMotionEnabled()) {
        /* a change that comes while another is on its way starts from where that one was going */
        if (_animating) _current = _next;
        _next = icon;
        _transition = 0;
        _animating = YES;
        _duration = ExteriaTransitionSeconds(_current, _next);
        if (icon == ExteriaMediaIconCancel && _current != ExteriaMediaIconCancel) {
            /* a new download starts empty */
            [_ring removeAnimationForKey:ExteriaRingTurnKey];
            _progress = 0;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _ring.strokeEnd = MIN_ARC_DEGREES / 360.0;
            [CATransaction commit];
        }
        _lastTick = CACurrentMediaTime();
        if (!_link) {
            _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
            [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
    } else {
        [self endTransition];
        _current = _next = icon;
        _transition = 1;
        if (icon == ExteriaMediaIconCancel) {
            _progress = 0;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _ring.strokeEnd = MIN_ARC_DEGREES / 360.0;
            [CATransaction commit];
        }
    }
    [self syncRing];
    [self applyDisc];
    [self setNeedsDisplay];
}

- (void)endTransition {
    [_link invalidate];
    [_link release];
    _link = nil;
    if (_animating) _current = _next;
    _animating = NO;
    _transition = 1;
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = MIN(now - _lastTick, 1.0 / 30);
    _lastTick = now;
    _transition += (CGFloat)(dt / _duration);
    if (_transition >= 1) {
        [self endTransition];
        _current = _next;
    }
    [self syncRing];
    [self applyDisc];
    [self setNeedsDisplay];
}

#pragma mark drawing

static void ExteriaLine(CGContextRef context, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGContextMoveToPoint(context, x1, y1);
    CGContextAddLineToPoint(context, x2, y2);
    CGContextStrokePath(context);
}

static void ExteriaArc(CGContextRef context, CGFloat cx, CGFloat cy, CGFloat radius, CGFloat startDegrees, CGFloat sweepDegrees) {
    CGContextAddArc(context, cx, cy, radius, startDegrees * (CGFloat)M_PI / 180, (startDegrees + sweepDegrees) * (CGFloat)M_PI / 180, 0);
    CGContextStrokePath(context);
}

- (void)setInk:(CGContextRef)context alpha:(CGFloat)alpha {
    CGFloat unit = [self unit];
    CGContextSetStrokeColorWithColor(context, [_inkColor colorWithAlphaComponent:alpha * CGColorGetAlpha(_inkColor.CGColor)].CGColor);
    CGContextSetFillColorWithColor(context, [_inkColor colorWithAlphaComponent:alpha * CGColorGetAlpha(_inkColor.CGColor)].CGColor);
    CGContextSetLineWidth(context, LINE_WIDTH * unit);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
}

/* the arrow of a file that has not come, or the cross, with their scale and turn */
static void ExteriaDrawCross(CGContextRef context, CGFloat cx, CGFloat cy, CGFloat half) {
    ExteriaLine(context, cx - half, cy - half, cx + half, cy + half);
    ExteriaLine(context, cx + half, cy - half, cx - half, cy + half);
}

/* the arrow turns into the cross in three stages: the arrow folds into a bar at the bottom, an arc swings out of
   its foot, and the cross grows out of the arc */
- (void)drawArrowAndCross:(CGContextRef)context folding:(CGFloat)t {
    CGFloat unit = [self unit];
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    CGFloat yStart = cy - 9 * unit, yEnd = cy + 9 * unit;
    CGFloat yStart2 = cy + 1 * unit, yEnd2 = cy + 12 * unit;
    CGFloat y1, y2, x1, x2, y3;
    if (t <= DOWNLOAD_TO_CANCEL_STAGE1) {
        CGFloat forward = t / DOWNLOAD_TO_CANCEL_STAGE1, back = 1 - forward;
        y1 = yStart + (yStart2 - yStart) * forward;
        y2 = yEnd + (yEnd2 - yEnd) * forward;
        x1 = cx - 8 * back * unit;
        x2 = cx + 8 * back * unit;
        y3 = y2 - 8 * back * unit;
    } else {
        CGFloat progress = t - DOWNLOAD_TO_CANCEL_STAGE1;
        CGFloat third = progress / (DOWNLOAD_TO_CANCEL_STAGE2 + DOWNLOAD_TO_CANCEL_STAGE3);
        CGFloat first, second;
        if (progress > DOWNLOAD_TO_CANCEL_STAGE2) {
            progress -= DOWNLOAD_TO_CANCEL_STAGE2;
            first = 1;
            second = progress / DOWNLOAD_TO_CANCEL_STAGE3;
        } else {
            first = progress / DOWNLOAD_TO_CANCEL_STAGE2;
            second = 0;
        }
        CGFloat d = 13 * unit * unit;
        CGFloat start = 100 * second;
        ExteriaArc(context, cx - d / 2, yEnd2, d / 2, start, 104 * third - start);
        y1 = yStart2 + (yEnd2 - yStart2) * first;
        y2 = y3 = yEnd2;
        x1 = x2 = cx;
        if (second > 0) {
            CGContextSaveGState(context);
            CGContextTranslateCTM(context, cx, cy);
            CGContextRotateCTM(context, -45 * (1 - second) * (CGFloat)M_PI / 180);
            CGContextTranslateCTM(context, -cx, -cy);
            [self setInk:context alpha:second];
            ExteriaDrawCross(context, cx, cy, 7 * second * unit);
            CGContextRestoreGState(context);
            [self setInk:context alpha:1];
        }
    }
    if (y1 != y2) ExteriaLine(context, cx, y1, cx, y2);
    if (x1 != cx) {
        ExteriaLine(context, x1, y3, cx, y2);
        ExteriaLine(context, x2, y3, cx, y2);
    }
}

/* the triangle and the two bars are one shape in two halves, mirrored about the middle */
- (void)drawPlay:(CGContextRef)context toPause:(CGFloat)p scale:(CGFloat)scale alpha:(CGFloat)alpha {
    if (scale <= 0 || alpha <= 0) return;
    static const CGPoint triangle[4] = {{-6, -9}, {9, 0}, {9, 0}, {-6, 0}};
    static const CGPoint bar[4] = {{-9, -7}, {9, -7}, {9, -2.5}, {-9, -2.5}};
    CGFloat unit = [self unit];
    CGFloat shaped = ExteriaEase(p);
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    [self setInk:context alpha:alpha];
    CGContextSetLineWidth(context, 1.4 * unit);
    for (int half = 0; half < 2; ++half) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, cx + 1 * (1 - shaped) * unit, cy);
        CGContextRotateCTM(context, 90 * shaped * (CGFloat)M_PI / 180);
        CGContextScaleCTM(context, scale * unit, (half ? -1 : 1) * scale * unit);
        for (int i = 0; i < 4; ++i) {
            CGFloat x = triangle[i].x + (bar[i].x - triangle[i].x) * shaped;
            CGFloat y = triangle[i].y + (bar[i].y - triangle[i].y) * shaped;
            if (i == 0) CGContextMoveToPoint(context, x, y);
            else CGContextAddLineToPoint(context, x, y);
        }
        CGContextClosePath(context);
        CGContextDrawPath(context, kCGPathFillStroke);
        CGContextRestoreGState(context);
    }
    [self setInk:context alpha:1];
}

/* one glyph at rest, with a scale, a turn and an opacity */
- (void)drawGlyph:(ExteriaMediaIcon)icon context:(CGContextRef)context scale:(CGFloat)scale rotation:(CGFloat)rotation alpha:(CGFloat)alpha {
    if (scale <= 0 || alpha <= 0) return;
    CGFloat unit = [self unit];
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    switch (icon) {
    case ExteriaMediaIconPlay: [self drawPlay:context toPause:0 scale:scale alpha:alpha]; return;
    case ExteriaMediaIconPause: [self drawPlay:context toPause:1 scale:scale alpha:alpha]; return;
    case ExteriaMediaIconNone: return;
    case ExteriaMediaIconFile: {
        /* a page of 16 by 22 points with its upper right corner folded over: the fold is cut out of the page in
           the color of the disc */
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, cx, cy);
        CGContextRotateCTM(context, rotation * (CGFloat)M_PI / 180);
        CGContextScaleCTM(context, scale * unit, scale * unit);
        [self setInk:context alpha:alpha];
        CGContextSetLineWidth(context, 1.2);
        CGContextMoveToPoint(context, -8, -11);
        CGContextAddLineToPoint(context, 2, -11);
        CGContextAddLineToPoint(context, 8, -5);
        CGContextAddLineToPoint(context, 8, 11);
        CGContextAddLineToPoint(context, -8, 11);
        CGContextClosePath(context);
        CGContextDrawPath(context, kCGPathFillStroke);
        CGColorRef back = _discColor ? _discColor.CGColor : [UIColor colorWithWhite:0 alpha:0.45f].CGColor;
        CGContextSetFillColorWithColor(context, back);
        CGContextMoveToPoint(context, 2, -11);
        CGContextAddLineToPoint(context, 2, -5);
        CGContextAddLineToPoint(context, 8, -5);
        CGContextClosePath(context);
        CGContextDrawPath(context, kCGPathFillStroke);
        CGContextRestoreGState(context);
        [self setInk:context alpha:1];
        return;
    }
    default: break;
    }
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, cx, cy);
    CGContextRotateCTM(context, rotation * (CGFloat)M_PI / 180);
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, -cx, -cy);
    [self setInk:context alpha:alpha];
    if (icon == ExteriaMediaIconCancel) {
        ExteriaDrawCross(context, cx, cy, 7 * unit);
    } else {
        ExteriaLine(context, cx, cy - 9 * unit, cx, cy + 9 * unit);
        ExteriaLine(context, cx - 8 * unit, cy + 1 * unit, cx, cy + 9 * unit);
        ExteriaLine(context, cx + 8 * unit, cy + 1 * unit, cx, cy + 9 * unit);
    }
    CGContextRestoreGState(context);
    [self setInk:context alpha:1];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self setInk:context alpha:1];
    if (!_animating || _current == _next) {
        [self drawGlyph:_next context:context scale:1 rotation:0 alpha:1];
        return;
    }
    ExteriaMediaIcon from = _current, to = _next;
    CGFloat t = _transition;
    if ((from == ExteriaMediaIconDownload && to == ExteriaMediaIconCancel) || (from == ExteriaMediaIconCancel && to == ExteriaMediaIconDownload)) {
        [self drawArrowAndCross:context folding:from == ExteriaMediaIconDownload ? t : 1 - t];
        return;
    }
    if ((from == ExteriaMediaIconPlay && to == ExteriaMediaIconPause) || (from == ExteriaMediaIconPause && to == ExteriaMediaIconPlay)) {
        [self drawPlay:context toPause:to == ExteriaMediaIconPause ? t : 1 - t scale:1 alpha:1];
        return;
    }
    /* any other change: the glyph that leaves shrinks away, and the one that comes grows */
    CGFloat grow, shrink;
    if (from == ExteriaMediaIconNone || from == ExteriaMediaIconCancel) {
        grow = t;
        shrink = 1 - t;
    } else {
        grow = MIN(1, t / 0.5);
        shrink = MAX(0, 1 - t / 0.5);
    }
    [self drawGlyph:from context:context scale:shrink rotation:0 alpha:shrink];
    [self drawGlyph:to context:context scale:grow rotation:to == ExteriaMediaIconCancel ? 45 * (1 - t) : 0 alpha:grow];
}

@end
