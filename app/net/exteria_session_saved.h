#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* AyuMoments, the part that keeps messages: what the other side deleted stays in the chat, marked, and what a
   message said before an edit stays as a version */
@interface ExteriaSession (Saved)

/* tells the part that handles the updates what the settings keep, now, and again after every new account */
- (void)setSavingSettingsFromDefaults;
/* the kept deleted messages and the kept versions together */
- (void)countSavedMessages:(void (^)(NSInteger count, NSString *errorName))completion;
- (void)clearSavedMessages:(void (^)(NSString *errorName))completion;
/* the kept deleted messages of a chat with ids from low to high, as ExteriaMessage items with deletedLocally set */
- (void)loadSavedDeletedOfDialog:(ExteriaDialog *)dialog from:(int32_t)low to:(int32_t)high completion:(void (^)(NSArray *messages))completion;
/* what a message said before its edits, the oldest version first, as ExteriaMessage items */
- (void)loadEditVersionsOfMessage:(int32_t)messageId dialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *versions))completion;

@end
