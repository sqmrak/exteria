#import "exteria_shiro_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_classic_shiro_controller.h"
#import "exteria_split_controller.h"
#import "exteria_main_controller.h"
#import "exteria_platform.h"
#import "exteria_shiro_home_view.h"
#import "exteria_shiro_style.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define HEADER_HEIGHT 56.0
/* the extra large corner of the Material shape scale, which the top of a bottom sheet takes */
#define CARD_RADIUS 28.0
#define CLOSE_HEIGHT 36.0
#define ENTER_SECONDS 0.3
#define DISMISS_DISTANCE 110.0
#define DISMISS_VELOCITY 700.0

@interface ExteriaShiroController () <UIGestureRecognizerDelegate> {
    ExteriaShiro *_shiro;
    UIView *_dim;
    UIView *_card;
    UIView *_header;
    UIButton *_close;
    UIView *_grabber;
    ExteriaShiroHomeView *_home;
    NSTimer *_statsTimer;
    BOOL _closing;
    /* the card is moving on its own account (entering, leaving or dragged), so a layout pass must not set it back */
    BOOL _moving;
}
@end

@implementation ExteriaShiroController

+ (void)presentWithShiro:(ExteriaShiro *)shiro from:(UIViewController *)host {
    /* the classic style has its own screen, after shiro 1.0.0 */
    if (ExteriaThemeIsClassic()) {
        [ExteriaClassicShiroController presentWithShiro:shiro from:host];
        return;
    }
    UIViewController *parent = host;
    while (parent && ![parent isKindOfClass:[ExteriaMainController class]]) parent = parent.parentViewController;
    if (!parent) {
        parent = host;
        while (parent.parentViewController) parent = parent.parentViewController;
    }
    /* on the ipad the main screen is only the left pane, and the screen has to cover both panes */
    for (UIViewController *up = parent; up; up = up.parentViewController) {
        if ([up isKindOfClass:[ExteriaSplitController class]]) {
            parent = up;
            break;
        }
    }
    for (UIViewController *child in parent.childViewControllers) {
        if ([child isKindOfClass:[ExteriaShiroController class]]) return;
    }
    ExteriaShiroController *screen = [[[ExteriaShiroController alloc] initWithShiro:shiro] autorelease];
    [parent addChildViewController:screen];
    screen.view.frame = parent.view.bounds;
    [parent.view addSubview:screen.view];
    [screen didMoveToParentViewController:parent];
    [screen enter];
}

- (id)initWithShiro:(ExteriaShiro *)shiro {
    self = [super init];
    if (!self) return nil;
    _shiro = [shiro retain];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_statsTimer invalidate];
    [_shiro release];
    [_dim release];
    [_card release];
    [_header release];
    [_close release];
    [_grabber release];
    [_home release];
    [super dealloc];
}

#pragma mark view

- (void)loadView {
    UIView *root = [[[UIView alloc] init] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [root addSubview:_dim];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)] autorelease];
    [_dim addGestureRecognizer:tap];

    _card = [[UIView alloc] init];
    /* the card reaches below the screen, so only its top corners show as round */
    _card.layer.cornerRadius = CARD_RADIUS;
    _card.layer.masksToBounds = YES;
    [root addSubview:_card];

    _home = [[ExteriaShiroHomeView alloc] init];
    [_home.power addTarget:self action:@selector(powerTapped) forControlEvents:UIControlEventTouchUpInside];
    _home.power.accessibilityLabel = NSLocalizedString(@"shiro.power", nil);
    [_home.card addTarget:self action:@selector(turnOff) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_home];

    _header = [[UIView alloc] init];
    [_card addSubview:_header];
    _grabber = [[UIView alloc] init];
    _grabber.layer.cornerRadius = 2;
    [_header addSubview:_grabber];
    /* a tonal button: a pill in the secondary container that sinks a little under the finger and eases back */
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setTitle:NSLocalizedString(@"shiro.close", nil) forState:UIControlStateNormal];
    _close.titleLabel.font = ExteriaShiroFontBody(14, YES);
    _close.layer.cornerRadius = CLOSE_HEIGHT / 2;
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_close addTarget:self action:@selector(closePressed) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_close addTarget:self action:@selector(closeReleased) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                                                          UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [_header addSubview:_close];

    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)] autorelease];
    pan.delegate = self;
    [_card addGestureRecognizer:pan];

    [self applyTheme];
}

- (void)applyTheme {
    _card.backgroundColor = ExteriaShiroColorSurface();
    _header.backgroundColor = [UIColor clearColor];
    _grabber.backgroundColor = ExteriaShiroColorOutline();
    _close.backgroundColor = ExteriaShiroColorSecondaryContainer();
    [_close setTitleColor:ExteriaShiroColorOnSecondaryContainer() forState:UIControlStateNormal];
    [_home applyTheme];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    BOOL pad = ExteriaIsPad();
    CGFloat cardWidth = pad ? MIN(size.width, 560) : size.width;
    CGFloat top = pad ? MAX(insets.top, 24) + 16 : MAX(insets.top, 0) + 28;
    _dim.frame = self.view.bounds;
    CGFloat bottomOverhang = CARD_RADIUS + 4;
    if (!_moving) _card.frame = CGRectMake(floor((size.width - cardWidth) / 2), top, cardWidth, size.height - top + bottomOverhang);
    else _card.bounds = CGRectMake(0, 0, cardWidth, size.height - top + bottomOverhang);

    _header.frame = CGRectMake(0, 0, cardWidth, HEADER_HEIGHT);
    _grabber.frame = CGRectMake(floor((cardWidth - 36) / 2), 6, 36, 4);
    CGFloat closeWidth = ceil(ExteriaStringSize(NSLocalizedString(@"shiro.close", nil), _close.titleLabel.font).width) + 36;
    _close.frame = CGRectMake(16, 14, closeWidth, CLOSE_HEIGHT);

    CGFloat sideInset = pad ? 0 : MAX(insets.left, 0);
    _home.frame = CGRectMake(sideInset, HEADER_HEIGHT, cardWidth - sideInset * 2,
                             size.height - top - HEADER_HEIGHT - MAX(insets.bottom, 0));
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shiroChanged) name:ExteriaShiroStateDidChangeNotification object:_shiro];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged) name:ExteriaThemeDidChangeNotification object:nil];
    [self shiroChanged];
}

- (void)themeChanged {
    [self applyTheme];
    [self shiroChanged];
}

#pragma mark state

static NSString *ExteriaShiroStateKey(ExteriaShiroState state, ExteriaShiroFailure failure) {
    switch (state) {
    case ExteriaShiroStateOff: return @"shiro.state.off";
    case ExteriaShiroStateRegistering: return @"shiro.state.registering";
    case ExteriaShiroStateConnecting: return @"shiro.state.connecting";
    case ExteriaShiroStateUp: return @"shiro.state.up";
    case ExteriaShiroStateFailed:
        switch (failure) {
        case ExteriaShiroFailureAccount: return @"shiro.state.failed.account";
        case ExteriaShiroFailureKey: return @"shiro.state.failed.key";
        default: return @"shiro.state.failed.server";
        }
    }
    return @"shiro.state.off";
}

- (void)shiroChanged {
    ExteriaShiroState state = _shiro.state;
    ExteriaShiroPowerState power = ExteriaShiroPowerOff;
    if (state == ExteriaShiroStateRegistering || state == ExteriaShiroStateConnecting) power = ExteriaShiroPowerWorking;
    else if (state == ExteriaShiroStateUp) power = ExteriaShiroPowerOn;
    else if (state == ExteriaShiroStateFailed) power = ExteriaShiroPowerFailed;
    _home.power.powerState = power;
    _home.stateLabel.text = NSLocalizedString(ExteriaShiroStateKey(state, _shiro.failure), nil);
    _home.power.accessibilityValue = _home.stateLabel.text;
    /* after a failure the plate offers the way out: the tunnel stays wanted, and traffic stays blocked, until the person turns it off */
    BOOL failed = state == ExteriaShiroStateFailed;
    _home.card.userInteractionEnabled = failed;
    _home.cardTitle.text = failed ? NSLocalizedString(@"shiro.card.turnoff", nil) : @"Cloudflare WARP";
    _home.cardTitle.textColor = failed ? ExteriaShiroColorError() : ExteriaShiroColorOnSurface();
    if (failed) {
        [self stopStatsTimer];
        _home.cardSubtitle.text = nil;
    } else if (state == ExteriaShiroStateUp) {
        if (!_statsTimer) _statsTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refreshStats) userInfo:nil repeats:YES] retain];
        [self refreshStats];
    } else if (!failed) {
        [self stopStatsTimer];
        _home.cardSubtitle.text = NSLocalizedString(@"shiro.card.idle", nil);
    }
}

- (void)refreshStats {
    ExteriaShiroStats stats;
    memset(&stats, 0, sizeof(stats));
    /* a busy engine keeps the last figures; the line stays as it was */
    [_shiro stats:&stats];
    unsigned long long seconds = stats.ageMs / 1000;
    _home.cardSubtitle.text = [NSString stringWithFormat:@"↓ %@   ↑ %@   %02llu:%02llu", ExteriaShiroByteText(stats.bytesIn),
                               ExteriaShiroByteText(stats.bytesOut), seconds / 60 % 100, seconds % 60];
}

- (void)stopStatsTimer {
    [_statsTimer invalidate];
    [_statsTimer release];
    _statsTimer = nil;
}

- (void)closePressed {
    [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        _close.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:nil];
}

- (void)closeReleased {
    if (CGAffineTransformIsIdentity(_close.transform)) return;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.35 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        _close.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)turnOff {
    [_shiro setEnabled:NO];
}

- (void)powerTapped {
    switch (_shiro.state) {
    case ExteriaShiroStateOff: [_shiro setEnabled:YES]; break;
    case ExteriaShiroStateFailed: [_shiro retry]; break;
    /* a tap while it dials gives up on it, as a tap on the lit control turns it off */
    default: [_shiro setEnabled:NO]; break;
    }
}

#pragma mark presenting

- (void)enter {
    [self.view layoutIfNeeded];
    CGRect rest = _card.frame;
    _moving = YES;
    _card.frame = CGRectOffset(rest, 0, self.view.bounds.size.height - rest.origin.y);
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : ENTER_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _card.frame = rest;
        _dim.alpha = 0.45;
    } completion:^(BOOL finished) {
        (void)finished;
        _moving = NO;
    }];
}

- (void)close {
    if (_closing) return;
    _closing = YES;
    _moving = YES;
    [self stopStatsTimer];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : ENTER_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        _card.frame = CGRectOffset(_card.frame, 0, self.view.bounds.size.height - _card.frame.origin.y);
        _dim.alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (_closing) return NO;
    CGPoint point = [recognizer locationInView:_card];
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:_card];
    /* only the header drags the card, and only downwards at first, so the controls under it keep their touches */
    return point.y <= HEADER_HEIGHT && velocity.y > fabs(velocity.x);
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = ExteriaIsPad() ? MAX(insets.top, 24) + 16 : MAX(insets.top, 0) + 28;
    CGFloat drag = MAX(0, [pan translationInView:self.view].y);
    CGRect frame = _card.frame;
    if (pan.state == UIGestureRecognizerStateBegan) _moving = YES;
    if (pan.state == UIGestureRecognizerStateChanged) {
        frame.origin.y = top + drag;
        _card.frame = frame;
        _dim.alpha = 0.45 * (1 - MIN(1, drag / self.view.bounds.size.height));
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat speed = [pan velocityInView:self.view].y;
        if (pan.state == UIGestureRecognizerStateEnded && (drag > DISMISS_DISTANCE || speed > DISMISS_VELOCITY)) {
            [self close];
            return;
        }
        frame.origin.y = top;
        [UIView animateWithDuration:0.2 animations:^{
            _card.frame = frame;
            _dim.alpha = 0.45;
        } completion:^(BOOL finished) {
            (void)finished;
            _moving = NO;
        }];
    }
}

@end
