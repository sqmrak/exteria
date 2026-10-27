#import <Foundation/Foundation.h>

/* a non-retaining pointer for blocks that outlive a screen; zeroing weak references arrived with ios 5 for ARC
   code only, so a screen under manual counting hands its blocks one of these and clears it in dealloc */
@interface ExteriaWeakReference : NSObject {
    id _target;
}
+ (ExteriaWeakReference *)referenceTo:(id)target;
@property (nonatomic, readonly) id target;
- (void)clear;
@end
