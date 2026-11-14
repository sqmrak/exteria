#import "exteria_slots_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_dice.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"

@interface ExteriaSlotsView () {
    NSMutableArray *_layers;
    exteria_slots_plan _plan;
    int32_t _result;
    CADisplayLink *_link;
    CFTimeInterval _start;
    BOOL _running;
    BOOL _throwing;
    BOOL _restShown;
    uint32_t _shown[EXTERIA_SLOTS_LAYERS];
    BOOL _hasShown;
    void (^_firstFrameHandler)(void);
}
@end

@implementation ExteriaSlotsView

@synthesize firstFrameHandler = _firstFrameHandler;

+ (NSArray *)documentIndexesForResult:(int32_t)result {
    exteria_slots_plan plan;
    if (result > 0) {
        if (exteria_slots_result_plan(result, &plan) != EXTERIA_OK) return nil;
    } else {
        exteria_slots_idle_plan(&plan);
    }
    NSMutableArray *indexes = [NSMutableArray arrayWithCapacity:EXTERIA_SLOTS_LAYERS];
    for (int i = 0; i < EXTERIA_SLOTS_LAYERS; ++i) [indexes addObject:[NSNumber numberWithInt:plan.doc[i]]];
    return indexes;
}

- (id)initWithLayers:(NSArray *)data result:(int32_t)result keyBase:(NSString *)keyBase {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    if (data.count != EXTERIA_SLOTS_LAYERS) {
        [self release];
        return nil;
    }
    if (result > 0 && exteria_slots_result_plan(result, &_plan) != EXTERIA_OK) result = 0;
    if (result <= 0) exteria_slots_idle_plan(&_plan);
    _result = result;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    _layers = [[NSMutableArray alloc] initWithCapacity:EXTERIA_SLOTS_LAYERS];
    for (int i = 0; i < EXTERIA_SLOTS_LAYERS; ++i) {
        ExteriaLottieView *layer = [[ExteriaLottieView alloc] initWithPackedData:[data objectAtIndex:(NSUInteger)i] key:[NSString stringWithFormat:@"%@-%d", keyBase, i]];
        [layer setLoaded:YES];
        [self addSubview:layer];
        [_layers addObject:layer];
        [layer release];
    }
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_layers release];
    [_firstFrameHandler release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (ExteriaLottieView *layer in _layers) layer.frame = self.bounds;
}

/* the frame counts of the five layers, or NO while any of them is still being parsed */
- (BOOL)counts:(uint32_t *)counts {
    for (int i = 0; i < EXTERIA_SLOTS_LAYERS; ++i) {
        NSUInteger count = [(ExteriaLottieView *)[_layers objectAtIndex:(NSUInteger)i] frameCount];
        if (count == 0 || count > 100000) return NO;
        counts[i] = (uint32_t)count;
    }
    return YES;
}

- (void)stopLink {
    [_link invalidate];
    _link = nil;
}

- (void)startLink {
    if (_link || !self.window) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    ExteriaSetFrameRate(_link, 60);
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self stopLink];
    else if (_running || !_restShown) [self startLink];
}

- (void)applyFrames:(const uint32_t *)frames {
    for (int i = 0; i < EXTERIA_SLOTS_LAYERS; ++i) {
        if (_hasShown && _shown[i] == frames[i]) continue;
        [(ExteriaLottieView *)[_layers objectAtIndex:(NSUInteger)i] showFrame:frames[i]];
        _shown[i] = frames[i];
    }
    _hasShown = YES;
    if (_firstFrameHandler) {
        void (^ready)(void) = _firstFrameHandler;
        _firstFrameHandler = nil;
        ready();
        [ready release];
    }
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    uint32_t counts[EXTERIA_SLOTS_LAYERS], frames[EXTERIA_SLOTS_LAYERS];
    if (![self counts:counts]) return;
    double rate = [(ExteriaLottieView *)[_layers objectAtIndex:EXTERIA_SLOTS_BACK] framesPerSecond];
    if (rate <= 0) rate = 60;
    if (!_running) {
        /* the first frame of the throw, or the last of the throw that is at rest, shows once and the clock stays off */
        if (_result > 0 && _restShown) {
            uint32_t total = exteria_slots_result_total(&_plan, counts);
            if (total == 0 || exteria_slots_result_frames(&_plan, counts, total - 1, frames) != EXTERIA_OK) return;
        } else if (_result > 0) {
            if (exteria_slots_result_frames(&_plan, counts, 0, frames) != EXTERIA_OK) return;
        } else if (exteria_slots_idle_frames(counts, 0, frames) != EXTERIA_OK) return;
        [self applyFrames:frames];
        [self stopLink];
        return;
    }
    double elapsed = CACurrentMediaTime() - _start;
    uint32_t frame = (uint32_t)(elapsed * rate);
    if (_throwing) {
        uint32_t total = exteria_slots_result_total(&_plan, counts);
        if (total == 0) return;
        if (frame >= total) {
            frame = total - 1;
            _running = NO;
            _throwing = NO;
            _restShown = YES;
            [self stopLink];
        }
        if (exteria_slots_result_frames(&_plan, counts, frame, frames) != EXTERIA_OK) return;
    } else if (exteria_slots_idle_frames(counts, frame, frames) != EXTERIA_OK) {
        return;
    }
    [self applyFrames:frames];
}

- (void)setActive:(BOOL)active {
    if (ExteriaReduceMotionEnabled()) active = NO;
    if (_result > 0) {
        /* a throw plays only when playThrow asks; leaving the screen in the middle of one leaves it on its last frame */
        if (!active && _throwing) [self showRest];
        return;
    }
    if (active == _running) return;
    _running = active;
    _start = CACurrentMediaTime();
    _hasShown = NO;
    [self startLink];
}

- (void)playThrow {
    if (_result <= 0) {
        [self setActive:YES];
        return;
    }
    if (ExteriaReduceMotionEnabled()) {
        [self showRest];
        return;
    }
    _running = YES;
    _throwing = YES;
    _restShown = NO;
    _start = CACurrentMediaTime();
    _hasShown = NO;
    [self startLink];
}

- (void)showRest {
    _running = NO;
    _throwing = NO;
    _restShown = YES;
    _hasShown = NO;
    [self startLink];
}

@end
