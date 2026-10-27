#import "exteria_phone_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_bar_button.h"
#import "exteria_frame_view.h"
#import "exteria_geometry.h"
#import "exteria_phone.h"
#import "exteria_phone_layout.h"
#import "exteria_phone_ring.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"

@interface ExteriaPhoneController () <UIGestureRecognizerDelegate> {
    ExteriaCountryBook *_book;
    ExteriaCountry *_country;
    NSString *_codeDigits;
    NSString *_nationalDigits;
    ExteriaWaveBackgroundView *_backdrop;
    ExteriaBarButton *_back;
    ExteriaBarButton *_next;
    UIActivityIndicatorView *_spinner;
    UIButton *_qr;
    BOOL _busy;
    ExteriaFrameView *_art;
    UILabel *_title;
    UILabel *_message;
    UIView *_card;
    UIControl *_countryRow;
    UIImageView *_flagView;
    UILabel *_countryName;
    UILabel *_chevron;
    UIView *_rowLine;
    UIView *_cellLine;
    UILabel *_plus;
    UITextField *_codeField;
    UITextField *_numberField;
    CGFloat _keyboardHeight;
    BOOL _visible;
}
@end

@implementation ExteriaPhoneController

@synthesize delegate = _delegate;
@synthesize busy = _busy;

- (id)initWithCountryBook:(ExteriaCountryBook *)book {
    self = [super init];
    if (!self) return nil;
    _book = [book retain];
    _country = [_book localCountry];
    _codeDigits = [(_country ? _country.code : @"") copy];
    _nationalDigits = [@"" copy];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _codeField.delegate = nil;
    _numberField.delegate = nil;
    [_book release];
    [_codeDigits release];
    [_nationalDigits release];
    [_backdrop release];
    [_back release];
    [_next release];
    [_spinner release];
    [_qr release];
    [_art release];
    [_title release];
    [_message release];
    [_card release];
    [_countryRow release];
    [_flagView release];
    [_countryName release];
    [_chevron release];
    [_rowLine release];
    [_cellLine release];
    [_plus release];
    [_codeField release];
    [_numberField release];
    [super dealloc];
}

static UILabel *ExteriaPhoneLabel(UIColor *color, NSInteger lines, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    return label;
}

static UIView *ExteriaHairline(void) {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = ExteriaColorHairline();
    return line;
}

static UITextField *ExteriaPhoneField(id<UITextFieldDelegate> delegate) {
    UITextField *field = [[UITextField alloc] init];
    field.delegate = delegate;
    field.borderStyle = UITextBorderStyleNone;
    field.backgroundColor = [UIColor clearColor];
    field.textColor = ExteriaColorTitle();
    field.keyboardType = UIKeyboardTypePhonePad;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
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

    _art = [[ExteriaFrameView alloc] initWithPrefix:@"phone_ring" count:EXTERIA_PHONE_RING_FRAMES
                                    framesPerSecond:EXTERIA_PHONE_RING_FPS];
    [root addSubview:_art];

    _title = ExteriaPhoneLabel(ExteriaColorTitle(), 1, ExteriaTextAlignmentCenter);
    _title.text = NSLocalizedString(@"phone.title", nil);
    [root addSubview:_title];
    _message = ExteriaPhoneLabel(ExteriaColorMessage(), 0, ExteriaTextAlignmentCenter);
    _message.text = NSLocalizedString(@"phone.message", nil);
    [root addSubview:_message];

    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.masksToBounds = YES;
    _card.layer.borderWidth = 1.0 / ExteriaScreenScale();
    _card.layer.borderColor = ExteriaColorHairline().CGColor;
    [root addSubview:_card];

    _countryRow = [[UIControl alloc] init];
    [_countryRow addTarget:self action:@selector(chooseCountry) forControlEvents:UIControlEventTouchUpInside];
    [_countryRow addTarget:self action:@selector(rowDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_countryRow addTarget:self action:@selector(rowUp)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _countryRow.isAccessibilityElement = YES;
    _countryRow.accessibilityTraits = UIAccessibilityTraitButton;
    [_card addSubview:_countryRow];
    _flagView = [[UIImageView alloc] init];
    _flagView.userInteractionEnabled = NO;
    [_countryRow addSubview:_flagView];
    _countryName = ExteriaPhoneLabel(ExteriaColorTitle(), 1, ExteriaTextAlignmentLeft);
    [_countryRow addSubview:_countryName];
    _chevron = ExteriaPhoneLabel(ExteriaColorDotOff(), 1, ExteriaTextAlignmentCenter);
    _chevron.text = @"\u203A";
    [_countryRow addSubview:_chevron];

    _rowLine = ExteriaHairline();
    [_card addSubview:_rowLine];
    _cellLine = ExteriaHairline();
    [_card addSubview:_cellLine];

    _plus = ExteriaPhoneLabel(ExteriaColorTitle(), 1, ExteriaTextAlignmentLeft);
    _plus.text = @"+";
    [_card addSubview:_plus];
    _codeField = ExteriaPhoneField(self);
    [_card addSubview:_codeField];
    _numberField = ExteriaPhoneField(self);
    [_card addSubview:_numberField];

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

    _qr = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_qr setTitle:NSLocalizedString(@"phone.qr", nil) forState:UIControlStateNormal];
    [_qr setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_qr setTitleColor:ExteriaColorMuted() forState:UIControlStateDisabled];
    [_qr addTarget:self action:@selector(openQr) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_qr];

    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)] autorelease];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [root addGestureRecognizer:tap];

    _codeField.text = _codeDigits;
    [self refreshCountry];
    [self refreshNumber];
}

- (void)openQr {
    if (_busy) return;
    [_delegate phoneControllerDidRequestQr:self];
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

#pragma mark layout

- (void)applyLayout {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat side = insets.left;
    exteria_phone_metrics metrics = {size.width - insets.left - insets.right, size.height - _keyboardHeight,
                                     insets.top, _keyboardHeight > 0 ? 0 : insets.bottom, ExteriaIsPad() ? 1 : 0};
    exteria_phone_layout layout;
    if (exteria_phone_layout_compute(&metrics, &layout) != EXTERIA_OK) {
        NSLog(@"exteria: phone layout does not fit %.0fx%.0f", metrics.width, metrics.height);
    }

    _backdrop.frame = self.view.bounds;
    _back.frame = ExteriaCGRectOffset(layout.back, side, 0);
    _next.frame = ExteriaCGRectOffset(layout.next, side, 0);
    _back.titleSize = _next.titleSize = (CGFloat)layout.bar_size;
    _spinner.center = CGPointMake(CGRectGetMaxX(_next.frame) - 26, CGRectGetMidY(_next.frame));

    _art.frame = ExteriaCGRectOffset(layout.art, side, 0);
    _art.hidden = layout.art.width <= 0;
    _title.frame = ExteriaCGRectOffset(layout.title, side, 0);
    _title.hidden = layout.title.height <= 0;
    _title.font = ExteriaFontBold((CGFloat)layout.title_size);
    _message.frame = ExteriaCGRectOffset(layout.message, side, 0);
    _message.hidden = layout.message.height <= 0;
    _message.font = ExteriaFontRegular((CGFloat)layout.message_size);

    _card.frame = ExteriaCGRectOffset(layout.card, side, 0);
    _card.layer.cornerRadius = (CGFloat)layout.card_radius;
    CGFloat rowHeight = (CGFloat)layout.country_row.height;
    CGFloat cardWidth = (CGFloat)layout.card.width;
    CGFloat hairline = 1.0 / ExteriaScreenScale();
    _countryRow.frame = CGRectMake(0, 0, cardWidth, rowHeight);
    CGFloat flagWidth = (CGFloat)layout.flag_width;
    CGFloat flagHeight = (CGFloat)layout.flag_height;
    _flagView.frame = CGRectMake(16, (rowHeight - flagHeight) / 2, flagWidth, flagHeight);
    _chevron.font = ExteriaFontRegular((CGFloat)layout.field_size + 7);
    _chevron.frame = CGRectMake(cardWidth - 38, 0, 30, rowHeight);
    _countryName.font = ExteriaFontRegular((CGFloat)layout.field_size);
    _countryName.frame = CGRectMake(16 + flagWidth + 12, 0, cardWidth - 16 - flagWidth - 12 - 38, rowHeight);
    _rowLine.frame = CGRectMake(0, rowHeight - hairline / 2, cardWidth, hairline);

    CGFloat codeWidth = (CGFloat)layout.code_cell.width;
    _cellLine.frame = CGRectMake(codeWidth - hairline / 2, rowHeight, hairline, rowHeight);
    UIFont *fieldFont = ExteriaFontRegular((CGFloat)layout.field_size);
    _plus.font = fieldFont;
    _plus.frame = CGRectMake(16, rowHeight, 14, rowHeight);
    _codeField.font = fieldFont;
    _codeField.frame = CGRectMake(30, rowHeight, codeWidth - 30 - 8, rowHeight);
    _numberField.font = fieldFont;
    _numberField.frame = CGRectMake(codeWidth + 14, rowHeight, cardWidth - codeWidth - 14 - 8, rowHeight);

    /* the link sits under the card when the keyboard is down and there is room for it */
    CGFloat linkY = CGRectGetMaxY(_card.frame) + 14;
    _qr.titleLabel.font = ExteriaFontSemibold(16);
    _qr.frame = CGRectMake(_card.frame.origin.x, linkY, _card.frame.size.width, 40);
    _qr.hidden = _keyboardHeight > 0 || linkY + 40 > size.height - metrics.bottom_inset - 4;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self applyLayout];
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
    [self refreshArtPlayback];
}

- (void)refreshArtPlayback {
    [_art setPlaying:_visible && !_art.hidden];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    NSString *motion = ExteriaReduceMotionChangedNotification();
    if (motion) [center addObserver:self selector:@selector(refreshArtPlayback) name:motion object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    [self refreshArtPlayback];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [self refreshArtPlayback];
    if (!self.presentedViewController) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [self.view endEditing:YES];
        _keyboardHeight = 0;
    }
}

#pragma mark state

static NSString *ExteriaPlaceholder(NSString *pattern) {
    return [pattern stringByReplacingOccurrencesOfString:@"X" withString:@"0"];
}

- (void)refreshCountry {
    _flagView.image = [_book flagForCountry:_country];
    _countryName.text = _country ? _country.name : NSLocalizedString(@"phone.badcode", nil);
    _countryName.textColor = _country ? ExteriaColorTitle() : ExteriaColorMessage();
    _countryRow.accessibilityLabel = _countryName.text;
    NSString *hint = _country.pattern.length ? ExteriaPlaceholder(_country.pattern) : NSLocalizedString(@"phone.placeholder", nil);
    _numberField.placeholder = hint;
}

- (void)refreshNumber {
    char formatted[48];
    const char *pattern = _country ? _country.pattern.UTF8String : "";
    if (exteria_phone_format(pattern, _nationalDigits.UTF8String, formatted, sizeof(formatted)) != EXTERIA_OK) {
        NSLog(@"exteria: phone number did not format");
        formatted[0] = '\0';
    }
    _numberField.text = [NSString stringWithUTF8String:formatted];
    BOOL valid = exteria_phone_valid(_codeDigits.length, _nationalDigits.length) && _country;
    _next.dimmed = !valid;
}

- (void)setBusy:(BOOL)busy {
    _qr.enabled = !busy;
    if (busy == _busy) return;
    _busy = busy;
    _next.hidden = busy;
    if (busy) [_spinner startAnimating];
    else [_spinner stopAnimating];
    _codeField.enabled = _numberField.enabled = !busy;
    _countryRow.enabled = !busy;
}

static NSString *ExteriaDigitsOf(NSString *text, NSUInteger limit) {
    char digits[EXTERIA_PHONE_MAX_DIGITS * 4 + 1];
    exteria_phone_digits(text.UTF8String, digits, sizeof(digits));
    NSString *all = [NSString stringWithUTF8String:digits];
    return all.length > limit ? [all substringToIndex:limit] : all;
}

/* takes a code and the digits typed after it; digits the code does not use move to the number, and a
   pasted whole number replaces it */
- (void)applyDigits:(NSString *)codeAndRest replaceNumber:(BOOL)replaceNumber {
    NSUInteger used = 0;
    NSString *digits = ExteriaDigitsOf(codeAndRest, EXTERIA_PHONE_MAX_DIGITS);
    ExteriaCountry *match = [_book countryForDigits:digits codeLength:&used];
    if (match) {
        NSString *rest = [digits substringFromIndex:used];
        [_codeDigits release];
        _codeDigits = [[digits substringToIndex:used] copy];
        _country = match;
        if (rest.length || replaceNumber) {
            NSString *national = replaceNumber ? rest : [rest stringByAppendingString:_nationalDigits];
            [_nationalDigits release];
            _nationalDigits = [(national.length > EXTERIA_PHONE_MAX_DIGITS - used
                                    ? [national substringToIndex:EXTERIA_PHONE_MAX_DIGITS - used] : national) copy];
        }
    } else {
        NSString *code = digits.length > EXTERIA_COUNTRY_CODE_MAX ? [digits substringToIndex:EXTERIA_COUNTRY_CODE_MAX] : digits;
        [_codeDigits release];
        _codeDigits = [code copy];
        _country = nil;
    }
    _codeField.text = _codeDigits;
    [self refreshCountry];
    [self refreshNumber];
}

#pragma mark text fields

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *text = field.text;
    if (field == _codeField) {
        NSString *proposed = [text stringByReplacingCharactersInRange:range withString:string];
        NSString *digits = ExteriaDigitsOf(proposed, EXTERIA_PHONE_MAX_DIGITS);
        NSUInteger before = _codeDigits.length;
        [self applyDigits:digits replaceNumber:digits.length > EXTERIA_COUNTRY_CODE_MAX];
        /* a digit the code did not take went to the number, so the cursor follows it */
        if (digits.length > _codeDigits.length && _codeDigits.length >= before) [_numberField becomeFirstResponder];
        return NO;
    }
    /* backspace over a separator removes the digit before it, or the field would not move */
    if (string.length == 0 && range.length == 1 && range.location < text.length &&
        ExteriaDigitsOf([text substringWithRange:range], 1).length == 0) {
        while (range.location > 0 && ExteriaDigitsOf([text substringWithRange:NSMakeRange(range.location, 1)], 1).length == 0) {
            --range.location;
        }
        range.length = 1;
    }
    NSString *proposed = [text stringByReplacingCharactersInRange:range withString:string];
    if ([string hasPrefix:@"+"] && range.location == 0) {
        [self applyDigits:string replaceNumber:YES];
        [self placeCaretAfterDigits:_nationalDigits.length];
        return NO;
    }
    NSUInteger room = EXTERIA_PHONE_MAX_DIGITS - _codeDigits.length;
    NSString *typed = ExteriaDigitsOf(proposed, room);
    NSString *beforeCaret = [proposed substringToIndex:MIN(proposed.length, range.location + string.length)];
    NSUInteger caretDigits = MIN(ExteriaDigitsOf(beforeCaret, room).length, typed.length);
    [_nationalDigits release];
    _nationalDigits = [typed copy];
    [self refreshNumber];
    [self placeCaretAfterDigits:caretDigits];
    return NO;
}

- (void)placeCaretAfterDigits:(NSUInteger)count {
    NSString *text = _numberField.text;
    NSUInteger position = 0;
    NSUInteger seen = 0;
    while (position < text.length && seen < count) {
        unichar c = [text characterAtIndex:position++];
        if (c >= '0' && c <= '9') ++seen;
    }
    UITextPosition *start = [_numberField positionFromPosition:_numberField.beginningOfDocument offset:(NSInteger)position];
    if (start) _numberField.selectedTextRange = [_numberField textRangeFromPosition:start toPosition:start];
}

#pragma mark actions

- (void)rowDown {
    _countryRow.backgroundColor = ExteriaColorField();
}

- (void)rowUp {
    _countryRow.backgroundColor = [UIColor clearColor];
}

- (void)chooseCountry {
    ExteriaCountryController *picker = [[[ExteriaCountryController alloc] initWithCountryBook:_book] autorelease];
    picker.delegate = self;
    if (ExteriaIsPad()) picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:NULL];
}

- (void)countryController:(ExteriaCountryController *)controller didPickCountry:(ExteriaCountry *)country {
    (void)controller;
    [self dismissViewControllerAnimated:YES completion:NULL];
    [self applyDigits:country.code replaceNumber:NO];
}

- (void)countryControllerDidCancel:(ExteriaCountryController *)controller {
    (void)controller;
    [self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)submit {
    if (_busy || !_country || !exteria_phone_valid(_codeDigits.length, _nationalDigits.length)) return;
    [self.view endEditing:YES];
    [_delegate phoneController:self didSubmitNumber:[NSString stringWithFormat:@"+%@%@", _codeDigits, _nationalDigits]];
}

@end
