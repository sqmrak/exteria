#import <UIKit/UIKit.h>

#import "exteria_bot.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

@class ExteriaGifPicker;

@protocol ExteriaGifPickerDelegate <NSObject>
/* an animation of the account's own list, or one the search found that Telegram already keeps */
- (void)gifPicker:(ExteriaGifPicker *)picker didPickGif:(ExteriaMedia *)gif;
/* a search result that is a link a bot hosts, which the bot sends in the person's name */
- (void)gifPicker:(ExteriaGifPicker *)picker didPickInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId;
@end

/* the animations of the account as a grid of pictures, with a search over them and the quick words the panel
   offers in its search bar */
@interface ExteriaGifPicker : UIView <UITableViewDataSource, UITableViewDelegate> {
    id<ExteriaGifPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<ExteriaGifPickerDelegate> delegate;
/* the chat the animation goes to, which the inline search is asked in */
@property (nonatomic, retain) ExteriaDialog *dialog;
@property (nonatomic, assign) CGFloat bottomInset;

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library;
/* called each time the picker comes on screen: the saved animations are asked for again */
- (void)prepare;

@end
