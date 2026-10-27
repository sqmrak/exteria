#import "exteria_welcome_controller.h"

#import "exteria_animated_icon_view.h"
#import "exteria_lottie_view.h"
#import "exteria_network_probe.h"
#import "exteria_page_dots_view.h"
#import "exteria_platform.h"
#import "exteria_senko.h"
#import "exteria_senko_popup.h"
#import "exteria_shiro_button.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"
#import "exteria_wave_button.h"
#import "exteria_weak_reference.h"
#import "exteria_welcome_toast.h"
#import "exteria_welcome.h"

#define EXTERIA_WELCOME_PAGES 6
/* the sticker of the network card: the duck with the phone and the cloud, from the welcome pages */
#define NETWORK_STICKER @"welcome_cloud"
#define SENKO_GREETING_DELAY 1.2
#define PROBE_RETRY_DELAY 0.5

/* what the card on screen says, which decides what its buttons do */
typedef enum {
    ExteriaWelcomeToastNone = 0,
    /* the network is bad and the VPN is off: the card offers to turn it on */
    ExteriaWelcomeToastOffer,
    /* the VPN is on and Telegram still does not answer */
    ExteriaWelcomeToastNoLink,
    /* the VPN is being made */
    ExteriaWelcomeToastDialing
} ExteriaWelcomeToastKind;

/* the Senko card shows once for a run of the app, not each time the login screen comes back */
static BOOL ExteriaSenkoGreeted;

/* page 0 is the animated icon, the others each carry one sticker */
static NSString *const ExteriaWelcomeStickers[EXTERIA_WELCOME_PAGES] = {
    nil, @"welcome_fast", @"welcome_free", @"welcome_secure", @"welcome_powerful", @"welcome_cloud"
};

@interface ExteriaWelcomePage : UIView {
    UIView *_art;
    UILabel *_title;
    UILabel *_message;
}
@property (nonatomic, readonly) UIView *art;
@property (nonatomic, readonly) UILabel *title;
@property (nonatomic, readonly) UILabel *message;
- (id)initWithIndex:(NSInteger)index;
@end

@implementation ExteriaWelcomePage

@synthesize art = _art;
@synthesize title = _title;
@synthesize message = _message;

static UILabel *ExteriaWelcomeLabel(UIColor *color, NSInteger lines) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.numberOfLines = lines;
    label.adjustsFontSizeToFitWidth = NO;
    return label;
}

- (id)initWithIndex:(NSInteger)index {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    NSString *sticker = ExteriaWelcomeStickers[index];
    _art = [(sticker ? (UIView *)[[[ExteriaLottieView alloc] initWithAnimationNamed:sticker] autorelease]
                     : (UIView *)[[[ExteriaAnimatedIconView alloc] init] autorelease]) retain];
    _title = [ExteriaWelcomeLabel(ExteriaColorTitle(), 1) retain];
    _message = [ExteriaWelcomeLabel(ExteriaColorMessage(), 0) retain];
    _title.text = NSLocalizedString(([NSString stringWithFormat:@"welcome.title.%d", (int)index]), nil);
    _message.text = NSLocalizedString(([NSString stringWithFormat:@"welcome.message.%d", (int)index]), nil);
    [self addSubview:_art];
    [self addSubview:_title];
    [self addSubview:_message];
    return self;
}

- (void)dealloc {
    [_art release];
    [_title release];
    [_message release];
    [super dealloc];
}

@end

@interface ExteriaWelcomeController () {
    ExteriaWaveBackgroundView *_backdrop;
    UIScrollView *_scroll;
    NSMutableArray *_pages;
    ExteriaPageDotsView *_dots;
    ExteriaWaveButton *_button;
    UIButton *_qr;
    ExteriaSenkoPopup *_senkoPopup;
    ExteriaShiroButton *_vpn;
    NSInteger _page;
    CGFloat _laidOutWidth;
    BOOL _visible;
    ExteriaWelcomeToast *_toast;
    ExteriaWelcomeToastKind _toastKind;
    BOOL _probing;
    /* the person closed the network card; it stays closed until the network has worked once and failed again */
    BOOL _networkDismissed;
    /* the card left because Telegram answered, which is not the person closing it */
    BOOL _leftForRecovery;
}
@end

@implementation ExteriaWelcomeController

@synthesize delegate = _delegate;
@synthesize shiro = _shiro;

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorBackdrop();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[ExteriaWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    _scroll = [[UIScrollView alloc] initWithFrame:root.bounds];
    _scroll.pagingEnabled = YES;
    _scroll.bounces = NO;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.scrollsToTop = NO;
    /* ios 7 and 11 would inset the pages by the status bar and shift every offset */
    if ([self respondsToSelector:NSSelectorFromString(@"setAutomaticallyAdjustsScrollViewInsets:")]) {
        [self setValue:[NSNumber numberWithBool:NO] forKey:@"automaticallyAdjustsScrollViewInsets"];
    }
    if ([_scroll respondsToSelector:NSSelectorFromString(@"setContentInsetAdjustmentBehavior:")]) {
        [_scroll setValue:[NSNumber numberWithInteger:2] forKey:@"contentInsetAdjustmentBehavior"];
    }
    _scroll.delegate = self;
    [root addSubview:_scroll];

    _pages = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i < EXTERIA_WELCOME_PAGES; ++i) {
        ExteriaWelcomePage *page = [[[ExteriaWelcomePage alloc] initWithIndex:i] autorelease];
        [_pages addObject:page];
        [_scroll addSubview:page];
    }

    _dots = [[ExteriaPageDotsView alloc] init];
    _dots.pages = EXTERIA_WELCOME_PAGES;
    [root addSubview:_dots];

    _button = [[ExteriaWaveButton alloc] init];
    _button.title = NSLocalizedString(@"welcome.start", nil);
    [_button addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_button];

    /* a plain line of text that does not compete with the button: half see-through until it is touched */
    _qr = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_qr setTitle:NSLocalizedString(@"phone.qr", nil) forState:UIControlStateNormal];
    [_qr setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    _qr.alpha = 0.6;
    [_qr addTarget:self action:@selector(qrTapped) forControlEvents:UIControlEventTouchUpInside];
    [_qr addTarget:self action:@selector(qrDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_qr addTarget:self action:@selector(qrUp)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [root addSubview:_qr];

    if (_shiro) {
        _vpn = [[ExteriaShiroButton alloc] initWithShiro:_shiro host:self];
        [root addSubview:_vpn];
    }
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self releaseToast];
    _scroll.delegate = nil;
    [_backdrop release];
    [_scroll release];
    [_pages release];
    [_dots release];
    [_button release];
    [_qr release];
    _senkoPopup.dismissHandler = nil;
    [_senkoPopup dismiss];
    [_senkoPopup release];
    [_vpn release];
    [super dealloc];
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
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    /* a notch in landscape cuts into the sides, so the stack is laid out inside them */
    CGFloat side = insets.left;
    exteria_welcome_metrics metrics = {size.width - insets.left - insets.right, size.height, insets.top,
                                       insets.bottom, ExteriaIsPad() ? 1 : 0, EXTERIA_WELCOME_PAGES};
    exteria_welcome_layout layout;
    if (exteria_welcome_layout_compute(&metrics, &layout) != EXTERIA_OK) {
        NSLog(@"exteria: welcome layout does not fit %.0fx%.0f", size.width, size.height);
    }

    _backdrop.frame = self.view.bounds;
    _scroll.frame = self.view.bounds;
    _toast.inset = insets.top;
    [_toast refresh];
    CGSize pill = [_vpn preferredSize];
    _vpn.frame = CGRectMake(size.width - insets.right - 16 - pill.width, insets.top + 10, pill.width, pill.height);
    _scroll.contentSize = CGSizeMake(size.width * EXTERIA_WELCOME_PAGES, size.height);
    for (NSInteger i = 0; i < EXTERIA_WELCOME_PAGES; ++i) {
        ExteriaWelcomePage *page = [_pages objectAtIndex:i];
        page.frame = CGRectMake(i * size.width, 0, size.width, size.height);
        page.art.frame = CGRectMake(side + layout.art.x, layout.art.y, layout.art.width, layout.art.height);
        page.title.frame = CGRectMake(side + layout.title.x, layout.title.y, layout.title.width, layout.title.height);
        page.title.font = ExteriaFontBold(layout.title_size);
        page.message.frame = CGRectMake(side + layout.message.x, layout.message.y, layout.message.width, layout.message.height);
        page.message.font = ExteriaFontRegular(layout.message_size);
        [page.message sizeToFit];
        CGRect fitted = page.message.frame;
        fitted.size.width = layout.message.width;
        fitted.origin.x = side + layout.message.x;
        fitted.size.height = MIN(fitted.size.height, layout.message.height);
        page.message.frame = fitted;
    }
    _dots.frame = CGRectMake(side + layout.dots.x, layout.dots.y, layout.dots.width, layout.dots.height);
    _dots.diameter = (CGFloat)layout.dot_diameter;
    _button.frame = CGRectMake(side + layout.button.x, layout.button.y, layout.button.width, layout.button.height);
    _button.cornerRadius = (CGFloat)layout.button_radius;
    _button.titleSize = (CGFloat)layout.button_size;
    /* the link goes under the button, or over it when the button sits too low for a line beneath */
    CGFloat linkHeight = 36;
    CGFloat below = CGRectGetMaxY(_button.frame) + 6;
    BOOL fits = below + linkHeight <= size.height - insets.bottom - 2;
    _qr.titleLabel.font = ExteriaFontMedium(16);
    _qr.frame = CGRectMake(_button.frame.origin.x, fits ? below : _button.frame.origin.y - linkHeight - 6, _button.frame.size.width, linkHeight);

    /* rotation changes the page width, and the offset would otherwise keep the old pixel position */
    if (size.width != _laidOutWidth) {
        _laidOutWidth = size.width;
        _scroll.contentOffset = CGPointMake(_page * size.width, 0);
    }
    [_dots setProgress:exteria_pager_progress(_scroll.contentOffset.x, size.width, EXTERIA_WELCOME_PAGES)];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(refreshPlayback)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
    NSString *motion = ExteriaReduceMotionChangedNotification();
    if (motion) [center addObserver:self selector:@selector(refreshPlayback) name:motion object:nil];
    if (_shiro) [center addObserver:self selector:@selector(shiroChanged) name:ExteriaShiroStateDidChangeNotification object:_shiro];
    [center addObserver:self selector:@selector(probeNetwork) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refreshPlayback];
    [self probeNetwork];
    [self performSelector:@selector(greetSenko) withObject:nil afterDelay:SENKO_GREETING_DELAY];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    /* the next screen has no use for a card of this one, and its buttons act on this screen */
    [self releaseToast];
    [self refreshPlayback];
}

/* backgrounding drops running core animations, so the active page starts again on return */
- (void)refreshPlayback {
    for (NSInteger i = 0; i < EXTERIA_WELCOME_PAGES; ++i) {
        UIView *art = ((ExteriaWelcomePage *)[_pages objectAtIndex:i]).art;
        BOOL active = _visible && i == _page;
        if ([art isKindOfClass:[ExteriaAnimatedIconView class]]) {
            if (active) [(ExteriaAnimatedIconView *)art startAnimating];
            else [(ExteriaAnimatedIconView *)art stopAnimating];
        } else {
            ExteriaLottieView *sticker = (ExteriaLottieView *)art;
            [sticker setLoaded:ABS(i - _page) <= 1];
            [sticker setPlaying:active];
        }
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat width = scrollView.bounds.size.width;
    [_dots setProgress:exteria_pager_progress(scrollView.contentOffset.x, width, EXTERIA_WELCOME_PAGES)];
    NSInteger page = exteria_pager_page(scrollView.contentOffset.x, width, EXTERIA_WELCOME_PAGES);
    /* layout resets the offset on rotation; that is not a page change */
    if (page == _page || width != _laidOutWidth) return;
    _page = page;
    [self refreshPlayback];
}

- (void)qrTapped {
    [_delegate welcomeControllerDidRequestQr:self];
}

- (void)qrDown {
    _qr.alpha = 0.3;
}

- (void)qrUp {
    [UIView animateWithDuration:0.2 animations:^{ _qr.alpha = 0.6; }];
}

- (void)startTapped {
    [_delegate welcomeControllerDidTapStart:self];
}

#pragma mark cards

/* the card is owned here and its handlers hold this screen only weakly, so neither keeps the other alive */
- (void)releaseToast {
    [NSObject cancelPreviousPerformRequestsWithTarget:_toast];
    _toast.primaryHandler = nil;
    _toast.secondaryHandler = nil;
    _toast.dismissHandler = nil;
    [_toast removeFromSuperview];
    [_toast release];
    _toast = nil;
    _toastKind = ExteriaWelcomeToastNone;
}

- (void)presentToast:(ExteriaWelcomeToast *)toast kind:(ExteriaWelcomeToastKind)kind {
    [self releaseToast];
    _toast = [toast retain];
    _toastKind = kind;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    toast.dismissHandler = ^{
        ExteriaWelcomeController *me = weak.target;
        if (!me) return;
        ExteriaWelcomeToastKind left = me->_toastKind;
        BOOL recovered = me->_leftForRecovery;
        me->_leftForRecovery = NO;
        [me releaseToast];
        if (left >= ExteriaWelcomeToastOffer && !recovered) me->_networkDismissed = YES;
    };
    [toast showInView:self.view inset:ExteriaLayoutInsets(self).top];
}

- (void)greetSenko {
    if (!_visible || ExteriaSenkoGreeted || _toast || _senkoPopup || !ExteriaSenkoInstalled()) return;
    ExteriaSenkoGreeted = YES;
    _senkoPopup = [[ExteriaSenkoPopup alloc] init];
    _senkoPopup.titleText = NSLocalizedString(@"welcome.senko.title", nil);
    _senkoPopup.messageText = NSLocalizedString(@"welcome.senko.message", nil);
    _senkoPopup.buttonTitle = NSLocalizedString(@"welcome.senko.ok", nil);
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    _senkoPopup.dismissHandler = ^{
        ExteriaWelcomeController *me = weak.target;
        if (!me) return;
        [me->_senkoPopup release];
        me->_senkoPopup = nil;
    };
    [_senkoPopup showInView:ExteriaOverlayHost() ? ExteriaOverlayHost() : self.view];
}

/* the texts and buttons of the network card for what the VPN is doing now */
- (ExteriaWelcomeToastKind)networkKind {
    switch (_shiro.state) {
    case ExteriaShiroStateRegistering:
    case ExteriaShiroStateConnecting: return ExteriaWelcomeToastDialing;
    case ExteriaShiroStateUp: return ExteriaWelcomeToastNoLink;
    case ExteriaShiroStateFailed:
    case ExteriaShiroStateOff: break;
    }
    return ExteriaWelcomeToastOffer;
}

- (void)fillNetworkToast:(ExteriaWelcomeToast *)toast kind:(ExteriaWelcomeToastKind)kind {
    toast.busyTitle = nil;
    switch (kind) {
    case ExteriaWelcomeToastOffer:
        toast.titleText = NSLocalizedString(@"welcome.network.title", nil);
        toast.messageText = NSLocalizedString(@"welcome.network.message", nil);
        toast.primaryTitle = _shiro ? NSLocalizedString(@"welcome.network.enable", nil) : nil;
        toast.secondaryTitle = NSLocalizedString(@"welcome.network.later", nil);
        break;
    case ExteriaWelcomeToastNoLink:
        toast.titleText = NSLocalizedString(@"welcome.network.nolink.title", nil);
        toast.messageText = NSLocalizedString(@"welcome.network.nolink.message", nil);
        toast.primaryTitle = NSLocalizedString(@"welcome.network.retry", nil);
        toast.secondaryTitle = NSLocalizedString(@"welcome.network.close", nil);
        break;
    case ExteriaWelcomeToastDialing:
        toast.titleText = NSLocalizedString(@"welcome.network.dialing.title", nil);
        toast.messageText = NSLocalizedString(@"welcome.network.dialing.message", nil);
        toast.primaryTitle = NSLocalizedString(@"welcome.network.retry", nil);
        toast.busyTitle = NSLocalizedString(@"welcome.network.dialing.busy", nil);
        toast.secondaryTitle = NSLocalizedString(@"welcome.network.close", nil);
        break;
    default: break;
    }
}

- (void)networkPrimaryTapped {
    switch (_toastKind) {
    case ExteriaWelcomeToastOffer:
        [_shiro setEnabled:YES];
        break;
    default:
        /* the VPN is up or being made; what is left is to ask the network again */
        [self probeNetwork];
        break;
    }
    [self syncNetworkToast];
    if (_toast && _toastKind != ExteriaWelcomeToastDialing && _toastKind != ExteriaWelcomeToastOffer) {
        _toast.busyTitle = NSLocalizedString(@"welcome.network.checking", nil);
        [_toast refresh];
    }
}

- (void)networkSecondaryTapped {
    [_toast dismiss];
}

/* the card follows the VPN: its kind changes with the state, and a card is made new only when there is none */
- (void)syncNetworkToast {
    if (!_toast || _toastKind < ExteriaWelcomeToastOffer) return;
    ExteriaWelcomeToastKind kind = [self networkKind];
    _toastKind = kind;
    [self fillNetworkToast:_toast kind:kind];
    [_toast refresh];
}

- (void)showNetworkToast {
    if (!_visible || _networkDismissed) return;
    if (_toast && _toastKind >= ExteriaWelcomeToastOffer) {
        [self syncNetworkToast];
        return;
    }
    /* the greeting makes way: it is only a thank-you, and the person cannot sign in yet */
    if (_toast) {
        [_toast dismiss];
        [self performSelector:@selector(showNetworkToast) withObject:nil afterDelay:0.35];
        return;
    }
    ExteriaWelcomeToast *toast = [[[ExteriaWelcomeToast alloc] init] autorelease];
    ExteriaLottieView *sticker = [[[ExteriaLottieView alloc] initWithAnimationNamed:NETWORK_STICKER] autorelease];
    toast.sticker = sticker;
    ExteriaWelcomeToastKind kind = [self networkKind];
    [self fillNetworkToast:toast kind:kind];
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    toast.primaryHandler = ^{ [(ExteriaWelcomeController *)weak.target networkPrimaryTapped]; };
    toast.secondaryHandler = ^{ [(ExteriaWelcomeController *)weak.target networkSecondaryTapped]; };
    [self presentToast:toast kind:kind];
}

#pragma mark network

/* asks whether Telegram can be reached; the screen has no session to tell it */
- (void)probeNetwork {
    if (_probing || !_visible) return;
    _probing = YES;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    [ExteriaNetworkProbe probeWithShiro:_shiro completion:^(ExteriaProbeResult result) {
        ExteriaWelcomeController *me = weak.target;
        if (!me) return;
        me->_probing = NO;
        [me probeFinished:result];
    }];
}

- (void)probeFinished:(ExteriaProbeResult)result {
    if (!_visible) return;
    switch (result) {
    case ExteriaProbeReachable:
        _networkDismissed = NO;
        if (_toast && _toastKind >= ExteriaWelcomeToastOffer) {
            _leftForRecovery = YES;
            [_toast dismiss];
        }
        break;
    case ExteriaProbeUnreachable:
        [self showNetworkToast];
        break;
    case ExteriaProbeBlocked:
        /* the VPN is wanted and not up: the app opens no connection, so there is no verdict on the network */
        [self syncNetworkToast];
        break;
    }
}

/* a settled VPN changes what the network can do, so it is asked again after a moment; while it is being made only the card moves */
- (void)shiroChanged {
    ExteriaShiroState state = _shiro.state;
    if (state == ExteriaShiroStateFailed) {
        /* the failure card of the app speaks for the tunnel, and a card of this screen under it would only repeat it */
        if (_toast && _toastKind >= ExteriaWelcomeToastOffer) [_toast dismiss];
        return;
    }
    [self syncNetworkToast];
    if (state == ExteriaShiroStateRegistering || state == ExteriaShiroStateConnecting) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(probeNetwork) object:nil];
    [self performSelector:@selector(probeNetwork) withObject:nil afterDelay:PROBE_RETRY_DELAY];
}

@end
