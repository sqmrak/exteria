#import <Foundation/Foundation.h>

#import "exteria_session.h"

#include "exteria_notify_prefs.h"

/* a chat that has notification settings of its own, as the exceptions list shows it */
@interface ExteriaNotifyException : NSObject {
    exteria_notify_exception _value;
    NSString *_title;
}
- (id)initWithValue:(const exteria_notify_exception *)value;
@property (nonatomic, readonly) int32_t peerKind;
@property (nonatomic, readonly) long long peerId;
@property (nonatomic, readonly) long long peerHash;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) BOOL deleted;
/* a channel that only its admins write in */
@property (nonatomic, readonly) BOOL broadcast;
/* the entry is for a topic of a forum; the list leaves those out */
@property (nonatomic, readonly) BOOL forumTopic;
@property (nonatomic, readonly) exteria_peer_notify settings;
@end

/* one tone saved in the cloud of the account */
@interface ExteriaCloudTone : NSObject {
    exteria_ringtone_row _row;
    NSString *_title;
}
- (id)initWithRow:(const exteria_ringtone_row *)row;
@property (nonatomic, readonly) exteria_ringtone_row row;
@property (nonatomic, readonly) long long toneId;
/* the title of the tone, or its file name without the extension when it has none */
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) int32_t duration;
@end

/* the notification settings of the account on the server */
@interface ExteriaSession (NotifySettings)

/* reads the settings of the three kinds of chat and the reactions from the server into the copy the phone keeps
   (exteria_notify_store.h); one failed kind leaves the rest as they were */
- (void)syncNotifySettingsWithCompletion:(void (^)(NSString *errorName))completion;
/* sends the copy of a kind of chat (its stories fields too, for private chats) */
- (void)sendNotifyScope:(exteria_notify_scope)scope completion:(void (^)(NSString *errorName))completion;
- (void)sendReactionNotifyWithCompletion:(void (^)(NSString *errorName))completion;

/* ExteriaNotifyException items for every chat with settings of its own (topics of forums included, marked), in server order */
- (void)loadNotifyExceptionsWithCompletion:(void (^)(NSArray *exceptions, NSString *errorName))completion;
/* the settings one chat sets itself, no fields when it has none */
- (void)loadNotifyOfPeerKind:(int32_t)kind id:(long long)peerId hash:(long long)hash topic:(int32_t)topic
                  completion:(void (^)(NSValue *settings, NSString *errorName))completion;
/* sends the fields that have has_ set to one chat; a field cannot be taken back one by one */
- (void)updateNotify:(NSValue *)settings ofPeerKind:(int32_t)kind id:(long long)peerId hash:(long long)hash topic:(int32_t)topic
          completion:(void (^)(NSString *errorName))completion;
/* the chat follows its kind again: its mute, preview and sound settings are sent as the defaults */
- (void)resetNotifyOfPeerKind:(int32_t)kind id:(long long)peerId hash:(long long)hash topic:(int32_t)topic completion:(void (^)(NSString *errorName))completion;

/* account.resetNotifySettings: every kind and every chat back to the defaults; the copy on the phone is cleared when it succeeds */
- (void)resetAllNotifySettingsWithCompletion:(void (^)(NSString *errorName))completion;
/* the news of a contact who joined Telegram */
- (void)setContactJoinedNotify:(BOOL)on completion:(void (^)(NSString *errorName))completion;

/* ExteriaCloudTone items in the order the account keeps them */
- (void)loadCloudTonesWithCompletion:(void (^)(NSArray *tones, NSString *errorName))completion;
- (void)removeCloudTone:(ExteriaCloudTone *)tone completion:(void (^)(NSString *errorName))completion;

@end
