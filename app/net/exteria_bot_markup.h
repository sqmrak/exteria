#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#include "exteria_markup.h"

/* one button of a bot's buttons or keyboard; built off the main thread */
@interface ExteriaMarkupButton : NSObject {
    exteria_markup_button _row;
    NSString *_text;
    NSString *_argument;
    NSData *_data;
}
@property (nonatomic, readonly) exteria_markup_button row;
@property (nonatomic, readonly) exteria_button_kind kind;
@property (nonatomic, readonly) exteria_button_style style;
@property (nonatomic, readonly, copy) NSString *text;
/* the address, the inline query or the text to copy, empty for a button without one */
@property (nonatomic, readonly, copy) NSString *argument;
/* the payload of a callback button */
@property (nonatomic, readonly, retain) NSData *data;
/* a button the person can press; a disabled one is only drawn */
@property (nonatomic, readonly) BOOL enabled;
@end

/* the buttons under a message, or the keyboard a bot put in place of the system one */
@interface ExteriaMarkup : NSObject {
    exteria_markup_kind _kind;
    BOOL _resize;
    BOOL _singleUse;
    BOOL _persistent;
    BOOL _selective;
    NSString *_placeholder;
    NSArray *_rows;
    NSData *_rowSizes;
    NSUInteger _buttonCount;
}
/* the ReplyMarkup of a message; nil when it holds nothing the screens show (no markup, an unknown constructor, empty rows) */
+ (ExteriaMarkup *)markupWithValue:(const exteria_tl_value *)value;
@property (nonatomic, readonly) exteria_markup_kind kind;
@property (nonatomic, readonly) BOOL resize;
@property (nonatomic, readonly) BOOL singleUse;
@property (nonatomic, readonly) BOOL persistent;
@property (nonatomic, readonly) BOOL selective;
@property (nonatomic, readonly, copy) NSString *placeholder;
/* arrays of ExteriaMarkupButton, one per row */
@property (nonatomic, readonly, retain) NSArray *rows;
@property (nonatomic, readonly) NSUInteger buttonCount;

/* the frames of the buttons in reading order for a width, in an array of buttonCount CGRect values; height is the whole stack.
   nil when the width is too small for the widest row */
- (NSData *)framesForWidth:(CGFloat)width rowHeight:(CGFloat)rowHeight gap:(CGFloat)gap height:(CGFloat *)height;
/* two markups that draw the same */
- (BOOL)isEqualMarkup:(ExteriaMarkup *)other;
@end
