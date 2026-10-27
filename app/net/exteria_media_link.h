#import <Foundation/Foundation.h>

#import "exteria_remote_file.h"
#import "exteria_shiro.h"

/* hands an exported authorization to the link: its id and bytes, or the rpc error name */
typedef void (^ExteriaAuthorizationDelivery)(long long authId, NSData *bytes, NSString *errorName);
/* asked for when the link's key is not signed in yet; it must call deliver once, from any thread */
typedef void (^ExteriaAuthorizer)(ExteriaAuthorizationDelivery deliver);
/* runs on the main thread: the file bytes, or nil and an error name (TIMEOUT, OFFLINE, an rpc error name) */
typedef void (^ExteriaDownloadCompletion)(NSData *data, NSString *errorName);

/* a second connection to a data center other than the account's home, for files that live there */
@interface ExteriaMediaLink : NSObject {
    int32_t _dc;
}

@property (nonatomic, readonly) int32_t dc;
/* the VPN the connection goes through when it is wanted; set before the first download */
@property (nonatomic, assign) ExteriaShiro *shiro;

- (id)initWithDc:(int32_t)dc directory:(NSString *)directory deviceModel:(NSString *)deviceModel
   systemVersion:(NSString *)systemVersion appVersion:(NSString *)appVersion langCode:(NSString *)langCode;

- (void)downloadFile:(ExteriaRemoteFile *)file authorizer:(ExteriaAuthorizer)authorizer completion:(ExteriaDownloadCompletion)completion;
/* one part of a large file: up to limit bytes from offset, fewer on the last part, none past the end */
- (void)downloadFile:(ExteriaRemoteFile *)file offset:(long long)offset limit:(int32_t)limit ranged:(BOOL)ranged
          authorizer:(ExteriaAuthorizer)authorizer completion:(ExteriaDownloadCompletion)completion;

/* waits for the thread to end */
- (void)stop;

@end
