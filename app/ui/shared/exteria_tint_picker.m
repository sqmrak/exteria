#import "exteria_tint_picker.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_classic_chrome.h"
#import "exteria_theme.h"

#define PICKER_HEIGHT 256.0
#define HEX_STRIP 56.0
#define PICKER_INSET 16.0
#define THUMB_SIDE 36.0
#define SWATCH_SIDE 34.0
/* the square is drawn this coarse and the layer smooths it up; a pixel per point would be 60 thousand colors on every layout */
#define RENDER_WIDTH 120
#define RENDER_HEIGHT 60

@implementation ExteriaTintPicker

/* the color alone, as the face of a disc */
static UIImage *ExteriaSolidImage(UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 4), YES, 1);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 4, 4));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@synthesize hue = _hue;
@synthesize saturation = _saturation;
@synthesize brightness = _brightness;

- (CGFloat)preferredHeight { return PICKER_HEIGHT; }

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _brightness = 1;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    /* both discs are the chrome rim of the QR logo around the color, drawn again whenever the color moves */
    _thumb = [[UIImageView alloc] init];
    _thumb.userInteractionEnabled = NO;
    _thumb.layer.shadowColor = [UIColor blackColor].CGColor;
    _thumb.layer.shadowOpacity = 0.45;
    _thumb.layer.shadowRadius = 3;
    _thumb.layer.shadowOffset = CGSizeMake(0, 2);
    [self addSubview:_thumb];
    _swatch = [[UIImageView alloc] init];
    _swatch.userInteractionEnabled = NO;
    [self addSubview:_swatch];
    /* the plate holds the # and the digits as two neighbours on one line, so they share a center and stand side by side whatever the font */
    _plate = [[UIView alloc] init];
    _plate.backgroundColor = ExteriaColorField();
    _plate.layer.cornerRadius = 10;
    [self addSubview:_plate];
    _hash = [[UILabel alloc] init];
    _hash.text = @"#";
    _hash.font = ExteriaFontSemibold(17);
    _hash.textColor = ExteriaColorSecondary();
    _hash.backgroundColor = [UIColor clearColor];
    [_plate addSubview:_hash];
    _field = [[UITextField alloc] init];
    _field.delegate = self;
    _field.backgroundColor = [UIColor clearColor];
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _field.font = ExteriaFontSemibold(17);
    _field.textColor = ExteriaColorTitle();
    _field.textAlignment = (NSTextAlignment)ExteriaTextAlignmentLeft;
    _field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.keyboardType = UIKeyboardTypeASCIICapable;
    _field.returnKeyType = UIReturnKeyDone;
    _field.clearButtonMode = UITextFieldViewModeNever;
    _field.accessibilityLabel = NSLocalizedString(@"chatset.tint.hex", nil);
    [_field addTarget:self action:@selector(hexEdited) forControlEvents:UIControlEventEditingChanged];
    [_plate addSubview:_field];
    return self;
}

- (void)dealloc {
    _field.delegate = nil;
    [_thumb release];
    [_swatch release];
    [_field release];
    [_hash release];
    [_plate release];
    [super dealloc];
}

- (CGRect)squareRect {
    return CGRectMake(PICKER_INSET, 8, self.bounds.size.width - 2 * PICKER_INSET, self.bounds.size.height - 8 - HEX_STRIP - 4);
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
    _thumb.bounds = CGRectMake(0, 0, THUMB_SIDE, THUMB_SIDE);
    _thumb.center = CGPointMake(square.origin.x + square.size.width * _hue / 360.0, square.origin.y + square.size.height * (1 - _saturation));
    _thumb.image = ExteriaClassicMetalDisc(ExteriaSolidImage(ExteriaThemeCustomTintColor(_hue, _saturation, _brightness)), THUMB_SIDE);
    [self showHex];
}

/* the swatch and the plate stand in the middle of the strip under the square; inside the plate the # and the digits are measured and set next to each other */
- (void)layoutSubviews {
    [super layoutSubviews];
    [self renderSquare];
    [self placeThumb];
    static const CGFloat plateHeight = 36, gap = 2;
    CGFloat digits = 0;
    for (NSString *sample in [NSArray arrayWithObjects:@"000000", @"888888", @"FFFFFF", @"BBBBBB", nil]) {
        UILabel *probe = [[[UILabel alloc] init] autorelease];
        probe.font = _field.font;
        probe.text = sample;
        [probe sizeToFit];
        digits = MAX(digits, probe.frame.size.width);
    }
    [_hash sizeToFit];
    CGFloat hashWidth = _hash.frame.size.width, fieldWidth = ceil(digits) + 4;
    CGFloat plateWidth = 16 + hashWidth + gap + fieldWidth + 16;
    CGFloat group = SWATCH_SIDE + 12 + plateWidth;
    CGFloat left = floor((self.bounds.size.width - group) / 2), top = self.bounds.size.height - HEX_STRIP + (HEX_STRIP - plateHeight) / 2 - 4;
    _swatch.frame = CGRectMake(left, top + (plateHeight - SWATCH_SIDE) / 2, SWATCH_SIDE, SWATCH_SIDE);
    _plate.frame = CGRectMake(left + SWATCH_SIDE + 12, top, plateWidth, plateHeight);
    _hash.frame = CGRectMake(16, 0, hashWidth, plateHeight);
    _field.frame = CGRectMake(16 + hashWidth + gap, 0, fieldWidth, plateHeight);
}

NSString *ExteriaHexOfTint(float hue, float saturation, float brightness) {
    CGFloat red, green, blue;
    ExteriaHSVToRGB(hue, saturation, 0.745 * MIN(1, MAX(0, brightness)), &red, &green, &blue);
    return [NSString stringWithFormat:@"%02X%02X%02X", (unsigned)(red * 255 + 0.5), (unsigned)(green * 255 + 0.5), (unsigned)(blue * 255 + 0.5)];
}

/* three digits are the short form of six; anything else that is not six hex digits is no color */
BOOL ExteriaTintOfHex(NSString *text, float *hue, float *saturation, float *brightness) {
    if (text.length == 3) {
        unichar c[3];
        [text getCharacters:c range:NSMakeRange(0, 3)];
        text = [NSString stringWithFormat:@"%C%C%C%C%C%C", c[0], c[0], c[1], c[1], c[2], c[2]];
    }
    if (text.length != 6) return NO;
    unsigned rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    if (![scanner scanHexInt:&rgb] || ![scanner isAtEnd]) return NO;
    CGFloat h, s, v;
    ExteriaRGBToHSV(((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, &h, &s, &v);
    /* a grey has no hue of its own, so the hue stays where the person had it; so does a black */
    if (s > 0 && v > 0) *hue = (float)h;
    *saturation = (float)s;
    *brightness = (float)MIN(1, v / 0.745);
    return YES;
}

BOOL ExteriaTintHexAllowed(NSString *text) {
    if (text.length > 6) return NO;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
    return [text rangeOfCharacterFromSet:bad].location == NSNotFound;
}

- (CGRect)editingRect { return _plate.frame; }

- (void)showHex {
    _swatch.image = ExteriaClassicMetalDisc(ExteriaSolidImage(ExteriaThemeCustomTintColor(_hue, _saturation, _brightness)), SWATCH_SIDE);
    if (!_field.isFirstResponder) _field.text = ExteriaHexOfTint(_hue, _saturation, _brightness);
}

- (void)hexEdited {
    float hue = _hue, saturation = _saturation, brightness = _brightness;
    if (!ExteriaTintOfHex(_field.text, &hue, &saturation, &brightness) || _field.text.length != 6) return;
    _hue = hue;
    _saturation = saturation;
    _brightness = brightness;
    [self placeThumb];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    return ExteriaTintHexAllowed([field.text stringByReplacingCharactersInRange:range withString:[string uppercaseString]]);
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

/* the color is taken when the field is done; a short or broken entry goes back to the color shown by the square */
- (void)textFieldDidEndEditing:(UITextField *)field {
    float hue = _hue, saturation = _saturation, brightness = _brightness;
    BOOL valid = ExteriaTintOfHex(field.text, &hue, &saturation, &brightness);
    if (valid) {
        _hue = hue;
        _saturation = saturation;
        _brightness = brightness;
        [self placeThumb];
    }
    [self showHex];
    if (valid) [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)setHue:(float)hue {
    _hue = MIN(360, MAX(0, hue));
    [self placeThumb];
}

- (void)setSaturation:(float)saturation {
    _saturation = MIN(1, MAX(0, saturation));
    [self placeThumb];
}

- (void)setBrightness:(float)brightness {
    _brightness = MIN(1, MAX(0, brightness));
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
    CGPoint point = [touch locationInView:self];
    /* a touch beside the square is not a pick; it also closes the keyboard */
    if (!CGRectContainsPoint(CGRectInset([self squareRect], -THUMB_SIDE / 2, -THUMB_SIDE / 2), point)) {
        [_field resignFirstResponder];
        return NO;
    }
    [_field resignFirstResponder];
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
