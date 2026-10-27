#import <UIKit/UIKit.h>

@interface ExteriaPhotoEditor : UIViewController
- (id)initWithImage:(UIImage *)image completion:(void (^)(UIImage *image))completion;
@end
