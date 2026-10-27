#import "exteria_profile_qr_controller.h"

#import <QuartzCore/QuartzCore.h>

#include "exteria_qr.h"

#import "exteria_avatar_view.h"
#import "exteria_classic_chrome.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_qr_view.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_wallpaper.h"

#define CARD_SIDE_MAX 300.0
#define CARD_RADIUS 24.0
#define CLASSIC_CARD_RADIUS 10.0
#define CODE_INSET 16.0
#define AVATAR 56.0
/* the card is cut away this far round the photo, so the wallpaper shows between the two */
#define PHOTO_GAP 4.0
#define LABEL_HEIGHT 22.0
#define SHEET_RADIUS 22.0
#define SHEET_MARGIN 16.0
#define TILE_MODERN 60.0
#define TILE_CLASSIC 48.0
#define TILE_GAP 8.0
#define SWITCH_HEIGHT 30.0
#define CODE_MIN 120.0
#define PAPER_COUNT 2
/* viewWithTag: matches the view it is sent to first, and the second tile has tag 1 itself */
#define PAPER_TAG 100
/* the key changed when the classic wallpaper became the second tile, which moved every gradient one place along */
#define THEME_KEY @"exteria.qr.theme.v3"

/* a backdrop and the ink of the code on it, for the tiles after the first */
typedef struct {
    CGFloat back[2][3];
    CGFloat ink[2][3];
    const char *emoji;
} ExteriaQrTheme;

static const ExteriaQrTheme ExteriaQrThemes[] = {
    {{{0.36, 0.66, 0.50}, {0.86, 0.83, 0.56}}, {{0.20, 0.58, 0.42}, {0.46, 0.72, 0.30}}, "\xF0\x9F\x8F\xA0"},
    {{{0.60, 0.80, 0.42}, {0.96, 0.86, 0.46}}, {{0.34, 0.64, 0.24}, {0.62, 0.72, 0.20}}, "\xF0\x9F\x90\xA5"},
    {{{0.44, 0.72, 0.96}, {0.66, 0.56, 0.96}}, {{0.20, 0.52, 0.90}, {0.38, 0.42, 0.88}}, "\xE2\x98\x83\xEF\xB8\x8F"},
    {{{0.72, 0.60, 0.96}, {0.56, 0.90, 0.90}}, {{0.52, 0.36, 0.88}, {0.24, 0.66, 0.78}}, "\xF0\x9F\x92\x8E"},
    {{{0.36, 0.64, 0.86}, {0.44, 0.86, 0.74}}, {{0.20, 0.50, 0.80}, {0.20, 0.68, 0.58}}, "\xF0\x9F\x8E\x93"},
};
#define GRADIENT_COUNT (sizeof(ExteriaQrThemes) / sizeof(ExteriaQrThemes[0]))
#define THEME_COUNT (GRADIENT_COUNT + PAPER_COUNT)

static UIColor *ExteriaQrColor(const CGFloat *rgb, CGFloat darken) {
    return [UIColor colorWithRed:rgb[0] * darken green:rgb[1] * darken blue:rgb[2] * darken alpha:1];
}

/* the sheet and its text follow the day or night switch of this screen, not the theme of the app */
static UIColor *ExteriaQrSheetColor(BOOL night) {
    return night ? [UIColor colorWithRed:0.11 green:0.13 blue:0.18 alpha:1] : [UIColor whiteColor];
}

static UIColor *ExteriaQrTextColor(BOOL night) {
    return night ? [UIColor whiteColor] : [UIColor colorWithWhite:0.08 alpha:1];
}

@interface ExteriaProfileQrController () {
    NSString *_url;
    NSString *_caption;
    NSString *_missingText;
    NSString *_initials;
    NSUInteger _seed;
    ExteriaPhoto *_photoRef;
    UIImageView *_wallpaper;
    UIView *_backdropView;
    CAGradientLayer *_backdrop;
    UIScrollView *_scroll;
    UIView *_card;
    CAShapeLayer *_cardMask;
    ExteriaQrView *_code;
    ExteriaAvatarView *_photo;
    UILabel *_link;
    UILabel *_missing;
    UIView *_sheet;
    CAShapeLayer *_sheetMask;
    UILabel *_sheetTitle;
    UIButton *_mode;
    UISegmentedControl *_modeSwitch;
    UIToolbar *_sheetBar;
    UIScrollView *_tiles;
    NSMutableArray *_tileViews;
    NSUInteger _theme;
    BOOL _night;
    BOOL _classic;
    BOOL _statusWasHidden;
    CGFloat _tile;
}
@end

@implementation ExteriaProfileQrController

/* the one place both kinds of owner end up: what the code holds, the line under it, and the picture in its middle */
- (id)initWithSession:(ExteriaSession *)session url:(NSString *)url caption:(NSString *)caption missing:(NSString *)missing initials:(NSString *)initials
                 seed:(NSUInteger)seed photo:(ExteriaPhoto *)photo avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _url = url.length ? [url copy] : nil;
    _caption = [caption copy];
    _missingText = [missing copy];
    _initials = [initials copy];
    _seed = seed;
    _photoRef = [photo retain];
    _night = ExteriaThemeIsDark();
    _classic = ExteriaThemeIsClassic();
    _tile = _classic ? TILE_CLASSIC : TILE_MODERN;
    /* with no choice stored the screen opens on the wallpaper of the style the app wears */
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:THEME_KEY];
    _theme = saved && saved.integerValue >= 0 && (NSUInteger)saved.integerValue < THEME_COUNT ? (NSUInteger)saved.integerValue : (_classic ? 1 : 0);
    self.clearBar = YES;
    self.screenTitle = NSLocalizedString(@"profile.qr", nil);
    return self;
}

- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    NSString *name = person.username;
    return [self initWithSession:session url:name.length ? [@"https://t.me/" stringByAppendingString:name] : nil
                         caption:name.length ? [@"@" stringByAppendingString:[name uppercaseString]] : @""
                         missing:NSLocalizedString(@"profile.qr.nousername", nil) initials:person.initials seed:(NSUInteger)(person.userId % 1000003)
                           photo:person.photo avatars:avatars media:media];
}

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    ExteriaDialog *dialog = channel.dialog;
    NSString *caption = channel.username.length ? [@"@" stringByAppendingString:[channel.username uppercaseString]] : [dialog.title uppercaseString];
    return [self initWithSession:session url:channel.webLink caption:caption missing:NSLocalizedString(@"channel.qr.nolink", nil) initials:dialog.initials
                            seed:dialog.avatarSeed photo:dialog.photo avatars:avatars media:media];
}

- (void)dealloc {
    [_url release];
    [_caption release];
    [_missingText release];
    [_initials release];
    [_photoRef release];
    [_wallpaper release];
    [_backdropView release];
    [_backdrop release];
    [_scroll release];
    [_card release];
    [_cardMask release];
    [_code release];
    [_photo release];
    [_link release];
    [_missing release];
    [_sheet release];
    [_sheetMask release];
    [_sheetTitle release];
    [_mode release];
    [_modeSwitch release];
    [_sheetBar release];
    [_tiles release];
    [_tileViews release];
    [super dealloc];
}

static UILabel *ExteriaCodeLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = alignment;
    label.font = font;
    return label;
}

- (void)buildBodyInView:(UIView *)root {
    _wallpaper = [[UIImageView alloc] init];
    [root addSubview:_wallpaper];
    _backdropView = [[UIView alloc] init];
    _backdrop = [[CAGradientLayer layer] retain];
    _backdrop.startPoint = CGPointMake(0.1, 0);
    _backdrop.endPoint = CGPointMake(0.9, 1);
    [_backdropView.layer addSublayer:_backdrop];
    [root addSubview:_backdropView];

    /* the card and the photo scroll above the sheet, which stays at the bottom, so a small screen can still bring the whole code
       into view */
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.backgroundColor = [UIColor clearColor];
    [root addSubview:_scroll];

    _card = [[UIView alloc] init];
    _card.backgroundColor = [UIColor whiteColor];
    _cardMask = [[CAShapeLayer layer] retain];
    _cardMask.fillRule = kCAFillRuleEvenOdd;
    _card.layer.mask = _cardMask;
    [_scroll addSubview:_card];
    _code = [[ExteriaQrView alloc] init];
    _code.metallic = _classic;
    [_card addSubview:_code];
    _link = ExteriaCodeLabel([UIColor blackColor], ExteriaFontBold(18), ExteriaTextAlignmentCenter);
    _link.adjustsFontSizeToFitWidth = YES;
    _link.minimumFontSize = 12;
    _link.text = _caption;
    [_card addSubview:_link];
    _photo = [[ExteriaAvatarView alloc] init];
    _photo.circular = YES;
    _photo.seed = _seed;
    _photo.initials = _initials;
    [_photo setPhoto:_photoRef cache:self.avatars];
    [_scroll addSubview:_photo];

    _missing = ExteriaCodeLabel(ExteriaColorSecondary(), ExteriaFontRegular(15), ExteriaTextAlignmentCenter);
    _missing.numberOfLines = 0;
    _missing.text = _missingText;
    _missing.hidden = _url != nil;
    [_scroll addSubview:_missing];

    _sheet = [[UIView alloc] init];
    _tileViews = [[NSMutableArray alloc] init];
    _tiles = [[UIScrollView alloc] init];
    _tiles.showsHorizontalScrollIndicator = NO;
    if (_classic) {
        /* the classic sheet is the system's own toolbar holding the tiles, and the day or night switch sits in the navigation bar, so
           the sheet is no taller than the tiles */
        _sheetBar = [[UIToolbar alloc] init];
        ExteriaClassicStyleToolbar(_sheetBar);
        [_sheet addSubview:_sheetBar];
        _modeSwitch = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:NSLocalizedString(@"profile.qr.day", nil),
                                                                 NSLocalizedString(@"profile.qr.night", nil), nil]];
        ExteriaClassicStyleSegmented(_modeSwitch);
        _modeSwitch.frame = CGRectMake(0, 0, 160, SWITCH_HEIGHT);
        [_modeSwitch addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = _modeSwitch;
    } else {
        _sheetMask = [[CAShapeLayer layer] retain];
        _sheet.layer.mask = _sheetMask;
        _sheetTitle = ExteriaCodeLabel(ExteriaQrTextColor(_night), ExteriaFontBold(18), ExteriaTextAlignmentLeft);
        _sheetTitle.text = NSLocalizedString(@"profile.qr", nil);
        [_sheet addSubview:_sheetTitle];
        _mode = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_mode addTarget:self action:@selector(toggleNight) forControlEvents:UIControlEventTouchUpInside];
        [_sheet addSubview:_mode];
    }
    [root addSubview:_sheet];
    [_sheet addSubview:_tiles];
    for (NSUInteger i = 0; i < THEME_COUNT; ++i) [self addTile:i];

    _card.hidden = _photo.hidden = _url == nil;
    _sheet.hidden = _url == nil;
    [self applyTheme];
    [self drawCode];
}

/* the first two tiles show the modern and the classic chat wallpaper, the others a gradient and the emoji of the theme */
- (void)addTile:(NSUInteger)index {
    CGRect bounds = CGRectMake(0, 0, _tile, _tile);
    CGFloat chipSide = floor(_tile * 0.46);
    UIControl *tile = [[[UIControl alloc] initWithFrame:bounds] autorelease];
    tile.tag = (NSInteger)index;
    tile.layer.cornerRadius = _classic ? 6 : 12;
    tile.layer.masksToBounds = YES;
    UIColor *ink;
    if (index < PAPER_COUNT) {
        UIImageView *paper = [[[UIImageView alloc] initWithFrame:bounds] autorelease];
        paper.tag = PAPER_TAG;
        [tile addSubview:paper];
        ink = ExteriaColorAccent();
    } else {
        CAGradientLayer *fill = [CAGradientLayer layer];
        fill.startPoint = CGPointMake(0.1, 0);
        fill.endPoint = CGPointMake(0.9, 1);
        fill.name = @"fill";
        fill.frame = bounds;
        [tile.layer addSublayer:fill];
        ink = ExteriaQrColor(ExteriaQrThemes[index - PAPER_COUNT].ink[0], 1);
    }
    UIImageView *chip = [[[UIImageView alloc] initWithFrame:CGRectMake((_tile - chipSide) / 2, index < PAPER_COUNT ? (_tile - chipSide) / 2 : 4, chipSide, chipSide)] autorelease];
    chip.backgroundColor = [UIColor whiteColor];
    chip.layer.cornerRadius = _classic ? 4 : 7;
    chip.contentMode = UIViewContentModeCenter;
    chip.image = ExteriaSymbolImage(ExteriaSymbolQr, chipSide - 8, ink);
    chip.userInteractionEnabled = NO;
    [tile addSubview:chip];
    if (index >= PAPER_COUNT) {
        ExteriaEmojiLabel *emoji = [[[ExteriaEmojiLabel alloc] init] autorelease];
        emoji.font = ExteriaFontRegular(floor(_tile * 0.27));
        emoji.textAlignment = ExteriaTextAlignmentCenter;
        emoji.text = [NSString stringWithUTF8String:ExteriaQrThemes[index - PAPER_COUNT].emoji];
        emoji.frame = CGRectMake(0, 6 + chipSide, _tile, _tile - 8 - chipSide);
        [tile addSubview:emoji];
    }
    [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_tiles addSubview:tile];
    [_tileViews addObject:tile];
}

static void ExteriaQrApplyPaper(UIImageView *view, NSUInteger index, BOOL night) {
    BOOL classic = index == 1;
    if (classic == ExteriaThemeIsClassic() && night == ExteriaThemeIsDark()) ExteriaApplyChatWallpaper(view, night);
    else ExteriaApplyWallpaperStyle(view, classic, night);
}

/* the backdrop, the ink of the code, the sheet and the tiles follow the chosen theme and the day or night switch */
- (void)applyTheme {
    BOOL paper = _theme < PAPER_COUNT;
    const ExteriaQrTheme *theme = paper ? NULL : &ExteriaQrThemes[_theme - PAPER_COUNT];
    CGFloat dim = _night ? 0.32 : 1;
    if (paper) ExteriaQrApplyPaper(_wallpaper, _theme, _night);
    _wallpaper.hidden = !paper;
    _backdropView.hidden = paper;
    if (theme) {
        _backdrop.colors = [NSArray arrayWithObjects:(id)ExteriaQrColor(theme->back[0], dim).CGColor, (id)ExteriaQrColor(theme->back[1], dim).CGColor, nil];
    }
    UIColor *top = theme ? ExteriaQrColor(theme->ink[0], 1) : ExteriaColorAccent();
    UIColor *bottom = theme ? ExteriaQrColor(theme->ink[1], 1) : ExteriaColorAccentDark();
    [_code setModuleTopColor:top bottomColor:bottom];
    /* the plain paper themes follow the chat color; a gradient theme keeps white, its ink is picked for it */
    UIColor *sheet = paper ? ExteriaColorQrPaper() : [UIColor whiteColor];
    _code.paperColor = sheet;
    _card.backgroundColor = sheet;
    _link.textColor = bottom;
    if (_classic) {
        _modeSwitch.selectedSegmentIndex = _night ? 1 : 0;
    } else {
        _sheet.backgroundColor = ExteriaQrSheetColor(_night);
        _sheetTitle.textColor = ExteriaQrTextColor(_night);
        [_mode setImage:ExteriaSymbolImage(_night ? ExteriaSymbolSun : ExteriaSymbolMoon, 24, ExteriaColorAccent()) forState:UIControlStateNormal];
    }
    for (UIView *tile in _tileViews) {
        if (tile.tag < PAPER_COUNT) {
            ExteriaQrApplyPaper((UIImageView *)[tile viewWithTag:PAPER_TAG], (NSUInteger)tile.tag, _night);
        } else {
            const ExteriaQrTheme *own = &ExteriaQrThemes[tile.tag - PAPER_COUNT];
            for (CALayer *layer in tile.layer.sublayers) {
                if (![layer.name isEqualToString:@"fill"]) continue;
                ((CAGradientLayer *)layer).colors = [NSArray arrayWithObjects:(id)ExteriaQrColor(own->back[0], dim).CGColor,
                                                     (id)ExteriaQrColor(own->back[1], dim).CGColor, nil];
            }
        }
        BOOL chosen = (NSUInteger)tile.tag == _theme;
        tile.layer.borderColor = (chosen ? ExteriaColorAccent() : [UIColor colorWithWhite:0.5 alpha:0.6]).CGColor;
        tile.layer.borderWidth = chosen ? 2 : (_classic ? 1 : 0);
    }
}

- (void)tileTapped:(UIControl *)tile {
    _theme = (NSUInteger)tile.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)_theme forKey:THEME_KEY];
    [self applyTheme];
}

- (void)modeChanged:(UISegmentedControl *)control {
    _night = control.selectedSegmentIndex == 1;
    [self applyTheme];
}

- (void)toggleNight {
    _night = !_night;
    [self applyTheme];
}

- (void)drawCode {
    static uint8_t modules[EXTERIA_QR_MAX_MODULES];
    int side = 0;
    const char *text = _url.UTF8String;
    if (!text || exteria_qr_encode((const uint8_t *)text, strlen(text), modules, sizeof(modules), &side, NULL) != EXTERIA_OK) {
        NSLog(@"exteria: the profile link did not encode as a QR code");
        return;
    }
    [_code setModules:[NSData dataWithBytes:modules length:(NSUInteger)(side * side)] side:side animated:YES];
}

- (void)layoutBody:(CGRect)body {
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat width = body.size.width, height = body.size.height;
    CGRect whole = self.view.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wallpaper.frame = whole;
    _backdropView.frame = whole;
    _backdrop.frame = _backdropView.bounds;
    [CATransaction commit];
    _scroll.frame = body;

    CGSize missing = [_missing sizeThatFits:CGSizeMake(width - 64, 200)];
    _missing.frame = CGRectMake(32, 40, width - 64, missing.height);
    if (!_url) {
        _scroll.contentSize = body.size;
        return;
    }

    /* the sheet: a row of tiles; the modern one has a title and the day or night switch over them, the classic one has the switch in
       the navigation bar */
    CGFloat tilesTop = _classic ? 6 : 40;
    CGFloat sheetHeight = tilesTop + _tile + (_classic ? 6 : 10) + MAX(insets.bottom, 4);
    CGFloat sheetTop = CGRectGetMaxY(body) - sheetHeight;
    _sheet.frame = CGRectMake(body.origin.x, sheetTop, width, sheetHeight);
    if (_classic) {
        _sheetBar.frame = _sheet.bounds;
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _sheetMask.frame = _sheet.bounds;
        _sheetMask.path = [UIBezierPath bezierPathWithRoundedRect:_sheet.bounds byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight
                                                      cornerRadii:CGSizeMake(SHEET_RADIUS, SHEET_RADIUS)].CGPath;
        [CATransaction commit];
        _sheetTitle.frame = CGRectMake(SHEET_MARGIN + 2, 6, width - 2 * SHEET_MARGIN - 56, 30);
        _mode.frame = CGRectMake(width - SHEET_MARGIN - 48, 3, 48, 36);
    }
    _tiles.frame = CGRectMake(0, tilesTop, width, _tile);
    for (NSUInteger i = 0; i < _tileViews.count; ++i) {
        UIView *tile = [_tileViews objectAtIndex:i];
        tile.frame = CGRectMake(SHEET_MARGIN + (_tile + TILE_GAP) * (CGFloat)i, 0, _tile, _tile);
    }
    _tiles.contentSize = CGSizeMake(2 * SHEET_MARGIN + (_tile + TILE_GAP) * (CGFloat)_tileViews.count - TILE_GAP, _tile);

    /* the whole card with the photo over its top edge has to show above the sheet, so the code takes the side the
       room allows */
    CGFloat cut = AVATAR / 2 + PHOTO_GAP;
    CGFloat around = cut + 6 + 4 + LABEL_HEIGHT + 12;
    CGFloat room = height - sheetHeight;
    CGFloat code = MIN(MIN(CARD_SIDE_MAX, width - 64) - 2 * CODE_INSET, room - AVATAR / 2 - 6 - 10 - around);
    code = floor(MAX(code, CODE_MIN));
    CGFloat cardWidth = code + 2 * CODE_INSET;
    CGFloat cardHeight = around + code;
    CGFloat top = AVATAR / 2 + MAX(6, (room - AVATAR / 2 - cardHeight) / 2);
    _card.frame = CGRectMake((width - cardWidth) / 2, top, cardWidth, cardHeight);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:_card.bounds cornerRadius:_classic ? CLASSIC_CARD_RADIUS : CARD_RADIUS];
    [shape appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cardWidth / 2 - cut, -cut, 2 * cut, 2 * cut)]];
    shape.usesEvenOddFillRule = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _cardMask.frame = _card.bounds;
    _cardMask.path = shape.CGPath;
    [CATransaction commit];
    _code.frame = CGRectMake(CODE_INSET, cut + 6, code, code);
    _link.frame = CGRectMake(CODE_INSET, cut + 6 + code + 4, code, LABEL_HEIGHT);
    _photo.frame = CGRectMake((width - AVATAR) / 2, top - AVATAR / 2, AVATAR, AVATAR);
    _scroll.contentSize = CGSizeMake(width, MAX(height, top + cardHeight + 10 + sheetHeight));
}

/* the modern bar is see-through, so the picture starts at the top edge and the card gets the room the bar would take */
- (CGRect)bodyFrame {
    if (_classic) return [super bodyFrame];
    CGSize size = self.view.bounds.size;
    CGFloat top = ExteriaLayoutInsets(self).top;
    return CGRectMake(0, top, size.width, size.height - top);
}

/* the wallpaper stops at the status bar on ios 5 and 6, where the window's own lilac shows above it as a strip;
   the modern screen hides the bar like the story viewer does */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_classic) return;
    UIApplication *application = [UIApplication sharedApplication];
    _statusWasHidden = application.statusBarHidden;
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_classic) return;
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) [application setStatusBarHidden:_statusWasHidden withAnimation:UIStatusBarAnimationFade];
}

- (BOOL)prefersStatusBarHidden { return !_classic; }

@end
