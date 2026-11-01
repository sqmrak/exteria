#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_message.h"

/* the card of the song a profile shows: a rounded cover, the title over the artist, on a plate of the color of the cover; a tap on it is the owner's
   to handle, and it hides itself when it has nothing to show, so ask hasContent before laying it out */
@interface ExteriaMusicPill : UIControl

/* the song the profile shows first, nil when it has none */
@property (nonatomic, retain) ExteriaMedia *savedTrack;
/* whether the pill has anything to show: a saved song or a song that plays */
@property (nonatomic, readonly) BOOL hasContent;
/* runs when the pill changes between having content and not, so the owner can lay the head out again */
@property (nonatomic, copy) void (^contentHandler)(void);
+ (CGFloat)height;
/* where the cover comes from; without it the card shows the note in place of the cover */
@property (nonatomic, retain) ExteriaMediaCache *media;
/* the emoji of the profile's Premium pattern and its color: a few of them run onto the right end of the card, fading out toward the left */
@property (nonatomic, retain) UIImage *patternImage;
@property (nonatomic, retain) UIColor *patternColor;
/* the card takes the whole row it is given, so this is maxWidth */
- (CGFloat)widthWithin:(CGFloat)maxWidth;

@end
