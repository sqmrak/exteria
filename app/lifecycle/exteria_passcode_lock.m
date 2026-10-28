#import "exteria_passcode_lock.h"

#import "exteria_biometric.h"
#import "exteria_passcode_entry_view.h"
#import "exteria_passcode_store.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaPasscodeLockController : UIViewController {
    ExteriaPasscodeEntryView *_entry;
    void (^_unlocked)(void);
    BOOL _asking;
    ExteriaWeakReference *_weak;
    /* the open question to the sensor, nil when none runs */
    id _biometricToken;
    /* the sensor is asked by itself once for each time the lock rises; after that only its button asks, or a cancelled sheet would come back
       on every return of the app to the foreground */
    BOOL _biometricOffered;
}
- (id)initWithUnlocked:(void (^)(void))unlocked;
/* the plain color, or the pad that asks for the code */
- (void)setAsking:(BOOL)asking;
/* once per rise of the lock, when the app is active */
- (void)offerBiometric;
- (void)askBiometric;
- (void)codeEntered:(NSString *)code;
@end

@implementation ExteriaPasscodeLockController

- (id)initWithUnlocked:(void (^)(void))unlocked {
    self = [super init];
    if (!self) return nil;
    _unlocked = [unlocked copy];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    ExteriaBiometricCancel(_biometricToken);
    [_biometricToken release];
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
        [self cancelBiometric];
        [_entry resignFirstResponder];
        return;
    }
    _biometricOffered = NO;
    [self applyBiometricButton];
    _entry.type = ExteriaPasscodeType();
    _entry.title = NSLocalizedString(@"passcode.enter", nil);
    _entry.message = nil;
    [_entry reset];
    [_entry holdForSeconds:ExteriaPasscodeWaitRemaining()];
    [_entry focus];
}

- (BOOL)biometricWanted {
    return ExteriaPasscodeBiometricEnabled() && ExteriaBiometricAvailable() != ExteriaBiometricNone;
}

- (void)applyBiometricButton {
    ExteriaPasscodeLockController *lock = self;
    BOOL wanted = [self biometricWanted];
    _entry.biometricTitle = wanted ? ExteriaBiometricName(ExteriaBiometricAvailable()) : nil;
    _entry.biometric = wanted ? ^{ [lock askBiometric]; } : nil;
}

- (void)cancelBiometric {
    ExteriaBiometricCancel(_biometricToken);
    [_biometricToken release];
    _biometricToken = nil;
}

- (void)askBiometric {
    if (!_asking || _biometricToken || ![self biometricWanted]) return;
    ExteriaWeakReference *weak = _weak;
    _biometricToken = [ExteriaBiometricEvaluate(NSLocalizedString(@"passcode.biometric.reason", nil), ^(BOOL matched) {
        ExteriaPasscodeLockController *me = weak.target;
        if (!me) return;
        [me->_biometricToken release];
        me->_biometricToken = nil;
        if (matched && me->_asking && me->_unlocked) me->_unlocked();
    }) retain];
}

/* the app is active: the sensor cannot be asked from an inactive app, and the first return after the lock rose is the first moment it can */
- (void)offerBiometric {
    if (_biometricOffered || !_asking) return;
    _biometricOffered = YES;
    [self askBiometric];
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
        if (_state == ExteriaLockStateAsking) {
            [_controller setAsking:YES];
            [_controller offerBiometric];
        }
        return;
    }
    /* a return with no leave noted was a call or the notification center over the app, which need no code */
    BOOL left = _leftAt > 0;
    BOOL lock = left && exteria_passcode_should_lock(ExteriaPasscodeAutoLock(), (int64_t)_leftAt, (int64_t)[[NSDate date] timeIntervalSince1970]);
    _leftAt = 0;
    if (lock) {
        [self ask];
        [_controller offerBiometric];
    } else {
        [self open];
    }
}

@end
