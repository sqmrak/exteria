#import "exteria_passcode_lock.h"

#import "exteria_passcode_entry_view.h"
#import "exteria_passcode_store.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

@interface ExteriaPasscodeLockController : UIViewController {
    ExteriaPasscodeEntryView *_entry;
    void (^_unlocked)(void);
    BOOL _asking;
}
- (id)initWithUnlocked:(void (^)(void))unlocked;
/* the plain color, or the pad that asks for the code */
- (void)setAsking:(BOOL)asking;
@end

@implementation ExteriaPasscodeLockController

- (id)initWithUnlocked:(void (^)(void))unlocked {
    self = [super init];
    if (!self) return nil;
    _unlocked = [unlocked copy];
    return self;
}

- (void)dealloc {
    [_entry release];
    [_unlocked release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    self.view = root;
    _entry = [[ExteriaPasscodeEntryView alloc] initWithFrame:root.bounds];
    _entry.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _entry.hidden = YES;
    ExteriaPasscodeLockController *lock = self;
    _entry.submit = ^(NSString *code) { [lock codeEntered:code]; };
    [root addSubview:_entry];
}

- (void)setAsking:(BOOL)asking {
    [self view];
    if (asking == _asking) {
        if (asking) [_entry focus];
        return;
    }
    _asking = asking;
    _entry.hidden = !asking;
    if (!asking) {
        [_entry resignFirstResponder];
        return;
    }
    _entry.type = ExteriaPasscodeType();
    _entry.title = NSLocalizedString(@"passcode.enter", nil);
    _entry.message = nil;
    [_entry reset];
    [_entry holdForSeconds:ExteriaPasscodeWaitRemaining()];
    [_entry focus];
}

- (void)codeEntered:(NSString *)code {
    NSUInteger wait = 0;
    ExteriaPasscodeResult result = ExteriaPasscodeCheck(code, &wait);
    if (result == ExteriaPasscodeResultOK) {
        if (_unlocked) _unlocked();
        return;
    }
    [_entry rejectCode];
    _entry.message = result == ExteriaPasscodeResultWrong ? NSLocalizedString(@"passcode.wrong", nil) : nil;
    [_entry holdForSeconds:wait];
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

@end

typedef enum { ExteriaLockStateOpen, ExteriaLockStateCover, ExteriaLockStateAsking } ExteriaLockState;

@interface ExteriaPasscodeLock () {
    UIWindow *_window;
    ExteriaPasscodeLockController *_controller;
    UIWindow *_appWindow;
    ExteriaLockState _state;
    /* wall seconds of the last move to the background, 0 when the app has not left since it was last active */
    NSTimeInterval _leftAt;
}
@end

@implementation ExteriaPasscodeLock

- (void)dealloc {
    [_window release];
    [_controller release];
    [super dealloc];
}

- (void)showWindow {
    if (_window) return;
    /* the keyboard of the app stands above every window, so what is being typed is let go before the lock rises */
    for (UIWindow *window in [[UIApplication sharedApplication] windows]) [window endEditing:YES];
    _appWindow = [[UIApplication sharedApplication] keyWindow];
    ExteriaPasscodeLock *me = self;
    _controller = [[ExteriaPasscodeLockController alloc] initWithUnlocked:^{ [me open]; }];
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.windowLevel = UIWindowLevelAlert + 100;
    _window.backgroundColor = ExteriaColorScreen();
    _window.rootViewController = _controller;
    [_window makeKeyAndVisible];
}

- (void)open {
    _state = ExteriaLockStateOpen;
    _leftAt = 0;
    [_controller setAsking:NO];
    _window.hidden = YES;
    _window.rootViewController = nil;
    /* the code that opened the lock is still running on the pad of this controller, so the last release waits for the end of the run loop pass */
    [_window autorelease];
    _window = nil;
    [_controller autorelease];
    _controller = nil;
    [_appWindow makeKeyWindow];
    _appWindow = nil;
}

- (void)ask {
    [self showWindow];
    _state = ExteriaLockStateAsking;
    [_controller setAsking:YES];
}

- (void)lockAtLaunch {
    if (ExteriaPasscodeEnabled()) [self ask];
}

- (void)cover {
    if (!ExteriaPasscodeEnabled() || _state != ExteriaLockStateOpen) return;
    [self showWindow];
    _state = ExteriaLockStateCover;
}

- (void)noteLeave {
    _leftAt = [[NSDate date] timeIntervalSince1970];
}

- (void)evaluateReturn {
    if (_state != ExteriaLockStateCover) {
        if (_state == ExteriaLockStateAsking) [_controller setAsking:YES];
        return;
    }
    /* a return with no leave noted was a call or the notification center over the app, which need no code */
    BOOL left = _leftAt > 0;
    BOOL lock = left && exteria_passcode_should_lock(ExteriaPasscodeAutoLock(), (int64_t)_leftAt, (int64_t)[[NSDate date] timeIntervalSince1970]);
    _leftAt = 0;
    if (lock) [self ask];
    else [self open];
}

@end
