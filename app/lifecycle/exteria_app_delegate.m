#import "exteria_power_notice.h"
#import "exteria_app_delegate.h"
#import "exteria_crash_log.h"
#import "exteria_app_icon.h"

#import "exteria_accounts.h"
#import "exteria_avatar_cache.h"
#import "exteria_session_profile.h"
#import "exteria_call_controller.h"
#import "exteria_group_call_presenter.h"
#import "exteria_language.h"
#import "exteria_link_router.h"
#import "exteria_lite_mode.h"
#import "exteria_music_player.h"
#import "exteria_notifier.h"
#import "exteria_night_mode.h"
#import "exteria_session_namecolor.h"
#import "exteria_session_notifysettings.h"
#import "exteria_perf_probe.h"
#import "exteria_wallpaper.h"
#import "exteria_traffic_store.h"
#import "exteria_chat_settings.h"
#import "exteria_back_swipe.h"
#import "exteria_passcode_lock.h"
#import "exteria_release_check.h"
#import "exteria_problem_report.h"
#import "exteria_proxy_settings.h"
#import "exteria_session_data.h"
#import "exteria_platform.h"
#import "exteria_shiro.h"
#import "exteria_shiro_failure_prompt.h"
#import "exteria_traffic_store.h"
#import "exteria_splash_view.h"
#import "exteria_split_controller.h"
#import "exteria_theme.h"

#import <QuartzCore/QuartzCore.h>

@interface ExteriaAppDelegate () {
    UIWindow *_window;
    UINavigationController *_navigation;
    ExteriaCountryBook *_countries;
    ExteriaSession *_session;
    ExteriaLoginFlow *_login;
    ExteriaNotifier *_notifier;
    ExteriaPasscodeLock *_passcodeLock;
    ExteriaBackSwipe *_backSwipe;
    ExteriaSplashView *_splash;
    ExteriaCallController *_callScreen;
    ExteriaGroupCallPresenter *_groupPresenter;
    /* the call screen folded away while the call goes on, and the bar over the chats that brings it back */
    BOOL _callMinimized;
    BOOL _callMinimizing;
    UIButton *_callBar;
    ExteriaCall *_callBarSnapshot;
    NSTimer *_callBarTimer;
    /* the newest snapshot of a call that began while the screen of the one before it was still leaving */
    ExteriaCall *_pendingCall;
    ExteriaAvatarCache *_callAvatars;
    ExteriaMediaCache *_callMedia;
    ExteriaShiro *_shiro;
    ExteriaShiroRoute _shiroRoute;
    /* a link that arrived before anyone was signed in, opened once the main screen exists */
    NSString *_pendingLink;
    /* the account that has the connection now; the first one is named "" */
    NSString *_activeAccount;
    NSTimer *_ghostTimer;
    /* an account being added: its own session while the login runs, the name of its directory, and the screen the person returns to by going back */
    ExteriaSession *_addSession;
    NSString *_addName;
    UIViewController *_addAnchor;
}
@end

@implementation ExteriaAppDelegate

@synthesize window = _window;

/* a signed in start waits for the first list; a list that never reports must not hold the screen for ever */
#define SPLASH_LIMIT_SECONDS 5.0

/* keys and the database stay in the app's private support directory */
static NSString *ExteriaSupportDirectory(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: cannot create %@: %@", directory, error);
    }
    return directory;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    /* before any text is asked for, so the first screen already speaks the chosen language */
    ExteriaApplyInterfaceLanguage();
    ExteriaLiteModeStart();
    ExteriaTrafficStart();
    /* before the first screen reads the stored theme, so a start at night already wears the night theme */
    ExteriaNightCheck(NO);
    /* and before the splash, the window and the tab bar, which draw with the colors of the tone that is current, light until it is applied */
    ExteriaThemeApplyStored();
    NSString *directory = ExteriaSupportDirectory();
    _activeAccount = [ExteriaAccountActive() copy];
    NSString *accountDirectory = ExteriaAccountDirectory(_activeAccount);
    BOOL signedIn = [ExteriaSession hasAccountInDirectory:accountDirectory];
    _session = [[ExteriaSession alloc] initWithDirectory:accountDirectory];
    _session.delegate = self;
    _session.callDelegate = self;
    _groupPresenter = [[ExteriaGroupCallPresenter alloc] initWithTopController:^UIViewController *{ return _navigation; } host:^UIView *{ return _navigation.view; }];
    _session.groupCallDelegate = _groupPresenter;
    /* the tunnel is wanted before the first connection, so a start with the VPN on never sends anything in the clear */
    _shiro = [[ExteriaShiro alloc] initWithDirectory:directory];
    _session.shiro = _shiro;
    ExteriaShiroSetActive(_shiro);
    _shiroRoute = _shiro.route;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shiroChanged:)
                                                 name:ExteriaShiroStateDidChangeNotification object:_shiro];
    [_shiro resume];
    [_session start];
    _notifier = [[ExteriaNotifier alloc] initWithSession:_session];
    if (signedIn) [_notifier start];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountSwitchRequested:) name:ExteriaAccountSwitchNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proxyChanged:) name:ExteriaProxyDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountAddRequested:) name:ExteriaAccountAddNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChangedForLaunchImages) name:ExteriaThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notifySettingsChanged:)
                                                 name:ExteriaNotifySettingsDidChangeNotification object:nil];

    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    self.window.backgroundColor = ExteriaColorBackdrop();
    /* every screen draws its own bar, so the system one stays hidden and only its push animation is used */
    _navigation = [[UINavigationController alloc] initWithRootViewController:signedIn ? [self makeMainController] : [self makeWelcomeController]];
    _navigation.navigationBarHidden = YES;
    self.window.rootViewController = _navigation;
    _backSwipe = [[ExteriaBackSwipe alloc] initWithNavigationController:_navigation];
    [self.window makeKeyAndVisible];
    _passcodeLock = [[ExteriaPasscodeLock alloc] init];
    [_passcodeLock lockAtLaunch];
    [self showSplashSignedIn:signedIn];
    ExteriaAppIconRestore();
    ExteriaCrashLogStart();
    ExteriaCrashLogWatchMemory();
    ExteriaWallpaperWarm();
    ExteriaPerfStart();
    ExteriaNightStart(^BOOL{ return [self nightMayRebuildScreens]; });
    /* a tap on a notification that started the app: the chat opens once the screens exist */
    UILocalNotification *launching = [options objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (launching && signedIn) dispatch_async(dispatch_get_main_queue(), ^{ [_notifier handleLocalNotification:launching]; });
    return YES;
}

/* tg:// links, which the Info.plist hands to the app, and t.me links when something passes them on: they open
   inside the app */
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    (void)application;
    (void)sourceApplication;
    (void)annotation;
    if (!ExteriaIsTelegramLink(url)) return NO;
    NSString *address = url.absoluteString;
    if (![ExteriaSession hasAccountInDirectory:ExteriaAccountDirectory(_activeAccount)]) {
        [_pendingLink release];
        _pendingLink = [address copy];
        return YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self openLink:address]; });
    return YES;
}

- (void)openLink:(NSString *)address {
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaOpenLinkNotification object:self
                                                      userInfo:[NSDictionary dictionaryWithObject:address forKey:@"url"]];
}

/* the icon the person chose on the color of the screen under it, light or dark; the launch image of a jailbroken phone is drawn with the same icon and color (see
   ExteriaAppIconRefreshLaunchImages), so the start is one splash and not a swap */
- (void)showSplashSignedIn:(BOOL)signedIn {
    /* before ios 8 a window subview does not rotate with the root controller */
    UIView *host = _navigation.view ? _navigation.view : self.window;
    _splash = [[ExteriaSplashView alloc] initWithFrame:host.bounds color:ExteriaColorScreen()];
    [host addSubview:_splash];
    if (signedIn) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissSplash)
                                                     name:ExteriaFirstScreenReadyNotification object:nil];
        [self performSelector:@selector(dismissSplash) withObject:nil afterDelay:SPLASH_LIMIT_SECONDS];
    } else {
        /* the welcome screen has nothing to wait for, so the splash only covers its first frame */
        [self performSelector:@selector(dismissSplash) withObject:nil afterDelay:0];
    }
}

- (void)dismissSplash {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissSplash) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaFirstScreenReadyNotification object:nil];
    [_splash dismiss];
    [_splash release];
    _splash = nil;
    ExteriaReleaseCheckStart(self.window);
}

/* the links follow the route: a tunnel that came up or dropped moves them to the other path */
- (void)shiroChanged:(NSNotification *)note {
    (void)note;
    /* a tunnel that did not open says so on a card of its own, wherever the person is: the app sends nothing while the tunnel is wanted and down */
    if (_shiro.state == ExteriaShiroStateFailed && _shiro.enabled) ExteriaShowShiroFailure(_shiro);
    if (_shiro.route == _shiroRoute) return;
    _shiroRoute = _shiro.route;
    [_session routeChanged];
}

- (void)proxyChanged:(NSNotification *)note {
    (void)note;
    [_session routeChanged];
    [_session reconnect];
    [_addSession routeChanged];
    [_addSession reconnect];
}

- (void)themeChangedForLaunchImages {
    ExteriaAppIconRefreshLaunchImages();
}

- (void)notifySettingsChanged:(NSNotification *)note {
    (void)note;
    [_notifier settingsChanged];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    [_passcodeLock cover];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [_passcodeLock noteLeave];
    /* what was counted since the last tick is kept before the system may end the app */
    ExteriaTrafficFlush();
    [_notifier applicationDidEnterBackground:application];
    /* the system suspends the process at once, wherever the session thread is */
    __block UIBackgroundTaskIdentifier hold = UIBackgroundTaskInvalid;
    void (^endHold)(void) = ^{
        if (hold == UIBackgroundTaskInvalid) return;
        [application endBackgroundTask:hold];
        hold = UIBackgroundTaskInvalid;
    };
    hold = [application beginBackgroundTaskWithExpirationHandler:endHold];
    [_session afterPendingWork:endHold];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [_passcodeLock evaluateReturn];
    [_notifier applicationDidBecomeActive:application];
    ExteriaPowerNoticeStart();
}

/* the system's wake for a look, every so often on ios 7 and later: the notifier reads the chat list and posts what is new */
/* UIBackgroundFetchResult is an NSUInteger, which the sdk of the armv7 slice does not name and the arm64 one does */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-parameter-types"
- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(NSUInteger result))completionHandler {
    (void)application;
    [_notifier performFetchWithCompletion:completionHandler];
}
#pragma clang diagnostic pop

/* a tap on a notification while the app runs */
- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    /* one that arrives while the app is on screen is not a tap, and must not pull the person into another chat */
    if (application.applicationState == UIApplicationStateActive) return;
    [_notifier handleLocalNotification:notification];
}

/* the headset and lock screen buttons of systems before ios 7.1, where they come as events to the responder chain, which ends here */
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    switch (event.subtype) {
    case UIEventSubtypeRemoteControlPlay:
        if (player.state == ExteriaMusicStatePaused) [player togglePause];
        break;
    case UIEventSubtypeRemoteControlPause:
        [player pause];
        break;
    case UIEventSubtypeRemoteControlTogglePlayPause:
        [player togglePause];
        break;
    case UIEventSubtypeRemoteControlNextTrack:
        [player next];
        break;
    case UIEventSubtypeRemoteControlPreviousTrack:
        [player previous];
        break;
    default:
        break;
    }
}

/* a switch of the theme builds the main screens again, and what is pushed over them would keep the old colors, so
   the automatic night theme waits for the person to be on the list itself */
- (BOOL)nightMayRebuildScreens {
    if (_navigation.viewControllers.count != 1 || self.window.rootViewController.presentedViewController) return NO;
    UIViewController *top = _navigation.topViewController;
    if ([top isKindOfClass:[ExteriaSplitController class]]) return [(ExteriaSplitController *)top canRebuildForTheme];
    return [top isKindOfClass:[ExteriaMainController class]];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    /* the link gave up while the app slept, so the first sight of it again tries once more */
    [_session reconnect];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_ghostTimer invalidate];
    [_callBarTimer invalidate];
    [_callBarTimer release];
    [_callBarSnapshot release];
    [_callBar release];
    [_activeAccount release];
    [_addName release];
    [_addSession release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_splash release];
    ExteriaNightStop();
    [_notifier stop];
    [_backSwipe release];
    [_passcodeLock release];
    [_notifier release];
    [_session stop];
    _session.delegate = nil;
    _session.callDelegate = nil;
    _session.groupCallDelegate = nil;
    _session.shiro = nil;
    ExteriaShiroSetActive(nil);
    [_shiro release];
    [_callScreen release];
    [_groupPresenter release];
    [_pendingCall release];
    [_callAvatars release];
    [_callMedia release];
    [_window release];
    [_navigation release];
    [_countries release];
    [_session release];
    [_login release];
    [super dealloc];
}

#pragma mark screens

/* the screens before the login are light only */
- (UIViewController *)makeWelcomeController {
    /* the welcome screen and the login after it wear the style the person chose, light until they choose */
    ExteriaThemeApplyStored();
    /* the classic bars are dark, but the login of that style has none, so its status bar follows the color of the screen */
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        [application setStatusBarStyle:ExteriaThemeIsDark() ? (UIStatusBarStyle)1 : UIStatusBarStyleDefault animated:NO];
    }
    ExteriaWelcomeController *welcome = [[[ExteriaWelcomeController alloc] init] autorelease];
    welcome.delegate = self;
    welcome.shiro = _shiro;
    return welcome;
}

/* ghost mode keeps the account offline: the server counts a connection in use as online, so the status is sent again every half minute */
- (void)ghostTick {
    if (!ExteriaChatFlagGet(ExteriaChatFlagGhostOffline) || ![ExteriaSession hasAccountInDirectory:ExteriaAccountDirectory(_activeAccount)]) return;
    [_session sendOfflineStatus];
}

- (UIViewController *)makeMainController {
    ExteriaThemeApplyStored();
    if (!_ghostTimer) _ghostTimer = [[NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(ghostTick) userInfo:nil repeats:YES] retain];
    /* the question about the crash of the last run comes a little after the screens are up; the link has time to come while the person reads it */
    ExteriaSession *reporting = [_session retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (reporting == _session) ExteriaProblemReportsStart(reporting);
        [reporting release];
    });
    ExteriaMainController *main = [[[ExteriaMainController alloc] initWithSession:_session] autorelease];
    main.delegate = self;
    /* the colors the server lists for names above the seven built in are kept for the chats to draw with; a failure leaves the ones kept before */
    [_session loadNameColors:^(NSArray *colors, NSString *errorName) {
        (void)colors;
        if (errorName) NSLog(@"exteria: the name colors did not load: %@", errorName);
    }];
    /* the list of accounts shows this one by name while another is connected */
    NSString *account = [[_activeAccount copy] autorelease];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        if (!items.count) {
            NSLog(@"exteria: the account record was not refreshed: %@", errorName);
            return;
        }
        ExteriaPerson *person = [items objectAtIndex:0];
        ExteriaAccountSetInfo(account, person.name, person.username, person.userId);
    }];
    /* what the account holds for notifications is copied to the phone, which the banners and the settings read */
    [_session syncNotifySettingsWithCompletion:^(NSString *errorName) {
        if (errorName) NSLog(@"exteria: the notification settings did not sync: %@", errorName);
    }];
    /* a tablet has room for the lists and what they open side by side */
    if (ExteriaIsPad()) return [[[ExteriaSplitController alloc] initWithMain:main] autorelease];
    return main;
}

/* both ways in need the country book, which the phone screen of either path uses */
- (BOOL)prepareLogin {
    return [self prepareLoginWithSession:_session];
}

- (BOOL)prepareLoginWithSession:(ExteriaSession *)session {
    if (!_countries) _countries = [[ExteriaCountryBook alloc] init];
    if (!_countries) {
        [self showNoticeTitle:NSLocalizedString(@"notice.countries.title", nil)
                      message:NSLocalizedString(@"notice.countries.message", nil)];
        return NO;
    }
    [_login release];
    _login = [[ExteriaLoginFlow alloc] initWithNavigation:_navigation session:session countryBook:_countries];
    _login.delegate = self;
    return YES;
}

- (void)welcomeControllerDidTapStart:(ExteriaWelcomeController *)controller {
    (void)controller;
    if ([self prepareLogin]) [_login begin];
}

- (void)welcomeControllerDidRequestQr:(ExteriaWelcomeController *)controller {
    (void)controller;
    if ([self prepareLogin]) [_login beginWithQr];
}

- (void)loginFlow:(ExteriaLoginFlow *)flow didAuthorizeUser:(long long)userId {
    [flow retain];
    ExteriaSession *retired = nil;
    if (_addSession) {
        /* the same person signed in twice would have two directories for one account */
        if (ExteriaAccountNameOfUser(userId, _addName)) {
            UIViewController *anchor = _addAnchor ? _addAnchor : [_navigation.viewControllers objectAtIndex:0];
            [self showNoticeTitle:nil message:NSLocalizedString(@"account.add.same", nil)];
            /* the server made a session for this login already; dropping the key here would leave it in the list of devices, so the session logs itself out first and
               its directory goes once that is done */
            ExteriaSession *duplicate = _addSession;
            NSString *duplicateName = _addName;
            _addSession = nil;
            _addName = nil;
            [self cancelAddAccount];
            [_navigation popToViewController:anchor animated:YES];
            duplicate.delegate = nil;
            duplicate.shiro = nil;
            [duplicate signOut:^(NSString *errorName) {
                if (errorName) NSLog(@"exteria: the duplicate login was not ended on the server: %@", errorName);
                [duplicate stop];
                ExteriaAccountRemove(duplicateName);
                [duplicate release];
                [duplicateName release];
            }];
            [flow release];
            return;
        }
        [_notifier stop];
        [_notifier release];
        retired = _session;
        _session = _addSession;
        _addSession = nil;
        _navigation.delegate = nil;
        _addAnchor = nil;
        [_activeAccount release];
        _activeAccount = _addName;
        _addName = nil;
        ExteriaAccountSetActive(_activeAccount);
        [self bindSession:_session];
        _notifier = [[ExteriaNotifier alloc] initWithSession:_session];
    }
    [_navigation setViewControllers:[NSArray arrayWithObject:[self makeMainController]] animated:YES];
    /* the flow gave up the session delegate when it finished; the app takes it back for later events */
    _session.delegate = self;
    [_notifier start];
    [_login release];
    _login = nil;
    [flow release];
    if (retired) {
        [self retireSession:retired];
        [retired release];
    }
    if (_pendingLink) {
        NSString *address = [_pendingLink autorelease];
        _pendingLink = nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [self openLink:address]; });
    }
}

#pragma mark main screen

- (void)mainController:(ExteriaMainController *)controller requestsSignOut:(void (^)(NSString *errorName))completion {
    (void)controller;
    [_session signOut:completion];
}

/* only events after the login reach here: a dropped session sends the user back to the welcome screen */
- (void)session:(ExteriaSession *)session didReceiveAuthEvent:(ExteriaAuthEvent *)event {
    (void)session;
    if (event.kind != ExteriaAuthEventLoggedOut) return;
    [_notifier stop];
    [_login release];
    _login = nil;
    /* another account signed in takes over; the last one leaves the welcome screen */
    NSString *gone = [[_activeAccount copy] autorelease];
    NSArray *left = ExteriaAccountNames();
    [self activateAccount:left.count ? [left objectAtIndex:0] : @""];
    ExteriaAccountRemove(gone);
}

#pragma mark accounts

- (void)bindSession:(ExteriaSession *)session {
    session.delegate = self;
    session.callDelegate = self;
    session.groupCallDelegate = _groupPresenter;
    session.shiro = _shiro;
}

/* the connection of an account that is no longer the active one is closed, so only one account is online */
- (void)retireSession:(ExteriaSession *)session {
    session.delegate = nil;
    session.callDelegate = nil;
    session.groupCallDelegate = nil;
    session.shiro = nil;
    [session stop];
}

/* makes the account the one with the connection, and shows its chats, or the welcome screen for one that is not signed in */
- (void)activateAccount:(NSString *)name {
    if (_callScreen || _groupPresenter.callIsShown || _addSession) return;
    UIViewController *shown = _navigation.presentedViewController;
    if (shown) [_navigation dismissViewControllerAnimated:NO completion:nil];
    [_notifier stop];
    [_notifier release];
    ExteriaSession *retired = _session;
    [_activeAccount release];
    _activeAccount = [name copy];
    ExteriaAccountSetActive(name);
    _session = [[ExteriaSession alloc] initWithDirectory:ExteriaAccountDirectory(name)];
    [self bindSession:_session];
    [_session start];
    _notifier = [[ExteriaNotifier alloc] initWithSession:_session];
    BOOL signedIn = [ExteriaSession hasAccountInDirectory:ExteriaAccountDirectory(name)];
    UIViewController *root;
    if (signedIn) {
        [_notifier start];
        root = [self makeMainController];
    } else {
        root = [self makeWelcomeController];
    }
    [_navigation setViewControllers:[NSArray arrayWithObject:root] animated:YES];
    [self retireSession:retired];
    [retired release];
}

- (void)accountSwitchRequested:(NSNotification *)note {
    NSString *name = [note.userInfo objectForKey:@"name"];
    if (!name || [name isEqualToString:_activeAccount]) return;
    if (![ExteriaSession hasAccountInDirectory:ExteriaAccountDirectory(name)]) return;
    [self activateAccount:name];
}

/* the phone screen is pushed over the screens the person is on, with a session of its own in a new directory; going back from it gives the directory up */
- (void)accountAddRequested:(NSNotification *)note {
    (void)note;
    if (_addSession || _callScreen) return;
    NSString *name = ExteriaAccountMakeNew();
    if (!name) {
        [self showNoticeTitle:nil message:NSLocalizedString(@"account.add.failed", nil)];
        return;
    }
    _addName = [name copy];
    _addSession = [[ExteriaSession alloc] initWithDirectory:ExteriaAccountDirectory(name)];
    _addSession.shiro = _shiro;
    [_addSession start];
    if (![self prepareLoginWithSession:_addSession]) {
        [self cancelAddAccount];
        return;
    }
    _addAnchor = _navigation.topViewController;
    _navigation.delegate = self;
    [_login begin];
}

- (void)cancelAddAccount {
    _navigation.delegate = nil;
    _addAnchor = nil;
    [_login release];
    _login = nil;
    if (_addSession) {
        _addSession.shiro = nil;
        [_addSession stop];
        [_addSession release];
        _addSession = nil;
    }
    if (_addName) ExteriaAccountRemove(_addName);
    [_addName release];
    _addName = nil;
}

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    (void)navigationController;
    (void)animated;
    if (_addSession && viewController == _addAnchor) [self cancelAddAccount];
}

/* a call that begins or rings gets the full screen over whatever is open; later snapshots only update it */
- (void)session:(ExteriaSession *)session callDidChange:(ExteriaCall *)call {
    if (_callScreen && _callScreen.finishing && call.callId != _callScreen.callId) {
        [_pendingCall release];
        _pendingCall = [call retain];
        return;
    }
    if (!_callScreen && call.phase == ExteriaCallPhaseEnded && call.end == ExteriaCallEndNone) return;
    if (call != _callBarSnapshot) {
        [_callBarSnapshot release];
        _callBarSnapshot = [call retain];
    }
    if (!_callScreen) {
        if (!_callAvatars) {
            NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSString *directory = [[caches stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"avatars"];
            _callAvatars = [[ExteriaAvatarCache alloc] initWithSession:session directory:directory];
            _callMedia = [[ExteriaMediaCache alloc] initWithSession:session directory:[[caches stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"media"]];
        }
        _callScreen = [[ExteriaCallController alloc] initWithSession:session];
        _callScreen.avatars = _callAvatars;
        _callScreen.media = _callMedia;
        _callScreen.photo = call.photo;
        /* not retained by the block: the screen holds the block */
        __block ExteriaCallController *shown = _callScreen;
        _callScreen.onMinimize = ^{ [self minimizeCall]; };
        _callScreen.onFinish = ^{
            if (_callScreen != shown) return;
            [self hideCallBar];
            _callMinimizing = NO;
            [_callBarSnapshot release];
            _callBarSnapshot = nil;
            [_callScreen release];
            _callScreen = nil;
            ExteriaCall *next = [[_pendingCall retain] autorelease];
            [_pendingCall release];
            _pendingCall = nil;
            if (next) [self session:_session callDidChange:next];
        };
        UIViewController *top = _navigation;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:_callScreen animated:YES completion:nil];
    }
    if (_callMinimized) {
        if (call.phase == ExteriaCallPhaseEnded) [self hideCallBar];
        else [self refreshCallBarWithCall:call];
    }
    [_callScreen updateWithCall:call];
}

#pragma mark minimized call

- (void)minimizeCall {
    if (!_callScreen || _callMinimized || _callScreen.finishing) return;
    _callMinimized = YES;
    _callMinimizing = YES;
    ExteriaCallController *screen = _callScreen;
    [screen dismissViewControllerAnimated:YES completion:^{
        if (_callScreen != screen) return;
        _callMinimizing = NO;
        if (_callMinimized) [self showCallBar];
    }];
}

- (void)restoreCallAnimated:(BOOL)animated {
    if (!_callScreen || !_callMinimized) return;
    if (_callMinimizing) return;
    _callMinimized = NO;
    [self hideCallBar];
    UIViewController *top = _navigation;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:_callScreen animated:animated completion:nil];
}

- (void)callBarTapped {
    [self restoreCallAnimated:YES];
}

- (void)showCallBar {
    if (!_callBar) {
        _callBar = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _callBar.backgroundColor = [UIColor colorWithRed:0.18f green:0.72f blue:0.35f alpha:1];
        _callBar.layer.cornerRadius = 16;
        _callBar.titleLabel.font = ExteriaFontSemibold(13);
        _callBar.titleLabel.lineBreakMode = UILineBreakModeTailTruncation;
        _callBar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [_callBar addTarget:self action:@selector(callBarTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    [self refreshCallBarWithCall:_callBarSnapshot];
    if (!_callBarTimer) _callBarTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(callBarTick:) userInfo:nil repeats:YES] retain];
    UIView *host = _navigation.view;
    CGFloat width = MIN(MAX(0, host.bounds.size.width - 104), 240);
    _callBar.frame = CGRectMake(floor((host.bounds.size.width - width) / 2), ExteriaStatusBarHeight() + 4, width, 32);
    [host addSubview:_callBar];
}

- (void)refreshCallBarWithCall:(ExteriaCall *)call {
    NSString *name = call.peerName.length ? call.peerName : @"";
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"call.return", nil), name];
    if (call.phase == ExteriaCallPhaseActive && call.startedAt > 0) {
        NSInteger seconds = MAX(0, (NSInteger)([NSDate timeIntervalSinceReferenceDate] - call.startedAt));
        NSString *time = seconds >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(seconds / 3600), (long)(seconds / 60 % 60), (long)(seconds % 60)]
                                         : [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
        title = [NSString stringWithFormat:@"%@ · %@", name, time];
    } else if (call.phase == ExteriaCallPhaseReconnecting) {
        title = NSLocalizedString(@"call.reconnecting", nil);
    }
    [_callBar setTitle:title forState:UIControlStateNormal];
    _callBar.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"call.return", nil), name];
}

- (void)callBarTick:(NSTimer *)timer {
    (void)timer;
    [self refreshCallBarWithCall:_callBarSnapshot];
}

- (void)hideCallBar {
    _callMinimized = NO;
    [_callBarTimer invalidate];
    [_callBarTimer release];
    _callBarTimer = nil;
    [_callBar removeFromSuperview];
}

- (void)showNoticeTitle:(NSString *)title message:(NSString *)message {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:title message:message delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

@end
