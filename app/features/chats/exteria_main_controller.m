#import "exteria_main_controller.h"
#import "exteria_chat_settings.h"

#import "exteria_calls_controller.h"
#import "exteria_classic_calls_controller.h"
#import "exteria_classic_chats_controller.h"
#import "exteria_classic_chrome.h"
#import "exteria_classic_contacts_controller.h"
#import "exteria_classic_profile_controller.h"
#import "exteria_chat_controller.h"
#import "exteria_community_screen.h"
#import "exteria_topics_screen.h"
#import "exteria_contacts_controller.h"
#import "exteria_language.h"
#import "exteria_lite_mode.h"
#import "exteria_link_router.h"
#import "exteria_developers.h"
#import "exteria_notifier.h"
#import "exteria_person.h"
#import "exteria_platform.h"
#import "exteria_profile_controller.h"
#import "exteria_settings_controller.h"
#import "exteria_settings_kit.h"
#import "exteria_split_controller.h"
#import "exteria_theme.h"
#import "exteria_theme_busy_view.h"
#import "exteria_wave_background_view.h"

#import <QuartzCore/QuartzCore.h>

/* what a tab of the bar shows; the layout of the person puts four of these in a row */
enum {
    ExteriaTabChats = EXTERIA_TAB_CHATS,
    ExteriaTabContacts = EXTERIA_TAB_CONTACTS,
    ExteriaTabSettings = EXTERIA_TAB_SETTINGS,
    ExteriaTabProfile = EXTERIA_TAB_PROFILE,
    ExteriaTabCalls = EXTERIA_TAB_CALLS
};
#define ExteriaTabCount EXTERIA_TAB_SLOTS

/* the four tabs of a layout, in the order of the bar */
static void ExteriaTabKinds(ExteriaTabLayout layout, NSInteger kinds[ExteriaTabCount]) {
    int order[EXTERIA_TAB_SLOTS];
    (void)layout;
    ExteriaTabOrderLoad(order);
    for (NSUInteger i = 0; i < EXTERIA_TAB_SLOTS; ++i) kinds[i] = order[i];
}

static NSInteger ExteriaTabIndexOfKind(const NSInteger kinds[ExteriaTabCount], NSInteger kind) {
    for (NSInteger i = 0; i < ExteriaTabCount; ++i) if (kinds[i] == kind) return i;
    return -1;
}

static NSString *ExteriaTabTitle(NSInteger kind) {
    static NSString *const keys[] = {@"tab.chats", @"tab.contacts", @"tab.settings", @"tab.profile", @"tab.calls"};
    return NSLocalizedString(keys[kind], nil);
}

static ExteriaSymbol ExteriaTabSymbol(NSInteger kind) {
    static const ExteriaSymbol symbols[] = {ExteriaSymbolChats, ExteriaSymbolPerson, ExteriaSymbolGear, ExteriaSymbolSmiley, ExteriaSymbolPhone};
    return symbols[kind];
}

#define CLASSIC_BADGE_TAG 0x4258

/* the count sits on the right of the first icon, whatever the width of the bar after a rotation */
static void ExteriaPlaceClassicBadge(UITabBar *bar, CGFloat width, NSInteger index) {
    UIView *badge = [bar viewWithTag:CLASSIC_BADGE_TAG];
    if (!badge) return;
    badge.frame = CGRectMake(floor(width * (CGFloat)(2 * index + 1) / (CGFloat)(ExteriaTabCount * 2)) + 4, 1, badge.frame.size.width, badge.frame.size.height);
}

@interface ExteriaMainController () <UITabBarControllerDelegate> {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaLinkRouter *_linkRouter;
    ExteriaTabBar *_tabBar;
    NSMutableArray *_screens;
    UIViewController *_current;
    UITabBarController *_classicTabs;
    UIImageView *_veil;
    ExteriaThemeBusyView *_busy;
    BOOL _busyShown;
    CGPoint _revealOrigin;
    NSInteger _currentTab;
    /* the kinds of the tabs the bar was built with, so a change of layout knows which tab the person stood on */
    NSInteger _kinds[ExteriaTabCount];
}
@end

@implementation ExteriaMainController

@synthesize delegate = _delegate;
@synthesize detailHost = _detailHost;

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    /* child bars own the status area, ios 5 must not reserve it again in each container */
    self.wantsFullScreenLayout = YES;
    _session = [session retain];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *root = [caches stringByAppendingPathComponent:@"Exteria"];
    _avatars = [[ExteriaAvatarCache alloc] initWithSession:session directory:[root stringByAppendingPathComponent:@"avatars"]];
    _media = [[ExteriaMediaCache alloc] initWithSession:session directory:[root stringByAppendingPathComponent:@"media"]];
    /* the files past the days the person chose to keep them go when the screens start */
    [_media removeFilesOlderThanDays:ExteriaCacheKeepDays()];
    _stickers = [[ExteriaStickerLibrary alloc] initWithSession:session];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_veil removeFromSuperview];
    [_veil release];
    [_busy stopAnimating];
    [_busy removeFromSuperview];
    [_busy release];
    [self releaseContent];
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    _linkRouter.anchor = nil;
    [_linkRouter release];
    [super dealloc];
}

/* the screens and the bar go together, so the theme change can build both again */
- (void)releaseContent {
    for (UIViewController *screen in _screens) {
        if ([screen isKindOfClass:[ExteriaChatsController class]]) [(ExteriaChatsController *)screen setChatsDelegate:nil];
        if ([screen isKindOfClass:[ExteriaProfileController class]]) [(ExteriaProfileController *)screen setDelegate:nil];
        if ([screen isKindOfClass:[ExteriaSettingsController class]]) [(ExteriaSettingsController *)screen setSignOutHandler:nil];
    }
    /* the handlers capture this controller, and the classic screens are not in _screens */
    for (UINavigationController *navigation in _classicTabs.viewControllers) {
        id root = navigation.viewControllers.count ? [navigation.viewControllers objectAtIndex:0] : nil;
        if ([root respondsToSelector:@selector(setSignOutHandler:)]) [root setSignOutHandler:nil];
    }
    [_classicTabs willMoveToParentViewController:nil];
    [_classicTabs.view removeFromSuperview];
    [_classicTabs removeFromParentViewController];
    [_classicTabs release];
    _classicTabs = nil;
    _tabBar.delegate = nil;
    [_tabBar removeFromSuperview];
    [_tabBar release];
    _tabBar = nil;
    [_screens release];
    _screens = nil;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:)
                                                 name:ExteriaThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tabOrderChanged:)
                                                 name:ExteriaTabOrderDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged)
                                                 name:ExteriaLanguageDidChangeNotification object:nil];
    [self buildContentWithTab:-1];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openTeamPerson:) name:ExteriaOpenTeamPersonNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openChatRequested:) name:ExteriaOpenChatNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openLinkRequested:) name:ExteriaOpenLinkNotification object:nil];
}

/* an address from outside the screens: it opens over the tab that is up, as a tap on it inside a chat would */
- (void)openLinkRequested:(NSNotification *)note {
    NSString *url = [note.userInfo objectForKey:@"url"];
    if (![url isKindOfClass:[NSString class]] || !url.length) return;
    if (!_linkRouter) _linkRouter = [[ExteriaLinkRouter alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers];
    UIViewController *anchor = self;
    if (_classicTabs) anchor = [(UINavigationController *)_classicTabs.selectedViewController topViewController];
    _linkRouter.anchor = anchor;
    [_linkRouter openLink:url];
}

- (void)openTeamPerson:(NSNotification *)note {
    ExteriaPerson *person = [note.userInfo objectForKey:@"person"];
    ExteriaDialog *dialog = [ExteriaDialog dialogWithPerson:person];
    if (!dialog || !exteria_team_member_for_id(person.userId)) return;
    if (!_linkRouter) _linkRouter = [[ExteriaLinkRouter alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers];
    UIViewController *anchor = self;
    if (_classicTabs) anchor = [(UINavigationController *)_classicTabs.selectedViewController topViewController];
    _linkRouter.anchor = anchor;
    [_linkRouter openDialog:dialog person:person draft:nil startParam:nil];
}

/* a notification was tapped: the chat opens over the list, whichever screen was up */
- (void)openChatRequested:(NSNotification *)note {
    int32_t kind = (int32_t)[[note.userInfo objectForKey:@"kind"] intValue];
    long long peer = [[note.userInfo objectForKey:@"peer"] longLongValue];
    [self retain];
    [_session loadDialogs:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (!items) {
            NSLog(@"exteria: the chat of the notification could not be looked up: %@", errorName);
            return;
        }
        for (ExteriaDialog *dialog in items) {
            if (!dialog.folder && dialog.peerKind == kind && dialog.peerId == peer) {
                [self openDialog:dialog];
                return;
            }
        }
        NSLog(@"exteria: the chat %lld of the notification is not in the list", peer);
    }];
}

- (void)openDialog:(ExteriaDialog *)dialog {
    UIViewController *chat = dialog.community ? ExteriaCommunityScreen(_session, dialog, nil, _avatars, _media, _stickers, nil)
        : dialog.forum ? ExteriaTopicsScreen(_session, dialog, _avatars, _media, _stickers, nil)
        : [[[ExteriaChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    if (_classicTabs) {
        _classicTabs.selectedIndex = (NSUInteger)MAX(0, ExteriaTabIndexOfKind(_kinds, ExteriaTabChats));
        UINavigationController *navigation = (UINavigationController *)_classicTabs.selectedViewController;
        [navigation popToRootViewControllerAnimated:NO];
        [navigation pushViewController:chat animated:NO];
        return;
    }
    [self.navigationController popToViewController:self animated:NO];
    [self.navigationController pushViewController:chat animated:NO];
}

/* the classic style is the system's own tab bar over navigation controllers, each with a navigation bar of its own; the
   screens are built when the tab bar is, since it asks each of them for its title at once */
- (void)buildClassicWithTab:(NSInteger)tab {
    ExteriaClassicChatsController *chats = nil;
    NSMutableArray *screens = [NSMutableArray array], *navigations = [NSMutableArray array];
    for (NSInteger i = 0; i < ExteriaTabCount; ++i) {
        UIViewController *screen = nil;
        switch (_kinds[i]) {
        case ExteriaTabChats:
            chats = [[[ExteriaClassicChatsController alloc] initWithSession:_session folderId:0 avatars:_avatars media:_media stickers:_stickers] autorelease];
            screen = chats;
            break;
        case ExteriaTabContacts:
            screen = [[[ExteriaClassicContactsController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers] autorelease];
            break;
        case ExteriaTabCalls:
            screen = [[[ExteriaClassicCallsController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers] autorelease];
            break;
        case ExteriaTabSettings: {
            /* the settings are one screen in both styles: the grouped table draws the same sections the modern cards do */
            ExteriaSettingsController *settings = [[[ExteriaSettingsController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
            settings.signOutHandler = ^(void (^completion)(NSString *errorName)) { [_delegate mainController:self requestsSignOut:completion]; };
            screen = settings;
            break;
        }
        default: {
            ExteriaClassicProfileController *profile = [[[ExteriaClassicProfileController alloc] initWithSession:_session avatars:_avatars] autorelease];
            profile.media = _media;
            profile.stickerLibrary = _stickers;
            profile.signOutHandler = ^(void (^completion)(NSString *errorName)) { [_delegate mainController:self requestsSignOut:completion]; };
            screen = profile;
            break;
        }
        }
        [screens addObject:screen];
    }
    for (NSUInteger i = 0; i < screens.count; ++i) {
        ExteriaSymbol symbol = ExteriaTabSymbol(_kinds[i]);
        UINavigationController *navigation = [[[ExteriaSplitNavigationController alloc] initWithRootViewController:[screens objectAtIndex:i]] autorelease];
        [(ExteriaSplitNavigationController *)navigation setDetailHost:_detailHost];
        ExteriaClassicStyleNavigationBar(navigation.navigationBar);
        navigation.tabBarItem = [[[UITabBarItem alloc] initWithTitle:ExteriaTabTitle(_kinds[i]) image:ExteriaClassicTabImage(symbol) tag:(NSInteger)i] autorelease];
        ExteriaClassicStyleTabItem(navigation.tabBarItem, symbol);
        [navigations addObject:navigation];
    }
    _classicTabs = [[UITabBarController alloc] init];
    _classicTabs.wantsFullScreenLayout = YES;
    _classicTabs.delegate = self;
    _classicTabs.viewControllers = navigations;
    _classicTabs.selectedIndex = (NSUInteger)tab;
    ExteriaClassicStyleTabBar(_classicTabs.tabBar);
    /* the system badge is red on ios 5 to 9 and takes no color before ios 10, so the count is a label of our own in the accent */
    UITabBar *bar = _classicTabs.tabBar;
    chats.unreadHandler = ^(NSInteger total) {
        [[bar viewWithTag:CLASSIC_BADGE_TAG] removeFromSuperview];
        if (total <= 0) return;
        UILabel *badge = ExteriaClassicBadge(total > 999 ? @"999+" : [NSString stringWithFormat:@"%ld", (long)total], NO);
        badge.tag = CLASSIC_BADGE_TAG;
        badge.backgroundColor = ExteriaColorAccent();
        badge.userInteractionEnabled = NO;
        [bar addSubview:badge];
        ExteriaPlaceClassicBadge(bar, bar.bounds.size.width, ExteriaTabIndexOfKind(_kinds, ExteriaTabChats));
    };
    [self addChildViewController:_classicTabs];
    _classicTabs.view.frame = self.view.bounds;
    _classicTabs.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_classicTabs.view];
    [_classicTabs didMoveToParentViewController:self];

    /* the profile tab, when the layout has one, wears the profile photo once it is here */
    NSInteger profileIndex = ExteriaTabIndexOfKind(_kinds, ExteriaTabProfile);
    if (profileIndex < 0) return;
    UITabBarItem *profileItem = ((UIViewController *)[navigations objectAtIndex:(NSUInteger)profileIndex]).tabBarItem;
    /* the photo of the last time is on the tab before the answer comes */
    ExteriaPerson *known = [_session ownPerson];
    if (known.photo) {
        [_avatars pinPhoto:known.photo];
        [_avatars loadImageForPhoto:known.photo completion:^(UIImage *photo) {
            if (!photo) return;
            UIImage *tab = ExteriaClassicProfileTabImage(photo);
            if ([profileItem respondsToSelector:@selector(setFinishedSelectedImage:withFinishedUnselectedImage:)]) {
                [profileItem setFinishedSelectedImage:tab withFinishedUnselectedImage:tab];
            }
        }];
    }
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        if (!items) {
            NSLog(@"exteria: profile tab did not load: %@", errorName);
            return;
        }
        ExteriaPerson *person = [items objectAtIndex:0];
        [_avatars pinPhoto:person.photo];
        ExteriaLiteSetPremium(ExteriaPremiumEffective(person.premium));
        if (!person.photo) return;
        [_avatars loadImageForPhoto:person.photo completion:^(UIImage *photo) {
            if (!photo) return;
            UIImage *tab = ExteriaClassicProfileTabImage(photo);
            if ([profileItem respondsToSelector:@selector(setFinishedSelectedImage:withFinishedUnselectedImage:)]) {
                [profileItem setFinishedSelectedImage:tab withFinishedUnselectedImage:tab];
            }
        }];
    }];
}

/* the system tab bar swaps its screens at once; a push transition on the container of the screens, not on the bar, gives the same
   sideways slide the modern tabs have */
- (BOOL)tabBarController:(UITabBarController *)tabs shouldSelectViewController:(UIViewController *)screen {
    NSUInteger from = tabs.selectedIndex, to = [tabs.viewControllers indexOfObject:screen];
    if (from == to || to == NSNotFound) return YES;
    for (UIView *container in tabs.view.subviews) {
        if ([container isKindOfClass:[UITabBar class]]) continue;
        CATransition *slide = [CATransition animation];
        slide.type = kCATransitionPush;
        slide.subtype = to > from ? kCATransitionFromRight : kCATransitionFromLeft;
        slide.duration = 0.3;
        slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [container.layer addAnimation:slide forKey:@"tab"];
        break;
    }
    return YES;
}

/* tab is the place in the bar to land on, or -1 for the chats */
- (void)buildContentWithTab:(NSInteger)tab {
    ExteriaTabKinds(ExteriaTabLayoutStored(), _kinds);
    if (tab < 0 || tab >= ExteriaTabCount) tab = MAX(0, ExteriaTabIndexOfKind(_kinds, ExteriaTabChats));
    if (ExteriaThemeIsClassic()) {
        [self buildClassicWithTab:tab];
        return;
    }
    UIView *root = self.view;
    /* screens are made on demand, so a tab nobody opens never asks the server for anything */
    _screens = [[NSMutableArray alloc] init];
    for (int i = 0; i < ExteriaTabCount; ++i) [_screens addObject:[NSNull null]];

    NSMutableArray *titles = [NSMutableArray array], *symbols = [NSMutableArray array];
    for (NSInteger i = 0; i < ExteriaTabCount; ++i) {
        [titles addObject:ExteriaTabTitle(_kinds[i])];
        /* the profile tab shows the photo of the person, so it has no symbol of its own */
        [symbols addObject:_kinds[i] == ExteriaTabProfile ? (id)[NSNull null] : (id)[NSNumber numberWithInt:ExteriaTabSymbol(_kinds[i])]];
    }
    _tabBar = [[ExteriaTabBar alloc] initWithTitles:titles symbols:symbols];
    _tabBar.delegate = self;
    /* a rebuild lands on the settings tab, and the bar has to say so or the next tap on settings is taken for no change */
    _tabBar.selectedIndex = tab;
    _currentTab = tab;
    [root addSubview:_tabBar];
    [self showTab:tab];
    [self loadProfileTab];
}

/* the root view turns with the interface on ios 5 through 7 */
- (UIView *)themeHost {
    return ExteriaOverlayHost();
}

- (void)themeChanged:(NSNotification *)note {
    NSValue *origin = [note.userInfo objectForKey:ExteriaThemeOriginKey];
    UIView *host = [self themeHost];
    _revealOrigin = [origin isKindOfClass:[NSValue class]] && host ? [host convertPoint:[origin CGPointValue] fromView:nil] : CGPointMake(-1, -1);
    [self coverWithSnapshot];
    [self showBusyOverVeil];
}

- (void)tabOrderChanged:(NSNotification *)note {
    (void)note;
    NSArray *pages = [self pagesToRestore];
    BOOL wasClassic = _classicTabs != nil;
    [self rebuildContent];
    [self restorePages:pages wasClassic:wasClassic];
}

/* the old screen darkens a little and the duck paints while the screens are made again, which keeps the main
   thread busy and would otherwise look like a freeze */
- (void)showBusyOverVeil {
    UIView *window = [self themeHost];
    if (!window || !_veil || _busyShown) {
        [self performSelector:@selector(rebuildForTheme) withObject:nil afterDelay:0];
        return;
    }
    /* the view and its parsed duck are kept from one change to the next: the first change would otherwise wait for the parse */
    if (!_busy) _busy = [[ExteriaThemeBusyView alloc] initWithFrame:window.bounds];
    _busyShown = YES;
    _busy.frame = window.bounds;
    _busy.alpha = ExteriaReduceMotionEnabled() ? 1 : 0;
    [window addSubview:_busy];
    [_busy startAnimating];
    [self retain];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.22 animations:^{ _busy.alpha = 1; } completion:^(BOOL finished) {
        (void)finished;
        [_busy whenReady:^{
            [self rebuildForTheme];
            [self autorelease];
        }];
    }];
}

/* the circle of the new colors opens over the picture, and the darkening and the duck go as it spreads */
- (void)dismissBusy {
    if (!_busyShown) return;
    _busyShown = NO;
    ExteriaThemeBusyView *busy = _busy;
    /* the view is kept, so UIKit never reads one that is gone after the animation */
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.3 animations:^{ busy.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        if (_busyShown) return;
        [busy stopAnimating];
        [busy removeFromSuperview];
    }];
}

static void ExteriaCollectWaves(UIView *view, NSMutableArray *waves) {
    if ([view isKindOfClass:[ExteriaWaveBackgroundView class]]) [waves addObject:view];
    for (UIView *child in view.subviews) ExteriaCollectWaves(child, waves);
}

/* the old screen stays above the rebuild as a picture, so the swap never shows a half built tab bar */
- (void)coverWithSnapshot {
    UIView *window = [self themeHost];
    if (!window || _veil) return;
    /* the waves are masked layers, which a picture of the window does not draw; they draw themselves for it */
    NSMutableArray *waves = [NSMutableArray array];
    ExteriaCollectWaves(window, waves);
    for (ExteriaWaveBackgroundView *wave in waves) [wave beginSnapshot];
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 0);
    [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    for (ExteriaWaveBackgroundView *wave in waves) [wave endSnapshot];
    _veil = [[UIImageView alloc] initWithImage:picture];
    _veil.frame = window.bounds;
    _veil.userInteractionEnabled = YES;
    [window addSubview:_veil];
}

/* a circle of the new theme grows from the settings switch and eats the picture of the old one */
- (void)revealBehindVeil {
    UIImageView *veil = _veil;
    _veil = nil;
    [self dismissBusy];
    if (!veil) return;
    CGRect bounds = veil.bounds;
    /* the screen that asked for the change says where it was touched; the switch of the settings tab asks without a point */
    CGPoint origin = _revealOrigin.x >= 0 ? _revealOrigin : CGPointMake(bounds.size.width - 48, 150);
    CGFloat reach = hypot(MAX(origin.x, bounds.size.width - origin.x), MAX(origin.y, bounds.size.height - origin.y));
    CGPathRef (^hole)(CGFloat) = ^CGPathRef(CGFloat radius) {
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, bounds);
        CGPathAddEllipseInRect(path, NULL, CGRectMake(origin.x - radius, origin.y - radius, 2 * radius, 2 * radius));
        return path;
    };
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = bounds;
    mask.fillRule = kCAFillRuleEvenOdd;
    CGPathRef from = hole(0.01), to = hole(reach);
    mask.path = to;
    veil.layer.mask = mask;
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.6];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [CATransaction setCompletionBlock:^{
        [veil removeFromSuperview];
        [veil release];
    }];
    CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"path"];
    grow.fromValue = (id)from;
    grow.toValue = (id)to;
    [mask addAnimation:grow forKey:@"reveal"];
    [CATransaction commit];
    CGPathRelease(from);
    CGPathRelease(to);
}

/* the texts are read when a view is built, so a new language needs new screens too */
- (void)languageChanged {
    [self coverWithSnapshot];
    [self performSelector:@selector(rebuildForLanguage) withObject:nil afterDelay:0];
}

- (void)fadeOutVeil {
    UIImageView *veil = _veil;
    _veil = nil;
    if (!veil) return;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.25 animations:^{ veil.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [veil removeFromSuperview];
        /* UIKit still reads the view after its completion block returns, so the last reference goes at the end of the pass and not here */
        [veil autorelease];
    }];
}

- (void)rebuildForLanguage {
    [self rebuildContent];
    [self fadeOutVeil];
}

/* colors are read when a view is built, so a new palette needs new screens; the settings tab is built again
   and shown, because the person is standing on it */
- (void)rebuildForTheme {
    NSArray *pages = [self pagesToRestore];
    BOOL wasClassic = _classicTabs != nil;
    [self rebuildContent];
    [self restorePages:pages wasClassic:wasClassic];
    /* the right pane rebuilds its own pages after the new style is active */
    [_detailHost styleDidChange:wasClassic || _classicTabs != nil];
    [self revealBehindVeil];
}

/* the pages pushed over the tab the person stands on */
- (NSArray *)pagesToRestore {
    if (_detailHost) return nil;
    BOOL involvesClassic = _classicTabs != nil || ExteriaThemeStoredClassic();
    if (!involvesClassic) return nil;
    UINavigationController *navigation = _classicTabs ? (UINavigationController *)_classicTabs.selectedViewController : self.navigationController;
    NSArray *all = navigation.viewControllers;
    NSUInteger from = _classicTabs ? 1 : [all indexOfObjectIdenticalTo:self] + 1;
    if (from == 0 || from >= all.count) return nil;
    return [NSArray arrayWithArray:[all subarrayWithRange:NSMakeRange(from, all.count - from)]];
}

/* the pages are made again after the screens, so they read the new colors */
- (void)restorePages:(NSArray *)pages wasClassic:(BOOL)wasClassic {
    if (!pages.count) return;
    if (!wasClassic) [self.navigationController popToViewController:self animated:NO];
    UINavigationController *navigation = _classicTabs ? (UINavigationController *)_classicTabs.selectedViewController : self.navigationController;
    for (UIViewController *old in pages) {
        if (![old respondsToSelector:@selector(controllerAfterThemeChange)]) break;
        UIViewController *again = [(id<ExteriaThemeRestorable>)old controllerAfterThemeChange];
        if (!again) break;
        [navigation pushViewController:again animated:NO];
    }
}

- (void)rebuildContent {
    /* the person stays on the tab they were on, which is settings when the switch there made the change */
    NSInteger tab = _classicTabs ? (NSInteger)_classicTabs.selectedIndex : _currentTab;
    /* a new layout may put the tab somewhere else, or have none of that kind: the settings are where the change was made, so they are the fallback */
    NSInteger kind = tab >= 0 && tab < ExteriaTabCount ? _kinds[tab] : ExteriaTabSettings;
    NSInteger next[ExteriaTabCount];
    ExteriaTabKinds(ExteriaTabLayoutStored(), next);
    tab = ExteriaTabIndexOfKind(next, kind);
    if (tab < 0) tab = ExteriaTabIndexOfKind(next, ExteriaTabSettings);
    ExteriaThemeApplyStored();
    if (_current) {
        [_current willMoveToParentViewController:nil];
        [_current beginAppearanceTransition:NO animated:NO];
        [_current.view removeFromSuperview];
        [_current endAppearanceTransition];
        [_current removeFromParentViewController];
        _current = nil;
    }
    [self releaseContent];
    self.view.backgroundColor = ExteriaColorScreen();
    [self buildContentWithTab:tab];
}

/* the last tab wears the profile photo, so the profile is fetched once for the tab bar as well */
- (void)loadProfileTab {
    NSInteger profileIndex = ExteriaTabIndexOfKind(_kinds, ExteriaTabProfile);
    /* the photo of the last time is on the tab before the answer comes */
    ExteriaPerson *known = [_session ownPerson];
    if (known && profileIndex >= 0) {
        [_avatars pinPhoto:known.photo];
        [_tabBar setAvatarInitials:known.initials seed:(NSUInteger)(known.userId % 1000003) photo:known.photo cache:_avatars forIndex:profileIndex];
    }
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        if (!items) {
            NSLog(@"exteria: profile tab did not load: %@", errorName);
            return;
        }
        ExteriaPerson *person = [items objectAtIndex:0];
        [_avatars pinPhoto:person.photo];
        ExteriaLiteSetPremium(ExteriaPremiumEffective(person.premium));
        if (profileIndex >= 0) [_tabBar setAvatarInitials:person.initials seed:(NSUInteger)(person.userId % 1000003) photo:person.photo cache:_avatars
                                                 forIndex:profileIndex];
    }];
}

- (BOOL)showsPlayerStrip {
    UIViewController *screen = _classicTabs ? [(UINavigationController *)_classicTabs.selectedViewController topViewController] : _current;
    return [screen isKindOfClass:[ExteriaChatsController class]] && [(ExteriaChatsController *)screen playerStripShowing];
}

- (UIViewController *)screenForTab:(NSInteger)tab {
    id existing = [_screens objectAtIndex:(NSUInteger)tab];
    if (existing != [NSNull null]) return existing;
    UIViewController *screen = nil;
    switch (_kinds[tab]) {
    case ExteriaTabChats: {
        ExteriaChatsController *chats = [[[ExteriaChatsController alloc] initWithSession:_session] autorelease];
        chats.chatsDelegate = self;
        chats.media = _media;
        chats.stickerLibrary = _stickers;
        screen = chats;
        break;
    }
    case ExteriaTabContacts: {
        ExteriaContactsController *contacts = [[[ExteriaContactsController alloc] initWithSession:_session] autorelease];
        contacts.media = _media;
        contacts.stickerLibrary = _stickers;
        screen = contacts;
        break;
    }
    case ExteriaTabCalls: {
        ExteriaCallsController *calls = [[[ExteriaCallsController alloc] initWithSession:_session] autorelease];
        calls.media = _media;
        calls.stickerLibrary = _stickers;
        screen = calls;
        break;
    }
    case ExteriaTabSettings: {
        ExteriaSettingsController *settings = [[[ExteriaSettingsController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
        settings.signOutHandler = ^(void (^completion)(NSString *errorName)) { [_delegate mainController:self requestsSignOut:completion]; };
        screen = settings;
        break;
    }
    default: {
        ExteriaProfileController *profile = [[[ExteriaProfileController alloc] initWithSession:_session] autorelease];
        profile.delegate = self;
        screen = profile;
        break;
    }
    }
    if ([screen isKindOfClass:[ExteriaListController class]]) [(ExteriaListController *)screen setAvatars:_avatars];
    else if ([screen isKindOfClass:[ExteriaProfileController class]]) {
        [(ExteriaProfileController *)screen setAvatars:_avatars];
        [(ExteriaProfileController *)screen setMedia:_media];
        [(ExteriaProfileController *)screen setStickerLibrary:_stickers];
    }
    [_screens replaceObjectAtIndex:(NSUInteger)tab withObject:screen];
    return screen;
}

- (void)setBottomInsetOf:(UIViewController *)screen to:(CGFloat)inset {
    if ([screen isKindOfClass:[ExteriaListController class]]) [(ExteriaListController *)screen setBottomInset:inset];
    else if ([screen isKindOfClass:[ExteriaSettingsController class]]) [(ExteriaSettingsController *)screen setBottomInset:inset];
    else if ([screen isKindOfClass:[ExteriaProfileController class]]) [(ExteriaProfileController *)screen setBottomInset:inset];
}

/* the tabs swap with a sideways slide in the direction of the tab bar: the new screen comes in from the side of its tab and the
   old one leaves towards the other */
- (void)showTab:(NSInteger)tab {
    UIViewController *next = [self screenForTab:tab];
    if (next == _current) return;
    UIView *leaving = nil;
    CGFloat direction = tab > _currentTab ? 1 : -1;
    if (_current) {
        [_current willMoveToParentViewController:nil];
        [_current beginAppearanceTransition:NO animated:NO];
        leaving = [_current.view retain];
        [_current endAppearanceTransition];
        [_current removeFromParentViewController];
    }
    _current = next;
    _currentTab = tab;
    [self addChildViewController:next];
    next.view.frame = self.view.bounds;
    next.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:next.view belowSubview:_tabBar];
    [next beginAppearanceTransition:YES animated:NO];
    [next endAppearanceTransition];
    [next didMoveToParentViewController:self];
    [self layoutTabBar];
    if (!leaving) return;
    CGFloat width = self.view.bounds.size.width;
    next.view.transform = CGAffineTransformMakeTranslation(direction * width, 0);
    self.view.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        next.view.transform = CGAffineTransformIdentity;
        leaving.transform = CGAffineTransformMakeTranslation(-direction * width, 0);
    } completion:^(BOOL finished) {
        (void)finished;
        [leaving removeFromSuperview];
        leaving.transform = CGAffineTransformIdentity;
        [leaving release];
        self.view.userInteractionEnabled = YES;
    }];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return ExteriaOrientationMask();
}
#pragma clang diagnostic pop

- (void)layoutTabBar {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat height = [ExteriaTabBar barHeight] + insets.bottom;
    _tabBar.frame = CGRectMake(0, size.height - height, size.width, height);
    _tabBar.itemArea = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_LIST);
    for (UIViewController *screen in _screens) {
        if (screen != (id)[NSNull null]) [self setBottomInsetOf:screen to:height];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTabBar];
    if (_classicTabs) ExteriaPlaceClassicBadge(_classicTabs.tabBar, self.view.bounds.size.width, ExteriaTabIndexOfKind(_kinds, ExteriaTabChats));
}

#pragma mark delegates

- (void)tabBar:(ExteriaTabBar *)tabBar didSelectIndex:(NSInteger)index {
    (void)tabBar;
    [self showTab:index];
}

- (void)chatsController:(ExteriaChatsController *)controller didChangeUnreadTotal:(NSInteger)total {
    (void)controller;
    NSInteger chatsIndex = ExteriaTabIndexOfKind(_kinds, ExteriaTabChats);
    if (chatsIndex >= 0) [_tabBar setBadge:total forIndex:chatsIndex];
}

- (void)profileControllerRequestsSettings:(ExteriaProfileController *)controller {
    (void)controller;
    NSInteger settingsIndex = ExteriaTabIndexOfKind(_kinds, ExteriaTabSettings);
    if (settingsIndex < 0) return;
    _tabBar.selectedIndex = settingsIndex;
    [self showTab:settingsIndex];
}

- (void)profileController:(ExteriaProfileController *)controller requestsSignOut:(void (^)(NSString *errorName))completion {
    (void)controller;
    [_delegate mainController:self requestsSignOut:completion];
}

@end
