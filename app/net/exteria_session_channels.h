#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_person.h"
#import "exteria_session.h"

/* posted on the main thread when the signed in account joined or left a chat, so the chat lists load again */
extern NSString *const ExteriaDialogsChangedNotification;

/* what the profile of a channel shows; built off the main thread */
@interface ExteriaFullChannel : NSObject {
    ExteriaDialog *_dialog;
    ExteriaDialog *_linked;
    NSString *_about;
    NSString *_username;
    NSString *_inviteLink;
    BOOL _megagroup;
    BOOL _membershipKnown;
    BOOL _verified;
    BOOL _muted;
    BOOL _giftsAvailable;
    BOOL _creator;
    BOOL _signatures;
    uint32_t _adminRights;
    NSInteger _participants;
    NSInteger _admins;
    NSInteger _banned;
    NSInteger _gifts;
    int32_t _pinnedMessage;
    int32_t _sendAsKind;
    long long _sendAsId;
}
/* the channel as a chat, with its title, picture and access hash */
@property (nonatomic, readonly, retain) ExteriaDialog *dialog;
/* the discussion group of a broadcast channel, nil when it has none */
@property (nonatomic, readonly, retain) ExteriaDialog *linked;
@property (nonatomic, readonly) BOOL membershipKnown;
@property (nonatomic, readonly, copy) NSString *about;
/* empty for a private channel */
@property (nonatomic, readonly, copy) NSString *username;
/* the invite link an admin sees, empty otherwise */
@property (nonatomic, readonly, copy) NSString *inviteLink;
/* "t.me/name" for a public channel, the invite link for a private one an admin can see, empty otherwise */
@property (nonatomic, readonly) NSString *shownLink;
/* the address that opens it from outside the app, with the scheme */
@property (nonatomic, readonly) NSString *webLink;
@property (nonatomic, readonly) BOOL megagroup;
@property (nonatomic, readonly) BOOL verified;
@property (nonatomic, readonly) BOOL muted;
@property (nonatomic, readonly) BOOL giftsAvailable;
/* the signed in account made the channel and holds every right */
@property (nonatomic, readonly) BOOL creator;
/* posts carry the name of the admin who wrote them */
@property (nonatomic, readonly) BOOL signatures;
/* EXTERIA_ADMIN_* bits the account holds: all for the creator, those of its admin rights for an admin, none for anyone else */
@property (nonatomic, readonly) uint32_t adminRights;
/* the account is the creator or an admin with at least one right, so the management screens are for it */
@property (nonatomic, readonly) BOOL isAdmin;
@property (nonatomic, readonly) NSInteger participants;
@property (nonatomic, readonly) NSInteger admins;
@property (nonatomic, readonly) NSInteger banned;
@property (nonatomic, readonly) NSInteger gifts;
@property (nonatomic, readonly) int32_t pinnedMessage;
/* who the account writes as here when the server keeps a choice other than the account itself: 1 user, 3 channel (as peerKind), zero for none */
@property (nonatomic, readonly) int32_t sendAsKind;
@property (nonatomic, readonly) long long sendAsId;
@end

/* the lists of people a channel keeps */
typedef enum {
    ExteriaChannelListSubscribers = 0,
    ExteriaChannelListAdmins,
    ExteriaChannelListBlacklist
} ExteriaChannelList;

typedef enum {
    ExteriaChannelRolePlain = 0,
    ExteriaChannelRoleCreator,
    ExteriaChannelRoleAdmin,
    ExteriaChannelRoleBanned
} ExteriaChannelRole;

/* one row of such a list; built off the main thread */
@interface ExteriaChannelMember : NSObject {
    ExteriaPerson *_person;
    ExteriaChannelRole _role;
    BOOL _canEdit;
    BOOL _isSelf;
    uint32_t _rights;
    int32_t _date;
    NSString *_rank;
}
@property (nonatomic, readonly, retain) ExteriaPerson *person;
@property (nonatomic, readonly) ExteriaChannelRole role;
/* an admin whose rights the account may change */
@property (nonatomic, readonly) BOOL canEdit;
@property (nonatomic, readonly) BOOL isSelf;
/* EXTERIA_ADMIN_* bits of an admin; all for the creator */
@property (nonatomic, readonly) uint32_t rights;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly, copy) NSString *rank;
@end

/* channels.getFullChannel, joining, and the lists and settings an admin keeps; implemented in
   exteria_session_channels.m */
@interface ExteriaSession (Channels)

- (void)loadFullChannelOfDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaFullChannel *channel, NSString *errorName))completion;
- (void)loadDiscussionOfPost:(int32_t)postId dialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaDialog *discussion, NSString *errorName))completion;
/* one message of a channel by id, such as its pinned one; the completion gets nil and an error name when it is gone */
- (void)loadMessage:(int32_t)messageId ofChannelDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaMessage *message, NSString *errorName))completion;
/* the signed in account joins the public channel or group */
- (void)joinChannelOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;

/* one page of a list of the channel */
- (void)loadMembersOfDialog:(ExteriaDialog *)dialog list:(ExteriaChannelList)list query:(NSString *)query offset:(NSInteger)offset
                 completion:(void (^)(NSArray *members, NSInteger total, NSString *errorName))completion;
/* makes the person an admin with exactly these EXTERIA_ADMIN_* rights and this rank (nil for none); zero rights make the person a subscriber again */
- (void)setAdminRights:(uint32_t)rights rank:(NSString *)rank ofPerson:(ExteriaPerson *)person inDialog:(ExteriaDialog *)dialog
            completion:(void (^)(NSString *errorName))completion;
/* puts the person on the blacklist, or takes the person off it */
- (void)setBanned:(BOOL)banned person:(ExteriaPerson *)person inDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* adds the person (a chat with a user) to the supergroup */
- (void)inviteUserDialog:(ExteriaDialog *)user toDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)setTitle:(NSString *)title ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)setAbout:(NSString *)about ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* the public name of the channel; empty makes it private */
- (void)setUsername:(NSString *)username ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* nil error when the name is free */
- (void)checkUsername:(NSString *)username ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)setSignatures:(BOOL)enabled ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;

@end
