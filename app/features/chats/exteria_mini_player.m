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
/* the modern strip is a tonal card that hangs from the bar above it: 8 points of room at the sides and 4 below, none above, so no gap shows between it and the pinned message
   or the header. the height the owners lay out is the card and the room below it */
#define CARD_HEIGHT 56.0
#define CARD_SIDE 8.0
#define CARD_GUTTER 4.0
#define CARD_RADIUS 16.0
#define LEAD_SIDE 40.0
#define LEAD_RADIUS 12.0
#define KEY_SIDE 36.0
#define PLAY_SIDE 40.0
#define PROGRESS_HEIGHT 3.0
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
    UIView *_track;
    UIView *_indicator;
    NSTimer *_timer;
    CGFloat _fraction;
    BOOL _showing;
    BOOL _wearsBarColor;
    void (^_changeHandler)(void);
}
@end

@implementation ExteriaMiniPlayer

@synthesize showing = _showing;
@synthesize wearsBarColor = _wearsBarColor;
@synthesize changeHandler = _changeHandler;

+ (CGFloat)height { return ExteriaThemeIsClassic() ? STRIP_HEIGHT : CARD_HEIGHT + CARD_GUTTER; }

/* the tonal colors of the card from the accent, the way a Material You scheme makes them from its key color: a container a little off the surface, a stronger one for the
   glyph tile, the accent itself for the play key and a dark or light ink for what stands on each */
static UIColor *ExteriaStripContainer(UIColor *surface) {
    return ExteriaMixedColor(surface, ExteriaColorAccent(), ExteriaThemeIsDark() ? 0.22 : 0.14);
}
static UIColor *ExteriaStripTile(void) {
    return ExteriaThemeIsDark() ? ExteriaMixedColor([UIColor colorWithWhite:0.12 alpha:1], ExteriaColorAccent(), 0.5) : ExteriaMixedColor([UIColor whiteColor], ExteriaColorAccent(), 0.3);
}
static UIColor *ExteriaStripOnTile(void) {
    return ExteriaThemeIsDark() ? ExteriaMixedColor(ExteriaColorAccent(), [UIColor whiteColor], 0.75) : ExteriaMixedColor(ExteriaColorAccent(), [UIColor blackColor], 0.55);
}
static UIColor *ExteriaStripOnPrimary(void) {
    return ExteriaThemeIsDark() ? ExteriaMixedColor(ExteriaColorAccent(), [UIColor blackColor], 0.78) : [UIColor whiteColor];
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

- (void)setWearsBarColor:(BOOL)wears {
    _wearsBarColor = wears;
    if (!ExteriaThemeIsClassic()) {
        UIColor *surface = wears ? ExteriaColorBar() : ExteriaColorCard();
        self.backgroundColor = surface;
        _card.backgroundColor = ExteriaStripContainer(surface);
    }
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
        self.backgroundColor = ExteriaColorCard();
    }
    if (!classic) {
        _card = [[UIView alloc] init];
        _card.backgroundColor = ExteriaStripContainer(ExteriaColorCard());
        [self addSubview:_card];
        _lead = [[UIView alloc] init];
        _lead.backgroundColor = ExteriaStripTile();
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
        _track = [[UIView alloc] init];
        _track.backgroundColor = ExteriaStripTile();
        _track.layer.cornerRadius = PROGRESS_HEIGHT / 2;
        [_card addSubview:_track];
        _indicator = [[UIView alloc] init];
        _indicator.backgroundColor = ExteriaColorAccent();
        _indicator.layer.cornerRadius = PROGRESS_HEIGHT / 2;
        [_track addSubview:_indicator];
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
    _previous = [ExteriaStripButton(ExteriaSymbolPrevious, self, @selector(previousTapped), @"music.previous") retain];
    _toggle = [ExteriaStripButton(ExteriaSymbolPlay, self, @selector(toggleTapped), @"music.play") retain];
    _next = [ExteriaStripButton(ExteriaSymbolNext, self, @selector(nextTapped), @"music.next") retain];
    _close = [ExteriaStripButton(ExteriaSymbolClose, self, @selector(closeTapped), @"music.stop") retain];
    for (UIView *view in [NSArray arrayWithObjects:_previous, _toggle, _next, _close, nil]) [classic ? (UIView *)self : _card addSubview:view];
    if (!classic) {
        /* the play key is the filled one: the accent with the light or dark ink of the scheme on it */
        [_toggle setBackgroundImage:ExteriaStripDisc(ExteriaColorAccent()) forState:UIControlStateNormal];
        [_toggle setBackgroundImage:ExteriaStripDisc(ExteriaMixedColor(ExteriaColorAccent(), ExteriaStripOnPrimary(), 0.14)) forState:UIControlStateHighlighted];
    }
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
    [_card release];
    [_lead release];
    [_leadGlyph release];
    [_leadCover release];
    [_subtitle release];
    [_track release];
    [_indicator release];
    [_title release];
    [_previous release];
    [_toggle release];
    [_next release];
    [_close release];
    [_line release];
    [_backdrop release];
    [_changeHandler release];
    [super dealloc];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (void)refresh {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    ExteriaRoundPlayback *round = [ExteriaRoundPlayback sharedPlayback];
    /* a video message that plays holds the output, so the strip is its and not the one of the song it paused */
    BOOL showing = round.active || (player.state != ExteriaMusicStateIdle && player.track != nil);
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
    _leadGlyph.image = ExteriaSymbolImage(round ? ExteriaSymbolMaterialVideocam : (voice ? ExteriaSymbolMaterialMic : ExteriaSymbolMaterialMusicNote), 24, ExteriaStripOnTile());
    UIImage *key = ExteriaSymbolImage(playing ? ExteriaSymbolMaterialPause : ExteriaSymbolMaterialPlay, 24, ExteriaStripOnPrimary());
    if (_toggle.currentImage != key) {
        BOOL animate = self.window != nil && _showing && !ExteriaReduceMotionEnabled() && _toggle.currentImage;
        if (animate) {
            [UIView transitionWithView:_toggle duration:0.15 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                            animations:^{ [_toggle setImage:key forState:UIControlStateNormal]; } completion:nil];
        } else {
            [_toggle setImage:key forState:UIControlStateNormal];
        }
    }
    [self updateProgress];
}

/* the line under the title and the thin bar along the foot of the card follow the sound; a song names its performer, and a voice or video message tells how far it is */
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

- (void)layoutProgress {
    _indicator.frame = CGRectMake(0, 0, _track.bounds.size.width * _fraction, PROGRESS_HEIGHT);
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
    if ([ExteriaRoundPlayback sharedPlayback].active) [[ExteriaRoundPlayback sharedPlayback] stop];
    else [[ExteriaMusicPlayer sharedPlayer] stop];
}
/* the sheet of the player has nothing for a video message, which has its own circle */
- (void)openPlayer {
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
    _card.frame = CGRectMake(CARD_SIDE, 0, MAX(0, width - 2 * CARD_SIDE), CARD_HEIGHT);
    /* only the lower corners are round, since the upper edge stands against the bar above */
    CAShapeLayer *shape = (CAShapeLayer *)_card.layer.mask;
    if (![shape isKindOfClass:[CAShapeLayer class]]) {
        shape = [CAShapeLayer layer];
        _card.layer.mask = shape;
    }
    shape.frame = _card.bounds;
    shape.path = [UIBezierPath bezierPathWithRoundedRect:_card.bounds byRoundingCorners:UIRectCornerBottomLeft | UIRectCornerBottomRight
                                             cornerRadii:CGSizeMake(CARD_RADIUS, CARD_RADIUS)].CGPath;
    CGFloat cardWidth = _card.bounds.size.width;
    BOOL narrow = cardWidth < CARD_NARROW;
    CGFloat key = narrow ? KEY_SIDE_NARROW : KEY_SIDE, lead = narrow ? LEAD_SIDE_NARROW : LEAD_SIDE;
    _previous.hidden = NO;
    CGFloat mid = CARD_HEIGHT / 2 - 1;
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
    _title.frame = CGRectMake(textX, hasLine ? 10 : mid - 10, textWidth, 20);
    _subtitle.frame = CGRectMake(textX, 29, textWidth, 16);
    _subtitle.hidden = !hasLine;
    _track.frame = CGRectMake(textX, CARD_HEIGHT - 6, MAX(0, cardWidth - textX - 16), PROGRESS_HEIGHT);
    [self layoutProgress];
}

@end
