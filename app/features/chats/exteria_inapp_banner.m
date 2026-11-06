#import "exteria_inapp_banner.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_chat_settings.h"
#import "exteria_classic_chrome.h"
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
/* the classic bar covers the status bar and is as tall as a title and two lines of text; the icon is the size of a home screen icon in the old bars */
#define CLASSIC_BAND 58.0
#define CLASSIC_ICON 38.0
/* the backdrop reaches this far above the bar, so the landing bounce never shows a gap over it */
#define CLASSIC_BLEED 16.0
#define CLASSIC_SWEEP_WIDTH 96.0

static ExteriaInAppBanner *ExteriaShownBanner;

@interface ExteriaInAppBanner () {
    void (^_tap)(void);
    ExteriaAvatarView *_avatar;
    UIImageView *_picture;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_body;
    UIImageView *_backdrop;
    CAGradientLayer *_glass;
    CALayer *_lip;
    CALayer *_press;
    UIView *_shine;
    CAGradientLayer *_sweep;
    CGFloat _contentTop;
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
    BOOL classic = ExteriaThemeIsClassic();
    CGFloat height = picture ? 132 : CARD_HEIGHT;
    if (classic) {
        /* the ios 5 banner is a full width bar that covers the status bar, not a floating card */
        banner->_contentTop = MAX(insets.top, [UIApplication sharedApplication].statusBarHidden ? 0 : 20);
        height = banner->_contentTop + (picture ? 132 : CLASSIC_BAND);
        banner.frame = CGRectMake(0, 0, window.bounds.size.width, height);
    } else {
        banner.frame = CGRectMake(floor((window.bounds.size.width - width) / 2), top, width, height);
    }
    [window addSubview:banner];
    ExteriaShownBanner = [banner retain];
    if (classic && !ExteriaReduceMotionEnabled()) {
        [banner dropWithBounce];
    } else if (!classic) {
        banner.transform = CGAffineTransformMakeTranslation(0, -(top + height + 20));
        [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ banner.transform = CGAffineTransformIdentity; } completion:nil];
    }
    [banner performSelector:@selector(leave) withObject:nil afterDelay:SHOW_SECONDS];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BOOL classic = ExteriaThemeIsClassic();
    if (classic) {
        /* the bar of the navigation bars, so the notice wears the accent of the theme on both tones. the glass over its upper half has a hard edge like the keys of the
           old chrome, and the dark lip under it and the lit line over it set the bar off the screen */
        _backdrop = [ExteriaClassicStripBackdrop() retain];
        [self addSubview:_backdrop];
        _glass = [[CAGradientLayer layer] retain];
        _glass.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:1 alpha:0.30].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.08].CGColor, nil];
        [self.layer addSublayer:_glass];
        _lip = [[CALayer layer] retain];
        _lip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55].CGColor;
        [self.layer addSublayer:_lip];
        /* the sheen that runs over the bar once it has landed lives in a clipped view, as the shadow of the bar needs the bar itself to stay unclipped */
        _shine = [[UIView alloc] init];
        _shine.userInteractionEnabled = NO;
        _shine.clipsToBounds = YES;
        _sweep = [[CAGradientLayer layer] retain];
        _sweep.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:1 alpha:0].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.38].CGColor,
                         (id)[UIColor colorWithWhite:1 alpha:0].CGColor, nil];
        _sweep.startPoint = CGPointMake(0, 0.5);
        _sweep.endPoint = CGPointMake(1, 0.5);
        _sweep.bounds = CGRectMake(0, 0, CLASSIC_SWEEP_WIDTH, 10);
        _sweep.position = CGPointMake(-CLASSIC_SWEEP_WIDTH, 0);
        [_shine.layer addSublayer:_sweep];
        [self addSubview:_shine];
        /* a touch lights the bar like a pressed row of the old tables */
        _press = [[CALayer layer] retain];
        _press.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        _press.opacity = 0;
        [self.layer addSublayer:_press];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.55f;
        self.layer.shadowRadius = 5;
        self.layer.shadowOffset = CGSizeMake(0, 2);
    } else {
        self.backgroundColor = ExteriaColorCard();
        self.layer.cornerRadius = 16;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.25f;
        self.layer.shadowRadius = 8;
        self.layer.shadowOffset = CGSizeMake(0, 3);
    }
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = !classic;
    _avatar.hidden = YES;
    [self addSubview:_avatar];
    if (classic) {
        /* the picture sits on the bar like an app icon: a pale rim and a drop shadow */
        _avatar.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
        _avatar.layer.borderWidth = 1;
        /* the rim follows the corner the person chose for pictures, as the avatar draws itself with it */
        _avatar.layer.cornerRadius = CLASSIC_ICON * MIN(100, ExteriaAvatarCornerPercent()) / 200.0;
        _avatar.layer.shadowColor = [UIColor blackColor].CGColor;
        _avatar.layer.shadowOpacity = 0.6f;
        _avatar.layer.shadowRadius = 1.5f;
        _avatar.layer.shadowOffset = CGSizeMake(0, 1);
    }
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = classic ? [UIFont boldSystemFontOfSize:15] : ExteriaFontSemibold(15);
    _title.textColor = classic ? [UIColor whiteColor] : ExteriaColorTitle();
    [self addSubview:_title];
    /* the body names who wrote, and a UILabel shows a box for every letter of a styled name that the system font lacks */
    _body = [[ExteriaEmojiLabel alloc] init];
    _body.font = classic ? [UIFont systemFontOfSize:13] : ExteriaFontRegular(14);
    _body.textColor = classic ? [UIColor colorWithWhite:1 alpha:0.9] : ExteriaColorSecondary();
    if (classic) {
        /* the text is stamped into the bar, as the titles of the navigation bar are */
        _title.shadowColor = _body.shadowColor = [UIColor colorWithWhite:0 alpha:0.55];
        _title.shadowOffset = _body.shadowOffset = CGSizeMake(0, -1);
    }
    _body.numberOfLines = 2;
    /* the body starts with the sender of a group message, so a styled nick that no font draws is left out of it as it is out of the title, not drawn as a box */
    _body.dropsUndrawable = YES;
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
    [_backdrop release];
    [_glass release];
    [_lip release];
    [_press release];
    [_sweep release];
    [_shine release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL classic = ExteriaThemeIsClassic();
    CGSize size = self.bounds.size;
    CGFloat band = size.height - _contentTop;
    CGFloat icon = classic ? CLASSIC_ICON : AVATAR_SIDE;
    CGFloat edge = classic ? 10 : PADDING;
    if (classic) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _backdrop.frame = CGRectMake(0, -CLASSIC_BLEED, size.width, size.height + CLASSIC_BLEED);
        _glass.frame = CGRectMake(0, -CLASSIC_BLEED, size.width, size.height / 2 + CLASSIC_BLEED);
        CGFloat line = 1.0 / ExteriaScreenScale();
        _lip.frame = CGRectMake(0, size.height - line, size.width, line);
        _press.frame = self.bounds;
        _shine.frame = self.bounds;
        _sweep.bounds = CGRectMake(0, 0, CLASSIC_SWEEP_WIDTH, size.height);
        _sweep.position = CGPointMake(-CLASSIC_SWEEP_WIDTH / 2, size.height / 2);
        self.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.bounds].CGPath;
        [CATransaction commit];
    }
    /* the text starts after the picture, and at the old edge when the card has none */
    CGFloat left = _picture ? 122 : (_avatar.hidden ? 14 : edge + icon + 10);
    CGFloat width = MAX(0, size.width - left - 14);
    if (_picture) _picture.frame = CGRectMake(8, _contentTop + 6, 104, band - 12);
    _avatar.frame = CGRectMake(edge, _contentTop + floor((band - icon) / 2), icon, icon);
    CGFloat textTop = _contentTop + (_picture ? floor((band - 60) / 2) : (classic ? 6 : 8));
    _title.frame = CGRectMake(left, textTop, width, classic ? 18 : 20);
    _body.frame = CGRectMake(left, textTop + (classic ? 18 : 20), width, _picture ? 40 : (classic ? 32 : 28));
}

/* the classic bar falls from the top edge, sinks a little past its place and rises back, then the picture pops and a sheen runs over the bar */
- (void)dropWithBounce {
    CGFloat height = self.bounds.size.height;
    CAKeyframeAnimation *fall = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    fall.values = [NSArray arrayWithObjects:[NSNumber numberWithDouble:-height - 12], [NSNumber numberWithDouble:7], [NSNumber numberWithDouble:-3], [NSNumber numberWithDouble:0], nil];
    fall.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:0.58], [NSNumber numberWithDouble:0.8], [NSNumber numberWithDouble:1], nil];
    fall.timingFunctions = [NSArray arrayWithObjects:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn],
                            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], nil];
    fall.duration = 0.45;
    [self.layer addAnimation:fall forKey:@"classicDrop"];
    if (!_avatar.hidden) {
        CAKeyframeAnimation *pop = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        pop.values = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0.5], [NSNumber numberWithDouble:1.15], [NSNumber numberWithDouble:0.96], [NSNumber numberWithDouble:1], nil];
        pop.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:0.5], [NSNumber numberWithDouble:0.8], [NSNumber numberWithDouble:1], nil];
        pop.duration = 0.35;
        pop.beginTime = CACurrentMediaTime() + 0.3;
        pop.fillMode = kCAFillModeBackwards;
        [_avatar.layer addAnimation:pop forKey:@"classicPop"];
    }
    CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"position.x"];
    sweep.fromValue = [NSNumber numberWithDouble:-CLASSIC_SWEEP_WIDTH / 2];
    sweep.toValue = [NSNumber numberWithDouble:self.bounds.size.width + CLASSIC_SWEEP_WIDTH / 2];
    sweep.duration = 0.7;
    sweep.beginTime = CACurrentMediaTime() + 0.4;
    sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_sweep addAnimation:sweep forKey:@"classicSweep"];
}

- (void)lightPress:(BOOL)on {
    _press.opacity = on ? 1 : 0;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lightPress:YES];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lightPress:NO];
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lightPress:NO];
    [super touchesCancelled:touches withEvent:event];
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
