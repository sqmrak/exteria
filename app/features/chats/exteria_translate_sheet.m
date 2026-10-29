#import "exteria_translate_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_language.h"
#import "exteria_platform.h"
#import "exteria_sheet.h"
#import "exteria_text_layout.h"
#import "exteria_theme.h"
#import "exteria_translate_config.h"
#import "exteria_translator.h"
#import "exteria_weak_reference.h"

#define SIDE 10.0
#define PAD 18.0
#define CARD_RADIUS 16.0
#define BUTTON_HEIGHT 46.0

/* a laid out text drawn as it is, in the box the layout measured */
@interface ExteriaTranslateTextView : UIView {
    ExteriaTextLayout *_layout;
}
- (void)setLayout:(ExteriaTextLayout *)layout;
@end

@implementation ExteriaTranslateTextView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)dealloc {
    [_layout release];
    [super dealloc];
}

- (void)setLayout:(ExteriaTextLayout *)layout {
    if (layout == _layout) return;
    [_layout release];
    _layout = [layout retain];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    [_layout drawAtPoint:CGPointZero];
}

@end

@interface ExteriaTranslateSheet () {
    UIView *_dim;
    UIView *_card;
    UILabel *_title;
    UIButton *_language;
    UIScrollView *_body;
    UIActivityIndicatorView *_spinner;
    UILabel *_status;
    ExteriaTranslateTextView *_translatedView;
    UILabel *_originalCaption;
    ExteriaTranslateTextView *_originalView;
    UIButton *_toggle;
    UIButton *_copy;
    UIButton *_close;
    NSString *_text;
    NSArray *_entities;
    NSString *_context;
    NSString *_target;
    ExteriaSession *_session;
    ExteriaTranslation *_result;
    NSString *_failure;
    ExteriaTranslateJob *_job;
    ExteriaWeakReference *_weak;
    BOOL _showOriginal;
    BOOL _closing;
    UIEdgeInsets _insets;
}
@end

@implementation ExteriaTranslateSheet

+ (void)presentInView:(UIView *)host text:(NSString *)text entities:(NSArray *)entities session:(ExteriaSession *)session context:(NSString *)context {
    ExteriaTranslateSheet *sheet = [[[ExteriaTranslateSheet alloc] initWithFrame:host.bounds] autorelease];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sheet->_text = [text copy];
    sheet->_entities = [entities copy];
    sheet->_session = [session retain];
    sheet->_context = [context copy];
    sheet->_target = [ExteriaTranslateTargetLanguage() copy];
    sheet->_weak = [[ExteriaWeakReference referenceTo:sheet] retain];
    sheet->_showOriginal = ExteriaTranslateOriginalMode() == 2;
    /* the margins of the screen the card stands on, taken from the controller that owns the host */
    for (UIResponder *responder = host; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            sheet->_insets = ExteriaLayoutInsets((UIViewController *)responder);
            break;
        }
    }
    [sheet build];
    [host addSubview:sheet];
    [sheet enter];
    [sheet start];
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_job cancel];
    [_job release];
    [_dim release];
    [_card release];
    [_title release];
    [_language release];
    [_body release];
    [_spinner release];
    [_status release];
    [_translatedView release];
    [_originalCaption release];
    [_originalView release];
    [_toggle release];
    [_copy release];
    [_close release];
    [_text release];
    [_entities release];
    [_context release];
    [_target release];
    [_session release];
    [_result release];
    [_failure release];
    [super dealloc];
}

#pragma mark build

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    return label;
}

- (UIButton *)pillWithTitle:(NSString *)title fill:(UIColor *)fill color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = fill;
    button.layer.cornerRadius = 12;
    button.titleLabel.font = ExteriaFontSemibold(16);
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)build {
    _dim = [[UIView alloc] initWithFrame:self.bounds];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = CARD_RADIUS;
    _card.layer.masksToBounds = YES;
    _title = [[self labelWithFont:ExteriaFontSemibold(18) color:ExteriaColorTitle()] retain];
    _title.text = NSLocalizedString(@"tr.sheet.title", nil);
    [_card addSubview:_title];
    _language = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _language.titleLabel.font = ExteriaFontMedium(15);
    [_language setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_language addTarget:self action:@selector(chooseLanguage) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_language];
    _body = [[UIScrollView alloc] init];
    _body.showsVerticalScrollIndicator = NO;
    [_card addSubview:_body];
    _translatedView = [[ExteriaTranslateTextView alloc] init];
    [_body addSubview:_translatedView];
    _originalCaption = [[self labelWithFont:ExteriaFontMedium(13) color:ExteriaColorSecondary()] retain];
    _originalCaption.text = NSLocalizedString(@"tr.sheet.original", nil);
    [_body addSubview:_originalCaption];
    _originalView = [[ExteriaTranslateTextView alloc] init];
    [_body addSubview:_originalView];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    [_card addSubview:_spinner];
    _status = [[self labelWithFont:ExteriaFontRegular(15) color:ExteriaColorSecondary()] retain];
    _status.numberOfLines = 0;
    [_card addSubview:_status];
    _toggle = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _toggle.titleLabel.font = ExteriaFontMedium(14);
    [_toggle setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_toggle addTarget:self action:@selector(toggleOriginal) forControlEvents:UIControlEventTouchUpInside];
    [_body addSubview:_toggle];
    _copy = [[self pillWithTitle:NSLocalizedString(@"tr.copy", nil) fill:ExteriaColorAccent() color:[UIColor whiteColor] action:@selector(copyTranslation)] retain];
    _close = [[self pillWithTitle:NSLocalizedString(@"tr.sheet.close", nil) fill:ExteriaColorField() color:ExteriaColorTitle() action:@selector(dismiss)] retain];
    [_card addSubview:_copy];
    [_card addSubview:_close];
    [self addSubview:_card];
    ExteriaAddDismissPan(_card, self, @selector(dismiss));
    [self refreshLanguage];
}

- (void)refreshLanguage {
    NSString *name = [NSString stringWithFormat:NSLocalizedString(@"tr.sheet.to", nil), ExteriaLanguageName(_target)];
    [_language setTitle:[name stringByAppendingString:@" ›"] forState:UIControlStateNormal];
}

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    UIEdgeInsets insets = _insets;
    CGFloat width = MIN(size.width - 2 * SIDE, 460);
    CGFloat inner = width - 2 * PAD;
    CGFloat headerHeight = 54;
    CGFloat footer = BUTTON_HEIGHT + 2 * 12;
    UIFont *font = ExteriaFontRegular(16);
    CGFloat contentHeight = 0;
    _translatedView.hidden = !_result;
    _originalCaption.hidden = YES;
    _originalView.hidden = YES;
    _toggle.hidden = YES;
    if (_result) {
        ExteriaTextLayout *layout = [ExteriaTextLayout layoutForText:_result.text entities:_result.entities font:font color:ExteriaColorTitle() linkColor:ExteriaColorAccent()
                                                              width:inner maxLines:0 flush:0];
        [_translatedView setLayout:layout];
        _translatedView.frame = CGRectMake(0, 0, inner, ceil(layout.size.height));
        contentHeight = _translatedView.frame.size.height;
        int mode = ExteriaTranslateOriginalMode();
        BOOL manual = mode == 1;
        if (mode == 1 || mode == 2) {
            CGFloat y = contentHeight + 14;
            if (manual) {
                _toggle.hidden = NO;
                [_toggle setTitle:NSLocalizedString(_showOriginal ? @"tr.sheet.hideoriginal" : @"tr.showoriginal", nil) forState:UIControlStateNormal];
                _toggle.frame = CGRectMake(0, y - 6, inner, 30);
                _toggle.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
                y += 30;
            }
            if (_showOriginal) {
                _originalCaption.hidden = NO;
                _originalCaption.frame = CGRectMake(0, y, inner, 18);
                ExteriaTextLayout *original = [ExteriaTextLayout layoutForText:_text entities:_entities font:ExteriaFontRegular(15) color:ExteriaColorSecondary()
                                                                  linkColor:ExteriaColorAccent() width:inner maxLines:0 flush:0];
                [_originalView setLayout:original];
                _originalView.hidden = NO;
                _originalView.frame = CGRectMake(0, y + 22, inner, ceil(original.size.height));
                contentHeight = CGRectGetMaxY(_originalView.frame);
            } else {
                contentHeight = y;
            }
        }
    } else {
        _status.frame = CGRectMake(PAD, headerHeight + 6, inner, 0);
        CGSize fit = [_status sizeThatFits:CGSizeMake(_failure ? inner : inner - 34, 400)];
        contentHeight = MAX(30, ceil(fit.height));
    }
    CGFloat limit = MAX(120, size.height - insets.top - insets.bottom - headerHeight - footer - 90);
    CGFloat bodyHeight = MIN(contentHeight, limit);
    CGFloat cardHeight = headerHeight + bodyHeight + 14 + footer + insets.bottom;
    _card.frame = CGRectMake((size.width - width) / 2, size.height - cardHeight - SIDE / 2, width, cardHeight);
    _title.frame = CGRectMake(PAD, 16, inner / 2, 26);
    _language.frame = CGRectMake(PAD + inner / 2, 12, inner / 2, 34);
    _language.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    _body.hidden = !_result;
    _body.frame = CGRectMake(PAD, headerHeight, inner, bodyHeight);
    _body.contentSize = CGSizeMake(inner, contentHeight);
    _body.scrollEnabled = contentHeight > bodyHeight;
    if (!_result) {
        BOOL waiting = !_failure;
        _spinner.hidden = !waiting;
        if (waiting) [_spinner startAnimating];
        else [_spinner stopAnimating];
        _spinner.frame = CGRectMake(PAD, headerHeight + 6, 24, 24);
        _status.frame = CGRectMake(PAD + (waiting ? 34 : 0), headerHeight + 6, inner - (waiting ? 34 : 0), contentHeight);
    } else {
        _spinner.hidden = YES;
        _status.hidden = YES;
    }
    _status.hidden = _result != nil;
    CGFloat buttonsY = headerHeight + bodyHeight + 14 + 12;
    CGFloat half = (inner - 10) / 2;
    _copy.frame = CGRectMake(PAD, buttonsY, half, BUTTON_HEIGHT);
    _close.frame = CGRectMake(PAD + half + 10, buttonsY, half, BUTTON_HEIGHT);
    _copy.enabled = _result != nil;
    _copy.alpha = _result ? 1 : 0.4;
}

#pragma mark flow

- (void)start {
    [_job cancel];
    [_job release];
    [_result release];
    _result = nil;
    [_failure release];
    _failure = nil;
    _status.text = NSLocalizedString(@"tr.translating", nil);
    [self setNeedsLayout];
    ExteriaWeakReference *weak = _weak;
    _job = [[ExteriaTranslateJob translateText:_text entities:_entities to:_target context:_context session:_session
                                     completion:^(ExteriaTranslation *translation, NSString *failure) {
        ExteriaTranslateSheet *me = weak.target;
        if (!me) return;
        if (translation) {
            me->_result = [translation retain];
        } else {
            me->_failure = [failure copy];
            me->_status.text = failure;
        }
        [me setNeedsLayout];
    }] retain];
}

- (void)chooseLanguage {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *codes = [NSMutableArray array];
    for (NSString *code in ExteriaTranslatePreferredLanguages()) {
        if (![codes containsObject:code]) [codes addObject:code];
    }
    NSString *own = ExteriaInterfaceLanguage();
    if (![codes containsObject:own]) [codes addObject:own];
    for (NSString *code in ExteriaTranslationLanguageCodes()) {
        if (![codes containsObject:code] && ![codes containsObject:ExteriaNormalizedLanguageCode(code)]) [codes addObject:code];
    }
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *code in codes) [names addObject:ExteriaLanguageName(code)];
    [ExteriaSheet presentInView:self title:NSLocalizedString(@"tr.target.title", nil) message:nil options:names destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil)
                        handler:^(NSUInteger index) {
        ExteriaTranslateSheet *me = weak.target;
        if (!me || index >= codes.count) return;
        [me->_target release];
        me->_target = [[codes objectAtIndex:index] copy];
        [me refreshLanguage];
        [me start];
    }];
}

- (void)toggleOriginal {
    _showOriginal = !_showOriginal;
    [self setNeedsLayout];
}

- (void)copyTranslation {
    if (!_result.text.length) return;
    [UIPasteboard generalPasteboard].string = _result.text;
    [self dismiss];
}

#pragma mark motion

- (void)enter {
    [self layoutIfNeeded];
    CGFloat shift = self.bounds.size.height - _card.frame.origin.y;
    _card.transform = CGAffineTransformMakeTranslation(0, shift);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0.42, EXTERIA_MOTION_ENTER, nil);
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, nil);
}

- (void)dismiss {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    [_job cancel];
    [self retain];
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, EXTERIA_MOTION_EXIT, nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeTranslation(0, self.bounds.size.height - (_card.center.y - _card.bounds.size.height / 2)), 1, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        [self release];
    });
}

@end
