#import <UIKit/UIKit.h>
#import "exteria_media_cache.h"
#import "exteria_reaction_artwork.h"

/* the burst the server draws when a reaction is put on a message: the reaction itself and the large effect around it, or the short burst of a double tap */
@interface ExteriaReactionEffect : NSObject
/* plays over host, centered on point (in the coordinates of host) and kept inside its bounds; one effect plays at a time, a new one ends the one before.
   longBurst: activate and effect, as the picker does; otherwise only around, when the reaction has it. nothing plays with reduced motion */
+ (void)playArtwork:(ExteriaReactionArtwork *)artwork longBurst:(BOOL)longBurst around:(CGPoint)point inView:(UIView *)host media:(ExteriaMediaCache *)media;
+ (void)dismiss;
@end
