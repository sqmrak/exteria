#import "exteria_login_flow.h"

typedef enum {
    ExteriaLoginStagePhone,
    ExteriaLoginStageCode,
    ExteriaLoginStagePassword,
    ExteriaLoginStageName,
    ExteriaLoginStageRecovery,
    ExteriaLoginStageQr
} ExteriaLoginStage;

@interface ExteriaLoginFlow () {
    UINavigationController *_navigation;
    ExteriaSession *_session;
    ExteriaCountryBook *_book;
    ExteriaPhoneController *_phone;
    ExteriaFormController *_form;
    ExteriaQrController *_qr;
    NSString *_display;
    ExteriaLoginStage _stage;
    BOOL _hasRecovery;
    /* events that arrive after the user backed out belong to a request nobody waits for */
    BOOL _awaiting;
}
@end

@implementation ExteriaLoginFlow

@synthesize delegate = _delegate;

- (id)initWithNavigation:(UINavigationController *)navigation session:(ExteriaSession *)session
            countryBook:(ExteriaCountryBook *)book {
    self = [super init];
    if (!self) return nil;
    _navigation = [navigation retain];
    _session = [session retain];
    _book = [book retain];
    return self;
}

- (void)dealloc {
    _phone.delegate = nil;
    _form.delegate = nil;
    _qr.delegate = nil;
    if (_session.delegate == self) _session.delegate = nil;
    [_navigation release];
    [_session release];
    [_book release];
    [_phone release];
    [_form release];
    [_qr release];
    [_display release];
    [super dealloc];
}

- (void)begin {
    _session.delegate = self;
    [_phone release];
    _phone = [[ExteriaPhoneController alloc] initWithCountryBook:_book];
    _phone.delegate = self;
    _stage = ExteriaLoginStagePhone;
    _awaiting = NO;
    [_navigation pushViewController:_phone animated:YES];
}

- (void)beginWithQr {
    _session.delegate = self;
    [_phone release];
    _phone = [[ExteriaPhoneController alloc] initWithCountryBook:_book];
    _phone.delegate = self;
    [self phoneControllerDidRequestQr:_phone];
}

#pragma mark texts

static NSString *ExteriaDuration(NSInteger seconds) {
    if (seconds < 120) return [NSString stringWithFormat:NSLocalizedString(@"duration.seconds", nil), (int)seconds];
    if (seconds < 7200) return [NSString stringWithFormat:NSLocalizedString(@"duration.minutes", nil), (int)((seconds + 59) / 60)];
    return [NSString stringWithFormat:NSLocalizedString(@"duration.hours", nil), (int)((seconds + 3599) / 3600)];
}

static NSString *ExteriaLoginErrorText(ExteriaAuthEvent *event) {
    static NSString *const known[][2] = {
        {@"PHONE_NUMBER_INVALID", @"error.phone.invalid"},
        {@"PHONE_NUMBER_BANNED", @"error.phone.banned"},
        {@"PHONE_NUMBER_FLOOD", @"error.flood.generic"},
        {@"SEND_CODE_UNAVAILABLE", @"error.code.unavailable"},
        {@"PHONE_CODE_INVALID", @"error.code.invalid"},
        {@"PHONE_CODE_EMPTY", @"error.code.invalid"},
        {@"PHONE_CODE_EXPIRED", @"error.code.expired"},
        {@"PASSWORD_HASH_INVALID", @"error.password.invalid"},
        {@"PASSWORD_RECOVERY_NA", @"error.recovery.unavailable"},
        {@"PASSWORD_RECOVERY_EXPIRED", @"error.code.expired"},
        {@"CODE_INVALID", @"error.code.invalid"},
        {@"CODE_EMPTY", @"error.code.invalid"},
        {@"AUTH_RESTART", @"error.auth.restart"},
        {@"PHONE_CODE_HASH_EMPTY", @"error.auth.restart"},
        {@"API_ID_INVALID", @"error.api"},
        {@"API_ID_PUBLISHED_FLOOD", @"error.api"},
        {@"TIMEOUT", @"error.timeout"},
        {@"INTERNAL", @"error.internal"},
        {@"STORAGE", @"error.storage"},
    };
    switch (event.kind) {
    case ExteriaAuthEventOffline:
        return NSLocalizedString(@"error.offline", nil);
    case ExteriaAuthEventUnsupported:
        return NSLocalizedString(@"error.unsupported", nil);
    default:
        break;
    }
    NSString *name = event.errorName;
    if ([name isEqualToString:@"FLOOD_WAIT"] || [name isEqualToString:@"FLOOD_PREMIUM_WAIT"]) {
        return [NSString stringWithFormat:NSLocalizedString(@"error.flood", nil), ExteriaDuration(event.errorNumber)];
    }
    for (size_t i = 0; i < sizeof(known) / sizeof(known[0]); ++i) {
        if ([name isEqualToString:known[i][0]]) return NSLocalizedString(known[i][1], nil);
    }
    return [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), name];
}

static NSString *ExteriaCodeMessage(ExteriaCodeKind kind) {
    switch (kind) {
    case ExteriaCodeKindApp: return NSLocalizedString(@"code.message.app", nil);
    case ExteriaCodeKindSms: return NSLocalizedString(@"code.message.sms", nil);
    case ExteriaCodeKindCall: return NSLocalizedString(@"code.message.call", nil);
    case ExteriaCodeKindOther: break;
    }
    return NSLocalizedString(@"code.message.other", nil);
}

/* the code screen names the number without printing it whole: the plus, the first digit and the last four */
static NSString *ExteriaMaskedNumber(NSString *number) {
    NSString *digits = [number hasPrefix:@"+"] ? [number substringFromIndex:1] : number;
    if (digits.length < 6) return @"+\u2022\u2022\u2022";
    return [NSString stringWithFormat:@"+%@ \u2022\u2022\u2022 %@", [digits substringToIndex:1],
            [digits substringFromIndex:digits.length - 4]];
}

#pragma mark screens

- (ExteriaFormController *)pushFormOfKind:(ExteriaFormKind)kind {
    [_form release];
    _form = [[ExteriaFormController alloc] initWithKind:kind];
    _form.delegate = self;
    [_navigation pushViewController:_form animated:YES];
    return _form;
}

- (void)applyCode:(ExteriaAuthEvent *)event toForm:(ExteriaFormController *)form {
    form.message = ExteriaCodeMessage(event.codeKind);
    form.codeLength = event.codeLength;
    [form setActionTitle:event.resendAfter >= 0 ? NSLocalizedString(@"code.resend", nil) : nil
             waitSeconds:event.resendAfter];
}

- (void)showFailure:(ExteriaAuthEvent *)event {
    NSString *text = ExteriaLoginErrorText(event);
    if (_stage == ExteriaLoginStageQr) {
        [_qr showFailure:text];
        return;
    }
    if (_stage == ExteriaLoginStagePhone) {
        _phone.busy = NO;
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil
                                   cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
        return;
    }
    _form.busy = NO;
    [_form showError:text];
}

#pragma mark session

- (void)session:(ExteriaSession *)session didReceiveAuthEvent:(ExteriaAuthEvent *)event {
    (void)session;
    if (!_awaiting) return;
    switch (event.kind) {
    case ExteriaAuthEventCode:
        if (_stage == ExteriaLoginStagePhone) {
            _phone.busy = NO;
            ExteriaFormController *form = [self pushFormOfKind:ExteriaFormKindCode];
            form.heading = _display;
            [self applyCode:event toForm:form];
            _stage = ExteriaLoginStageCode;
        } else {
            _form.busy = NO;
            [_form clearFields];
            [self applyCode:event toForm:_form];
        }
        break;
    case ExteriaAuthEventQr:
        if (_stage == ExteriaLoginStageQr) [_qr showUrl:event.qrUrl];
        break;
    case ExteriaAuthEventPassword:
        if (_stage == ExteriaLoginStageCode || _stage == ExteriaLoginStageQr) {
            ExteriaFormController *form = [self pushFormOfKind:ExteriaFormKindPassword];
            form.heading = NSLocalizedString(@"password.title", nil);
            form.message = event.hint.length
                ? [NSString stringWithFormat:NSLocalizedString(@"password.hint", nil), event.hint]
                : NSLocalizedString(@"password.message", nil);
            form.fieldHint = event.hint;
            [form setActionTitle:NSLocalizedString(@"password.forgot", nil) waitSeconds:0];
            _hasRecovery = event.hasRecovery;
            _stage = ExteriaLoginStagePassword;
        } else {
            /* the server asked for a fresh challenge after a stale one */
            _form.busy = NO;
        }
        break;
    case ExteriaAuthEventRecovery:
        if (_stage == ExteriaLoginStagePassword) {
            ExteriaFormController *form = [self pushFormOfKind:ExteriaFormKindCode];
            form.heading = NSLocalizedString(@"recovery.title", nil);
            form.message = [NSString stringWithFormat:NSLocalizedString(@"recovery.message", nil), event.emailPattern.length ? event.emailPattern : @""];
            _stage = ExteriaLoginStageRecovery;
        } else {
            _form.busy = NO;
        }
        break;
    case ExteriaAuthEventSignUp: {
        ExteriaFormController *form = [self pushFormOfKind:ExteriaFormKindName];
        form.heading = NSLocalizedString(@"name.title", nil);
        form.message = NSLocalizedString(@"name.message", nil);
        _stage = ExteriaLoginStageName;
        break;
    }
    case ExteriaAuthEventAuthorized:
        _awaiting = NO;
        [_delegate loginFlow:self didAuthorizeUser:event.userId];
        break;
    case ExteriaAuthEventFailed:
    case ExteriaAuthEventUnsupported:
    case ExteriaAuthEventOffline:
        _awaiting = NO;
        [self showFailure:event];
        break;
    case ExteriaAuthEventLoggedOut:
        break;
    }
}

#pragma mark phone screen

- (void)phoneController:(ExteriaPhoneController *)controller didSubmitNumber:(NSString *)number {
    (void)controller;
    [_display release];
    _display = [ExteriaMaskedNumber(number) copy];
    _phone.busy = YES;
    _awaiting = YES;
    [_session requestCodeForNumber:number];
}

#pragma mark qr screen

- (void)phoneControllerDidRequestQr:(ExteriaPhoneController *)controller {
    (void)controller;
    [_qr release];
    _qr = [[ExteriaQrController alloc] init];
    _qr.delegate = self;
    _stage = ExteriaLoginStageQr;
    _awaiting = YES;
    [_navigation pushViewController:_qr animated:YES];
    [_session requestQrLogin];
}

/* the code screen and the phone screen are two ways into the same login, so leaving one for the other gives the first up */
- (void)leaveQr {
    _awaiting = NO;
    [_session cancelLogin];
    _stage = ExteriaLoginStagePhone;
    _phone.busy = NO;
    if ([_navigation.viewControllers containsObject:_phone]) [_navigation popToViewController:_phone animated:YES];
    else [_navigation popViewControllerAnimated:YES];
}

/* the QR screen was opened from the welcome screen, so the phone screen is not under it: it takes its place */
- (void)replaceQrWithPhone {
    _awaiting = NO;
    [_session cancelLogin];
    _stage = ExteriaLoginStagePhone;
    _phone.busy = NO;
    if ([_navigation.viewControllers containsObject:_phone]) {
        [_navigation popToViewController:_phone animated:YES];
        return;
    }
    NSMutableArray *stack = [NSMutableArray arrayWithArray:_navigation.viewControllers];
    [stack removeLastObject];
    [stack addObject:_phone];
    [_navigation setViewControllers:stack animated:YES];
}

- (void)qrControllerDidGoBack:(ExteriaQrController *)controller {
    (void)controller;
    [self leaveQr];
}

- (void)qrControllerDidChoosePhone:(ExteriaQrController *)controller {
    (void)controller;
    [self replaceQrWithPhone];
}

- (void)qrControllerDidRequestRetry:(ExteriaQrController *)controller {
    (void)controller;
    _awaiting = YES;
    [_session cancelLogin];
    [_session requestQrLogin];
}

#pragma mark form screens

- (void)formController:(ExteriaFormController *)controller didSubmitValues:(NSArray *)values {
    controller.busy = YES;
    _awaiting = YES;
    switch (_stage) {
    case ExteriaLoginStageCode:
        [_session submitCode:[values objectAtIndex:0]];
        break;
    case ExteriaLoginStagePassword:
        [_session submitPassword:[values objectAtIndex:0]];
        break;
    case ExteriaLoginStageRecovery:
        [_session submitRecoveryCode:[values objectAtIndex:0]];
        break;
    case ExteriaLoginStageName:
        [_session submitFirstName:[values objectAtIndex:0] lastName:[values objectAtIndex:1]];
        break;
    case ExteriaLoginStagePhone:
    case ExteriaLoginStageQr:
        break;
    }
}

- (void)formControllerDidTapAction:(ExteriaFormController *)controller {
    if (_stage == ExteriaLoginStagePassword) {
        /* without a recovery e-mail the only way back in is the seven-day reset, which only the official apps can ask for */
        if (!_hasRecovery) {
            Class alertClass = NSClassFromString(@"UIAlertView");
            id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"recovery.none.title", nil) message:NSLocalizedString(@"recovery.none.message", nil)
                                                delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
            [alert show];
            [alert release];
            return;
        }
        controller.busy = YES;
        _awaiting = YES;
        [_session requestPasswordRecovery];
        return;
    }
    controller.busy = YES;
    _awaiting = YES;
    [_session resendCode];
}

/* the state machine cannot step back, so every back button cancels the login and returns to the phone */
- (void)formControllerDidGoBack:(ExteriaFormController *)controller {
    (void)controller;
    _awaiting = NO;
    [_session cancelLogin];
    _stage = ExteriaLoginStagePhone;
    _phone.busy = NO;
    [_navigation popToViewController:_phone animated:YES];
}

@end
