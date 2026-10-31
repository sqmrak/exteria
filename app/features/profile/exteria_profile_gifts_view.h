#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"

/* the pinned unique gifts of a profile standing round the photo, each on the glow of its own backdrop, three on a side */
@interface ExteriaProfileGiftsView : UIView

+ (NSUInteger)capacity;
- (id)initWithMedia:(ExteriaMediaCache *)media;
/* ExteriaSavedGift items in profile order; only the pinned unique ones are shown, up to capacity */
- (void)setGifts:(NSArray *)gifts;
/* the center of the photo in the coordinates of this view */
@property (nonatomic, assign) CGPoint focus;

@end
