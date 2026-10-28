#import <UIKit/UIKit.h>

/* the colored ground of a profile header: a radial blend from the middle color, at the focus, out to the edge color at the borders */
@interface ExteriaProfileBackdropView : UIView
@property (nonatomic, retain) UIColor *centerColor;
@property (nonatomic, retain) UIColor *edgeColor;
/* where the blend is brightest, in the coordinates of the view; the middle of the photo */
@property (nonatomic, assign) CGPoint focus;
@end
