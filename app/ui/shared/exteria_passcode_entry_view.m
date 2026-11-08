#import <QuartzCore/QuartzCore.h>
#import "exteria_passcode_entry_view.h"

#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define DOT_SIDE 14.0
#define DOT_GAP 22.0
#define KEY_SIDE_MAX 76.0
#define KEY_GAP 14.0
#define FIELD_HEIGHT 46.0
#define PASS_DOT_SIDE 12.0
#define PASS_DOT_GAP 9.0
#define PASS_PAD 20.0

NSString *ExteriaPasscodeText(NSString *key, exteria_passcode_type type) {
    return NSLocalizedString(type == EXTERIA_PASSCODE_PASSWORD ? [key stringByAppendingString:@".password"] : key, nil);
}

/* the shapes a pressed key turns into, after the expressive shapes of Material You that the lock screen of a Pixel picks from. every one is the same number of points around the key,
   so the path of a key moves from the circle to a shape and back point by point, which is the only way a layer animates its path */
#define KEY_POINTS 96
#define KEY_HOLD 0.18

typedef enum { ExteriaKeyShapeLobed, ExteriaKeyShapePolygon, ExteriaKeyShapeSuper } ExteriaKeyShapeKind;

/* lobed: count lobes, a the depth of them, b the roundness of a crest (above 1 narrow rays, below 1 broad petals), c the same for a valley.
   polygon: count sides, a how far the corners are drawn in towards a circle.
   super: a the exponent of a superellipse (2 is an ellipse, 4 a squircle), b and c its two half axes */
typedef struct {
    ExteriaKeyShapeKind kind;
    int count;
    CGFloat a, b, c;
} ExteriaKeyShape;

static const ExteriaKeyShape ExteriaKeyShapes[] = {
    /* cookies: a circle with scallops */
    {ExteriaKeyShapeLobed, 4, 0.10f, 1, 1}, {ExteriaKeyShapeLobed, 6, 0.09f, 1, 1}, {ExteriaKeyShapeLobed, 7, 0.08f, 1, 1},
    {ExteriaKeyShapeLobed, 9, 0.07f, 1, 1}, {ExteriaKeyShapeLobed, 12, 0.055f, 1, 1},
    /* clovers and flowers: round petals with narrow valleys between them */
    {ExteriaKeyShapeLobed, 4, 0.30f, 0.6f, 2.0f}, {ExteriaKeyShapeLobed, 5, 0.26f, 0.7f, 1.8f}, {ExteriaKeyShapeLobed, 6, 0.24f, 0.7f, 1.8f},
    {ExteriaKeyShapeLobed, 8, 0.20f, 0.7f, 1.8f},
    /* suns and bursts: narrow rays with broad valleys */
    {ExteriaKeyShapeLobed, 8, 0.16f, 2.0f, 0.7f}, {ExteriaKeyShapeLobed, 12, 0.13f, 2.0f, 0.7f}, {ExteriaKeyShapeLobed, 10, 0.20f, 2.4f, 0.7f},
    /* rounded triangle, diamond and pentagon */
    {ExteriaKeyShapePolygon, 3, 0.38f, 0, 0}, {ExteriaKeyShapePolygon, 4, 0.30f, 0, 0}, {ExteriaKeyShapePolygon, 5, 0.30f, 0, 0},
    /* squircle, oval and pill, drawn in from the rim so that their corners stay inside the circle of the key */
    {ExteriaKeyShapeSuper, 0, 4.0f, 0.84f, 0.84f}, {ExteriaKeyShapeSuper, 0, 2.0f, 1.0f, 0.78f}, {ExteriaKeyShapeSuper, 0, 3.4f, 0.94f, 0.58f}
};
#define KEY_SHAPE_COUNT (sizeof(ExteriaKeyShapes) / sizeof(ExteriaKeyShapes[0]))

/* the points of a shape around the middle of a key of this size, turned by spin; grow 1 reaches the rim of the circle the key is */
static void ExteriaKeyShapePoints(const ExteriaKeyShape *shape, CGFloat spin, CGSize size, CGFloat grow, CGPoint *out) {
    CGFloat cx = size.width / 2, cy = size.height / 2, radius = MIN(size.width, size.height) / 2 * grow;
    for (NSUInteger i = 0; i < KEY_POINTS; ++i) {
        CGFloat t = (CGFloat)(2 * M_PI) * (CGFloat)i / KEY_POINTS, x, y;
        if (shape->kind == ExteriaKeyShapeLobed) {
            CGFloat c = cosf(shape->count * (t - spin));
            CGFloat v = c >= 0 ? powf(c, shape->b) : -powf(-c, shape->c);
            CGFloat r = (1 + shape->a * v) / (1 + shape->a);
            x = cosf(t) * r;
            y = sinf(t) * r;
        } else if (shape->kind == ExteriaKeyShapePolygon) {
            CGFloat sector = (CGFloat)(2 * M_PI) / shape->count, u = t - spin;
            CGFloat phi = u - sector * floorf(u / sector) - sector / 2;
            CGFloat edge = cosf(sector / 2) / cosf(phi);
            CGFloat r = (1 - shape->a) * edge + shape->a * 0.86f;
            x = cosf(t) * r;
            y = sinf(t) * r;
        } else {
            CGFloat c = cosf(t), sn = sinf(t), e = 2 / shape->a;
            CGFloat px = shape->b * (c < 0 ? -powf(-c, e) : powf(c, e)), py = shape->c * (sn < 0 ? -powf(-sn, e) : powf(sn, e));
            x = px * cosf(spin) - py * sinf(spin);
            y = px * sinf(spin) + py * cosf(spin);
        }
        out[i] = CGPointMake(cx + radius * x, cy + radius * y);
    }
}

/* the key at rest: a circle, or on a wide pad the rounded plate of a key that is wider than it is high */
static void ExteriaKeyRestPoints(CGSize size, BOOL wide, CGFloat grow, CGPoint *out) {
    if (!wide) {
        ExteriaKeyShape circle = {ExteriaKeyShapeLobed, 1, 0, 1, 1};
        ExteriaKeyShapePoints(&circle, 0, size, grow, out);
        return;
    }
    for (NSUInteger i = 0; i < KEY_POINTS; ++i) {
        CGFloat t = (CGFloat)(2 * M_PI) * (CGFloat)i / KEY_POINTS, c = cosf(t), sn = sinf(t), e = 2 / 5.0f;
        out[i] = CGPointMake(size.width / 2 + size.width / 2 * grow * (c < 0 ? -powf(-c, e) : powf(c, e)),
                             size.height / 2 + size.height / 2 * grow * (sn < 0 ? -powf(-sn, e) : powf(sn, e)));
    }
}

/* a closed path through the points; the caller releases it */
static CGPathRef ExteriaKeyPathCreate(const CGPoint *points) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
    for (NSUInteger i = 1; i < KEY_POINTS; ++i) CGPathAddLineToPoint(path, NULL, points[i].x, points[i].y);
    CGPathCloseSubpath(path);
    return path;
}

@interface ExteriaPasscodeEntryView () <UITextFieldDelegate> {
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    NSMutableArray *_dots;
    NSMutableArray *_keys;
    /* a modern pad draws each key as a layer of its own, whose path turns into a shape while the key is down; the classic pad keeps plain plates */
    BOOL _shapeKeys;
    NSMutableArray *_plates;
    BOOL _keyDown[10];
    CFTimeInterval _pressedAt[10];
    NSUInteger _lastShape;
    BOOL _wideKeys;
    UIButton *_delete;
    UIButton *_biometricButton;
    UITextField *_field;
    /* the plate a password is typed on: the field over it takes the keys and stays unseen, and the dots on the plate are what shows */
    UIView *_plate;
    UIView *_passDots;
    NSMutableArray *_passDotViews;
    NSUInteger _shownFilled;
    BOOL _accented;
    NSMutableString *_typed;
    exteria_passcode_type _type;
    BOOL _inputEnabled;
    NSTimer *_holdTimer;
    NSDate *_holdEnd;
}
@end

@implementation ExteriaPasscodeEntryView

@synthesize submit = _submit;
@synthesize biometric = _biometric;
@synthesize biometricFingerprint = _biometricFingerprint;
@synthesize topInset = _topInset;
@synthesize inputEnabled = _inputEnabled;
@synthesize accented = _accented;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _inputEnabled = YES;
    _typed = [[NSMutableString alloc] init];
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = ExteriaColorTitle();
    _titleLabel.font = ExteriaFontSemibold(20);
    _titleLabel.textAlignment = ExteriaTextAlignmentCenter;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumFontSize = 14;
    [self addSubview:_titleLabel];
    _messageLabel = [[UILabel alloc] init];
    _messageLabel.backgroundColor = [UIColor clearColor];
    _messageLabel.textColor = ExteriaColorSecondary();
    _messageLabel.font = ExteriaFontRegular(14);
    _messageLabel.textAlignment = ExteriaTextAlignmentCenter;
    _messageLabel.numberOfLines = 2;
    [self addSubview:_messageLabel];
    _dots = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < EXTERIA_PASSCODE_PIN_LEN; ++i) {
        UIView *dot = [[[UIView alloc] init] autorelease];
        dot.layer.cornerRadius = DOT_SIDE / 2;
        dot.layer.borderWidth = 1.5;
        [self addSubview:dot];
        [_dots addObject:dot];
    }
    _keys = [[NSMutableArray alloc] init];
    _shapeKeys = !ExteriaThemeIsClassic();
    _plates = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i < 10; ++i) {
        UIButton *key = [UIButton buttonWithType:UIButtonTypeCustom];
        key.tag = i;
        [key setTitle:[NSString stringWithFormat:@"%ld", (long)i] forState:UIControlStateNormal];
        key.titleLabel.font = ExteriaFontRegular(30);
        [key setTitleColor:ExteriaColorTitle() forState:UIControlStateNormal];
        key.backgroundColor = ExteriaColorField();
        [key addTarget:self action:@selector(digitPressed:) forControlEvents:UIControlEventTouchUpInside];
        [key addTarget:self action:@selector(keyDown:) forControlEvents:UIControlEventTouchDown];
        [key addTarget:self action:@selector(keyUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        key.accessibilityLabel = key.currentTitle;
        if (_shapeKeys) {
            CAShapeLayer *plate = [CAShapeLayer layer];
            plate.fillColor = ExteriaColorField().CGColor;
            [key.layer insertSublayer:plate atIndex:0];
            key.backgroundColor = [UIColor clearColor];
            [_plates addObject:plate];
        }
        [self addSubview:key];
        [_keys addObject:key];
    }
    _delete = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_delete setImage:ExteriaSymbolImage(ExteriaSymbolBackspace, 26, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_delete addTarget:self action:@selector(deletePressed) forControlEvents:UIControlEventTouchUpInside];
    _delete.accessibilityLabel = NSLocalizedString(@"passcode.delete", nil);
    [self addSubview:_delete];
    _biometricButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _biometricButton.titleLabel.font = ExteriaFontSemibold(14);
    _biometricButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _biometricButton.titleLabel.minimumFontSize = 10;
    [_biometricButton setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_biometricButton addTarget:self action:@selector(biometricPressed) forControlEvents:UIControlEventTouchUpInside];
    _biometricButton.hidden = YES;
    [self addSubview:_biometricButton];
    _plate = [[UIView alloc] init];
    _plate.layer.cornerRadius = FIELD_HEIGHT / 2;
    _plate.userInteractionEnabled = NO;
    [self addSubview:_plate];
    _passDots = [[UIView alloc] init];
    _passDots.userInteractionEnabled = NO;
    [_plate addSubview:_passDots];
    _passDotViews = [[NSMutableArray alloc] init];
    _field = [[UITextField alloc] init];
    /* nearly clear and not hidden: a hidden field cannot hold the keyboard, and a field with no alpha takes no touch */
    _field.alpha = 0.02;
    _field.font = ExteriaFontRegular(18);
    _field.secureTextEntry = YES;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _field.returnKeyType = UIReturnKeyDone;
    _field.enablesReturnKeyAutomatically = YES;
    _field.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _field.delegate = self;
    [_field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    [self addSubview:_field];
    [self applyType];
    [self applyPalette];
    [self refreshDots];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_holdTimer invalidate];
    [_holdEnd release];
    _field.delegate = nil;
    [_titleLabel release];
    [_messageLabel release];
    [_dots release];
    [_keys release];
    [_plates release];
    [_delete release];
    [_biometricButton release];
    [_biometric release];
    [_field release];
    [_plate release];
    [_passDots release];
    [_passDotViews release];
    [_typed release];
    [_submit release];
    [super dealloc];
}

- (exteria_passcode_type)type {
    return _type;
}

- (void)setType:(exteria_passcode_type)type {
    if (type == _type) return;
    _type = type;
    [self reset];
    [self applyType];
    [self setNeedsLayout];
}

- (void)applyType {
    BOOL pin = _type == EXTERIA_PASSCODE_PIN;
    for (UIView *dot in _dots) dot.hidden = !pin;
    for (UIView *key in _keys) key.hidden = !pin;
    _delete.hidden = !pin;
    _field.hidden = pin;
    _plate.hidden = pin;
    if (pin) [_field resignFirstResponder];
}

#pragma mark palette

- (UIColor *)ink {
    return _accented ? [UIColor whiteColor] : ExteriaColorTitle();
}

- (UIColor *)softInk {
    return _accented ? [UIColor colorWithWhite:1 alpha:0.74] : ExteriaColorSecondary();
}

- (UIColor *)plateColor {
    return _accented ? [UIColor colorWithWhite:1 alpha:0.16] : ExteriaColorField();
}

- (UIColor *)plateDownColor {
    return _accented ? [UIColor colorWithWhite:1 alpha:0.34] : ExteriaColorAccent();
}

- (void)setAccented:(BOOL)accented {
    if (accented == _accented) return;
    _accented = accented;
    [self applyPalette];
}

- (void)applyPalette {
    _titleLabel.textColor = [self ink];
    _messageLabel.textColor = [self softInk];
    for (UIButton *key in _keys) {
        [key setTitleColor:[self ink] forState:UIControlStateNormal];
        if (!_shapeKeys) key.backgroundColor = [self plateColor];
        else if (!_keyDown[key.tag]) [self setPlateFill:[self plateColor] ofKey:key animated:NO];
    }
    [_delete setImage:ExteriaSymbolImage(ExteriaSymbolBackspace, 26, [self ink]) forState:UIControlStateNormal];
    [_biometricButton setTitleColor:[self ink] forState:UIControlStateNormal];
    if (_biometricFingerprint) [_biometricButton setImage:ExteriaSymbolImage(ExteriaSymbolFingerprint, 34, [self ink]) forState:UIControlStateNormal];
    _plate.backgroundColor = [self plateColor];
    _field.keyboardAppearance = _accented || ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    [self refreshDots];
    for (UIView *dot in _passDotViews) dot.backgroundColor = [self ink];
}

- (NSString *)title {
    return _titleLabel.text;
}

- (void)setTitle:(NSString *)title {
    _titleLabel.text = title;
}

- (NSString *)message {
    return _messageLabel.text;
}

- (void)setMessage:(NSString *)message {
    _messageLabel.text = message;
}

- (NSString *)biometricTitle {
    return [_biometricButton titleForState:UIControlStateNormal];
}

- (void)setBiometricTitle:(NSString *)title {
    [_biometricButton setTitle:_biometricFingerprint ? nil : title forState:UIControlStateNormal];
    [_biometricButton setImage:_biometricFingerprint ? ExteriaSymbolImage(ExteriaSymbolFingerprint, 34, [self ink]) : nil forState:UIControlStateNormal];
    _biometricButton.accessibilityLabel = title;
    _biometricButton.hidden = title.length == 0;
}

- (void)biometricPressed {
    if (_inputEnabled && _biometric) _biometric();
}

- (void)setInputEnabled:(BOOL)enabled {
    _inputEnabled = enabled;
    self.userInteractionEnabled = enabled;
    self.alpha = 1;
    for (UIButton *key in _keys) {
        key.enabled = enabled;
        /* a key that is down when the pad stops taking touches gets no touch up, and would stay in its shape */
        if (!enabled) [self settleKey:key];
    }
    _delete.enabled = enabled;
    _biometricButton.enabled = enabled;
    _field.enabled = enabled;
}

- (void)reset {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(submitTyped) object:nil];
    [_typed setString:@""];
    _field.text = @"";
    [self refreshDots];
    [self refreshPasswordDotsAnimated:NO];
}

- (void)focus {
    if (_type == EXTERIA_PASSCODE_PASSWORD && _inputEnabled) [_field becomeFirstResponder];
}

- (void)rejectCode {
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:-14], [NSNumber numberWithFloat:12],
                    [NSNumber numberWithFloat:-9], [NSNumber numberWithFloat:6], [NSNumber numberWithFloat:0], nil];
    shake.duration = 0.35;
    for (UIView *dot in _dots) [dot.layer addAnimation:shake forKey:@"shake"];
    [_plate.layer addAnimation:shake forKey:@"shake"];
    [self reset];
}

- (void)holdForSeconds:(NSUInteger)seconds {
    [_holdTimer invalidate];
    _holdTimer = nil;
    [_holdEnd release];
    _holdEnd = nil;
    if (seconds == 0) return;
    _holdEnd = [[NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds] retain];
    self.inputEnabled = NO;
    [self reset];
    [_field resignFirstResponder];
    /* the timer keeps the view alive until it stops, which the move out of the window below makes sure of */
    _holdTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(holdTick) userInfo:nil repeats:YES];
    [self holdTick];
}

- (void)holdTick {
    NSInteger left = (NSInteger)ceil([_holdEnd timeIntervalSinceNow]);
    if (left > 0) {
        _messageLabel.text = [NSString stringWithFormat:NSLocalizedString(@"passcode.wait", nil), (long)left];
        return;
    }
    [_holdTimer invalidate];
    _holdTimer = nil;
    [_holdEnd release];
    _holdEnd = nil;
    _messageLabel.text = nil;
    self.inputEnabled = YES;
    [self focus];
}

- (void)willMoveToWindow:(UIWindow *)window {
    [super willMoveToWindow:window];
    if (window) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(releaseKey:) object:nil];
    for (UIButton *key in _keys) [self restKey:key animated:NO];
    [_holdTimer invalidate];
    _holdTimer = nil;
    [_holdEnd release];
    _holdEnd = nil;
    if (!_inputEnabled) self.inputEnabled = YES;
}

/* a dot that fills pops past its size and settles, and one that empties dips and drains, which is how the lock screen of a Pixel answers a key */
- (void)animateDot:(UIView *)dot filling:(BOOL)filling color:(UIColor *)color {
    CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    scale.values = filling ? [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.55f], [NSNumber numberWithFloat:1.3f], [NSNumber numberWithFloat:1], nil]
                           : [NSArray arrayWithObjects:[NSNumber numberWithFloat:1], [NSNumber numberWithFloat:0.72f], [NSNumber numberWithFloat:1], nil];
    scale.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.55f], [NSNumber numberWithFloat:1], nil];
    scale.timingFunctions = [NSArray arrayWithObjects:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
                             [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], nil];
    scale.duration = filling ? 0.26 : 0.18;
    [dot.layer addAnimation:scale forKey:@"pop"];
    CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    fill.fromValue = (id)(filling ? [UIColor clearColor] : color).CGColor;
    fill.toValue = (id)(filling ? color : [UIColor clearColor]).CGColor;
    fill.duration = filling ? 0.14 : 0.18;
    [dot.layer addAnimation:fill forKey:@"fill"];
}

- (void)refreshDots {
    UIColor *color = [self ink];
    BOOL animate = self.window && !ExteriaReduceMotionEnabled();
    for (NSUInteger i = 0; i < _dots.count; ++i) {
        UIView *dot = [_dots objectAtIndex:i];
        BOOL filled = i < _typed.length, was = i < _shownFilled;
        dot.layer.borderColor = color.CGColor;
        dot.backgroundColor = filled ? color : [UIColor clearColor];
        if (animate && filled != was) [self animateDot:dot filling:filled color:color];
    }
    _shownFilled = MIN(_typed.length, _dots.count);
}

#pragma mark password dots

- (void)fieldChanged {
    [self refreshPasswordDotsAnimated:YES];
}

/* the size and the step of the dots for this many of them on the plate: they close up when a long password would run off it */
static void ExteriaPassDotMetrics(NSUInteger count, CGFloat room, CGFloat *side, CGFloat *step) {
    *side = PASS_DOT_SIDE;
    *step = PASS_DOT_SIDE + PASS_DOT_GAP;
    if (count < 2 || (count - 1) * *step + *side <= room) return;
    *step = (room - *side) / (CGFloat)(count - 1);
    if (*step < *side + 1.5) {
        *side = MAX(3, *step - 1.5);
        *step = (room - *side) / (CGFloat)(count - 1);
    }
}

- (CGRect)frameOfPassDot:(NSUInteger)index of:(NSUInteger)count {
    CGFloat room = MAX(40, _passDots.bounds.size.width - 2 * PASS_PAD), side, step;
    ExteriaPassDotMetrics(count, room, &side, &step);
    CGFloat total = count ? (count - 1) * step + side : 0;
    CGFloat left = (_passDots.bounds.size.width - total) / 2;
    return CGRectMake(left + index * step, (_passDots.bounds.size.height - side) / 2, side, side);
}

- (void)refreshPasswordDotsAnimated:(BOOL)animated {
    NSUInteger count = _field.text.length;
    BOOL motion = animated && self.window && !ExteriaReduceMotionEnabled();
    NSUInteger had = _passDotViews.count;
    UIColor *ink = [self ink];
    while (_passDotViews.count > count) {
        UIView *gone = [_passDotViews lastObject];
        [_passDotViews removeLastObject];
        if (!motion) {
            [gone removeFromSuperview];
            continue;
        }
        [UIView animateWithDuration:0.16 animations:^{
            gone.transform = CGAffineTransformMakeScale(0.2f, 0.2f);
            gone.alpha = 0;
        } completion:^(BOOL finished) {
            (void)finished;
            [gone removeFromSuperview];
        }];
    }
    while (_passDotViews.count < count) {
        UIView *dot = [[[UIView alloc] init] autorelease];
        dot.backgroundColor = ink;
        [_passDots addSubview:dot];
        [_passDotViews addObject:dot];
    }
    for (NSUInteger i = 0; i < _passDotViews.count; ++i) {
        UIView *dot = [_passDotViews objectAtIndex:i];
        CGRect frame = [self frameOfPassDot:i of:count];
        dot.layer.cornerRadius = frame.size.width / 2;
        if (i >= had) {
            dot.frame = frame;
            if (motion) {
                CAKeyframeAnimation *pop = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
                pop.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.2f], [NSNumber numberWithFloat:1.35f], [NSNumber numberWithFloat:1], nil];
                pop.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.55f], [NSNumber numberWithFloat:1], nil];
                pop.timingFunctions = [NSArray arrayWithObjects:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
                                       [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], nil];
                pop.duration = 0.28;
                [dot.layer addAnimation:pop forKey:@"pop"];
                CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
                fade.fromValue = [NSNumber numberWithFloat:0];
                fade.toValue = [NSNumber numberWithFloat:1];
                fade.duration = 0.12;
                [dot.layer addAnimation:fade forKey:@"fade"];
            }
        } else if (motion) {
            [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                             animations:^{ dot.frame = frame; } completion:nil];
        } else {
            dot.frame = frame;
        }
    }
}

- (CAShapeLayer *)plateOfKey:(UIButton *)key {
    return _shapeKeys && (NSUInteger)key.tag < _plates.count ? [_plates objectAtIndex:(NSUInteger)key.tag] : nil;
}

- (BOOL)keyMoves {
    return !ExteriaReduceMotionEnabled() && [UIView areAnimationsEnabled] && self.window;
}

/* the color of a plate changes with the press, and a layer that stands on its own animates a change of its fill by itself, which is turned off unless asked for */
- (void)setPlateFill:(UIColor *)color ofKey:(UIButton *)key animated:(BOOL)animated {
    CAShapeLayer *plate = [self plateOfKey:key];
    if (!plate) return;
    CALayer *visible = plate.presentationLayer;
    CGColorRef from = visible ? ((CAShapeLayer *)visible).fillColor : plate.fillColor;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    plate.fillColor = color.CGColor;
    [CATransaction commit];
    [plate removeAnimationForKey:@"fill"];
    if (!animated || !from) return;
    CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"fillColor"];
    fill.fromValue = (id)from;
    fill.toValue = (id)color.CGColor;
    fill.duration = 0.16;
    [plate addAnimation:fill forKey:@"fill"];
}

/* moves the path of the plate through the points in order, from where it is drawn now, ending on the last: a push past the end and a settle, which is the spring of the
   shapes of a Pixel */
- (void)movePlate:(CAShapeLayer *)plate through:(NSArray *)stops duration:(CFTimeInterval)duration {
    CAShapeLayer *visible = (CAShapeLayer *)plate.presentationLayer;
    CGPathRef from = visible && visible.path ? visible.path : plate.path;
    CGPathRef last = (CGPathRef)[stops lastObject];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    plate.path = last;
    [CATransaction commit];
    [plate removeAnimationForKey:@"shape"];
    if (!from || stops.count < 2) return;
    NSMutableArray *values = [NSMutableArray arrayWithObject:(id)from];
    [values addObjectsFromArray:stops];
    CAKeyframeAnimation *morph = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    morph.values = values;
    NSMutableArray *times = [NSMutableArray array], *curves = [NSMutableArray array];
    for (NSUInteger i = 0; i < values.count; ++i) {
        [times addObject:[NSNumber numberWithFloat:(float)i / (float)(values.count - 1)]];
        if (i) [curves addObject:[CAMediaTimingFunction functionWithName:i == 1 ? kCAMediaTimingFunctionEaseOut : kCAMediaTimingFunctionEaseInEaseOut]];
    }
    morph.keyTimes = times;
    morph.timingFunctions = curves;
    morph.duration = duration;
    [plate addAnimation:morph forKey:@"shape"];
}

- (void)layoutPlateOfKey:(UIButton *)key {
    CAShapeLayer *plate = [self plateOfKey:key];
    if (!plate) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    plate.frame = key.bounds;
    if (!_keyDown[key.tag]) {
        CGPoint points[KEY_POINTS];
        ExteriaKeyRestPoints(key.bounds.size, _wideKeys, 1, points);
        CGPathRef path = ExteriaKeyPathCreate(points);
        plate.path = path;
        CGPathRelease(path);
    }
    [CATransaction commit];
}

- (void)keyDown:(UIButton *)key {
    CAShapeLayer *plate = [self plateOfKey:key];
    if (!plate) {
        key.backgroundColor = [self plateDownColor];
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(releaseKey:) object:key];
    _keyDown[key.tag] = YES;
    _pressedAt[key.tag] = CACurrentMediaTime();
    BOOL moves = [self keyMoves];
    [self setPlateFill:[self plateDownColor] ofKey:key animated:moves];
    if (!moves || key.bounds.size.width < 1) return;
    /* every press is a shape of its own, never the one before it, turned to any angle */
    NSUInteger index;
    do { index = arc4random() % KEY_SHAPE_COUNT; } while (index == _lastShape && KEY_SHAPE_COUNT > 1);
    _lastShape = index;
    CGFloat spin = (CGFloat)(arc4random() % 6283) / 1000.0f;
    CGPoint push[KEY_POINTS], shape[KEY_POINTS];
    ExteriaKeyShapePoints(&ExteriaKeyShapes[index], spin, key.bounds.size, 1.12f, push);
    ExteriaKeyShapePoints(&ExteriaKeyShapes[index], spin, key.bounds.size, 1.0f, shape);
    CGPathRef over = ExteriaKeyPathCreate(push), final = ExteriaKeyPathCreate(shape);
    [self movePlate:plate through:[NSArray arrayWithObjects:(id)over, (id)final, nil] duration:0.3];
    CGPathRelease(over);
    CGPathRelease(final);
    /* the shape settles out of a turn, so it does not only grow in place */
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    turn.fromValue = [NSNumber numberWithFloat:(arc4random() & 1 ? 0.45f : -0.45f)];
    turn.toValue = [NSNumber numberWithFloat:0];
    turn.duration = 0.34;
    turn.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [plate addAnimation:turn forKey:@"turn"];
}

/* the plate goes back to its resting form, with a dip under it and a settle */
- (void)restKey:(UIButton *)key animated:(BOOL)animated {
    CAShapeLayer *plate = [self plateOfKey:key];
    if (!plate) return;
    _keyDown[key.tag] = NO;
    BOOL moves = animated && [self keyMoves];
    [self setPlateFill:[self plateColor] ofKey:key animated:moves];
    CGPoint under[KEY_POINTS], rest[KEY_POINTS];
    ExteriaKeyRestPoints(key.bounds.size, _wideKeys, 0.92f, under);
    ExteriaKeyRestPoints(key.bounds.size, _wideKeys, 1, rest);
    CGPathRef dip = ExteriaKeyPathCreate(under), end = ExteriaKeyPathCreate(rest);
    if (moves) {
        [self movePlate:plate through:[NSArray arrayWithObjects:(id)dip, (id)end, nil] duration:0.34];
    } else {
        [plate removeAnimationForKey:@"shape"];
        [plate removeAnimationForKey:@"turn"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        plate.path = end;
        [CATransaction commit];
    }
    CGPathRelease(dip);
    CGPathRelease(end);
}

- (void)releaseKey:(UIButton *)key {
    [self restKey:key animated:YES];
}

/* a tap is over before the shape has shown, so the key keeps its shape for a moment before it goes back */
- (void)settleKey:(UIButton *)key {
    CAShapeLayer *plate = [self plateOfKey:key];
    if (!plate) {
        key.backgroundColor = [self plateColor];
        return;
    }
    if (!_keyDown[key.tag]) return;
    CFTimeInterval wait = [self keyMoves] ? KEY_HOLD - (CACurrentMediaTime() - _pressedAt[key.tag]) : 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(releaseKey:) object:key];
    if (wait > 0.01) [self performSelector:@selector(releaseKey:) withObject:key afterDelay:wait];
    else [self releaseKey:key];
}

- (void)keyUp:(UIButton *)key {
    [self settleKey:key];
}

- (void)digitPressed:(UIButton *)key {
    if (!_inputEnabled || _typed.length >= EXTERIA_PASSCODE_PIN_LEN) return;
    [_typed appendFormat:@"%ld", (long)key.tag];
    [self refreshDots];
    if (_typed.length == EXTERIA_PASSCODE_PIN_LEN) [self scheduleSubmit];
}

/* the last dot shows before the owner judges the code, which may answer with a shake at once. the pad stops taking touches meanwhile: a key pressed in
   this gap is still down when a correct code takes the lock window away, and ios 6 then calls the delegate of a gesture recognizer that was freed with it */
- (void)scheduleSubmit {
    self.inputEnabled = NO;
    [self performSelector:@selector(submitTyped) withObject:nil afterDelay:0.1];
}

- (void)deletePressed {
    if (!_inputEnabled || _typed.length == 0 || _typed.length >= EXTERIA_PASSCODE_PIN_LEN) return;
    [_typed deleteCharactersInRange:NSMakeRange(_typed.length - 1, 1)];
    [self refreshDots];
}

- (void)submitTyped {
    NSString *code = [[_typed copy] autorelease];
    [self retain];
    if (code.length && _submit) _submit(code);
    /* a rejected code clears the digits and leaves the pad in its window to be used again; an accepted one takes the view out of the window or leaves the
       digits in place while the screen moves on */
    if (self.window && !_holdTimer && !_inputEnabled && _typed.length < EXTERIA_PASSCODE_PIN_LEN) self.inputEnabled = YES;
    [self release];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSString *code = field.text;
    if (code.length && _inputEnabled && _submit) _submit(code);
    return NO;
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [field.text stringByReplacingCharactersInRange:range withString:string];
    return [next lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= EXTERIA_PASSCODE_MAX_LEN;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    BOOL pin = _type == EXTERIA_PASSCODE_PIN;
    BOOL landscape = width > height;
    /* a pin in landscape puts the words on the left half and the pad on the right, since four rows of keys do not fit under them in 320 points;
       a screen tall enough to keep the keys at a usable size under the words (the ipad) stays in the centred column */
    CGFloat stackedSide = (height - (MAX(28, height * 0.1) + 78 + 6 + DOT_SIDE + 28) - 16 - 3 * KEY_GAP) / 4;
    BOOL split = pin && landscape && stackedSide < 56;
    CGFloat textWidth = split ? width / 2 : width;
    CGFloat textCenter = textWidth / 2;
    CGFloat labelWidth = MIN(textWidth - 32, 360);
    CGFloat top = pin ? (split ? height * 0.28 : MAX(28, height * 0.1)) : MAX(24, height * (landscape ? 0.1 : 0.14));
    top = MAX(top, _topInset + 8);
    _titleLabel.frame = CGRectMake(textCenter - labelWidth / 2, top, labelWidth, 28);
    _messageLabel.frame = CGRectMake(textCenter - labelWidth / 2, top + 32, labelWidth, 38);
    CGFloat below = top + 78;
    if (!pin) {
        CGFloat fieldWidth = MIN(width - 48, 320);
        _plate.frame = CGRectMake((width - fieldWidth) / 2, below + 8, fieldWidth, FIELD_HEIGHT);
        _field.frame = _plate.frame;
        _passDots.frame = _plate.bounds;
        [self refreshPasswordDotsAnimated:NO];
        _biometricButton.frame = CGRectMake((width - fieldWidth) / 2, below + 8 + FIELD_HEIGHT + 12, fieldWidth, 40);
        return;
    }
    CGFloat dotsWidth = EXTERIA_PASSCODE_PIN_LEN * DOT_SIDE + (EXTERIA_PASSCODE_PIN_LEN - 1) * DOT_GAP;
    for (NSUInteger i = 0; i < _dots.count; ++i) {
        ((UIView *)[_dots objectAtIndex:i]).frame = CGRectMake(textCenter - dotsWidth / 2 + i * (DOT_SIDE + DOT_GAP), below + 6, DOT_SIDE, DOT_SIDE);
    }
    CGFloat padTop = split ? 12 : below + 6 + DOT_SIDE + 28;
    CGFloat padHeight = height - padTop - 16;
    BOOL widePad = !split && width >= 600 && height >= 600;
    _wideKeys = widePad;
    CGFloat side = MAX(40, MIN(KEY_SIDE_MAX, (padHeight - 3 * KEY_GAP) / 4));
    CGFloat keyWidth = widePad ? (width - 64 - 2 * KEY_GAP) / 3 : side;
    CGFloat keyHeight = widePad ? MAX(0, (padHeight - 3 * KEY_GAP) / 4) : side;
    CGFloat padWidth = 3 * keyWidth + 2 * KEY_GAP;
    CGFloat padLeft = split ? width / 2 + (width / 2 - padWidth) / 2 : (width - padWidth) / 2;
    if (split) padTop = MAX(8, (height - (4 * keyHeight + 3 * KEY_GAP)) / 2);
    for (NSInteger row = 0; row < 4; ++row) {
        for (NSInteger column = 0; column < 3; ++column) {
            CGRect frame = CGRectMake(padLeft + column * (keyWidth + KEY_GAP), padTop + row * (keyHeight + KEY_GAP), keyWidth, keyHeight);
            NSInteger digit = row < 3 ? row * 3 + column + 1 : (column == 1 ? 0 : -1);
            if (digit >= 0) {
                UIButton *key = [_keys objectAtIndex:(NSUInteger)digit];
                key.frame = frame;
                if (_shapeKeys) [self layoutPlateOfKey:key];
                else key.layer.cornerRadius = widePad ? MIN(20, keyHeight / 2) : side / 2;
                key.titleLabel.font = ExteriaFontRegular(widePad ? 36 : 30);
            } else if (column == 2) {
                _delete.frame = frame;
            } else {
                _biometricButton.frame = frame;
            }
        }
    }
}

@end
