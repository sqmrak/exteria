#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_person.h"
#import "exteria_session.h"
#include "exteria_profile.h"

/* the channel a profile shows under the name: the chat to open it, how many follow it and its newest message */
@interface ExteriaPersonalChannel : NSObject {
    ExteriaDialog *_dialog;
    NSInteger _subscribers;
    NSString *_lastText;
    int32_t _lastDate;
}
@property (nonatomic, readonly, retain) ExteriaDialog *dialog;
@property (nonatomic, readonly) NSInteger subscribers;
/* what the profile's message of the channel says, empty when it has none or it is not text */
@property (nonatomic, readonly, copy) NSString *lastText;
@property (nonatomic, readonly) int32_t lastDate;
@end

/* everything users.getFullUser tells about a person: the bio, the birthday and the personal channel */
@interface ExteriaFullUser : NSObject {
    NSString *_about;
    ExteriaPerson *_person;
    BOOL _requiresPremium;
    BOOL _sharingRestricted;
    BOOL _hasBirthday;
    int32_t _birthdayDay;
    int32_t _birthdayMonth;
    int32_t _birthdayYear;
    ExteriaPersonalChannel *_channel;
    ExteriaMedia *_music;
    BOOL _hasRating;
    BOOL _hasPendingRating;
    int32_t _pendingRatingDate;
    exteria_star_rating _rating;
    exteria_star_rating _pendingRating;
}
@property (nonatomic, readonly, copy) NSString *about;
/* the user as that answer names them, nil when it did not carry them */
@property (nonatomic, readonly, retain) ExteriaPerson *person;
/* only Premium users may write to this person and reply to their stories */
@property (nonatomic, readonly) BOOL requiresPremium;
@property (nonatomic, readonly) BOOL sharingRestricted;
@property (nonatomic, readonly) BOOL hasBirthday;
@property (nonatomic, readonly) int32_t birthdayDay;
@property (nonatomic, readonly) int32_t birthdayMonth;
/* zero when the year is hidden */
@property (nonatomic, readonly) int32_t birthdayYear;
@property (nonatomic, readonly, retain) ExteriaPersonalChannel *channel;
/* the song the profile shows first, nil when it has none */
@property (nonatomic, readonly, retain) ExteriaMedia *music;
@property (nonatomic, readonly) BOOL hasRating;
@property (nonatomic, readonly) BOOL hasPendingRating;
@property (nonatomic, readonly) int32_t pendingRatingDate;
@property (nonatomic, readonly) exteria_star_rating rating;
@property (nonatomic, readonly) exteria_star_rating pendingRating;
@end

/* the signed in person's own profile: the bio, the name, the username and the photo; implemented in
   exteria_session_profile.m; USERNAME_INVALID is this layer's own */
@interface ExteriaSession (Profile)

/* the full profile of the person a chat is with, or of oneself for the chat with oneself; the personal channel comes with its
   newest message when the profile shows one */
- (void)loadFullUserOfDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaFullUser *user, NSString *errorName))completion;
/* whether the person of a chat accepts messages and story replies only from Premium users while the signed in
   person is not one */
- (void)loadPremiumGateOfDialog:(ExteriaDialog *)dialog completion:(void (^)(BOOL blocked))completion;
/* the songs saved on the profile of the person a chat is with (or on one's own, for the chat with oneself), a page
   from offset on. total is how many there are altogether */
- (void)loadSavedMusicOfDialog:(ExteriaDialog *)dialog offset:(NSInteger)offset completion:(void (^)(NSArray *tracks, NSInteger total, NSString *errorName))completion;
/* the profile photos of the person a chat is with (the newest first, one's own for the chat with oneself) or the
   photos a group or channel has had; the items are ExteriaMedia of kind photo */
- (void)loadAvatarsOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *photos, NSString *errorName))completion;
/* puts a song on the signed in profile, or takes it off; the song is an ExteriaMedia of kind audio that has a file reference */
- (void)saveMusic:(ExteriaMedia *)song unsave:(BOOL)unsave completion:(void (^)(NSString *errorName))completion;
/* a year of zero hides it; a date the calendar does not have is refused before it is sent and comes back as INTERNAL */
- (void)setBirthdayDay:(int32_t)day month:(int32_t)month year:(int32_t)year completion:(void (^)(NSString *errorName))completion;
- (void)clearBirthday:(void (^)(NSString *errorName))completion;
/* the channels that may go on the profile as ExteriaDialog items; nil takes the channel off the profile */
- (void)loadChannelsForProfile:(ExteriaListCompletion)completion;
- (void)setPersonalChannel:(ExteriaDialog *)channel completion:(void (^)(NSString *errorName))completion;
/* the bio, empty when there is none */
- (void)loadAbout:(void (^)(NSString *about, NSString *errorName))completion;
/* a nil argument leaves that part as it is; an empty last name or bio clears it */
- (void)updateFirstName:(NSString *)firstName lastName:(NSString *)lastName about:(NSString *)about
             completion:(void (^)(ExteriaPerson *person, NSString *errorName))completion;
/* an empty name removes the username */
- (void)updateUsername:(NSString *)username completion:(void (^)(ExteriaPerson *person, NSString *errorName))completion;

@end

/* the word that stands for a message that is not text, as the chat list says it: "Photo", "Video", "Voice message"; empty for text */
NSString *ExteriaPreviewWord(exteria_preview_kind kind);
