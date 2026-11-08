#import "exteria_alert_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_theme.h"

#define CARD_WIDTH 300.0
#define CARD_RADIUS 18.0
#define SIDE_MARGIN 24.0
#define PAD 22.0
#define BUTTON_HEIGHT 50.0
#define FIELD_HEIGHT 42.0
#define ENTER_SECONDS 0.24
#define LEAVE_SECONDS 0.16

@interface ExteriaAlertView () {
    id _delegate;
    NSString *_title;
    NSString *_message;
    NSInteger _cancelButtonIndex;
    NSInteger _alertViewStyle;
    NSMutableArray *_titles;
    UITextField *_field;
    UIView *_dim;
    UIView *_card;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    NSMutableArray *_buttons;
    NSMutableArray *_lines;
    CGFloat _keyboardOverlap;
    BOOL _shown;
    BOOL _closing;
}
@end

@implementation ExteriaAlertView

@synthesize delegate = _delegate;
@synthesize title = _title;
@synthesize message = _message;
@synthesize cancelButtonIndex = _cancelButtonIndex;
@synthesize alertViewStyle = _alertViewStyle;

- (id)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate cancelButtonTitle:(NSString *)cancelTitle otherButtonTitles:(NSString *)first, ... {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _delegate = delegate;
    _title = [title copy];
    _message = [message copy];
    _cancelButtonIndex = -1;
    _titles = [[NSMutableArray alloc] init];
    _buttons = [[NSMutableArray alloc] init];
    _lines = [[NSMutableArray alloc] init];
    if (cancelTitle) _cancelButtonIndex = [self addButtonWithTitle:cancelTitle];
    va_list rest;
    va_start(rest, first);
    for (NSString *other = first; other; other = va_arg(rest, NSString *)) [self addButtonWithTitle:other];
    va_end(rest);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _field.delegate = nil;
    [_title release];
    [_message release];
    [_titles release];
    [_field release];
    [_dim release];
    [_card release];
    [_titleLabel release];
    [_messageLabel release];
    [_buttons release];
    [_lines release];
    [super dealloc];
}

- (NSInteger)numberOfButtons {
    return (NSInteger)_titles.count;
}

- (NSInteger)addButtonWithTitle:(NSString *)title {
    [_titles addObject:title ? title : @""];
    return (NSInteger)_titles.count - 1;
}

- (NSString *)buttonTitleAtIndex:(NSInteger)index {
    return index >= 0 && (NSUInteger)index < _titles.count ? [_titles objectAtIndex:(NSUInteger)index] : nil;
}

/* the field exists as soon as the style asks for one, since the caller fills it in before the alert shows */
- (void)setAlertViewStyle:(NSInteger)style {
    _alertViewStyle = style;
    if (style != 1 && style != 2) return;
    if (!_field) {
        _field = [[UITextField alloc] init];
        _field.delegate = self;
        _field.font = ExteriaFontRegular(16);
        _field.textColor = ExteriaColorTitle();
        _field.backgroundColor = ExteriaColorField();
        _field.layer.cornerRadius = 10;
        _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _field.leftView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, FIELD_HEIGHT)] autorelease];
        _field.leftViewMode = UITextFieldViewModeAlways;
        _field.returnKeyType = UIReturnKeyDone;
        _field.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    }
    _field.secureTextEntry = style == 1;
}

- (UITextField *)textFieldAtIndex:(NSInteger)index {
    return index == 0 ? _field : nil;
}

#pragma mark building

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color text:(NSString *)text {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.text = text;
    label.numberOfLines = 0;
    label.textAlignment = ExteriaTextAlignmentCenter;
    [_card addSubview:label];
    return label;
}

- (UIView *)hairline {
    UIView *line = [[[UIView alloc] init] autorelease];
    line.backgroundColor = ExteriaColorHairline();
    [_card addSubview:line];
    [_lines addObject:line];
    return line;
}

- (void)build {
    _dim = [[UIView alloc] initWithFrame:self.bounds];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = CARD_RADIUS;
    _card.layer.masksToBounds = YES;
    [self addSubview:_card];
    BOOL hasTitle = _title.length > 0;
    if (hasTitle) _titleLabel = [[self labelWithFont:ExteriaFontSemibold(17) color:ExteriaColorTitle() text:_title] retain];
    if (_message.length) {
        _messageLabel = [[self labelWithFont:hasTitle ? ExteriaFontRegular(14.5) : ExteriaFontMedium(16) color:hasTitle ? ExteriaColorSecondary() : ExteriaColorTitle() text:_message] retain];
    }
    if (_field) [_card addSubview:_field];
    for (NSUInteger i = 0; i < _titles.count; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        BOOL cancel = (NSInteger)i == _cancelButtonIndex;
        [button setTitle:[_titles objectAtIndex:i] forState:UIControlStateNormal];
        [button setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        button.titleLabel.font = cancel ? ExteriaFontRegular(17) : ExteriaFontSemibold(17);
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumFontSize = 12;
        button.tag = (NSInteger)i;
        [button addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [button addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:button];
        [_buttons addObject:button];
        [self hairline];
    }
    /* the vertical rule between two buttons side by side is one more line */
    if (_titles.count == 2) [self hairline];
}

- (void)rowDown:(UIButton *)row { row.backgroundColor = ExteriaColorField(); }
- (void)rowUp:(UIButton *)row { row.backgroundColor = [UIColor clearColor]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_card) return;
    CGSize size = self.bounds.size;
    CGFloat width = MIN(size.width - 2 * SIDE_MARGIN, CARD_WIDTH), inner = width - 2 * PAD, y = PAD - 4;
    if (_titleLabel) {
        CGSize fit = [_titleLabel sizeThatFits:CGSizeMake(inner, 400)];
        _titleLabel.frame = CGRectMake(PAD, y, inner, ceil(fit.height));
        y += ceil(fit.height) + (_messageLabel || _field ? 6 : 0);
    }
    if (_messageLabel) {
        CGSize fit = [_messageLabel sizeThatFits:CGSizeMake(inner, 600)];
        _messageLabel.frame = CGRectMake(PAD, y, inner, ceil(fit.height));
        y += ceil(fit.height);
    }
    if (_field) {
        y += (_titleLabel || _messageLabel) ? 14 : 4;
        _field.frame = CGRectMake(PAD - 4, y, inner + 8, FIELD_HEIGHT);
        y += FIELD_HEIGHT;
    }
    y += PAD - 4;
    CGFloat rule = 1.0 / ExteriaScreenScale();
    BOOL sideBySide = _buttons.count == 2;
    for (NSUInteger i = 0; i < _buttons.count; ++i) {
        UIButton *button = [_buttons objectAtIndex:i];
        if (sideBySide) {
            CGFloat half = width / 2;
            button.frame = CGRectMake(half * (CGFloat)i, y, half, BUTTON_HEIGHT);
            ((UIView *)[_lines objectAtIndex:i]).frame = CGRectMake(half * (CGFloat)i, y, half, rule);
        } else {
            button.frame = CGRectMake(0, y + BUTTON_HEIGHT * (CGFloat)i, width, BUTTON_HEIGHT);
            ((UIView *)[_lines objectAtIndex:i]).frame = CGRectMake(0, y + BUTTON_HEIGHT * (CGFloat)i, width, rule);
        }
    }
    if (sideBySide) ((UIView *)[_lines lastObject]).frame = CGRectMake(width / 2, y, rule, BUTTON_HEIGHT);
    y += (sideBySide ? 1 : (CGFloat)_buttons.count) * BUTTON_HEIGHT;
    CGFloat room = size.height - _keyboardOverlap;
    CGFloat top = MAX(SIDE_MARGIN, floor((room - y) / 2));
    /* a transform is set while the card comes and goes, and a frame set under it resizes the card */
    CGAffineTransform held = _card.transform;
    _card.transform = CGAffineTransformIdentity;
    _card.frame = CGRectMake(floor((size.width - width) / 2), top, width, y);
    _card.transform = held;
}

#pragma mark answering

- (void)picked:(UIButton *)button {
    [self finishWithIndex:button.tag];
}

- (void)finishWithIndex:(NSInteger)index {
    if (_closing) return;
    [self retain];
    if ([_delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [_delegate alertView:(id)self clickedButtonAtIndex:index];
    [self closeWithIndex:index animated:YES];
    [self release];
}

- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated {
    [self closeWithIndex:index animated:animated];
}

/* the application leaving the screen takes the question back, as the system alert is taken */
- (void)appResigned:(NSNotification *)note {
    (void)note;
    if (_closing) return;
    [self retain];
    if ([_delegate respondsToSelector:@selector(alertViewCancel:)]) [_delegate alertViewCancel:(id)self];
    [self closeWithIndex:_cancelButtonIndex animated:NO];
    [self release];
}

- (void)closeWithIndex:(NSInteger)index animated:(BOOL)animated {
    if (_closing) return;
    _closing = YES;
    [self retain];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_field resignFirstResponder];
    self.userInteractionEnabled = NO;
    void (^gone)(void) = ^{
        [self removeFromSuperview];
        if ([_delegate respondsToSelector:@selector(alertView:didDismissWithButtonIndex:)]) [_delegate alertView:(id)self didDismissWithButtonIndex:index];
        [self release];
    };
    if (!animated || ExteriaReduceMotionEnabled() || ![UIView areAnimationsEnabled] || !self.window) {
        gone();
        return;
    }
    [UIView animateWithDuration:LEAVE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        _dim.alpha = 0;
        _card.alpha = 0;
        _card.transform = CGAffineTransformMakeScale(0.94f, 0.94f);
    } completion:^(BOOL finished) {
        (void)finished;
        gone();
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    /* done on the keyboard answers as the last button, which is the one that goes on, when there are two; otherwise it only puts the keyboard away */
    if (_titles.count == 2 && _cancelButtonIndex == 0) {
        [self finishWithIndex:1];
        return NO;
    }
    [field resignFirstResponder];
    return NO;
}

#pragma mark showing

- (void)keyboardChanged:(NSNotification *)note {
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    BOOL hiding = [note.name isEqualToString:UIKeyboardWillHideNotification];
    CGRect inView = [self convertRect:[self.window convertRect:end fromWindow:nil] fromView:nil];
    _keyboardOverlap = hiding ? 0 : MAX(0, CGRectGetMaxY(self.bounds) - inView.origin.y);
    NSTimeInterval duration = [[note.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration > 0 ? duration : 0.25 animations:^{ [self setNeedsLayout]; [self layoutIfNeeded]; }];
}

- (void)show {
    if (_shown) return;
    UIView *host = ExteriaOverlayHost();
    if (!host) return;
    _shown = YES;
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self build];
    [host addSubview:self];
    [self layoutIfNeeded];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(appResigned:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    if (_field) {
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    }
    BOOL moves = !ExteriaReduceMotionEnabled() && [UIView areAnimationsEnabled];
    if (moves) {
        _card.alpha = 0;
        _card.transform = CGAffineTransformMakeScale(0.9f, 0.9f);
        [UIView animateWithDuration:ENTER_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            _dim.alpha = 0.42f;
            _card.alpha = 1;
            _card.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        _dim.alpha = 0.42f;
    }
    if (_field) [_field becomeFirstResponder];
}

@end

Class ExteriaAlertClass(void) {
    return ExteriaThemeIsClassic() ? NSClassFromString(@"UIAlertView") : [ExteriaAlertView class];
}
