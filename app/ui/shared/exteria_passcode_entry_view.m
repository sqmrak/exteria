#import <QuartzCore/QuartzCore.h>
#import "exteria_passcode_entry_view.h"

#import "exteria_symbol.h"
#import "exteria_theme.h"

#define DOT_SIDE 14.0
#define DOT_GAP 22.0
#define KEY_SIDE_MAX 76.0
#define KEY_GAP 14.0
#define FIELD_HEIGHT 46.0

@interface ExteriaPasscodeEntryView () <UITextFieldDelegate> {
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    NSMutableArray *_dots;
    NSMutableArray *_keys;
    UIButton *_delete;
    UIButton *_biometricButton;
    UITextField *_field;
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
@synthesize topInset = _topInset;
@synthesize inputEnabled = _inputEnabled;

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
    _field = [[UITextField alloc] init];
    _field.backgroundColor = ExteriaColorField();
    _field.layer.cornerRadius = 10;
    _field.textColor = ExteriaColorTitle();
    _field.font = ExteriaFontRegular(18);
    _field.textAlignment = ExteriaTextAlignmentCenter;
    _field.secureTextEntry = YES;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _field.returnKeyType = UIReturnKeyDone;
    _field.enablesReturnKeyAutomatically = YES;
    _field.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _field.delegate = self;
    [self addSubview:_field];
    [self applyType];
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
    if (pin) [_field resignFirstResponder];
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
    [_biometricButton setTitle:title forState:UIControlStateNormal];
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
    for (UIButton *key in _keys) key.enabled = enabled;
    _delete.enabled = enabled;
    _biometricButton.enabled = enabled;
    _field.enabled = enabled;
}

- (void)reset {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(submitTyped) object:nil];
    [_typed setString:@""];
    _field.text = @"";
    [self refreshDots];
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
    [_field.layer addAnimation:shake forKey:@"shake"];
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

- (void)refreshDots {
    UIColor *color = ExteriaColorTitle();
    for (NSUInteger i = 0; i < _dots.count; ++i) {
        UIView *dot = [_dots objectAtIndex:i];
        dot.layer.borderColor = color.CGColor;
        dot.backgroundColor = i < _typed.length ? color : [UIColor clearColor];
    }
}

- (void)keyDown:(UIButton *)key {
    key.backgroundColor = ExteriaColorAccent();
}

- (void)keyUp:(UIButton *)key {
    key.backgroundColor = ExteriaColorField();
}

- (void)digitPressed:(UIButton *)key {
    if (!_inputEnabled || _typed.length >= EXTERIA_PASSCODE_PIN_LEN) return;
    [_typed appendFormat:@"%ld", (long)key.tag];
    [self refreshDots];
    /* the last dot shows before the owner judges the code, which may answer with a shake at once */
    if (_typed.length == EXTERIA_PASSCODE_PIN_LEN) [self performSelector:@selector(submitTyped) withObject:nil afterDelay:0.1];
}

- (void)deletePressed {
    if (!_inputEnabled || _typed.length == 0 || _typed.length >= EXTERIA_PASSCODE_PIN_LEN) return;
    [_typed deleteCharactersInRange:NSMakeRange(_typed.length - 1, 1)];
    [self refreshDots];
}

- (void)submitTyped {
    NSString *code = [[_typed copy] autorelease];
    if (code.length && _submit) _submit(code);
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
        _field.frame = CGRectMake((width - fieldWidth) / 2, below + 8, fieldWidth, FIELD_HEIGHT);
        _biometricButton.frame = CGRectMake((width - fieldWidth) / 2, below + 8 + FIELD_HEIGHT + 12, fieldWidth, 40);
        return;
    }
    CGFloat dotsWidth = EXTERIA_PASSCODE_PIN_LEN * DOT_SIDE + (EXTERIA_PASSCODE_PIN_LEN - 1) * DOT_GAP;
    for (NSUInteger i = 0; i < _dots.count; ++i) {
        ((UIView *)[_dots objectAtIndex:i]).frame = CGRectMake(textCenter - dotsWidth / 2 + i * (DOT_SIDE + DOT_GAP), below + 6, DOT_SIDE, DOT_SIDE);
    }
    CGFloat padTop = split ? 12 : below + 6 + DOT_SIDE + 28;
    CGFloat padHeight = height - padTop - 16;
    CGFloat side = MAX(40, MIN(KEY_SIDE_MAX, (padHeight - 3 * KEY_GAP) / 4));
    CGFloat padWidth = 3 * side + 2 * KEY_GAP;
    CGFloat padLeft = split ? width / 2 + (width / 2 - padWidth) / 2 : (width - padWidth) / 2;
    if (split) padTop = MAX(8, (height - (4 * side + 3 * KEY_GAP)) / 2);
    for (NSInteger row = 0; row < 4; ++row) {
        for (NSInteger column = 0; column < 3; ++column) {
            CGRect frame = CGRectMake(padLeft + column * (side + KEY_GAP), padTop + row * (side + KEY_GAP), side, side);
            NSInteger digit = row < 3 ? row * 3 + column + 1 : (column == 1 ? 0 : -1);
            if (digit >= 0) {
                UIButton *key = [_keys objectAtIndex:(NSUInteger)digit];
                key.frame = frame;
                key.layer.cornerRadius = side / 2;
            } else if (column == 2) {
                _delete.frame = frame;
            } else {
                _biometricButton.frame = frame;
            }
        }
    }
}

@end
