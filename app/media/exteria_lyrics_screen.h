#import <UIKit/UIKit.h>

/* the lyrics of the song that plays, over nearly the whole screen: a small player on top, as the strip of the main screen is, and the lines under it. it comes up from the bottom edge
   with the dim fading in, and goes down the same way. the modern look is a sheet like the one of the browser, with a handle, round top corners and a pull down that closes it, on a ground of
   the cover's color, and the line that is sung springs in; the skeuomorphic one has a dark ground of the cover's hue and white lines that only brighten. it looks the lyrics up itself,
   says so while it waits or when there are none, and follows the song: when the next one starts, its lyrics are looked up and shown */
@interface ExteriaLyricsScreen : UIView
/* does nothing while no song is the current one */
+ (void)present;
@end
