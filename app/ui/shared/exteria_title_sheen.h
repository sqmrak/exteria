#import <UIKit/UIKit.h>

/* a band of the accent that crosses the letters of a big title now and then, over the black of the oled theme. it is a layer above the title, cut to the shape of its
   letters, and the crossing is one animation of the render server, so no frame is drawn by the app. it runs only under the oled palette, with reduce motion off, the
   background animations on and a device that is not of the low class; everywhere else the view is hidden and holds nothing */
@interface ExteriaTitleSheen : UIView

/* the owner turns it off while the title stands on a color of its own, such as a profile with a backdrop */
@property (nonatomic, assign) BOOL enabled;

/* the letters of source are copied as the cut; a copy is made again only when the size changed or invalidateMask was called */
- (void)refreshFromView:(UIView *)source;
- (void)invalidateMask;

@end
