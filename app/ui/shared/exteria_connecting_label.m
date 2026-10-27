#import "exteria_connecting_label.h"

#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define MAX_DOTS 3
#define DOT_INTERVAL 0.4

static NSString *ExteriaDotsText(NSString *base, NSUInteger dots) {
    return [base stringByPaddingToLength:base.length + MIN(dots, (NSUInteger)MAX_DOTS) withString:@"." startingAtIndex:0];
}

NSString *ExteriaConnectingText(NSUInteger dots) {
    return ExteriaDotsText(NSLocalizedString(@"connecting.title", nil), dots);
}

NSString *ExteriaUpdatingText(NSUInteger dots) {
    return ExteriaDotsText(NSLocalizedString(@"updating.title", nil), dots);
}

@interface ExteriaConnectingLabel () {
    BOOL _connecting;
    BOOL _updating;
    NSUInteger _dots;
    NSTimer *_timer;
    /* the window stays attached in the background, where the app may be kept awake for its link and nobody sees the dots */
    BOOL _appBackground;
}
@end

@implementation ExteriaConnectingLabel

@synthesize connecting = _connecting;
@synthesize updating = _updating;

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    [super dealloc];
}

- (void)setConnecting:(BOOL)connecting {
    if (connecting == _connecting) return;
    _connecting = connecting;
    _dots = 0;
    if (connecting) self.text = [self titleWithDots:0];
    [self updateTimer];
}

/* the words of the link coming up and of the list being loaded over a link that works differ, and the dots run the same way */
- (NSString *)titleWithDots:(NSUInteger)dots {
    return _updating ? ExteriaUpdatingText(dots) : ExteriaConnectingText(dots);
}

- (void)setUpdating:(BOOL)updating {
    if (updating == _updating) return;
    _updating = updating;
    if (_connecting) self.text = [self titleWithDots:_dots];
}

/* the timer retains the label, so it runs only while the label is on screen and dies with the window */
- (void)updateTimer {
    BOOL wanted = _connecting && self.window && !_appBackground;
    if (wanted && !_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:DOT_INTERVAL target:self selector:@selector(tick) userInfo:nil repeats:YES];
    } else if (!wanted && _timer) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    if (self.window) {
        _appBackground = [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
        [center addObserver:self selector:@selector(appWentToBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:self selector:@selector(appCameForward) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    [self updateTimer];
}

- (void)appWentToBackground {
    _appBackground = YES;
    [self updateTimer];
}

- (void)appCameForward {
    _appBackground = NO;
    [self updateTimer];
}

- (void)tick {
    _dots = (_dots + 1) % (MAX_DOTS + 1);
    self.text = [self titleWithDots:_dots];
}

- (CGSize)sizeThatFits:(CGSize)size {
    if (!_connecting) return [super sizeThatFits:size];
    CGSize full = ExteriaStringSize([self titleWithDots:MAX_DOTS], self.font);
    return CGSizeMake(ceil(full.width), ceil(full.height));
}

@end
