#import "exteria_wallpaper_grid_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_wallpaper.h"

#define TILE_WIDTH 72.0
#define TILE_HEIGHT 104.0
#define GAP 10.0
#define PAD 14.0
#define RADIUS 16.0
#define RING 3.0
/* the tiles before the gradients: the library and the standard wallpaper */
#define LEADING_TILES 2
#define TAG_CHECK 100

@interface ExteriaWallpaperGridView () {
    UIScrollView *_scroll;
    NSMutableArray *_tiles;
    NSUInteger _chosenIndex;
    BOOL _standardChosen;
    BOOL _photoChosen;
    void (^_chooseHandler)(NSUInteger index);
    void (^_galleryHandler)(void);
    void (^_standardHandler)(void);
    CGPoint _tapPoint;
    BOOL _scrolledToChosen;
}
@end

@implementation ExteriaWallpaperGridView

@synthesize chooseHandler = _chooseHandler;
@synthesize galleryHandler = _galleryHandler;
@synthesize standardHandler = _standardHandler;
@synthesize tapPoint = _tapPoint;
@synthesize chosenIndex = _chosenIndex;
@synthesize standardChosen = _standardChosen;
@synthesize photoChosen = _photoChosen;

+ (CGFloat)height {
    return 2 * PAD + TILE_HEIGHT;
}

- (UIColor *)colorOfRGB:(uint32_t)rgb {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

/* a tile of the row: the corners and the ring are on the tile, and what it shows is clipped to them */
- (UIControl *)makeTileWithTag:(NSInteger)tag {
    UIControl *tile = [[[UIControl alloc] init] autorelease];
    tile.tag = tag;
    tile.layer.cornerRadius = RADIUS;
    tile.clipsToBounds = YES;
    UIImageView *check = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolCheck, 28, [UIColor whiteColor])] autorelease];
    check.contentMode = UIViewContentModeCenter;
    check.tag = TAG_CHECK;
    check.hidden = YES;
    check.userInteractionEnabled = NO;
    check.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    [tile addSubview:check];
    [tile addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:tile];
    [_tiles addObject:tile];
    return tile;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 22;
    self.clipsToBounds = YES;
    _chosenIndex = NSNotFound;
    _tiles = [[NSMutableArray alloc] init];
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.alwaysBounceHorizontal = YES;
    [self addSubview:_scroll];

    /* the library: the tone of the field with the glyph of the gallery in the accent */
    UIControl *gallery = [self makeTileWithTag:-1];
    gallery.backgroundColor = ExteriaColorField();
    UIImageView *glyph = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolGallery, 30, ExteriaColorAccent())] autorelease];
    glyph.contentMode = UIViewContentModeCenter;
    glyph.tag = 101;
    glyph.userInteractionEnabled = NO;
    [gallery insertSubview:glyph atIndex:0];
    gallery.accessibilityLabel = NSLocalizedString(@"chatset.wallpaper.gallery", nil);

    /* the standard wallpaper, drawn as the chat draws it */
    UIControl *standard = [self makeTileWithTag:-2];
    UIImageView *picture = [[[UIImageView alloc] init] autorelease];
    picture.tag = 101;
    picture.contentMode = UIViewContentModeScaleAspectFill;
    picture.clipsToBounds = YES;
    picture.userInteractionEnabled = NO;
    ExteriaApplyWallpaperStyle(picture, ExteriaThemeIsClassic(), ExteriaThemeIsDark());
    [standard insertSubview:picture atIndex:0];
    standard.accessibilityLabel = NSLocalizedString(@"chatset.wallpaper.reset", nil);

    for (NSUInteger i = 0; i < ExteriaWallpaperPresetCount(); ++i) {
        ExteriaWallpaperSetting preset = ExteriaWallpaperPreset(i);
        UIControl *tile = [self makeTileWithTag:(NSInteger)i];
        CAGradientLayer *gradient = [CAGradientLayer layer];
        CGFloat r = preset.angle * M_PI / 180.0;
        gradient.startPoint = CGPointMake(0.5 - cos(r) / 2, 0.5 - sin(r) / 2);
        gradient.endPoint = CGPointMake(0.5 + cos(r) / 2, 0.5 + sin(r) / 2);
        gradient.colors = [NSArray arrayWithObjects:(id)[self colorOfRGB:preset.top].CGColor, (id)[self colorOfRGB:preset.bottom].CGColor, nil];
        [tile.layer insertSublayer:gradient atIndex:0];
        tile.accessibilityLabel = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
    }
    return self;
}

- (void)dealloc {
    [_scroll release];
    [_tiles release];
    [_chooseHandler release];
    [_galleryHandler release];
    [_standardHandler release];
    [super dealloc];
}

- (void)showChosen:(BOOL)chosen onTile:(UIControl *)tile {
    tile.layer.borderWidth = chosen ? RING : 0;
    tile.layer.borderColor = ExteriaColorAccent().CGColor;
    [tile viewWithTag:TAG_CHECK].hidden = !chosen;
    tile.accessibilityTraits = chosen ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (void)refreshChosen {
    for (UIControl *tile in _tiles) {
        BOOL chosen;
        if (tile.tag == -1) chosen = _photoChosen;
        else if (tile.tag == -2) chosen = _standardChosen;
        else chosen = !_photoChosen && !_standardChosen && (NSUInteger)tile.tag == _chosenIndex;
        [self showChosen:chosen onTile:tile];
    }
}

- (void)setChosenIndex:(NSUInteger)index {
    _chosenIndex = index;
    [self refreshChosen];
}

- (void)setStandardChosen:(BOOL)chosen {
    _standardChosen = chosen;
    [self refreshChosen];
}

- (void)setPhotoChosen:(BOOL)chosen {
    _photoChosen = chosen;
    [self refreshChosen];
}

- (void)tapped:(UIControl *)tile {
    _tapPoint = [tile.superview convertPoint:tile.center toView:nil];
    if (tile.tag == -1) {
        if (_galleryHandler) _galleryHandler();
    } else if (tile.tag == -2) {
        if (_standardHandler) _standardHandler();
    } else if (_chooseHandler) {
        _chooseHandler((NSUInteger)tile.tag);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    CGFloat x = PAD;
    for (UIControl *tile in _tiles) {
        tile.frame = CGRectMake(x, PAD, TILE_WIDTH, TILE_HEIGHT);
        UIView *content = [tile viewWithTag:101];
        content.frame = tile.bounds;
        for (CALayer *layer in tile.layer.sublayers) {
            if ([layer isKindOfClass:[CAGradientLayer class]]) layer.frame = tile.bounds;
        }
        [tile viewWithTag:TAG_CHECK].frame = tile.bounds;
        x += TILE_WIDTH + GAP;
    }
    _scroll.contentSize = CGSizeMake(x - GAP + PAD, self.bounds.size.height);
    /* the row opens with the chosen gradient in view, once */
    if (!_scrolledToChosen && self.bounds.size.width > 1) {
        _scrolledToChosen = YES;
        if (_chosenIndex != NSNotFound && !_photoChosen && !_standardChosen) {
            CGFloat chosenX = PAD + (CGFloat)(LEADING_TILES + _chosenIndex) * (TILE_WIDTH + GAP);
            CGFloat offset = MIN(MAX(0, chosenX - (self.bounds.size.width - TILE_WIDTH) / 2), MAX(0, _scroll.contentSize.width - self.bounds.size.width));
            _scroll.contentOffset = CGPointMake(offset, 0);
        }
    }
}

@end
