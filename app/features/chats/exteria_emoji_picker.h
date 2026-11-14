#import <UIKit/UIKit.h>

@class ExteriaEmojiPicker;

@protocol ExteriaEmojiPickerDelegate <NSObject>
/* entry is an index into the emoji table; its string is what goes into the message */
- (void)emojiPicker:(ExteriaEmojiPicker *)picker didPickEntry:(size_t)entry;
@end

/* the emoji grid: the ones used lately, then the nine groups, with a strip that jumps between them. the magnifier at the head of the strip asks for a word, and the grid shows the
   emoji that the keywords of the server name for it */
@class ExteriaSession;

@interface ExteriaEmojiPicker : UIView <UITableViewDataSource, UITableViewDelegate> {
    id<ExteriaEmojiPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<ExteriaEmojiPickerDelegate> delegate;
/* the account the keywords of the search are asked from; without one the search uses what an earlier launch kept */
@property (nonatomic, assign) ExteriaSession *session;
@end
