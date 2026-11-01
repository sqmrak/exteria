#import "exteria_tint_picker.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_theme.h"

#define PICKER_HEIGHT 196.0
#define PICKER_INSET 16.0
#define THUMB_SIDE 30.0
/* the square is drawn this coarse and the layer smooths it up; a pixel per point would be 60 thousand colors on every layout */
#define RENDER_WIDTH 120
#define RENDER_HEIGHT 60

@implementation ExteriaTintPicker

@synthesize hue = _hue;
@synthesize saturation = _saturation;

+ (CGFloat)height { return PICKER_HEIGHT; }

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    _thumb = [[UIView alloc] init];
    _thumb.userInteractionEnabled = NO;
    _thumb.layer.cornerRadius = THUMB_SIDE / 2;
    _thumb.layer.borderWidth = 3;
    _thumb.layer.borderColor = [UIColor whiteColor].CGColor;
    _thumb.layer.shadowColor = [UIColor blackColor].CGColor;
    _thumb.layer.shadowOpacity = 0.35;
    _thumb.layer.shadowRadius = 3;
    _thumb.layer.shadowOffset = CGSizeMake(0, 1);
    [self addSubview:_thumb];
    return self;
}

- (void)dealloc {
    [_thumb release];
    [super dealloc];
}

- (CGRect)squareRect {
    return CGRectInset(self.bounds, PICKER_INSET, 8);
}

- (void)renderSquare {
    CGRect square = [self squareRect];
    if (square.size.width <= 0 || square.size.height <= 0) return;
    if (CGSizeEqualToSize(_renderedSize, square.size) && self.layer.contents) return;
    static uint8_t pixels[RENDER_WIDTH * RENDER_HEIGHT * 4];
    for (int y = 0; y < RENDER_HEIGHT; ++y) {
        CGFloat saturation = 1 - (CGFloat)y / (RENDER_HEIGHT - 1);
        for (int x = 0; x < RENDER_WIDTH; ++x) {
            CGFloat red, green, blue;
            ExteriaHSVToRGB(360.0 * x / (RENDER_WIDTH - 1), saturation, 0.745, &red, &green, &blue);
            uint8_t *pixel = pixels + (y * RENDER_WIDTH + x) * 4;
            pixel[0] = (uint8_t)(red * 255 + 0.5);
            pixel[1] = (uint8_t)(green * 255 + 0.5);
            pixel[2] = (uint8_t)(blue * 255 + 0.5);
            pixel[3] = 255;
        }
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, RENDER_WIDTH, RENDER_HEIGHT, 8, RENDER_WIDTH * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        NSLog(@"exteria: the color square could not be drawn");
        return;
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!image) {
        NSLog(@"exteria: the color square could not be drawn");
        return;
    }
    /* the square is the layer of a hidden view under the thumb, so the control keeps clear corners */
    UIView *ground = [self viewWithTag:7001];
    if (!ground) {
        ground = [[[UIView alloc] init] autorelease];
        ground.tag = 7001;
        ground.userInteractionEnabled = NO;
        ground.layer.cornerRadius = 14;
        ground.layer.masksToBounds = YES;
        [self insertSubview:ground belowSubview:_thumb];
    }
    ground.frame = square;
    ground.layer.contents = (id)image;
    ground.layer.magnificationFilter = kCAFilterLinear;
    CGImageRelease(image);
    _renderedSize = square.size;
}

- (void)placeThumb {
    CGRect square = [self squareRect];
    _thumb.frame = CGRectMake(0, 0, THUMB_SIDE, THUMB_SIDE);
    _thumb.center = CGPointMake(square.origin.x + square.size.width * _hue / 360.0, square.origin.y + square.size.height * (1 - _saturation));
    _thumb.backgroundColor = ExteriaThemeCustomTintColor(_hue, _saturation);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self renderSquare];
    [self placeThumb];
}

- (void)setHue:(float)hue {
    _hue = MIN(360, MAX(0, hue));
    [self placeThumb];
}

- (void)setSaturation:(float)saturation {
    _saturation = MIN(1, MAX(0, saturation));
    [self placeThumb];
}

- (void)moveToPoint:(CGPoint)point {
    CGRect square = [self squareRect];
    if (square.size.width <= 0 || square.size.height <= 0) return;
    float hue = (float)((point.x - square.origin.x) / square.size.width * 360.0);
    float saturation = (float)(1 - (point.y - square.origin.y) / square.size.height);
    self.hue = hue;
    self.saturation = saturation;
}

/* a UIControl keeps the touch when the table around it starts to scroll, which a plain view does not on ios 5 */
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self moveToPoint:[touch locationInView:self]];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self moveToPoint:[touch locationInView:self]];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (touch) [self moveToPoint:[touch locationInView:self]];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (NSString *)accessibilityLabel { return NSLocalizedString(@"chatset.tint.picker", nil); }

- (NSString *)accessibilityValue {
    return [NSString stringWithFormat:@"%.0f°, %.0f%%", _hue, _saturation * 100];
}

/* voice over steps the hue, which is the axis a color is mostly named by */
- (void)accessibilityIncrement {
    self.hue = fmodf(_hue + 10, 360);
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)accessibilityDecrement {
    self.hue = fmodf(_hue + 350, 360);
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

@end
