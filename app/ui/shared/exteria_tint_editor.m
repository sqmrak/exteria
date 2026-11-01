#import "exteria_tint_editor.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define EDITOR_HEIGHT 372.0
#define MARGIN 16.0
#define CARD_HEIGHT 112.0
#define CARD_RADIUS 30.0
#define TRACK_HEIGHT 28.0
#define THUMB_SIDE 38.0
#define SLIDER_ROW 40.0
#define CHIP_SIDE 44.0
#define CHIP_GAP 12.0
#define LOBES 10
/* the value of the light accent of the palette, which every color of the editor is shown at */
#define SHOWN_VALUE 0.745

static const struct { float hue, saturation; } ExteriaTintPresets[] = {
    {286, 0.60f}, {337, 0.80f}, {2, 0.75f}, {24, 0.82f}, {42, 0.85f}, {135, 0.58f}, {174, 0.70f}, {212, 0.76f}, {252, 0.62f}, {0, 0}
};
#define PRESET_COUNT (sizeof(ExteriaTintPresets) / sizeof(ExteriaTintPresets[0]))

static UIColor *ExteriaShown(float hue, float saturation) {
    CGFloat red, green, blue;
    ExteriaHSVToRGB(hue, saturation, SHOWN_VALUE, &red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:1];
}

static void ExteriaSpring(void (^changes)(void)) {
    [CATransaction begin];
    if (ExteriaReduceMotionEnabled()) {
        [CATransaction setDisableActions:YES];
    } else {
        [CATransaction setAnimationDuration:0.3];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithControlPoints:0.34f:1.45f:0.64f:1.0f]];
    }
    changes();
    [CATransaction commit];
}

#pragma mark track

/* a slider whose track is a gradient and whose handle is a ringed disc in the color it sets; the handle swells while it is held */
@interface ExteriaTintTrack : UIControl {
    CAGradientLayer *_track;
    CALayer *_handle;
    float _fraction;
}
@property (nonatomic, assign) float fraction;
@property (nonatomic, copy) NSString *spokenName;
- (void)setColors:(NSArray *)colors;
- (void)setHandleColor:(UIColor *)color;
@end

@implementation ExteriaTintTrack

@synthesize fraction = _fraction;
@synthesize spokenName = _spokenName;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.isAccessibilityElement = YES;
    /* UIAccessibilityTraitAdjustable is 1 << 12; the constant is not exported by every runtime this app starts on */
    self.accessibilityTraits = (UIAccessibilityTraits)(1 << 12);
    _track = [[CAGradientLayer alloc] init];
    _track.startPoint = CGPointMake(0, 0.5f);
    _track.endPoint = CGPointMake(1, 0.5f);
    _track.cornerRadius = TRACK_HEIGHT / 2;
    [self.layer addSublayer:_track];
    _handle = [[CALayer alloc] init];
    _handle.bounds = CGRectMake(0, 0, THUMB_SIDE, THUMB_SIDE);
    _handle.cornerRadius = THUMB_SIDE / 2;
    _handle.borderWidth = 4;
    _handle.borderColor = [UIColor whiteColor].CGColor;
    _handle.shadowColor = [UIColor blackColor].CGColor;
    _handle.shadowOpacity = 0.3f;
    _handle.shadowRadius = 4;
    _handle.shadowOffset = CGSizeMake(0, 2);
    [self.layer addSublayer:_handle];
    return self;
}

- (void)dealloc {
    [_track release];
    [_handle release];
    [_spokenName release];
    [super dealloc];
}

- (CGFloat)travel { return MAX(1, self.bounds.size.width - THUMB_SIDE); }

- (void)place {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGSize size = self.bounds.size;
    _track.frame = CGRectMake(0, (size.height - TRACK_HEIGHT) / 2, size.width, TRACK_HEIGHT);
    _handle.position = CGPointMake(THUMB_SIDE / 2 + _fraction * [self travel], size.height / 2);
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self place];
}

- (void)setFraction:(float)fraction {
    _fraction = MIN(1, MAX(0, fraction));
    [self place];
}

- (void)setColors:(NSArray *)colors {
    NSMutableArray *refs = [NSMutableArray array];
    for (UIColor *color in colors) [refs addObject:(id)color.CGColor];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _track.colors = refs;
    [CATransaction commit];
}

- (void)setHandleColor:(UIColor *)color {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _handle.backgroundColor = color.CGColor;
    [CATransaction commit];
}

- (void)swell:(BOOL)held {
    ExteriaSpring(^{ _handle.transform = held ? CATransform3DMakeScale(1.18f, 1.18f, 1) : CATransform3DIdentity; });
}

- (void)moveToTouch:(UITouch *)touch {
    float before = _fraction;
    self.fraction = (float)(([touch locationInView:self].x - THUMB_SIDE / 2) / [self travel]);
    if (_fraction != before) [self sendActionsForControlEvents:UIControlEventValueChanged];
}

/* a UIControl keeps the touch when the table around it starts to scroll, which a plain view does not on ios 5 */
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self swell:YES];
    [self moveToTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self moveToTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self swell:NO];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self swell:NO];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -8, -MAX(0, (44 - self.bounds.size.height) / 2)), point);
}

- (NSString *)accessibilityLabel { return _spokenName; }
- (NSString *)accessibilityValue { return [NSString stringWithFormat:@"%.0f%%", _fraction * 100]; }

- (void)stepBy:(float)step {
    self.fraction = _fraction + step;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)accessibilityIncrement { [self stepBy:0.05f]; }
- (void)accessibilityDecrement { [self stepBy:-0.05f]; }

@end

#pragma mark editor

@interface ExteriaTintEditor () {
    float _hue;
    float _saturation;
    UIView *_card;
    CAShapeLayer *_cookie;
    UILabel *_hash;
    UITextField *_field;
    UILabel *_hueName;
    UILabel *_saturationName;
    ExteriaTintTrack *_hueTrack;
    ExteriaTintTrack *_saturationTrack;
    UIScrollView *_chips;
    NSMutableArray *_chipButtons;
    NSInteger _chosenChip;
}
@end

@implementation ExteriaTintEditor

@synthesize hue = _hue;
@synthesize saturation = _saturation;

- (CGFloat)preferredHeight { return EDITOR_HEIGHT; }
- (CGRect)editingRect { return _card.frame; }

/* ten lobes on a circle: the scalloped shape of the expressive set */
static CGPathRef ExteriaCookiePath(CGFloat radius) {
    CGMutablePathRef path = CGPathCreateMutable();
    int steps = 120;
    for (int i = 0; i <= steps; ++i) {
        CGFloat angle = (CGFloat)i / steps * (CGFloat)(M_PI * 2);
        CGFloat r = radius * (1 + 0.09 * cos(angle * LOBES));
        CGPoint point = CGPointMake(radius + r * cos(angle), radius + r * sin(angle));
        if (i == 0) CGPathMoveToPoint(path, NULL, point.x, point.y);
        else CGPathAddLineToPoint(path, NULL, point.x, point.y);
    }
    CGPathCloseSubpath(path);
    return (CGPathRef)[(id)path autorelease];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _chosenChip = -1;
    _card = [[UIView alloc] init];
    _card.layer.cornerRadius = CARD_RADIUS;
    [self addSubview:_card];
    _cookie = [[CAShapeLayer alloc] init];
    _cookie.path = ExteriaCookiePath(34);
    _cookie.bounds = CGRectMake(0, 0, 68, 68);
    _cookie.fillColor = [UIColor colorWithWhite:1 alpha:0.22f].CGColor;
    [_card.layer addSublayer:_cookie];
    _hash = [[UILabel alloc] init];
    _hash.text = @"#";
    _hash.font = ExteriaFontSemibold(32);
    _hash.backgroundColor = [UIColor clearColor];
    [_card addSubview:_hash];
    _field = [[UITextField alloc] init];
    _field.delegate = self;
    _field.backgroundColor = [UIColor clearColor];
    _field.font = ExteriaFontSemibold(32);
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.keyboardType = UIKeyboardTypeASCIICapable;
    _field.returnKeyType = UIReturnKeyDone;
    _field.accessibilityLabel = NSLocalizedString(@"chatset.tint.hex", nil);
    [_field addTarget:self action:@selector(hexEdited) forControlEvents:UIControlEventEditingChanged];
    [_card addSubview:_field];
    UIColor *secondary = ExteriaColorSecondary();
    _hueName = [[UILabel alloc] init];
    _hueName.text = NSLocalizedString(@"chatset.tint.hue", nil);
    _saturationName = [[UILabel alloc] init];
    _saturationName.text = NSLocalizedString(@"chatset.tint.saturation", nil);
    for (UILabel *label in [NSArray arrayWithObjects:_hueName, _saturationName, nil]) {
        label.font = ExteriaFontMedium(13);
        label.textColor = secondary;
        label.backgroundColor = [UIColor clearColor];
        [self addSubview:label];
    }
    _hueTrack = [[ExteriaTintTrack alloc] init];
    _hueTrack.spokenName = _hueName.text;
    [_hueTrack addTarget:self action:@selector(hueMoved) forControlEvents:UIControlEventValueChanged];
    [_hueTrack addTarget:self action:@selector(released) forControlEvents:UIControlEventTouchUpInside];
    NSMutableArray *rainbow = [NSMutableArray array];
    for (int i = 0; i <= 6; ++i) [rainbow addObject:ExteriaShown(i * 60, 0.78f)];
    [_hueTrack setColors:rainbow];
    [self addSubview:_hueTrack];
    _saturationTrack = [[ExteriaTintTrack alloc] init];
    _saturationTrack.spokenName = _saturationName.text;
    [_saturationTrack addTarget:self action:@selector(saturationMoved) forControlEvents:UIControlEventValueChanged];
    [_saturationTrack addTarget:self action:@selector(released) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_saturationTrack];

    _chips = [[UIScrollView alloc] init];
    _chips.showsHorizontalScrollIndicator = NO;
    _chips.showsVerticalScrollIndicator = NO;
    _chips.scrollsToTop = NO;
    [self addSubview:_chips];
    _chipButtons = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < PRESET_COUNT; ++i) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        chip.tag = (NSInteger)i;
        chip.layer.cornerRadius = CHIP_SIDE / 2;
        chip.backgroundColor = ExteriaShown(ExteriaTintPresets[i].hue, ExteriaTintPresets[i].saturation);
        chip.accessibilityLabel = ExteriaHexOfTint(ExteriaTintPresets[i].hue, ExteriaTintPresets[i].saturation);
        [chip setImage:ExteriaSymbolImage(ExteriaSymbolCheck, 22, [UIColor whiteColor]) forState:UIControlStateSelected];
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_chips addSubview:chip];
        [_chipButtons addObject:chip];
    }
    [self refresh];
    return self;
}

- (void)dealloc {
    _field.delegate = nil;
    [_card release];
    [_cookie release];
    [_hash release];
    [_field release];
    [_hueName release];
    [_saturationName release];
    [_hueTrack release];
    [_saturationTrack release];
    [_chips release];
    [_chipButtons release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, inner = width - 2 * MARGIN;
    CGFloat y = 12;
    _card.frame = CGRectMake(MARGIN, y, inner, CARD_HEIGHT);
    CGFloat digits = 0;
    for (NSString *sample in [NSArray arrayWithObjects:@"000000", @"888888", @"FFFFFF", @"BBBBBB", nil]) {
        UILabel *probe = [[[UILabel alloc] init] autorelease];
        probe.font = _field.font;
        probe.text = sample;
        [probe sizeToFit];
        digits = MAX(digits, probe.frame.size.width);
    }
    [_hash sizeToFit];
    CGFloat hashWidth = _hash.frame.size.width;
    _hash.frame = CGRectMake(24, 18, hashWidth, 44);
    _field.frame = CGRectMake(24 + hashWidth + 1, 18, ceil(digits) + 6, 44);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _cookie.position = CGPointMake(inner - 24 - 34 - 6, CARD_HEIGHT / 2);
    [CATransaction commit];
    y += CARD_HEIGHT + 22;
    _hueName.frame = CGRectMake(MARGIN + 4, y, inner, 18);
    _hueTrack.frame = CGRectMake(MARGIN, y + 20, inner, SLIDER_ROW);
    y += 20 + SLIDER_ROW + 12;
    _saturationName.frame = CGRectMake(MARGIN + 4, y, inner, 18);
    _saturationTrack.frame = CGRectMake(MARGIN, y + 20, inner, SLIDER_ROW);
    y += 20 + SLIDER_ROW + 22;
    _chips.frame = CGRectMake(0, y, width, CHIP_SIDE + 8);
    for (NSUInteger i = 0; i < _chipButtons.count; ++i) {
        [[_chipButtons objectAtIndex:i] setFrame:CGRectMake(MARGIN + i * (CHIP_SIDE + CHIP_GAP), 4, CHIP_SIDE, CHIP_SIDE)];
    }
    _chips.contentSize = CGSizeMake(2 * MARGIN + _chipButtons.count * (CHIP_SIDE + CHIP_GAP) - CHIP_GAP, CHIP_SIDE + 8);
}

/* the card, the hex, the shape, the tracks and the chosen chip all follow the one color */
- (void)refresh {
    UIColor *color = ExteriaThemeCustomTintColor(_hue, _saturation);
    CGFloat red = 0, green = 0, blue = 0;
    [color getRed:&red green:&green blue:&blue alpha:NULL];
    BOOL dark = 0.299f * red + 0.587f * green + 0.114f * blue > 0.62f;
    UIColor *ink = dark ? [UIColor colorWithWhite:0.1f alpha:1] : [UIColor whiteColor];
    _card.backgroundColor = color;
    _hash.textColor = [ink colorWithAlphaComponent:0.6f];
    _field.textColor = ink;
    /* the caret takes the ink on ios 7 and later; the older runtimes have no tintColor on a field and draw a plain caret */
    if ([_field respondsToSelector:@selector(setTintColor:)]) [_field performSelector:@selector(setTintColor:) withObject:ink];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _cookie.fillColor = [ink colorWithAlphaComponent:0.16f].CGColor;
    /* the shape turns with the hue */
    _cookie.transform = CATransform3DMakeRotation(_hue / 360.0f * (CGFloat)(M_PI * 2) / LOBES, 0, 0, 1);
    [CATransaction commit];
    if (!_field.isFirstResponder) _field.text = ExteriaHexOfTint(_hue, _saturation);
    _hueTrack.fraction = _hue / 360.0f;
    _saturationTrack.fraction = _saturation;
    [_hueTrack setHandleColor:ExteriaShown(_hue, MAX(0.78f, _saturation))];
    [_saturationTrack setHandleColor:color];
    [_saturationTrack setColors:[NSArray arrayWithObjects:ExteriaShown(_hue, 0), ExteriaShown(_hue, 1), nil]];
    NSInteger chosen = -1;
    for (NSUInteger i = 0; i < PRESET_COUNT; ++i) {
        float dh = fabsf(ExteriaTintPresets[i].hue - _hue);
        if (dh > 180) dh = 360 - dh;
        BOOL grey = ExteriaTintPresets[i].saturation == 0;
        if (fabsf(ExteriaTintPresets[i].saturation - _saturation) < 0.03f && (grey || dh < 3)) {
            chosen = (NSInteger)i;
            break;
        }
    }
    if (chosen != _chosenChip) {
        _chosenChip = chosen;
        for (NSUInteger i = 0; i < _chipButtons.count; ++i) {
            UIButton *chip = [_chipButtons objectAtIndex:i];
            BOOL on = (NSInteger)i == chosen;
            chip.selected = on;
            /* the chosen color is a rounded square, the others stay discs */
            CGFloat radius = on ? 14 : CHIP_SIDE / 2;
            CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
            morph.fromValue = [NSNumber numberWithDouble:chip.layer.cornerRadius];
            morph.toValue = [NSNumber numberWithDouble:radius];
            morph.duration = ExteriaReduceMotionEnabled() ? 0 : 0.3;
            morph.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.34f:1.45f:0.64f:1.0f];
            chip.layer.cornerRadius = radius;
            [chip.layer addAnimation:morph forKey:@"cornerRadius"];
        }
    }
}

- (void)setHue:(float)hue {
    _hue = MIN(360, MAX(0, hue));
    [self refresh];
}

- (void)setSaturation:(float)saturation {
    _saturation = MIN(1, MAX(0, saturation));
    [self refresh];
}

- (void)hueMoved {
    _hue = _hueTrack.fraction * 360.0f;
    [self refresh];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)saturationMoved {
    _saturation = _saturationTrack.fraction;
    [self refresh];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)released {
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)chipTapped:(UIButton *)chip {
    _hue = ExteriaTintPresets[chip.tag].hue;
    _saturation = ExteriaTintPresets[chip.tag].saturation;
    [self refresh];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

#pragma mark hex

- (void)hexEdited {
    float hue = _hue, saturation = _saturation;
    if (_field.text.length != 6 || !ExteriaTintOfHex(_field.text, &hue, &saturation)) return;
    _hue = hue;
    _saturation = saturation;
    [self refresh];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    return ExteriaTintHexAllowed([field.text stringByReplacingCharactersInRange:range withString:[string uppercaseString]]);
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

/* the color is taken when the field is done; a short or broken entry goes back to the color on the card */
- (void)textFieldDidEndEditing:(UITextField *)field {
    float hue = _hue, saturation = _saturation;
    BOOL valid = ExteriaTintOfHex(field.text, &hue, &saturation);
    if (valid) {
        _hue = hue;
        _saturation = saturation;
    }
    [self refresh];
    if (valid) [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

/* a tap on the card brings the keyboard */
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    return CGRectContainsPoint(_card.frame, [touch locationInView:self]);
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [_field becomeFirstResponder];
}

@end
