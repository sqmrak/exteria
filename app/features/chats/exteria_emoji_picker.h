#import <UIKit/UIKit.h>

@class ExteriaEmojiPicker;

@protocol ExteriaEmojiPickerDelegate <NSObject>
/* entry is an index into the emoji table; its string is what goes into the message */
- (void)emojiPicker:(ExteriaEmojiPicker *)picker didPickEntry:(size_t)entry;
@end

/* the emoji grid: the ones used lately, then the nine groups, with a strip that jumps between them */
@interface ExteriaEmojiPicker : UIView <UITableViewDataSource, UITableViewDelegate> {
    id<ExteriaEmojiPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<ExteriaEmojiPickerDelegate> delegate;
@end
