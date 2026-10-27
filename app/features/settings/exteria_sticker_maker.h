#import <UIKit/UIKit.h>

#import "exteria_session.h"

/* making a sticker of one's own, step by step: a picture from the library (cut to a square or kept whole), the
   emoji it stands for, then a new set or one made here before */
@interface ExteriaStickerMaker : NSObject

/* host presents the picker and the busy cover; done runs on the main thread with the public name of the set once the sticker is in it */
+ (void)startWithSession:(ExteriaSession *)session host:(UIViewController *)host done:(void (^)(NSString *shortName))done;

@end
