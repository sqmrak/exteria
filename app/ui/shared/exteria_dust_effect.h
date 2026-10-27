#import <UIKit/UIKit.h>

/* the dust-effect deletion (ThanosEffect): a view that is going away breaks into small squares that sweep off to
   the right and fade, left to right */

/* a picture of the view as it looks now, or nil for a view without size */
UIImage *ExteriaDustSnapshot(UIView *view);

/* plays the dust of the picture over host at frame, which is in the coordinates of host */
void ExteriaDustDisperse(UIImage *picture, CGRect frame, UIView *host);
