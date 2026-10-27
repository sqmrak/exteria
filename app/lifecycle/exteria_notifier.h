#import <UIKit/UIKit.h>

#import "exteria_session.h"

/* the master switch of the notifications of this phone, kept in the user defaults; what is announced for each kind
   of chat is in exteria_notify_store.h */
BOOL ExteriaNotifyEnabled(void);
void ExteriaNotifySetEnabled(BOOL on);

/* the economy mode of the background: the app is not kept awake with a silent sound, so news come when the system
   wakes it for a look instead of at once */
BOOL ExteriaNotifySavingAvailable(void);
BOOL ExteriaNotifySaving(void);
void ExteriaNotifySetSaving(BOOL on);

/* the chat on screen says so here (zero for none), so a message of it brings no notice of its own */
void ExteriaNotifierSetOpenChat(int32_t peerKind, long long peerId);

/* posted on the main thread after one of the switches changed */
extern NSString *const ExteriaNotifySettingsDidChangeNotification;

/* whether the connection should be made a voip socket: the notifications are on and this system keeps such a socket alive */
BOOL ExteriaBackgroundLinkWanted(void);

/* posted on the main thread when a notification was tapped or launched the app; userInfo has "kind" and "peer" as numbers */
extern NSString *const ExteriaOpenChatNotification;

/* notifications of a closed or sleeping app, the way OneGram does them on ios 5 and 6 */
@interface ExteriaNotifier : NSObject

- (id)initWithSession:(ExteriaSession *)session;
/* the session has an account; the hook on its store starts */
- (void)start;
/* the account is gone: pending notifications and the badge go, and the hook stops */
- (void)stop;
/* the app left the screen: what is unread now is the baseline, and the system is asked to keep the link and wake it */
- (void)applicationDidEnterBackground:(UIApplication *)application;
/* the app is on screen again: the keep-alive, pending notifications and the badge are cleared */
- (void)applicationDidBecomeActive:(UIApplication *)application;
/* a local notification was tapped (or launched the app) */
- (void)handleLocalNotification:(UILocalNotification *)notification;
/* a tap on a notification of ios 10 and later: userInfo names the chat as "kind" and "peer" */
- (void)openChatWithInfo:(NSDictionary *)info;
/* the system woke the app for a background fetch: the news are looked for and posted, and completion gets the system's result (0 new data,
   1 none, 2 failed) within about thirty seconds */
- (void)performFetchWithCompletion:(void (^)(NSUInteger result))completion;
/* the switches changed: asks for the permission where the system wants it, and posts nothing already shown again */
- (void)settingsChanged;

@end
