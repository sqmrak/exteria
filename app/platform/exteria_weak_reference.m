#import "exteria_weak_reference.h"

@implementation ExteriaWeakReference

@synthesize target = _target;

+ (ExteriaWeakReference *)referenceTo:(id)target {
    ExteriaWeakReference *reference = [[[ExteriaWeakReference alloc] init] autorelease];
    reference->_target = target;
    return reference;
}

- (void)clear {
    _target = nil;
}

@end
