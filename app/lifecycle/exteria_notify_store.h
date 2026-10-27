#import <Foundation/Foundation.h>

#include "exteria_notify_prefs.h"

/* the notification settings the phone keeps; the rest are switches of this phone only */

/* posted when anything here changes, on the main thread */
extern NSString *const ExteriaNotifyStoreDidChangeNotification;

/* the copy of the settings of a kind of chat; a kind never set has no fields, which means on, shown, default sound */
exteria_peer_notify ExteriaNotifyScopeStored(exteria_notify_scope scope);
void ExteriaNotifyScopeStore(exteria_notify_scope scope, const exteria_peer_notify *value);

exteria_reaction_notify ExteriaNotifyReactionsStored(void);
void ExteriaNotifyReactionsStore(const exteria_reaction_notify *value);

/* the rules for a look at the chat list: the account's settings with the switches of the phone */
void ExteriaNotifyRulesSnapshot(exteria_notify_rules *out);

/* the switches of the phone */
BOOL ExteriaNotifyInAppSounds(void);
void ExteriaNotifySetInAppSounds(BOOL on);
BOOL ExteriaNotifyInAppVibrate(void);
void ExteriaNotifySetInAppVibrate(BOOL on);
BOOL ExteriaNotifyInAppPreview(void);
void ExteriaNotifySetInAppPreview(BOOL on);
/* a short sound for a message that comes into the chat on screen, and for one sent from it; off by default */
BOOL ExteriaNotifyInChatSounds(void);
void ExteriaNotifySetInChatSounds(BOOL on);
BOOL ExteriaNotifyContactJoined(void);
void ExteriaNotifySetContactJoined(BOOL on);
BOOL ExteriaNotifyPinnedMessages(void);
void ExteriaNotifySetPinnedMessages(BOOL on);
/* the number on the icon: shown at all, counting muted chats too, and counting messages and not chats */
BOOL ExteriaNotifyBadgeShown(void);
void ExteriaNotifySetBadgeShown(BOOL on);
BOOL ExteriaNotifyBadgeMuted(void);
void ExteriaNotifySetBadgeMuted(BOOL on);
BOOL ExteriaNotifyBadgeMessages(void);
void ExteriaNotifySetBadgeMessages(BOOL on);
/* minutes between the reminders of unread messages, zero for never; an hour by default */
NSInteger ExteriaNotifyRepeatMinutes(void);
void ExteriaNotifySetRepeatMinutes(NSInteger minutes);
/* how the phone shakes for an incoming call: 0 default, 1 short, 2 off, 3 long */
NSInteger ExteriaNotifyCallVibration(void);
void ExteriaNotifySetCallVibration(NSInteger style);

/* forget the copy of the account's settings and every switch: the state of a new install (the phone's own master switch and power saver stay) */
void ExteriaNotifyStoreReset(void);
