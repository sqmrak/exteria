#import "exteria_qr_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#include "exteria_qr.h"

#import "exteria_bar_button.h"
#import "exteria_platform.h"
#import "exteria_qr_view.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"

#define STEPS 3
#define CARD_MAX 280.0
#define CARD_PADDING 14.0

@interface ExteriaQrController () {
    ExteriaWaveBackgroundView *_backdrop;
    ExteriaBarButton *_back;
    UIScrollView *_scroll;
    UIView *_card;
    ExteriaQrView *_code;
    UIActivityIndicatorView *_spinner;
    UILabel *_failure;
    UIButton *_retry;
    UILabel *_title;
    UILabel *_steps[STEPS];
    UILabel *_numbers[STEPS];
    UIButton *_phone;
    BOOL _appeared;
    BOOL _hasCode;
    id<ExteriaQrControllerDelegate> _delegate;
}
@end

@implementation ExteriaQrController

@synthesize delegate = _delegate;

- (void)dealloc {
    [_backdrop release];
    [_back release];
    [_scroll release];
    [_card release];
    [_code release];
    [_spinner release];
    [_failure release];
    [_retry release];
    [_title release];
    for (int i = 0; i < STEPS; ++i) {
        [_steps[i] release];
        [_numbers[i] release];
    }
    [_phone release];
    [super dealloc];
}

static UILabel *ExteriaQrLabel(UIColor *color, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = alignment;
    label.numberOfLines = 0;
    return label;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorBackdrop();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[ExteriaWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    /* a small screen cannot hold the code and the steps at once, so everything under the back button scrolls */
    _scroll = [[UIScrollView alloc] init];
    _scroll.alwaysBounceVertical = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    [root addSubview:_scroll];
    _card = [[UIView alloc] init];
    _card.backgroundColor = [UIColor whiteColor];
    _card.layer.cornerRadius = 22;
    _card.layer.shadowColor = [UIColor blackColor].CGColor;
    _card.layer.shadowOpacity = 0.18;
    _card.layer.shadowRadius = 14;
    _card.layer.shadowOffset = CGSizeMake(0, 6);
    [_scroll addSubview:_card];
    _code = [[ExteriaQrView alloc] init];
    _code.layer.cornerRadius = 12;
    _code.layer.masksToBounds = YES;
    _code.stillMode = ExteriaReduceMotionEnabled();
    [_card addSubview:_code];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_card addSubview:_spinner];
    _failure = ExteriaQrLabel(ExteriaColorMessage(), ExteriaTextAlignmentCenter);
    _failure.hidden = YES;
    [_card addSubview:_failure];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [_card addSubview:_retry];

    _title = ExteriaQrLabel(ExteriaColorTitle(), ExteriaTextAlignmentCenter);
    _title.text = NSLocalizedString(@"qr.title", nil);
    [_scroll addSubview:_title];
    NSString *keys[STEPS] = {@"qr.step.open", @"qr.step.settings", @"qr.step.scan"};
    for (int i = 0; i < STEPS; ++i) {
        _numbers[i] = ExteriaQrLabel([UIColor whiteColor], ExteriaTextAlignmentCenter);
        _numbers[i].backgroundColor = ExteriaColorAccent();
        _numbers[i].layer.masksToBounds = YES;
        _numbers[i].text = [NSString stringWithFormat:@"%d", i + 1];
        [_scroll addSubview:_numbers[i]];
        _steps[i] = ExteriaQrLabel(ExteriaColorMessage(), ExteriaTextAlignmentLeft);
        _steps[i].text = NSLocalizedString(keys[i], nil);
        [_scroll addSubview:_steps[i]];
    }
    _phone = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_phone setTitle:NSLocalizedString(@"qr.phone", nil) forState:UIControlStateNormal];
    [_phone setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_phone addTarget:self action:@selector(phoneTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_phone];
    _back = [[ExteriaBarButton alloc] init];
    _back.chevron = YES;
    _back.title = NSLocalizedString(@"phone.back", nil);
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_back];
    [self showLoading];
}

#pragma mark state

- (void)showLoading {
    _failure.hidden = YES;
    _retry.hidden = YES;
    if (!_hasCode) [_spinner startAnimating];
}

- (void)showFailure:(NSString *)text {
    [_spinner stopAnimating];
    _hasCode = NO;
    [_code clear];
    _failure.text = text;
    _failure.hidden = NO;
    _retry.hidden = NO;
    [self.view setNeedsLayout];
}

- (void)showUrl:(NSString *)url {
    static uint8_t modules[EXTERIA_QR_MAX_MODULES];
    int side = 0;
    const char *text = url.UTF8String;
    exteria_status status = text ? exteria_qr_encode((const uint8_t *)text, strlen(text), modules, sizeof(modules), &side, NULL) : EXTERIA_E_ARG;
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: the login code does not fit a QR code: %s", exteria_status_name(status));
        [self showFailure:NSLocalizedString(@"error.internal", nil)];
        return;
    }
    [_spinner stopAnimating];
    _failure.hidden = YES;
    _retry.hidden = YES;
    /* the first code appears after the screen does, so its wave is seen; a later one replaces the old with the same wave */
    BOOL animated = YES;
    [_code setModules:[NSData dataWithBytes:modules length:(NSUInteger)(side * side)] side:side animated:animated];
    _hasCode = YES;
}

#pragma mark actions

- (void)goBack {
    [_delegate qrControllerDidGoBack:self];
}

- (void)phoneTapped {
    [_delegate qrControllerDidChoosePhone:self];
}

- (void)retryTapped {
    [self showLoading];
    [_spinner startAnimating];
    _retry.hidden = YES;
    _failure.hidden = YES;
    [_delegate qrControllerDidRequestRetry:self];
}

#pragma mark layout

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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    BOOL wide = size.width > size.height && size.width > 520;
    _backdrop.frame = self.view.bounds;
    _back.frame = CGRectMake(insets.left, insets.top, 90, 44);
    CGFloat top = insets.top + 44;
    CGFloat usableHeight = size.height - top - insets.bottom;
    _scroll.frame = CGRectMake(0, top, size.width, size.height - top);
    CGFloat card = MIN(CARD_MAX, wide ? usableHeight - 40 : MIN(size.width - 80, usableHeight * 0.55));
    card = MAX(card, 170);
    CGFloat textWidth = wide ? MIN(size.width / 2 - 40, 340) : MIN(size.width - 56, 360);
    CGFloat titleSize = ExteriaIsPad() ? 26 : 22, stepSize = ExteriaIsPad() ? 18 : 16;
    _title.font = ExteriaFontBold(titleSize);
    CGSize titleFit = [_title sizeThatFits:CGSizeMake(textWidth, 200)];
    CGFloat stepsHeight = 0;
    CGFloat heights[STEPS];
    for (int i = 0; i < STEPS; ++i) {
        _steps[i].font = ExteriaFontRegular(stepSize);
        CGSize fit = [_steps[i] sizeThatFits:CGSizeMake(textWidth - 40, 200)];
        heights[i] = MAX(26, fit.height);
        stepsHeight += heights[i] + 12;
    }
    CGFloat textBlock = titleFit.height + 18 + stepsHeight + 16 + 40;
    /* coordinates below are inside the scroll view */
    CGFloat cardX, cardY, textX, textY, content;
    if (wide) {
        CGFloat total = card + 44 + textWidth;
        cardX = (size.width - total) / 2;
        cardY = MAX(12, (usableHeight - card) / 2);
        textX = cardX + card + 44;
        textY = MAX(12, (usableHeight - textBlock) / 2);
        content = MAX(cardY + card, textY + textBlock) + 24;
    } else {
        cardX = (size.width - card) / 2;
        cardY = MAX(8, (usableHeight - (card + 28 + textBlock)) / 2);
        textX = (size.width - textWidth) / 2;
        textY = cardY + card + 28;
        content = textY + textBlock + 24;
    }
    _scroll.contentSize = CGSizeMake(size.width, MAX(content, usableHeight));
    _card.frame = CGRectMake(cardX, cardY, card, card);
    _code.frame = CGRectInset(_card.bounds, CARD_PADDING, CARD_PADDING);
    _spinner.center = CGPointMake(card / 2, card / 2);
    _failure.font = ExteriaFontRegular(15);
    _failure.frame = CGRectMake(20, card / 2 - 50, card - 40, 60);
    _retry.frame = CGRectMake((card - 120) / 2, card / 2 + 14, 120, 40);
    _title.frame = CGRectMake(textX, textY, textWidth, titleFit.height);
    CGFloat y = textY + titleFit.height + 18;
    for (int i = 0; i < STEPS; ++i) {
        _numbers[i].font = ExteriaFontSemibold(13);
        _numbers[i].frame = CGRectMake(textX, y + (heights[i] - 24) / 2, 24, 24);
        _numbers[i].layer.cornerRadius = 12;
        _steps[i].frame = CGRectMake(textX + 36, y, textWidth - 36, heights[i]);
        y += heights[i] + 12;
    }
    _phone.titleLabel.font = ExteriaFontSemibold(17);
    _phone.frame = CGRectMake(textX, y + 6, textWidth, 40);
    _phone.contentHorizontalAlignment = wide ? UIControlContentHorizontalAlignmentLeft : UIControlContentHorizontalAlignmentCenter;
    _title.textAlignment = wide ? ExteriaTextAlignmentLeft : ExteriaTextAlignmentCenter;
}

#pragma mark entrance

/* the card rises and settles, then the title and the steps follow one after another */
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_appeared) return;
    _appeared = YES;
    if (ExteriaReduceMotionEnabled()) return;
    _card.alpha = 0;
    _card.transform = CGAffineTransformMakeScale(0.86, 0.86);
    ExteriaAnimateViewAfter(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, 0.05, nil);
    NSMutableArray *views = [NSMutableArray arrayWithObject:_title];
    for (int i = 0; i < STEPS; ++i) {
        [views addObject:_numbers[i]];
        [views addObject:_steps[i]];
    }
    [views addObject:_phone];
    NSUInteger index = 0;
    for (UIView *view in views) {
        view.alpha = 0;
        view.transform = CGAffineTransformMakeTranslation(0, 14);
        ExteriaAnimateViewAfter(view, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER,
                                0.15 + 0.035 * (NSTimeInterval)index, nil);
        ++index;
    }
}

@end
