#import "exteria_mini_player.h"

#import "exteria_emoji_label.h"
#import "exteria_music_player.h"
#import "exteria_music_sheet.h"
#import "exteria_platform.h"
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
    BOOL _showing;
    void (^_changeHandler)(void);
}
@end

@implementation ExteriaMiniPlayer

@synthesize showing = _showing;
@synthesize changeHandler = _changeHandler;

+ (CGFloat)height { return STRIP_HEIGHT; }

static UIButton *ExteriaStripButton(ExteriaSymbol symbol, id target, SEL action, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:ExteriaSymbolImage(symbol, 20, ExteriaColorTitle()) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = NSLocalizedString(label, nil);
    return button;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.clipsToBounds = YES;
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = ExteriaFontSemibold(14);
    _title.textColor = ExteriaColorTitle();
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
    _line.backgroundColor = ExteriaColorHairline();
    [self addSubview:_line];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
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
    [_changeHandler release];
    [super dealloc];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (void)refresh {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    BOOL showing = player.state != ExteriaMusicStateIdle && player.track != nil;
    if (showing) {
        BOOL playing = player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStateLoading;
        _title.text = ExteriaTrackLine(player.track);
        [_toggle setImage:ExteriaSymbolImage(playing ? ExteriaSymbolPause : ExteriaSymbolPlay, 22, ExteriaColorTitle()) forState:UIControlStateNormal];
        _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    }
    if (showing != _showing) {
        _showing = showing;
        self.hidden = !showing;
        if (_changeHandler) _changeHandler();
    }
    [self setNeedsLayout];
}

- (void)previousTapped { [[ExteriaMusicPlayer sharedPlayer] previous]; }
- (void)toggleTapped { [[ExteriaMusicPlayer sharedPlayer] togglePause]; }
- (void)nextTapped { [[ExteriaMusicPlayer sharedPlayer] next]; }
- (void)closeTapped { [[ExteriaMusicPlayer sharedPlayer] stop]; }
- (void)openPlayer { if (ExteriaThemeIsClassic()) [ExteriaMusicSheet present]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
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
