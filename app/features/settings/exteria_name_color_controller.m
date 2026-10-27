#import "exteria_name_color_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_gift_screen.h"
#import "exteria_peer_colors.h"
#import "exteria_person.h"
#import "exteria_session_namecolor.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define SWATCH 44.0
#define SWATCH_GAP 14.0
#define GRID_PAD 18.0

/* the preview: a bubble with a quoted reply in the chosen color, over the colors of the chat */
@interface ExteriaNameColorPreview : UIView {
    UIView *_bubble;
    UIView *_quote;
    UIView *_bar;
    ExteriaEmojiLabel *_name;
    ExteriaEmojiLabel *_text;
}
- (void)setName:(NSString *)name color:(UIColor *)color;
@end

@implementation ExteriaNameColorPreview

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorChatBackground();
    self.layer.cornerRadius = 22;
    self.layer.masksToBounds = YES;
    /* clipped once, and kept while the page scrolls */
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.accessibilityElementsHidden = YES;
    _bubble = [[UIView alloc] init];
    _bubble.backgroundColor = ExteriaColorBubbleIn();
    _bubble.layer.cornerRadius = 17;
    [self addSubview:_bubble];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.font = ExteriaFontSemibold(15);
    [_bubble addSubview:_name];
    _quote = [[UIView alloc] init];
    _quote.layer.cornerRadius = 6;
    [_bubble addSubview:_quote];
    _bar = [[UIView alloc] init];
    [_quote addSubview:_bar];
    _text = [[ExteriaEmojiLabel alloc] init];
    _text.font = ExteriaFontRegular(15);
    _text.numberOfLines = 2;
    _text.textColor = ExteriaColorBubbleText(NO);
    _text.text = NSLocalizedString(@"namecolor.preview", nil);
    [_quote addSubview:_text];
    return self;
}

- (void)dealloc {
    [_bubble release];
    [_quote release];
    [_bar release];
    [_name release];
    [_text release];
    [super dealloc];
}

- (void)setName:(NSString *)name color:(UIColor *)color {
    _name.text = name;
    _name.textColor = color;
    _bar.backgroundColor = color;
    _quote.backgroundColor = [color colorWithAlphaComponent:0.14];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat bubbleWidth = MIN(width - 32, 260), bubbleHeight = 112;
    _bubble.frame = CGRectMake(16, floor((height - bubbleHeight) / 2), bubbleWidth, bubbleHeight);
    _name.frame = CGRectMake(14, 10, bubbleWidth - 28, 20);
    _quote.frame = CGRectMake(14, 36, bubbleWidth - 28, 60);
    _bar.frame = CGRectMake(0, 0, 3, 60);
    _text.frame = CGRectMake(12, 8, bubbleWidth - 28 - 20, 44);
}

@end

/* the colors as circles in rows, the chosen one ringed and ticked, a locked one with a padlock */
@interface ExteriaNameColorGrid : UIView {
    NSArray *_items;
    NSMutableArray *_swatches;
    NSInteger _chosenId;
    void (^_chooseHandler)(NSDictionary *item);
}
@property (nonatomic, copy) void (^chooseHandler)(NSDictionary *item);
/* each item is a dictionary with id (NSNumber), color (UIColor) and locked (NSNumber) */
- (void)setItems:(NSArray *)items chosenId:(NSInteger)chosenId;
+ (CGFloat)heightForCount:(NSUInteger)count width:(CGFloat)width;
@end

@implementation ExteriaNameColorGrid

@synthesize chooseHandler = _chooseHandler;

static NSUInteger ExteriaSwatchColumns(CGFloat width) {
    return MAX(4, (NSUInteger)floor((width - 2 * GRID_PAD + SWATCH_GAP) / (SWATCH + SWATCH_GAP)));
}

+ (CGFloat)heightForCount:(NSUInteger)count width:(CGFloat)width {
    NSUInteger columns = ExteriaSwatchColumns(width), rows = MAX(1, (count + columns - 1) / columns);
    return 2 * GRID_PAD + (CGFloat)rows * SWATCH + (CGFloat)(rows - 1) * SWATCH_GAP;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 22;
    self.layer.masksToBounds = YES;
    /* clipped once, and kept while the page scrolls */
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    _swatches = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_items release];
    [_swatches release];
    [_chooseHandler release];
    [super dealloc];
}

- (void)setItems:(NSArray *)items chosenId:(NSInteger)chosenId {
    [_items release];
    _items = [items retain];
    _chosenId = chosenId;
    for (UIView *old in _swatches) [old removeFromSuperview];
    [_swatches removeAllObjects];
    for (NSUInteger i = 0; i < items.count; ++i) {
        NSDictionary *item = [items objectAtIndex:i];
        UIControl *swatch = [[[UIControl alloc] init] autorelease];
        swatch.tag = (NSInteger)i;
        swatch.backgroundColor = [item objectForKey:@"color"];
        swatch.layer.cornerRadius = SWATCH / 2;
        BOOL chosen = [[item objectForKey:@"id"] integerValue] == chosenId;
        BOOL locked = [[item objectForKey:@"locked"] boolValue];
        if (chosen) {
            swatch.layer.borderWidth = 3;
            swatch.layer.borderColor = ExteriaColorTitle().CGColor;
        }
        if (chosen || locked) {
            UIImageView *mark = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(chosen ? ExteriaSymbolCheck : ExteriaSymbolLock, 22, [UIColor whiteColor])] autorelease];
            mark.contentMode = UIViewContentModeCenter;
            mark.frame = CGRectMake(0, 0, SWATCH, SWATCH);
            mark.userInteractionEnabled = NO;
            [swatch addSubview:mark];
        }
        [swatch addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        swatch.accessibilityLabel = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
        swatch.accessibilityTraits = chosen ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
        [self addSubview:swatch];
        [_swatches addObject:swatch];
    }
    [self setNeedsLayout];
}

- (void)tapped:(UIControl *)swatch {
    if ((NSUInteger)swatch.tag < _items.count && _chooseHandler) _chooseHandler([_items objectAtIndex:(NSUInteger)swatch.tag]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger columns = ExteriaSwatchColumns(self.bounds.size.width);
    CGFloat used = (CGFloat)columns * SWATCH + (CGFloat)(columns - 1) * SWATCH_GAP;
    CGFloat left = floor((self.bounds.size.width - used) / 2);
    for (UIControl *swatch in _swatches) {
        NSUInteger i = (NSUInteger)swatch.tag;
        swatch.frame = CGRectMake(left + (CGFloat)(i % columns) * (SWATCH + SWATCH_GAP), GRID_PAD + (CGFloat)(i / columns) * (SWATCH + SWATCH_GAP), SWATCH, SWATCH);
    }
}

@end

@interface ExteriaNameColorController () {
    ExteriaSession *_session;
    ExteriaPerson *_person;
    ExteriaWeakReference *_weak;
    ExteriaNameColorPreview *_preview;
    ExteriaNameColorGrid *_grid;
    NSInteger _colorId;
    BOOL _busy;
    void (^_changedHandler)(NSInteger colorId);
}
@end

@implementation ExteriaNameColorController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _person = [person retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _colorId = person.nameColor >= 0 ? person.nameColor : ExteriaDefaultNameColorId(person.userId);
    self.pageTitle = NSLocalizedString(@"chatset.namecolor", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_person release];
    [_preview release];
    [_grid release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _preview = [[ExteriaNameColorPreview alloc] init];
    _grid = [[ExteriaNameColorGrid alloc] init];
    ExteriaWeakReference *weak = _weak;
    _grid.chooseHandler = ^(NSDictionary *item) { [(ExteriaNameColorController *)weak.target choose:item]; };
    [self rebuild];
    /* the list of the server may have changed since it was kept */
    [_session loadNameColors:^(NSArray *colors, NSString *errorName) {
        ExteriaNameColorController *me = weak.target;
        if (!me) return;
        if (errorName) NSLog(@"exteria: the name colors did not load: %@", errorName);
        [me rebuild];
    }];
}

/* the colors on offer: the seven built in, then the ones of the server that are in the list (a hidden one only while it is in use) */
- (NSArray *)items {
    BOOL dark = ExteriaThemeIsDark();
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < ExteriaBuiltInNameColorCount(); ++i) {
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:i], @"id", ExteriaNameColor((NSInteger)i, 0, dark), @"color",
                          [NSNumber numberWithBool:NO], @"locked", nil]];
    }
    for (NSDictionary *option in ExteriaServerNameColors()) {
        NSInteger colorId = [[option objectForKey:@"id"] integerValue];
        if (colorId < (NSInteger)ExteriaBuiltInNameColorCount()) continue;
        if ([[option objectForKey:@"hidden"] boolValue] && colorId != _colorId) continue;
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:colorId], @"id", ExteriaNameColor(colorId, 0, dark), @"color",
                          [NSNumber numberWithBool:!_person.premium], @"locked", nil]];
    }
    return items;
}

- (void)rebuild {
    NSArray *items = [self items];
    [_grid setItems:items chosenId:_colorId];
    [_preview setName:_person.name.length ? _person.name : @"" color:ExteriaNameColor(_colorId, _person.userId, ExteriaThemeIsDark())];
    ExteriaNameColorPreview *preview = _preview;
    ExteriaNameColorGrid *grid = _grid;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
        [ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { (void)width; return 164; }]]]];
    NSUInteger count = items.count;
    ExteriaSettingsRow *colors = [ExteriaSettingsRow viewRowWithView:grid height:^CGFloat(CGFloat width) { return [ExteriaNameColorGrid heightForCount:count width:width]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.namecolor.header", nil) footer:NSLocalizedString(@"chatset.namecolor.info", nil)
                                                              rows:[NSArray arrayWithObject:colors]]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)choose:(NSDictionary *)item {
    NSInteger colorId = [[item objectForKey:@"id"] integerValue];
    if (colorId == _colorId || _busy) return;
    if ([[item objectForKey:@"locked"] boolValue]) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"chatset.namecolor.premium", nil));
        return;
    }
    _busy = YES;
    NSInteger before = _colorId;
    _colorId = colorId;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session setNameColorId:colorId completion:^(NSString *errorName) {
        ExteriaNameColorController *me = weak.target;
        if (!me) return;
        me->_busy = NO;
        if (errorName && ![errorName isEqualToString:@"NOT_MODIFIED"]) {
            NSLog(@"exteria: setting the name color failed: %@", errorName);
            me->_colorId = before;
            ExteriaGiftAlert(nil, [errorName isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"] ? NSLocalizedString(@"chatset.namecolor.premium", nil) : ExteriaGiftErrorText(errorName));
            [me rebuild];
            return;
        }
        if (me->_changedHandler) me->_changedHandler(colorId);
    }];
}

@end
