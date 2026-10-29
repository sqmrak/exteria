#import "exteria_group_call_presenter.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_cache.h"
#import "exteria_group_call_controller.h"
#import "exteria_group_call_state.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

@interface ExteriaGroupCallPresenter () {
    UIViewController *(^_topController)(void);
    UIView *(^_host)(void);
    ExteriaSession *_session;
    ExteriaGroupCallController *_screen;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaGroupCall *_snapshot, *_pending;
    UIButton *_bar;
    NSTimer *_barTimer;
    BOOL _minimized, _minimizing;
}
@end

@implementation ExteriaGroupCallPresenter

@synthesize session = _session;

- (id)initWithTopController:(UIViewController *(^)(void))topController host:(UIView *(^)(void))host {
    self = [super init];
    if (!self) return nil;
    _topController = [topController copy];
    _host = [host copy];
    return self;
}

- (void)dealloc {
    [_barTimer invalidate];
    [_barTimer release];
    [_bar removeFromSuperview];
    [_bar release];
    [_topController release];
    [_host release];
    [_screen release];
    [_avatars release];
    [_media release];
    [_snapshot release];
    [_pending release];
    [super dealloc];
}

- (BOOL)callIsShown { return _screen != nil; }

- (void)session:(ExteriaSession *)session groupCallDidChange:(ExteriaGroupCall *)call {
    if (_screen && _screen.finishing && call.callId != _screen.callId && call.phase != ExteriaGroupPhaseEnded) {
        /* the next call waits until the screen of the one that ended is gone */
        [_pending release];
        _pending = [call retain];
        return;
    }
    if (call != _snapshot) {
        [_snapshot release];
        _snapshot = [call retain];
    }
    if (!_screen) {
        if (call.phase == ExteriaGroupPhaseEnded) {
            /* a call that failed before its screen was shown is only worded */
            [self noticeForCall:call];
            return;
        }
        if (!_avatars) {
            NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSString *directory = [[caches stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"avatars"];
            _avatars = [[ExteriaAvatarCache alloc] initWithSession:session directory:directory];
            _media = [[ExteriaMediaCache alloc] initWithSession:session directory:[[caches stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"media"]];
        }
        _screen = [[ExteriaGroupCallController alloc] initWithSession:session];
        _screen.avatars = _avatars;
        _screen.media = _media;
        /* not retained by the block: the screen holds the block */
        __block ExteriaGroupCallController *shown = _screen;
        _screen.onMinimize = ^{ [self minimize]; };
        _screen.onFinish = ^{
            if (_screen != shown) return;
            [self hideBar];
            _minimizing = NO;
            ExteriaGroupCall *last = [[_snapshot retain] autorelease];
            [_snapshot release];
            _snapshot = nil;
            [_screen release];
            _screen = nil;
            [self noticeForCall:last];
            ExteriaGroupCall *next = [[_pending retain] autorelease];
            [_pending release];
            _pending = nil;
            if (next) [self session:session groupCallDidChange:next];
        };
        UIViewController *top = _topController();
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:_screen animated:YES completion:nil];
    }
    if (_minimized) {
        if (call.phase == ExteriaGroupPhaseEnded) {
            /* the screen of a call that ended while it was folded is put back for the moment it shows its end, so it closes the way every screen does */
            [self hideBar];
            [self presentFoldedScreen];
        } else {
            [self refreshBar];
        }
    }
    [_screen updateWithCall:call];
}

- (void)presentFoldedScreen {
    if (!_screen) return;
    UIViewController *top = _topController();
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:_screen animated:NO completion:nil];
}

#pragma mark the end

- (NSString *)noticeTextForCall:(ExteriaGroupCall *)call {
    switch (call.end) {
    case ExteriaGroupEndFinished: return NSLocalizedString(@"group.notice.finished", nil);
    case ExteriaGroupEndNoCall: return NSLocalizedString(@"group.notice.nocall", nil);
    case ExteriaGroupEndUnsupported: return NSLocalizedString(@"group.notice.unsupported", nil);
    case ExteriaGroupEndRemoved: return NSLocalizedString(@"group.notice.removed", nil);
    case ExteriaGroupEndFailed:
        return call.error.length ? [NSString stringWithFormat:NSLocalizedString(@"group.notice.failed.detail", nil), call.error] : NSLocalizedString(@"group.notice.failed", nil);
    default: return nil;
    }
}

- (void)noticeForCall:(ExteriaGroupCall *)call {
    NSString *text = call.phase == ExteriaGroupPhaseEnded ? [self noticeTextForCall:call] : nil;
    if (!text) return;
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

#pragma mark folded call

- (void)minimize {
    if (!_screen || _minimized || _screen.finishing) return;
    _minimized = YES;
    _minimizing = YES;
    ExteriaGroupCallController *screen = _screen;
    [screen dismissViewControllerAnimated:YES completion:^{
        if (_screen != screen) return;
        _minimizing = NO;
        if (_minimized) [self showBar];
    }];
}

- (void)restore {
    if (!_screen || !_minimized || _minimizing) return;
    _minimized = NO;
    [self hideBar];
    UIViewController *top = _topController();
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:_screen animated:YES completion:nil];
}

- (void)showBar {
    if (!_bar) {
        _bar = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _bar.backgroundColor = [UIColor colorWithRed:0.18f green:0.72f blue:0.35f alpha:1];
        _bar.layer.cornerRadius = 16;
        _bar.titleLabel.font = ExteriaFontSemibold(13);
        _bar.titleLabel.lineBreakMode = UILineBreakModeTailTruncation;
        _bar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [_bar addTarget:self action:@selector(restore) forControlEvents:UIControlEventTouchUpInside];
    }
    [self refreshBar];
    if (!_barTimer) _barTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refreshBar) userInfo:nil repeats:YES] retain];
    UIView *host = _host();
    CGFloat width = MIN(MAX(0, host.bounds.size.width - 104), 260);
    _bar.frame = CGRectMake(floor((host.bounds.size.width - width) / 2), ExteriaStatusBarHeight() + 4, width, 32);
    [host addSubview:_bar];
}

- (void)refreshBar {
    NSString *name = _snapshot.title.length ? _snapshot.title : (_snapshot.chatTitle.length ? _snapshot.chatTitle : NSLocalizedString(@"group.title", nil));
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"group.return", nil), name];
    if (_snapshot.phase == ExteriaGroupPhaseActive && _snapshot.startedAt > 0) {
        NSInteger seconds = MAX(0, (NSInteger)([NSDate timeIntervalSinceReferenceDate] - _snapshot.startedAt));
        title = [NSString stringWithFormat:@"%@ · %ld:%02ld", name, (long)(seconds / 60), (long)(seconds % 60)];
    } else if (_snapshot.phase == ExteriaGroupPhaseReconnecting) {
        title = NSLocalizedString(@"call.reconnecting", nil);
    }
    [_bar setTitle:title forState:UIControlStateNormal];
}

- (void)hideBar {
    _minimized = NO;
    [_barTimer invalidate];
    [_barTimer release];
    _barTimer = nil;
    [_bar removeFromSuperview];
}

@end
