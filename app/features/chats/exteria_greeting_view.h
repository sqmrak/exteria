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
- (CGSize)cardSizeForWidth:(CGFloat)width;

@end
