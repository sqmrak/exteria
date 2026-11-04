#import <UIKit/UIKit.h>

/* the field for the words under a picture or a file: a text view whose return key makes a new line, with a hint that shows while it is empty. the field of one line
   (UITextField) could not take a line break */
@interface ExteriaCaptionView : UITextView {
    UILabel *_hint;
}
@property (nonatomic, copy) NSString *placeholder;
/* the height of the words at a width, with the room the view keeps around them; at least one line */
- (CGFloat)contentHeightForWidth:(CGFloat)width;
@end
