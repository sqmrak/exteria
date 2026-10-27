#import "exteria_split_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chats_controller.h"
#import "exteria_classic_chats_controller.h"
#import "exteria_classic_chrome.h"
#import "exteria_classic_search_controller.h"
#import "exteria_main_controller.h"
#import "exteria_platform.h"
#import "exteria_search_controller.h"
#import "exteria_settings_kit.h"
#import "exteria_theme.h"
#import "exteria_wallpaper.h"

#define MASTER_MIN 320.0
#define MASTER_MAX 420.0
#define MASTER_SHARE 0.36
#define HINT_PAD_X 16.0
#define HINT_HEIGHT 32.0

#pragma mark empty pane

/* what the right pane shows while nothing is open: the chat wallpaper and the line that says what to do, as the chat of Telegram does on a tablet */
@interface ExteriaDetailPlaceholder : UIViewController {
    UIImageView *_wallpaper;
    UILabel *_hint;
}
@end

@implementation ExteriaDetailPlaceholder

- (void)dealloc {
    [_wallpaper release];
    [_hint release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.backgroundColor = ExteriaColorScreen();
    self.view = root;
    _wallpaper = [[UIImageView alloc] initWithFrame:root.bounds];
    _wallpaper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    ExteriaApplyChatWallpaper(_wallpaper, ExteriaThemeIsDark());
    _wallpaper.clipsToBounds = YES;
    [root addSubview:_wallpaper];
    _hint = [[UILabel alloc] init];
    _hint.text = NSLocalizedString(@"split.empty", nil);
    _hint.font = ExteriaFontMedium(15);
    _hint.textColor = [UIColor whiteColor];
    _hint.textAlignment = ExteriaTextAlignmentCenter;
    _hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    _hint.layer.cornerRadius = HINT_HEIGHT / 2;
    _hint.layer.masksToBounds = YES;
    [root addSubview:_hint];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    CGSize fit = [_hint sizeThatFits:CGSizeMake(size.width - 2 * HINT_PAD_X, HINT_HEIGHT)];
    CGFloat width = MIN(size.width - 2 * HINT_PAD_X, ceil(fit.width) + 2 * HINT_PAD_X);
    _hint.frame = CGRectMake(floor((size.width - width) / 2), floor((size.height - HINT_HEIGHT) / 2), width, HINT_HEIGHT);
}

@end

#pragma mark host

@implementation ExteriaDetailHost

@synthesize detail = _detail;

- (BOOL)opensInDetail:(UIViewController *)screen {
    if ([screen isKindOfClass:[ExteriaSearchController class]] || [screen isKindOfClass:[ExteriaClassicSearchController class]]) return NO;
    /* a folder of the chat list (the archive) is a list of the left pane; the main list itself is never pushed */
    if ([screen isKindOfClass:[ExteriaChatsController class]] || [screen isKindOfClass:[ExteriaClassicChatsController class]]) return NO;
    return YES;
}

- (BOOL)detailIsEmpty {
    return _detail.viewControllers.count <= 1 && [_detail.topViewController isKindOfClass:[ExteriaDetailPlaceholder class]];
}

- (void)showInDetail:(UIViewController *)screen animated:(BOOL)animated {
    if (!_detail) return;
    /* the classic bar of the right pane has no way back for its only page, so a button closes it into the empty pane */
    if (ExteriaThemeIsClassic() && !screen.navigationItem.leftBarButtonItem) {
        screen.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"split.close", nil) style:UIBarButtonItemStyleBordered
                                                                                    target:self action:@selector(closeDetail)] autorelease];
    }
    BOOL replacing = ![self detailIsEmpty];
    if (animated && replacing && !ExteriaReduceMotionEnabled()) {
        /* a page that takes the place of another fades in over it; a slide would read as going deeper */
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.2;
        [_detail.view.layer addAnimation:fade forKey:@"detail"];
        [_detail setViewControllers:[NSArray arrayWithObject:screen] animated:NO];
        return;
    }
    [_detail setViewControllers:[NSArray arrayWithObject:screen] animated:animated && !replacing];
}

- (void)closeDetail {
    [self resetDetail];
}

- (void)resetDetail {
    if (!_detail || [self detailIsEmpty]) return;
    [_detail setViewControllers:[NSArray arrayWithObject:[[[ExteriaDetailPlaceholder alloc] init] autorelease]] animated:NO];
}

- (void)styleDidChange:(BOOL)involvesClassic {
    if (!_detail) return;
    BOOL classic = ExteriaThemeIsClassic();
    NSArray *oldPages = involvesClassic ? [[_detail.viewControllers copy] autorelease] : nil;
    if (classic) ExteriaClassicStyleNavigationBar(_detail.navigationBar);
    [_detail setNavigationBarHidden:!classic animated:NO];
    if (!oldPages) return;
    NSMutableArray *pages = [NSMutableArray array];
    for (UIViewController *old in oldPages) {
        if (![old respondsToSelector:@selector(controllerAfterThemeChange)]) break;
        UIViewController *page = [(id<ExteriaThemeRestorable>)old controllerAfterThemeChange];
        if (!page) break;
        [pages addObject:page];
    }
    if (!pages.count) {
        [pages addObject:[[[ExteriaDetailPlaceholder alloc] init] autorelease]];
    } else if (classic) {
        UIViewController *root = [pages objectAtIndex:0];
        if (!root.navigationItem.leftBarButtonItem) {
            root.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"split.close", nil) style:UIBarButtonItemStyleBordered
                                                                                     target:self action:@selector(closeDetail)] autorelease];
        }
    }
    [_detail setViewControllers:pages animated:NO];
}

@end

#pragma mark navigation controllers

@implementation ExteriaSplitNavigationController

@synthesize detailHost = _detailHost;

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (void)pushViewController:(UIViewController *)screen animated:(BOOL)animated {
    if (_detailHost && [_detailHost opensInDetail:screen]) {
        [_detailHost showInDetail:screen animated:animated];
        return;
    }
    [super pushViewController:screen animated:animated];
}

@end

@implementation ExteriaDetailNavigationController

@synthesize detailHost = _detailHost;

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

/* the only page of the pane closes into the empty pane, as a chat that was left or deleted has nothing to go back to */
- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    if (self.viewControllers.count <= 1) {
        [_detailHost resetDetail];
        return nil;
    }
    return [super popViewControllerAnimated:animated];
}

@end

BOOL ExteriaIsDetailRoot(UIViewController *screen) {
    UINavigationController *navigation = screen.navigationController;
    return [navigation isKindOfClass:[ExteriaDetailNavigationController class]] && navigation.viewControllers.count && [navigation.viewControllers objectAtIndex:0] == screen;
}

#pragma mark split

@interface ExteriaSplitController () {
    ExteriaMainController *_main;
    ExteriaSplitNavigationController *_masterNavigation;
    ExteriaDetailNavigationController *_detailNavigation;
    UIView *_divider;
}
@end

@implementation ExteriaSplitController

- (id)initWithMain:(ExteriaMainController *)main {
    self = [super init];
    if (!self) return nil;
    self.wantsFullScreenLayout = YES;
    _main = [main retain];
    _host = [[ExteriaDetailHost alloc] init];
    _main.detailHost = _host;
    _masterNavigation = [[ExteriaSplitNavigationController alloc] initWithRootViewController:_main];
    _masterNavigation.wantsFullScreenLayout = YES;
    _masterNavigation.navigationBarHidden = YES;
    _masterNavigation.detailHost = _host;
    ExteriaDetailPlaceholder *placeholder = [[[ExteriaDetailPlaceholder alloc] init] autorelease];
    _detailNavigation = [[ExteriaDetailNavigationController alloc] initWithRootViewController:placeholder];
    _detailNavigation.detailHost = _host;
    _host.detail = _detailNavigation;
    [_host styleDidChange:NO];
    return self;
}

- (void)dealloc {
    _host.detail = nil;
    _masterNavigation.detailHost = nil;
    _detailNavigation.detailHost = nil;
    _main.detailHost = nil;
    [_main release];
    [_masterNavigation release];
    [_detailNavigation release];
    [_divider release];
    [_host release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.backgroundColor = ExteriaColorScreen();
    self.view = root;
    [self addChildViewController:_masterNavigation];
    [root addSubview:_masterNavigation.view];
    [_masterNavigation didMoveToParentViewController:self];
    [self addChildViewController:_detailNavigation];
    [root addSubview:_detailNavigation.view];
    [_detailNavigation didMoveToParentViewController:self];
    _divider = [[UIView alloc] init];
    _divider.backgroundColor = ExteriaColorHairline();
    [root addSubview:_divider];
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    CGFloat master = MIN(MASTER_MAX, MAX(MASTER_MIN, floor(size.width * MASTER_SHARE)));
    CGFloat hair = 1.0 / ExteriaScreenScale();
    _masterNavigation.view.frame = CGRectMake(0, 0, master, size.height);
    _detailNavigation.view.frame = CGRectMake(master, 0, size.width - master, size.height);
    _divider.frame = CGRectMake(master - hair, 0, hair, size.height);
    _divider.backgroundColor = ExteriaColorHairline();
}

- (BOOL)canRebuildForTheme {
    if (_masterNavigation.viewControllers.count != 1 || self.presentedViewController || _masterNavigation.presentedViewController) return NO;
    return [_host detailIsEmpty];
}

@end
