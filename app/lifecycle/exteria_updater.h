#import <Foundation/Foundation.h>
#include "exteria_status.h"

typedef enum {
    ExteriaUpdaterIdle,
    ExteriaUpdaterWorking,
    ExteriaUpdaterDone,
    ExteriaUpdaterFailed,
    ExteriaUpdaterCancelled,
    /* the checked ipa is served on the loopback address and the system was asked to install it; the system closes the app when it does */
    ExteriaUpdaterHandedOff
} ExteriaUpdaterState;

/* downloads the ipa of a release, checks it against the digest published next to it, and puts its files into the bundle of the running
   app (core/base/exteria_update.c). a bundle it cannot write goes to installd instead: the ipa and a manifest are served from 127.0.0.1
   (core/base/exteria_file_server.c) and itms-services opens the manifest, which AppSync lets through for an ldid signature. One run per
   object; the object reports on the main thread and keeps working with no one watching until cancel or the end */
@interface ExteriaUpdater : NSObject

/* the roots GitHub's api, its pages and its download hosts chain to: the shared pem files of the bundle, nil when one is missing */
+ (NSData *)trustedRoots;
/* in-place updates require a writable jailbreak installation and uicache */
+ (BOOL)canInstallInPlace;
/* before ios 7.1, a user app on a phone with AppSync can use the local http manifest */
+ (BOOL)canInstallThroughInstaller;
+ (BOOL)canInstall;
/* hands the system the download of a release when the app cannot install it itself: the direct url of the ipa, which is one redirect to a file,
   and only without one the page of the latest release, which old browsers cannot draw. NO when the system took neither */
+ (BOOL)openDownloadOfIpaURL:(NSString *)ipaURL;

/* version is the release tag, the manifest names it to the system */
- (id)initWithIpaURL:(NSString *)ipaURL digestURL:(NSString *)digestURL size:(uint64_t)size version:(NSString *)version;

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
/* stops a download or a staging; an install that has begun moving files is finished first. after the hand off it stops serving the files */
- (void)cancel;

@end
