#import "exteria_classic_chrome.h"
#import "exteria_status_label.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"

BOOL ExteriaClassicIsFlatSystem(void) {
#if defined(__LP64__)
    return YES;
#else
    /* the armv7 slice links against the ios 5 sdk, so ios 7 and later draw its bars in the ios 6 look where tintColor
       paints the bar itself; setting a white tintColor there turned every bar white */
    return NO;
#endif
}

/* the purple of the bars: deep enough in the dark theme that the gloss of ios 5 and 6 still reads, lighter in the white
   theme where the deep one looks heavy next to white rows; both keep the white text */
static UIColor *ExteriaClassicBarColor(void) {
    if (ExteriaThemeIsDark()) return ExteriaThemeTinted([UIColor colorWithRed:0.40 green:0.27 blue:0.56 alpha:1]);
    return ExteriaThemeTinted([UIColor colorWithRed:0.60 green:0.44 blue:0.78 alpha:1]);
}

/* every picture of the classic chrome is drawn once for a palette and then kept: the lists, the bars and the buttons ask for the same few pictures at every configure and every touch, and
   each ask drew a gradient into a new bitmap on the main thread. the key holds the revision of the theme, so a change of colors never finds a picture of the old ones */
static NSCache *ExteriaClassicImageCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 120;
    });
    return cache;
}

static UIImage *ExteriaClassicRemembered(NSString *key, UIImage *(^make)(void)) {
    NSCache *cache = ExteriaClassicImageCache();
    NSString *full = [NSString stringWithFormat:@"%lu|%.1f|%@", (unsigned long)ExteriaThemeRevision(), ExteriaScreenScale(), key];
    UIImage *image = [[[cache objectForKey:full] retain] autorelease];
    if (image) return image;
    image = make();
    if (image) [cache setObject:image forKey:full];
    return image;
}

static UIImage *ExteriaClassicBarImageMade(void);

static UIImage *ExteriaClassicBarImage(void) {
    return ExteriaClassicRemembered(@"bar", ^UIImage *{ return ExteriaClassicBarImageMade(); });
}

static UIImage *ExteriaClassicBarImageMade(void) {
    UIColor *base = ExteriaClassicBarColor();
    UIColor *top = ExteriaMixedColor(base, [UIColor whiteColor], 0.15);
    UIColor *bottom = ExteriaMixedColor(base, [UIColor blackColor], 0.12);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, 44), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = [NSArray arrayWithObjects:(id)top.CGColor, (id)base.CGColor, (id)bottom.CGColor, nil];
    CGFloat stops[] = {0, 0.48, 1};
    CGGradientRef gradient = CGGradientCreateWithColors(space, (CFArrayRef)colors, stops);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, 44), 0);
    /* the light on the upper half fades out by the middle: with a hard edge there, a strip of any height showed a band, and the pinned message, the player and the sheet headers
       are all strips */
    {
        CGFloat shine[] = {1, 1, 1, 0.12, 1, 1, 1, 0};
        CGGradientRef lit = CGGradientCreateWithColorComponents(space, shine, NULL, 2);
        CGContextSaveGState(context);
        CGContextClipToRect(context, CGRectMake(0, 0, 2, 22));
        CGContextDrawLinearGradient(context, lit, CGPointMake(0, 0), CGPointMake(0, 22), 0);
        CGContextRestoreGState(context);
        CGGradientRelease(lit);
    }
    /* a bright line runs along the top and a dark one under the bar */
    [[UIColor colorWithWhite:1 alpha:0.22] setFill];
    UIRectFill(CGRectMake(0, 0, 2, 1.0 / ExteriaScreenScale()));
    [[UIColor colorWithWhite:0 alpha:0.35] setFill];
    UIRectFill(CGRectMake(0, 44 - 1.0 / ExteriaScreenScale(), 2, 1.0 / ExteriaScreenScale()));
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* ios 15 draws a bar that has nothing scrolled under it from scrollEdgeAppearance, which is clear by default and ignores barTintColor: the classic bar came out
   white with white buttons and title. the appearance classes are looked up by name, so the slices linked against old sdks never see them */
static void ExteriaClassicApplyBarAppearance(UIView *bar) {
    BOOL navigation = [bar isKindOfClass:[UINavigationBar class]];
    Class kind = NSClassFromString(navigation ? @"UINavigationBarAppearance" : @"UIToolbarAppearance");
    SEL opaque = NSSelectorFromString(@"configureWithOpaqueBackground");
    if (!kind || ![kind instancesRespondToSelector:opaque]) return;
    id appearance = [[[kind alloc] init] autorelease];
    [appearance performSelector:opaque];
    [appearance setValue:ExteriaClassicBarColor() forKey:@"backgroundColor"];
    if (navigation && [appearance respondsToSelector:NSSelectorFromString(@"setBackgroundImage:")]) [appearance setValue:ExteriaClassicBarImage() forKey:@"backgroundImage"];
    if (navigation) {
        [appearance setValue:[NSDictionary dictionaryWithObject:[UIColor whiteColor] forKey:NSForegroundColorAttributeName] forKey:@"titleTextAttributes"];
    }
    for (NSString *key in [NSArray arrayWithObjects:@"standardAppearance", @"compactAppearance", @"scrollEdgeAppearance", nil]) {
        NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        if ([bar respondsToSelector:NSSelectorFromString(setter)]) [bar setValue:appearance forKey:key];
    }
}

static void ExteriaClassicTintBar(id bar) {
    if (ExteriaClassicIsFlatSystem()) {
        ExteriaClassicApplyBarAppearance(bar);
        /* black style makes the title and the buttons white; the tint then colors the bar itself */
        [bar setValue:ExteriaClassicBarColor() forKey:@"barTintColor"];
        [bar setValue:[UIColor whiteColor] forKey:@"tintColor"];
        [bar setValue:[NSNumber numberWithBool:NO] forKey:@"translucent"];
    } else {
        [bar setTintColor:ExteriaClassicBarColor()];
    }
}

void ExteriaClassicStyleNavigationBar(UINavigationBar *bar) {
    bar.barStyle = ExteriaClassicIsFlatSystem() ? UIBarStyleBlack : (ExteriaThemeIsDark() ? UIBarStyleBlack : UIBarStyleDefault);
    ExteriaClassicTintBar(bar);
    if (ExteriaClassicIsFlatSystem()) [bar setBackgroundImage:ExteriaClassicBarImage() forBarMetrics:UIBarMetricsDefault];
}

void ExteriaClassicStyleToolbar(UIToolbar *bar) {
    bar.barStyle = ExteriaClassicIsFlatSystem() ? UIBarStyleBlack : (ExteriaThemeIsDark() ? UIBarStyleBlack : UIBarStyleDefault);
    ExteriaClassicTintBar(bar);
}

/* a stretchable pill: the fill is a little darker than the screen and light falls on its lower rim, with no shadow inside */
static UIImage *ExteriaClassicSearchWellMade(void);

static UIImage *ExteriaClassicSearchWell(void) {
    return ExteriaClassicRemembered(@"well", ^UIImage *{ return ExteriaClassicSearchWellMade(); });
}

static UIImage *ExteriaClassicSearchWellMade(void) {
    BOOL dark = ExteriaThemeIsDark();
    CGFloat side = 30, rim = 1;
    /* one point wider than the two caps, or ios 6 leaves a seam down the middle of the pill */
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side + 1, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect pill = CGRectMake(0, 0, side + 1, side - rim);
    CGFloat radius = (side - rim) / 2;
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:radius];
    UIBezierPath *lower = [UIBezierPath bezierPathWithRoundedRect:CGRectOffset(pill, 0, rim) cornerRadius:radius];
    [(dark ? [UIColor colorWithWhite:1 alpha:0.1] : [UIColor colorWithWhite:1 alpha:0.9]) setFill];
    [lower fill];
    [ExteriaThemeTinted(dark ? [UIColor colorWithRed:0.09 green:0.07 blue:0.13 alpha:1] : [UIColor colorWithRed:0.86 green:0.83 blue:0.91 alpha:1]) setFill];
    [shape fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius + rim, radius)];
}

/* the text field a search bar keeps inside, which sits one level down on ios 5 and 6 and two on ios 7 and later */
static NSArray *ExteriaClassicSearchFieldsIn(UIView *view) {
    NSMutableArray *found = [NSMutableArray array];
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[UITextField class]]) [found addObject:child];
        else [found addObjectsFromArray:ExteriaClassicSearchFieldsIn(child)];
    }
    return found;
}

void ExteriaClassicStyleSearchBar(UISearchBar *bar) {
    bar.barStyle = ExteriaClassicIsFlatSystem() ? UIBarStyleBlack : (ExteriaThemeIsDark() ? UIBarStyleBlack : UIBarStyleDefault);
    ExteriaClassicTintBar(bar);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
    UIImage *clear = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    bar.backgroundImage = clear;
    [bar setSearchFieldBackgroundImage:ExteriaClassicSearchWell() forState:UIControlStateNormal];
    /* the word sat high in the pill of the custom image; the field of the bar puts its line on the middle when it is asked to */
    for (UIView *view in ExteriaClassicSearchFieldsIn(bar)) {
        UITextField *field = (UITextField *)view;
        field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        /* the field of the system is black on white; the pill of the dark themes is dark, so the typed words and the placeholder are white on it */
        if (ExteriaThemeIsDark()) {
            field.textColor = [UIColor whiteColor];
            if (field.placeholder.length && [field respondsToSelector:@selector(setAttributedPlaceholder:)]) {
                NSDictionary *look = [NSDictionary dictionaryWithObject:[UIColor colorWithWhite:1 alpha:0.6] forKey:@"NSColor"];
                [field setValue:[[[NSAttributedString alloc] initWithString:field.placeholder attributes:look] autorelease] forKey:@"attributedPlaceholder"];
            }
        }
    }
    /* the pill of the image has a lit rim under it, which the field counts in its height, so the line sat a point
       or two below the middle of what is seen */
    bar.searchTextPositionAdjustment = UIOffsetMake(0, -3.0f);
}

#define FACADE_WELL_HEIGHT 30.0
#define FACADE_WELL_RIM 1.0
#define FACADE_SIDE 8.0
#define FACADE_GLASS 14.0

/* the pill, the glass and the word, laid out by this view alone */
@interface ExteriaClassicSearchFacadeView : UIView {
    UIImageView *_well;
    UIImageView *_glass;
    UILabel *_label;
}
@end

@implementation ExteriaClassicSearchFacadeView


- (id)initWithFrame:(CGRect)frame placeholder:(NSString *)placeholder {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.isAccessibilityElement = NO;
    _well = [[UIImageView alloc] initWithImage:ExteriaClassicSearchWell()];
    [self addSubview:_well];
    UIColor *ink = ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.82] : [UIColor colorWithWhite:0.42 alpha:1];
    _glass = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, FACADE_GLASS, ink)];
    [self addSubview:_glass];
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.font = [UIFont systemFontOfSize:15];
    _label.textColor = ink;
    _label.text = placeholder;
    [self addSubview:_label];
    return self;
}

- (void)dealloc {
    [_well release];
    [_glass release];
    [_label release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    /* the lit rim lies under the pill, so the pill proper is the well without its last point, and the word stands on the middle of that */
    CGFloat top = floor((size.height - FACADE_WELL_HEIGHT) / 2);
    _well.frame = CGRectMake(FACADE_SIDE, top, MAX(0, size.width - 2 * FACADE_SIDE), FACADE_WELL_HEIGHT);
    CGFloat pillHeight = FACADE_WELL_HEIGHT - FACADE_WELL_RIM;
    CGFloat left = _well.frame.origin.x + 10;
    _glass.frame = CGRectMake(left, top + floor((pillHeight - _glass.image.size.height) / 2), _glass.image.size.width, _glass.image.size.height);
    CGFloat textX = CGRectGetMaxX(_glass.frame) + 6;
    _label.frame = CGRectMake(textX, top, MAX(0, CGRectGetMaxX(_well.frame) - 10 - textX), pillHeight);
}

@end

UIView *ExteriaClassicSearchFacade(CGRect frame, NSString *placeholder) {
    ExteriaClassicSearchFacadeView *view = [[[ExteriaClassicSearchFacadeView alloc] initWithFrame:frame placeholder:placeholder] autorelease];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    return view;
}

/* the text of the pill: one line tall on the middle of the pill, for the typed words, the hint and the clear button alike */
@interface ExteriaClassicSearchTextField : UITextField
@end

@implementation ExteriaClassicSearchTextField

- (CGRect)lineRectForBounds:(CGRect)bounds {
    CGFloat line = ceil(self.font.lineHeight);
    return CGRectMake(0, floor((bounds.size.height - line) / 2), MAX(0, bounds.size.width - 22), line);
}

- (CGRect)textRectForBounds:(CGRect)bounds { return [self lineRectForBounds:bounds]; }
- (CGRect)editingRectForBounds:(CGRect)bounds { return [self lineRectForBounds:bounds]; }
- (CGRect)placeholderRectForBounds:(CGRect)bounds { return [self lineRectForBounds:bounds]; }

- (CGRect)clearButtonRectForBounds:(CGRect)bounds {
    return CGRectMake(bounds.size.width - 22, floor((bounds.size.height - 22) / 2), 22, 22);
}

- (void)drawPlaceholderInRect:(CGRect)rect {
    [[self.textColor colorWithAlphaComponent:0.6] set];
    ExteriaDrawStringIn(self.placeholder, self.font, rect, ExteriaStringTailTruncate, ExteriaTextAlignmentLeft);
}

@end

@implementation ExteriaClassicSearchInput

@synthesize changeHandler = _changeHandler;

- (id)initWithFrame:(CGRect)frame placeholder:(NSString *)placeholder {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _well = [[UIImageView alloc] initWithImage:ExteriaClassicSearchWell()];
    [self addSubview:_well];
    UIColor *ink = ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.82] : [UIColor colorWithWhite:0.42 alpha:1];
    _glass = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, FACADE_GLASS, ink)];
    [self addSubview:_glass];
    _field = [[ExteriaClassicSearchTextField alloc] init];
    _field.backgroundColor = [UIColor clearColor];
    _field.borderStyle = UITextBorderStyleNone;
    _field.font = [UIFont systemFontOfSize:15];
    _field.textColor = ExteriaThemeIsDark() ? [UIColor whiteColor] : [UIColor colorWithWhite:0.12 alpha:1];
    _field.placeholder = placeholder;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _field.returnKeyType = UIReturnKeySearch;
    _field.enablesReturnKeyAutomatically = YES;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.delegate = self;
    [_field addTarget:self action:@selector(edited) forControlEvents:UIControlEventEditingChanged];
    [self addSubview:_field];
    return self;
}

- (void)dealloc {
    _field.delegate = nil;
    [_well release];
    [_glass release];
    [_field release];
    [_changeHandler release];
    [super dealloc];
}

- (NSString *)text { return _field.text; }

- (void)setText:(NSString *)text {
    _field.text = text;
}

- (BOOL)becomeFirstResponder { return [_field becomeFirstResponder]; }
- (BOOL)resignFirstResponder { return [_field resignFirstResponder]; }

- (void)edited {
    if (_changeHandler) _changeHandler(_field.text);
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    field.text = @"";
    [self edited];
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat top = floor((size.height - FACADE_WELL_HEIGHT) / 2);
    _well.frame = CGRectMake(FACADE_SIDE, top, MAX(0, size.width - 2 * FACADE_SIDE), FACADE_WELL_HEIGHT);
    /* the lit rim lies under the pill, so the line is centered on the pill without it */
    CGFloat pillHeight = FACADE_WELL_HEIGHT - FACADE_WELL_RIM;
    _glass.frame = CGRectMake(FACADE_SIDE + 10, top + floor((pillHeight - _glass.image.size.height) / 2), _glass.image.size.width, _glass.image.size.height);
    CGFloat fieldX = CGRectGetMaxX(_glass.frame) + 6;
    _field.frame = CGRectMake(fieldX, top, MAX(0, CGRectGetMaxX(_well.frame) - 8 - fieldX), pillHeight);
}

@end

void ExteriaClassicStyleSegmented(UISegmentedControl *control) {
    if (!ExteriaClassicIsFlatSystem()) control.segmentedControlStyle = UISegmentedControlStyleBar;
    control.tintColor = ExteriaClassicIsFlatSystem() ? [UIColor whiteColor] : ExteriaClassicBarColor();
}

CGFloat ExteriaClassicTabBarHeight(void) {
    static CGFloat height = 0;
    if (height <= 0) {
        UITabBar *bar = [[UITabBar alloc] init];
        height = ceil([bar sizeThatFits:CGSizeZero].height);
        [bar release];
        if (height <= 0) height = 49;
    }
    return height;
}

void ExteriaClassicStyleTabBar(UITabBar *bar) {
    if (ExteriaClassicIsFlatSystem()) {
        [bar setValue:ExteriaClassicBarColor() forKey:@"barTintColor"];
        [bar setValue:[UIColor whiteColor] forKey:@"tintColor"];
        [bar setValue:[NSNumber numberWithBool:NO] forKey:@"translucent"];
    } else {
        [bar setTintColor:ExteriaClassicBarColor()];
        /* the selected glyph glows in white on the purple bar */
        [bar setSelectedImageTintColor:[UIColor whiteColor]];
    }
}

void ExteriaClassicStyleTable(UITableView *table) {
    if (![table.backgroundView isKindOfClass:[ExteriaWaveBackgroundView class]]) {
        ExteriaWaveBackgroundView *background = [[[ExteriaWaveBackgroundView alloc] initWithFrame:table.bounds] autorelease];
        background.plain = YES;
        background.userInteractionEnabled = YES;
        table.backgroundView = background;
    }
    if (!ExteriaThemeIsDark()) return;
    table.backgroundColor = ExteriaColorScreen();
    /* the etched line of a grouped table on ios 5 and 6 adds a white line under the dark one, which glows on the dark cards; a single faint line sits quietly between the rows and
       along the edge of each card */
    table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    table.separatorColor = [UIColor colorWithWhite:1 alpha:0.055];
}

CGFloat ExteriaClassicGroupedTextInset(CGFloat width) {
    if ([UITableView instancesRespondToSelector:@selector(setSeparatorInset:)]) return 10;
    if (width <= 400) return 20;
    return MAX(31, MIN(45, floor(width * 0.06f))) + 10;
}

@interface ExteriaClassicGroupedHeaderView : UIView {
    UILabel *_label;
}
- (id)initWithText:(NSString *)text frame:(CGRect)frame color:(UIColor *)color;
@end

@implementation ExteriaClassicGroupedHeaderView
- (id)initWithText:(NSString *)text frame:(CGRect)frame color:(UIColor *)color {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = color;
    _label.font = [UIFont boldSystemFontOfSize:17];
    _label.numberOfLines = 0;
    _label.text = text;
    if ([color isEqual:[UIColor whiteColor]]) {
        _label.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
        _label.shadowOffset = CGSizeMake(0, 1);
    }
    [self addSubview:_label];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat edge = ExteriaClassicGroupedTextInset(self.bounds.size.width);
    _label.frame = CGRectMake(edge, 0, MAX(0, self.bounds.size.width - 2 * edge), self.bounds.size.height);
}
- (void)dealloc {
    [_label release];
    [super dealloc];
}
@end

UIView *ExteriaClassicGroupedHeader(NSString *text, CGFloat width, CGFloat height, UIColor *color) {
    return [[[ExteriaClassicGroupedHeaderView alloc] initWithText:text frame:CGRectMake(0, 0, width, height) color:color] autorelease];
}

@interface ExteriaClassicGroupedFooterView : UIView {
    UILabel *_label;
}
- (id)initWithText:(NSString *)text frame:(CGRect)frame;
@end

@implementation ExteriaClassicGroupedFooterView
- (id)initWithText:(NSString *)text frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = ExteriaColorSecondary();
    _label.font = [UIFont systemFontOfSize:14];
    _label.numberOfLines = 0;
    _label.text = text;
    [self addSubview:_label];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat edge = ExteriaClassicGroupedTextInset(self.bounds.size.width);
    _label.frame = CGRectMake(edge, 6, MAX(0, self.bounds.size.width - 2 * edge), MAX(0, self.bounds.size.height - 12));
}
- (void)dealloc { [_label release]; [super dealloc]; }
@end

UIView *ExteriaClassicGroupedFooter(NSString *text, CGFloat width, CGFloat height) {
    return [[[ExteriaClassicGroupedFooterView alloc] initWithText:text frame:CGRectMake(0, 0, width, height)] autorelease];
}

UIColor *ExteriaClassicSelectionColor(void) {
    return ExteriaMixedColor(ExteriaColorField(), ExteriaColorAccent(), ExteriaThemeIsDark() ? 0.24 : 0.18);
}

void ExteriaClassicStyleCell(UITableViewCell *cell) {
    if (!ExteriaThemeIsDark()) return;
    cell.backgroundColor = ExteriaColorCard();
    cell.textLabel.textColor = ExteriaColorTitle();
    cell.detailTextLabel.textColor = ExteriaColorSecondary();
}

void ExteriaClassicStyleTabItem(UITabBarItem *item, ExteriaSymbol symbol) {
    UIColor *resting = ExteriaThemeTinted([UIColor colorWithRed:0.86 green:0.78 blue:0.96 alpha:1]);
    NSDictionary *restingText = [NSDictionary dictionaryWithObjectsAndKeys:resting, UITextAttributeTextColor,
                                 [UIColor clearColor], UITextAttributeTextShadowColor, nil];
    NSDictionary *selectedText = [NSDictionary dictionaryWithObjectsAndKeys:[UIColor whiteColor], UITextAttributeTextColor,
                                  [UIColor clearColor], UITextAttributeTextShadowColor, nil];
    [item setTitleTextAttributes:restingText forState:UIControlStateNormal];
    [item setTitleTextAttributes:selectedText forState:UIControlStateSelected];
    /* the resting glyph is drawn as given on ios 5, so it carries its own color; the template tint would turn it grey */
    if ([item respondsToSelector:@selector(setFinishedSelectedImage:withFinishedUnselectedImage:)]) {
        [item setFinishedSelectedImage:ExteriaSymbolImage(symbol, 28, [UIColor whiteColor])
           withFinishedUnselectedImage:ExteriaSymbolImage(symbol, 28, resting)];
    }
}

UIImage *ExteriaClassicTabImage(ExteriaSymbol symbol) {
    return ExteriaSymbolImage(symbol, 28, [UIColor blackColor]);
}

static UIImage *ExteriaClassicRoundImageMade(ExteriaSymbol symbol, CGFloat side, BOOL pressed, BOOL red);

static UIImage *ExteriaClassicRoundImage(ExteriaSymbol symbol, CGFloat side, BOOL pressed, BOOL red) {
    NSString *key = [NSString stringWithFormat:@"round|%d|%.1f|%d|%d", (int)symbol, side, pressed, red];
    return ExteriaClassicRemembered(key, ^UIImage *{ return ExteriaClassicRoundImageMade(symbol, side, pressed, red); });
}

static UIImage *ExteriaClassicRoundImageMade(ExteriaSymbol symbol, CGFloat side, BOOL pressed, BOOL red) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectMake(0.5, 0.5, side - 1, side - 1);
    CGFloat dim = pressed ? 0.78 : 1;
    CGFloat colors[] = {0.74 * dim, 0.58 * dim, 0.90 * dim, 1,
                        0.50 * dim, 0.30 * dim, 0.72 * dim, 1,
                        0.40 * dim, 0.20 * dim, 0.62 * dim, 1};
    if (red) {
        CGFloat redColors[] = {0.94 * dim, 0.42 * dim, 0.36 * dim, 1,
                               0.80 * dim, 0.18 * dim, 0.14 * dim, 1,
                               0.66 * dim, 0.10 * dim, 0.08 * dim, 1};
        memcpy(colors, redColors, sizeof(colors));
    }
    for (NSUInteger i = 0; !red && i < 3; ++i) {
        UIColor *tinted = ExteriaThemeTinted([UIColor colorWithRed:colors[i * 4] green:colors[i * 4 + 1] blue:colors[i * 4 + 2] alpha:1]);
        [tinted getRed:&colors[i * 4] green:&colors[i * 4 + 1] blue:&colors[i * 4 + 2] alpha:NULL];
    }
    CGFloat locations[] = {0, 0.5, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, locations, 3);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, bounds);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, side), 0);
    CGContextRestoreGState(context);
    /* the pale cap of the dome stands wholly inside the rim and fades towards its foot: an ellipse that ran past the rim was cut by it, and the cut showed as flat corners on the
       top of the circle */
    CGFloat capAlpha[] = {1, 1, 1, 0.34,  1, 1, 1, 0.02};
    CGGradientRef cap = CGGradientCreateWithColorComponents(space, capAlpha, NULL, 2);
    CGRect capRect = CGRectMake(side * 0.12, side * 0.06, side * 0.76, side * 0.46);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, capRect);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, cap, CGPointMake(0, capRect.origin.y), CGPointMake(0, CGRectGetMaxY(capRect)), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(cap);
    UIColor *outline = red ? [UIColor colorWithRed:0.40 green:0.04 blue:0.03 alpha:1]
                           : ExteriaThemeTinted([UIColor colorWithRed:0.26 green:0.12 blue:0.40 alpha:1]);
    CGContextSetStrokeColorWithColor(context, outline.CGColor);
    CGContextSetLineWidth(context, 1);
    CGContextStrokeEllipseInRect(context, bounds);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGFloat glyphSide = symbol == ExteriaSymbolSendArrow ? side * 0.5 : side * 0.58;
    UIImage *glyph = ExteriaSymbolImage(symbol, glyphSide, [UIColor whiteColor]);
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

UIImage *ExteriaClassicRoundButtonImage(ExteriaSymbol symbol, CGFloat side, BOOL pressed) {
    return ExteriaClassicRoundImage(symbol, side, pressed, NO);
}

UIImage *ExteriaClassicRedRoundButtonImage(ExteriaSymbol symbol, CGFloat side, BOOL pressed) {
    return ExteriaClassicRoundImage(symbol, side, pressed, YES);
}

UIImage *ExteriaClassicProfileTabImage(UIImage *photo) {
    CGSize size = CGSizeMake(30, 30);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    /* a profile photo comes as a jpeg, so a round picture arrives with white corners; a circle clip, as the modern tab has, takes them off */
    UIBezierPath *shape = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size.width, size.height)];
    CGContextSaveGState(context);
    [shape addClip];
    [photo drawInRect:CGRectMake(0, 0, size.width, size.height)];
    CGContextRestoreGState(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

UIView *ExteriaClassicTitleView(NSString *title, NSString *subtitle) {
    return ExteriaClassicTitleViewWithStatus(title, subtitle, 0);
}

UIView *ExteriaClassicTitleViewWithStatus(NSString *title, NSString *subtitle, int kind) {
    /* a tablet's bar has the room for a long name, and the 190 points of a phone cut it and its emoji short */
    return ExteriaClassicTitleViewWithStatusWidth(title, subtitle, kind, ExteriaIsPad() ? 420 : 190);
}

UIView *ExteriaClassicTitleViewWithStatusWidth(NSString *title, NSString *subtitle, int kind, CGFloat titleWidth) {
    BOOL flat = ExteriaClassicIsFlatSystem();
    UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, titleWidth, 44)] autorelease];
    view.backgroundColor = [UIColor clearColor];
    BOOL hasSubtitle = subtitle.length > 0;
    /* the title is a chat name, so its emoji come from the app's pictures; an old system font shows boxes for the newer ones */
    ExteriaEmojiLabel *top = [[[ExteriaEmojiLabel alloc] initWithFrame:CGRectMake(0, hasSubtitle ? 3 : 0, titleWidth, hasSubtitle ? 24 : 44)] autorelease];
    /* the system font of an old bar lacks the letters of a styled nick, and the bundled fallback shows them as boxes with a code in them: they are left out, as in every other name */
    top.dropsUndrawable = YES;
    top.text = title;
    top.textAlignment = ExteriaTextAlignmentCenter;
    top.font = [UIFont boldSystemFontOfSize:hasSubtitle ? 17 : 20];
    top.textColor = [UIColor whiteColor];
    top.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    /* the engraved shadow is part of the look of the old bars; the flat ones have none */
    if (!flat) {
        top.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
        top.shadowOffset = CGSizeMake(0, -1);
    }
    [view addSubview:top];
    if (hasSubtitle) {
        ExteriaStatusLabel *bottom = [[[ExteriaStatusLabel alloc] initWithFrame:CGRectMake(0, 25, titleWidth, 16)] autorelease];
        bottom.textAlignment = ExteriaTextAlignmentCenter;
        bottom.backgroundColor = [UIColor clearColor];
        bottom.font = [UIFont systemFontOfSize:12];
        bottom.plainColor = [UIColor colorWithWhite:0.92 alpha:1];
        bottom.activeColor = [UIColor colorWithRed:0.82 green:0.94 blue:1 alpha:1];
        [bottom setStatus:subtitle kind:(ExteriaStatusKind)kind];
        if (!flat) {
            bottom.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
            bottom.shadowOffset = CGSizeMake(0, -1);
        }
        bottom.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [view addSubview:bottom];
    }
    return view;
}

static UIImage *ExteriaClassicCounterImage(void) {
    static UIImage *cached;
    static CGFloat key[3];
    CGFloat rgb[3], alpha;
    [ExteriaColorAccent() getRed:&rgb[0] green:&rgb[1] blue:&rgb[2] alpha:&alpha];
    if (cached && key[0] == rgb[0] && key[1] == rgb[1] && key[2] == rgb[2]) return cached;
    const CGFloat side = 24, ring = 1.5;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect outer = CGRectMake(1, 0.5, side - 2, side - 3.5);
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0, 1.5), 2, [UIColor colorWithWhite:0 alpha:0.5].CGColor);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:outer cornerRadius:outer.size.height / 2] fill];
    CGContextRestoreGState(context);
    CGRect inner = CGRectInset(outer, ring, ring);
    UIBezierPath *face = [UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:inner.size.height / 2];
    CGContextSaveGState(context);
    [face addClip];
    CGFloat fill[] = {MIN(1, rgb[0] + (1 - rgb[0]) * 0.35), MIN(1, rgb[1] + (1 - rgb[1]) * 0.35), MIN(1, rgb[2] + (1 - rgb[2]) * 0.35), 1,
                      rgb[0], rgb[1], rgb[2], 1,
                      rgb[0] * 0.78, rgb[1] * 0.78, rgb[2] * 0.78, 1};
    CGFloat at[] = {0, 0.5, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, fill, at, 3);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, inner.origin.y), CGPointMake(0, CGRectGetMaxY(inner)), 0);
    CGFloat shine[] = {1, 1, 1, 0.55, 1, 1, 1, 0.08};
    CGGradientRef gloss = CGGradientCreateWithColorComponents(space, shine, NULL, 2);
    CGContextClipToRect(context, CGRectMake(0, inner.origin.y, side, inner.size.height * 0.5));
    CGContextDrawLinearGradient(context, gloss, CGPointMake(0, inner.origin.y), CGPointMake(0, inner.origin.y + inner.size.height * 0.5), 0);
    CGGradientRelease(gloss);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(context);
    [[UIColor colorWithRed:rgb[0] * 0.55 green:rgb[1] * 0.55 blue:rgb[2] * 0.55 alpha:1] setStroke];
    face.lineWidth = 0.5;
    [face stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [cached release];
    cached = [[image resizableImageWithCapInsets:UIEdgeInsetsMake(0, side / 2 - 1, 0, side / 2 - 1)] retain];
    for (int i = 0; i < 3; ++i) key[i] = rgb[i];
    return cached;
}

UIView *ExteriaClassicCounterBadge(NSString *text) {
    UIFont *font = [UIFont boldSystemFontOfSize:13];
    CGFloat width = MAX(24, ceil(ExteriaStringSize(text, font).width) + 16);
    UIImageView *badge = [[[UIImageView alloc] initWithImage:ExteriaClassicCounterImage()] autorelease];
    badge.frame = CGRectMake(0, 0, width, 24);
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(0, -1, width, 22)] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.text = text;
    label.font = font;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
    label.shadowOffset = CGSizeMake(0, -1);
    [badge addSubview:label];
    return badge;
}

/* the count of a row: a capsule in the accent, drawn as a stretched picture under the text. a layer with a corner radius and a mask is drawn off screen at every frame of a scroll, and a
   list has one of these on every row that has unread messages */
@interface ExteriaClassicBadgeLabel : UILabel {
    BOOL _muted;
}
@property (nonatomic, assign) BOOL muted;
@end

@implementation ExteriaClassicBadgeLabel
@synthesize muted = _muted;
- (void)drawRect:(CGRect)rect {
    UIColor *color = _muted ? [UIColor colorWithRed:0.62 green:0.66 blue:0.71 alpha:1] : ExteriaColorAccent();
    NSString *key = [NSString stringWithFormat:@"badge|%d", _muted];
    UIImage *capsule = ExteriaClassicRemembered(key, ^UIImage *{
        /* one point of stretch between the caps: with none, ios 6 leaves a seam down the middle of the capsule */
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(23, 22), NO, 0);
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 23, 22) cornerRadius:11] fill];
        UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return [made resizableImageWithCapInsets:UIEdgeInsetsMake(0, 11, 0, 11)];
    });
    [capsule drawInRect:self.bounds];
    [super drawRect:rect];
}
@end

UILabel *ExteriaClassicBadge(NSString *text, BOOL muted) {
    UIFont *font = [UIFont boldSystemFontOfSize:13];
    CGFloat width = MAX(22, ceil(ExteriaStringSize(text, font).width) + 14);
    ExteriaClassicBadgeLabel *label = [[[ExteriaClassicBadgeLabel alloc] initWithFrame:CGRectMake(0, 0, width, 22)] autorelease];
    label.muted = muted;
    label.text = text;
    label.font = font;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.backgroundColor = [UIColor clearColor];
    label.opaque = NO;
    return label;
}

/* one image for the glossy things: a rounded rect with a three stop fill, an outline, a lit line just inside the
   top and, for a button */
static UIImage *ExteriaClassicGlossImageMade(const CGFloat *fill, const CGFloat *outline, CGFloat radius, CGFloat gloss, CGFloat lit);

static UIImage *ExteriaClassicGlossImage(const CGFloat *fill, const CGFloat *outline, CGFloat radius, CGFloat gloss, CGFloat lit) {
    NSMutableString *key = [NSMutableString stringWithFormat:@"gloss|%.1f|%.3f|%.3f", radius, gloss, lit];
    for (int i = 0; i < 12; ++i) [key appendFormat:@"|%.3f", fill[i]];
    for (int i = 0; i < 3; ++i) [key appendFormat:@"|%.3f", outline[i]];
    return ExteriaClassicRemembered(key, ^UIImage *{ return ExteriaClassicGlossImageMade(fill, outline, radius, gloss, lit); });
}

static UIImage *ExteriaClassicGlossImageMade(const CGFloat *fill, const CGFloat *outline, CGFloat radius, CGFloat gloss, CGFloat lit) {
    CGFloat side = radius * 2 + 4;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectMake(0.5, 0.5, side - 1, side - 1);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius];
    CGFloat locations[] = {0, 0.5, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, fill, locations, 3);
    CGContextSaveGState(context);
    [shape addClip];
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, side), 0);
    if (gloss > 0) {
        /* the cap fades out by the middle of the picture, where it used to stop at a quarter of its strength: that edge ran across every button and plate as a band */
        CGFloat shine[] = {1, 1, 1, gloss, 1, 1, 1, 0};
        CGGradientRef cap = CGGradientCreateWithColorComponents(space, shine, NULL, 2);
        CGContextClipToRect(context, CGRectMake(0, 0, side, side / 2));
        CGContextDrawLinearGradient(context, cap, CGPointMake(0, 0), CGPointMake(0, side / 2), 0);
        CGGradientRelease(cap);
    }
    if (gloss > 0) {
        /* metal: a faint light bouncing up from the lower edge, and a thin specular streak that fades out toward the ends of the upper half */
        CGFloat bounce[] = {1, 1, 1, 0, 1, 1, 1, gloss * 0.35};
        CGGradientRef lower = CGGradientCreateWithColorComponents(space, bounce, NULL, 2);
        CGContextSaveGState(context);
        CGContextClipToRect(context, CGRectMake(0, side * 0.72, side, side * 0.28));
        CGContextDrawLinearGradient(context, lower, CGPointMake(0, side * 0.72), CGPointMake(0, side), 0);
        CGContextRestoreGState(context);
        CGGradientRelease(lower);
        CGFloat streak[] = {1, 1, 1, 0, 1, 1, 1, gloss * 0.9, 1, 1, 1, 0};
        CGFloat streakAt[] = {0, 0.5, 1};
        CGGradientRef across = CGGradientCreateWithColorComponents(space, streak, streakAt, 3);
        CGContextSaveGState(context);
        CGContextClipToRect(context, CGRectMake(radius * 0.6, 2, side - radius * 1.2, 1));
        CGContextDrawLinearGradient(context, across, CGPointMake(radius * 0.6, 0), CGPointMake(side - radius * 0.6, 0), 0);
        CGContextRestoreGState(context);
        CGGradientRelease(across);
    }
    CGContextRestoreGState(context);
    if (lit > 0) {
        CGContextSaveGState(context);
        CGContextClipToRect(context, CGRectMake(0, 0, side, radius));
        [[UIColor colorWithWhite:1 alpha:lit] setStroke];
        UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, 1, 1) cornerRadius:MAX(0, radius - 1)];
        rim.lineWidth = 1;
        [rim stroke];
        CGContextRestoreGState(context);
    }
    [[UIColor colorWithRed:outline[0] green:outline[1] blue:outline[2] alpha:1] setStroke];
    shape.lineWidth = 1;
    [shape stroke];
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGFloat cap = side / 2 - 1;
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap)];
}

UIImage *ExteriaClassicBarButtonImage(BOOL pressed) {
    UIColor *base = ExteriaClassicBarColor();
    UIColor *colors[] = {
        ExteriaMixedColor(base, [UIColor whiteColor], pressed ? 0.02 : 0.15),
        ExteriaMixedColor(base, [UIColor blackColor], pressed ? 0.32 : 0.18),
        ExteriaMixedColor(base, [UIColor blackColor], pressed ? 0.48 : 0.35)
    };
    CGFloat fill[12];
    for (int i = 0; i < 3; ++i) {
        const CGFloat *components = CGColorGetComponents(colors[i].CGColor);
        for (int j = 0; j < 3; ++j) fill[i * 4 + j] = components[j];
        fill[i * 4 + 3] = 1;
    }
    UIColor *border = ExteriaMixedColor(base, [UIColor blackColor], 0.65);
    const CGFloat *components = CGColorGetComponents(border.CGColor);
    CGFloat outline[] = {components[0], components[1], components[2]};
    return ExteriaClassicGlossImage(fill, outline, 6, pressed ? 0.08 : 0.20, 0.30);
}

/* a purple of the classic chrome with the hue of the theme, as three components */
static void ExteriaTintedRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat out[3]) {
    const CGFloat *c = CGColorGetComponents(ExteriaThemeTinted([UIColor colorWithRed:red green:green blue:blue alpha:1]).CGColor);
    out[0] = c[0];
    out[1] = c[1];
    out[2] = c[2];
}

UIImage *ExteriaClassicGlossButtonImage(ExteriaClassicGloss color, BOOL pressed) {
    CGFloat dim = pressed ? 0.78 : 1;
    if (color == ExteriaClassicGlossGreen) {
        CGFloat fill[] = {0.52 * dim, 0.80 * dim, 0.36 * dim, 1,
                          0.30 * dim, 0.62 * dim, 0.20 * dim, 1,
                          0.20 * dim, 0.50 * dim, 0.14 * dim, 1};
        CGFloat outline[] = {0.10, 0.30, 0.06};
        return ExteriaClassicGlossImage(fill, outline, 8, pressed ? 0.12 : 0.34, 0.45);
    }
    if (color == ExteriaClassicGlossSlate) {
        /* the purple plate of the app: it takes the hue the wallpaper gave the theme */
        CGFloat fill[12];
        const CGFloat purple[3][3] = {{0.64, 0.59, 0.74}, {0.43, 0.37, 0.56}, {0.33, 0.27, 0.46}};
        for (int i = 0; i < 3; ++i) {
            ExteriaTintedRGB(purple[i][0] * dim, purple[i][1] * dim, purple[i][2] * dim, fill + i * 4);
            fill[i * 4 + 3] = 1;
        }
        CGFloat outline[3];
        ExteriaTintedRGB(0.16, 0.11, 0.25, outline);
        return ExteriaClassicGlossImage(fill, outline, 8, pressed ? 0.10 : 0.30, 0.40);
    }
    if (color == ExteriaClassicGlossAmber) {
        CGFloat fill[] = {1.00 * dim, 0.87 * dim, 0.46 * dim, 1,
                          0.97 * dim, 0.70 * dim, 0.20 * dim, 1,
                          0.88 * dim, 0.55 * dim, 0.08 * dim, 1};
        CGFloat outline[] = {0.48, 0.29, 0.02};
        return ExteriaClassicGlossImage(fill, outline, 8, pressed ? 0.12 : 0.34, 0.50);
    }
    CGFloat fill[] = {0.94 * dim, 0.42 * dim, 0.36 * dim, 1,
                      0.80 * dim, 0.18 * dim, 0.14 * dim, 1,
                      0.66 * dim, 0.10 * dim, 0.08 * dim, 1};
    CGFloat outline[] = {0.40, 0.04, 0.03};
    return ExteriaClassicGlossImage(fill, outline, 8, pressed ? 0.12 : 0.34, 0.45);
}

UIImage *ExteriaClassicPlateImage(void) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [ExteriaColorCard() getRed:&r green:&g blue:&b alpha:&a];
    CGFloat fill[] = {MIN(1, r + 0.06), MIN(1, g + 0.06), MIN(1, b + 0.06), 1,
                      r, g, b, 1,
                      r * 0.92, g * 0.92, b * 0.92, 1};
    CGFloat outline[] = {r * 0.65, g * 0.65, b * 0.65};
    return ExteriaClassicGlossImage(fill, outline, 12, 0, ExteriaThemeIsDark() ? 0.15 : 0.55);
}

void ExteriaClassicApplyMenuPlate(UIView *view, CGFloat radius) {
    BOOL charcoal = ExteriaThemeIsDark();
    view.layer.cornerRadius = radius;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = charcoal ? 0.6 : 0.35;
    view.layer.shadowRadius = 10;
    view.layer.shadowOffset = CGSizeMake(0, 4);
    /* a plate of polished metal: the upper half is lit and fades out by the middle, light bounces up from the lower edge, a streak runs under the top edge, and the rim is a dark line over a
       lit one. it is one stretchable picture, so a card of any size keeps its corners and its rim */
    static const CGFloat paleFill[] = {1.00, 1.00, 1.00, 1, 0.95, 0.95, 0.96, 1, 0.88, 0.88, 0.90, 1};
    static const CGFloat charcoalFill[] = {0.38, 0.38, 0.42, 1, 0.18, 0.18, 0.21, 1, 0.09, 0.09, 0.11, 1};
    static const CGFloat paleRim[] = {0.60, 0.60, 0.64};
    static const CGFloat charcoalRim[] = {0.52, 0.52, 0.57};
    UIImage *picture = ExteriaClassicGlossImage(charcoal ? charcoalFill : paleFill, charcoal ? charcoalRim : paleRim, radius, charcoal ? 0.22 : 0.30, charcoal ? 0.38 : 0.70);
    CALayer *gloss = [CALayer layer];
    gloss.contents = (id)picture.CGImage;
    gloss.contentsScale = picture.scale;
    CGFloat side = radius * 2 + 4, cap = side / 2 - 1;
    gloss.contentsCenter = CGRectMake(cap / side, cap / side, 2 / side, 2 / side);
    gloss.name = @"plate";
    gloss.frame = view.bounds;
    [view.layer insertSublayer:gloss atIndex:0];
    ExteriaClassicFitPlate(view, 0);
}

void ExteriaClassicFitPlate(UIView *view, CGFloat bleed) {
    CGRect bounds = view.bounds;
    if (CGRectIsEmpty(bounds)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"plate"]) layer.frame = CGRectMake(0, 0, bounds.size.width, bounds.size.height + bleed);
    }
    CGPathRef path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:view.layer.cornerRadius].CGPath;
    if (!view.layer.shadowPath || !CGPathEqualToPath(view.layer.shadowPath, path)) view.layer.shadowPath = path;
    [CATransaction commit];
}

UIColor *ExteriaClassicMenuTextColor(void) {
    return ExteriaThemeIsDark() ? [UIColor whiteColor] : ExteriaColorTitle();
}

UIColor *ExteriaClassicMenuRedColor(void) {
    return ExteriaThemeIsDark() ? [UIColor colorWithRed:1 green:0.45 blue:0.40 alpha:1] : ExteriaColorBadgeRed();
}

UIColor *ExteriaClassicMenuPressColor(void) {
    return ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.14] : [UIColor colorWithWhite:0 alpha:0.08];
}

void ExteriaClassicStyleMenuLabel(UILabel *label, CGFloat size) {
    label.font = [UIFont boldSystemFontOfSize:size];
    if (ExteriaThemeIsDark()) {
        label.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
        label.shadowOffset = CGSizeMake(0, -1);
    } else {
        label.shadowColor = [UIColor colorWithWhite:1 alpha:0.8];
        label.shadowOffset = CGSizeMake(0, 1);
    }
}

/* the white (or dark gray) box of the classic bar with a good share of the accent mixed in (a third on the dark theme, a quarter on the light one), so it reads as the color of the
   theme and not as grey; opaque since the emoji of the text are drawn over it. more than this takes the placeholder, which is the muted ink, down to the fill */
UIColor *ExteriaClassicInputFill(void) {
    UIColor *base = ExteriaThemeIsDark() ? [UIColor colorWithWhite:0.23 alpha:1] : [UIColor whiteColor];
    CGFloat br, bg, bb, ba, ar, ag, ab, aa;
    if (![base getRed:&br green:&bg blue:&bb alpha:&ba]) {
        CGFloat white = 0;
        if (![base getWhite:&white alpha:&ba]) return base;
        br = bg = bb = white;
    }
    if (![ExteriaColorAccent() getRed:&ar green:&ag blue:&ab alpha:&aa]) return base;
    CGFloat share = ExteriaThemeIsDark() ? 0.34 : 0.26;
    return [UIColor colorWithRed:br * (1 - share) + ar * share green:bg * (1 - share) + ag * share blue:bb * (1 - share) + ab * share alpha:1];
}

UIImage *ExteriaClassicTintedGlossImage(UIColor *base, CGFloat radius, BOOL pressed) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![base getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [base getWhite:&white alpha:&a];
        r = g = b = white;
    }
    CGFloat dim = pressed ? 0.8 : 1;
    CGFloat fill[] = {MIN(1, r + (1 - r) * 0.30) * dim, MIN(1, g + (1 - g) * 0.30) * dim, MIN(1, b + (1 - b) * 0.30) * dim, 1,
                      r * dim, g * dim, b * dim, 1,
                      r * 0.74 * dim, g * 0.74 * dim, b * 0.74 * dim, 1};
    CGFloat outline[] = {r * 0.45, g * 0.45, b * 0.45};
    return ExteriaClassicGlossImage(fill, outline, radius, pressed ? 0.12 : 0.34, 0.45);
}

UIImage *ExteriaClassicGroundKeyImage(UIColor *ground, BOOL pressed) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![ground getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [ground getWhite:&white alpha:&a];
        r = g = b = white;
    }
    CGFloat dim = pressed ? 0.78 : 1;
    CGFloat fill[] = {MIN(1, r * 1.12 + 0.04) * dim, MIN(1, g * 1.12 + 0.04) * dim, MIN(1, b * 1.12 + 0.04) * dim, 1,
                      r * dim, g * dim, b * dim, 1,
                      r * 0.84 * dim, g * 0.84 * dim, b * 0.84 * dim, 1};
    CGFloat outline[] = {r * 0.55, g * 0.55, b * 0.55};
    return ExteriaClassicGlossImage(fill, outline, 8, 0, 0);
}

UIColor *ExteriaClassicStripGround(void) {
    /* a dark grey or white with a little of the accent in it, so the strips read as part of the theme and not as holes: the first version was near black */
    BOOL dark = ExteriaThemeIsDark();
    return ExteriaMixedColor(dark ? [UIColor colorWithWhite:0.17 alpha:1] : [UIColor whiteColor], ExteriaColorAccent(), dark ? 0.16 : 0.07);
}
UIColor *ExteriaClassicStripInk(void) { return ExteriaThemeIsDark() ? [UIColor whiteColor] : [UIColor colorWithWhite:0.1 alpha:1]; }
UIColor *ExteriaClassicStripEdge(void) { return ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.16] : [UIColor colorWithWhite:0 alpha:0.22]; }

UIImageView *ExteriaClassicStripBackdrop(void) {
    UIImageView *view = [[[UIImageView alloc] initWithImage:ExteriaClassicBarImage()] autorelease];
    view.contentMode = UIViewContentModeScaleToFill;
    view.userInteractionEnabled = NO;
    return view;
}

/* the face of the disc in a chrome rim: a brushed metal gradient on the outside, a darker bevel before the face,
   an inner shadow where the face sits low and a soft gloss over the upper half */
UIImage *ExteriaClassicMetalDisc(UIImage *face, CGFloat side) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat rim = side * 0.1;
    CGRect outer = CGRectMake(0.5, 0.5, side - 1, side - 1);
    CGRect bevel = CGRectInset(outer, rim * 0.8, rim * 0.8);
    CGRect inner = CGRectInset(outer, rim, rim);
    CGPoint topLeft = CGPointMake(0, 0), bottomRight = CGPointMake(side, side);

    static const CGFloat chrome[] = {0.96, 0.96, 0.97, 1,  0.72, 0.73, 0.76, 1,  0.43, 0.44, 0.48, 1,  0.82, 0.83, 0.86, 1,
                                     0.55, 0.56, 0.60, 1,  0.94, 0.95, 0.96, 1};
    static const CGFloat chromeAt[] = {0, 0.22, 0.45, 0.62, 0.82, 1};
    CGGradientRef metal = CGGradientCreateWithColorComponents(space, chrome, chromeAt, 6);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, outer);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, metal, topLeft, bottomRight, 0);
    CGContextRestoreGState(context);
    CGGradientRelease(metal);

    /* the bevel runs the other way, so the rim looks turned in towards the face */
    static const CGFloat turned[] = {0.35, 0.36, 0.40, 1,  0.93, 0.94, 0.96, 1};
    CGGradientRef bevelGradient = CGGradientCreateWithColorComponents(space, turned, NULL, 2);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, bevel);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, bevelGradient, topLeft, bottomRight, 0);
    CGContextRestoreGState(context);
    CGGradientRelease(bevelGradient);

    CGContextSetRGBStrokeColor(context, 0.25, 0.26, 0.30, 0.85);
    CGContextSetLineWidth(context, 1);
    CGContextStrokeEllipseInRect(context, outer);

    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, inner);
    CGContextClip(context);
    if (face) {
        CGFloat scale = MAX(inner.size.width / face.size.width, inner.size.height / face.size.height);
        CGSize drawn = CGSizeMake(face.size.width * scale, face.size.height * scale);
        [face drawInRect:CGRectMake(CGRectGetMidX(inner) - drawn.width / 2, CGRectGetMidY(inner) - drawn.height / 2, drawn.width, drawn.height)];
    }
    /* a soft shadow on the upper edge of the face, where the rim stands over it */
    static const CGFloat shade[] = {0, 0, 0, 0.35,  0, 0, 0, 0};
    CGGradientRef shadow = CGGradientCreateWithColorComponents(space, shade, NULL, 2);
    CGContextDrawLinearGradient(context, shadow, CGPointMake(0, inner.origin.y), CGPointMake(0, inner.origin.y + inner.size.height * 0.28), 0);
    CGGradientRelease(shadow);
    CGContextRestoreGState(context);
    CGContextSetRGBStrokeColor(context, 0.12, 0.12, 0.16, 0.7);
    CGContextStrokeEllipseInRect(context, inner);

    /* the gloss: white fading out over the upper half of the whole disc */
    static const CGFloat gloss[] = {1, 1, 1, 0.34,  1, 1, 1, 0};
    CGGradientRef shine = CGGradientCreateWithColorComponents(space, gloss, NULL, 2);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(side * 0.06, side * 0.02, side * 0.88, side * 0.55));
    CGContextClip(context);
    CGContextDrawLinearGradient(context, shine, CGPointMake(0, side * 0.02), CGPointMake(0, side * 0.57), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(shine);
    CGColorSpaceRelease(space);
    UIImage *disc = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return disc;
}
