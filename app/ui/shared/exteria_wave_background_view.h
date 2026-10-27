#import <UIKit/UIKit.h>

/* a pale lilac gradient with a purple wave in two opposite corners; when animated, the waves drift and
   their edges ripple slowly */
@interface ExteriaWaveBackgroundView : UIView

@property (nonatomic, assign) BOOL animated;
/* the signed in screens: a near white gradient and only the top corner wave, in a paler lilac */
@property (nonatomic, assign) BOOL plain;
/* a list over the waves is moving: their animation holds still and the layers are drawn once into a texture, since
   an animated path mask is drawn again by the render server on every frame */
@property (nonatomic, assign) BOOL scrolling;

/* a wave is a gradient layer seen through a shape layer, and CALayer renderInContext; does not draw a layer that
   has a mask, so a picture of the window took the waves out of the screen or showed them as plain rectangles */
- (void)beginSnapshot;
- (void)endSnapshot;

@end
