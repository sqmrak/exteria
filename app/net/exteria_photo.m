#import "exteria_photo.h"

@implementation ExteriaPhoto

@synthesize ref = _ref;
@synthesize key = _key;

+ (ExteriaPhoto *)photoWithRef:(const exteria_photo_ref *)ref {
    if (!ref || ref->photo_id <= 0) return nil;
    ExteriaPhoto *photo = [[[ExteriaPhoto alloc] init] autorelease];
    photo->_ref = *ref;
    photo->_key = [[NSString stringWithFormat:@"%lld", (long long)ref->photo_id] copy];
    return photo;
}

- (void)dealloc {
    [_key release];
    [super dealloc];
}

@end
