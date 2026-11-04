#import "exteria_typing_bubble.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_settings.h"
#import "exteria_theme.h"

/* the size of the bubble of the intro: 52 by 30, three dots of radius 3 ten points apart, the first 16 from the left edge. the beat is one second with a sixth of a
   second between the dots; a dot rises 3.5 points and is at half strength at rest */
#define BUBBLE_WIDTH 52.0
#define BUBBLE_HEIGHT 30.0
#define DOT_COUNT 3
#define DOT_RADIUS 3.0
#define DOT_STEP 10.0
#define DOT_FIRST_X 16.0
#define DOT_RISE 3.5
#define BEAT_PERIOD 1.0
#define BEAT_STAGGER 0.16
#define BEAT_SAMPLES 24
#define REST_ALPHA 0.5f

static NSString *const ExteriaTypingBeatKey = @"exteria.typing.beat";

@implementation ExteriaTypingBubble

+ (CGSize)size { return CGSizeMake(BUBBLE_WIDTH, BUBBLE_HEIGHT); }

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, BUBBLE_WIDTH, BUBBLE_HEIGHT)];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    NSMutableArray *dots = [NSMutableArray array];
    for (int i = 0; i < DOT_COUNT; ++i) {
        CALayer *dot = [CALayer layer];
        dot.bounds = CGRectMake(0, 0, DOT_RADIUS * 2, DOT_RADIUS * 2);
        dot.position = CGPointMake(DOT_FIRST_X + i * DOT_STEP, BUBBLE_HEIGHT / 2);
        dot.cornerRadius = DOT_RADIUS;
        /* the beat moves a dot by its own steps, so the layer is not to glide to a new place by itself either */
        dot.actions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"bounds", nil];
        dot.opacity = REST_ALPHA;
        [self.layer addSublayer:dot];
        [dots addObject:dot];
    }
    _dots = [dots retain];
    [self applyTheme];
    return self;
}

- (void)dealloc {
    [_dots release];
    [super dealloc];
}

/* the dots stand in the middle of the bubble however large it is made, and the whole row is as wide as the three dots and the two steps between them */
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat row = DOT_STEP * (DOT_COUNT - 1) + DOT_RADIUS * 2;
    CGFloat first = floor((size.width - row) / 2) + DOT_RADIUS;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _dots.count; ++i) ((CALayer *)[_dots objectAtIndex:i]).position = CGPointMake(first + (CGFloat)i * DOT_STEP, size.height / 2);
    [CATransaction commit];
}

- (void)applyTheme {
    BOOL classic = ExteriaThemeIsClassic();
    CGFloat radius = (CGFloat)(classic ? ExteriaChatClassicBubbleRadius() : ExteriaChatBubbleRadius());
    self.backgroundColor = ExteriaColorBubbleIn();
    self.layer.cornerRadius = MIN(radius, BUBBLE_HEIGHT / 2);
    /* a near white bubble melts into the light wallpaper, so the incoming ones get the thin outline the messages have */
    self.layer.borderWidth = !classic && !ExteriaThemeIsDark() ? 1 : 0;
    self.layer.borderColor = [ExteriaColorAccent() colorWithAlphaComponent:0.3f].CGColor;
    for (CALayer *dot in _dots) dot.backgroundColor = ExteriaColorSecondary().CGColor;
}

/* the lift and the light of a dot follow (1 - cos) / 2 over the whole period, so it never stops or turns with a corner. the wave is sampled at 24 points a period, which
   linear steps cannot tell from the curve on a screen */
- (void)startBeat {
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray *light = [NSMutableArray arrayWithCapacity:BEAT_SAMPLES + 1], *lift = [NSMutableArray arrayWithCapacity:BEAT_SAMPLES + 1], *times = [NSMutableArray arrayWithCapacity:BEAT_SAMPLES + 1];
    for (int k = 0; k <= BEAT_SAMPLES; ++k) {
        double phase = (double)k / BEAT_SAMPLES;
        double wave = (1 - cos(2 * M_PI * phase)) / 2;
        [light addObject:[NSNumber numberWithFloat:(float)(REST_ALPHA + (1 - REST_ALPHA) * wave)]];
        [lift addObject:[NSNumber numberWithFloat:(float)(-DOT_RISE * wave)]];
        [times addObject:[NSNumber numberWithFloat:(float)phase]];
    }
    for (NSUInteger i = 0; i < _dots.count; ++i) {
        CALayer *dot = [_dots objectAtIndex:i];
        CAKeyframeAnimation *glow = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        glow.values = light;
        glow.keyTimes = times;
        CAKeyframeAnimation *rise = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
        rise.values = lift;
        rise.keyTimes = times;
        CAAnimationGroup *beat = [CAAnimationGroup animation];
        beat.animations = [NSArray arrayWithObjects:glow, rise, nil];
        beat.duration = BEAT_PERIOD;
        beat.repeatCount = HUGE_VALF;
        beat.beginTime = now + i * BEAT_STAGGER;
        beat.fillMode = kCAFillModeBackwards;
        [dot removeAnimationForKey:ExteriaTypingBeatKey];
        [dot addAnimation:beat forKey:ExteriaTypingBeatKey];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self startBeat];
}

@end
