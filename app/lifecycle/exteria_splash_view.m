#import "exteria_splash_view.h"
#import "exteria_app_icon.h"

#define ICON_SIDE 96.0
#define FADE_SECONDS 0.25
/* a start that settles at once would show the splash for a blink, so it stays at least this long */
#define HOLD_SECONDS 1.2

NSString *const ExteriaFirstScreenReadyNotification = @"ExteriaFirstScreenReady";

/* a png decodes on its first draw, which left the first frame of the splash without the icon */
static UIImage *ExteriaDecodedIcon(UIImage *image) {
    if (!image) return nil;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawAtPoint:CGPointZero];
    UIImage *decoded = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return decoded ? decoded : image;
}

@interface ExteriaSplashView () {
    UIImageView *_icon;
    BOOL _dismissing;
    NSTimeInterval _shownAt;
}
@end

@implementation ExteriaSplashView

- (id)initWithFrame:(CGRect)frame color:(UIColor *)color {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = color;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _icon = [[UIImageView alloc] initWithImage:ExteriaDecodedIcon(ExteriaSplashIconImage())];
    [self addSubview:_icon];
    [self layoutSubviews];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && _shownAt == 0) _shownAt = [NSDate timeIntervalSinceReferenceDate];
}

- (void)dealloc {
    [_icon release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _icon.frame = CGRectMake(floor((self.bounds.size.width - ICON_SIDE) / 2), floor((self.bounds.size.height - ICON_SIDE) / 2), ICON_SIDE, ICON_SIDE);
}

- (void)dismiss {
    if (_dismissing) return;
    _dismissing = YES;
    NSTimeInterval remaining = _shownAt ? HOLD_SECONDS - ([NSDate timeIntervalSinceReferenceDate] - _shownAt) : HOLD_SECONDS;
    if (remaining > 0) [self performSelector:@selector(fadeOut) withObject:nil afterDelay:remaining];
    else [self fadeOut];
}

- (void)fadeOut {
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:FADE_SECONDS animations:^{ self.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    }];
}

@end
