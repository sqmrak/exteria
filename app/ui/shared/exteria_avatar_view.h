#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_photo.h"
#import "exteria_symbol.h"

/* the rounded square that stands in for a profile photo: a gradient picked by a seed, with the initials
   or one symbol on it */
@interface ExteriaAvatarView : UIView

@property (nonatomic, copy) NSString *initials;
/* a symbol replaces the initials when it is set */
@property (nonatomic, assign) BOOL showsSymbol;
@property (nonatomic, assign) ExteriaSymbol symbol;
/* the accent gradient instead of one of the seeded colors; it is made of the accent color of the app, so it follows a change of it */
@property (nonatomic, assign) BOOL accent;
@property (nonatomic, assign) NSUInteger seed;
/* the classic style draws it as a circle instead of the rounded square; the other styles draw every avatar in the shape chosen in the customization, circular or not */
@property (nonatomic, assign) BOOL circular;
/* a transparent photo shows the view behind it */
@property (nonatomic, assign) BOOL transparentPhoto;
/* the ghost stands in for the initials of an account that is gone; a photo or a symbol still wins */
@property (nonatomic, assign) BOOL deleted;

/* shows the photo once the cache has it, the colors and initials until then; a nil photo clears it */
- (void)setPhoto:(ExteriaPhoto *)photo cache:(ExteriaAvatarCache *)cache;

/* shows a decoded picture at once, without a cache; a nil picture brings the colors back */
- (void)showImage:(UIImage *)image;

@end

@interface ExteriaOnlineDotView : UIView
/* the dot of a row that is chosen is white, as the green one would vanish on the colored plate of the row */
@property (nonatomic, assign) BOOL inverted;
@end
