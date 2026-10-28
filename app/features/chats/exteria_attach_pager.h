#import <UIKit/UIKit.h>

/* one photo or movie of a selection that is waiting for its send; exactly one of image and movie is set, and poster is the first frame of a movie */
@interface ExteriaAttachItem : NSObject {
@public
    UIImage *image;
    NSURL *movie;
    UIImage *poster;
}
@end

/* the screen that holds a selection of two or more pictures before they go out: the person pages between them, edits a photo, drops one, and writes a
   caption for the whole album */
@interface ExteriaAttachPager : UIViewController
/* send gets the items that are left, in order, and the caption, after the screen has gone; cancel runs after it has gone with nothing to send */
- (id)initWithItems:(NSArray *)items caption:(NSString *)caption send:(void (^)(NSArray *items, NSString *caption))send cancel:(void (^)(void))cancel;
@end
