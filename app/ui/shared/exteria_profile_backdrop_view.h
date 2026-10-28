#import <UIKit/UIKit.h>

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
@end
