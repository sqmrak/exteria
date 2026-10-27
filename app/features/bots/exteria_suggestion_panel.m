#import "exteria_suggestion_panel.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_image_decoder.h"
#import "exteria_remote_file.h"
#import "exteria_session_bots.h"
#import "exteria_theme.h"

#define LIST_ROW 54.0
#define HEADER_ROW 46.0
#define THUMB 40.0
#define GALLERY_COLUMNS 3
#define GALLERY_GAP 2.0
/* a bot hosts its pictures wherever it likes, so one that answers with more than this is not fetched */
#define WEB_PICTURE_LIMIT (512 * 1024)
#define WEB_THUMB_SIDE 160.0

@implementation ExteriaSuggestion

@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize media = _media;
@synthesize webFile = _webFile;
@synthesize payload = _payload;

- (id)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle media:(ExteriaMedia *)media webFile:(ExteriaWebFile *)webFile payload:(id)payload {
    self = [super init];
    if (!self) return nil;
    _title = [title copy];
    _subtitle = [subtitle copy];
    _media = [media retain];
    _webFile = [webFile retain];
    _payload = [payload retain];
    return self;
}

- (void)dealloc {
    [_title release];
    [_subtitle release];
    [_media release];
    [_webFile release];
    [_payload release];
    [super dealloc];
}

@end

/* decoded pictures of the web, by address; the panel is short lived, the pictures are small and the count is capped */
static NSCache *ExteriaWebPictures(void) {
    static NSCache *cache = nil;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 80;
    }
    return cache;
}

static void ExteriaLoadWebPicture(ExteriaSession *session, ExteriaWebFile *file, void (^done)(UIImage *image)) {
    UIImage *known = [ExteriaWebPictures() objectForKey:file.url];
    if (known) {
        done(known);
        return;
    }
    void (^finish)(NSData *) = ^(NSData *data) {
        UIImage *image = data.length && data.length <= WEB_PICTURE_LIMIT ? ExteriaDecodeImage(data, WEB_THUMB_SIDE * 2) : nil;
        if (image) [ExteriaWebPictures() setObject:image forKey:file.url];
        done(image);
    };
    if (file.proxied) {
        [session loadWebFile:file completion:^(NSData *data, NSString *errorName) {
            (void)errorName;
            finish(data);
        }];
        return;
    }
    NSURL *url = [NSURL URLWithString:file.url];
    NSString *scheme = url.scheme.lowercaseString;
    if (!url || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) {
        done(nil);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
        NSString *type = response.MIMEType.lowercaseString;
        /* an error page with status 200 is html, and a picture is not */
        BOOL picture = [type hasPrefix:@"image/"];
        finish(!error && status == 200 && picture ? data : nil);
    }];
}

@interface ExteriaSuggestionCell : UITableViewCell {
@public
    UIImageView *thumb;
    ExteriaEmojiLabel *title;
    ExteriaEmojiLabel *subtitle;
    NSUInteger token;
    UIImageView *grid[GALLERY_COLUMNS];
}
@end

@implementation ExteriaSuggestionCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleGray;
    thumb = [[UIImageView alloc] init];
    thumb.contentMode = UIViewContentModeScaleAspectFill;
    thumb.clipsToBounds = YES;
    thumb.layer.cornerRadius = 6;
    [self.contentView addSubview:thumb];
    title = [[ExteriaEmojiLabel alloc] init];
    title.font = ExteriaFontMedium(16);
    title.textColor = ExteriaColorTitle();
    [self.contentView addSubview:title];
    subtitle = [[ExteriaEmojiLabel alloc] init];
    subtitle.font = ExteriaFontRegular(13);
    subtitle.textColor = ExteriaColorSecondary();
    [self.contentView addSubview:subtitle];
    return self;
}

- (void)dealloc {
    [thumb release];
    [title release];
    [subtitle release];
    for (int i = 0; i < GALLERY_COLUMNS; ++i) [grid[i] release];
    [super dealloc];
}

@end

@implementation ExteriaSuggestionPanel

@synthesize pickHandler = _pickHandler;
@synthesize moreHandler = _moreHandler;

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _items = [[NSMutableArray alloc] init];
    self.backgroundColor = ExteriaColorBar();
    _table = [[UITableView alloc] init];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorColor = ExteriaColorHairline();
    _table.dataSource = self;
    _table.delegate = self;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_table];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [self addSubview:_spinner];
    _empty = [[UILabel alloc] init];
    _empty.backgroundColor = [UIColor clearColor];
    _empty.textColor = ExteriaColorSecondary();
    _empty.font = ExteriaFontRegular(15);
    _empty.textAlignment = ExteriaTextAlignmentCenter;
    _empty.hidden = YES;
    [self addSubview:_empty];
    return self;
}

- (void)dealloc {
    _table.dataSource = nil;
    _table.delegate = nil;
    [_session release];
    [_media release];
    [_table release];
    [_spinner release];
    [_empty release];
    [_items release];
    [_headerTitle release];
    [_pickHandler release];
    [_headerHandler release];
    [_moreHandler release];
    [super dealloc];
}

- (NSUInteger)count {
    return _items.count;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _table.frame = self.bounds;
    _spinner.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    _empty.frame = CGRectMake(12, 0, self.bounds.size.width - 24, self.bounds.size.height);
}

- (void)setSuggestions:(NSArray *)items gallery:(BOOL)gallery {
    [_items setArray:items];
    _gallery = gallery;
    _empty.hidden = _items.count > 0 || !_empty.text.length;
    [_table reloadData];
    [_table setContentOffset:CGPointZero animated:NO];
}

- (void)appendSuggestions:(NSArray *)items {
    [_items addObjectsFromArray:items];
    [_table reloadData];
}

- (void)setHeaderTitle:(NSString *)title handler:(void (^)(void))handler {
    [_headerTitle release];
    _headerTitle = [title copy];
    [_headerHandler release];
    _headerHandler = [handler copy];
    [_table reloadData];
}

- (void)setLoading:(BOOL)loading {
    if (loading) [_spinner startAnimating];
    else [_spinner stopAnimating];
    if (loading) _empty.hidden = YES;
}

- (void)setEmptyText:(NSString *)text {
    _empty.text = text;
    _empty.hidden = _items.count > 0 || !text.length;
}

- (NSUInteger)galleryRows {
    return (_items.count + GALLERY_COLUMNS - 1) / GALLERY_COLUMNS;
}

- (CGFloat)galleryRowHeightForWidth:(CGFloat)width {
    return floor((width - (GALLERY_COLUMNS - 1) * GALLERY_GAP) / GALLERY_COLUMNS) + GALLERY_GAP;
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight {
    CGFloat content = _headerTitle.length ? HEADER_ROW : 0;
    content += _gallery ? [self galleryRows] * [self galleryRowHeightForWidth:width] : _items.count * LIST_ROW;
    if (!content) return _spinner.isAnimating || !_empty.hidden ? MIN(maxHeight, 90) : 0;
    return MIN(maxHeight, content);
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    NSInteger rows = _gallery ? (NSInteger)[self galleryRows] : (NSInteger)_items.count;
    return rows + (_headerTitle.length ? 1 : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_headerTitle.length && indexPath.row == 0) return HEADER_ROW;
    return _gallery ? [self galleryRowHeightForWidth:tableView.bounds.size.width] : LIST_ROW;
}

/* a picture for a row; a cell that was reused for another row meanwhile ignores the answer */
- (void)loadPictureOf:(ExteriaSuggestion *)suggestion into:(UIImageView *)view cell:(ExteriaSuggestionCell *)cell token:(NSUInteger)token side:(CGFloat)side {
    view.image = nil;
    view.backgroundColor = ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.08] : [UIColor colorWithWhite:0 alpha:0.06];
    ExteriaRemoteFile *file = suggestion.media.previewFile ? suggestion.media.previewFile : suggestion.media.file;
    if (file) {
        [_media loadImageForFile:file maxSide:side * 2 completion:^(UIImage *image) {
            if (cell->token == token && image) view.image = image;
        }];
        return;
    }
    if (suggestion.webFile) {
        ExteriaLoadWebPicture(_session, suggestion.webFile, ^(UIImage *image) {
            if (cell->token == token && image) view.image = image;
        });
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"suggestion";
    ExteriaSuggestionCell *cell = (ExteriaSuggestionCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaSuggestionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ++cell->token;
    CGFloat width = tableView.bounds.size.width;
    for (int i = 0; i < GALLERY_COLUMNS; ++i) cell->grid[i].hidden = YES;
    if (_headerTitle.length && indexPath.row == 0) {
        cell->thumb.hidden = YES;
        cell->subtitle.hidden = YES;
        cell->title.hidden = NO;
        cell->title.text = _headerTitle;
        cell->title.textColor = ExteriaColorAccent();
        cell->title.frame = CGRectMake(14, 0, width - 28, HEADER_ROW);
        return cell;
    }
    NSInteger index = indexPath.row - (_headerTitle.length ? 1 : 0);
    if (_gallery) {
        cell->thumb.hidden = YES;
        cell->title.hidden = YES;
        cell->subtitle.hidden = YES;
        CGFloat side = floor((width - (GALLERY_COLUMNS - 1) * GALLERY_GAP) / GALLERY_COLUMNS);
        for (int column = 0; column < GALLERY_COLUMNS; ++column) {
            NSUInteger at = (NSUInteger)index * GALLERY_COLUMNS + (NSUInteger)column;
            if (!cell->grid[column]) {
                UIImageView *view = [[UIImageView alloc] init];
                view.contentMode = UIViewContentModeScaleAspectFill;
                view.clipsToBounds = YES;
                view.userInteractionEnabled = YES;
                view.tag = column;
                [view addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(galleryTapped:)] autorelease]];
                [cell.contentView addSubview:view];
                cell->grid[column] = view;
            }
            UIImageView *view = cell->grid[column];
            view.frame = CGRectMake(column * (side + GALLERY_GAP), 0, side, side);
            view.hidden = at >= _items.count;
            if (at < _items.count) [self loadPictureOf:[_items objectAtIndex:at] into:view cell:cell token:cell->token side:side];
        }
        return cell;
    }
    ExteriaSuggestion *suggestion = [_items objectAtIndex:(NSUInteger)index];
    BOOL picture = suggestion.media || suggestion.webFile;
    CGFloat left = picture ? 14 + THUMB + 12 : 14;
    cell->thumb.hidden = !picture;
    cell->thumb.frame = CGRectMake(14, (LIST_ROW - THUMB) / 2, THUMB, THUMB);
    if (picture) [self loadPictureOf:suggestion into:cell->thumb cell:cell token:cell->token side:THUMB];
    BOOL hasSubtitle = suggestion.subtitle.length > 0;
    cell->title.hidden = NO;
    cell->title.text = suggestion.title;
    cell->title.textColor = ExteriaColorTitle();
    cell->title.frame = CGRectMake(left, hasSubtitle ? 8 : 0, width - left - 12, hasSubtitle ? 20 : LIST_ROW);
    cell->subtitle.hidden = !hasSubtitle;
    cell->subtitle.text = suggestion.subtitle;
    cell->subtitle.frame = CGRectMake(left, 29, width - left - 12, 17);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_headerTitle.length && indexPath.row == 0) {
        if (_headerHandler) _headerHandler();
        return;
    }
    if (_gallery) return;
    NSInteger index = indexPath.row - (_headerTitle.length ? 1 : 0);
    if (index >= 0 && index < (NSInteger)_items.count && _pickHandler) _pickHandler([_items objectAtIndex:(NSUInteger)index]);
}

#pragma mark gallery taps and paging

- (void)galleryTapped:(UITapGestureRecognizer *)tap {
    UIView *view = tap.view;
    UIView *cell = view.superview;
    while (cell && ![cell isKindOfClass:[UITableViewCell class]]) cell = cell.superview;
    NSIndexPath *path = cell ? [_table indexPathForCell:(UITableViewCell *)cell] : nil;
    if (!path) return;
    NSInteger index = (path.row - (_headerTitle.length ? 1 : 0)) * GALLERY_COLUMNS + view.tag;
    if (index >= 0 && index < (NSInteger)_items.count && _pickHandler) _pickHandler([_items objectAtIndex:(NSUInteger)index]);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat remaining = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.size.height;
    if (remaining < 120 && scrollView.contentSize.height > 0 && _moreHandler) _moreHandler();
}

@end
