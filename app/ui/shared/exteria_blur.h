#import <UIKit/UIKit.h>

/* the screen behind a popup, blurred, taken from host before the popup joins it; the system blur where it exists (ios 8 and later, found by class
   so the older slices never link it), and elsewhere a picture of the host drawn small and stretched back with smoothing, a blur the old systems
   can do without a filter. nil when the picture could not be made */
UIView *ExteriaBlurBackdrop(UIView *host, CGRect bounds);

/* the image blurred by a box filter of radius r run passes times; the image itself when the memory for the work is not there */
UIImage *ExteriaBoxBlurredImage(UIImage *image, int r, int passes);
