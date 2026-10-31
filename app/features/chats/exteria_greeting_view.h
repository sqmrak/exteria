#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_message.h"

/* the card an empty chat with a person shows: a line that nothing is here yet, and one greeting sticker to send with a tap */
@interface ExteriaGreetingView : UIView

/* the sticker picked for this chat, sent when the card is tapped; nil until the server named some */
@property (nonatomic, readonly, retain) ExteriaSticker *sticker;
@property (nonatomic, copy) void (^onSend)(ExteriaSticker *sticker);

- (id)initWithMedia:(ExteriaMediaCache *)media;
/* picks one of the stickers at random and loads its picture */
- (void)showStickers:(NSArray *)stickers;
/* the card the other person wrote for every new chat: their title, their text and their sticker in place of the stock words; empty parts keep the stock ones;
   the note under the card says who set it */
- (void)showIntroTitle:(NSString *)title text:(NSString *)text sticker:(ExteriaSticker *)sticker author:(NSString *)author;
/* the card of the saved messages: what the storage keeps, a list on the left, and a sticker that is only looked at */
- (void)showSavedCard;
- (CGSize)cardSizeForWidth:(CGFloat)width;

@end
