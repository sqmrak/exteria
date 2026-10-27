#import "exteria_community.h"

@implementation ExteriaCommunity

@synthesize title = _title;
@synthesize about = _about;
@synthesize collapsed = _collapsed;
@synthesize joined = _joined;
@synthesize viewable = _viewable;

- (id)initWithTitle:(NSString *)title about:(NSString *)about collapsed:(BOOL)collapsed joined:(NSArray *)joined viewable:(NSArray *)viewable {
    self = [super init];
    if (!self) return nil;
    _title = [title copy];
    _about = [about copy];
    _collapsed = collapsed;
    _joined = [joined retain];
    _viewable = [viewable retain];
    return self;
}

- (void)dealloc {
    [_title release];
    [_about release];
    [_joined release];
    [_viewable release];
    [super dealloc];
}

@end
