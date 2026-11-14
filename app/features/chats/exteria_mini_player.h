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
/* the modern card is a rounded rectangle; as a pill it is rounded to half its height and floats with room around it, so inside a chat it does not hang from the header or the
   pinned message under it */
@property (nonatomic, assign) BOOL pill;
/* the strip inside another screen of the player (the lyrics) does not open the sheet of the player on a tap and does not end the music with its last key: when these are set the
   tap on the name and the last key call them instead */
@property (nonatomic, copy) void (^openHandler)(void);
@property (nonatomic, copy) void (^closeHandler)(void);

/* the lyrics screen makes the card a Material You scheme of a color of the cover: the play key, the tile and the keys take tones of it instead of the accent, the surface is the
   given one, and the progress is a wave. nil tone returns the card to the accent and the surface of the theme. animated crossfades; the classic strip ignores it */
- (void)setTone:(UIColor *)tone surface:(UIColor *)surface animated:(BOOL)animated;

@end
