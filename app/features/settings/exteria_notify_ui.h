#import <UIKit/UIKit.h>

#import "exteria_session_notifysettings.h"
#import "exteria_symbol.h"

/* what the notification screens share: the kinds of the main list, the words for a state and a tone, the tones of the app, and the lists of exceptions */

typedef enum {
    ExteriaNotifyKindPrivate,
    ExteriaNotifyKindGroups,
    ExteriaNotifyKindChannels,
    ExteriaNotifyKindStories,
    ExteriaNotifyKindReactions,
    /* only the exceptions of every kind, as the alert about a change lists them */
    ExteriaNotifyKindAllExceptions
} ExteriaNotifyKind;

/* the scope of the account a kind of chat is kept in; not for stories (they ride on private chats) and reactions */
exteria_notify_scope ExteriaNotifyScopeOfKind(ExteriaNotifyKind kind);

/* "on", "Off", or "Off until Friday" for a mute time say it */
NSString *ExteriaNotifyMuteText(int32_t muteUntil);
/* the name of a tone as the settings show it; has says the settings name one at all */
NSString *ExteriaNotifySoundText(BOOL has, const exteria_notify_sound *sound);
/* the tones the bundle holds, each as an array of the file name and the title */
NSArray *ExteriaNotifyTones(void);
/* a count with its noun, "3 chats" or "2 exceptions"; base is "notif.chats" or "notif.exceptions" */
NSString *ExteriaNotifyCountText(NSString *base, NSInteger count);

/* the exceptions that belong in the list of a kind */
NSArray *ExteriaNotifyExceptionsForKind(NSArray *all, ExteriaNotifyKind kind);

/* a round picture with the initials of a title on a color picked by the id, the size of a row tile */
UIImage *ExteriaNotifyInitialsTile(NSString *title, long long seed, CGFloat side);

/* the dates of a mute: now plus an hour, eight hours, two days; forever */
int32_t ExteriaNotifyNow(void);
