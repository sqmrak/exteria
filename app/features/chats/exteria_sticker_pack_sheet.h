#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_message.h"
#import "exteria_session.h"

/* the window a tap on a sticker of a chat opens, the one */
@interface ExteriaStickerPackSheet : UIView

/* the sticker that was tapped, which names the pack; nothing is shown when it names none */
+ (BOOL)presentInView:(UIView *)host forSticker:(ExteriaMedia *)sticker session:(ExteriaSession *)session media:(ExteriaMediaCache *)media
               sender:(void (^)(ExteriaMedia *sticker))sender;

@end
