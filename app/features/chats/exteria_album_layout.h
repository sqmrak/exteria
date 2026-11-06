#import <UIKit/UIKit.h>

/* the rects of a collage of two to ten pictures in a width, from the top left, and the height they take; ratios are width over height as NSNumbers.
   the chat bubble and the preview of a selection about to be sent lay a collage out with this one rule, so the preview shows what the chat will */
CGFloat ExteriaAlbumLayout(NSArray *ratios, CGFloat width, NSMutableArray *frames);
