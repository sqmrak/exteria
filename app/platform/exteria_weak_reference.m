#import "exteria_weak_reference.h"

#import <objc/runtime.h>

/* hangs on the target and is freed with it, which clears the reference: a block that outlives its screen then finds nil, where a pointer nobody cleared (a reference made in a method
   other than init, a callback handed to a strip that lives on) pointed at a freed screen and crashed on the first message it was sent */
@interface ExteriaWeakSentinel : NSObject {
    ExteriaWeakReference *_reference;
}
@property (nonatomic, readonly) ExteriaWeakReference *reference;
- (id)initWithReference:(ExteriaWeakReference *)reference;
@end

@implementation ExteriaWeakSentinel

@synthesize reference = _reference;

- (id)initWithReference:(ExteriaWeakReference *)reference {
    self = [super init];
    if (self) _reference = [reference retain];
    return self;
}

- (void)dealloc {
    [_reference clear];
    [_reference release];
    [super dealloc];
}

@end

static char ExteriaWeakSentinelKey;

@implementation ExteriaWeakReference

@synthesize target = _target;

/* one reference serves every holder of the same target: they are all cleared together when it goes, and nothing grows with each call */
+ (ExteriaWeakReference *)referenceTo:(id)target {
    if (!target) return [[[ExteriaWeakReference alloc] init] autorelease];
    @synchronized ([ExteriaWeakReference class]) {
        ExteriaWeakSentinel *sentinel = objc_getAssociatedObject(target, &ExteriaWeakSentinelKey);
        if (sentinel) return sentinel.reference;
        ExteriaWeakReference *reference = [[[ExteriaWeakReference alloc] init] autorelease];
        reference->_target = target;
        sentinel = [[[ExteriaWeakSentinel alloc] initWithReference:reference] autorelease];
        objc_setAssociatedObject(target, &ExteriaWeakSentinelKey, sentinel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return reference;
    }
}

- (void)clear {
    _target = nil;
}

@end
