#import <UIKit/UIKit.h>

/* what the page of the wallpapers needs of a color control, so the classic and the modern one stand in the same row: UIControlEventValueChanged comes while the color
   moves, UIControlEventTouchUpInside once when the person lets go (or types a hex color and is done), which is when the app should take it. The hue is in degrees
   from 0 to 360 and the saturation from 0 to 1; setting them moves the control and sends nothing */
@protocol ExteriaTintControl <NSObject>
@property (nonatomic, assign) float hue;
@property (nonatomic, assign) float saturation;
@property (nonatomic, readonly) CGFloat preferredHeight;
/* the part of the control the keyboard must not cover while the hex color is typed, in the coordinates of the control */
@property (nonatomic, readonly) CGRect editingRect;
@end

/* a hex color (three or six digits, no #) as the hue and the saturation it gives; the value stays that of the palette. A grey has no hue, so *hue is left as it was.
   NO when the text is no color */
BOOL ExteriaTintOfHex(NSString *text, float *hue, float *saturation);
/* whether text is a hex color on its way: no more than six digits of 0 to 9 and A to F */
BOOL ExteriaTintHexAllowed(NSString *text);
/* the six digits of the accent that a hue and a saturation make */
NSString *ExteriaHexOfTint(float hue, float saturation);

/* the classic picker: a square of colors (the hue runs left to right and the saturation bottom to top, over the value of the light accent of the palette) with a
   metal disc for a thumb and a metal swatch beside a hex field under it, the way the logo of the QR code is set in chrome */
@interface ExteriaTintPicker : UIControl <ExteriaTintControl, UITextFieldDelegate> {
    float _hue;
    float _saturation;
    UIImageView *_thumb;
    UIImageView *_swatch;
    UIView *_plate;
    UILabel *_hash;
    UITextField *_field;
    CGSize _renderedSize;
}
@end
