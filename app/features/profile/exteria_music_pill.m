#import "exteria_music_pill.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_music_player.h"
#import "exteria_music_style.h"
#import "exteria_shiro_style.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define PILL_HEIGHT 36.0
#define SLOT 40.0
#define TOGGLE_SIDE 30.0

@interface ExteriaMusicPill () {
    ExteriaMedia *_savedTrack;
    void (^_contentHandler)(void);
    UIImageView *_note;
    ExteriaMusicKey *_toggle;
    ExteriaEmojiLabel *_line;
    UIImageView *_arrow;
    UIButton *_close;
    BOOL _hadContent;
}
@end

@implementation ExteriaMusicPill

@synthesize savedTrack = _savedTrack;
@synthesize contentHandler = _contentHandler;

+ (CGFloat)height { return PILL_HEIGHT; }

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaMusicTonalColor();
    self.layer.cornerRadius = PILL_HEIGHT / 2;
    _note = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMusic, 16, ExteriaColorAccent())];
    _note.contentMode = UIViewContentModeCenter;
    [self addSubview:_note];
    _toggle = [[ExteriaMusicKey buttonWithType:UIButtonTypeCustom] retain];
    _toggle.backgroundColor = ExteriaColorAccent();
    [_toggle setRestRadius:TOGGLE_SIDE / 2 animated:NO];
    [_toggle addTarget:self action:@selector(togglePlayback) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_toggle];
    _line = [[ExteriaEmojiLabel alloc] init];
    _line.textColor = ExteriaColorTitle();
    _line.font = ExteriaShiroFontBody(14, YES);
    _line.userInteractionEnabled = NO;
    [self addSubview:_line];
    _arrow = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolChevronRight, 12, ExteriaColorSecondary())];
    _arrow.contentMode = UIViewContentModeCenter;
    [self addSubview:_arrow];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:ExteriaSymbolImage(ExteriaSymbolClose, 14, ExteriaColorSecondary()) forState:UIControlStateNormal];
    [_close addTarget:self action:@selector(stopPlayback) forControlEvents:UIControlEventTouchUpInside];
    _close.accessibilityLabel = NSLocalizedString(@"music.stop", nil);
    [self addSubview:_close];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_savedTrack release];
    [_contentHandler release];
    [_note release];
    [_toggle release];
    [_line release];
    [_arrow release];
    [_close release];
    [super dealloc];
}

- (BOOL)playerActive {
    return [ExteriaMusicPlayer sharedPlayer].state != ExteriaMusicStateIdle;
}

- (BOOL)hasContent {
    return _savedTrack != nil || [self playerActive];
}

- (void)setSavedTrack:(ExteriaMedia *)track {
    if (track == _savedTrack) return;
    [_savedTrack release];
    _savedTrack = [track retain];
    [self refresh];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

/* shows the song that plays when one does, the saved one otherwise */
- (void)refresh {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    BOOL active = [self playerActive];
    ExteriaMedia *shown = active ? player.track : _savedTrack;
    BOOL content = shown != nil;
    self.hidden = !content;
    _line.text = shown ? ExteriaTrackLine(shown) : @"";
    _note.hidden = active;
    _arrow.hidden = active;
    _toggle.hidden = !active;
    _close.hidden = !active;
    if (active) {
        BOOL playing = player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStateLoading;
        [_toggle setImage:ExteriaSymbolImage(playing ? ExteriaSymbolPause : ExteriaSymbolPlay, 14, [UIColor whiteColor]) forState:UIControlStateNormal];
        [_toggle setRestRadius:TOGGLE_SIDE / 2 animated:self.window != nil];
        _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    }
    self.accessibilityLabel = _line.text;
    [self setNeedsLayout];
    if (content != _hadContent) {
        _hadContent = content;
        if (_contentHandler) _contentHandler();
    }
}

- (void)togglePlayback {
    [[ExteriaMusicPlayer sharedPlayer] togglePause];
}

- (void)stopPlayback {
    [[ExteriaMusicPlayer sharedPlayer] stop];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    BOOL active = [self playerActive];
    _note.frame = CGRectMake(10, 0, 24, PILL_HEIGHT);
    _toggle.frame = CGRectMake(3, (PILL_HEIGHT - TOGGLE_SIDE) / 2, TOGGLE_SIDE, TOGGLE_SIDE);
    _close.frame = CGRectMake(width - SLOT - 2, 0, SLOT, PILL_HEIGHT);
    _arrow.frame = CGRectMake(width - 28, 0, 18, PILL_HEIGHT);
    CGFloat left = active ? TOGGLE_SIDE + 10 : 38;
    CGFloat right = active ? SLOT + 2 : 30;
    _line.frame = CGRectMake(left, 0, MAX(0, width - left - right), PILL_HEIGHT);
}

@end
