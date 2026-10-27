#import "exteria_form_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_bar_button.h"
#import "exteria_form_layout.h"
#import "exteria_geometry.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"

#define CODE_LENGTH_FALLBACK 8
#define NAME_LENGTH_LIMIT 64

@interface ExteriaFormController () {
    ExteriaFormKind _kind;
    id<ExteriaFormControllerDelegate> _delegate;
    NSString *_heading;
    NSString *_message;
    NSString *_fieldHint;
    NSInteger _codeLength;
    BOOL _busy;
    NSString *_actionTitle;
    NSDate *_actionReady;
    NSTimer *_countdown;
    ExteriaWaveBackgroundView *_backdrop;
    ExteriaBarButton *_back;
    ExteriaBarButton *_next;
    UIActivityIndicatorView *_spinner;
    ExteriaLottieView *_art;
    /* the monkey of the password form covers its eyes while the field has the keyboard, and peeks open again when it lets go */
    ExteriaLottieView *_closeArt;
    ExteriaLottieView *_openArt;
    BOOL _artFits;
    BOOL _eyesClosed;
    BOOL _eyesOpening;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    UIView *_card;
    NSMutableArray *_fields;
    NSMutableArray *_lines;
    UILabel *_errorLabel;
    NSString *_errorText;
    BOOL _messageInNote;
    UIButton *_action;
    CGFloat _keyboardHeight;
    BOOL _visible;
}
@end

@implementation ExteriaFormController

@synthesize delegate = _delegate;
@synthesize codeLength = _codeLength;
@synthesize busy = _busy;

- (void)setFieldHint:(NSString *)hint {
    if (hint == _fieldHint) return;
    [_fieldHint release];
    _fieldHint = [hint copy];
    if (_kind != ExteriaFormKindPassword) return;
    for (UITextField *field in _fields) field.placeholder = _fieldHint.length ? _fieldHint : NSLocalizedString(@"password.placeholder", nil);
}

- (NSString *)fieldHint {
    return _fieldHint;
}

- (id)initWithKind:(ExteriaFormKind)kind {
    self = [super init];
    if (!self) return nil;
    _kind = kind;
    return self;
}

- (void)dealloc {
    [_fieldHint release];
    [_countdown invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (UITextField *field in _fields) field.delegate = nil;
    [_heading release];
    [_message release];
    [_actionTitle release];
    [_actionReady release];
    [_backdrop release];
    [_back release];
    [_next release];
    [_spinner release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(eyesOpened) object:nil];
    [_art release];
    [_closeArt release];
    [_openArt release];
    [_titleLabel release];
    [_messageLabel release];
    [_card release];
    [_fields release];
    [_lines release];
    [_errorLabel release];
    [_errorText release];
    [_action release];
    [super dealloc];
}

static UILabel *ExteriaFormLabel(UIColor *color, NSInteger lines, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    return label;
}

- (NSInteger)rowCount {
    return _kind == ExteriaFormKindName ? 2 : 1;
}

- (UITextField *)fieldForRow:(NSInteger)row {
    UITextField *field = [[[UITextField alloc] init] autorelease];
    field.delegate = self;
    field.borderStyle = UITextBorderStyleNone;
    field.backgroundColor = [UIColor clearColor];
    field.textColor = ExteriaColorTitle();
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.clearButtonMode = UITextFieldViewModeNever;
    field.returnKeyType = UIReturnKeyNext;
    switch (_kind) {
    case ExteriaFormKindCode:
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.textAlignment = ExteriaTextAlignmentCenter;
        field.placeholder = NSLocalizedString(@"code.placeholder", nil);
        break;
    case ExteriaFormKindPassword:
        field.secureTextEntry = YES;
        field.returnKeyType = UIReturnKeyGo;
        field.placeholder = _fieldHint.length ? _fieldHint : NSLocalizedString(@"password.placeholder", nil);
        break;
    case ExteriaFormKindName:
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.placeholder = NSLocalizedString(row == 0 ? @"name.first" : @"name.last", nil);
        field.returnKeyType = row == 0 ? UIReturnKeyNext : UIReturnKeyGo;
        break;
    }
    return field;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorBackdrop();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[ExteriaWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    static NSString *const stickers[] = {@"form_code", @"form_password", @"form_name"};
    _art = [[ExteriaLottieView alloc] initWithAnimationNamed:stickers[_kind]];
    [root addSubview:_art];
    if (_kind == ExteriaFormKindPassword) {
        _closeArt = [[ExteriaLottieView alloc] initWithAnimationNamed:@"form_password_close"];
        /* the first half of the animation closes the eyes and the second opens them again it: it stops where the
           eyes are shut */
        _closeArt.lastFrame = 49;
        _openArt = [[ExteriaLottieView alloc] initWithAnimationNamed:@"form_password_open"];
        _closeArt.hidden = _openArt.hidden = YES;
        [root addSubview:_closeArt];
        [root addSubview:_openArt];
    }

    _titleLabel = ExteriaFormLabel(ExteriaColorTitle(), 1, ExteriaTextAlignmentCenter);
    _titleLabel.text = _heading;
    [root addSubview:_titleLabel];
    _messageLabel = ExteriaFormLabel(ExteriaColorMessage(), 0, ExteriaTextAlignmentCenter);
    _messageLabel.text = _message;
    [root addSubview:_messageLabel];

    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.masksToBounds = YES;
    _card.layer.borderWidth = 1.0 / ExteriaScreenScale();
    _card.layer.borderColor = ExteriaColorHairline().CGColor;
    [root addSubview:_card];

    _fields = [[NSMutableArray alloc] init];
    _lines = [[NSMutableArray alloc] init];
    for (NSInteger row = 0; row < [self rowCount]; ++row) {
        UITextField *field = [self fieldForRow:row];
        [_fields addObject:field];
        [_card addSubview:field];
        if (row > 0) {
            UIView *line = [[[UIView alloc] init] autorelease];
            line.backgroundColor = ExteriaColorHairline();
            [_lines addObject:line];
            [_card addSubview:line];
        }
    }

    _errorLabel = ExteriaFormLabel([UIColor colorWithRed:0.82 green:0.18 blue:0.2 alpha:1], 2, ExteriaTextAlignmentCenter);
    [root addSubview:_errorLabel];
    [self refreshNote];

    _action = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _action.backgroundColor = [UIColor clearColor];
    [_action setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_action setTitleColor:ExteriaColorMessage() forState:UIControlStateDisabled];
    [_action addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_action];

    _back = [[ExteriaBarButton alloc] init];
    _back.chevron = YES;
    _back.title = NSLocalizedString(@"phone.back", nil);
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_back];
    _next = [[ExteriaBarButton alloc] init];
    _next.bold = YES;
    _next.title = NSLocalizedString(@"phone.next", nil);
    [_next addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_next];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];

    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)] autorelease];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [root addGestureRecognizer:tap];

    [self refreshAction];
    [self refreshState];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

/* only a tap on bare background closes the keyboard; fields and buttons keep their own taps */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
        if ([view isKindOfClass:[UIControl class]] || [view isKindOfClass:[UITextField class]]) return NO;
    }
    return YES;
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

#pragma mark properties

- (NSString *)heading {
    return _heading;
}

- (void)setHeading:(NSString *)heading {
    if (heading == _heading || [heading isEqualToString:_heading]) return;
    [_heading release];
    _heading = [heading copy];
    _titleLabel.text = _heading;
}

- (NSString *)message {
    return _message;
}

- (void)setMessage:(NSString *)message {
    if (message == _message || [message isEqualToString:_message]) return;
    [_message release];
    _message = [message copy];
    _messageLabel.text = _message;
}

- (void)setBusy:(BOOL)busy {
    if (busy == _busy) return;
    _busy = busy;
    [self refreshState];
}

- (void)showError:(NSString *)text {
    [_errorText release];
    _errorText = [(text.length ? text : nil) copy];
    [self refreshNote];
    /* with no room for the line, the keyboard hides the only other place the text could show */
    if (_errorText && self.isViewLoaded && _errorLabel.hidden) [self showErrorAlert];
}

/* the line under the card shows the error; when the keyboard leaves no room for the message above the card,
   that line shows the message instead until an error needs it */
- (void)refreshNote {
    BOOL error = _errorText.length > 0;
    _errorLabel.text = error ? _errorText : (_messageInNote ? _message : nil);
    _errorLabel.textColor = error ? [UIColor colorWithRed:0.82 green:0.18 blue:0.2 alpha:1] : ExteriaColorSecondary();
}

- (void)showErrorAlert {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:nil message:_errorText delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)clearFields {
    for (UITextField *field in _fields) field.text = @"";
    [self refreshState];
}

#pragma mark action and countdown

- (void)setActionTitle:(NSString *)title waitSeconds:(NSInteger)seconds {
    [_actionTitle release];
    _actionTitle = [title copy];
    [_actionReady release];
    _actionReady = seconds > 0 ? [[NSDate dateWithTimeIntervalSinceNow:seconds] retain] : nil;
    [self refreshAction];
    [self restartCountdown];
}

- (void)restartCountdown {
    [_countdown invalidate];
    _countdown = nil;
    if (!_actionReady || !_visible) return;
    _countdown = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(countdownTick)
                                                userInfo:nil repeats:YES];
}

- (void)countdownTick {
    if ([_actionReady timeIntervalSinceNow] <= 0) {
        [_actionReady release];
        _actionReady = nil;
        [_countdown invalidate];
        _countdown = nil;
    }
    [self refreshAction];
}

- (void)refreshAction {
    if (!_action) return;
    NSTimeInterval left = _actionReady ? [_actionReady timeIntervalSinceNow] : 0;
    BOOL waiting = left > 0;
    NSString *title = _actionTitle;
    if (waiting && _actionTitle) {
        NSInteger seconds = (NSInteger)ceil(left);
        title = [NSString stringWithFormat:NSLocalizedString(@"code.resend.wait", nil), (int)(seconds / 60), (int)(seconds % 60)];
    }
    [_action setTitle:title forState:UIControlStateNormal];
    [_action setTitle:title forState:UIControlStateDisabled];
    _action.enabled = !waiting && !_busy;
    _action.hidden = _actionTitle == nil || _action.frame.size.height <= 0;
}

- (void)actionTapped {
    [_delegate formControllerDidTapAction:self];
}

#pragma mark layout

- (void)applyLayout {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat side = insets.left;
    exteria_form_metrics metrics = {size.width - insets.left - insets.right, size.height - _keyboardHeight, insets.top,
                                    _keyboardHeight > 0 ? 0 : insets.bottom, ExteriaIsPad() ? 1 : 0, (int)[self rowCount]};
    exteria_form_layout layout;
    if (exteria_form_layout_compute(&metrics, &layout) != EXTERIA_OK) {
        NSLog(@"exteria: form layout does not fit %.0fx%.0f", metrics.width, metrics.height);
    }

    _backdrop.frame = self.view.bounds;
    _back.frame = ExteriaCGRectOffset(layout.back, side, 0);
    _next.frame = ExteriaCGRectOffset(layout.next, side, 0);
    _back.titleSize = _next.titleSize = (CGFloat)layout.bar_size;
    _spinner.center = CGPointMake(CGRectGetMaxX(_next.frame) - 26, CGRectGetMidY(_next.frame));

    _art.frame = _closeArt.frame = _openArt.frame = ExteriaCGRectOffset(layout.art, side, 0);
    _artFits = layout.art.height > 0;
    [self refreshArtPlayback];
    _titleLabel.frame = ExteriaCGRectOffset(layout.title, side, 0);
    _titleLabel.hidden = layout.title.height <= 0;
    _titleLabel.font = ExteriaFontBold((CGFloat)layout.title_size);
    _messageLabel.frame = ExteriaCGRectOffset(layout.message, side, 0);
    _messageLabel.hidden = layout.message.height <= 0;
    _messageLabel.font = ExteriaFontRegular((CGFloat)layout.message_size);

    _card.frame = ExteriaCGRectOffset(layout.card, side, 0);
    _card.layer.cornerRadius = (CGFloat)layout.card_radius;
    CGFloat hairline = 1.0 / ExteriaScreenScale();
    UIFont *fieldFont = ExteriaFontRegular((CGFloat)layout.field_size);
    for (NSInteger row = 0; row < [self rowCount]; ++row) {
        CGRect cell = ExteriaCGRectOffset(layout.rows[row], -layout.card.x, -layout.card.y);
        UITextField *field = [_fields objectAtIndex:row];
        field.font = fieldFont;
        field.frame = CGRectMake(16, cell.origin.y, cell.size.width - 32, cell.size.height);
        if (row > 0) {
            UIView *line = [_lines objectAtIndex:row - 1];
            line.frame = CGRectMake(0, cell.origin.y - hairline / 2, cell.size.width, hairline);
        }
    }

    _errorLabel.frame = ExteriaCGRectOffset(layout.error, side, 0);
    _errorLabel.hidden = layout.error.height <= 0;
    _messageInNote = layout.message.height <= 0 && layout.error.height > 0;
    [self refreshNote];
    _errorLabel.font = ExteriaFontRegular((CGFloat)layout.note_size);
    _action.frame = ExteriaCGRectOffset(layout.action, side, 0);
    _action.titleLabel.font = ExteriaFontRegular((CGFloat)layout.field_size - 2);
    [self refreshAction];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self applyLayout];
}

/* the sticker holds its parsed animation only while it is on screen */
- (void)refreshArtPlayback {
    _art.hidden = !_artFits || _eyesClosed || _eyesOpening;
    BOOL shown = _visible && !_art.hidden;
    [_art setLoaded:shown];
    [_art setPlaying:shown];
    _closeArt.hidden = !_artFits || !_eyesClosed;
    _openArt.hidden = !_artFits || !_eyesOpening;
    if (_closeArt.hidden) [_closeArt setLoaded:NO];
    if (_openArt.hidden) [_openArt setLoaded:NO];
}

/* the password field took or gave up the keyboard: the monkey closes its eyes at once and stays so, or peeks and goes back to its idle loop */
- (void)setEyesClosed:(BOOL)closed {
    if (_kind != ExteriaFormKindPassword || closed == _eyesClosed) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(eyesOpened) object:nil];
    _eyesClosed = closed;
    _eyesOpening = !closed;
    [self refreshArtPlayback];
    ExteriaLottieView *moving = closed ? _closeArt : _openArt;
    if (!moving.hidden) {
        [moving rewind];
        [moving playOnce];
    }
    if (!closed) [self performSelector:@selector(eyesOpened) withObject:nil afterDelay:0.6];
}

- (void)eyesOpened {
    _eyesOpening = NO;
    [self refreshArtPlayback];
}

- (void)textFieldDidBeginEditing:(UITextField *)field {
    (void)field;
    [self setEyesClosed:YES];
}

- (void)textFieldDidEndEditing:(UITextField *)field {
    (void)field;
    [self setEyesClosed:NO];
}

#pragma mark keyboard

- (void)keyboardChanged:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect end = [self.view convertRect:[[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat height = MAX(0, self.view.bounds.size.height - end.origin.y);
    if (height == _keyboardHeight) return;
    _keyboardHeight = height;
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSUInteger curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)((curve << 16) | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{ [self applyLayout]; } completion:NULL];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    [self refreshArtPlayback];
    [self restartCountdown];
    [self refreshAction];
    /* the code is read from the sms or the other device, and a keyboard that comes up by itself covers the message about it */
    if (!_busy && _kind != ExteriaFormKindCode) [[_fields objectAtIndex:0] becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [self refreshArtPlayback];
    [_countdown invalidate];
    _countdown = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.view endEditing:YES];
    _keyboardHeight = 0;
}

#pragma mark state

- (NSArray *)values {
    NSMutableArray *values = [NSMutableArray array];
    for (UITextField *field in _fields) {
        NSString *text = field.text ? field.text : @"";
        [values addObject:_kind == ExteriaFormKindPassword ? text : [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    }
    return values;
}

- (BOOL)valid {
    NSArray *values = [self values];
    NSString *first = [values objectAtIndex:0];
    if (_kind == ExteriaFormKindCode && _codeLength > 0) return (NSInteger)first.length == _codeLength;
    return first.length > 0;
}

- (void)refreshState {
    if (!_next) return;
    _next.dimmed = _busy || ![self valid];
    _next.hidden = _busy;
    if (_busy) [_spinner startAnimating];
    else [_spinner stopAnimating];
    for (UITextField *field in _fields) field.enabled = !_busy;
    [self refreshAction];
}

#pragma mark text fields

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *proposed = [field.text stringByReplacingCharactersInRange:range withString:string];
    if (_kind == ExteriaFormKindCode) {
        NSMutableString *digits = [NSMutableString string];
        for (NSUInteger i = 0; i < proposed.length; ++i) {
            unichar c = [proposed characterAtIndex:i];
            if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
        }
        NSUInteger limit = _codeLength > 0 ? (NSUInteger)_codeLength : CODE_LENGTH_FALLBACK;
        if (digits.length > limit) [digits deleteCharactersInRange:NSMakeRange(limit, digits.length - limit)];
        field.text = digits;
        [self showError:nil];
        [self refreshState];
        if (_codeLength > 0 && (NSInteger)digits.length == _codeLength) [self submit];
        return NO;
    }
    if (_kind == ExteriaFormKindName && proposed.length > NAME_LENGTH_LIMIT) return NO;
    [self showError:nil];
    /* the field has not taken the change yet, so the button state is read on the next turn */
    [self performSelector:@selector(refreshState) withObject:nil afterDelay:0];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSUInteger index = [_fields indexOfObject:field];
    if (index + 1 < [_fields count]) {
        [[_fields objectAtIndex:index + 1] becomeFirstResponder];
        return NO;
    }
    [self submit];
    return NO;
}

#pragma mark actions

- (void)goBack {
    [_delegate formControllerDidGoBack:self];
}

- (void)submit {
    if (_busy || ![self valid]) return;
    [self.view endEditing:YES];
    [self showError:nil];
    [_delegate formController:self didSubmitValues:[self values]];
}

@end
