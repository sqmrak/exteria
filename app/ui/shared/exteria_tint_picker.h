#import <UIKit/UIKit.h>

/* a square of colors: the hue runs left to right and the saturation bottom to top, over the value of the light accent of the palette. UIControlEventValueChanged
   comes while the finger moves, UIControlEventTouchUpInside once when it lets go (or the touch is taken away), which is when the app should take the color */
@interface ExteriaTintPicker : UIControl {
    float _hue;
    float _saturation;
    UIView *_thumb;
    CGSize _renderedSize;
}
/* degrees from 0 to 360 and from 0 to 1; setting them moves the thumb and sends nothing */
@property (nonatomic, assign) float hue;
@property (nonatomic, assign) float saturation;
+ (CGFloat)height;
@end
