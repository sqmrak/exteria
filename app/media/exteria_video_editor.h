#import <UIKit/UIKit.h>

@interface ExteriaVideoEditor : UIViewController
- (id)initWithURL:(NSURL *)url start:(double)start end:(double)end muted:(BOOL)muted turns:(NSInteger)turns mirrored:(BOOL)mirrored crop:(CGRect)crop
      completion:(void (^)(double start, double end, BOOL muted, NSInteger turns, BOOL mirrored, CGRect crop))completion;
@end
