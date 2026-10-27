#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* the content settings of the account, from account.getContentSettings and account.setContentSettings: whether
   media meant for adults is shown */
@interface ExteriaSession (Content)

/* enabled says what the server has now, canChange whether this account may switch it (otherwise the choice is not offered) */
- (void)loadContentSettings:(void (^)(BOOL enabled, BOOL canChange, NSString *errorName))completion;
- (void)setSensitiveContent:(BOOL)enabled completion:(void (^)(NSString *errorName))completion;

@end
