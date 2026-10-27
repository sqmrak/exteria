#import <Foundation/Foundation.h>

#include "exteria_people.h"

@class ExteriaPhoto;

/* a user as the contact list and the settings screen show it; no UIKit object, so it can be built off the main thread */
/* the document of an emoji status that has not ended, by the unix time it ends (zero for never); zero for none */
long long ExteriaLiveEmojiStatus(long long document, int32_t until);

@interface ExteriaPerson : NSObject {
    long long _userId;
    long long _accessHash;
    BOOL _bot;
    BOOL _botInline;
    BOOL _botInlineGeo;
    NSString *_botPlaceholder;
    BOOL _verified;
    BOOL _contact;
    BOOL _mutual;
    BOOL _premium;
    long long _emojiStatus;
    NSInteger _nameColor;
    exteria_presence _presence;
    int32_t _seen;
    NSString *_name;
    NSString *_username;
    NSString *_phone;
    NSString *_initials;
    ExteriaPhoto *_photo;
}
@property (nonatomic, readonly) long long userId;
/* what a request that names this user needs, zero when none is known */
@property (nonatomic, readonly) long long accessHash;
@property (nonatomic, readonly) BOOL bot;
/* a bot that answers @name queries in any chat, and the hint it gives for the query; asks for the location with them */
@property (nonatomic, readonly) BOOL botInline;
@property (nonatomic, readonly) BOOL botInlineGeo;
@property (nonatomic, readonly, copy) NSString *botPlaceholder;
/* a bot with a main web app, and one that can be added to the attachment menu */
@property (nonatomic, readonly) BOOL verified;
/* in the contacts of the account */
@property (nonatomic, readonly) BOOL contact;
/* and the account is in the contacts of this person too, which marks with two arrows on the row */
@property (nonatomic, readonly) BOOL mutual;
/* Telegram Premium, which lets the person write custom emoji */
@property (nonatomic, readonly) BOOL premium;
/* the custom emoji document shown after the name, zero without one or once it has run out */
@property (nonatomic, readonly) long long emojiStatus;
/* the id of the color the person chose for their name in groups, -1 when they chose none and the id decides */
@property (nonatomic, readonly) NSInteger nameColor;
@property (nonatomic, readonly) exteria_presence presence;
/* the account is gone: the avatar is the ghost and the status reads "a very long time ago" */
@property (nonatomic, readonly) BOOL deleted;
@property (nonatomic, readonly) int32_t seen;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *username;
@property (nonatomic, readonly, copy) NSString *phone;
@property (nonatomic, readonly, copy) NSString *initials;
@property (nonatomic, readonly, retain) ExteriaPhoto *photo;

- (id)initWithRow:(const exteria_person_row *)row;

@end

/* up to two letters from the first two words, empty when the name starts with symbols only */
NSString *ExteriaInitialsOfName(NSString *name);
