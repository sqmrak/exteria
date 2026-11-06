#import "exteria_music_pill.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_music_player.h"
#import "exteria_music_style.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define CARD_HEIGHT 72.0
#define CARD_RADIUS 20.0
#define COVER_INSET 8.0
#define COVER_SIDE 56.0
#define COVER_RADIUS 12.0
#define KEY_SIDE 36.0
#define SLOT 34.0
/* the part of the card, from its right edge, that the pattern may reach */
#define PATTERN_REACH 0.42

/* the emoji of the profile as a few marks that run onto the right end of the card, each fainter toward the left; the marks stand at fixed places so a
   card looks the same every time it is drawn */
@interface ExteriaMusicPatternView : UIView {
    UIImage *_image;
    UIColor *_color;
}
- (void)setImage:(UIImage *)image color:(UIColor *)color;
@end

@implementation ExteriaMusicPatternView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    return self;
}

- (void)dealloc {
    [_image release];
    [_color release];
    [super dealloc];
}

- (void)setImage:(UIImage *)image color:(UIColor *)color {
    [_image release];
    _image = [image retain];
    [_color release];
    _color = [color retain];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_image.CGImage || !_color) return;
    /* x and y as fractions of the view, then the size as a fraction of its height, then the alpha */
    static const CGFloat marks[][4] = {
        {0.80f, 0.20f, 0.30f, 0.30f}, {0.55f, 0.72f, 0.24f, 0.22f}, {0.93f, 0.62f, 0.34f, 0.34f},
        {0.30f, 0.30f, 0.20f, 0.14f}, {0.66f, 0.40f, 0.18f, 0.16f}, {0.12f, 0.78f, 0.17f, 0.10f}
    };
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGSize size = self.bounds.size;
    for (size_t i = 0; i < sizeof(marks) / sizeof(marks[0]); ++i) {
        CGFloat side = size.height * marks[i][2];
        CGRect box = CGRectMake(size.width * marks[i][0] - side / 2, size.height * marks[i][1] - side / 2, side, side);
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, box.origin.x, box.origin.y + side);
        CGContextScaleCTM(context, 1, -1);
        CGContextClipToMask(context, CGRectMake(0, 0, side, side), _image.CGImage);
        CGContextSetFillColorWithColor(context, [_color colorWithAlphaComponent:marks[i][3]].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, side, side));
        CGContextRestoreGState(context);
    }
}

@end

/* the average color of a cover, drawn into one pixel */
static UIColor *ExteriaCoverColor(UIImage *image) {
    if (!image.CGImage) return nil;
    uint8_t pixel[4] = {0, 0, 0, 0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context);
    if (!pixel[3]) return nil;
    return [UIColor colorWithRed:pixel[0] / 255.0f green:pixel[1] / 255.0f blue:pixel[2] / 255.0f alpha:1];
}

/* the plate is the cover's color pulled toward black until white text reads on it, as light covers would otherwise leave the words faint */
static UIColor *ExteriaPlateColor(UIColor *cover) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![cover getRed:&red green:&green blue:&blue alpha:&alpha]) return nil;
    CGFloat luminance = 0.299f * red + 0.587f * green + 0.114f * blue;
    CGFloat keep = luminance > 0.55f ? 0.5f : (luminance > 0.35f ? 0.68f : 0.85f);
    return [UIColor colorWithRed:red * keep green:green * keep blue:blue * keep alpha:1];
}

@interface ExteriaMusicPill () {
    ExteriaMedia *_savedTrack;
    ExteriaMediaCache *_media;
    UIImage *_patternImage;
    UIColor *_patternColor;
    void (^_contentHandler)(void);
    ExteriaMusicPatternView *_pattern;
    UIImageView *_cover;
    UIImageView *_note;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_artist;
    ExteriaMusicKey *_toggle;
    UIButton *_close;
    NSString *_coverKey;
    UIColor *_plate;
    CAGradientLayer *_glass;
    BOOL _hadContent;
}
@end

@implementation ExteriaMusicPill

@synthesize savedTrack = _savedTrack;
@synthesize media = _media;
@synthesize patternImage = _patternImage;
@synthesize patternColor = _patternColor;
@synthesize contentHandler = _contentHandler;

+ (CGFloat)height { return CARD_HEIGHT; }

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaMusicTonalColor();
    self.layer.cornerRadius = CARD_RADIUS;
    self.clipsToBounds = YES;
    if (ExteriaThemeIsClassic()) {
        /* the classic card is a plate that is lit at the top and shades down to the bottom with no edge between the two, a dark rim round it, and the cover in a white slide mount */
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.4].CGColor;
        _glass = [[CAGradientLayer layer] retain];
        _glass.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:1 alpha:0.14].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.16].CGColor, nil];
        [self.layer insertSublayer:_glass atIndex:0];
    }
    _pattern = [[ExteriaMusicPatternView alloc] init];
    CAGradientLayer *fade = [CAGradientLayer layer];
    fade.startPoint = CGPointMake(0, 0.5f);
    fade.endPoint = CGPointMake(1, 0.5f);
    fade.colors = [NSArray arrayWithObjects:(id)[UIColor clearColor].CGColor, (id)[UIColor blackColor].CGColor, nil];
    _pattern.layer.mask = fade;
    [self addSubview:_pattern];
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = ExteriaThemeIsClassic() ? 5 : COVER_RADIUS;
    if (ExteriaThemeIsClassic()) {
        _cover.layer.borderWidth = 2;
        _cover.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.92].CGColor;
    }
    _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    _cover.userInteractionEnabled = NO;
    [self addSubview:_cover];
    _note = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMusic, 24, [UIColor colorWithWhite:1 alpha:0.8])];
    _note.contentMode = UIViewContentModeCenter;
    _note.userInteractionEnabled = NO;
    [self addSubview:_note];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = [UIFont boldSystemFontOfSize:17];
    _title.textColor = [UIColor whiteColor];
    _title.dropsUndrawable = YES;
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];
    _artist = [[ExteriaEmojiLabel alloc] init];
    _artist.font = [UIFont systemFontOfSize:15];
    _artist.textColor = [UIColor colorWithWhite:1 alpha:0.7f];
    _artist.dropsUndrawable = YES;
    _artist.userInteractionEnabled = NO;
    [self addSubview:_artist];
    _toggle = [[ExteriaMusicKey buttonWithType:UIButtonTypeCustom] retain];
    _toggle.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22f];
    [_toggle setRestRadius:KEY_SIDE / 2 animated:NO];
    [_toggle addTarget:self action:@selector(togglePlayback) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_toggle];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:ExteriaSymbolImage(ExteriaSymbolClose, 14, [UIColor colorWithWhite:1 alpha:0.7f]) forState:UIControlStateNormal];
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
    [_media release];
    [_patternImage release];
    [_patternColor release];
    [_glass release];
    [_contentHandler release];
    [_pattern release];
    [_cover release];
    [_note release];
    [_title release];
    [_artist release];
    [_toggle release];
    [_close release];
    [_coverKey release];
    [_plate release];
    [super dealloc];
}

/* the controls belong to the profile's own song; a song the person plays from elsewhere must not replace what the profile shows */
- (BOOL)playerActive {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    return player.state != ExteriaMusicStateIdle && [player isCurrentTrack:_savedTrack];
}

- (BOOL)hasContent {
    return _savedTrack != nil;
}

- (void)setSavedTrack:(ExteriaMedia *)track {
    if (track == _savedTrack) return;
    [_savedTrack release];
    _savedTrack = [track retain];
    [self refresh];
}

- (void)setMedia:(ExteriaMediaCache *)media {
    if (media == _media) return;
    [_media release];
    _media = [media retain];
    [self refresh];
}

- (void)setPatternImage:(UIImage *)image {
    if (image == _patternImage) return;
    [_patternImage release];
    _patternImage = [image retain];
    [_pattern setImage:_patternImage color:_patternColor];
}

- (void)setPatternColor:(UIColor *)color {
    if (color == _patternColor) return;
    [_patternColor release];
    _patternColor = [color retain];
    [_pattern setImage:_patternImage color:_patternColor];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (void)setPlate:(UIColor *)color {
    if (color == _plate) return;
    [_plate release];
    _plate = [color retain];
    [UIView animateWithDuration:self.window ? 0.25 : 0 animations:^{
        self.backgroundColor = _plate ? _plate : ExteriaMusicTonalColor();
    }];
}

/* shows the saved song, with the controls while it is the one that plays */
- (void)refresh {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    BOOL active = [self playerActive];
    ExteriaMedia *shown = _savedTrack;
    BOOL content = shown != nil;
    self.hidden = !content;
    _title.text = shown ? ExteriaTrackTitle(shown) : @"";
    NSString *performer = shown ? ExteriaTrackPerformer(shown) : @"";
    _artist.text = performer;
    _toggle.hidden = !active;
    _close.hidden = !active;
    if (active) {
        BOOL playing = player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStateLoading;
        [_toggle setImage:ExteriaSymbolImage(playing ? ExteriaSymbolPause : ExteriaSymbolPlay, 16, [UIColor whiteColor]) forState:UIControlStateNormal];
        _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    }
    [self loadCoverOf:shown];
    self.accessibilityLabel = shown ? ExteriaTrackLine(shown) : nil;
    [self setNeedsLayout];
    if (content != _hadContent) {
        _hadContent = content;
        if (_contentHandler) _contentHandler();
    }
}

/* the cover and the plate that takes its color; a song without a cover, or one that has not come yet, keeps the note and the tonal plate */
- (void)loadCoverOf:(ExteriaMedia *)track {
    NSString *key = track ? [NSString stringWithFormat:@"%lld:%@:%@", track.size, track.name, track.title] : nil;
    if (key == _coverKey || [key isEqualToString:_coverKey]) return;
    [_coverKey release];
    _coverKey = [key copy];
    _cover.image = nil;
    _note.hidden = NO;
    [self setPlate:nil];
    if (!track || !_media) return;
    NSString *requested = _coverKey;
    [_media loadCoverForTrack:track maxSide:COVER_SIDE * ExteriaScreenScale() completion:^(UIImage *image) {
        if (!image || ![requested isEqualToString:_coverKey]) return;
        _cover.image = image;
        _note.hidden = YES;
        UIColor *plate = ExteriaPlateColor(ExteriaCoverColor(image));
        if (plate) [self setPlate:plate];
    }];
}

- (void)togglePlayback {
    [[ExteriaMusicPlayer sharedPlayer] togglePause];
}

- (void)stopPlayback {
    [[ExteriaMusicPlayer sharedPlayer] stop];
}

- (CGFloat)widthWithin:(CGFloat)maxWidth {
    return maxWidth;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    BOOL active = [self playerActive];
    if (_glass) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _glass.frame = self.bounds;
        [CATransaction commit];
    }
    CGFloat reach = floor(size.width * PATTERN_REACH);
    _pattern.frame = CGRectMake(size.width - reach, 0, reach, size.height);
    /* the marks fade out toward the left edge of their area */
    _pattern.layer.mask.frame = _pattern.bounds;
    _cover.frame = CGRectMake(COVER_INSET, COVER_INSET, COVER_SIDE, COVER_SIDE);
    _note.frame = _cover.frame;
    CGFloat right = active ? KEY_SIDE + SLOT + 10 : 16;
    CGFloat left = CGRectGetMaxX(_cover.frame) + 14;
    CGFloat width = MAX(0, size.width - left - right);
    BOOL hasArtist = _artist.text.length > 0;
    _title.frame = CGRectMake(left, hasArtist ? 15 : (size.height - 22) / 2, width, 22);
    _artist.frame = CGRectMake(left, 38, width, hasArtist ? 20 : 0);
    _toggle.frame = CGRectMake(size.width - SLOT - KEY_SIDE - 4, (size.height - KEY_SIDE) / 2, KEY_SIDE, KEY_SIDE);
    _close.frame = CGRectMake(size.width - SLOT - 4, 0, SLOT, size.height);
}

@end
