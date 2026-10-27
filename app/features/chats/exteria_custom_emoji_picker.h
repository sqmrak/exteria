#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_symbol.h"

@class ExteriaCustomEmojiPicker;

@protocol ExteriaCustomEmojiPickerDelegate <NSObject>
- (void)customEmojiPicker:(ExteriaCustomEmojiPicker *)picker didPickEmoji:(ExteriaCustomEmojiDocument *)emoji;
@optional
/* the tab put first by leadingSymbol was chosen; the picker shows no grid then, and the owner shows its own content under the strip */
- (void)customEmojiPickerDidSelectLeading:(ExteriaCustomEmojiPicker *)picker;
/* a set was chosen, or the first load of the sets finished: the owner takes its own content away */
- (void)customEmojiPickerDidSelectSet:(ExteriaCustomEmojiPicker *)picker;
@end

/* the custom emoji sets of a Premium account as a strip of set names over a grid of the emoji of the chosen one */
@interface ExteriaCustomEmojiPicker : UIView {
    id<ExteriaCustomEmojiPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<ExteriaCustomEmojiPickerDelegate> delegate;
/* a glyph tab before the sets, for an owner that has content of its own to offer first; it is the chosen tab until a set is tapped */
@property (nonatomic, assign) BOOL hasLeading;
@property (nonatomic, assign) ExteriaSymbol leadingSymbol;
@property (nonatomic, copy) NSString *leadingLabel;
/* a set of the strip draws a lock, for an account that may look at custom emoji and not use them */
@property (nonatomic, assign) BOOL showsLocks;
/* the height of the strip, which an owner with a leading tab starts its own content under */
+ (CGFloat)stripHeight;

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media;
/* called each time the picker comes on screen, to fetch what is missing */
- (void)prepare;

@end
