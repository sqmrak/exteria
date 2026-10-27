#import <UIKit/UIKit.h>

/* the strip over a chat or the list of chats while a song is the current one; the song and who sings it, the
   buttons for the song before, play or pause, and the song after, and the one that ends the music */
@interface ExteriaMiniPlayer : UIView

+ (CGFloat)height;
/* whether a song is the current one, which is what gives the strip its height */
@property (nonatomic, readonly) BOOL showing;
@property (nonatomic, copy) void (^changeHandler)(void);

@end
