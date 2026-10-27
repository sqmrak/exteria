#import <UIKit/UIKit.h>

#import "exteria_bot_markup.h"

/* the keyboard a bot puts in place of the system one: rows of keys that fill the width, scrolling when there are more rows than fit */
@interface ExteriaBotKeyboardView : UIView {
    ExteriaMarkup *_markup;
    UIScrollView *_scroll;
    NSMutableArray *_keys;
    void (^_pressHandler)(ExteriaMarkupButton *button);
}

@property (nonatomic, copy) void (^pressHandler)(ExteriaMarkupButton *button);
@property (nonatomic, readonly, retain) ExteriaMarkup *markup;

- (void)setMarkup:(ExteriaMarkup *)markup;
/* the height the keys want for a width, no taller than maxHeight; a keyboard that is not asked to resize fills maxHeight */
- (CGFloat)preferredHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight;

@end
