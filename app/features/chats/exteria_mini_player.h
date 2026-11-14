#import <UIKit/UIKit.h>

/* the strip over a chat or the list of chats while a song is the current one; the song and who sings it, the
   buttons for the song before, play or pause, and the song after, and the one that ends the music */
@interface ExteriaMiniPlayer : UIView

+ (CGFloat)height;
/* the height of a strip that stands as a pill (see pill): the card and the room above and below it */
+ (CGFloat)heightForPill:(BOOL)pill;
/* whether a song or a video message holds the output, which is when any strip of the app has a height */
+ (BOOL)isActive;
/* whether a song is the current one, which is what gives the strip its height */
@property (nonatomic, readonly) BOOL showing;
@property (nonatomic, copy) void (^changeHandler)(void);
/* the strip wears the color of the bars of a chat (its header and the pinned message under it) and not the color of the cards of the chat list, so the stack of them reads as one */
@property (nonatomic, assign) BOOL wearsBarColor;
/* the modern card stands on the tab bar and not under a header: its upper corners are round and the gutter is above it */
@property (nonatomic, assign) BOOL standsOnBar;

@end
