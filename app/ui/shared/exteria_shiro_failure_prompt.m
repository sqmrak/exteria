#import "exteria_shiro_failure_prompt.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_platform.h"
#import "exteria_shiro.h"
#import "exteria_theme.h"

#define CARD_WIDTH_MAX 330.0
#define CARD_MARGIN 24.0
#define BUTTON_HEIGHT 46.0
/* the least height of the picture on a card, below which the card scrolls instead */
#define PICTURE_MIN 110.0

@interface ExteriaShiroFailureTarget : NSObject {
@public
    ExteriaShiro *shiro;
    UIView *dim;
    UIView *card;
    UIButton *copyButton;
}
@end

static ExteriaShiroFailureTarget *ExteriaShiroFailureShown;

@implementation ExteriaShiroFailureTarget

- (void)close {
    if (ExteriaShiroFailureShown != self) return;
    ExteriaShiroFailureShown = nil;
    UIView *shade = [dim retain], *plate = [card retain];
    [UIView animateWithDuration:0.18 animations:^{
        shade.alpha = 0;
        plate.alpha = 0;
        plate.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(BOOL finished) {
        (void)finished;
        [shade removeFromSuperview];
        [plate removeFromSuperview];
        [shade release];
        [plate release];
    }];
    [self release];
}

- (void)retryTapped {
    ExteriaShiro *tunnel = [[shiro retain] autorelease];
    [self close];
    [tunnel retry];
}

- (void)copyTapped {
    [UIPasteboard generalPasteboard].string = [shiro logText];
    [copyButton setTitle:NSLocalizedString(@"shiro.fail.copied", nil) forState:UIControlStateNormal];
}

- (void)offTapped {
    ExteriaShiro *tunnel = [[shiro retain] autorelease];
    [self close];
    [tunnel setEnabled:NO];
}

- (void)backdropTapped:(UITapGestureRecognizer *)tap {
    (void)tap;
    [self close];
}

/* a tap on the card itself keeps it, as the buttons on it need their own touches */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return !CGRectContainsPoint(card.frame, [touch locationInView:dim]);
}

- (void)dealloc {
    [shiro release];
    [dim release];
    [card release];
    [super dealloc];
}

@end

static UIButton *ExteriaFailureButton(NSString *title, BOOL primary, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = primary ? ExteriaColorAccent() : ExteriaColorField();
    button.layer.cornerRadius = BUTTON_HEIGHT / 2;
    button.titleLabel.font = ExteriaFontSemibold(16);
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:primary ? [UIColor whiteColor] : ExteriaColorTitle() forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

void ExteriaShowShiroFailure(ExteriaShiro *shiro) {
    UIView *host = ExteriaOverlayHost();
    if (!host || !shiro || ExteriaShiroFailureShown) return;
    ExteriaShiroFailureTarget *target = [[ExteriaShiroFailureTarget alloc] init];
    target->shiro = [shiro retain];
    CGFloat width = MIN(host.bounds.size.width - 2 * CARD_MARGIN, CARD_WIDTH_MAX);
    CGFloat inner = width - 40;

    UIView *dim = [[UIView alloc] initWithFrame:host.bounds];
    dim.backgroundColor = [UIColor blackColor];
    dim.alpha = 0;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(backdropTapped:)] autorelease];
    tap.delegate = (id<UIGestureRecognizerDelegate>)target;
    [dim addGestureRecognizer:tap];
    target->dim = dim;

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = 26;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.3f;
    card.layer.shadowRadius = 18;
    card.layer.shadowOffset = CGSizeMake(0, 6);
    target->card = card;

    UILabel *title = [[[UILabel alloc] init] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.font = ExteriaFontBold(21);
    title.textColor = ExteriaColorTitle();
    title.textAlignment = ExteriaTextAlignmentCenter;
    title.numberOfLines = 0;
    title.text = NSLocalizedString(@"shiro.fail.title", nil);
    CGSize titleFit = [title sizeThatFits:CGSizeMake(inner, 200)];

    NSString *why = shiro.failureText.length ? shiro.failureText : NSLocalizedString(@"shiro.why.server", nil);
    NSString *detail = shiro.failureDetail;
    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.font = ExteriaFontRegular(15);
    text.textColor = ExteriaColorSecondary();
    text.textAlignment = ExteriaTextAlignmentCenter;
    text.numberOfLines = 0;
    text.text = detail.length ? [NSString stringWithFormat:@"%@\n\n(%@)", why, detail] : why;
    CGSize fit = [text sizeThatFits:CGSizeMake(inner, 600)];

    /* the picture takes what the screen has left over the words and the three buttons, up to the width of the card */
    CGFloat rest = 22 + ceil(titleFit.height) + 10 + ceil(fit.height) + 20 + 3 * BUTTON_HEIGHT + 2 * 10 + 20;
    /* the most the card may take of the screen; the picture is never dropped, and a card that does not fit scrolls, since a small phone has no room for the picture, the words and the buttons together */
    CGFloat room = host.bounds.size.height - 2 * CARD_MARGIN - ExteriaStatusBarHeight();
    CGFloat side = MIN(inner, room - rest - 14);
    BOOL scrolls = side < PICTURE_MIN;
    if (scrolls) side = PICTURE_MIN;
    UIScrollView *content = [[[UIScrollView alloc] init] autorelease];
    content.showsVerticalScrollIndicator = NO;
    content.layer.cornerRadius = 26;
    content.clipsToBounds = YES;
    [card addSubview:content];
    CGFloat top = 22;
    {
        UIImageView *picture = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"shiro_meme.jpg"]] autorelease];
        picture.contentMode = UIViewContentModeScaleAspectFill;
        picture.clipsToBounds = YES;
        picture.layer.cornerRadius = 14;
        picture.frame = CGRectMake(20, 20, inner, floor(side));
        [content addSubview:picture];
        top = CGRectGetMaxY(picture.frame) + 14;
    }
    title.frame = CGRectMake(20, top, inner, ceil(titleFit.height));
    [content addSubview:title];
    text.frame = CGRectMake(20, CGRectGetMaxY(title.frame) + 10, inner, ceil(fit.height));
    [content addSubview:text];

    CGFloat y = CGRectGetMaxY(text.frame) + 20;
    UIButton *retry = ExteriaFailureButton(NSLocalizedString(@"shiro.fail.retry", nil), YES, target, @selector(retryTapped));
    retry.frame = CGRectMake(20, y, inner, BUTTON_HEIGHT);
    [content addSubview:retry];
    UIButton *copy = ExteriaFailureButton(NSLocalizedString(@"shiro.fail.copy", nil), NO, target, @selector(copyTapped));
    copy.frame = CGRectMake(20, y + BUTTON_HEIGHT + 10, inner, BUTTON_HEIGHT);
    [content addSubview:copy];
    target->copyButton = copy;
    UIButton *off = ExteriaFailureButton(NSLocalizedString(@"shiro.fail.off", nil), NO, target, @selector(offTapped));
    off.frame = CGRectMake(20, y + 2 * (BUTTON_HEIGHT + 10), inner, BUTTON_HEIGHT);
    [content addSubview:off];
    CGFloat height = CGRectGetMaxY(off.frame) + 20;
    content.contentSize = CGSizeMake(width, height);
    content.scrollEnabled = scrolls;
    content.frame = CGRectMake(0, 0, width, MIN(height, room));
    card.bounds = CGRectMake(0, 0, width, MIN(height, room));
    card.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    [host addSubview:dim];
    [host addSubview:card];
    ExteriaShiroFailureShown = target;
    card.alpha = 0;
    card.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [UIView animateWithDuration:0.2 animations:^{ dim.alpha = 0.5f; }];
    ExteriaAnimateView(card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}
