#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_photo.h"

/* the round pictures of the people in a list of the settings */
@interface ExteriaPeopleAvatars : NSObject

- (id)initWithCache:(ExteriaAvatarCache *)cache changed:(void (^)(void))changed;
/* the key is whatever names the person on this page (kind and id); the same key keeps the same image */
- (UIImage *)imageForKey:(NSString *)key initials:(NSString *)initials seed:(NSUInteger)seed deleted:(BOOL)deleted photo:(ExteriaPhoto *)photo;
/* a picture the phone kept of a person whose photo cannot be asked for, such as an account that has no connection; it is used until a photo of the cache comes */
- (void)useStoredPhoto:(UIImage *)photo forKey:(NSString *)key seed:(NSUInteger)seed;
/* the page is going away: answers that come later are dropped */
- (void)invalidate;

@end
