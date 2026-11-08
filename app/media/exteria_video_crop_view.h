#import <UIKit/UIKit.h>

/* the frame of the crop over a picture: the part outside it is dimmed, and its corners and sides are dragged to give it any shape, or, with a ratio set, only the corners, which keep the
   shape. the view stands exactly over the picture, and the frame is a rectangle of fractions of it (x, y, width, height) */
@interface ExteriaVideoCropView : UIView

@property (nonatomic, assign) CGRect crop;
/* the shape the frame keeps, as the width over the height of the frame in the fractions of the picture; zero lets it take any shape */
@property (nonatomic, assign) CGFloat ratio;
/* the size of the picture in pixels, which sets how small the frame may become: the encoder takes nothing under a few pixels */
@property (nonatomic, assign) CGSize pictureSize;
/* runs while the frame is dragged and when it is let go */
@property (nonatomic, copy) void (^changed)(CGRect crop);

/* the frame a centered crop of the shape width over height has in a picture of this size, as fractions of it; the whole picture for a ratio of zero */
+ (CGRect)centeredCropOfRatio:(double)ratio inPicture:(CGSize)picture;

@end
