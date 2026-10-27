#import <UIKit/UIKit.h>

/* UIKit keeps the Unicode text, selection and editing; the app supplies emoji pictures */
@interface ExteriaEmojiTextView : UITextView
@property (nonatomic, retain) UIColor *emojiBackgroundColor;
- (void)refreshEmoji;
/* the "Format" item this view adds to the system menu of a selection; nil takes the item away */
@property (nonatomic, copy) void (^formatHandler)(void);
@end
