#import <Foundation/Foundation.h>

#include "exteria_photos.h"

/* where a profile photo lives; the file itself comes from ExteriaSession downloadFile:completion */
@interface ExteriaPhoto : NSObject {
    exteria_photo_ref _ref;
    NSString *_key;
}

/* nil when the ref carries no photo */
+ (ExteriaPhoto *)photoWithRef:(const exteria_photo_ref *)ref;

@property (nonatomic, readonly) exteria_photo_ref ref;
/* one photo, one key: the id alone, because a photo id is unique across telegram */
@property (nonatomic, readonly, copy) NSString *key;

@end
