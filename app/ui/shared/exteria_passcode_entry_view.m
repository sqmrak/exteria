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

static void ExteriaPasscodeKeyShape(UIButton *key, BOOL pressed, BOOL animated) {
    CGFloat width = key.bounds.size.width, height = key.bounds.size.height;
    CGFloat side = MIN(width, height);
    CGFloat normal = fabs(width - height) < 0.5 ? side / 2 : MIN(20, side / 2);
    CGFloat radius = pressed ? MIN(normal, side * 0.19f) : normal;
    CALayer *visible = (CALayer *)key.layer.presentationLayer;
    CGFloat from = visible ? visible.cornerRadius : key.layer.cornerRadius;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    key.layer.cornerRadius = radius;
    [CATransaction commit];
    [key.layer removeAnimationForKey:@"keyShape"];
    if (animated && side > 0) {
        CABasicAnimation *shape = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        shape.fromValue = [NSNumber numberWithDouble:from];
        shape.toValue = [NSNumber numberWithDouble:radius];
        shape.duration = pressed ? 0.12 : 0.22;
        shape.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [key.layer addAnimation:shape forKey:@"keyShape"];
    }
}

@interface ExteriaPasscodeEntryView () <UITextFieldDelegate> {
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    NSMutableArray *_dots;
    NSMutableArray *_keys;
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
        key.backgroundColor = [self plateColor];
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
        if (!enabled) {
            [key.layer removeAllAnimations];
            key.transform = CGAffineTransformIdentity;
            key.backgroundColor = [self plateColor];
            if (!ExteriaThemeIsClassic()) ExteriaPasscodeKeyShape(key, NO, NO);
        }
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

- (void)keyDown:(UIButton *)key {
    key.backgroundColor = [self plateDownColor];
    if (!ExteriaThemeIsClassic())
        ExteriaPasscodeKeyShape(key, YES, !ExteriaReduceMotionEnabled() && [UIView areAnimationsEnabled]);
    if (!ExteriaThemeIsClassic() && !ExteriaReduceMotionEnabled() && [UIView areAnimationsEnabled]) {
        [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{ key.transform = CGAffineTransformMakeScale(0.9f, 0.9f); } completion:nil];
    }
}

- (void)keyUp:(UIButton *)key {
    key.backgroundColor = [self plateColor];
    if (!ExteriaThemeIsClassic())
        ExteriaPasscodeKeyShape(key, NO, !ExteriaReduceMotionEnabled() && [UIView areAnimationsEnabled]);
    if (!ExteriaThemeIsClassic() && !ExteriaReduceMotionEnabled() && [UIView areAnimationsEnabled]) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{ key.transform = CGAffineTransformIdentity; } completion:nil];
    } else {
        key.transform = CGAffineTransformIdentity;
    }
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
                key.layer.cornerRadius = widePad ? MIN(20, keyHeight / 2) : side / 2;
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
