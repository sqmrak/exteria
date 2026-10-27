#import "exteria_music_card.h"

#import <QuartzCore/QuartzCore.h>

#include <math.h>

#import "exteria_emoji_label.h"
#import "exteria_music_player.h"
#import "exteria_music_style.h"
#import "exteria_platform.h"
#import "exteria_shiro_style.h"
#import "exteria_symbol.h"
#import "exteria_wave_progress.h"
#import "exteria_theme.h"

#define CARD_HEIGHT 184.0
#define CARD_PAD 14.0
#define COVER_SIDE 56.0
#define KEY_HEIGHT 56.0
#define KEY_GAP 6.0
#define SHAPE_POINTS 144

static NSString *const ExteriaCardShapeKey = @"card.shape";
static NSString *const ExteriaCardRevealKey = @"card.reveal";

static NSString *ExteriaCardClock(NSTimeInterval seconds) {
    NSInteger total = seconds > 0 ? (NSInteger)seconds : 0;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

#pragma mark cover shapes

/* the two outlines of the cover have the same number of points, because core animation only interpolates paths
   that are built the same way */
static UIBezierPath *ExteriaCardShape(CGFloat side, BOOL cookie) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat half = side / 2;
    const CGFloat depth = 0.07f;
    const int lobes = 9;
    for (int i = 0; i < SHAPE_POINTS; ++i) {
        CGFloat angle = (CGFloat)(2 * M_PI * i / SHAPE_POINTS);
        CGFloat s = sin(angle), c = cos(angle);
        CGPoint point;
        if (cookie) {
            CGFloat r = half / (1 + depth) * (1 + depth * cos(lobes * angle));
            point = CGPointMake(half + r * s, half - r * c);
        } else {
            point = CGPointMake(half + half * (s < 0 ? -1 : 1) * sqrt(fabs(s)), half - half * (c < 0 ? -1 : 1) * sqrt(fabs(c)));
        }
        if (i == 0) [path moveToPoint:point];
        else [path addLineToPoint:point];
    }
    [path closePath];
    return path;
}


#pragma mark card

@interface ExteriaMusicCard () {
    UIView *_coverBox;
    UIImageView *_coverImage;
    UIImageView *_coverNote;
    CAShapeLayer *_coverMask;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_performer;
    ExteriaMusicKey *_speed;
    ExteriaWaveProgress *_progress;
    UILabel *_elapsed;
    UILabel *_remaining;
    ExteriaMusicKey *_previous;
    ExteriaMusicKey *_toggle;
    ExteriaMusicKey *_next;
    UIActivityIndicatorView *_spinner;
    BOOL _scrubbing;
    BOOL _cookie;
}
@end

@implementation ExteriaMusicCard

+ (CGFloat)height { return CARD_HEIGHT; }

static UILabel *ExteriaCardLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

static ExteriaMusicKey *ExteriaCardKey(UIColor *fill, CGFloat radius, id target, SEL action) {
    ExteriaMusicKey *key = [[ExteriaMusicKey alloc] initWithFrame:CGRectZero];
    key.backgroundColor = fill;
    [key setRestRadius:radius animated:NO];
    [key addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return key;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    UIColor *tonal = ExteriaMusicTonalColor();
    UIColor *accent = ExteriaColorAccent();
    self.backgroundColor = ExteriaMusicSurfaceColor();
    self.layer.cornerRadius = 28;

    _coverBox = [[UIView alloc] init];
    _coverBox.backgroundColor = tonal;
    _coverMask = [[CAShapeLayer alloc] init];
    _coverMask.path = ExteriaCardShape(COVER_SIDE, NO).CGPath;
    _coverMask.frame = CGRectMake(0, 0, COVER_SIDE, COVER_SIDE);
    _coverBox.layer.mask = _coverMask;
    [self addSubview:_coverBox];
    _coverImage = [[UIImageView alloc] init];
    _coverImage.contentMode = UIViewContentModeScaleAspectFill;
    _coverImage.clipsToBounds = YES;
    [_coverBox addSubview:_coverImage];
    _coverNote = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMusic, 24, accent)];
    _coverNote.contentMode = UIViewContentModeCenter;
    [_coverBox addSubview:_coverNote];

    _title = [[ExteriaEmojiLabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.font = ExteriaShiroFontBody(18, YES);
    _title.textColor = ExteriaColorTitle();
    [self addSubview:_title];
    _performer = [[ExteriaEmojiLabel alloc] init];
    _performer.backgroundColor = [UIColor clearColor];
    _performer.font = ExteriaShiroFontBody(14, NO);
    _performer.textColor = ExteriaColorSecondary();
    [self addSubview:_performer];

    _speed = ExteriaCardKey(tonal, 14, self, @selector(speedTapped));
    _speed.titleLabel.font = ExteriaShiroFontBody(13, YES);
    [_speed setTitleColor:accent forState:UIControlStateNormal];
    _speed.accessibilityLabel = NSLocalizedString(@"music.speed", nil);
    [self addSubview:_speed];

    _progress = [[ExteriaWaveProgress alloc] init];
    _progress.accessibilityLabel = NSLocalizedString(@"media.seek", nil);
    [_progress addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [_progress addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
    [_progress addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:_progress];
    _elapsed = ExteriaCardLabel(ExteriaColorSecondary(), ExteriaShiroFontBody(12, NO), ExteriaTextAlignmentLeft);
    [self addSubview:_elapsed];
    _remaining = ExteriaCardLabel(ExteriaColorSecondary(), ExteriaShiroFontBody(12, NO), ExteriaTextAlignmentRight);
    [self addSubview:_remaining];

    _previous = ExteriaCardKey(tonal, KEY_HEIGHT / 2, self, @selector(previousTapped));
    [_previous setImage:ExteriaSymbolImage(ExteriaSymbolPrevious, 22, accent) forState:UIControlStateNormal];
    _previous.accessibilityLabel = NSLocalizedString(@"music.previous", nil);
    [self addSubview:_previous];
    _toggle = ExteriaCardKey(accent, KEY_HEIGHT / 2, self, @selector(toggleTapped));
    [self addSubview:_toggle];
    _next = ExteriaCardKey(tonal, KEY_HEIGHT / 2, self, @selector(nextTapped));
    [_next setImage:ExteriaSymbolImage(ExteriaSymbolNext, 22, accent) forState:UIControlStateNormal];
    _next.accessibilityLabel = NSLocalizedString(@"music.next", nil);
    [self addSubview:_next];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    _spinner.userInteractionEnabled = NO;
    [_toggle addSubview:_spinner];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(playerTicked:) name:ExteriaMusicPlayerDidTickNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_coverBox release];
    [_coverImage release];
    [_coverNote release];
    [_coverMask release];
    [_title release];
    [_performer release];
    [_speed release];
    [_progress release];
    [_elapsed release];
    [_remaining release];
    [_previous release];
    [_toggle release];
    [_next release];
    [_spinner release];
    [super dealloc];
}

#pragma mark state

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (void)playerTicked:(NSNotification *)note {
    (void)note;
    [self refreshProgress];
}

/* the cover goes from the rounded square to the cookie when the song starts and back when it stops */
- (void)setCookie:(BOOL)cookie {
    if (cookie == _cookie) return;
    _cookie = cookie;
    CAShapeLayer *shown = (CAShapeLayer *)[_coverMask presentationLayer];
    CGPathRef from = shown && shown.path ? shown.path : _coverMask.path;
    CGPathRetain(from);
    [_coverMask removeAnimationForKey:ExteriaCardShapeKey];
    _coverMask.path = ExteriaCardShape(COVER_SIDE, cookie).CGPath;
    if (self.window && !ExteriaReduceMotionEnabled() && from) {
        CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
        morph.fromValue = (id)from;
        morph.toValue = (id)_coverMask.path;
        morph.duration = 0.5;
        morph.timingFunction = ExteriaMusicSpring();
        [_coverMask addAnimation:morph forKey:ExteriaCardShapeKey];
    }
    CGPathRelease(from);
}

- (void)refresh {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    ExteriaMusicState state = player.state;
    if (state == ExteriaMusicStateIdle) return;
    BOOL playing = state == ExteriaMusicStatePlaying;
    BOOL busy = state == ExteriaMusicStateLoading;
    BOOL failed = state == ExteriaMusicStateFailed;

    _title.text = ExteriaTrackTitle(player.track);
    _performer.text = failed ? NSLocalizedString(@"music.failed", nil) : ExteriaTrackPerformer(player.track);
    _performer.textColor = failed ? ExteriaColorBadgeRed() : ExteriaColorSecondary();
    UIImage *cover = player.cover;
    _coverImage.image = cover;
    _coverImage.hidden = cover == nil;
    _coverNote.hidden = cover != nil;
    [self setCookie:playing];

    BOOL running = playing || busy;
    if (busy) [_spinner startAnimating];
    else [_spinner stopAnimating];
    [_toggle setImage:busy ? nil : ExteriaSymbolImage(running ? ExteriaSymbolPause : ExteriaSymbolPlay, 26, [UIColor whiteColor]) forState:UIControlStateNormal];
    [_toggle setRestRadius:running ? 18 : KEY_HEIGHT / 2 animated:self.window != nil];
    _toggle.accessibilityLabel = NSLocalizedString(running ? @"music.pause" : @"music.play", nil);
    NSUInteger at = [player.queue indexOfObject:player.track];
    _previous.enabled = player.queue.count > 1 || player.position > 3;
    _next.enabled = at != NSNotFound && at + 1 < player.queue.count;
    _previous.alpha = _previous.enabled ? 1 : 0.4f;
    _next.alpha = _next.enabled ? 1 : 0.4f;
    [_speed setTitle:ExteriaSpeedText(player.speed) forState:UIControlStateNormal];
    _progress.waving = playing;
    _progress.enabled = playing || state == ExteriaMusicStatePaused;
    [self refreshProgress];
}

- (void)refreshProgress {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    NSTimeInterval length = player.duration;
    if (!_scrubbing) {
        float fraction = length > 0 ? (float)(player.position / length) : 0;
        /* only a small step forward glides; a new song or a seek jumps */
        BOOL forward = fraction >= _progress.value && fraction - _progress.value < 0.1f;
        [_progress setValue:fraction gliding:forward];
    }
    NSTimeInterval shown = _scrubbing ? length * _progress.value : player.position;
    _elapsed.text = ExteriaCardClock(shown);
    _remaining.text = length > 0 ? [@"-" stringByAppendingString:ExteriaCardClock(length - shown)] : @"";
}

#pragma mark actions

- (void)scrubBegan { _scrubbing = YES; }
- (void)scrubMoved { [self refreshProgress]; }

- (void)scrubEnded {
    _scrubbing = NO;
    [[ExteriaMusicPlayer sharedPlayer] seekToFraction:_progress.value];
}

- (void)previousTapped { [[ExteriaMusicPlayer sharedPlayer] previous]; }
- (void)toggleTapped { [[ExteriaMusicPlayer sharedPlayer] togglePause]; }
- (void)nextTapped { [[ExteriaMusicPlayer sharedPlayer] next]; }
- (void)speedTapped { [[ExteriaMusicPlayer sharedPlayer] cycleSpeed]; }

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _coverBox.frame = CGRectMake(CARD_PAD, CARD_PAD, COVER_SIDE, COVER_SIDE);
    _coverImage.frame = _coverBox.bounds;
    _coverNote.frame = _coverBox.bounds;
    CGFloat chipWidth = 48;
    _speed.frame = CGRectMake(width - CARD_PAD - chipWidth, CARD_PAD + 4, chipWidth, 28);
    CGFloat textX = CARD_PAD + COVER_SIDE + 12;
    CGFloat textWidth = MAX(0, width - textX - CARD_PAD - chipWidth - 8);
    BOOL hasPerformer = _performer.text.length > 0;
    _title.frame = CGRectMake(textX, hasPerformer ? CARD_PAD + 6 : CARD_PAD + 16, textWidth, 24);
    _performer.frame = CGRectMake(textX, CARD_PAD + 32, textWidth, 20);
    _progress.frame = CGRectMake(CARD_PAD - ExteriaWaveProgressInset, 72, width - (CARD_PAD - ExteriaWaveProgressInset) * 2, ExteriaWaveProgressHeight);
    _elapsed.frame = CGRectMake(CARD_PAD, 98, 64, 16);
    _remaining.frame = CGRectMake(width - CARD_PAD - 64, 98, 64, 16);
    CGFloat sideKey = 72, middleKey = 96;
    CGFloat x = floor((width - sideKey * 2 - middleKey - KEY_GAP * 2) / 2);
    CGFloat y = CARD_HEIGHT - CARD_PAD + 2 - KEY_HEIGHT;
    _previous.frame = CGRectMake(x, y, sideKey, KEY_HEIGHT);
    _toggle.frame = CGRectMake(x + sideKey + KEY_GAP, y, middleKey, KEY_HEIGHT);
    _next.frame = CGRectMake(x + sideKey + KEY_GAP + middleKey + KEY_GAP, y, sideKey, KEY_HEIGHT);
    _spinner.center = CGPointMake(middleKey / 2, KEY_HEIGHT / 2);
}

#pragma mark reveal

- (void)reveal {
    if (self.window == nil || ExteriaReduceMotionEnabled()) return;
    CABasicAnimation *rise = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    rise.fromValue = [NSNumber numberWithFloat:(float)(CARD_HEIGHT * 0.7)];
    rise.toValue = [NSNumber numberWithFloat:0];
    rise.timingFunction = ExteriaMusicSpring();
    rise.duration = 0.55;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = [NSNumber numberWithFloat:0];
    fade.toValue = [NSNumber numberWithFloat:1];
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    fade.duration = 0.2;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = [NSArray arrayWithObjects:rise, fade, nil];
    group.duration = 0.55;
    [self.layer addAnimation:group forKey:ExteriaCardRevealKey];
}

@end
