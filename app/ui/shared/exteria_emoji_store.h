#import <UIKit/UIKit.h>

#include "exteria_emoji.h"

/* whether the app has a picture for the emoji, which the layout needs to reserve room for it */
BOOL ExteriaEmojiHasPicture(size_t entry);

/* the decoded picture when it is in memory */
UIImage *ExteriaEmojiImage(size_t entry);

/* the picture, decoded here when it is not in memory; for rendering into a bitmap that is kept, where a missing
   picture cannot be filled in later */
UIImage *ExteriaEmojiImageNow(size_t entry);

/* a system emoji rendered at chat size, or nil when this ios cannot draw the complete sequence */
void ExteriaLargeEmojiImage(size_t entry, void (^completion)(UIImage *image));

/* how many times a picture was asked for and not yet in memory; a view reads it before and after drawing, and when
   it changed calls ExteriaEmojiRedrawWhenLoaded */
NSUInteger ExteriaEmojiMissCount(void);

/* sets the view to redraw once the pictures that are being decoded are in memory; asking twice before the redraw
   is the same as once */
void ExteriaEmojiRedrawWhenLoaded(UIView *view);

/* the emoji as a string, to type it into a message */
NSString *ExteriaEmojiString(size_t entry);

/* draws the emoji in rect when its picture is in memory, and leaves the rect empty while it is being decoded */
void ExteriaDrawEmoji(size_t entry, CGRect rect);
