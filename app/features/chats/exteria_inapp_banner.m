#import "exteria_inapp_banner.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_emoji_label.h"
#import "exteria_developers.h"
#import "exteria_image_decoder.h"
#import "exteria_name_badge.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define CARD_MAX_WIDTH 420.0
#define CARD_SIDE 8.0
#define CARD_HEIGHT 62.0
#define AVATAR_SIDE 42.0
#define PADDING 12.0
#define SHOW_SECONDS 4.0
#define SLIDE_SECONDS 0.25

static ExteriaInAppBanner *ExteriaShownBanner;

@interface ExteriaInAppBanner () {
    void (^_tap)(void);
    ExteriaAvatarView *_avatar;
    UIImageView *_picture;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_body;
    BOOL _leaving;
}
@end

@implementation ExteriaInAppBanner

+ (void)showTitle:(NSString *)title body:(NSString *)body dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars tap:(void (^)(void))tap {
    [self showTitle:title body:body dialog:dialog avatars:avatars tap:tap picture:nil];
}

+ (void)showPowerTitle:(NSString *)title body:(NSString *)body {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *path = [[NSBundle mainBundle] pathForResource:@"power_meme" ofType:@"png"];
        UIImage *picture = [path ? ExteriaDecodeImageAtURL([NSURL fileURLWithPath:path], 300) : nil retain];
        if (!picture) NSLog(@"exteria: power notice image is missing or invalid");
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive)
                [self showTitle:title body:body dialog:nil avatars:nil tap:nil picture:picture];
            [picture release];
        });
        [pool drain];
    });
}

+ (void)showTitle:(NSString *)title body:(NSString *)body dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars tap:(void (^)(void))tap picture:(UIImage *)picture {
    UIView *window = ExteriaOverlayHost();
    if (!window) return;
    [ExteriaShownBanner leaveNow];
    ExteriaInAppBanner *banner = [[[ExteriaInAppBanner alloc] initWithFrame:CGRectZero] autorelease];
    banner->_tap = [tap copy];
    /* a person's name wears the marks of the app and the Premium star as it does in the chat list; the card has no media cache, so a status picture that is not
       on the device is left out instead of drawn as a box */
    NSArray *titleEntities = nil;
    banner->_title.dropsUndrawable = YES;
    banner->_title.text = ExteriaNameWithBadges(title.length ? title : @"Telegram", dialog ? ExteriaDialogBadgeDocument(dialog) : 0, ExteriaDialogIsDeveloper(dialog), &titleEntities);
    banner->_title.entities = titleEntities;
    banner->_body.text = body;
    if (dialog) {
        ExteriaAvatarView *avatar = banner->_avatar;
        avatar.seed = dialog.avatarSeed;
        avatar.initials = dialog.initials;
        avatar.deleted = dialog.deleted;
        avatar.accent = dialog.saved || dialog.replies;
        avatar.symbol = dialog.replies ? ExteriaSymbolReply : ExteriaSymbolBookmark;
        avatar.showsSymbol = dialog.saved || dialog.replies;
        [avatar setPhoto:dialog.saved || dialog.replies ? nil : dialog.photo cache:avatars];
        avatar.hidden = NO;
    }
    if (picture) {
        banner->_picture = [[UIImageView alloc] initWithImage:picture];
        banner->_picture.contentMode = UIViewContentModeScaleAspectFit;
        [banner addSubview:banner->_picture];
    }
    UIEdgeInsets insets = ExteriaSafeInsets(window);
    CGFloat width = MIN(CARD_MAX_WIDTH, window.bounds.size.width - 2 * CARD_SIDE - insets.left - insets.right);
    CGFloat top = MAX(insets.top, [UIApplication sharedApplication].statusBarHidden ? 0 : 20) + 4;
    CGFloat height = picture ? 132 : CARD_HEIGHT;
    banner.frame = CGRectMake(floor((window.bounds.size.width - width) / 2), top, width, height);
    [window addSubview:banner];
    ExteriaShownBanner = [banner retain];
    banner.transform = CGAffineTransformMakeTranslation(0, -(top + height + 20));
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ banner.transform = CGAffineTransformIdentity; } completion:nil];
    [banner performSelector:@selector(leave) withObject:nil afterDelay:SHOW_SECONDS];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 16;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.25f;
    self.layer.shadowRadius = 8;
    self.layer.shadowOffset = CGSizeMake(0, 3);
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES;
    _avatar.hidden = YES;
    [self addSubview:_avatar];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = ExteriaFontSemibold(15);
    _title.textColor = ExteriaColorTitle();
    [self addSubview:_title];
    /* the body names who wrote, and a UILabel shows a box for every letter of a styled name that the system font lacks */
    _body = [[ExteriaEmojiLabel alloc] init];
    _body.font = ExteriaFontRegular(14);
    _body.textColor = ExteriaColorSecondary();
    _body.numberOfLines = 2;
    [self addSubview:_body];
    [self addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)] autorelease]];
    /* the card follows the finger to the left, to the right or up, and goes when it is let go far enough or flicked; a tap still opens the chat */
    [self addGestureRecognizer:[[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)] autorelease]];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_tap release];
    [_avatar release];
    [_picture release];
    [_title release];
    [_body release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    /* the text starts after the picture, and at the old edge when the card has none */
    CGFloat left = _picture ? 122 : (_avatar.hidden ? 14 : PADDING + AVATAR_SIDE + 10);
    CGFloat width = MAX(0, self.bounds.size.width - left - 14);
    if (_picture) _picture.frame = CGRectMake(8, 6, 104, self.bounds.size.height - 12);
    _avatar.frame = CGRectMake(PADDING, (CARD_HEIGHT - AVATAR_SIDE) / 2, AVATAR_SIDE, AVATAR_SIDE);
    CGFloat textTop = _picture ? floor((self.bounds.size.height - 60) / 2) : 8;
    _title.frame = CGRectMake(left, textTop, width, 20);
    _body.frame = CGRectMake(left, textTop + 20, width, _picture ? 40 : 28);
}

- (void)removeNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self removeFromSuperview];
    if (ExteriaShownBanner == self) {
        ExteriaShownBanner = nil;
        [self autorelease];
    }
}

/* a banner that is replaced does not animate out, the new one is already coming in */
- (void)leaveNow {
    _leaving = YES;
    [self removeNow];
}

- (void)leave {
    if (_leaving) return;
    _leaving = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ self.transform = CGAffineTransformMakeTranslation(0, -(self.frame.origin.y + self.bounds.size.height + 20)); }
                     completion:^(BOOL finished) {
        (void)finished;
        [self removeNow];
    }];
}

/* how far a drag must go, as a part of the card width, or how fast a flick must be (points per second), to send the card away */
#define DISMISS_FRACTION 0.35
#define DISMISS_SPEED 500.0
#define DISMISS_UP_DISTANCE 24.0
/* the card stays this long after a drag that did not send it away */
#define RETURN_SECONDS 3.0

- (void)dragged:(UIPanGestureRecognizer *)pan {
    if (_leaving) return;
    UIView *host = self.superview;
    if (!host) return;
    CGPoint move = [pan translationInView:host];
    /* downward there is nowhere to go: the card rests against its place */
    CGFloat y = MIN(0, move.y);
    CGFloat width = MAX(1, self.bounds.size.width);
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
        /* the timer must not take the card from under the finger */
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(leave) object:nil];
        break;
    case UIGestureRecognizerStateChanged:
        self.transform = CGAffineTransformMakeTranslation(move.x, y);
        self.alpha = (CGFloat)MAX(0.3, 1.0 - fabs(move.x) / (width * 1.5));
        break;
    case UIGestureRecognizerStateEnded: {
        CGPoint speed = [pan velocityInView:host];
        BOOL sideways = fabs(move.x) > width * DISMISS_FRACTION || fabs(speed.x) > DISMISS_SPEED;
        BOOL up = -y > DISMISS_UP_DISTANCE || speed.y < -DISMISS_SPEED;
        if (sideways && fabs(move.x) >= fabs(y)) {
            [self flyAwayToward:(move.x != 0 ? move.x : speed.x) < 0 ? -1 : 1];
        } else if (up) {
            [self leave];
        } else {
            [self settle];
        }
        break;
    }
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        [self settle];
        break;
    default:
        break;
    }
}

/* the card leaves across the screen edge on the side it was thrown to */
- (void)flyAwayToward:(int)direction {
    if (_leaving) return;
    _leaving = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    CGFloat distance = direction * (self.superview.bounds.size.width + self.bounds.size.width);
    CGFloat lift = self.transform.ty;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.transform = CGAffineTransformMakeTranslation(distance, lift);
        self.alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeNow];
    }];
}

/* a drag that stopped short puts the card back and gives it a few more seconds */
- (void)settle {
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
    } completion:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(leave) object:nil];
    [self performSelector:@selector(leave) withObject:nil afterDelay:RETURN_SECONDS];
}

- (void)tapped {
    if (_leaving) return;
    void (^tap)(void) = [[_tap retain] autorelease];
    [self leave];
    if (tap) tap();
}

@end
