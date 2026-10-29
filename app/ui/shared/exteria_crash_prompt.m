#import "exteria_crash_prompt.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define CARD_WIDTH_MAX 320.0
#define CARD_MARGIN 24.0
#define BUTTON_HEIGHT 48.0
/* the least height of the picture on a card, below which the card scrolls instead */
#define PICTURE_MIN 110.0

@interface ExteriaCrashPromptTarget : NSObject {
@public
    UIView *dim;
    UIView *card;
    void (^answer)(BOOL);
}
- (void)finish:(BOOL)send;
@end

static ExteriaCrashPromptTarget *ExteriaCrashPromptShown;

@implementation ExteriaCrashPromptTarget

- (void)finish:(BOOL)send {
    if (ExteriaCrashPromptShown != self) return;
    ExteriaCrashPromptShown = nil;
    void (^done)(BOOL) = [answer retain];
    UIView *shade = [dim retain], *plate = [card retain];
    /* a second tap while the card fades out (the main thread is busy with the answer, so the fade can be late) must not reach a target that is gone: the
       target lives until the fade ends, and nothing is tappable meanwhile */
    shade.userInteractionEnabled = NO;
    plate.userInteractionEnabled = NO;
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
        [self release];
    }];
    if (done) done(send);
    [done release];
}

- (void)sendTapped { [self finish:YES]; }
- (void)laterTapped { [self finish:NO]; }

- (void)dealloc {
    [dim release];
    [card release];
    [answer release];
    [super dealloc];
}

@end

static UIButton *ExteriaPromptButton(NSString *title, BOOL primary, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = primary ? ExteriaColorAccent() : ExteriaColorField();
    button.layer.cornerRadius = BUTTON_HEIGHT / 2;
    button.titleLabel.font = ExteriaFontSemibold(17);
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:primary ? [UIColor whiteColor] : ExteriaColorTitle() forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

BOOL ExteriaAskCrashReport(void (^answer)(BOOL send)) {
    UIView *window = ExteriaOverlayHost();
    if (!window || ExteriaCrashPromptShown) {
        return NO;
    }
    ExteriaCrashPromptTarget *target = [[ExteriaCrashPromptTarget alloc] init];
    target->answer = [answer copy];
    CGFloat width = MIN(window.bounds.size.width - 2 * CARD_MARGIN, CARD_WIDTH_MAX);
    CGFloat inner = width - 40;

    UIView *dim = [[UIView alloc] initWithFrame:window.bounds];
    dim.backgroundColor = [UIColor blackColor];
    dim.alpha = 0;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
    title.font = ExteriaFontBold(22);
    title.textColor = ExteriaColorTitle();
    title.textAlignment = ExteriaTextAlignmentCenter;
    title.numberOfLines = 0;
    title.text = NSLocalizedString(@"crash.title", nil);
    CGSize titleFit = [title sizeThatFits:CGSizeMake(inner, 200)];

    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.font = ExteriaFontRegular(15);
    text.textColor = ExteriaColorSecondary();
    text.textAlignment = ExteriaTextAlignmentCenter;
    text.numberOfLines = 0;
    text.text = NSLocalizedString(@"crash.text", nil);
    CGSize fit = [text sizeThatFits:CGSizeMake(inner, 400)];

    /* the picture takes what the screen has left over the words and the two buttons, up to the width of the card */
    CGFloat rest = 22 + ceil(titleFit.height) + 6 + ceil(fit.height) + 20 + 2 * BUTTON_HEIGHT + 10 + 20;
    /* the most the card may take of the screen; the picture is never dropped, and a card that does not fit scrolls, since a small phone has no room for the picture, the words and the buttons together */
    CGFloat room = window.bounds.size.height - 2 * CARD_MARGIN - ExteriaStatusBarHeight();
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
        UIImageView *picture = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"crash_meme.jpg"]] autorelease];
        picture.contentMode = UIViewContentModeScaleAspectFill;
        picture.clipsToBounds = YES;
        picture.layer.cornerRadius = 14;
        picture.frame = CGRectMake(20, 20, inner, floor(side));
        [content addSubview:picture];
        top = CGRectGetMaxY(picture.frame) + 14;
    }
    title.frame = CGRectMake(20, top, inner, ceil(titleFit.height));
    [content addSubview:title];
    text.frame = CGRectMake(20, CGRectGetMaxY(title.frame) + 6, inner, ceil(fit.height));
    [content addSubview:text];

    CGFloat y = CGRectGetMaxY(text.frame) + 20;
    UIButton *send = ExteriaPromptButton(NSLocalizedString(@"crash.send", nil), YES, target, @selector(sendTapped));
    send.frame = CGRectMake(20, y, inner, BUTTON_HEIGHT);
    [content addSubview:send];
    UIButton *later = ExteriaPromptButton(NSLocalizedString(@"crash.later", nil), NO, target, @selector(laterTapped));
    later.frame = CGRectMake(20, y + BUTTON_HEIGHT + 10, inner, BUTTON_HEIGHT);
    [content addSubview:later];
    CGFloat height = CGRectGetMaxY(later.frame) + 20;
    content.contentSize = CGSizeMake(width, height);
    content.scrollEnabled = scrolls;
    content.frame = CGRectMake(0, 0, width, MIN(height, room));
    card.bounds = CGRectMake(0, 0, width, MIN(height, room));
    card.center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    [window addSubview:dim];
    [window addSubview:card];
    ExteriaCrashPromptShown = target;
    card.alpha = 0;
    card.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [UIView animateWithDuration:0.2 animations:^{ dim.alpha = 0.5f; }];
    ExteriaAnimateView(card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
    return YES;
}
