#import <UIKit/UIKit.h>

/* a square of colors with a hex field under it for typing a color: the hue runs left to right and the saturation bottom to top, over the value of the light accent of the palette. UIControlEventValueChanged
   comes while the finger moves, UIControlEventTouchUpInside once when it lets go (or the touch is taken away) or the hex field is done, which is when the app should take the color. The hex color gives its hue and its saturation, the value stays that of the palette */
@interface ExteriaTintPicker : UIControl <UITextFieldDelegate> {
    float _hue;
    float _saturation;
    UIView *_thumb;
    UIView *_swatch;
    UITextField *_field;
    CGSize _renderedSize;
}
/* degrees from 0 to 360 and from 0 to 1; setting them moves the thumb and sends nothing */
@property (nonatomic, assign) float hue;
@property (nonatomic, assign) float saturation;
+ (CGFloat)height;
@end
