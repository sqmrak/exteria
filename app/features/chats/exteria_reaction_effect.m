#import "exteria_reaction_effect.h"

#import "exteria_lottie_view.h"
#import "exteria_platform.h"

/* ReactionsEffectOverlay: the large burst is 0.8 of the smaller screen side up to 350 points, the reaction in it is half of that, the short burst is 80 points */
#define LONG_BURST_MAX 350.0
#define LONG_BURST_SHARE 0.8
#define SHORT_BURST_SIDE 80.0
/* a view whose animation cannot be parsed never reports its end, so the container leaves by itself */
#define EFFECT_LIFETIME 6.0

/* a callback of an effect that was ended or replaced carries an older token */
static UIView *sCurrent;
static NSUInteger sToken;

@implementation ExteriaReactionEffect

+ (void)dismiss {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    ++sToken;
    [sCurrent removeFromSuperview];
    [sCurrent release];
    sCurrent = nil;
}

+ (void)expire:(NSNumber *)token {
    if (token.unsignedIntegerValue == sToken) [self dismiss];
}

/* the square of side around point, moved to stay inside the host */
static CGRect ExteriaEffectFrame(CGPoint point, CGFloat side, CGRect bounds) {
    CGFloat x = MAX(CGRectGetMinX(bounds), MIN(point.x - side / 2, CGRectGetMaxX(bounds) - side));
    CGFloat y = MAX(CGRectGetMinY(bounds), MIN(point.y - side / 2, CGRectGetMaxY(bounds) - side));
    return CGRectMake(floor(x), floor(y), side, side);
}

+ (void)playArtwork:(ExteriaReactionArtwork *)artwork longBurst:(BOOL)longBurst around:(CGPoint)point inView:(UIView *)host media:(ExteriaMediaCache *)media {
    [self dismiss];
    if (!artwork || !host || !media || ExteriaReduceMotionEnabled()) return;
    ExteriaCustomEmojiDocument *burst = longBurst ? artwork.effect : artwork.around;
    if (!burst) return;
    CGFloat side = longBurst ? floor(MIN(LONG_BURST_MAX, MIN(host.bounds.size.width, host.bounds.size.height) * LONG_BURST_SHARE)) : SHORT_BURST_SIDE;
    CGRect frame = ExteriaEffectFrame(point, side, host.bounds);
    UIView *container = [[[UIView alloc] initWithFrame:host.bounds] autorelease];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.userInteractionEnabled = NO;
    container.backgroundColor = [UIColor clearColor];
    [host addSubview:container];
    sCurrent = [container retain];
    NSUInteger token = sToken;
    [self performSelector:@selector(expire:) withObject:[NSNumber numberWithUnsignedInteger:token] afterDelay:EFFECT_LIFETIME];
    /* wait for both files so a slow activation cannot appear after the burst has ended */
    [ExteriaReactionArtwork animationViewForDocument:longBurst ? artwork.activate : nil media:media completion:^(ExteriaLottieView *activation) {
        if (token != sToken || !sCurrent) return;
        [ExteriaReactionArtwork animationViewForDocument:burst media:media completion:^(ExteriaLottieView *view) {
            if (token != sToken || !sCurrent) return;
            if (!view) { [ExteriaReactionEffect dismiss]; return; }
            view.frame = frame;
            view.userInteractionEnabled = NO;
            [sCurrent addSubview:view];
            view.finishHandler = ^{ if (token == sToken) [ExteriaReactionEffect dismiss]; };
            if (activation) {
                CGFloat icon = floor(side / 2);
                activation.frame = CGRectMake(floor(CGRectGetMidX(frame) - icon / 2), floor(CGRectGetMidY(frame) - icon / 2), icon, icon);
                activation.userInteractionEnabled = NO;
                [sCurrent addSubview:activation];
            }
            [view playOnce];
            [activation playOnce];
        }];
    }];
}

@end
