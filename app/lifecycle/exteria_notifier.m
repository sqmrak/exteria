#import "exteria_notifier.h"

#import <objc/message.h>

#import "exteria_background_keeper.h"
#import "exteria_app_sounds.h"
#import "exteria_inapp_banner.h"
#import "exteria_lite_mode.h"
#import "exteria_notify_store.h"
#import "exteria_plural.h"
#import "exteria_session_internal.h"
#import "exteria_session_notify.h"
#import "exteria_voip_socket.h"
#import "exteria_weak_reference.h"

NSString *const ExteriaOpenChatNotification = @"ExteriaOpenChat";
NSString *const ExteriaNotifySettingsDidChangeNotification = @"ExteriaNotifySettingsDidChange";

#define KEY_ENABLED @"exteria.notify.enabled"
#define KEY_SAVING @"exteria.notify.saving"
/* a change of the store is looked at after this pause, so a burst of messages is one look */
#define DEBOUNCE_SECONDS 0.4
/* the system wakes a keep-alive app this often at best */
#define KEEP_ALIVE_SECONDS 600.0
/* on screen the chat list is read at most this often for the notices of other chats, since every look is a request */
#define FOREGROUND_LOOK_SECONDS 6.0
/* the chat list is read at most this often from the background, so a chat that writes all day is not a request for
   each message */
#define BACKGROUND_LOOK_SECONDS 8.0
#define FLOOD_WAIT_DEFAULT_SECONDS 30.0
#define FLOOD_WAIT_MAX_SECONDS 900.0
/* a quiet link in the background pings this rarely, since every ping wakes the radio; the disconnect delay sent with it follows the interval */
#define BACKGROUND_PING_MS 60000u
#define BACKGROUND_PING_SAVER_MS 120000u

static int32_t ExteriaOpenChatKind;
static long long ExteriaOpenChatPeer;

void ExteriaNotifierSetOpenChat(int32_t peerKind, long long peerId) {
    ExteriaOpenChatKind = peerKind;
    ExteriaOpenChatPeer = peerId;
}

static BOOL ExteriaNotifyFlag(NSString *key, BOOL fallback) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return stored ? [stored boolValue] : fallback;
}

static void ExteriaNotifySetFlag(NSString *key, BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaNotifySettingsDidChangeNotification object:nil];
}

BOOL ExteriaNotifyEnabled(void) { return ExteriaNotifyFlag(KEY_ENABLED, YES); }
void ExteriaNotifySetEnabled(BOOL on) { ExteriaNotifySetFlag(KEY_ENABLED, on); }
BOOL ExteriaNotifySavingAvailable(void) { return [ExteriaBackgroundKeeper needed]; }
BOOL ExteriaNotifySaving(void) { return ExteriaNotifyFlag(KEY_SAVING, NO); }
void ExteriaNotifySetSaving(BOOL on) { ExteriaNotifySetFlag(KEY_SAVING, on); }

BOOL ExteriaBackgroundLinkWanted(void) {
    return ExteriaNotifyEnabled() && ExteriaVoipSocketSupported();
}

/* the answer of the delegate of ios 10 and later: the system tells it about a tap on a notification, and asks
   whether to show one while the app is on screen */
@interface ExteriaUserNotificationDelegate : NSObject {
    ExteriaWeakReference *_notifier;
}
- (id)initWithNotifier:(ExteriaWeakReference *)notifier;
@end

@interface ExteriaNotifier () {
    ExteriaBackgroundKeeper *_keeper;
    id _unDelegate;
    void (^_fetchHandler)(NSUInteger result);
    ExteriaSession *_session;
    ExteriaAvatarCache *_bannerAvatars;
    ExteriaWeakReference *_weak;
    NSTimer *_debounce;
    BOOL _scanning;
    BOOL _rescan;
    BOOL _started;
    NSUInteger _scanGeneration;
    NSTimeInterval _lastForegroundLook;
    NSTimeInterval _lastBackgroundLook;
    /* the server asked for quiet until this time (reference date), zero when it did not */
    NSTimeInterval _blockedUntil;
    /* held from the moment a change woke the app until the look it caused is done, so the system does not put it back to sleep */
    UIBackgroundTaskIdentifier _wakeTask;
}
@end

@implementation ExteriaNotifier

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _wakeTask = UIBackgroundTaskInvalid;
    _keeper = [[ExteriaBackgroundKeeper alloc] init];
    /* it has to be in place before the app finishes launching, or the tap that started it is lost */
    id center = [self userNotificationCenter];
    if (center) {
        _unDelegate = [[ExteriaUserNotificationDelegate alloc] initWithNotifier:_weak];
        [center setValue:_unDelegate forKey:@"delegate"];
    }
    return self;
}

- (void)dealloc {
    [[self userNotificationCenter] setValue:nil forKey:@"delegate"];
    [_unDelegate release];
    [_keeper stop];
    [_keeper release];
    [_fetchHandler release];
    [_weak clear];
    [_weak release];
    [_debounce invalidate];
    [_bannerAvatars release];
    [_session release];
    [super dealloc];
}

#pragma mark system calls that the sdks of the two slices do not agree on

/* setKeepAliveTimeout:handler: is deprecated from ios 9 and its header is gone from the newest sdk, so it is called by name */
- (void)installKeepAliveForApplication:(UIApplication *)application {
    SEL install = NSSelectorFromString(@"setKeepAliveTimeout:handler:");
    if (!ExteriaVoipSocketSupported() || ![application respondsToSelector:install]) return;
    ExteriaWeakReference *weak = _weak;
    void (^handler)(void) = ^{
        /* the handler may come on any thread */
        dispatch_async(dispatch_get_main_queue(), ^{ [(ExteriaNotifier *)weak.target keepAliveWake]; });
    };
    BOOL installed = ((BOOL (*)(id, SEL, NSTimeInterval, void (^)(void)))objc_msgSend)(application, install, KEEP_ALIVE_SECONDS, handler);
    NSLog(@"exteria: keep-alive %@", installed ? @"installed" : @"refused");
}

- (void)clearKeepAliveForApplication:(UIApplication *)application {
    SEL clear = NSSelectorFromString(@"clearKeepAliveTimeout");
    if ([application respondsToSelector:clear]) ((void (*)(id, SEL))objc_msgSend)(application, clear);
}

/* the notification center of ios 10 and later, nil before; every call to it goes by name, since the sdk of the armv7 slice does not have it */
- (id)userNotificationCenter {
    Class center = NSClassFromString(@"UNUserNotificationCenter");
    return center ? [center performSelector:NSSelectorFromString(@"currentNotificationCenter")] : nil;
}

/* ios 8 asks before a local notification may show or the badge may change, and ios 10 moved the question to the notification center; the
   classes are looked up by name for the older sdk */
- (void)registerForNotificationsInApplication:(UIApplication *)application {
    id center = [self userNotificationCenter];
    if (center) {
        /* badge, sound and alert are bits 0, 1 and 2 of UNAuthorizationOptions */
        void (^answered)(BOOL, NSError *) = ^(BOOL granted, NSError *error) {
            if (error) NSLog(@"exteria: the notification permission could not be asked: %@", error);
            else if (!granted) NSLog(@"exteria: the notifications are not allowed in the settings of the system");
        };
        ((void (*)(id, SEL, NSUInteger, void (^)(BOOL, NSError *)))objc_msgSend)(center, NSSelectorFromString(@"requestAuthorizationWithOptions:completionHandler:"), 1 | 2 | 4, answered);
        /* a sleeping app is woken by the system now and then to look; the system picks the interval */
        SEL interval = NSSelectorFromString(@"setMinimumBackgroundFetchInterval:");
        if ([application respondsToSelector:interval]) ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(application, interval, 0);
        return;
    }
    SEL register_ = NSSelectorFromString(@"registerUserNotificationSettings:");
    Class settingsClass = NSClassFromString(@"UIUserNotificationSettings");
    if (!settingsClass || ![application respondsToSelector:register_]) return;
    /* alert, badge and sound are bits 4, 1 and 2 of UIUserNotificationType */
    NSUInteger types = 4 | 1 | 2;
    SEL make = NSSelectorFromString(@"settingsForTypes:categories:");
    id settings = ((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(settingsClass, make, types, nil);
    if (settings) ((void (*)(id, SEL, id))objc_msgSend)(application, register_, settings);
}

/* every notification of ours that is waiting or on the screen of the person goes, and the badge with them */
- (void)clearNotificationsInApplication:(UIApplication *)application {
    id center = [self userNotificationCenter];
    if (center) {
        ((void (*)(id, SEL))objc_msgSend)(center, NSSelectorFromString(@"removeAllPendingNotificationRequests"));
        ((void (*)(id, SEL))objc_msgSend)(center, NSSelectorFromString(@"removeAllDeliveredNotifications"));
    }
    [application cancelAllLocalNotifications];
    application.applicationIconBadgeNumber = 0;
}

#pragma mark lifecycle

- (void)start {
    if (_started) return;
    _started = YES;
    ExteriaWeakReference *weak = _weak;
    [_session post:^{
        [_session setChangeHook:^{
            dispatch_async(dispatch_get_main_queue(), ^{ [(ExteriaNotifier *)weak.target storeChanged]; });
        }];
    }];
    if (ExteriaNotifyEnabled()) [self registerForNotificationsInApplication:[UIApplication sharedApplication]];
}

- (void)stop {
    if (!_started) return;
    _started = NO;
    ++_scanGeneration;
    _scanning = NO;
    _rescan = NO;
    [_session post:^{ [_session setChangeHook:nil]; }];
    [_debounce invalidate];
    _debounce = nil;
    [self endWakeTask];
    UIApplication *application = [UIApplication sharedApplication];
    [self clearNotificationsInApplication:application];
    [self clearKeepAliveForApplication:application];
    [_keeper stop];
}

- (void)settingsChanged {
    UIApplication *application = [UIApplication sharedApplication];
    if (ExteriaNotifyEnabled()) {
        [self registerForNotificationsInApplication:application];
        return;
    }
    ++_scanGeneration;
    _scanning = NO;
    _rescan = NO;
    [_debounce invalidate];
    _debounce = nil;
    [self endWakeTask];
    [self clearNotificationsInApplication:application];
    [self clearKeepAliveForApplication:application];
    [_keeper stop];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (!_started || !ExteriaNotifyEnabled()) return;
    [_session setPingInterval:ExteriaLitePowerSaverApplied() ? BACKGROUND_PING_SAVER_MS : BACKGROUND_PING_MS];
    /* what is unread now is old news: the first look after leaving the screen takes it as the baseline and sets the badge */
    [self scanAnnouncing:NO application:application];
    [self installKeepAliveForApplication:application];
    /* where no VoIP socket is kept for the app, playing silence is what keeps it, and its link, awake */
    if ([ExteriaBackgroundKeeper needed] && !ExteriaNotifySaving()) [_keeper start];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    /* the person is here, so the reminder of what they have not read has no use */
    for (UILocalNotification *old in [[application.scheduledLocalNotifications copy] autorelease]) {
        if ([[old.userInfo objectForKey:@"repeat"] boolValue]) [application cancelLocalNotification:old];
    }
    [_session setPingInterval:0];
    [_debounce invalidate];
    _debounce = nil;
    [self clearKeepAliveForApplication:application];
    [_keeper stop];
}

- (void)handleLocalNotification:(UILocalNotification *)notification {
    [self openChatWithInfo:notification.userInfo];
}

/* the numbers a notification carries name its chat; the main screen opens it */
- (void)openChatWithInfo:(NSDictionary *)info {
    NSNumber *kind = [info objectForKey:@"kind"], *peer = [info objectForKey:@"peer"];
    if (![kind isKindOfClass:[NSNumber class]] || ![peer isKindOfClass:[NSNumber class]]) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaOpenChatNotification object:self
                                                      userInfo:[NSDictionary dictionaryWithObjectsAndKeys:kind, @"kind", peer, @"peer", nil]];
}

#pragma mark looking

- (void)storeChanged {
    if (!_started || !ExteriaNotifyEnabled() || _debounce) return;
    UIApplication *application = [UIApplication sharedApplication];
    if (application.applicationState == UIApplicationStateActive) {
        /* on screen, the app tells of other chats itself: a sound, a shake, a card; with all three off there is nothing to look for */
        if (!ExteriaNotifyInAppSounds() && !ExteriaNotifyInAppVibrate() && !ExteriaNotifyInAppPreview()) return;
        NSTimeInterval wait = FOREGROUND_LOOK_SECONDS - ([NSDate timeIntervalSinceReferenceDate] - _lastForegroundLook);
        _debounce = [NSTimer scheduledTimerWithTimeInterval:MAX(DEBOUNCE_SECONDS, wait) target:self selector:@selector(debounceFired:) userInfo:nil repeats:NO];
        return;
    }
    if (_wakeTask == UIBackgroundTaskInvalid) {
        ExteriaWeakReference *weak = _weak;
        _wakeTask = [application beginBackgroundTaskWithExpirationHandler:^{ [(ExteriaNotifier *)weak.target endWakeTask]; }];
    }
    NSTimeInterval since = [NSDate timeIntervalSinceReferenceDate] - _lastBackgroundLook;
    _debounce = [NSTimer scheduledTimerWithTimeInterval:MAX(DEBOUNCE_SECONDS, BACKGROUND_LOOK_SECONDS - since) target:self selector:@selector(debounceFired:) userInfo:nil repeats:NO];
}

- (void)endWakeTask {
    if (_wakeTask == UIBackgroundTaskInvalid) return;
    UIBackgroundTaskIdentifier task = _wakeTask;
    _wakeTask = UIBackgroundTaskInvalid;
    [[UIApplication sharedApplication] endBackgroundTask:task];
}

- (void)debounceFired:(NSTimer *)timer {
    (void)timer;
    _debounce = nil;
    UIApplication *application = [UIApplication sharedApplication];
    if (application.applicationState == UIApplicationStateActive) _lastForegroundLook = [NSDate timeIntervalSinceReferenceDate];
    [self scanAnnouncing:YES application:application];
}

/* every ten minutes the system wakes the app; a background task keeps the app awake until the answer is in */
- (void)keepAliveWake {
    if (!_started || !ExteriaNotifyEnabled()) return;
    UIApplication *application = [UIApplication sharedApplication];
    if (application.applicationState == UIApplicationStateActive) return;
    [_session reconnect];
    [self scanAnnouncing:YES application:application];
}

/* the system woke the app for a look: the link is made sure of, the chat list is read and the news are posted */
- (void)performFetchWithCompletion:(void (^)(NSUInteger result))completion {
    if (!_started || !ExteriaNotifyEnabled()) {
        completion(1);
        return;
    }
    if (_fetchHandler) {
        /* a second wake while one is still looking has nothing to add */
        completion(1);
        return;
    }
    _fetchHandler = [completion copy];
    ExteriaWeakReference *weak = _weak;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [(ExteriaNotifier *)weak.target finishFetch:2];
    });
    UIApplication *application = [UIApplication sharedApplication];
    [_session reconnect];
    [self scanAnnouncing:YES application:application];
}

/* result is the system's UIBackgroundFetchResult */
- (void)finishFetch:(NSUInteger)result {
    if (!_fetchHandler) return;
    void (^handler)(NSUInteger) = _fetchHandler;
    _fetchHandler = nil;
    handler(result);
    [handler release];
}

- (void)scanAnnouncing:(BOOL)announce application:(UIApplication *)application {
    if (!_started || !ExteriaNotifyEnabled()) return;
    if (_scanning) {
        _rescan = _rescan || announce;
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < _blockedUntil) {
        /* one look when the wait is over, whatever came in meanwhile */
        if (!_debounce) _debounce = [NSTimer scheduledTimerWithTimeInterval:_blockedUntil - now + 0.5 target:self selector:@selector(debounceFired:) userInfo:nil repeats:NO];
        [self finishFetch:1];
        return;
    }
    if (application.applicationState != UIApplicationStateActive) _lastBackgroundLook = now;
    _scanning = YES;
    NSUInteger generation = ++_scanGeneration;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    task = [application beginBackgroundTaskWithExpirationHandler:^{
        UIBackgroundTaskIdentifier expired = task;
        task = UIBackgroundTaskInvalid;
        if (expired != UIBackgroundTaskInvalid) [application endBackgroundTask:expired];
    }];
    ExteriaWeakReference *weak = _weak;
    ExteriaNotifyScanOptions options;
    memset(&options, 0, sizeof(options));
    ExteriaNotifyRulesSnapshot(&options.rules);
    options.badgeShown = ExteriaNotifyBadgeShown();
    options.badgeMuted = ExteriaNotifyBadgeMuted();
    options.badgeMessages = ExteriaNotifyBadgeMessages();
    options.activeKind = ExteriaOpenChatKind;
    options.activePeer = ExteriaOpenChatPeer;
    [_session scanNotificationsAnnouncing:announce options:options completion:^(NSArray *events, NSUInteger more, NSString *moreText, NSInteger badge, NSInteger unreadChats, NSString *errorName) {
        ExteriaNotifier *notifier = weak.target;
        if (notifier && notifier->_scanGeneration == generation) {
            notifier->_scanning = NO;
            if (errorName) {
                NSLog(@"exteria: notification look failed: %@", errorName);
                if ([errorName hasPrefix:@"FLOOD_WAIT"]) {
                    /* the link is fine, the list was asked for too often: nothing is reconnected, and the next look waits what the server said */
                    NSRange colon = [errorName rangeOfString:@":"];
                    NSTimeInterval seconds = colon.location == NSNotFound ? FLOOD_WAIT_DEFAULT_SECONDS : [[errorName substringFromIndex:colon.location + 1] doubleValue];
                    if (seconds < 1) seconds = FLOOD_WAIT_DEFAULT_SECONDS;
                    notifier->_blockedUntil = [NSDate timeIntervalSinceReferenceDate] + MIN(seconds, FLOOD_WAIT_MAX_SECONDS);
                    notifier->_rescan = YES;
                } else if (![errorName isEqualToString:@"NO_ACCOUNT"]) {
                    /* a look that cannot be made says the link is down; one try to bring it back */
                    [notifier->_session reconnect];
                }
                [notifier finishFetch:2];
            } else {
                [notifier postEvents:events more:more moreText:moreText badge:badge unreadChats:unreadChats application:application];
                [notifier finishFetch:events.count ? 0 : 1];
            }
            if (notifier->_rescan) {
                notifier->_rescan = NO;
                [notifier scanAnnouncing:YES application:application];
            } else {
                [notifier endWakeTask];
            }
        }
        if (task != UIBackgroundTaskInvalid) {
            UIBackgroundTaskIdentifier finished = task;
            task = UIBackgroundTaskInvalid;
            [application endBackgroundTask:finished];
        }
    }];
}

#pragma mark posting

/* ios 10 and later: a notification content with its title and body, posted at once; its identifier is the
   message's, so the same news twice is one notification, and the chat is its thread */
/* the file of the bundle a banner plays: nil for a banner without a sound, the empty string for the default one */
static NSString *ExteriaBannerSoundFile(const exteria_notify_sound *sound) {
    if (sound->kind == EXTERIA_SOUND_NONE) return nil;
    if (sound->kind == EXTERIA_SOUND_LOCAL && sound->data[0]) {
        NSString *name = [NSString stringWithUTF8String:sound->data];
        if (name.length && [[NSBundle mainBundle] pathForResource:name ofType:nil]) return name;
    }
    return @"";
}

- (void)presentWithCenter:(id)center title:(NSString *)title body:(NSString *)body userInfo:(NSDictionary *)info sound:(NSString *)sound {
    Class contentClass = NSClassFromString(@"UNMutableNotificationContent");
    Class soundClass = NSClassFromString(@"UNNotificationSound");
    Class requestClass = NSClassFromString(@"UNNotificationRequest");
    if (!contentClass || !soundClass || !requestClass) return;
    id content = [[[contentClass alloc] init] autorelease];
    [content setValue:title forKey:@"title"];
    [content setValue:body forKey:@"body"];
    if (sound) {
        id tone = sound.length ? [soundClass performSelector:NSSelectorFromString(@"soundNamed:") withObject:sound]
                               : [soundClass performSelector:NSSelectorFromString(@"defaultSound")];
        [content setValue:tone forKey:@"sound"];
    }
    if (info) [content setValue:info forKey:@"userInfo"];
    NSNumber *kind = [info objectForKey:@"kind"], *peer = [info objectForKey:@"peer"], *mid = [info objectForKey:@"mid"];
    NSString *identifier = @"exteria.more";
    if (kind && peer) {
        identifier = [NSString stringWithFormat:@"exteria.%@.%@.%@", kind, peer, mid ? mid : @0];
        [content setValue:[NSString stringWithFormat:@"%@.%@", kind, peer] forKey:@"threadIdentifier"];
    }
    id request = ((id (*)(id, SEL, NSString *, id, id))objc_msgSend)(requestClass, NSSelectorFromString(@"requestWithIdentifier:content:trigger:"),
                                                                    identifier, content, nil);
    void (^added)(NSError *) = ^(NSError *error) {
        if (error) NSLog(@"exteria: a notification was not posted: %@", error);
    };
    ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(center, NSSelectorFromString(@"addNotificationRequest:withCompletionHandler:"), request, added);
}

- (void)present:(NSString *)title body:(NSString *)body userInfo:(NSDictionary *)info sound:(NSString *)sound application:(UIApplication *)application {
    id center = [self userNotificationCenter];
    if (center) {
        [self presentWithCenter:center title:title body:body userInfo:info sound:sound];
        return;
    }
    UILocalNotification *notification = [[[UILocalNotification alloc] init] autorelease];
    /* the title is its own line only from ios 8.2; before that it leads the text */
    if ([notification respondsToSelector:NSSelectorFromString(@"setAlertTitle:")]) {
        [notification setValue:title forKey:@"alertTitle"];
        notification.alertBody = body;
    } else {
        notification.alertBody = title.length ? [NSString stringWithFormat:@"%@: %@", title, body] : body;
    }
    if (sound) notification.soundName = sound.length ? sound : UILocalNotificationDefaultSoundName;
    notification.userInfo = info;
    [application presentLocalNotificationNow:notification];
}

/* the reminder of what is still unread, a notification that fires after the interval of the settings and is taken
   back whenever the app looks again; an hour by default */
- (void)scheduleRepeatForUnread:(NSInteger)unreadChats application:(UIApplication *)application {
    for (UILocalNotification *old in [[application.scheduledLocalNotifications copy] autorelease]) {
        if ([[old.userInfo objectForKey:@"repeat"] boolValue]) [application cancelLocalNotification:old];
    }
    NSInteger minutes = ExteriaNotifyRepeatMinutes();
    if (unreadChats <= 0 || minutes <= 0 || !ExteriaNotifyEnabled()) return;
    UILocalNotification *reminder = [[[UILocalNotification alloc] init] autorelease];
    reminder.fireDate = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)minutes * 60];
    reminder.alertBody = [NSString stringWithFormat:NSLocalizedString([@"notif.repeat.body." stringByAppendingString:ExteriaPluralForm(unreadChats)], nil), (int)unreadChats];
    reminder.soundName = UILocalNotificationDefaultSoundName;
    reminder.userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"repeat"];
    [application scheduleLocalNotification:reminder];
}

/* the pictures on the cards come from the same folder as the lists' ones, so a face the lists loaded is already on disk */
- (ExteriaAvatarCache *)bannerAvatars {
    if (!_bannerAvatars) {
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *directory = [[caches stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"avatars"];
        _bannerAvatars = [[ExteriaAvatarCache alloc] initWithSession:_session directory:directory];
    }
    return _bannerAvatars;
}

/* the app is on screen: a message of another chat is a sound, a shake and a card, as the in-app settings say; the card names the chat and, with the preview on,
   shows the text */
- (void)announceInApp:(NSArray *)events {
    ExteriaNotifyEvent *event = events.lastObject;
    if (!event) return;
    exteria_notify_sound tone = event.sound;
    if (ExteriaNotifyInAppSounds() && tone.kind != EXTERIA_SOUND_NONE) {
        NSString *file = ExteriaBannerSoundFile(&tone);
        ExteriaPlayAppSound(file.length ? file : @"sound_in.caf");
    }
    ExteriaVibrateOnce();
    if (!ExteriaNotifyInAppPreview()) return;
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:event.peerKind], @"kind", [NSNumber numberWithLongLong:event.peerId], @"peer", nil];
    [ExteriaInAppBanner showTitle:event.title body:event.body dialog:event.dialog avatars:[self bannerAvatars] tap:^{ [self openChatWithInfo:info]; }];
}

- (void)postEvents:(NSArray *)events more:(NSUInteger)more moreText:(NSString *)moreText badge:(NSInteger)badge unreadChats:(NSInteger)unreadChats application:(UIApplication *)application {
    /* nothing is posted while the app is on screen: the look may have finished after the person came back */
    if (application.applicationState != UIApplicationStateActive) {
        for (ExteriaNotifyEvent *event in events) {
            NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:event.peerKind], @"kind",
                                  [NSNumber numberWithLongLong:event.peerId], @"peer", [NSNumber numberWithInt:event.messageId], @"mid", nil];
            exteria_notify_sound tone = event.sound;
            [self present:event.title body:event.body userInfo:info sound:ExteriaBannerSoundFile(&tone) application:application];
        }
        if (more && moreText) [self present:@"" body:moreText userInfo:nil sound:@"" application:application];
        application.applicationIconBadgeNumber = badge;
        [self scheduleRepeatForUnread:unreadChats application:application];
        return;
    }
    [self announceInApp:events];
}

@end

@implementation ExteriaUserNotificationDelegate

- (id)initWithNotifier:(ExteriaWeakReference *)notifier {
    self = [super init];
    if (!self) return nil;
    _notifier = [notifier retain];
    return self;
}

- (void)dealloc {
    [_notifier release];
    [super dealloc];
}

/* the app shows its own news while it is on screen, so nothing from the system is shown over it */
- (void)userNotificationCenter:(id)center willPresentNotification:(id)notification withCompletionHandler:(void (^)(NSUInteger options))handler {
    (void)center;
    (void)notification;
    handler(0);
}

- (void)userNotificationCenter:(id)center didReceiveNotificationResponse:(id)response withCompletionHandler:(void (^)(void))handler {
    (void)center;
    NSDictionary *info = [response valueForKeyPath:@"notification.request.content.userInfo"];
    void (^done)(void) = [handler copy];
    /* the chat opens once the screens exist, which for a tap that started the app is a turn of the run loop later */
    dispatch_async(dispatch_get_main_queue(), ^{
        [(ExteriaNotifier *)_notifier.target openChatWithInfo:info];
        done();
        [done release];
    });
}

@end
