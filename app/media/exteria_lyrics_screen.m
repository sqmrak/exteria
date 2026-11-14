#import "exteria_lyrics_screen.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_lyrics_view.h"
#import "exteria_mini_player.h"
#import "exteria_music_player.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define PANEL_GAP 8.0
#define PANEL_RADIUS 28.0
#define PANEL_RADIUS_SKEUOMORPHIC 8.0
#define PANEL_MAX_WIDTH 560.0
/* the modern sheet is the card of the browser: it starts 28 points under the safe top, and goes 32 points past the bottom edge so a pull down does not show its end */
#define SHEET_TOP 28.0
#define SHEET_OVERHANG 32.0
#define HANDLE_WIDTH 36.0
#define HANDLE_HEIGHT 4.0
#define HANDLE_TOP 6.0
#define PLAYER_TOP 14.0
#define LYRICS_GAP 8.0
#define COVER_FADE 0.6

/* the ground of the skeuomorphic screen: the hue of the most saturated cell of the cover, bright at the top and nearly black at the bottom; a cover without colour, or none, gives plain
   greys. a whole-cover average would lose the accent of the picture, so twelve by twelve cells are looked at one by one */
static void ExteriaLyricsGround(UIImage *cover, UIColor **top, UIColor **bottom) {
    *top = [UIColor colorWithWhite:0.16f alpha:1];
    *bottom = [UIColor colorWithWhite:0.07f alpha:1];
    CGImageRef source = cover.CGImage;
    if (!source) return;
    const int grid = 12;
    unsigned char pixels[12 * 12 * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, grid, grid, 8, grid * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return;
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextDrawImage(context, CGRectMake(0, 0, grid, grid), source);
    CGContextRelease(context);
    CGFloat bestHue = 0, bestSaturation = 0;
    BOOL found = NO;
    for (int i = 0; i < grid * grid; ++i) {
        unsigned char *p = pixels + i * 4;
        UIColor *sample = [UIColor colorWithRed:p[0] / 255.0f green:p[1] / 255.0f blue:p[2] / 255.0f alpha:1];
        CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 1;
        if (![sample getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) continue;
        /* near black and near white cells (a letterbox, a blown highlight) carry no colour */
        if (brightness < 0.12f || brightness > 0.92f) continue;
        if (!found || saturation > bestSaturation) { bestHue = hue; bestSaturation = saturation; found = YES; }
    }
    if (!found) return;
    CGFloat saturation = MIN(0.75f, MAX(0.35f, bestSaturation));
    *top = [UIColor colorWithHue:bestHue saturation:saturation brightness:0.46f alpha:1];
    *bottom = [UIColor colorWithHue:bestHue saturation:saturation brightness:0.16f alpha:1];
}

/* the average color of the cover, which is the ground of the modern screen; one pixel drawn from the whole picture is its average. no cover, or a clear one, gives the accent */
static UIColor *ExteriaLyricsCoverTint(UIImage *cover) {
    CGImageRef image = cover.CGImage;
    if (!image) return ExteriaColorAccent();
    unsigned char pixel[4] = {0, 0, 0, 0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return ExteriaColorAccent();
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image);
    CGContextRelease(context);
    if (!pixel[3]) return ExteriaColorAccent();
    return [UIColor colorWithRed:pixel[0] / 255.0 green:pixel[1] / 255.0 blue:pixel[2] / 255.0 alpha:1];
}

/* how far the cover color goes into the screen color at the top and at the bottom of the panel; the top is the share the player card wears, so the card reads as part of the ground */
static CGFloat ExteriaLyricsTintShare(BOOL top) {
    if (ExteriaThemeIsDark()) return top ? 0.5 : 0.18;
    return top ? 0.4 : 0.14;
}

@interface ExteriaLyricsScreen () {
    UIView *_dim;
    UIView *_panel;
    UIView *_handle;
    CAGradientLayer *_ground;
    ExteriaMiniPlayer *_player;
    ExteriaLyricsView *_lyricsView;
    ExteriaLyricsRequest *_request;
    ExteriaMedia *_track;
    UIImage *_cover;
    ExteriaWeakReference *_weak;
    BOOL _closing;
    BOOL _grounded;
}
@end

@implementation ExteriaLyricsScreen

+ (void)present {
    UIView *host = ExteriaOverlayHost();
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if (!host || !player.track) return;
    for (UIView *view in host.subviews) if ([view isKindOfClass:self]) return;
    ExteriaLyricsScreen *screen = [[[self alloc] initWithFrame:host.bounds] autorelease];
    [host addSubview:screen];
    [screen followTrack:player.track];
    [screen enter];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BOOL skeuomorphic = ExteriaThemeIsClassic();
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim = [[UIView alloc] initWithFrame:self.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:_dim];
    _panel = [[UIView alloc] init];
    _panel.clipsToBounds = YES;
    _panel.layer.cornerRadius = skeuomorphic ? PANEL_RADIUS_SKEUOMORPHIC : PANEL_RADIUS;
    if (skeuomorphic) {
        _panel.backgroundColor = [UIColor blackColor];
        _ground = [[CAGradientLayer layer] retain];
        [_panel.layer insertSublayer:_ground atIndex:0];
    } else {
        _panel.backgroundColor = ExteriaColorScreen();
        _ground = [[CAGradientLayer layer] retain];
        [_panel.layer insertSublayer:_ground atIndex:0];
        _handle = [[UIView alloc] init];
        _handle.backgroundColor = [ExteriaColorSecondary() colorWithAlphaComponent:0.4];
        _handle.layer.cornerRadius = HANDLE_HEIGHT / 2;
    }
    [self addSubview:_panel];
    if (_handle) {
        [_panel addSubview:_handle];
        ExteriaAddDismissPan(_panel, self, @selector(dismiss));
    }
    _lyricsView = [[ExteriaLyricsView alloc] init];
    _lyricsView.skeuomorphic = skeuomorphic;
    _lyricsView.onSeek = ^(NSTimeInterval seconds) {
        ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
        if (player.duration > 0) [player seekToFraction:(float)MIN(1.0, seconds / player.duration)];
    };
    [_panel addSubview:_lyricsView];
    /* the strip of the main screen: its tap on the name goes back to the player, and its last key closes the lyrics and leaves the music playing */
    _player = [[ExteriaMiniPlayer alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    ExteriaWeakReference *weak = _weak;
    _player.openHandler = ^{ [(ExteriaLyricsScreen *)weak.target dismiss]; };
    _player.closeHandler = ^{ [(ExteriaLyricsScreen *)weak.target dismiss]; };
    [_panel addSubview:_player];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [self applyCover:[ExteriaMusicPlayer sharedPlayer].cover];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_request cancel];
    [_weak clear];
    [_weak release];
    _player.openHandler = nil;
    _player.closeHandler = nil;
    [_request release]; [_dim release]; [_panel release]; [_handle release]; [_ground release]; [_player release]; [_lyricsView release]; [_track release]; [_cover release];
    [super dealloc];
}

- (void)applyCover:(UIImage *)cover {
    [_cover release];
    _cover = [cover retain];
    UIColor *top, *bottom, *tint = nil;
    if (ExteriaThemeIsClassic()) {
        ExteriaLyricsGround(cover, &top, &bottom);
    } else {
        tint = ExteriaLyricsCoverTint(cover);
        top = ExteriaMixedColor(ExteriaColorScreen(), tint, ExteriaLyricsTintShare(YES));
        bottom = ExteriaMixedColor(ExteriaColorScreen(), tint, ExteriaLyricsTintShare(NO));
    }
    NSArray *colors = [NSArray arrayWithObjects:(id)top.CGColor, (id)bottom.CGColor, nil];
    /* the first cover is laid down at once, the next songs fade the ground and the card to their colors together */
    BOOL fade = _grounded && self.window != nil;
    if (fade) {
        CABasicAnimation *change = [CABasicAnimation animationWithKeyPath:@"colors"];
        change.fromValue = _ground.presentationLayer ? ((CAGradientLayer *)_ground.presentationLayer).colors : _ground.colors;
        change.duration = COVER_FADE;
        change.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_ground addAnimation:change forKey:@"cover.ground"];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ground.colors = colors;
    [CATransaction commit];
    if (!ExteriaThemeIsClassic()) [_player setTone:tint surface:top animated:fade];
    _grounded = YES;
}

/* the lyrics of a song are looked up while the old ones give way to a word */
- (void)followTrack:(ExteriaMedia *)track {
    [_track release];
    _track = [track retain];
    [_request cancel]; [_request release]; _request = nil;
    if (_track.kind == EXTERIA_PREVIEW_VOICE) {
        [_lyricsView showStatus:NSLocalizedString(@"music.lyrics.none", nil)];
        return;
    }
    [_lyricsView showStatus:NSLocalizedString(@"music.lyrics.loading", nil)];
    ExteriaLyricsView *view = _lyricsView;
    _request = [[ExteriaLyricsRequest fetchForPerformer:ExteriaTrackPerformer(_track) title:ExteriaTrackTitle(_track)
                                             completion:^(ExteriaLyrics *lyrics, BOOL definitive) {
        if (lyrics) [view showLyrics:lyrics];
        else [view showStatus:NSLocalizedString(definitive ? @"music.lyrics.none" : @"music.lyrics.failed", nil)];
    }] retain];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if (!player.track) { [self dismiss]; return; }
    if (player.cover != _cover) [self applyCover:player.cover];
    if (player.track != _track) [self followTrack:player.track];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL sheet = _handle != nil;
    CGFloat width = MIN(self.bounds.size.width, PANEL_MAX_WIDTH);
    UIEdgeInsets safe = ExteriaSafeInsets(self);
    CGFloat top = safe.top + (sheet ? SHEET_TOP : PANEL_GAP);
    CGFloat visible = MAX(0, self.bounds.size.height - top);
    CGFloat height = visible + (sheet ? SHEET_OVERHANG : 0);
    /* the panel is moved by its transform while it comes and goes, and a frame set under a transform resizes it */
    ExteriaPlaceView(_panel, CGRectMake((self.bounds.size.width - width) / 2, top, width, height));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ground.frame = _panel.bounds;
    [CATransaction commit];
    _handle.frame = CGRectMake(floor((width - HANDLE_WIDTH) / 2), HANDLE_TOP, HANDLE_WIDTH, HANDLE_HEIGHT);
    CGFloat playerTop = sheet ? PLAYER_TOP : 0;
    CGFloat strip = [ExteriaMiniPlayer height];
    _player.frame = CGRectMake(0, playerTop, width, strip);
    /* the lines start below a gap under the card, or the first of them touches it */
    CGFloat lyricsTop = playerTop + strip + (ExteriaThemeIsClassic() ? 0 : LYRICS_GAP);
    _lyricsView.frame = CGRectMake(0, lyricsTop, width, MAX(0, visible - lyricsTop - safe.bottom));
}

/* how far the panel goes to stand just below the screen, from where it rests */
- (CGFloat)panelTravel {
    return self.bounds.size.height - (_panel.center.y - _panel.bounds.size.height / 2);
}

- (void)enter {
    [self layoutIfNeeded];
    _panel.transform = CGAffineTransformMakeTranslation(0, [self panelTravel]);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0.5, ExteriaPopupCurve(YES), nil);
    ExteriaAnimateView(_panel, CGAffineTransformIdentity, 1, ExteriaPopupCurve(YES), nil);
}

- (void)dismiss {
    if (_closing) return;
    _closing = YES;
    [_request cancel];
    self.userInteractionEnabled = NO;
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, ExteriaPopupCurve(NO), nil);
    ExteriaAnimateView(_panel, CGAffineTransformMakeTranslation(0, [self panelTravel]), 1, ExteriaPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    });
}

@end
