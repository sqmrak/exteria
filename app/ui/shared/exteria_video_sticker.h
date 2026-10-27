#import "exteria_lottie.h"

/* the same frame interface as tgs, with a bounded 15 fps vp9 decode */
@interface ExteriaVideoSticker : NSObject <ExteriaFrameAnimation>
+ (ExteriaVideoSticker *)animationWithPackedData:(NSData *)packed key:(NSString *)key;
@end
