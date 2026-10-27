#import "exteria_sticker_picker.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_image_decoder.h"
#import "exteria_lite_mode.h"
#import "exteria_lottie_view.h"
#import "exteria_person.h"
#import "exteria_platform.h"
#import "exteria_session_stickermanage.h"
#import "exteria_string_drawing.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define STRIP_HEIGHT 44.0
#define COLUMNS_MIN 4
#define CELL_TARGET 78.0
#define TAB_SIDE 32.0
#define HEADER_HEIGHT 34.0
/* the animated stickers that play at once; an old phone draws no more than this many without dropping frames */
#define ANIMATED_MAX 8

typedef enum { ExteriaSectionFaved, ExteriaSectionRecent, ExteriaSectionSet } ExteriaSectionKind;

/* one row of the grid: a few stickers, each a picture, with a tap and a hold */
@interface ExteriaStickerRow : UITableViewCell {
    NSMutableArray *_views;
    CGFloat _cellSize;
    id _pickTarget;
}
- (void)setColumns:(NSInteger)columns cellSize:(CGFloat)size;
@property (nonatomic, readonly) NSMutableArray *views;
/* hears of a tap as -stickerRow:didTapColumn: and of a hold as -stickerRow:didHoldColumn */
@property (nonatomic, assign) id target;
@end

@implementation ExteriaStickerRow

@synthesize views = _views;
@synthesize target = _pickTarget;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    UILongPressGestureRecognizer *hold = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)] autorelease];
    [self.contentView addGestureRecognizer:hold];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    [tap requireGestureRecognizerToFail:hold];
    [self.contentView addGestureRecognizer:tap];
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.backgroundColor = [UIColor clearColor];
    _views = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_views release];
    [super dealloc];
}

- (NSNumber *)columnAt:(CGPoint)point {
    return [NSNumber numberWithInteger:_cellSize > 0 ? (NSInteger)(point.x / _cellSize) : 0];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    [_pickTarget performSelector:@selector(stickerRow:didTapColumn:) withObject:self withObject:[self columnAt:[tap locationInView:self.contentView]]];
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    [_pickTarget performSelector:@selector(stickerRow:didHoldColumn:) withObject:self withObject:[self columnAt:[hold locationInView:self.contentView]]];
}

- (void)setColumns:(NSInteger)columns cellSize:(CGFloat)size {
    _cellSize = size;
    while ((NSInteger)_views.count < columns) {
        UIImageView *view = [[[UIImageView alloc] init] autorelease];
        view.contentMode = UIViewContentModeScaleAspectFit;
        view.tag = (NSInteger)_views.count;
        [self.contentView addSubview:view];
        [_views addObject:view];
    }
    for (NSInteger i = 0; i < (NSInteger)_views.count; ++i) {
        UIImageView *view = [_views objectAtIndex:(NSUInteger)i];
        view.hidden = i >= columns;
        view.frame = CGRectMake(size * (CGFloat)i + 6, 6, size - 12, size - 12);
    }
}

@end

@interface ExteriaStickerPicker () {
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_library;
    UIScrollView *_strip;
    UITableView *_table;
    UILabel *_message;
    NSArray *_sets;
    /* the sections of the list, in order: dictionaries with "kind", "title", "set" (for a set), "stickers" (nil until fetched) and "loading" */
    NSMutableArray *_sections;
    NSArray *_faved;
    NSArray *_recent;
    NSInteger _current;
    NSInteger _columns;
    CGFloat _cellSize;
    NSUInteger _request;
    BOOL _prepared;
    CGFloat _bottomInset;
    /* the animations on screen, oldest first: an overlay over the picture of one sticker, and the picture it hides */
    NSMutableArray *_playing;
}
@end

@implementation ExteriaStickerPicker

@synthesize delegate = _delegate;
@synthesize bottomInset = _bottomInset;

- (id)initWithMedia:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _media = [media retain];
    _library = [library retain];
    self.backgroundColor = [UIColor clearColor];
    _strip = [[UIScrollView alloc] init];
    _strip.showsHorizontalScrollIndicator = NO;
    _strip.scrollsToTop = NO;
    [self addSubview:_strip];
    _table = [[UITableView alloc] init];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.scrollsToTop = NO;
    [self addSubview:_table];
    _message = [[UILabel alloc] init];
    _message.backgroundColor = [UIColor clearColor];
    _message.textColor = ExteriaColorSecondary();
    _message.font = ExteriaFontRegular(15);
    _message.textAlignment = ExteriaTextAlignmentCenter;
    _message.numberOfLines = 0;
    [self addSubview:_message];
    _sections = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setsChanged) name:ExteriaStickerSetsDidChangeNotification object:nil];
    return self;
}

/* a set came, went or moved: the next showing asks for the sets again */
- (void)setsChanged {
    _prepared = NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.dataSource = nil;
    _table.delegate = nil;
    [_media release];
    [_library release];
    [_strip release];
    [_table release];
    [_message release];
    [_sets release];
    [_sections release];
    [_faved release];
    [_recent release];
    [_playing release];
    [super dealloc];
}

- (void)showMessage:(NSString *)text {
    _message.text = text;
    _message.hidden = text.length == 0;
    [self setNeedsLayout];
}

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    _table.contentInset = UIEdgeInsetsMake(0, 0, inset, 0);
    _table.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, inset, 0);
}

#pragma mark data

/* the favorites and the recent ones are asked for every time the panel shows; the sets once, and a set's stickers when it comes near the screen */
- (void)prepare {
    if (!_prepared) {
        _prepared = YES;
        [self showMessage:NSLocalizedString(@"chat.stickers.loading", nil)];
        [_library loadSets:^(NSArray *sets, NSString *errorName) {
            if (!sets) {
                _prepared = NO;
                [self showMessage:NSLocalizedString(@"chat.stickers.failed", nil)];
                NSLog(@"exteria: sticker sets not loaded: %@", errorName);
                return;
            }
            [_sets release];
            _sets = [sets retain];
            [self showMessage:@""];
            [self rebuildSections];
        }];
    }
    [_library loadRecent:^(NSArray *stickers, NSString *errorName) {
        if (!stickers) {
            NSLog(@"exteria: recent stickers not loaded: %@", errorName);
            return;
        }
        [_recent release];
        _recent = [stickers retain];
        [self rebuildSections];
    }];
    [_library loadFaved:^(NSArray *stickers, NSString *errorName) {
        if (!stickers) {
            NSLog(@"exteria: favorite stickers not loaded: %@", errorName);
            return;
        }
        [_faved release];
        _faved = [stickers retain];
        [self rebuildSections];
    }];
}

- (NSMutableDictionary *)sectionOfKind:(ExteriaSectionKind)kind title:(NSString *)title set:(ExteriaStickerSet *)set stickers:(NSArray *)stickers {
    NSMutableDictionary *section = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kind], @"kind", title, @"title", nil];
    if (set) [section setObject:set forKey:@"set"];
    if (stickers) [section setObject:stickers forKey:@"stickers"];
    return section;
}

/* the sections are made again from what is known; what a set already fetched is carried over, and the list keeps its place */
- (void)rebuildSections {
    if (!_sets) return;
    NSMutableDictionary *fetched = [NSMutableDictionary dictionary];
    for (NSDictionary *old in _sections) {
        ExteriaStickerSet *set = [old objectForKey:@"set"];
        NSArray *stickers = [old objectForKey:@"stickers"];
        if (set && stickers) [fetched setObject:stickers forKey:[NSNumber numberWithLongLong:set.row.id]];
    }
    NSMutableArray *sections = [NSMutableArray array];
    if (_faved.count) [sections addObject:[self sectionOfKind:ExteriaSectionFaved title:NSLocalizedString(@"chat.stickers.faved", nil) set:nil stickers:_faved]];
    [sections addObject:[self sectionOfKind:ExteriaSectionRecent title:NSLocalizedString(@"chat.stickers.recent", nil) set:nil stickers:_recent ? _recent : [NSArray array]]];
    for (ExteriaStickerSet *set in _sets) {
        [sections addObject:[self sectionOfKind:ExteriaSectionSet title:set.title set:set stickers:[fetched objectForKey:[NSNumber numberWithLongLong:set.row.id]]]];
    }
    [_sections release];
    _sections = [sections retain];
    [self rebuildStrip];
    [_table reloadData];
    [self loadSectionsNearScreen];
}

- (void)loadSection:(NSMutableDictionary *)section {
    ExteriaStickerSet *set = [section objectForKey:@"set"];
    if (!set || [section objectForKey:@"stickers"] || [[section objectForKey:@"loading"] boolValue]) return;
    [section setObject:[NSNumber numberWithBool:YES] forKey:@"loading"];
    [_library loadStickersOfSet:set completion:^(NSArray *stickers, NSString *errorName) {
        [section removeObjectForKey:@"loading"];
        if (!stickers) {
            NSLog(@"exteria: stickers of %@ not loaded: %@", set.title, errorName);
            return;
        }
        [section setObject:stickers forKey:@"stickers"];
        NSUInteger index = [_sections indexOfObjectIdenticalTo:section];
        if (index != NSNotFound) [_table reloadSections:[NSIndexSet indexSetWithIndex:index] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

/* the sets a screen above and below the visible part are fetched, so a scroll finds them ready */
- (void)loadSectionsNearScreen {
    CGFloat top = _table.contentOffset.y - _table.bounds.size.height, bottom = CGRectGetMaxY(_table.bounds) + _table.contentOffset.y + _table.bounds.size.height;
    for (NSUInteger i = 0; i < _sections.count; ++i) {
        CGRect rect = [_table rectForSection:(NSInteger)i];
        if (CGRectGetMaxY(rect) >= top && rect.origin.y <= bottom) [self loadSection:[_sections objectAtIndex:i]];
    }
}

#pragma mark strip

- (UIButton *)tabButtonWithTag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.layer.cornerRadius = 8;
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.imageEdgeInsets = UIEdgeInsetsMake(3, 3, 3, 3);
    [button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/* one tab per section: a star for the favorites, a clock for the recent ones, the cover of every set */
- (void)rebuildStrip {
    for (UIView *view in [[_strip.subviews copy] autorelease]) [view removeFromSuperview];
    CGFloat x = 8;
    for (NSUInteger i = 0; i < _sections.count; ++i) {
        NSDictionary *section = [_sections objectAtIndex:i];
        ExteriaSectionKind kind = (ExteriaSectionKind)[[section objectForKey:@"kind"] intValue];
        UIButton *button = [self tabButtonWithTag:(NSInteger)i];
        button.frame = CGRectMake(x, (STRIP_HEIGHT - TAB_SIDE) / 2, TAB_SIDE, TAB_SIDE);
        x += TAB_SIDE + 8;
        if (kind == ExteriaSectionFaved) [button setImage:ExteriaSymbolImage(ExteriaSymbolStar, 20, ExteriaColorSecondary()) forState:UIControlStateNormal];
        else if (kind == ExteriaSectionRecent) [button setImage:ExteriaSymbolImage(ExteriaSymbolClock, 20, ExteriaColorSecondary()) forState:UIControlStateNormal];
        else [self setCoverOf:[section objectForKey:@"set"] onButton:button];
        [_strip addSubview:button];
    }
    _strip.contentSize = CGSizeMake(x, STRIP_HEIGHT);
    [self highlightTab:_current];
}

/* sets without a separate thumbnail use their first sticker */
- (void)setCoverOf:(ExteriaStickerSet *)set onButton:(UIButton *)button {
    NSString *letters = ExteriaInitialsOfName(set.title);
    [button setTitle:letters forState:UIControlStateNormal];
    [button setTitleColor:ExteriaColorSecondary() forState:UIControlStateNormal];
    button.titleLabel.font = ExteriaFontSemibold(13);
    ExteriaRemoteFile *cover = set.coverFile;
    CGFloat side = TAB_SIDE * ExteriaScreenScale();
    if (!cover) {
        [self setFirstStickerCoverOf:set onButton:button side:side];
        return;
    }
    [_media loadImageForFile:cover maxSide:side completion:^(UIImage *image) {
        if (image) {
            [self showCover:image onButton:button];
            return;
        }
        [self setFirstStickerCoverOf:set onButton:button side:side];
    }];
}

- (void)showCover:(UIImage *)image onButton:(UIButton *)button {
    [button setTitle:@"" forState:UIControlStateNormal];
    [button setImage:image forState:UIControlStateNormal];
}

- (void)setFirstStickerCoverOf:(ExteriaStickerSet *)set onButton:(UIButton *)button side:(CGFloat)side {
    [_library loadStickersOfSet:set completion:^(NSArray *stickers, NSString *errorName) {
        if (!stickers.count) {
            NSLog(@"exteria: sticker cover %@ not loaded: %@", set.title, errorName);
            return;
        }
        ExteriaMedia *media = [[stickers objectAtIndex:0] media];
        for (ExteriaSticker *sticker in stickers) {
            if (sticker.media.ref.id == set.row.thumb_document_id) { media = sticker.media; break; }
        }
        [_media loadImageForFile:media.file maxSide:side completion:^(UIImage *image) {
            if (image) [self showCover:image onButton:button];
            else [_media loadImageForFile:media.previewFile maxSide:side completion:^(UIImage *preview) {
                if (preview) [self showCover:preview onButton:button];
            }];
        }];
    }];
}

- (void)highlightTab:(NSInteger)tab {
    _current = tab;
    for (UIView *view in _strip.subviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        view.backgroundColor = view.tag == tab ? ExteriaColorField() : [UIColor clearColor];
    }
}

- (void)tabTapped:(UIButton *)button {
    NSInteger section = button.tag;
    if (section < 0 || section >= (NSInteger)_sections.count) return;
    [self highlightTab:section];
    CGFloat top = [_table rectForSection:section].origin.y;
    CGFloat limit = MAX(0, _table.contentSize.height - _table.bounds.size.height + _bottomInset);
    [_table setContentOffset:CGPointMake(0, MIN(top, limit)) animated:YES];
}

#pragma mark animation

/* takes an overlay off, and shows the picture under it again */
- (void)stopOverlay:(NSDictionary *)entry {
    ExteriaLottieView *overlay = [entry objectForKey:@"overlay"];
    UIView *picture = [entry objectForKey:@"picture"];
    [overlay setPlaying:NO];
    [overlay removeFromSuperview];
    picture.alpha = 1;
    [_playing removeObject:entry];
}

- (void)stopAnimations {
    for (NSDictionary *entry in [[_playing copy] autorelease]) [self stopOverlay:entry];
}

/* a row that is reused or leaves loses its overlays */
- (void)stopAnimationsInRow:(ExteriaStickerRow *)row {
    for (NSDictionary *entry in [[_playing copy] autorelease]) {
        if ([entry objectForKey:@"row"] == row) [self stopOverlay:entry];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self stopAnimations];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if (hidden) [self stopAnimations];
}

/* an animated sticker plays over its picture as soon as its file is here, when the power saving settings let stickers of the keyboard play */
- (void)animateMedia:(ExteriaMedia *)media picture:(UIImageView *)picture row:(ExteriaStickerRow *)row index:(NSInteger)index request:(NSUInteger)request {
    if (media.stickerFormat != EXTERIA_STICKER_ANIMATED && media.stickerFormat != EXTERIA_STICKER_VIDEO) return;
    if (!media.file || !ExteriaLiteEnabled(EXTERIA_LITE_STICKERS_KEYBOARD)) return;
    NSString *key = media.file.key;
    [_media loadDataForFile:media.file completion:^(NSData *data) {
        if (request != _request || picture.tag != index || row.superview == nil || !self.window || self.hidden) return;
        ExteriaFileFormat format = data ? ExteriaFileFormatOfData(data) : ExteriaFileFormatUnknown;
        if (format != ExteriaFileFormatGzip && format != ExteriaFileFormatMatroska) {
            NSLog(@"exteria: animation %@ did not load as tgs or webm", key);
            return;
        }
        if (!_playing) _playing = [[NSMutableArray alloc] init];
        while (_playing.count >= ANIMATED_MAX) [self stopOverlay:[_playing objectAtIndex:0]];
        ExteriaLottieView *overlay = [[[ExteriaLottieView alloc] initWithPackedData:data key:key] autorelease];
        overlay.frame = picture.frame;
        [overlay setLoaded:YES];
        [row.contentView addSubview:overlay];
        /* the picture goes when the first frame stands in its place, so there is no blank between them */
        overlay.firstFrameHandler = ^{ picture.alpha = 0; };
        [overlay setPlaying:YES];
        [_playing addObject:[NSDictionary dictionaryWithObjectsAndKeys:overlay, @"overlay", picture, @"picture", row, @"row", nil]];
    }];
}

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _strip.frame = CGRectMake(0, 0, size.width, STRIP_HEIGHT);
    _table.frame = CGRectMake(0, STRIP_HEIGHT, size.width, size.height - STRIP_HEIGHT);
    _message.frame = CGRectMake(20, STRIP_HEIGHT, size.width - 40, size.height - STRIP_HEIGHT);
    NSInteger columns = MAX(COLUMNS_MIN, (NSInteger)floor(size.width / CELL_TARGET));
    if (columns != _columns) {
        _columns = columns;
        _cellSize = size.width / (CGFloat)columns;
        [_table reloadData];
    }
}

#pragma mark table

/* the items of a section: the tile that makes a sticker leads the recent ones, then the stickers; a set not fetched yet counts what its row says */
- (NSInteger)itemCountOfSection:(NSDictionary *)section {
    NSArray *stickers = [section objectForKey:@"stickers"];
    ExteriaStickerSet *set = [section objectForKey:@"set"];
    NSInteger count = stickers ? (NSInteger)stickers.count : (set ? set.row.count : 0);
    if ((ExteriaSectionKind)[[section objectForKey:@"kind"] intValue] == ExteriaSectionRecent) ++count;
    return count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (!_columns || section >= (NSInteger)_sections.count) return 0;
    return ([self itemCountOfSection:[_sections objectAtIndex:(NSUInteger)section]] + _columns - 1) / _columns;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return _cellSize;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return HEADER_HEIGHT;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSDictionary *info = [_sections objectAtIndex:(NSUInteger)section];
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, HEADER_HEIGHT)] autorelease];
    UILabel *title = [[[UILabel alloc] init] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.textColor = ExteriaColorSecondary();
    title.font = ExteriaFontSemibold(15);
    title.text = [info objectForKey:@"title"];
    title.frame = CGRectMake(14, 0, header.bounds.size.width - 70, HEADER_HEIGHT);
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:title];
    if ((ExteriaSectionKind)[[info objectForKey:@"kind"] intValue] == ExteriaSectionRecent && [[info objectForKey:@"stickers"] count]) {
        UIButton *clear = [UIButton buttonWithType:UIButtonTypeCustom];
        clear.frame = CGRectMake(header.bounds.size.width - 50, 0, 50, HEADER_HEIGHT);
        clear.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [clear setImage:ExteriaSymbolImage(ExteriaSymbolClose, 16, ExteriaColorSecondary()) forState:UIControlStateNormal];
        clear.accessibilityLabel = NSLocalizedString(@"chat.stickers.clear", nil);
        [clear addTarget:self action:@selector(askClearRecent) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:clear];
    }
    return header;
}

/* the picture of the tile that makes a sticker: a soft square with the sticker glyph and the word under it */
- (UIImage *)createTileImage:(CGFloat)side {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect tile = CGRectMake(0, 0, side, side);
    (void)context;
    [ExteriaColorField() setFill];
    [[UIBezierPath bezierPathWithRoundedRect:tile cornerRadius:16] fill];
    UIImage *glyph = ExteriaSymbolImage(ExteriaSymbolSticker, MIN(34, side * 0.42), ExteriaColorSecondary());
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, side * 0.2)];
    [ExteriaColorSecondary() set];
    ExteriaDrawStringIn(NSLocalizedString(@"chat.stickers.create", nil), ExteriaFontSemibold(12), CGRectMake(4, side * 0.66, side - 8, 16), ExteriaStringClip, ExteriaTextAlignmentCenter);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"stickers";
    ExteriaStickerRow *row = (ExteriaStickerRow *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!row) row = [[[ExteriaStickerRow alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    row.target = self;
    [self stopAnimationsInRow:row];
    [row setColumns:_columns cellSize:_cellSize];
    NSDictionary *section = [_sections objectAtIndex:(NSUInteger)indexPath.section];
    NSArray *stickers = [section objectForKey:@"stickers"];
    BOOL recent = (ExteriaSectionKind)[[section objectForKey:@"kind"] intValue] == ExteriaSectionRecent;
    CGFloat side = (_cellSize - 12) * ExteriaScreenScale();
    NSUInteger request = _request;
    for (NSInteger i = 0; i < _columns; ++i) {
        UIImageView *view = [row.views objectAtIndex:(NSUInteger)i];
        NSInteger item = indexPath.row * _columns + i;
        NSInteger index = recent ? item - 1 : item;
        view.image = nil;
        view.alpha = 1;
        view.tag = item;
        if (item >= [self itemCountOfSection:section]) {
            view.hidden = YES;
            continue;
        }
        view.hidden = NO;
        if (recent && item == 0) {
            view.image = [self createTileImage:_cellSize - 12];
            continue;
        }
        if (index < 0 || index >= (NSInteger)stickers.count) continue;
        ExteriaMedia *media = [[stickers objectAtIndex:(NSUInteger)index] media];
        [self animateMedia:media picture:view row:row index:item request:request];
        /* prefer the small server preview, then render a poster when the set has none */
        ExteriaRemoteFile *file = media.stickerFormat == EXTERIA_STICKER_STATIC ? media.file : (media.previewFile ? media.previewFile : media.file);
        UIImage *ready = [_media cachedImageForFile:file maxSide:side];
        if (ready) {
            view.image = ready;
            continue;
        }
        [_media loadImageForFile:file maxSide:side completion:^(UIImage *image) {
            if (request != _request || view.tag != item) return;
            if (image) view.image = image;
            else if (file != media.file) [_media loadImageForFile:media.file maxSide:side completion:^(UIImage *poster) {
                if (request == _request && view.tag == item && poster) view.image = poster;
            }];
        }];
    }
    return row;
}

/* the sticker under a column of a row, or nil for the tile that makes one, or a column with nothing */
- (ExteriaSticker *)stickerAtRow:(ExteriaStickerRow *)row column:(NSInteger)column isCreate:(BOOL *)create {
    *create = NO;
    NSIndexPath *path = [_table indexPathForCell:row];
    if (!path) return nil;
    NSDictionary *section = [_sections objectAtIndex:(NSUInteger)path.section];
    NSInteger item = path.row * _columns + column;
    BOOL recent = (ExteriaSectionKind)[[section objectForKey:@"kind"] intValue] == ExteriaSectionRecent;
    if (recent && item == 0) {
        *create = YES;
        return nil;
    }
    NSInteger index = recent ? item - 1 : item;
    NSArray *stickers = [section objectForKey:@"stickers"];
    return index >= 0 && index < (NSInteger)stickers.count ? [stickers objectAtIndex:(NSUInteger)index] : nil;
}

- (void)stickerRow:(ExteriaStickerRow *)row didTapColumn:(NSNumber *)column {
    BOOL create = NO;
    ExteriaSticker *sticker = [self stickerAtRow:row column:[column integerValue] isCreate:&create];
    if (create) {
        if ([_delegate respondsToSelector:@selector(stickerPickerDidTapCreate:)]) [_delegate stickerPickerDidTapCreate:self];
        return;
    }
    if (sticker) [_delegate stickerPicker:self didPickSticker:sticker];
}

/* a hold offers the favorites: in them the sticker is taken out, elsewhere it goes in */
- (void)stickerRow:(ExteriaStickerRow *)row didHoldColumn:(NSNumber *)column {
    BOOL create = NO;
    ExteriaSticker *sticker = [self stickerAtRow:row column:[column integerValue] isCreate:&create];
    if (!sticker || create) return;
    BOOL faved = NO;
    for (ExteriaSticker *known in _faved) if (known.media.ref.id == sticker.media.ref.id) { faved = YES; break; }
    ExteriaChoose(nil, [NSArray arrayWithObject:NSLocalizedString(faved ? @"chat.stickers.unfave" : @"chat.stickers.fave", nil)], -1, ^(NSInteger index) {
        (void)index;
        [_library faveSticker:sticker unfave:faved completion:^(NSString *errorName) {
            if (errorName) {
                NSLog(@"exteria: the favorite sticker was not changed: %@", errorName);
                return;
            }
            [self prepare];
        }];
    });
}

- (void)askClearRecent {
    ExteriaConfirm(nil, NSLocalizedString(@"chat.stickers.clear.ask", nil), NSLocalizedString(@"chat.stickers.clear", nil), ^{
        [_library clearRecent:^(NSString *errorName) {
            if (errorName) {
                NSLog(@"exteria: the recent stickers were not cleared: %@", errorName);
                return;
            }
            [_recent release];
            _recent = [[NSArray alloc] init];
            [self rebuildSections];
        }];
    });
}

#pragma mark scrolling

/* the tab of the section at the top of the list is the lit one */
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != _table || !_sections.count) return;
    /* a plain table pins the header of the section on screen; a negative top inset of up to one header makes the headers leave with their rows */
    CGFloat offset = scrollView.contentOffset.y;
    UIEdgeInsets inset = _table.contentInset;
    CGFloat pinned = offset <= 0 ? 0 : -MIN(offset, HEADER_HEIGHT);
    if (inset.top != pinned) {
        inset.top = pinned;
        _table.contentInset = inset;
    }
    NSInteger top = 0;
    CGFloat edge = scrollView.contentOffset.y + HEADER_HEIGHT;
    for (NSUInteger i = 0; i < _sections.count; ++i) {
        if ([_table rectForSection:(NSInteger)i].origin.y <= edge) top = (NSInteger)i;
    }
    if (top != _current) {
        [self highlightTab:top];
        UIView *tab = nil;
        for (UIView *view in _strip.subviews) if (view.tag == top && [view isKindOfClass:[UIButton class]]) tab = view;
        if (tab) [_strip scrollRectToVisible:CGRectInset(tab.frame, -TAB_SIDE, 0) animated:YES];
    }
    [self loadSectionsNearScreen];
}

@end
