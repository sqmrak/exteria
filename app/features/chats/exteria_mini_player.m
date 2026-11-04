#import "exteria_mini_player.h"

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

@interface ExteriaMiniPlayer () {
    ExteriaEmojiLabel *_title;
    UIButton *_previous;
    UIButton *_toggle;
    UIButton *_next;
    UIButton *_close;
    UIView *_line;
    UIImageView *_backdrop;
    BOOL _showing;
    BOOL _wearsBarColor;
    void (^_changeHandler)(void);
}
@end

@implementation ExteriaMiniPlayer

@synthesize showing = _showing;
@synthesize wearsBarColor = _wearsBarColor;
@synthesize changeHandler = _changeHandler;

+ (CGFloat)height { return STRIP_HEIGHT; }

static UIButton *ExteriaStripButton(ExteriaSymbol symbol, id target, SEL action, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:ExteriaSymbolImage(symbol, 20, ExteriaThemeIsClassic() ? [UIColor whiteColor] : ExteriaColorTitle()) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = NSLocalizedString(label, nil);
    return button;
}

- (void)setWearsBarColor:(BOOL)wears {
    _wearsBarColor = wears;
    if (!ExteriaThemeIsClassic()) self.backgroundColor = wears ? ExteriaColorBar() : ExteriaColorCard();
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BOOL classic = ExteriaThemeIsClassic();
    self.clipsToBounds = YES;
    if (classic) {
        _backdrop = [ExteriaClassicStripBackdrop() retain];
        [self addSubview:_backdrop];
    } else {
        self.backgroundColor = ExteriaColorCard();
    }
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = classic ? [UIFont boldSystemFontOfSize:14] : ExteriaFontSemibold(14);
    _title.textColor = classic ? [UIColor whiteColor] : ExteriaColorTitle();
    if (classic) {
        _title.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        _title.shadowOffset = CGSizeMake(0, -1);
    }
    _title.dropsUndrawable = YES;
    [self addSubview:_title];
    _title.userInteractionEnabled = YES;
    [_title addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPlayer)] autorelease]];
    _previous = [ExteriaStripButton(ExteriaSymbolPrevious, self, @selector(previousTapped), @"music.previous") retain];
    _toggle = [ExteriaStripButton(ExteriaSymbolPlay, self, @selector(toggleTapped), @"music.play") retain];
    _next = [ExteriaStripButton(ExteriaSymbolNext, self, @selector(nextTapped), @"music.next") retain];
    _close = [ExteriaStripButton(ExteriaSymbolClose, self, @selector(closeTapped), @"music.stop") retain];
    for (UIView *view in [NSArray arrayWithObjects:_previous, _toggle, _next, _close, nil]) [self addSubview:view];
    _line = [[UIView alloc] init];
    _line.backgroundColor = classic ? [UIColor colorWithWhite:0 alpha:0.55] : ExteriaColorHairline();
    [self addSubview:_line];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaRoundPlaybackDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
        _title.text = round.active ? NSLocalizedString(@"round.title", nil) : ExteriaTrackLine(player.track);
        [_toggle setImage:ExteriaSymbolImage(playing ? ExteriaSymbolPause : ExteriaSymbolPlay, 22, ExteriaThemeIsClassic() ? [UIColor whiteColor] : ExteriaColorTitle()) forState:UIControlStateNormal];
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
    [self setNeedsLayout];
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

@end
