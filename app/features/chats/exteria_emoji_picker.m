#import "exteria_emoji_picker.h"

#import "exteria_alert.h"
#import "exteria_emoji_keywords.h"
#import "exteria_emoji_store.h"
#import "exteria_platform.h"
#import "exteria_session_keywords.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define STRIP_HEIGHT 34.0
#define ROW_HEIGHT 44.0
#define CELL_MIN 40.0
#define RECENT_MAX 28
#define RECENT_KEY @"ExteriaRecentEmoji"
/* one emoji from each group stands for it on the strip, as the code points of its fully qualified form: the football is U+26BD alone, since it looks like an emoji by default,
   and with U+FE0F after it the table has no such entry and its place on the strip stayed empty */
static const struct { uint32_t points[2]; size_t count; } ExteriaGroupFaces[EXTERIA_EMOJI_GROUPS] = {
    {{0x1F600}, 1}, {{0x1F44B}, 1}, {{0x1F43B}, 1}, {{0x1F34E}, 1}, {{0x1F697}, 1}, {{0x26BD}, 1}, {{0x1F4A1}, 1},
    {{0x2764, 0xFE0F}, 2}, {{0x1F3C1}, 1}
};

/* the content of a row: it draws up to a screen's width of emoji in one pass and says which one was tapped, so a row is
   one bitmap and not forty views */
@interface ExteriaEmojiRowContent : UIView {
    NSArray *_entries;
    CGFloat _cellWidth;
    id _target;
}
@property (nonatomic, retain) NSArray *entries;
@property (nonatomic, assign) CGFloat cellWidth;
@property (nonatomic, assign) id target;
@end

@implementation ExteriaEmojiRowContent

@synthesize entries = _entries;
@synthesize cellWidth = _cellWidth;
@synthesize target = _target;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dealloc {
    [_entries release];
    [super dealloc];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    NSUInteger misses = ExteriaEmojiMissCount();
    for (NSUInteger i = 0; i < _entries.count; ++i) {
        size_t entry = (size_t)[[_entries objectAtIndex:i] unsignedIntegerValue];
        ExteriaDrawEmoji(entry, CGRectMake(_cellWidth * (CGFloat)i + (_cellWidth - 30) / 2, (ROW_HEIGHT - 30) / 2, 30, 30));
    }
    if (ExteriaEmojiMissCount() != misses) ExteriaEmojiRedrawWhenLoaded(self);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    NSInteger index = (NSInteger)([tap locationInView:self].x / _cellWidth);
    if (index >= 0 && (NSUInteger)index < _entries.count) [_target performSelector:@selector(rowDidPick:) withObject:[_entries objectAtIndex:(NSUInteger)index]];
}

@end

@interface ExteriaEmojiRow : UITableViewCell {
    ExteriaEmojiRowContent *_content;
}
@property (nonatomic, readonly) ExteriaEmojiRowContent *content;
@end

@implementation ExteriaEmojiRow

@synthesize content = _content;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.backgroundColor = [UIColor clearColor];
    _content = [[ExteriaEmojiRowContent alloc] init];
    [self.contentView addSubview:_content];
    return self;
}

- (void)dealloc {
    [_content release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _content.frame = self.contentView.bounds;
}

@end

@interface ExteriaEmojiPicker () {
    UIScrollView *_strip;
    NSMutableArray *_stripButtons;
    UITableView *_table;
    NSArray *_recent;
    /* a row is an array of entry numbers, and starts says which row each group begins at */
    NSMutableArray *_rows;
    NSMutableArray *_groupRows;
    NSInteger _columns;
    /* the magnifier at the head of the strip, and what a typed word found: entry numbers of the grid, best first; nil while no word is being looked up */
    UIButton *_searchButton;
    UILabel *_nothing;
    NSString *_query;
    NSArray *_found;
    ExteriaSession *_session;
    CGSize _stripBuiltFor;
}
@end

@implementation ExteriaEmojiPicker

@synthesize delegate = _delegate;
@synthesize session = _session;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _strip = [[UIScrollView alloc] init];
    _strip.showsHorizontalScrollIndicator = NO;
    _strip.scrollsToTop = NO;
    [self addSubview:_strip];
    _stripButtons = [[NSMutableArray alloc] init];
    for (int group = 0; group <= EXTERIA_EMOJI_GROUPS; ++group) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = group;
        [button addTarget:self action:@selector(groupTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_strip addSubview:button];
        [_stripButtons addObject:button];
    }
    _searchButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_searchButton addTarget:self action:@selector(askQuery) forControlEvents:UIControlEventTouchUpInside];
    _searchButton.accessibilityLabel = NSLocalizedString(@"panel.emoji.search", nil);
    [_strip addSubview:_searchButton];
    _table = [[UITableView alloc] init];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = ROW_HEIGHT;
    _table.scrollsToTop = NO;
    [self addSubview:_table];
    _nothing = [[UILabel alloc] init];
    _nothing.backgroundColor = [UIColor clearColor];
    _nothing.textColor = ExteriaColorSecondary();
    _nothing.font = ExteriaFontRegular(15);
    _nothing.textAlignment = ExteriaTextAlignmentCenter;
    _nothing.text = NSLocalizedString(@"panel.emoji.nothing", nil);
    _nothing.hidden = YES;
    [self addSubview:_nothing];
    _rows = [[NSMutableArray alloc] init];
    _groupRows = [[NSMutableArray alloc] init];
    [self loadRecent];
    return self;
}

- (void)dealloc {
    _table.dataSource = nil;
    _table.delegate = nil;
    [_strip release];
    [_stripButtons release];
    [_searchButton release];
    [_nothing release];
    [_query release];
    [_found release];
    [_table release];
    [_recent release];
    [_rows release];
    [_groupRows release];
    [super dealloc];
}

- (void)loadRecent {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:RECENT_KEY];
    NSMutableArray *valid = [NSMutableArray array];
    for (id entry in stored) {
        /* a table from another version may be shorter than the numbers saved against it */
        if ([entry isKindOfClass:[NSNumber class]] && [entry unsignedIntegerValue] < exteria_emoji_entry_count) [valid addObject:entry];
    }
    [_recent release];
    _recent = [valid retain];
}

- (void)remember:(NSNumber *)entry {
    NSMutableArray *list = [NSMutableArray arrayWithArray:_recent];
    [list removeObject:entry];
    [list insertObject:entry atIndex:0];
    while (list.count > RECENT_MAX) [list removeLastObject];
    [_recent release];
    _recent = [list retain];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:RECENT_KEY];
}

/* the rows for the width the grid has, recent emoji first when there are any */
- (void)buildRows {
    CGFloat width = _table.bounds.size.width;
    NSInteger columns = MAX(5, (NSInteger)floor(width / CELL_MIN));
    _columns = columns;
    [_rows removeAllObjects];
    [_groupRows removeAllObjects];
    if (_found) {
        for (NSUInteger start = 0; start < _found.count; start += (NSUInteger)columns) {
            [_rows addObject:[_found subarrayWithRange:NSMakeRange(start, MIN((NSUInteger)columns, _found.count - start))]];
        }
        /* the strip jumps to the head of the list while a word is looked up */
        for (int group = 0; group <= EXTERIA_EMOJI_GROUPS; ++group) [_groupRows addObject:[NSNumber numberWithUnsignedInteger:0]];
        return;
    }
    for (int group = 0; group <= EXTERIA_EMOJI_GROUPS; ++group) {
        NSMutableArray *entries = [NSMutableArray array];
        if (group == 0) {
            [entries addObjectsFromArray:_recent];
        } else {
            for (size_t i = exteria_emoji_group_start[group - 1]; i < exteria_emoji_group_start[group]; ++i) {
                [entries addObject:[NSNumber numberWithUnsignedInteger:exteria_emoji_picker[i]]];
            }
        }
        [_groupRows addObject:[NSNumber numberWithUnsignedInteger:_rows.count]];
        for (NSUInteger start = 0; start < entries.count; start += (NSUInteger)columns) {
            NSUInteger count = MIN((NSUInteger)columns, entries.count - start);
            [_rows addObject:[entries subarrayWithRange:NSMakeRange(start, count)]];
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _strip.frame = CGRectMake(0, 0, size.width, STRIP_HEIGHT);
    _table.frame = CGRectMake(0, STRIP_HEIGHT, size.width, size.height - STRIP_HEIGHT);
    CGFloat buttonWidth = size.width / (CGFloat)(_stripButtons.count + 1);
    _searchButton.frame = CGRectMake(0, 0, buttonWidth, STRIP_HEIGHT);
    for (UIButton *button in _stripButtons) button.frame = CGRectMake(buttonWidth * (CGFloat)(button.tag + 1), 0, buttonWidth, STRIP_HEIGHT);
    _nothing.frame = CGRectMake(16, STRIP_HEIGHT + 24, size.width - 32, 22);
    [self showSearchState];
    if (_stripBuiltFor.width == 0) {
        _stripBuiltFor = size;
        for (UIButton *button in _stripButtons) [button setImage:[self stripImageForGroup:button.tag] forState:UIControlStateNormal];
        [self showSearchState];
    }
    _strip.contentSize = CGSizeMake(size.width, STRIP_HEIGHT);
    NSInteger columns = MAX(5, (NSInteger)floor(_table.bounds.size.width / CELL_MIN));
    if (columns != _columns || !_rows.count) {
        [self buildRows];
        [_table reloadData];
    }
}

/* the clock for the emoji used lately, and the face of the group otherwise */
- (UIImage *)stripImageForGroup:(NSInteger)group {
    if (group == 0) return ExteriaSymbolImage(ExteriaSymbolClock, 20, ExteriaColorSecondary());
    size_t index;
    if (!exteria_emoji_find(ExteriaGroupFaces[group - 1].points, ExteriaGroupFaces[group - 1].count, &index)) {
        NSLog(@"exteria: the face of emoji group %ld is not in the emoji table", (long)group);
        return nil;
    }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22, 22), NO, 0);
    /* the strip keeps this bitmap, so the picture is decoded here and not filled in later */
    UIImage *face = ExteriaEmojiImageNow(exteria_emoji_entries[index].canonical);
    [face drawInRect:CGRectMake(0, 0, 22, 22)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the magnifier takes the accent while a word is looked up; the list says so when nothing was found */
- (void)showSearchState {
    UIColor *ink = _found ? ExteriaColorAccent() : ExteriaColorSecondary();
    [_searchButton setImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, 20, ink) forState:UIControlStateNormal];
    _nothing.hidden = !(_found && _found.count == 0);
}

- (void)askQuery {
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    ExteriaPromptText(NSLocalizedString(@"panel.emoji.search", nil), nil, _query, nil, ^(NSString *text) {
        [(ExteriaEmojiPicker *)weak.target searchFor:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    });
}

/* the entry numbers of the grid for the emoji strings of the keywords; one the picture pack does not draw is left out */
static NSArray *ExteriaEntriesOfEmoji(NSArray *strings, NSMutableSet *seen) {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *emoji in strings) {
        uint16_t units[16];
        NSUInteger length = emoji.length;
        size_t entry;
        if (length == 0 || length > 16) continue;
        [emoji getCharacters:units range:NSMakeRange(0, length)];
        if (!exteria_emoji_single(units, length, &entry) || exteria_emoji_entries[entry].image == EXTERIA_EMOJI_NO_IMAGE) continue;
        NSNumber *number = [NSNumber numberWithUnsignedInteger:entry];
        if ([seen containsObject:number]) continue;
        [seen addObject:number];
        [entries addObject:number];
    }
    return entries;
}

/* an empty word leaves the search; otherwise the words of the interface language come first and those of English after them */
- (void)searchFor:(NSString *)query {
    [_query release];
    _query = query.length ? [query copy] : nil;
    [_found release];
    _found = nil;
    if (_query) {
        NSMutableArray *all = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSString *language in [ExteriaEmojiKeywords searchLanguages]) {
            ExteriaEmojiKeywords *keywords = [ExteriaEmojiKeywords keywordsForLanguage:language];
            [all addObjectsFromArray:ExteriaEntriesOfEmoji([keywords emojiForQuery:_query], seen)];
            [self updateKeywords:keywords];
        }
        _found = [all retain];
    }
    [self showSearchState];
    [self buildRows];
    [_table reloadData];
    if (_rows.count) [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
}

/* the list of a language is asked for once a launch; the words that arrive search again, so a first search does not stay empty */
- (void)updateKeywords:(ExteriaEmojiKeywords *)keywords {
    if (!_session || keywords.updateRequested) return;
    keywords.updateRequested = YES;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    [_session updateEmojiKeywords:keywords completion:^(NSString *errorName) {
        ExteriaEmojiPicker *picker = (ExteriaEmojiPicker *)weak.target;
        if (errorName) {
            NSLog(@"exteria: the emoji keywords could not be updated: %@", errorName);
            keywords.updateRequested = NO;
        } else if (picker && picker->_query) {
            [picker searchFor:picker->_query];
        }
    }];
}

/* the lists are fetched when the panel opens, so the first word typed already finds something */
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) return;
    for (NSString *language in [ExteriaEmojiKeywords searchLanguages]) [self updateKeywords:[ExteriaEmojiKeywords keywordsForLanguage:language]];
}

- (void)groupTapped:(UIButton *)button {
    if (_found) [self searchFor:nil];
    NSUInteger row = [[_groupRows objectAtIndex:(NSUInteger)button.tag] unsignedIntegerValue];
    if (row >= _rows.count) return;
    [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
}

- (void)rowDidPick:(NSNumber *)entry {
    [self remember:entry];
    [_delegate emojiPicker:self didPickEntry:(size_t)[entry unsignedIntegerValue]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"emoji";
    ExteriaEmojiRow *row = (ExteriaEmojiRow *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!row) row = [[[ExteriaEmojiRow alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    row.content.target = self;
    row.content.cellWidth = tableView.bounds.size.width / (CGFloat)_columns;
    row.content.entries = [_rows objectAtIndex:(NSUInteger)indexPath.row];
    [row.content setNeedsDisplay];
    return row;
}

@end
