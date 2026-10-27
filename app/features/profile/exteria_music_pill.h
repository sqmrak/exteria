#import <UIKit/UIKit.h>

#import "exteria_message.h"

/* the line under the buttons of a profile that is about music; a tap on the text is the owner's to handle, and the
   pill hides itself when it has nothing to show, so ask visible before laying it out */
@interface ExteriaMusicPill : UIControl

/* the song the profile shows first, nil when it has none */
@property (nonatomic, retain) ExteriaMedia *savedTrack;
/* whether the pill has anything to show: a saved song or a song that plays */
@property (nonatomic, readonly) BOOL hasContent;
/* runs when the pill changes between having content and not, so the owner can lay the head out again */
@property (nonatomic, copy) void (^contentHandler)(void);
+ (CGFloat)height;

@end
