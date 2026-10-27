#import "exteria_people_avatars.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_weak_reference.h"

#define SIDE 48.0

@interface ExteriaPeopleAvatars () {
    ExteriaAvatarCache *_cache;
    NSMutableDictionary *_images;
    NSMutableSet *_asked;
    ExteriaWeakReference *_weak;
    void (^_changed)(void);
}
@end

@implementation ExteriaPeopleAvatars

- (id)initWithCache:(ExteriaAvatarCache *)cache changed:(void (^)(void))changed {
    self = [super init];
    if (!self) return nil;
    _cache = [cache retain];
    _images = [[NSMutableDictionary alloc] init];
    _asked = [[NSMutableSet alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _changed = [changed copy];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_cache release];
    [_images release];
    [_asked release];
    [_changed release];
    [super dealloc];
}

- (void)invalidate {
    [_weak clear];
    [_changed release];
    _changed = nil;
}

/* the colors and initials of the avatar view, drawn once into a picture */
static UIImage *ExteriaPlaceholderImage(NSString *initials, NSUInteger seed, BOOL deleted) {
    ExteriaAvatarView *view = [[[ExteriaAvatarView alloc] initWithFrame:CGRectMake(0, 0, SIDE, SIDE)] autorelease];
    view.circular = YES;
    view.initials = initials;
    view.seed = seed;
    view.deleted = deleted;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(SIDE, SIDE), NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the avatar view owns the look of a photo with see-through parts: it stands on the gradient of the person, and a bare picture drawn into a clear
   circle shows the white of the table behind it */
static UIImage *ExteriaRoundImage(UIImage *photo, NSUInteger seed) {
    ExteriaAvatarView *view = [[[ExteriaAvatarView alloc] initWithFrame:CGRectMake(0, 0, SIDE, SIDE)] autorelease];
    view.circular = YES;
    view.seed = seed;
    [view showImage:photo];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(SIDE, SIDE), NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (UIImage *)imageForKey:(NSString *)key initials:(NSString *)initials seed:(NSUInteger)seed deleted:(BOOL)deleted photo:(ExteriaPhoto *)photo {
    UIImage *image = [_images objectForKey:key];
    if (!image) {
        image = ExteriaPlaceholderImage(initials, seed, deleted);
        [_images setObject:image forKey:key];
    }
    /* a synchronous cache hit can replace this image while the caller is still building rows */
    image = [[image retain] autorelease];
    if (photo && _cache && ![_asked containsObject:key]) {
        [_asked addObject:key];
        ExteriaWeakReference *weak = _weak;
        __block BOOL inCall = YES;
        [_cache loadImageForPhoto:photo completion:^(UIImage *loaded) {
            ExteriaPeopleAvatars *me = weak.target;
            if (!me || !loaded) return;
            [me->_images setObject:ExteriaRoundImage(loaded, seed) forKey:key];
            if (!inCall && me->_changed) me->_changed();
        }];
        inCall = NO;
        UIImage *current = [_images objectForKey:key];
        if (current) image = current;
    }
    return image;
}

@end
