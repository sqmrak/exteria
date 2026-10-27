#import <Foundation/Foundation.h>
#include "exteria_status.h"

typedef enum {
    ExteriaUpdaterIdle,
    ExteriaUpdaterWorking,
    ExteriaUpdaterDone,
    ExteriaUpdaterFailed,
    ExteriaUpdaterCancelled
} ExteriaUpdaterState;

/* downloads the ipa of a release, checks it against the digest published next to it, and puts its files into the bundle of the running
   app (core/base/exteria_update.c). One run per object; the object reports on the main thread and keeps working with no one watching until
   cancel or the end */
@interface ExteriaUpdater : NSObject

/* the roots GitHub's api, its pages and its download hosts chain to: the shared pem files of the bundle, nil when one is missing */
+ (NSData *)trustedRoots;
/* NO, with the reason in the text of the notice, when this process cannot write the app folder (an app installed by root) */
+ (BOOL)canInstallInPlace;

- (id)initWithIpaURL:(NSString *)ipaURL digestURL:(NSString *)digestURL size:(uint64_t)size;

/* called on the main thread after every change; set it to nil before the object that owns the block goes away */
@property (nonatomic, copy) void (^onChange)(void);
@property (nonatomic, readonly) ExteriaUpdaterState state;
/* 0 to 1 over the whole run, download first and install after it */
@property (nonatomic, readonly) float fraction;
@property (nonatomic, readonly) uint64_t downloaded;
@property (nonatomic, readonly) uint64_t expected;
@property (nonatomic, readonly) BOOL installing;
@property (nonatomic, readonly) exteria_status failure;

- (void)start;
/* stops a download or a staging; an install that has begun moving files is finished first */
- (void)cancel;

@end
