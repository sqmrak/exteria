#import <UIKit/UIKit.h>

@interface ExteriaVideoEditor : UIViewController
- (id)initWithURL:(NSURL *)url start:(double)start end:(double)end muted:(BOOL)muted turns:(NSInteger)turns mirrored:(BOOL)mirrored aspect:(unsigned)aspect
      completion:(void (^)(double start, double end, BOOL muted, NSInteger turns, BOOL mirrored, unsigned aspect))completion;
@end
