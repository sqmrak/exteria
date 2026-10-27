#import "exteria_classic_shiro_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_classic_chrome.h"
#import "exteria_split_controller.h"
#import "exteria_main_controller.h"
#import "exteria_platform.h"
#import "exteria_shiro_fox_field.h"
#import "exteria_shiro_power_button.h"
#import "exteria_shiro_style.h"
#import "exteria_theme.h"

#define ENTER_SECONDS 0.3
#define ORBIT_SPIN_KEY @"exteria.shiro.orbit.spin"
#define ORBIT_FADE_KEY @"exteria.shiro.orbit.fade"
#define ORBIT_PULSE_KEY @"exteria.shiro.orbit.pulse"
#define ORBIT_FADE_SECONDS 0.45
#define ORBIT_DOT_REST 0.2f

/* the palette of the ios 6 theme of shiro 1.0.0, light and dark */
static UIColor *ExteriaClassicShiroRGB(CGFloat lightR, CGFloat lightG, CGFloat lightB, CGFloat darkR, CGFloat darkG, CGFloat darkB) {
    return ExteriaThemeIsDark() ? [UIColor colorWithRed:darkR green:darkG blue:darkB alpha:1] : [UIColor colorWithRed:lightR green:lightG blue:lightB alpha:1];
}

static UIColor *ExteriaClassicShiroBackdropTop(void) { return ExteriaClassicShiroRGB(0.97, 0.90, 0.93, 0.24, 0.13, 0.19); }
static UIColor *ExteriaClassicShiroBackdropBottom(void) { return ExteriaClassicShiroRGB(0.90, 0.79, 0.84, 0.14, 0.07, 0.11); }
static UIColor *ExteriaClassicShiroInk(void) { return ExteriaClassicShiroRGB(0.12, 0.12, 0.14, 0.96, 0.96, 0.98); }
static UIColor *ExteriaClassicShiroInkMuted(void) { return ExteriaClassicShiroRGB(0.43, 0.43, 0.47, 0.73, 0.73, 0.77); }
static UIColor *ExteriaClassicShiroAccent(void) { return ExteriaClassicShiroRGB(0.78, 0.03, 0.38, 0.96, 0.16, 0.50); }
static UIColor *ExteriaClassicShiroCellHigh(void) { return ExteriaClassicShiroRGB(0.99, 0.99, 1.00, 0.33, 0.33, 0.36); }
static UIColor *ExteriaClassicShiroCellLow(void) { return ExteriaClassicShiroRGB(0.93, 0.93, 0.95, 0.22, 0.22, 0.25); }
static UIColor *ExteriaClassicShiroConnected(void) { return [UIColor colorWithRed:1.0 green:0.06 blue:0.39 alpha:1]; }
static UIColor *ExteriaClassicShiroError(void) { return [UIColor colorWithRed:0.95 green:0.30 blue:0.26 alpha:1]; }

/* a color moved toward white (amount above 0) or black (below 0) */
static UIColor *ExteriaClassicShiroShade(UIColor *color, CGFloat amount) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 1, white = 0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        if (![color getWhite:&white alpha:&alpha]) return color;
        red = green = blue = white;
    }
    CGFloat target = amount >= 0 ? 1 : 0, share = fabs(amount);
    return [UIColor colorWithRed:red + (target - red) * share green:green + (target - green) * share blue:blue + (target - blue) * share alpha:alpha];
}

static UIImage *ExteriaClassicShiroChevron(UIColor *color);

static CGPathRef ExteriaClassicShiroCircle(CGPoint center, CGFloat radius) {
    return [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:0 endAngle:(CGFloat)(M_PI * 2) clockwise:YES].CGPath;
}

static void ExteriaClassicShiroSilent(void (^changes)(void)) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    changes();
    [CATransaction commit];
}

#pragma mark orbit button

/* the power control: a disc in relief inside a thin ring, the power glyph on it, and a dot that circles the rim
   while the tunnel is made or up; the dot turns on the render server */
@interface ExteriaClassicOrbitButton : UIControl {
    CAShapeLayer *_track;
    CAShapeLayer *_halo;
    CAShapeLayer *_face;
    CAGradientLayer *_faceFill;
    CAGradientLayer *_faceSheen;
    CAShapeLayer *_ring;
    CAShapeLayer *_glyph;
    CALayer *_orbit;
    CAShapeLayer *_trail;
    CAShapeLayer *_dot;
    ExteriaShiroPowerState _powerState;
    BOOL _running;
    BOOL _orbitShown;
    CGSize _laidSize;
}
@property (nonatomic, assign) ExteriaShiroPowerState powerState;
- (void)setRunning:(BOOL)running;
- (void)applyTheme;
@end

@implementation ExteriaClassicOrbitButton

- (UIColor *)tint {
    switch (_powerState) {
    case ExteriaShiroPowerOn: return ExteriaClassicShiroConnected();
    case ExteriaShiroPowerFailed: return ExteriaClassicShiroError();
    default: return ExteriaClassicShiroAccent();
    }
}

- (CAShapeLayer *)shapeLayer {
    CAShapeLayer *layer = [[[CAShapeLayer alloc] init] autorelease];
    layer.fillColor = [UIColor clearColor].CGColor;
    [self.layer addSublayer:layer];
    return layer;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.exclusiveTouch = YES;
    _track = [[self shapeLayer] retain];
    _track.lineWidth = 1;
    _halo = [[self shapeLayer] retain];
    _halo.shadowOffset = CGSizeZero;
    _face = [[self shapeLayer] retain];
    _face.shadowColor = [UIColor blackColor].CGColor;
    _faceFill = [[CAGradientLayer alloc] init];
    _faceFill.startPoint = CGPointMake(0.5, 0);
    _faceFill.endPoint = CGPointMake(0.5, 1);
    _faceFill.masksToBounds = YES;
    [self.layer addSublayer:_faceFill];
    _faceSheen = [[CAGradientLayer alloc] init];
    _faceSheen.startPoint = CGPointMake(0.5, 0);
    _faceSheen.endPoint = CGPointMake(0.5, 1);
    [_faceFill addSublayer:_faceSheen];
    _ring = [[self shapeLayer] retain];
    _ring.shadowOffset = CGSizeZero;
    /* the glow is a blur of a still stroke; a cached bitmap keeps it from being drawn again on every frame the dot moves on armv7 */
    _ring.shouldRasterize = YES;
    _ring.rasterizationScale = [UIScreen mainScreen].scale;
    _glyph = [[self shapeLayer] retain];
    _glyph.lineCap = kCALineCapRound;
    _orbit = [[CALayer alloc] init];
    [self.layer addSublayer:_orbit];
    _trail = [[CAShapeLayer alloc] init];
    _trail.fillColor = [UIColor clearColor].CGColor;
    _trail.lineCap = kCALineCapRound;
    _trail.lineWidth = 2;
    [_orbit addSublayer:_trail];
    _dot = [[CAShapeLayer alloc] init];
    _dot.shadowOffset = CGSizeZero;
    _dot.shadowRadius = 5;
    _dot.shadowOpacity = 0.9f;
    [_orbit addSublayer:_dot];
    /* the dot starts off the ring: no tail, shrunk, transparent */
    _orbit.opacity = 0;
    _trail.strokeStart = 1;
    _dot.transform = CATransform3DMakeScale(ORBIT_DOT_REST, ORBIT_DOT_REST, 1);
    [self applyTheme];
    return self;
}

- (void)dealloc {
    [_track release];
    [_halo release];
    [_face release];
    [_faceFill release];
    [_faceSheen release];
    [_ring release];
    [_glyph release];
    [_trail release];
    [_dot release];
    [_orbit release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1 || CGSizeEqualToSize(size, _laidSize)) return;
    _laidSize = size;
    CGRect bounds = self.bounds;
    CGFloat side = MIN(size.width, size.height);
    CGPoint center = CGPointMake(size.width / 2, size.height / 2);
    CGFloat dotRadius = MAX(4, side * 0.018f);
    CGFloat trackRadius = side / 2 - dotRadius - 3;
    CGFloat ringRadius = trackRadius * 0.76f;
    CGFloat gap = ringRadius * 0.34f;
    CGFloat faceRadius = ringRadius - 1;
    UIBezierPath *power = [UIBezierPath bezierPathWithArcCenter:center radius:gap startAngle:(CGFloat)(-M_PI_2 + 0.62) endAngle:(CGFloat)(-M_PI_2 - 0.62 + M_PI * 2) clockwise:YES];
    [power moveToPoint:CGPointMake(center.x, center.y - gap * 1.22f)];
    [power addLineToPoint:CGPointMake(center.x, center.y - gap * 0.30f)];
    ExteriaClassicShiroSilent(^{
        _track.frame = bounds;
        _halo.frame = bounds;
        _face.frame = bounds;
        _ring.frame = bounds;
        _glyph.frame = bounds;
        _orbit.bounds = bounds;
        _orbit.position = center;
        _trail.frame = bounds;
        /* the dot is its own small layer so it grows from its center; a frame is undefined under the scale it rests at */
        _dot.bounds = CGRectMake(0, 0, dotRadius * 2, dotRadius * 2);
        _dot.position = CGPointMake(center.x + trackRadius, center.y);
        _track.path = ExteriaClassicShiroCircle(center, trackRadius);
        _halo.path = ExteriaClassicShiroCircle(center, ringRadius);
        _halo.shadowPath = _halo.path;
        _face.path = ExteriaClassicShiroCircle(center, faceRadius);
        _face.shadowPath = _face.path;
        _faceFill.frame = CGRectMake(center.x - faceRadius, center.y - faceRadius, faceRadius * 2, faceRadius * 2);
        _faceFill.cornerRadius = faceRadius;
        _faceSheen.frame = CGRectMake(0, 0, faceRadius * 2, faceRadius);
        _ring.path = ExteriaClassicShiroCircle(center, ringRadius);
        _ring.lineWidth = MAX(2.5f, side * 0.013f);
        _glyph.path = power.CGPath;
        _glyph.lineWidth = MAX(3, ringRadius * 0.075f);
        _trail.path = [UIBezierPath bezierPathWithArcCenter:center radius:trackRadius startAngle:-1.05f endAngle:0 clockwise:YES].CGPath;
        _dot.path = ExteriaClassicShiroCircle(CGPointMake(dotRadius, dotRadius), dotRadius);
        _dot.shadowPath = _dot.path;
    });
}

/* at rest the button is lit only by the theme; a tunnel that is up, dialing or failed gives it a dim halo in its state color */
- (void)applyTheme {
    UIColor *tint = [self tint];
    BOOL idle = _powerState == ExteriaShiroPowerOff;
    BOOL connected = _powerState == ExteriaShiroPowerOn;
    BOOL light = !ExteriaThemeIsDark();
    UIColor *faceColor = connected ? tint : ExteriaClassicShiroCellHigh();
    ExteriaClassicShiroSilent(^{
        _track.strokeColor = [tint colorWithAlphaComponent:0.22f].CGColor;
        _halo.fillColor = tint.CGColor;
        _halo.shadowColor = tint.CGColor;
        _halo.shadowRadius = 14;
        _halo.shadowOpacity = idle ? 0 : 0.32f;
        _halo.hidden = idle;
        _face.fillColor = ExteriaClassicShiroCellLow().CGColor;
        _face.shadowOffset = CGSizeMake(0, 3);
        _face.shadowRadius = 5;
        _face.shadowOpacity = light ? 0.22f : 0.5f;
        _faceFill.colors = [NSArray arrayWithObjects:(id)ExteriaClassicShiroShade(faceColor, 0.04f).CGColor, (id)ExteriaClassicShiroShade(faceColor, -0.14f).CGColor, nil];
        _faceSheen.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:1 alpha:light ? 0.30f : 0.12f].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor, nil];
        _ring.strokeColor = tint.CGColor;
        _ring.shadowColor = tint.CGColor;
        _ring.shadowRadius = 6;
        _ring.shadowOpacity = idle ? 0 : 0.45f;
        _glyph.strokeColor = (connected ? [UIColor whiteColor] : tint).CGColor;
        _trail.strokeColor = [tint colorWithAlphaComponent:0.45f].CGColor;
        _dot.fillColor = tint.CGColor;
        _dot.shadowColor = tint.CGColor;
        _dot.shadowOpacity = idle ? 0.35f : 0.8f;
    });
}

- (BOOL)orbitWanted {
    return _running && (_powerState == ExteriaShiroPowerWorking || _powerState == ExteriaShiroPowerOn);
}

- (double)shownAngle {
    CALayer *shown = [_orbit presentationLayer];
    return [[(shown ? shown : _orbit) valueForKeyPath:@"transform.rotation.z"] doubleValue];
}

/* the dot keeps its place when the speed changes: a new lap starts from wherever the old one is on screen, so a state switch never makes it jump */
- (void)stopSpin {
    double angle = [self shownAngle];
    [_orbit removeAnimationForKey:ORBIT_SPIN_KEY];
    ExteriaClassicShiroSilent(^{ _orbit.transform = CATransform3DMakeRotation((CGFloat)angle, 0, 0, 1); });
}

- (void)restartSpin {
    double angle = [self shownAngle];
    [self stopSpin];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = [NSNumber numberWithDouble:angle];
    spin.toValue = [NSNumber numberWithDouble:angle + M_PI * 2];
    /* seconds per lap: quick while the tunnel is made, slow once it is up */
    spin.duration = _powerState == ExteriaShiroPowerWorking ? 1.4 : 4.5;
    spin.repeatCount = HUGE_VALF;
    spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_orbit addAnimation:spin forKey:ORBIT_SPIN_KEY];
}

static void ExteriaClassicShiroTween(CALayer *layer, NSString *path, id from, id to, BOOL show) {
    CABasicAnimation *tween = [CABasicAnimation animationWithKeyPath:path];
    tween.fromValue = from;
    tween.toValue = to;
    tween.duration = ORBIT_FADE_SECONDS;
    tween.timingFunction = [CAMediaTimingFunction functionWithName:show ? kCAMediaTimingFunctionEaseOut : kCAMediaTimingFunctionEaseIn];
    [layer addAnimation:tween forKey:ORBIT_FADE_KEY];
}

/* the ring stays put; the dot grows its tail on it when a tunnel starts and pulls it back when the tunnel stops;
   it keeps circling while it fades out, so it never freezes in place */
- (void)showOrbit:(BOOL)show animated:(BOOL)animated {
    if (show == _orbitShown) return;
    _orbitShown = show;
    CALayer *orbitNow = [_orbit presentationLayer];
    CAShapeLayer *trailNow = (CAShapeLayer *)[_trail presentationLayer];
    CALayer *dotNow = [_dot presentationLayer];
    NSNumber *opacityFrom = [NSNumber numberWithFloat:(orbitNow ? orbitNow : _orbit).opacity];
    NSNumber *startFrom = [NSNumber numberWithFloat:(trailNow ? trailNow : _trail).strokeStart];
    NSValue *scaleFrom = [NSValue valueWithCATransform3D:(dotNow ? dotNow : _dot).transform];
    CATransform3D scale = show ? CATransform3DIdentity : CATransform3DMakeScale(ORBIT_DOT_REST, ORBIT_DOT_REST, 1);
    [_orbit removeAnimationForKey:ORBIT_FADE_KEY];
    [_trail removeAnimationForKey:ORBIT_FADE_KEY];
    [_dot removeAnimationForKey:ORBIT_FADE_KEY];
    ExteriaClassicShiroSilent(^{
        _orbit.opacity = show ? 1 : 0;
        _trail.strokeStart = show ? 0 : 1;
        _dot.transform = scale;
    });
    if (!animated) {
        if (!show) [self stopSpin];
        return;
    }
    [CATransaction begin];
    if (!show) {
        [CATransaction setCompletionBlock:^{
            if (!_orbitShown) [self stopSpin];
        }];
    }
    ExteriaClassicShiroTween(_orbit, @"opacity", opacityFrom, [NSNumber numberWithFloat:_orbit.opacity], show);
    ExteriaClassicShiroTween(_trail, @"strokeStart", startFrom, [NSNumber numberWithFloat:_trail.strokeStart], show);
    ExteriaClassicShiroTween(_dot, @"transform", scaleFrom, [NSValue valueWithCATransform3D:scale], show);
    [CATransaction commit];
}

- (void)syncOrbitAnimated:(BOOL)animated restart:(BOOL)restart {
    if ([self orbitWanted]) {
        if (restart || ![_orbit animationForKey:ORBIT_SPIN_KEY]) [self restartSpin];
        [self showOrbit:YES animated:animated];
    } else {
        [self showOrbit:NO animated:animated];
    }
}

- (void)syncPulse {
    BOOL want = _running && _powerState == ExteriaShiroPowerWorking;
    if (!want) {
        [_ring removeAnimationForKey:ORBIT_PULSE_KEY];
        return;
    }
    if ([_ring animationForKey:ORBIT_PULSE_KEY]) return;
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = [NSNumber numberWithFloat:1];
    pulse.toValue = [NSNumber numberWithFloat:0.35f];
    pulse.duration = 0.7;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [_ring addAnimation:pulse forKey:ORBIT_PULSE_KEY];
}

/* core animation drops layer animations while the app is in the background, so every state write also puts back whatever went missing */
- (void)setPowerState:(ExteriaShiroPowerState)state {
    BOOL changed = state != _powerState;
    _powerState = state;
    [self applyTheme];
    [self syncOrbitAnimated:changed restart:changed];
    [self syncPulse];
}

- (ExteriaShiroPowerState)powerState {
    return _powerState;
}

- (void)setRunning:(BOOL)running {
    BOOL changed = _running != running;
    _running = running;
    [self syncOrbitAnimated:NO restart:changed];
    [self syncPulse];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.95f, 0.95f) : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark plate

/* a plate in relief: a lit upper half over a lower one that darkens, a hairline rim and a short shadow under it */
@interface ExteriaClassicShiroPlate : UIControl {
    CAGradientLayer *_fill;
    CAGradientLayer *_sheen;
}
- (void)applyTheme;
@end

@implementation ExteriaClassicShiroPlate

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 0.5f;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    self.layer.shadowRadius = 3;
    _fill = [[CAGradientLayer alloc] init];
    _fill.startPoint = CGPointMake(0.5, 0);
    _fill.endPoint = CGPointMake(0.5, 1);
    [self.layer insertSublayer:_fill atIndex:0];
    _sheen = [[CAGradientLayer alloc] init];
    _sheen.startPoint = CGPointMake(0.5, 0);
    _sheen.endPoint = CGPointMake(0.5, 1);
    [self.layer insertSublayer:_sheen above:_fill];
    [self applyTheme];
    return self;
}

- (void)dealloc {
    [_fill release];
    [_sheen release];
    [super dealloc];
}

- (void)applyTheme {
    BOOL light = !ExteriaThemeIsDark();
    UIColor *card = ExteriaClassicShiroCellHigh();
    ExteriaClassicShiroSilent(^{
        _fill.colors = [NSArray arrayWithObjects:(id)ExteriaClassicShiroShade(card, light ? 0.01f : 0.02f).CGColor, (id)ExteriaClassicShiroShade(card, light ? -0.08f : -0.10f).CGColor, nil];
        _sheen.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:1 alpha:light ? 0.34f : 0.14f].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor, nil];
        self.layer.borderColor = [UIColor colorWithWhite:light ? 0 : 1 alpha:0.10f].CGColor;
        self.layer.shadowOpacity = light ? 0.18f : 0.42f;
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    ExteriaClassicShiroSilent(^{
        _fill.frame = bounds;
        _fill.cornerRadius = 14;
        _sheen.frame = CGRectMake(1, 1, MAX(0, bounds.size.width - 2), floor(bounds.size.height / 2));
        _sheen.cornerRadius = 13;
        /* a shadow without a path is drawn offscreen on every frame the screen moves */
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:14].CGPath;
    });
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.97f, 0.97f) : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark screen

@interface ExteriaClassicShiroScreen : UIViewController {
    ExteriaShiro *_shiro;
    CAGradientLayer *_backdrop;
    ExteriaShiroFoxField *_foxes;
    UILabel *_wordmark;
    UILabel *_tagline;
    ExteriaClassicOrbitButton *_power;
    UILabel *_state;
    UILabel *_detail;
    ExteriaClassicShiroPlate *_card;
    UIImageView *_cardIcon;
    UILabel *_cardTitle;
    UILabel *_cardSubtitle;
    UIImageView *_chevron;
    UIView *_protocolDot;
    UILabel *_protocol;
    NSTimer *_statsTimer;
}
- (id)initWithShiro:(ExteriaShiro *)shiro;
@end

@interface ExteriaClassicShiroController () {
    UINavigationController *_nav;
    BOOL _closing;
}
@end

@implementation ExteriaClassicShiroScreen

- (id)initWithShiro:(ExteriaShiro *)shiro {
    self = [super init];
    if (!self) return nil;
    _shiro = [shiro retain];
    self.title = @"shiro";
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_statsTimer invalidate];
    [_statsTimer release];
    [_shiro release];
    [_backdrop release];
    [_foxes release];
    [_wordmark release];
    [_tagline release];
    [_power release];
    [_state release];
    [_detail release];
    [_card release];
    [_cardIcon release];
    [_cardTitle release];
    [_cardSubtitle release];
    [_chevron release];
    [_protocolDot release];
    [_protocol release];
    [super dealloc];
}

- (UILabel *)labelIn:(UIView *)host alignment:(int)alignment {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = alignment;
    label.userInteractionEnabled = NO;
    [host addSubview:label];
    return label;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] init] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _backdrop = [[CAGradientLayer alloc] init];
    [root.layer addSublayer:_backdrop];
    _foxes = [[ExteriaShiroFoxField alloc] initWithFrame:root.bounds spriteName:@"shiro_fox"];
    _foxes.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:_foxes];
    _wordmark = [[self labelIn:root alignment:ExteriaTextAlignmentCenter] retain];
    _wordmark.text = @"shiro";
    _tagline = [[self labelIn:root alignment:ExteriaTextAlignmentCenter] retain];
    _tagline.text = @"by sqmrak :3";
    _power = [[ExteriaClassicOrbitButton alloc] init];
    _power.accessibilityLabel = NSLocalizedString(@"shiro.power", nil);
    [_power addTarget:self action:@selector(powerTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_power];
    _state = [[self labelIn:root alignment:ExteriaTextAlignmentCenter] retain];
    _detail = [[self labelIn:root alignment:ExteriaTextAlignmentCenter] retain];
    _detail.numberOfLines = 2;
    _detail.lineBreakMode = UILineBreakModeTailTruncation;
    _card = [[ExteriaClassicShiroPlate alloc] init];
    [_card addTarget:self action:@selector(turnOff) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_card];
    _cardIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"shiro_cloudflare.png"]];
    _cardIcon.clipsToBounds = YES;
    _cardIcon.layer.cornerRadius = 8;
    _cardIcon.userInteractionEnabled = NO;
    [_card addSubview:_cardIcon];
    _cardTitle = [[self labelIn:_card alignment:ExteriaTextAlignmentLeft] retain];
    _cardSubtitle = [[self labelIn:_card alignment:ExteriaTextAlignmentLeft] retain];
    _chevron = [[UIImageView alloc] init];
    _chevron.contentMode = UIViewContentModeCenter;
    [_card addSubview:_chevron];
    _protocolDot = [[UIView alloc] init];
    _protocolDot.layer.cornerRadius = 3;
    [root addSubview:_protocolDot];
    _protocol = [[self labelIn:root alignment:ExteriaTextAlignmentLeft] retain];
    _protocol.lineBreakMode = UILineBreakModeTailTruncation;
    _protocol.text = @"WireGuard · WARP";
    [self applyTheme];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(shiroChanged) name:ExteriaShiroStateDidChangeNotification object:_shiro];
    [center addObserver:self selector:@selector(themeChanged) name:ExteriaThemeDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(activate) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(deactivate) name:UIApplicationWillResignActiveNotification object:nil];
    [self shiroChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self activate];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self deactivate];
}

- (void)activate {
    [_power setRunning:YES];
}

- (void)deactivate {
    [_power setRunning:NO];
}

- (void)applyTheme {
    ExteriaClassicShiroSilent(^{
        _backdrop.colors = [NSArray arrayWithObjects:(id)ExteriaClassicShiroBackdropTop().CGColor, (id)ExteriaClassicShiroBackdropBottom().CGColor, nil];
    });
    _wordmark.textColor = ExteriaClassicShiroAccent();
    _tagline.textColor = ExteriaClassicShiroInkMuted();
    _state.textColor = ExteriaClassicShiroInk();
    _cardSubtitle.textColor = ExteriaClassicShiroInkMuted();
    _protocol.textColor = ExteriaClassicShiroInkMuted();
    _protocolDot.backgroundColor = ExteriaClassicShiroAccent();
    _detail.textColor = ExteriaClassicShiroInkMuted();
    [_card applyTheme];
    [_power applyTheme];
    [self.view setNeedsLayout];
}

- (void)themeChanged {
    [self applyTheme];
    [self shiroChanged];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutScreen];
}

- (void)layoutScreen {
    CGSize size = self.view.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    ExteriaClassicShiroSilent(^{ _backdrop.frame = self.view.bounds; });
    BOOL pad = ExteriaIsPad();
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    BOOL wide = size.width > size.height && size.height < 560;
    BOOL compact = !pad && !wide && size.height <= 500;
    CGFloat margin = pad ? 28 : (size.width <= 320 ? 14 : 18);
    CGFloat left = MAX(insets.left, 0) + margin, right = size.width - MAX(insets.right, 0) - margin;
    CGFloat bottom = MAX(insets.bottom, 0) + (pad ? 28 : 14);

    CGFloat wordSize = pad ? 58 : ((compact || wide) ? 32 : 44);
    _wordmark.font = ExteriaShiroFontDisplay(wordSize);
    CGFloat wordHeight = ceil(wordSize * 1.2);
    _wordmark.frame = CGRectMake(left, 4, right - left, wordHeight);
    CGFloat top = 4 + wordHeight;
    if (!wide) {
        CGFloat tagSize = pad ? 17 : (compact ? 12 : 14);
        _tagline.font = ExteriaShiroFontBody(tagSize, NO);
        CGFloat tagHeight = ceil(tagSize * 1.4);
        _tagline.frame = CGRectMake(left, top - 4, right - left, tagHeight);
        top = CGRectGetMaxY(_tagline.frame) + (compact ? 4 : 12);
    } else {
        top += 4;
    }
    _tagline.hidden = wide;

    CGFloat cardHeight = pad ? 78 : (compact ? 58 : 68);
    CGFloat protocolHeight = compact ? 20 : 24;
    CGFloat stateSize = pad ? 26 : (compact ? 19 : 22);
    _state.font = ExteriaShiroFontBody(stateSize, YES);
    CGFloat stateHeight = ceil(stateSize * 1.3);
    CGFloat detailSize = pad ? 16 : 14;
    _detail.font = ExteriaShiroFontBody(detailSize, NO);
    _protocol.font = ExteriaShiroFontBody(pad ? 15 : 13, NO);

    if (wide) {
        /* a phone on its side has no height for a stacked screen: the control takes the left half, the texts the right */
        CGFloat leftWidth = floor((right - left) * 0.44);
        CGFloat available = size.height - top - bottom;
        CGFloat side = MAX(80, MIN(available, leftWidth));
        _power.frame = CGRectMake(left + floor((leftWidth - side) / 2), top + floor((available - side) / 2), side, side);
        CGFloat x = left + leftWidth + 14, width = right - x;
        CGFloat detailHeight = 18, gap = 10;
        CGFloat block = stateHeight + detailHeight + gap + 56 + gap + 22;
        CGFloat y = MAX(top, top + floor((available - block) / 2));
        _state.frame = CGRectMake(x, y, width, stateHeight);
        y += stateHeight;
        _detail.numberOfLines = 1;
        _detail.frame = CGRectMake(x, y, width, detailHeight);
        y += detailHeight + gap;
        _card.frame = CGRectMake(x, y, width, 56);
        y += 56 + gap;
        _protocolDot.frame = CGRectMake(x + 8, y + 8, 6, 6);
        _protocol.frame = CGRectMake(x + 22, y, width - 22, 22);
    } else {
        CGFloat columnWidth = MIN(right - left, pad ? 480 : 440);
        CGFloat columnX = floor((size.width - columnWidth) / 2);
        CGFloat y = size.height - bottom - protocolHeight;
        _protocolDot.frame = CGRectMake(columnX + 8, y + floor((protocolHeight - 6) / 2), 6, 6);
        _protocol.frame = CGRectMake(columnX + 22, y, columnWidth - 22, protocolHeight);
        y -= (compact ? 6 : 10) + cardHeight;
        _card.frame = CGRectMake(columnX, y, columnWidth, cardHeight);
        CGFloat detailHeight = compact ? ceil(detailSize * 1.3) : ceil(detailSize * 2.5);
        _detail.numberOfLines = compact ? 1 : 2;
        y -= (compact ? 8 : 14) + detailHeight;
        _detail.frame = CGRectMake(columnX, y, columnWidth, detailHeight);
        y -= stateHeight;
        _state.frame = CGRectMake(columnX, y, columnWidth, stateHeight);
        CGFloat available = y - (compact ? 4 : 10) - top;
        CGFloat side = MIN(available, columnWidth * (pad ? 0.7 : 0.82));
        side = MAX(90, MIN(side, pad ? 380 : 320));
        _power.frame = CGRectMake(floor((size.width - side) / 2), top + floor((available - side) / 2), side, side);
    }
    [self layoutCard];
}

- (void)layoutCard {
    CGRect bounds = _card.bounds;
    CGFloat height = bounds.size.height;
    CGFloat icon = MAX(28, MIN(44, floor(height - 24)));
    _cardIcon.frame = CGRectMake(14, floor((height - icon) / 2), icon, icon);
    _chevron.frame = CGRectMake(bounds.size.width - 28, floor((height - 20) / 2), 14, 20);
    CGFloat textX = 14 + icon + 12, textWidth = CGRectGetMinX(_chevron.frame) - 8 - textX;
    CGFloat titleSize = height >= 66 ? 17 : 15;
    _cardTitle.font = ExteriaShiroFontBody(titleSize, YES);
    _cardSubtitle.font = ExteriaShiroFontBody(titleSize - 3, NO);
    CGFloat titleHeight = ceil(titleSize * 1.3), subtitleHeight = ceil((titleSize - 3) * 1.35);
    /* a plate with no second line centers its title */
    CGFloat textTop = floor((height - titleHeight - (_cardSubtitle.text.length ? subtitleHeight : 0)) / 2);
    _cardTitle.frame = CGRectMake(textX, textTop, textWidth, titleHeight);
    _cardSubtitle.frame = CGRectMake(textX, textTop + titleHeight, textWidth, subtitleHeight);
}

#pragma mark state

static NSString *ExteriaClassicShiroStateKey(ExteriaShiroState state, ExteriaShiroFailure failure) {
    switch (state) {
    case ExteriaShiroStateOff: return @"shiro.state.off";
    case ExteriaShiroStateRegistering: return @"shiro.state.registering";
    case ExteriaShiroStateConnecting: return @"shiro.state.connecting";
    case ExteriaShiroStateUp: return @"shiro.state.up";
    case ExteriaShiroStateFailed:
        switch (failure) {
        case ExteriaShiroFailureAccount: return @"shiro.state.failed.account";
        case ExteriaShiroFailureKey: return @"shiro.state.failed.key";
        default: return @"shiro.state.failed.server";
        }
    }
    return @"shiro.state.off";
}

- (void)shiroChanged {
    ExteriaShiroState state = _shiro.state;
    ExteriaShiroPowerState power = ExteriaShiroPowerOff;
    if (state == ExteriaShiroStateRegistering || state == ExteriaShiroStateConnecting) power = ExteriaShiroPowerWorking;
    else if (state == ExteriaShiroStateUp) power = ExteriaShiroPowerOn;
    else if (state == ExteriaShiroStateFailed) power = ExteriaShiroPowerFailed;
    _power.powerState = power;
    _state.text = NSLocalizedString(ExteriaClassicShiroStateKey(state, _shiro.failure), nil);
    _power.accessibilityValue = _state.text;
    /* after a failure the plate offers the way out: the tunnel stays wanted, and traffic stays blocked, until the person turns it off */
    BOOL failed = state == ExteriaShiroStateFailed;
    _card.userInteractionEnabled = failed;
    _chevron.image = failed ? ExteriaClassicShiroChevron(ExteriaClassicShiroInkMuted()) : nil;
    _cardTitle.text = failed ? NSLocalizedString(@"shiro.card.turnoff", nil) : @"Cloudflare WARP";
    _cardTitle.textColor = failed ? ExteriaClassicShiroError() : ExteriaClassicShiroInk();
    _cardSubtitle.text = NSLocalizedString(@"shiro.endpoint", nil);
    if (state == ExteriaShiroStateUp) {
        if (!_statsTimer) _statsTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refreshStats) userInfo:nil repeats:YES] retain];
        [self refreshStats];
    } else {
        [self stopStatsTimer];
        _detail.text = failed ? nil : NSLocalizedString(@"shiro.card.idle", nil);
    }
    [self layoutCard];
}

static UIImage *ExteriaClassicShiroChevron(UIColor *color) {
    CGSize size = CGSizeMake(14, 20);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(4, 4)];
    [path addLineToPoint:CGPointMake(10, 10)];
    [path addLineToPoint:CGPointMake(4, 16)];
    path.lineWidth = 2;
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    [color setStroke];
    [path stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)refreshStats {
    ExteriaShiroStats stats;
    memset(&stats, 0, sizeof(stats));
    /* a busy engine keeps the last figures; the line stays as it was */
    [_shiro stats:&stats];
    unsigned long long seconds = stats.ageMs / 1000;
    _detail.text = [NSString stringWithFormat:@"↓ %@   ↑ %@   %02llu:%02llu", ExteriaShiroByteText(stats.bytesIn), ExteriaShiroByteText(stats.bytesOut), seconds / 60 % 100, seconds % 60];
}

- (void)stopStatsTimer {
    [_statsTimer invalidate];
    [_statsTimer release];
    _statsTimer = nil;
}

- (void)turnOff {
    [_shiro setEnabled:NO];
}

- (void)powerTapped {
    switch (_shiro.state) {
    case ExteriaShiroStateOff: [_shiro setEnabled:YES]; break;
    case ExteriaShiroStateFailed: [_shiro retry]; break;
    /* a tap while it dials gives up on it, as a tap on the lit control turns it off */
    default: [_shiro setEnabled:NO]; break;
    }
}

@end

#pragma mark controller

@implementation ExteriaClassicShiroController

+ (void)presentWithShiro:(ExteriaShiro *)shiro from:(UIViewController *)host {
    UIViewController *parent = host;
    while (parent && ![parent isKindOfClass:[ExteriaMainController class]]) parent = parent.parentViewController;
    if (!parent) {
        parent = host;
        while (parent.parentViewController) parent = parent.parentViewController;
    }
    /* on the ipad the main screen is only the left pane, and the screen has to cover both panes */
    for (UIViewController *up = parent; up; up = up.parentViewController) {
        if ([up isKindOfClass:[ExteriaSplitController class]]) {
            parent = up;
            break;
        }
    }
    for (UIViewController *child in parent.childViewControllers) {
        if ([child isKindOfClass:[ExteriaClassicShiroController class]]) return;
    }
    ExteriaClassicShiroController *cover = [[[ExteriaClassicShiroController alloc] init] autorelease];
    ExteriaClassicShiroScreen *screen = [[[ExteriaClassicShiroScreen alloc] initWithShiro:shiro] autorelease];
    screen.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"shiro.close", nil) style:UIBarButtonItemStyleDone target:cover action:@selector(close)] autorelease];
    cover->_nav = [[UINavigationController alloc] initWithRootViewController:screen];
    ExteriaClassicStyleNavigationBar(cover->_nav.navigationBar);
    /* a bar that is not translucent keeps the screen below it on ios 5 to 6 and on 7 and later alike */
    cover->_nav.navigationBar.translucent = NO;
    [parent addChildViewController:cover];
    cover.view.frame = parent.view.bounds;
    [parent.view addSubview:cover.view];
    [cover didMoveToParentViewController:parent];
    [cover enter];
}

- (void)dealloc {
    [_nav release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] init] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    [self addChildViewController:_nav];
    _nav.view.frame = root.bounds;
    _nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:_nav.view];
    [_nav didMoveToParentViewController:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat top = ExteriaLayoutInsets(self).top;
    _nav.view.frame = CGRectMake(0, top, bounds.size.width, MAX(0, bounds.size.height - top));
}

- (void)enter {
    [self.view layoutIfNeeded];
    CGRect rest = self.view.frame;
    self.view.frame = CGRectOffset(rest, 0, rest.size.height);
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : ENTER_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.view.frame = rest;
    } completion:nil];
}

- (void)close {
    if (_closing) return;
    _closing = YES;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : ENTER_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.view.frame = CGRectOffset(self.view.frame, 0, self.view.bounds.size.height);
    } completion:^(BOOL finished) {
        (void)finished;
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    }];
}

@end
