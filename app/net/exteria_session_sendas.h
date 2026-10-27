#import <Foundation/Foundation.h>

#include "exteria_messages.h"

#import "exteria_dialog.h"
#import "exteria_session.h"

/* one identity the account may write as in a chat: itself, a channel it administers, or the anonymous identity of the group */
@interface ExteriaSendAsOption : NSObject {
    ExteriaDialog *_identity;
    BOOL _premiumRequired;
}
/* the identity as a chat, with its name, picture and access hash */
@property (nonatomic, readonly, retain) ExteriaDialog *identity;
/* the identity can only be used with Telegram Premium */
@property (nonatomic, readonly) BOOL premiumRequired;
/* the account itself */
@property (nonatomic, readonly) BOOL isAccount;
@end

/* who the account writes as in groups and channels that let it choose */
@interface ExteriaSession (SendAs)

/* the identities for a chat, the account itself first; a chat that offers no choice answers one option or none */
- (void)loadSendAsOptionsOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *options, NSString *errorName))completion;
/* the identity messages to the chat are sent as: nil for the account itself */
- (ExteriaDialog *)sendAsIdentityOfDialog:(ExteriaDialog *)dialog;
/* takes the choice the server already holds (the full channel names it) without telling the server again; nil for the account itself */
- (void)adoptSendAsIdentity:(ExteriaDialog *)identity ofDialog:(ExteriaDialog *)dialog;
/* the person chose: later messages carry it, and the server keeps it for the other devices. nil for the account
   itself */
- (void)chooseSendAsIdentity:(ExteriaDialog *)identity ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;

/* the stored choice for a chat, nil for the account itself; any thread */
- (ExteriaDialog *)storedSendAsForChat:(const exteria_peer_ref *)chat;
- (void)storeSendAs:(ExteriaDialog *)identity forChat:(const exteria_peer_ref *)chat;

@end
