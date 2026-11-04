#import "exteria_cleaning.h"
#import "exteria_memory_controller.h"

#import "exteria_cache_kind.h"
#import "exteria_chat_settings.h"
#import "exteria_donut_view.h"
#import "exteria_sheet.h"
#import "exteria_storage_card_view.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

/* the bytes the way the cache screen writes them, with the separator of the language: 2,86 GB, 389,2 MB, 12 KB */
static NSString *ExteriaMemorySize(unsigned long long bytes, int gigabyteDecimals) {
    if (!bytes) return NSLocalizedString(@"settings.cache.empty", nil);
    if (bytes >= 1024ull * 1024ull * 1024ull) return [NSString localizedStringWithFormat:@"%.*f GB", gigabyteDecimals, (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    if (bytes >= 1024ull * 1024ull) return [NSString localizedStringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    return [NSString localizedStringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
}

/* the number and the unit apart, for the middle of the ring */
static void ExteriaMemoryParts(unsigned long long bytes, NSString **amount, NSString **unit) {
    NSString *whole = bytes ? ExteriaMemorySize(bytes, 1) : @"0 KB";
    NSRange space = [whole rangeOfString:@" " options:NSBackwardsSearch];
    *amount = space.location == NSNotFound ? whole : [whole substringToIndex:space.location];
    *unit = space.location == NSNotFound ? @"" : [whole substringFromIndex:space.location + 1];
}

/* the kinds as the screen lists them: the five of the media cache, and the photos of people, which live in a cache of their own */
enum { ExteriaStorageAvatars = EXTERIA_CACHE_KIND_COUNT, ExteriaStorageKinds };

static const int ExteriaStorageOrder[] = {EXTERIA_CACHE_VIDEO, EXTERIA_CACHE_PHOTO, EXTERIA_CACHE_MUSIC, EXTERIA_CACHE_STICKER, ExteriaStorageAvatars, EXTERIA_CACHE_OTHER};
static NSString *const ExteriaStorageTitles[ExteriaStorageKinds] = {
    @"memory.kind.video", @"memory.kind.photo", @"memory.kind.music", @"memory.kind.stickers", @"memory.kind.other", @"memory.avatars"};
static const uint32_t ExteriaStorageColors[ExteriaStorageKinds] = {0x4DA3FF, 0x2F6FE4, 0x9362E8, 0xF58A3C, 0xF2B632, 0x35B8A6};

#define HEADER_PAD 14.0
#define DONUT_SIDE 176.0

/* the days a file stays: zero is as long as the cache has room */
static const NSInteger ExteriaKeepChoices[] = {3, 7, 30, 0};
static NSString *const ExteriaKeepTitles[] = {@"memory.keep.3", @"memory.keep.7", @"memory.keep.30", @"memory.keep.forever"};

@interface ExteriaMemoryController () {
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    unsigned long long _bytes[ExteriaStorageKinds];
    BOOL _selected[ExteriaStorageKinds];
    BOOL _loaded;
    /* a scan that was started before the screen was rebuilt must not fill the new one */
    NSUInteger _scan;
    UIView *_header;
    ExteriaDonutView *_donut;
    UILabel *_headline;
    UILabel *_subtitle;
    ExteriaStorageCardView *_card;
}
@end

@implementation ExteriaMemoryController

- (id)initWithAvatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    for (int i = 0; i < ExteriaStorageKinds; ++i) _selected[i] = YES;
    self.pageTitle = NSLocalizedString(@"memory.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_avatars release];
    [_media release];
    [_header release];
    [_donut release];
    [_headline release];
    [_subtitle release];
    [_card release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaMemoryController alloc] initWithAvatars:_avatars media:_media] autorelease];
}

/* the kinds that hold something, in the order of the screen */
- (NSArray *)shownKinds {
    NSMutableArray *kinds = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(ExteriaStorageOrder) / sizeof(ExteriaStorageOrder[0]); ++i) {
        if (_bytes[ExteriaStorageOrder[i]]) [kinds addObject:[NSNumber numberWithInt:ExteriaStorageOrder[i]]];
    }
    return kinds;
}

- (unsigned long long)selectedBytes {
    unsigned long long total = 0;
    for (int i = 0; i < ExteriaStorageKinds; ++i) if (_selected[i]) total += _bytes[i];
    return total;
}

- (NSString *)deviceShareLine {
    NSDictionary *system = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
    double capacity = [[system objectForKey:NSFileSystemSize] doubleValue];
    if (capacity <= 0) return nil;
    unsigned long long all = 0;
    for (int i = 0; i < ExteriaStorageKinds; ++i) all += _bytes[i];
    double percent = (double)all * 100.0 / capacity;
    NSString *text = percent < 1 ? @"<1%" : [NSString stringWithFormat:@"%d%%", (int)floor(percent + 0.5)];
    return [NSString stringWithFormat:NSLocalizedString(@"memory.share", nil), text];
}

/* puts the numbers into the ring, the card and the line under the title; animated is for a check that was tapped */
- (void)showStorageAnimated:(BOOL)animated {
    NSArray *kinds = [self shownKinds];
    NSMutableArray *values = [NSMutableArray array], *colors = [NSMutableArray array], *titles = [NSMutableArray array], *shares = [NSMutableArray array];
    NSMutableArray *sizes = [NSMutableArray array], *checks = [NSMutableArray array];
    unsigned long long all = 0;
    for (int i = 0; i < ExteriaStorageKinds; ++i) all += _bytes[i];
    for (NSNumber *number in kinds) {
        int kind = number.intValue;
        [values addObject:[NSNumber numberWithDouble:_selected[kind] ? (double)_bytes[kind] : 0]];
        [colors addObject:ExteriaColorOfRGB(ExteriaStorageColors[kind])];
        [titles addObject:NSLocalizedString(ExteriaStorageTitles[kind], nil)];
        double share = all ? (double)_bytes[kind] * 100.0 / (double)all : 0;
        [shares addObject:share < 1 ? @"<1%" : [NSString stringWithFormat:@"%d%%", (int)floor(share + 0.5)]];
        [sizes addObject:ExteriaMemorySize(_bytes[kind], 2)];
        [checks addObject:[NSNumber numberWithBool:_selected[kind]]];
    }
    unsigned long long picked = [self selectedBytes];
    NSString *amount = nil, *unit = nil;
    ExteriaMemoryParts(picked, &amount, &unit);
    [_donut setValues:values colors:colors amount:amount unit:unit animated:animated];
    _subtitle.text = [self deviceShareLine];
    [_card setTitles:titles shares:shares sizes:sizes colors:colors checked:checks buttonTitle:NSLocalizedString(@"memory.clear.button", nil)
          buttonSize:picked ? ExteriaMemorySize(picked, 2) : nil enabled:picked > 0];
    [_header setNeedsLayout];
}

- (void)toggleKindAtIndex:(NSUInteger)index {
    NSArray *kinds = [self shownKinds];
    if (index >= kinds.count) return;
    int kind = [[kinds objectAtIndex:index] intValue];
    _selected[kind] = !_selected[kind];
    /* the ring slides and the check moves; the rows stay where they are */
    [self showStorageAnimated:YES];
}

- (void)scanStorage {
    ExteriaWeakReference *weak = _weak;
    NSUInteger scan = ++_scan;
    _bytes[ExteriaStorageAvatars] = [_avatars diskBytes];
    [_media loadKindBytes:^(const unsigned long long *bytes) {
        ExteriaMemoryController *me = weak.target;
        if (!me || me->_scan != scan) return;
        for (int i = 0; i < EXTERIA_CACHE_KIND_COUNT; ++i) me->_bytes[i] = bytes[i];
        me->_loaded = YES;
        [me showStorageAnimated:NO];
        [me reloadSettings];
    }];
}

- (void)confirmClear {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"memory.clear.confirm", nil), NSLocalizedString(@"settings.cache.clear", nil), ^{
        ExteriaMemoryController *again = weak.target;
        if (!again) return;
        ExteriaMediaCache *media = again->_media;
        ExteriaAvatarCache *avatars = again->_avatars;
        NSMutableArray *steps = [NSMutableArray array];
        for (NSNumber *number in [again shownKinds]) {
            int kind = number.intValue;
            if (!again->_selected[kind]) continue;
            NSString *name = NSLocalizedString(ExteriaStorageTitles[kind], nil);
            if (kind == ExteriaStorageAvatars) [steps addObject:[ExteriaCleaningStep stepNamed:name asyncWork:^(void (^finished)(BOOL)) { [avatars clearWithCompletion:finished]; }]];
            else [steps addObject:[ExteriaCleaningStep stepNamed:name asyncWork:^(void (^finished)(BOOL)) { [media clearKindsMask:1u << kind completion:finished]; }]];
        }
        if (!steps.count) return;
        ExteriaRunCleaning(steps, ^{
            [(ExteriaMemoryController *)weak.target rebuild];
        });
    });
}

- (UIView *)buildHeader {
    UIView *header = [[[UIView alloc] init] autorelease];
    [_donut release];
    _donut = [[ExteriaDonutView alloc] initWithFrame:CGRectMake(0, 0, DONUT_SIDE, DONUT_SIDE)];
    [header addSubview:_donut];
    [_headline release];
    _headline = [[UILabel alloc] init];
    _headline.backgroundColor = [UIColor clearColor];
    _headline.font = ExteriaFontBold(24);
    _headline.textColor = ExteriaColorTitle();
    _headline.textAlignment = ExteriaTextAlignmentCenter;
    _headline.adjustsFontSizeToFitWidth = YES;
    _headline.minimumFontSize = 16;
    _headline.text = NSLocalizedString(@"memory.title", nil);
    [header addSubview:_headline];
    [_subtitle release];
    _subtitle = [[UILabel alloc] init];
    _subtitle.backgroundColor = [UIColor clearColor];
    _subtitle.font = ExteriaFontMedium(15);
    _subtitle.textColor = ExteriaColorSecondary();
    _subtitle.textAlignment = ExteriaTextAlignmentCenter;
    _subtitle.numberOfLines = 2;
    [header addSubview:_subtitle];
    [_header release];
    _header = [header retain];
    return header;
}

- (void)layoutHeader:(CGFloat)width {
    _donut.frame = CGRectMake(floor((width - DONUT_SIDE) / 2), HEADER_PAD, DONUT_SIDE, DONUT_SIDE);
    CGFloat y = HEADER_PAD + DONUT_SIDE + 18;
    _headline.frame = CGRectMake(8, y, width - 16, 30);
    CGSize line = [_subtitle.text ? _subtitle.text : @"" sizeWithFont:_subtitle.font constrainedToSize:CGSizeMake(width - 32, 40)];
    _subtitle.frame = CGRectMake(16, y + 32, width - 32, line.height);
}

- (CGFloat)headerHeight:(CGFloat)width {
    [self layoutHeader:width];
    return CGRectGetMaxY(_subtitle.frame) + 20;
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    UIView *header = [self buildHeader];
    [_card release];
    _card = [[ExteriaStorageCardView alloc] init];
    _card.toggleHandler = ^(NSUInteger index) { [(ExteriaMemoryController *)weak.target toggleKindAtIndex:index]; };
    _card.clearHandler = ^{ [(ExteriaMemoryController *)weak.target confirmClear]; };
    /* the first frame of a screen that waits for the scan is an empty ring; the rows come in when the files are counted */
    memset(_bytes, 0, sizeof(_bytes));
    _loaded = NO;
    [self showStorageAnimated:NO];
    ExteriaSettingsRow *ring = [ExteriaSettingsRow viewRowWithView:header height:^CGFloat(CGFloat width) {
        ExteriaMemoryController *me = weak.target;
        return me ? [me headerHeight:width] : 0;
    }];
    ExteriaStorageCardView *card = _card;
    ExteriaSettingsRow *rows = [ExteriaSettingsRow viewRowWithView:card height:^CGFloat(CGFloat width) {
        (void)width;
        ExteriaMemoryController *me = weak.target;
        return [ExteriaStorageCardView heightForRows:me ? [me shownKinds].count : 0];
    }];
    NSMutableArray *keep = [NSMutableArray array];
    NSInteger days = ExteriaCacheKeepDays();
    for (size_t i = 0; i < sizeof(ExteriaKeepChoices) / sizeof(ExteriaKeepChoices[0]); ++i) {
        NSInteger choice = ExteriaKeepChoices[i];
        [keep addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(ExteriaKeepTitles[i], nil) subtitle:nil checked:days == choice tap:^{
            ExteriaMemoryController *me = weak.target;
            if (!me) return;
            ExteriaCacheSetKeepDays(choice);
            /* the files past the new limit go at once, not at the next start */
            [me->_media removeFilesOlderThanDays:choice];
            [me rebuild];
        }]];
    }
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"memory.clear.info", nil) rows:[NSArray arrayWithObjects:ring, rows, nil]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"memory.keep", nil) footer:NSLocalizedString(@"memory.keep.info", nil) rows:keep]];
    self.sections = sections;
    [self reloadSettings];
    [self scanStorage];
}

@end
