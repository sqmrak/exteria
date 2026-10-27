#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* a login from another device that the server asks the owner to confirm */
@interface ExteriaUnconfirmedLogin : NSObject {
    long long _hash;
    int32_t _date;
    NSString *_device;
    NSString *_place;
}
@property (nonatomic, readonly) long long sessionHash;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly, copy) NSString *device;
/* "frankfurt am Main, Germany", empty when the server gave no place */
@property (nonatomic, readonly, copy) NSString *place;
@end

/* the logins the owner has not answered for yet; implemented in exteria_session_logins.m */
@interface ExteriaSession (Logins)

/* ExteriaUnconfirmedLogin items, newest first; empty when there is nothing to ask */
- (void)loadUnconfirmedLogins:(ExteriaListCompletion)completion;
/* "yes, it was me" */
- (void)confirmLogin:(ExteriaUnconfirmedLogin *)login completion:(void (^)(NSString *errorName))completion;
/* "no, it was not me": the session ends */
- (void)terminateLogin:(ExteriaUnconfirmedLogin *)login completion:(void (^)(NSString *errorName))completion;

@end
