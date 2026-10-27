#import <UIKit/UIKit.h>

/* the colors of the names of people in group chats, which each person may choose; 0 to 6 are the seven colors
   every client has built in, and the ones above come from the server and are kept between runs, so a chat can draw
   them without asking */

/* the id of the color of a person who chose none, which the server leaves to the id of the person */
NSInteger ExteriaDefaultNameColorId(long long userId);
/* the color of the name for an id, on the light or the dark theme; an id the app has no color for (a server color
   not loaded yet) gives the default of the person */
UIColor *ExteriaNameColor(NSInteger colorId, long long userId, BOOL dark);

/* the colors of the server's list (id, light and dark as 0xRRGGBB numbers, hidden), as NSDictionary items with the keys id, light, dark and hidden, in
   the order of the server; empty until the list has been loaded once */
NSArray *ExteriaServerNameColors(void);
void ExteriaStoreServerNameColors(NSArray *colors);
/* the seven built-in ids, for the screen that lists them */
NSUInteger ExteriaBuiltInNameColorCount(void);
