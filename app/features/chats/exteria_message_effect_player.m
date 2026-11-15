#import "exteria_message_effect_player.h"

#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_reaction_artwork.h"

/* a file that cannot be parsed never reports its end, so the overlay leaves by itself */
#define EFFECT_LIFETIME 8.0

static UIView *sCurrent;
static NSUInteger sToken;

@implementation ExteriaMessageEffectPlayer

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

+ (void)playEffect:(ExteriaMessageEffect *)effect inView:(UIView *)host media:(ExteriaMediaCache *)media {
    [self dismiss];
    ExteriaCustomEmojiDocument *document = effect.animation ? effect.animation : effect.sticker;
    if (!document || !host || !media || ExteriaReduceMotionEnabled()) return;
    UIView *container = [[[UIView alloc] initWithFrame:host.bounds] autorelease];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.userInteractionEnabled = NO;
    container.backgroundColor = [UIColor clearColor];
    [host addSubview:container];
    sCurrent = [container retain];
    NSUInteger token = sToken;
    [self performSelector:@selector(expire:) withObject:[NSNumber numberWithUnsignedInteger:token] afterDelay:EFFECT_LIFETIME];
    [ExteriaReactionArtwork animationViewForDocument:document media:media completion:^(ExteriaLottieView *view) {
        if (token != sToken || !sCurrent) return;
        if (!view) { [ExteriaMessageEffectPlayer dismiss]; return; }
        CGFloat side = floor(MIN(host.bounds.size.width, host.bounds.size.height));
        view.frame = CGRectMake(floor((host.bounds.size.width - side) / 2), floor((host.bounds.size.height - side) / 2), side, side);
        view.userInteractionEnabled = NO;
        [sCurrent addSubview:view];
        view.finishHandler = ^{ if (token == sToken) [ExteriaMessageEffectPlayer dismiss]; };
        [view playOnce];
    }];
}

@end
