#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"

@class ExteriaStickerPicker;

@protocol ExteriaStickerPickerDelegate <NSObject>
- (void)stickerPicker:(ExteriaStickerPicker *)picker didPickSticker:(ExteriaSticker *)sticker;
@optional
/* the tile "Create" among the recent stickers: the screen starts the making of a sticker */
- (void)stickerPickerDidTapCreate:(ExteriaStickerPicker *)picker;
@end

/* the stickers of the account as one list of sections them */
@interface ExteriaStickerPicker : UIView <UITableViewDataSource, UITableViewDelegate> {
    id<ExteriaStickerPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<ExteriaStickerPickerDelegate> delegate;
/* the height at the bottom that the floating tabs of the panel cover, which the list leaves free to scroll past */
@property (nonatomic, assign) CGFloat bottomInset;

- (id)initWithMedia:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library;
/* called each time the picker comes on screen, to fetch what is missing and to refresh the favorites and the recent ones */
- (void)prepare;

@end
