#import "exteria_expressive_slider.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_settings.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define TRACK_HEIGHT 20.0
#define HANDLE_WIDTH 5.0
#define HANDLE_PRESSED_WIDTH 3.0
#define HANDLE_GAP 6.0
#define SIDE_INSET 2.0

@interface ExteriaExpressiveSlider () {
    CALayer *_inactive;
    CALayer *_active;
    CALayer *_handle;
    float _minimum;
    float _maximum;
    float _value;
}
@end

@implementation ExteriaExpressiveSlider

static CGFloat size_handle(CGFloat height) { return MIN(height, 34); }

@synthesize minimumValue = _minimum;
@synthesize maximumValue = _maximum;
@synthesize value = _value;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _maximum = 1;
    self.isAccessibilityElement = YES;
    /* UIAccessibilityTraitAdjustable is 1 << 12; the constant is not exported by every runtime this app starts on */
    self.accessibilityTraits = (UIAccessibilityTraits)(1 << 12);
    UIColor *accent = ExteriaColorAccent();
    _inactive = [[CALayer alloc] init];
    _inactive.backgroundColor = [accent colorWithAlphaComponent:0.22f].CGColor;
    [self.layer addSublayer:_inactive];
    _active = [[CALayer alloc] init];
    _active.backgroundColor = accent.CGColor;
    [self.layer addSublayer:_active];
    _handle = [[CALayer alloc] init];
    _handle.backgroundColor = accent.CGColor;
    [self.layer addSublayer:_handle];
    return self;
}

- (void)dealloc {
    [_inactive release];
    [_active release];
    [_handle release];
    [super dealloc];
}

- (CGFloat)travel {
    return MAX(1, self.bounds.size.width - SIDE_INSET * 2);
}

- (float)fraction {
    return _maximum > _minimum ? (_value - _minimum) / (_maximum - _minimum) : 0;
}

/* the active part ends a gap before the handle and the rest starts a gap after it; the ends facing the handle are small corners, the outer ends are
   full circles */
- (void)place {
    CGSize size = self.bounds.size;
    CGFloat track = MIN(TRACK_HEIGHT, size.height);
    CGFloat top = floor((size.height - track) / 2);
    CGFloat x = SIDE_INSET + [self fraction] * [self travel];
    CGFloat activeWidth = MAX(0, x - HANDLE_GAP - SIDE_INSET);
    CGFloat restStart = x + HANDLE_GAP;
    CGFloat restWidth = MAX(0, size.width - SIDE_INSET - restStart);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _active.frame = CGRectMake(SIDE_INSET, top, activeWidth, track);
    _active.cornerRadius = MIN(track / 2, activeWidth / 2);
    _inactive.frame = CGRectMake(restStart, top, restWidth, track);
    _inactive.cornerRadius = MIN(track / 2, restWidth / 2);
    _handle.position = CGPointMake(x, size.height / 2);
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _handle.bounds = CGRectMake(0, 0, HANDLE_WIDTH, size_handle(self.bounds.size.height));
    _handle.cornerRadius = HANDLE_WIDTH / 2;
    [CATransaction commit];
    [self place];
}

- (void)setValue:(float)value {
    value = value < _minimum ? _minimum : (value > _maximum ? _maximum : value);
    if (value == _value) return;
    _value = value;
    [self place];
}

- (void)setMinimumValue:(float)minimum {
    _minimum = minimum;
    [self place];
}

- (void)setMaximumValue:(float)maximum {
    _maximum = maximum;
    [self place];
}

#pragma mark touch

- (void)squeeze:(BOOL)squeezed {
    CGFloat width = squeezed ? HANDLE_PRESSED_WIDTH : HANDLE_WIDTH;
    [CATransaction begin];
    if (ExteriaReduceMotionEnabled()) {
        [CATransaction setDisableActions:YES];
    } else {
        [CATransaction setAnimationDuration:0.25];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithControlPoints:0.34f:1.45f:0.64f:1.0f]];
    }
    _handle.bounds = CGRectMake(0, 0, width, size_handle(self.bounds.size.height));
    [CATransaction commit];
}

- (void)setValueForTouch:(UITouch *)touch {
    CGFloat x = [touch locationInView:self].x;
    float fraction = (float)((x - SIDE_INSET) / [self travel]);
    fraction = fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction);
    float before = _value;
    self.value = _minimum + fraction * (_maximum - _minimum);
    if (_value != before) [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self squeeze:YES];
    [self setValueForTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self setValueForTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)touch;
    (void)event;
    [self squeeze:NO];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event;
    [self squeeze:NO];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return CGRectContainsPoint(CGRectInset(self.bounds, -6, -MAX(0, (44 - self.bounds.size.height) / 2)), point);
}

#pragma mark accessibility

- (NSString *)accessibilityValue {
    return [NSString stringWithFormat:@"%g", (double)_value];
}

- (void)stepBy:(float)step {
    float before = _value;
    self.value = _value + step;
    if (_value != before) [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)accessibilityIncrement { [self stepBy:MAX(1, (_maximum - _minimum) / 20)]; }
- (void)accessibilityDecrement { [self stepBy:-MAX(1, (_maximum - _minimum) / 20)]; }

@end
