#import "exteria_gif_picker.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_remote_file.h"
#import "exteria_session_bots.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define BAR_HEIGHT 46.0
#define COLUMNS 3
#define GAP 2.0
#define CHIP_WIDTH 40.0

/* the words the quick buttons of the bar search for, each shown as the emoji that stands for it */
static NSString *const ExteriaGifChips[][2] = {
    {@"❤️", @"love"}, {@"\U0001F44D", @"yes"}, {@"\U0001F44E", @"no"}, {@"\U0001F389", @"party"}, {@"\U0001F600", @"happy"},
    {@"\U0001F62E", @"wow"}, {@"\U0001F622", @"sad"}, {@"\U0001F621", @"angry"}, {@"\U0001F602", @"lol"}, {@"\U0001F431", @"cat"},
};

/* a row of the grid: three pictures and a tap each */
@interface ExteriaGifRow : UITableViewCell {
    NSMutableArray *_views;
    id _pickTarget;
}
@property (nonatomic, readonly) NSMutableArray *views;
@property (nonatomic, assign) id target;
- (void)layoutColumns:(NSInteger)columns side:(CGFloat)side;
@end

@implementation ExteriaGifRow
@synthesize views = _views;
@synthesize target = _pickTarget;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.backgroundColor = [UIColor clearColor];
    [self.contentView addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease]];
    _views = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_views release];
    [super dealloc];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    CGFloat width = self.contentView.bounds.size.width / COLUMNS;
    [_pickTarget performSelector:@selector(gifRow:didTapColumn:) withObject:self withObject:[NSNumber numberWithInteger:(NSInteger)([tap locationInView:self.contentView].x / width)]];
}

- (void)layoutColumns:(NSInteger)columns side:(CGFloat)side {
    while ((NSInteger)_views.count < columns) {
        UIImageView *view = [[[UIImageView alloc] init] autorelease];
        view.contentMode = UIViewContentModeScaleAspectFill;
        view.clipsToBounds = YES;
        [self.contentView addSubview:view];
        [_views addObject:view];
    }
    for (NSInteger i = 0; i < (NSInteger)_views.count; ++i) {
        UIImageView *view = [_views objectAtIndex:(NSUInteger)i];
        view.frame = CGRectMake((side + GAP) * (CGFloat)i, 0, side, side);
    }
}
@end

@interface ExteriaGifPicker () {
    ExteriaSession *_session;
    ExteriaMediaCache *_mediaCache;
    ExteriaStickerLibrary *_library;
    ExteriaDialog *_dialog;
    UIView *_bar;
    UIButton *_search;
    UIScrollView *_chips;
    UITableView *_table;
    UILabel *_message;
    /* what the grid shows: dictionaries with "media", or with "result" and "queryId" for a search that a bot answered */
    NSMutableArray *_items;
    NSArray *_saved;
    NSString *_query;
    ExteriaPerson *_bot;
    ExteriaDialog *_botDialog;
    NSUInteger _token;
    CGFloat _bottomInset;
    BOOL _loadingSaved;
}
@end

@implementation ExteriaGifPicker

@synthesize delegate = _delegate;
@synthesize dialog = _dialog;
@synthesize bottomInset = _bottomInset;

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _session = [session retain];
    _mediaCache = [media retain];
    _library = [library retain];
    self.backgroundColor = [UIColor clearColor];
    _items = [[NSMutableArray alloc] init];
    _bar = [[UIView alloc] init];
    _bar.backgroundColor = ExteriaColorField();
    _bar.layer.cornerRadius = 18;
    [self addSubview:_bar];
    _search = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_search setImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, 20, ExteriaColorSecondary()) forState:UIControlStateNormal];
    [_search setTitle:NSLocalizedString(@"chat.gif.search", nil) forState:UIControlStateNormal];
    [_search setTitleColor:ExteriaColorSecondary() forState:UIControlStateNormal];
    _search.titleLabel.font = ExteriaFontRegular(15);
    _search.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _search.imageEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
    _search.titleEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 0);
    [_search addTarget:self action:@selector(askQuery) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_search];
    _chips = [[UIScrollView alloc] init];
    _chips.showsHorizontalScrollIndicator = NO;
    _chips.scrollsToTop = NO;
    for (NSUInteger i = 0; i < sizeof(ExteriaGifChips) / sizeof(ExteriaGifChips[0]); ++i) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        chip.frame = CGRectMake(CHIP_WIDTH * (CGFloat)i, 0, CHIP_WIDTH, 36);
        chip.tag = (NSInteger)i;
        /* a button title would be set in the emoji of the system, the old ones on a device that has not got the new set; the label draws the pictures of the app */
        ExteriaEmojiLabel *face = [[[ExteriaEmojiLabel alloc] initWithFrame:chip.bounds] autorelease];
        face.font = ExteriaFontRegular(22);
        face.textAlignment = ExteriaTextAlignmentCenter;
        face.text = ExteriaGifChips[i][0];
        face.userInteractionEnabled = NO;
        face.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [chip addSubview:face];
        chip.accessibilityLabel = ExteriaGifChips[i][1];
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_chips addSubview:chip];
    }
    _chips.contentSize = CGSizeMake(CHIP_WIDTH * (sizeof(ExteriaGifChips) / sizeof(ExteriaGifChips[0])), 36);
    [_bar addSubview:_chips];
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
    return self;
}

- (void)dealloc {
    _table.dataSource = nil;
    _table.delegate = nil;
    [_session release];
    [_mediaCache release];
    [_library release];
    [_dialog release];
    [_bar release];
    [_search release];
    [_chips release];
    [_table release];
    [_message release];
    [_items release];
    [_saved release];
    [_query release];
    [_bot release];
    [_botDialog release];
    [super dealloc];
}

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    _table.contentInset = UIEdgeInsetsMake(0, 0, inset, 0);
    _table.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, inset, 0);
}

- (void)showMessage:(NSString *)text {
    _message.text = text;
    _message.hidden = text.length == 0;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _bar.frame = CGRectMake(8, 5, size.width - 16, BAR_HEIGHT - 10);
    _search.frame = CGRectMake(0, 0, MIN(150, _bar.bounds.size.width * 0.4), _bar.bounds.size.height);
    CGFloat from = CGRectGetMaxX(_search.frame);
    _chips.frame = CGRectMake(from, (_bar.bounds.size.height - 36) / 2, _bar.bounds.size.width - from - 6, 36);
    _table.frame = CGRectMake(0, BAR_HEIGHT, size.width, size.height - BAR_HEIGHT);
    _message.frame = CGRectMake(20, BAR_HEIGHT, size.width - 40, size.height - BAR_HEIGHT);
    [_table reloadData];
}

#pragma mark data

- (void)prepare {
    if (_query.length || _loadingSaved) return;
    _loadingSaved = YES;
    if (!_saved) [self showMessage:NSLocalizedString(@"chat.gif.loading", nil)];
    [_library loadGifs:^(NSArray *gifs, NSString *errorName) {
        _loadingSaved = NO;
        if (!gifs) {
            NSLog(@"exteria: the saved animations did not load: %@", errorName);
            if (!_saved) [self showMessage:NSLocalizedString(@"chat.gif.failed", nil)];
            return;
        }
        [_saved release];
        _saved = [gifs retain];
        if (_query.length) return;
        [self showSaved];
    }];
}

- (void)showSaved {
    [_items removeAllObjects];
    for (ExteriaSticker *gif in _saved) [_items addObject:[NSDictionary dictionaryWithObject:gif.media forKey:@"media"]];
    [self showMessage:_items.count ? @"" : NSLocalizedString(@"chat.gif.none", nil)];
    [_table reloadData];
    [_table setContentOffset:CGPointZero animated:NO];
}

- (void)chipTapped:(UIButton *)chip {
    [self searchFor:ExteriaGifChips[chip.tag][1]];
}

- (void)askQuery {
    ExteriaPromptText(NSLocalizedString(@"chat.gif.search", nil), nil, _query, nil, ^(NSString *text) {
        NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (query.length) [self searchFor:query];
        else [self clearSearch];
    });
}

- (void)clearSearch {
    [_query release];
    _query = nil;
    ++_token;
    [_search setTitle:NSLocalizedString(@"chat.gif.search", nil) forState:UIControlStateNormal];
    [self showSaved];
}

/* the @gif bot answers the search; the bot is looked up once */
- (void)searchFor:(NSString *)query {
    [_query release];
    _query = [query copy];
    [_search setTitle:query forState:UIControlStateNormal];
    NSUInteger token = ++_token;
    [self showMessage:NSLocalizedString(@"chat.gif.loading", nil)];
    if (_bot) {
        [self runSearch:query token:token];
        return;
    }
    [_session resolveUsername:@"gif" completion:^(ExteriaDialog *dialog, ExteriaPerson *person, NSString *errorName) {
        if (token != _token) return;
        if (!person) {
            NSLog(@"exteria: the gif bot was not found: %@", errorName);
            [self showMessage:NSLocalizedString(@"chat.gif.failed", nil)];
            return;
        }
        _bot = [person retain];
        _botDialog = [dialog retain];
        [self runSearch:query token:token];
    }];
}

- (void)runSearch:(NSString *)query token:(NSUInteger)token {
    if (!_dialog) return;
    [_session searchInline:query bot:_bot inDialog:_dialog offset:@"" completion:^(ExteriaInlinePage *page, NSString *errorName) {
        if (token != _token) return;
        if (!page) {
            NSLog(@"exteria: the gif search failed: %@", errorName);
            [self showMessage:NSLocalizedString(@"chat.gif.failed", nil)];
            return;
        }
        [_items removeAllObjects];
        for (ExteriaInlineResult *result in page.results) {
            if (!result.media && !result.thumb) continue;
            NSMutableDictionary *item = [NSMutableDictionary dictionaryWithObjectsAndKeys:result, @"result", [NSNumber numberWithLongLong:page.queryId], @"queryId", nil];
            if (result.media) [item setObject:result.media forKey:@"media"];
            [_items addObject:item];
        }
        [self showMessage:_items.count ? @"" : NSLocalizedString(@"chat.gif.none", nil)];
        [_table reloadData];
        [_table setContentOffset:CGPointZero animated:NO];
    }];
}

#pragma mark table

- (CGFloat)side {
    return floor((self.bounds.size.width - GAP * (COLUMNS - 1)) / COLUMNS);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return ((NSInteger)_items.count + COLUMNS - 1) / COLUMNS;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [self side] + GAP;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"gifs";
    ExteriaGifRow *row = (ExteriaGifRow *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!row) row = [[[ExteriaGifRow alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    row.target = self;
    CGFloat side = [self side];
    [row layoutColumns:COLUMNS side:side];
    NSUInteger token = _token;
    for (NSInteger i = 0; i < COLUMNS; ++i) {
        UIImageView *view = [row.views objectAtIndex:(NSUInteger)i];
        NSInteger index = indexPath.row * COLUMNS + i;
        view.image = nil;
        view.tag = index;
        view.backgroundColor = ExteriaColorField();
        view.hidden = index >= (NSInteger)_items.count;
        if (view.hidden) continue;
        NSDictionary *item = [_items objectAtIndex:(NSUInteger)index];
        ExteriaMedia *media = [item objectForKey:@"media"];
        ExteriaInlineResult *result = [item objectForKey:@"result"];
        CGFloat pixels = side * ExteriaScreenScale();
        ExteriaRemoteFile *file = media.previewFile ? media.previewFile : nil;
        if (file) {
            UIImage *ready = [_mediaCache cachedImageForFile:file maxSide:pixels];
            if (ready) {
                view.image = ready;
                continue;
            }
            [_mediaCache loadImageForFile:file maxSide:pixels completion:^(UIImage *image) {
                if (token == _token && view.tag == index && image) view.image = image;
            }];
        } else if (result.thumb) {
            [_session loadWebFile:result.thumb completion:^(NSData *data, NSString *errorName) {
                (void)errorName;
                if (token != _token || view.tag != index || !data) return;
                UIImage *image = [UIImage imageWithData:data];
                if (image) view.image = image;
            }];
        }
    }
    return row;
}

- (void)gifRow:(ExteriaGifRow *)row didTapColumn:(NSNumber *)column {
    NSIndexPath *path = [_table indexPathForCell:row];
    if (!path) return;
    NSInteger index = path.row * COLUMNS + [column integerValue];
    if (index < 0 || index >= (NSInteger)_items.count) return;
    NSDictionary *item = [_items objectAtIndex:(NSUInteger)index];
    ExteriaMedia *media = [item objectForKey:@"media"];
    ExteriaInlineResult *result = [item objectForKey:@"result"];
    if (media) [_delegate gifPicker:self didPickGif:media];
    else if (result) [_delegate gifPicker:self didPickInlineResult:result queryId:[[item objectForKey:@"queryId"] longLongValue]];
}

@end
