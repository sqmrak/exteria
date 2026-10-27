#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* what the account keeps on the server about the use of the app, for the Data and Memory screen */
@interface ExteriaSession (Data)

/* messages.clearAllDrafts: the drafts of every chat of the account go, on this phone and on the others */
- (void)clearAllDraftsWithCompletion:(void (^)(NSString *errorName))completion;

/* account.deleteAccount without a password: the account goes for good */
- (void)deleteAccountWithReason:(NSString *)reason completion:(void (^)(NSString *errorName))completion;

/* account.updateStatus: tells the account is offline, which ghost mode repeats while the app runs, since the server counts a connection that is in use as online */
- (void)sendOfflineStatus;

@end
