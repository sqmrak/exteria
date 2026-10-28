#import <UIKit/UIKit.h>

/* the sparks of a one-time photo, video or message burning away: a burst of small glowing dots over a rectangle, which fade and fall as they die */
@interface ExteriaBurnEffect : NSObject
/* rect is in the coordinates of view; the layer leaves by itself when the sparks are gone, and completion runs then, on the main thread */
+ (void)burnRect:(CGRect)rect inView:(UIView *)view duration:(NSTimeInterval)duration completion:(void (^)(void))completion;
@end
