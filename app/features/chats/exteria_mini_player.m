#import "exteria_mini_player.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_classic_chrome.h"
#import "exteria_emoji_label.h"
#import "exteria_music_player.h"
#import "exteria_music_sheet.h"
#import "exteria_platform.h"
#import "exteria_round_playback.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define STRIP_HEIGHT 46.0
#define BUTTON_WIDTH 40.0
/* the modern strip is a tonal card with 8 points of room at the sides; a pill has room above and below it too */
#define CARD_HEIGHT 62.0
#define CARD_SIDE 8.0
#define CARD_RADIUS 16.0
#define PILL_GAP 8.0
#define LEAD_SIDE 40.0
#define LEAD_RADIUS 12.0
#define KEY_SIDE 36.0
#define PLAY_SIDE 40.0
/* the progress rings the play key as the circular indicator of Material 3: the played arc waves while the sound runs (RING_WAVES whole waves around, so the turn
   loops without a seam), then a gap and the plain track that is left */
#define RING_RADIUS 17.0
#define RING_STROKE 2.2
#define RING_AMPLITUDE 1.3
#define RING_WAVES 10
#define RING_GAP 4.0
#define RING_PERIOD 2.0
/* a card narrower than this (a 320 point screen) packs its keys and tile closer, so all four keys still fit beside the text */
#define CARD_NARROW 330.0
#define KEY_SIDE_NARROW 32.0
#define LEAD_SIDE_NARROW 36.0

@interface ExteriaMiniPlayer () {
    ExteriaEmojiLabel *_title;
    UIButton *_previous;
    UIButton *_toggle;
    UIButton *_next;
    UIButton *_close;
    UIView *_line;
    UIImageView *_backdrop;
    UIView *_card;
    UIView *_lead;
    UIImageView *_leadGlyph;
    UIImageView *_leadCover;
    ExteriaEmojiLabel *_subtitle;
    CALayer *_ring;
    CAShapeLayer *_ringTrack;
    CALayer *_ringSpin;
    CAShapeLayer *_ringArc;
    BOOL _ringWavy;
    BOOL _waving;
    UIColor *_tone;
    NSTimer *_timer;
    CGFloat _fraction;
    BOOL _showing;
    BOOL _pill;
    UIColor *_surface;
    void (^_changeHandler)(void);
    void (^_openHandler)(void);
    void (^_closeHandler)(void);
}
@end

@implementation ExteriaMiniPlayer

@synthesize showing = _showing;
@synthesize pill = _pill;
@synthesize changeHandler = _changeHandler;
@synthesize openHandler = _openHandler;
@synthesize closeHandler = _closeHandler;

+ (BOOL)isActive {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    /* a video message that plays holds the output, so the strip is its and not the one of the song it paused */
    return [ExteriaRoundPlayback sharedPlayback].active || (player.state != ExteriaMusicStateIdle && player.track != nil);
}

+ (CGFloat)height { return ExteriaThemeIsClassic() ? STRIP_HEIGHT : CARD_HEIGHT; }
+ (CGFloat)heightForPill:(BOOL)pill { return ExteriaThemeIsClassic() || !pill ? [self height] : CARD_HEIGHT + 2 * PILL_GAP; }

/* the tonal colors of the card from a key color, the way a Material You scheme makes them: a container a little off the surface, a stronger one for the glyph tile, the key
   color itself for the play key and a dark or light ink for what stands on each. the key color is the accent, or the tonal primary of the cover in the lyrics */
static UIColor *ExteriaStripContainer(UIColor *surface, UIColor *key) {
    return ExteriaMixedColor(surface, key, ExteriaThemeIsDark() ? 0.22 : 0.14);
}
static UIColor *ExteriaStripTile(UIColor *key) {
    return ExteriaThemeIsDark() ? ExteriaMixedColor([UIColor colorWithWhite:0.12 alpha:1], key, 0.5) : ExteriaMixedColor([UIColor whiteColor], key, 0.3);
}
static UIColor *ExteriaStripOnTile(UIColor *key) {
    return ExteriaThemeIsDark() ? ExteriaMixedColor(key, [UIColor whiteColor], 0.75) : ExteriaMixedColor(key, [UIColor blackColor], 0.55);
}
/* the primary of a scheme made from a color of the cover: pale and soft on the dark theme, deep on the light one, whatever the cover's own brightness was */
static UIColor *ExteriaStripTonalPrimary(UIColor *tone) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0, hue = 0, saturation = 0, value = 0;
    if (![tone getRed:&red green:&green blue:&blue alpha:&alpha]) return ExteriaColorAccent();
    ExteriaRGBToHSV(red, green, blue, &hue, &saturation, &value);
    if (ExteriaThemeIsDark()) ExteriaHSVToRGB(hue, MIN(saturation, 0.5), 0.88, &red, &green, &blue);
    else ExteriaHSVToRGB(hue, MIN(0.85, MAX(saturation, 0.2)), 0.45, &red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:1];
}

/* a round state layer that stretches to the button it is the background of, so a press lights a disc and not the whole box of the button */
static UIImage *ExteriaStripDisc(UIColor *color) {
    CGFloat side = 40;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [color setFill];
    CGContextFillEllipseInRect(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, side, side));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(side / 2 - 1, side / 2 - 1, side / 2 - 1, side / 2 - 1)];
}

static NSString *ExteriaStripClock(NSTimeInterval seconds) {
    NSInteger total = seconds > 0 ? (NSInteger)seconds : 0;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

static UIButton *ExteriaStripButton(ExteriaSymbol symbol, id target, SEL action, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    if (ExteriaThemeIsClassic()) {
        [button setImage:ExteriaSymbolImage(symbol, 20, ExteriaClassicStripInk()) forState:UIControlStateNormal];
    } else {
        [button setImage:ExteriaSymbolImage(symbol, 24, ExteriaColorSecondary()) forState:UIControlStateNormal];
        [button setBackgroundImage:ExteriaStripDisc([ExteriaColorSecondary() colorWithAlphaComponent:0.16]) forState:UIControlStateHighlighted];
    }
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = NSLocalizedString(label, nil);
    return button;
}

- (void)setPill:(BOOL)pill {
    if (pill == _pill) return;
    _pill = pill;
    [self setNeedsLayout];
}

- (UIColor *)key { return _tone ? ExteriaStripTonalPrimary(_tone) : ExteriaColorAccent(); }

/* the card in the colors of its key: the surface, the tile, the keys, the ring. a tone makes the card a scheme of that color, no tone is the accent of the app */
- (void)applyScheme {
    if (ExteriaThemeIsClassic()) return;
    UIColor *key = [self key];
    BOOL wave = _tone != nil;
    _card.backgroundColor = _surface ? _surface : ExteriaStripContainer(ExteriaColorCard(), key);
    _lead.backgroundColor = ExteriaStripTile(key);
    _ringArc.strokeColor = key.CGColor;
    _ringTrack.strokeColor = ExteriaMixedColor(ground, key, 0.35).CGColor;
    /* the ring is the key now, so only a press lights a disc inside it */
    [_toggle setBackgroundImage:nil forState:UIControlStateNormal];
    [_toggle setBackgroundImage:ExteriaStripDisc([key colorWithAlphaComponent:0.16]) forState:UIControlStateHighlighted];
    UIColor *ink = toned ? ExteriaStripOnTile(key) : ExteriaColorSecondary();
    [_previous setImage:ExteriaSymbolImage(ExteriaSymbolPlayerPrevious, 24, ink) forState:UIControlStateNormal];
    [_next setImage:ExteriaSymbolImage(ExteriaSymbolPlayerNext, 24, ink) forState:UIControlStateNormal];
    [_close setImage:ExteriaSymbolImage(ExteriaSymbolPlayerClose, 24, ink) forState:UIControlStateNormal];
    [self refresh];
}

- (void)setTone:(UIColor *)tone surface:(UIColor *)surface animated:(BOOL)animated {
    BOOL layoutChanges = (tone != nil) != (_tone != nil);
    [_tone release];
    _tone = [tone retain];
    [_surface release];
    _surface = [surface retain];
    if (animated && _card && self.window && !ExteriaReduceMotionEnabled()) {
        [UIView transitionWithView:_card duration:0.6 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ [self applyScheme]; } completion:nil];
    } else {
        [self applyScheme];
    }
    if (layoutChanges) [self setNeedsLayout];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BOOL classic = ExteriaThemeIsClassic();
    self.clipsToBounds = YES;
    if (classic) {
        /* a plain black or white ground, as the pinned message has, and not the purple of the bars: the chat showed through the strip and the plate made a stripe */
        self.backgroundColor = ExteriaClassicStripGround();
    } else {
        /* the rounded card stands alone, so the wallpaper shows in the gutter below it and not a plate */
        self.backgroundColor = [UIColor clearColor];
    }
    if (!classic) {
        _card = [[UIView alloc] init];
        _card.backgroundColor = ExteriaStripContainer(ExteriaColorCard(), ExteriaColorAccent());
        [self addSubview:_card];
        _lead = [[UIView alloc] init];
        _lead.backgroundColor = ExteriaStripTile(ExteriaColorAccent());
        _lead.layer.cornerRadius = LEAD_RADIUS;
        _lead.clipsToBounds = YES;
        [_card addSubview:_lead];
        _leadGlyph = [[UIImageView alloc] init];
        _leadGlyph.contentMode = UIViewContentModeCenter;
        [_lead addSubview:_leadGlyph];
        _leadCover = [[UIImageView alloc] init];
        _leadCover.contentMode = UIViewContentModeScaleAspectFill;
        _leadCover.clipsToBounds = YES;
        _leadCover.hidden = YES;
        [_lead addSubview:_leadCover];
        _subtitle = [[ExteriaEmojiLabel alloc] init];
        _subtitle.font = ExteriaFontRegular(12);
        _subtitle.textColor = ExteriaColorSecondary();
        _subtitle.dropsUndrawable = YES;
        [_card addSubview:_subtitle];
        [self makeRing];
    }
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = classic ? [UIFont boldSystemFontOfSize:14] : ExteriaFontSemibold(14);
    _title.textColor = classic ? ExteriaClassicStripInk() : ExteriaColorTitle();
    if (classic && ExteriaThemeIsDark()) {
        _title.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        _title.shadowOffset = CGSizeMake(0, -1);
    }
    _title.dropsUndrawable = YES;
    [classic ? (UIView *)self : _card addSubview:_title];
    _title.userInteractionEnabled = YES;
    [_title addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPlayer)] autorelease]];
    _previous = [ExteriaStripButton(classic ? ExteriaSymbolPrevious : ExteriaSymbolPlayerPrevious, self, @selector(previousTapped), @"music.previous") retain];
    _toggle = [ExteriaStripButton(ExteriaSymbolPlay, self, @selector(toggleTapped), @"music.play") retain];
    _next = [ExteriaStripButton(classic ? ExteriaSymbolNext : ExteriaSymbolPlayerNext, self, @selector(nextTapped), @"music.next") retain];
    _close = [ExteriaStripButton(classic ? ExteriaSymbolClose : ExteriaSymbolPlayerClose, self, @selector(closeTapped), @"music.stop") retain];
    for (UIView *view in [NSArray arrayWithObjects:_previous, _toggle, _next, _close, nil]) [classic ? (UIView *)self : _card addSubview:view];
    if (!classic) [self applyScheme];
    _line = [[UIView alloc] init];
    _line.backgroundColor = classic ? ExteriaClassicStripEdge() : ExteriaColorHairline();
    /* the card floats between its gutters, so it has no line under it */
    _line.hidden = !classic;
    [self addSubview:_line];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaRoundPlaybackDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    [_tone release];
    [_surface release];
    [_ring release];
    [_ringTrack release];
    [_ringSpin release];
    [_ringArc release];
    [_card release];
    [_lead release];
    [_leadGlyph release];
    [_leadCover release];
    [_subtitle release];
    [_title release];
    [_previous release];
    [_toggle release];
    [_next release];
    [_close release];
    [_line release];
    [_backdrop release];
    [_changeHandler release];
    [_openHandler release];
    [_closeHandler release];
    [super dealloc];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (void)refresh {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    ExteriaRoundPlayback *round = [ExteriaRoundPlayback sharedPlayback];
    BOOL showing = [ExteriaMiniPlayer isActive];
    if (showing) {
        BOOL playing = round.active ? round.playing : (player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStateLoading);
        if (ExteriaThemeIsClassic()) {
            _title.text = round.active ? NSLocalizedString(@"round.title", nil) : ExteriaTrackLine(player.track);
            [_toggle setImage:ExteriaSymbolImage(playing ? ExteriaSymbolPause : ExteriaSymbolPlay, 22, ExteriaClassicStripInk()) forState:UIControlStateNormal];
        } else {
            [self showModernPlaying:playing round:round.active];
        }
        _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    }
    if (showing != _showing) {
        _showing = showing;
        /* the owner lays the strip in and out at its new height inside the animation, so the list under it slides instead of jumping when a voice
           message opens or ends the player; the strip stays visible until the collapse is done, and its clipping hides the rest */
        if (showing) self.hidden = NO;
        BOOL animate = self.window != nil && !ExteriaReduceMotionEnabled();
        void (^change)(void) = ^{ if (_changeHandler) _changeHandler(); };
        if (!animate) {
            change();
            self.hidden = !_showing;
        } else {
            [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:change completion:^(BOOL finished) {
                (void)finished;
                self.hidden = !_showing;
            }];
        }
    }
    [self updateTimer];
    [self setNeedsLayout];
}

/* what the card says: the title, the line under it, the tile that tells a song from a voice message from a video message, and the key that plays or pauses */
- (void)showModernPlaying:(BOOL)playing round:(BOOL)round {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    BOOL voice = !round && player.track.kind == EXTERIA_PREVIEW_VOICE;
    _title.text = round ? NSLocalizedString(@"round.title", nil) : ExteriaTrackTitle(player.track);
    UIImage *cover = round || voice ? nil : player.cover;
    _leadCover.image = cover;
    _leadCover.hidden = cover == nil;
    _leadGlyph.hidden = cover != nil;
    _leadGlyph.image = ExteriaSymbolImage(round ? ExteriaSymbolMaterialVideocam : (voice ? ExteriaSymbolMaterialMic : ExteriaSymbolPlayerNote), 24, ExteriaStripOnTile([self key]));
    UIImage *key = ExteriaSymbolImage(playing ? ExteriaSymbolPlayerPause : ExteriaSymbolPlayerPlay, 24, [self key]);
    if (_toggle.currentImage != key) {
        BOOL animate = self.window != nil && _showing && !ExteriaReduceMotionEnabled() && _toggle.currentImage;
        if (animate) {
            [UIView transitionWithView:_toggle duration:0.15 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                            animations:^{ [_toggle setImage:key forState:UIControlStateNormal]; } completion:nil];
        } else {
            [_toggle setImage:key forState:UIControlStateNormal];
        }
    }
    _waving = playing;
    [self updateProgress];
}

/* the line under the title and the ring of the play key follow the sound; a song names its performer, and a voice or video message tells how far it is */
- (void)updateProgress {
    if (ExteriaThemeIsClassic()) return;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    ExteriaRoundPlayback *round = [ExteriaRoundPlayback sharedPlayback];
    NSTimeInterval duration, position;
    NSString *line;
    if (round.active) {
        duration = round.duration;
        _fraction = round.progress;
        position = duration * _fraction;
        line = duration > 0 ? [NSString stringWithFormat:@"%@ / %@", ExteriaStripClock(position), ExteriaStripClock(duration)] : @"";
    } else {
        duration = player.duration;
        position = player.position;
        _fraction = duration > 0 ? (CGFloat)(position / duration) : 0;
        NSString *performer = ExteriaTrackPerformer(player.track);
        BOOL voice = player.track.kind == EXTERIA_PREVIEW_VOICE;
        line = performer.length && !voice ? performer : (duration > 0 ? [NSString stringWithFormat:@"%@ / %@", ExteriaStripClock(position), ExteriaStripClock(duration)] : @"");
    }
    _fraction = MIN(1, MAX(0, _fraction));
    if (![_subtitle.text isEqualToString:line]) {
        BOOL appears = (line.length > 0) != (_subtitle.text.length > 0);
        _subtitle.text = line;
        if (appears) [self setNeedsLayout];
    }
    [self layoutProgress];
}

/* a ring from the top, clockwise, turned twice: the played arc is a stroke range of it, and the range may slide past the first turn while the wave runs */
static CGPathRef ExteriaRingPath(CGPoint center, BOOL wavy) {
    CGMutablePathRef path = CGPathCreateMutable();
    const int steps = 2 * 180;
    for (int i = 0; i <= steps; ++i) {
        CGFloat angle = -(CGFloat)M_PI_2 + 4 * (CGFloat)M_PI * i / steps;
        CGFloat radius = RING_RADIUS + (wavy ? RING_AMPLITUDE * sinf(RING_WAVES * angle) : 0);
        CGFloat x = center.x + radius * cosf(angle), y = center.y + radius * sinf(angle);
        if (i == 0) CGPathMoveToPoint(path, NULL, x, y);
        else CGPathAddLineToPoint(path, NULL, x, y);
    }
    return path;
}

/* a stroke value set with no implicit animation, and the step to it spread over the tick as an additive linear slide. the implicit one eased in and out on every
   tick, and began from the shown value that already holds the additive wave offset, so the end of the arc jumped back and pulsed four times a second */
static void ExteriaRingSetStroke(CAShapeLayer *layer, NSString *keyPath, CGFloat value, NSTimeInterval follow) {
    NSString *key = [@"follow." stringByAppendingString:keyPath];
    CGFloat old = [[layer valueForKey:keyPath] floatValue];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer setValue:[NSNumber numberWithFloat:(float)value] forKey:keyPath];
    [CATransaction commit];
    /* a seek or a new song snaps, a tick of the sound slides */
    if (follow <= 0 || old == value || fabs(old - value) > 0.05 || !layer.superlayer) {
        [layer removeAnimationForKey:key];
        return;
    }
    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:keyPath];
    slide.fromValue = [NSNumber numberWithFloat:(float)(old - value)];
    slide.toValue = [NSNumber numberWithFloat:0];
    slide.additive = YES;
    slide.duration = follow;
    slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:slide forKey:key];
}

- (void)makeRing {
    _ring = [[CALayer layer] retain];
    _ringTrack = [[CAShapeLayer layer] retain];
    _ringSpin = [[CALayer layer] retain];
    _ringArc = [[CAShapeLayer layer] retain];
    for (CAShapeLayer *shape in [NSArray arrayWithObjects:_ringTrack, _ringArc, nil]) {
        shape.fillColor = NULL;
        shape.lineWidth = RING_STROKE;
        shape.lineCap = kCALineCapRound;
        shape.lineJoin = kCALineJoinRound;
        shape.strokeStart = 0;
        shape.strokeEnd = 0;
    }
    [_ring addSublayer:_ringTrack];
    [_ring addSublayer:_ringSpin];
    [_ringSpin addSublayer:_ringArc];
    [_card.layer insertSublayer:_ring atIndex:0];
}

- (void)layoutProgress {
    if (!_ring) return;
    CGFloat side = 2 * (RING_RADIUS + RING_AMPLITUDE + RING_STROKE);
    CGRect frame = CGRectMake(CGRectGetMidX(_toggle.frame) - side / 2, CGRectGetMidY(_toggle.frame) - side / 2, side, side);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!CGRectEqualToRect(_ring.frame, frame)) {
        _ring.frame = frame;
        _ringSpin.frame = _ring.bounds;
        _ringTrack.frame = _ringArc.frame = _ring.bounds;
        CGPoint center = CGPointMake(side / 2, side / 2);
        CGPathRef flat = ExteriaRingPath(center, NO);
        _ringTrack.path = flat;
        CGPathRelease(flat);
    }
    [self updateRingShape];
    [CATransaction commit];
    /* the arc and the track follow the sound smoothly between the ticks, on the strokes alone so the ring itself does not slide */
    CGFloat played = _fraction > 0.002 ? _fraction : 0;
    CGFloat gap = (RING_GAP + RING_STROKE) / (2 * (CGFloat)M_PI * RING_RADIUS);
    /* the slide is as long as a tick of the timer, and none while a card is off screen or reduced motion is on */
    NSTimeInterval follow = self.window && !ExteriaReduceMotionEnabled() ? 0.25 : 0;
    ExteriaRingSetStroke(_ringArc, @"strokeEnd", played / 2, follow);
    _ringArc.hidden = played <= 0;
    CGFloat restStart = played > 0 ? played + gap : 0, restEnd = played > 0 ? 1 - gap : 1;
    ExteriaRingSetStroke(_ringTrack, @"strokeStart", restStart / 2, follow);
    ExteriaRingSetStroke(_ringTrack, @"strokeEnd", restEnd / 2, follow);
    _ringTrack.hidden = restEnd <= restStart;
    [self updateWave];
}

/* the played arc waves while the sound runs and lies flat when it is paused, as the wavy indicator of Material 3 does */
- (void)updateRingShape {
    BOOL wavy = _waving;
    if (_ringArc.path && wavy == _ringWavy) return;
    CGFloat side = _ring.bounds.size.width;
    CGPathRef path = ExteriaRingPath(CGPointMake(side / 2, side / 2), wavy);
    CGPathRef shown = _ringArc.path ? CGPathRetain(_ringArc.path) : NULL;
    _ringArc.path = path;
    /* the wave rises and settles over a moment, as the Material 3 indicator does, and does not pop when the sound starts or pauses; both paths have the same points */
    if (shown && self.window && !ExteriaReduceMotionEnabled()) {
        CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
        morph.fromValue = (id)shown;
        morph.toValue = (id)path;
        morph.duration = 0.3;
        morph.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_ringArc addAnimation:morph forKey:@"shape"];
    }
    if (shown) CGPathRelease(shown);
    CGPathRelease(path);
    _ringWavy = wavy;
}

/* the wave travels round the ring with no work per frame: the ring turns back by one wave while the stroke range runs forward by one, so the arc stands still and only
   the wave moves; the motion stops when the sound is paused or reduced motion is on */
- (void)updateWave {
    BOOL run = _ring && _waving && self.window && !ExteriaReduceMotionEnabled();
    BOOL running = [_ringSpin animationForKey:@"wave"] != nil;
    if (run && !running) {
        CFTimeInterval begin = [_ringSpin convertTime:CACurrentMediaTime() fromLayer:nil];
        CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        turn.fromValue = [NSNumber numberWithFloat:0];
        turn.toValue = [NSNumber numberWithFloat:(float)(-2 * M_PI / RING_WAVES)];
        NSMutableArray *animations = [NSMutableArray arrayWithObject:turn];
        for (NSString *keyPath in [NSArray arrayWithObjects:@"strokeStart", @"strokeEnd", nil]) {
            CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:keyPath];
            slide.fromValue = [NSNumber numberWithFloat:0];
            slide.toValue = [NSNumber numberWithFloat:(float)(0.5 / RING_WAVES)];
            slide.additive = YES;
            [animations addObject:slide];
        }
        for (CABasicAnimation *animation in animations) {
            animation.duration = RING_PERIOD;
            animation.repeatCount = HUGE_VALF;
            animation.beginTime = begin;
            animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        }
        [_ringSpin addAnimation:turn forKey:@"wave"];
        [_ringArc addAnimation:[animations objectAtIndex:1] forKey:@"waveStart"];
        [_ringArc addAnimation:[animations objectAtIndex:2] forKey:@"waveEnd"];
    } else if (!run && running) {
        [_ringSpin removeAnimationForKey:@"wave"];
        [_ringArc removeAnimationForKey:@"waveStart"];
        [_ringArc removeAnimationForKey:@"waveEnd"];
    }
}

/* the timer lives only while the card is on a screen and has a sound to follow, since it holds the card; a card taken off the screen lets it go */
- (void)updateTimer {
    BOOL want = !ExteriaThemeIsClassic() && _showing && self.window != nil;
    if (want && !_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    } else if (!want && _timer) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    [self updateProgress];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateTimer];
    if (self.window) [self refresh];
}

- (void)previousTapped {
    if ([ExteriaRoundPlayback sharedPlayback].active) [[ExteriaRoundPlayback sharedPlayback] step:-1];
    else [[ExteriaMusicPlayer sharedPlayer] previous];
}
- (void)toggleTapped {
    if ([ExteriaRoundPlayback sharedPlayback].active) [[ExteriaRoundPlayback sharedPlayback] togglePause];
    else [[ExteriaMusicPlayer sharedPlayer] togglePause];
}
- (void)nextTapped {
    if ([ExteriaRoundPlayback sharedPlayback].active) [[ExteriaRoundPlayback sharedPlayback] step:1];
    else [[ExteriaMusicPlayer sharedPlayer] next];
}
- (void)closeTapped {
    if (_closeHandler) { _closeHandler(); return; }
    if ([ExteriaRoundPlayback sharedPlayback].active) [[ExteriaRoundPlayback sharedPlayback] stop];
    else [[ExteriaMusicPlayer sharedPlayer] stop];
}
/* the sheet of the player has nothing for a video message, which has its own circle */
- (void)openPlayer {
    if (_openHandler) { _openHandler(); return; }
    if (![ExteriaRoundPlayback sharedPlayback].active) [ExteriaMusicSheet present];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _backdrop.frame = self.bounds;
    if (!ExteriaThemeIsClassic()) {
        [self layoutCard];
        return;
    }
    _line.frame = CGRectMake(0, height - 1.0 / ExteriaScreenScale(), width, 1.0 / ExteriaScreenScale());
    CGFloat x = width - 4 - BUTTON_WIDTH;
    _close.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    x -= BUTTON_WIDTH;
    _next.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    x -= BUTTON_WIDTH;
    _toggle.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    x -= BUTTON_WIDTH;
    _previous.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    _title.frame = CGRectMake(16, (STRIP_HEIGHT - 20) / 2, MAX(0, x - 24), 20);
}

/* the card keeps its own height while the owner animates the strip open or shut, and the strip's clipping hides the rest, so the content does not squeeze */
- (void)layoutCard {
    CGFloat width = self.bounds.size.width;
    _card.frame = CGRectMake(CARD_SIDE, _pill ? PILL_GAP : 0, MAX(0, width - 2 * CARD_SIDE), CARD_HEIGHT);
    CAShapeLayer *shape = (CAShapeLayer *)_card.layer.mask;
    if (![shape isKindOfClass:[CAShapeLayer class]]) {
        shape = [CAShapeLayer layer];
        _card.layer.mask = shape;
    }
    shape.frame = _card.bounds;
    shape.path = [UIBezierPath bezierPathWithRoundedRect:_card.bounds byRoundingCorners:UIRectCornerAllCorners
                                             cornerRadii:CGSizeMake(_pill ? CARD_HEIGHT / 2 : CARD_RADIUS, _pill ? CARD_HEIGHT / 2 : CARD_RADIUS)].CGPath;
    CGFloat cardWidth = _card.bounds.size.width;
    BOOL narrow = cardWidth < CARD_NARROW;
    CGFloat key = narrow ? KEY_SIDE_NARROW : KEY_SIDE, lead = narrow ? LEAD_SIDE_NARROW : LEAD_SIDE;
    _previous.hidden = NO;
    CGFloat mid = CARD_HEIGHT / 2;
    CGFloat x = cardWidth - 4;
    x -= key;
    _close.frame = CGRectMake(x, mid - key / 2, key, key);
    x -= key;
    _next.frame = CGRectMake(x, mid - key / 2, key, key);
    x -= PLAY_SIDE;
    _toggle.frame = CGRectMake(x, mid - PLAY_SIDE / 2, PLAY_SIDE, PLAY_SIDE);
    x -= key;
    _previous.frame = CGRectMake(x, mid - key / 2, key, key);
    _lead.frame = CGRectMake(8, mid - lead / 2, lead, lead);
    _leadCover.frame = _lead.bounds;
    _leadGlyph.frame = _lead.bounds;
    CGFloat textX = 8 + lead + (narrow ? 10 : 12);
    CGFloat textWidth = MAX(0, x - 8 - textX);
    BOOL hasLine = _subtitle.text.length > 0;
    _title.frame = CGRectMake(textX, hasLine ? 12 : mid - 10, textWidth, 20);
    _subtitle.frame = CGRectMake(textX, 31, textWidth, 16);
    _subtitle.hidden = !hasLine;
    [self layoutProgress];
}

@end
