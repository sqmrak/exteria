#import <UIKit/UIKit.h>

#define EXTERIA_BACKDROP_BLUR_BAND 110.0
#define EXTERIA_BACKDROP_BLEED 18.0

/* the colored ground of a profile header: a radial blend from the middle color, at the focus, out to the edge color at the borders */
@interface ExteriaProfileBackdropView : UIView
@property (nonatomic, retain) UIColor *centerColor;
@property (nonatomic, retain) UIColor *edgeColor;
/* where the blend is brightest, in the coordinates of the view; the middle of the photo */
@property (nonatomic, assign) CGPoint focus;
/* the emoji that tiles the ground, as a picture whose shape is used and whose colors are not: it is drawn in patternColor, in rings round the focus. Radius is the
   size of the photo's circle that the rings stand out from */
@property (nonatomic, retain) UIImage *patternImage;
@property (nonatomic, retain) UIColor *patternColor;
@property (nonatomic, assign) CGFloat photoRadius;
/* the lower edge of the ground melts: its last EXTERIA_BACKDROP_BLUR_BAND points are a blurred copy of itself that grows stronger towards the edge, and the ground goes on for
   EXTERIA_BACKDROP_BLEED points past the edge, fading out over the page, so the header does not end in a hard line. The owner makes the view that much taller than the ground
   and puts whatever stands under the ground (the music pill) over this strip, which it does not blur. Off, the view is drawn as it was, down to its own bottom edge */
@property (nonatomic, assign) BOOL softBottom;
@end
