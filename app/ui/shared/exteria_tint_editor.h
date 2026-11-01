#import <UIKit/UIKit.h>

#import "exteria_tint_picker.h"

/* the color editor of the modern look, in the Material 3 Expressive manner: a card in the color that carries the hex digits and a scalloped shape that turns with
   the hue, two slider tracks (hue on a rainbow, saturation from grey to the color), and a row of ready colors whose chosen one becomes a rounded square. Same events
   and values as the classic picker; main thread only */
@interface ExteriaTintEditor : UIControl <ExteriaTintControl, UITextFieldDelegate>
@end
