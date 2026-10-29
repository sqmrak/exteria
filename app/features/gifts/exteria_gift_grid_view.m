#import "exteria_gift_grid_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_gift_backdrop_view.h"
#import "exteria_gift_screen.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define TILE_TARGET 96.0
#define TILE_GAP 8.0
/* a tile never grows past this, so two columns on a phone leave room at the sides instead of filling the screen */
#define TILE_MAX 128.0
#define TILE_RADIUS 12.0
#define PICTURE 76.0
/* a profile card: the picture takes this share of the width, the corner marks and the hidden mark are shares of it too */
#define CARD_PICTURE 0.66
#define CORNER_MARK 0.22
#define CORNER_INSET 0.055
#define VEIL_MARK 0.26
/* the brown disc of the hidden mark */
#define HIDDEN_MARK_COLOR 0x6b3412

@implementation ExteriaGiftTileInfo

@synthesize sticker = _sticker;
@synthesize localImage = _localImage;
@synthesize expressive = _expressive;
@synthesize pictureFile = _pictureFile;
@synthesize title = _title;
@synthesize starsAmount = _starsAmount;
@synthesize caption = _caption;
@synthesize badge = _badge;
@synthesize hasBackdrop = _hasBackdrop;
@synthesize backdropCenter = _backdropCenter;
@synthesize backdropEdge = _backdropEdge;
@synthesize dimmed = _dimmed;
@synthesize card = _card;
@synthesize story = _story;
@synthesize unique = _unique;
@synthesize pinned = _pinned;
@synthesize hiddenMark = _hiddenMark;
@synthesize anonymous = _anonymous;
@synthesize ribbon = _ribbon;
@synthesize patternSticker = _patternSticker;
@synthesize patternColor = _patternColor;
@synthesize fromPhoto = _fromPhoto;
@synthesize fromSeed = _fromSeed;
@synthesize fromInitials = _fromInitials;

- (void)dealloc {
    [_sticker release];
    [_localImage release];
    [_pictureFile release];
    [_title release];
    [_caption release];
    [_badge release];
    [_ribbon release];
    [_patternSticker release];
    [_fromPhoto release];
    [_fromInitials release];
    [super dealloc];
}

@end

/* one gift: a card, its picture, a line of text under it and a smaller one above; a profile card has the picture large and
   its marks in the corners instead */
@interface ExteriaGiftTile : UIView {
    UIImageView *_picture;
    ExteriaLottieView *_poster;
    UILabel *_title;
    UIImageView *_price;
    UILabel *_caption;
    UILabel *_badge;
    ExteriaGiftBackdropView *_backdrop;
    ExteriaGiftRibbonView *_ribbonView;
    ExteriaAvatarView *_sender;
    UIImageView *_spy;
    UIView *_pinDisc;
    UIImageView *_pin;
    UIView *_veil;
    UIImageView *_veilEye;
    BOOL _card;
    BOOL _pinLeft;
    BOOL _story;
    NSUInteger _token;
}
- (void)configureWithInfo:(ExteriaGiftTileInfo *)info media:(ExteriaMediaCache *)media avatars:(ExteriaAvatarCache *)avatars;
@end

@implementation ExteriaGiftTile

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.layer.cornerRadius = TILE_RADIUS;
    self.layer.masksToBounds = YES;
    _backdrop = [[ExteriaGiftBackdropView alloc] init];
    _backdrop.hidden = YES;
    [self addSubview:_backdrop];
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_picture];
    _ribbonView = [[ExteriaGiftRibbonView alloc] init];
    _ribbonView.hidden = YES;
    [self addSubview:_ribbonView];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textAlignment = ExteriaTextAlignmentCenter;
    _title.font = ExteriaFontSemibold(13);
    _title.adjustsFontSizeToFitWidth = YES;
    [self addSubview:_title];
    _price = [[UIImageView alloc] init];
    _price.contentMode = UIViewContentModeCenter;
    [self addSubview:_price];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textAlignment = ExteriaTextAlignmentCenter;
    _caption.font = ExteriaFontRegular(10);
    [self addSubview:_caption];
    _badge = [[UILabel alloc] init];
    _badge.backgroundColor = [UIColor clearColor];
    _badge.textAlignment = ExteriaTextAlignmentRight;
    _badge.font = ExteriaFontRegular(12);
    [self addSubview:_badge];
    _sender = [[ExteriaAvatarView alloc] init];
    _sender.circular = YES;
    [self addSubview:_sender];
    _spy = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"gift_anonymous"]];
    _spy.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_spy];
    _pinDisc = [[UIView alloc] init];
    _pinDisc.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
    [self addSubview:_pinDisc];
    _pin = [[UIImageView alloc] init];
    _pin.contentMode = UIViewContentModeCenter;
    [_pinDisc addSubview:_pin];
    _veil = [[UIView alloc] init];
    _veil.backgroundColor = ExteriaGiftRgb(HIDDEN_MARK_COLOR);
    [self addSubview:_veil];
    _veilEye = [[UIImageView alloc] init];
    _veilEye.contentMode = UIViewContentModeCenter;
    [_veil addSubview:_veilEye];
    return self;
}

- (void)dealloc {
    [_picture release];
    [_poster release];
    [_title release];
    [_price release];
    [_caption release];
    [_badge release];
    [_backdrop release];
    [_ribbonView release];
    [_sender release];
    [_spy release];
    [_pinDisc release];
    [_pin release];
    [_veil release];
    [_veilEye release];
    [super dealloc];
}

- (CGRect)pictureFrame {
    CGSize size = self.bounds.size;
    if (_story) return self.bounds;
    if (_card) {
        CGFloat side = floor(size.width * CARD_PICTURE);
        return CGRectMake((size.width - side) / 2, (size.height - side) / 2, side, side);
    }
    CGFloat side = MIN(PICTURE, size.width - 16);
    return CGRectMake((size.width - side) / 2, 16, side, side);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _backdrop.frame = self.bounds;
    _ribbonView.frame = self.bounds;
    CGRect picture = [self pictureFrame];
    _picture.frame = picture;
    _poster.frame = picture;
    _caption.frame = CGRectMake(4, 3, size.width - 8, 13);
    _badge.frame = CGRectMake(4, 3, size.width - 10, 16);
    _title.frame = CGRectMake(6, size.height - 24, size.width - 12, 18);
    _price.frame = _title.frame;
    if (_story) {
        CGFloat captionWidth = MIN(size.width - 10, ceil([_caption sizeThatFits:CGSizeMake(size.width - 10, 18)].width) + 6);
        CGFloat titleLimit = size.width - (_badge.text.length ? 30 : 10);
        CGFloat titleWidth = MIN(titleLimit, ceil([_title sizeThatFits:CGSizeMake(titleLimit, 18)].width) + 6);
        _caption.frame = CGRectMake(5, size.height - 23, captionWidth, 18);
        _title.frame = CGRectMake(5, 5, titleWidth, 18);
        _badge.frame = CGRectMake(5, 5, size.width - 10, 18);
    }
    if (!_card) return;
    CGFloat disc = floor(size.width * CORNER_MARK), inset = floor(size.width * CORNER_INSET);
    CGRect left = CGRectMake(inset, inset, disc, disc);
    CGRect right = CGRectMake(size.width - inset - disc, inset, disc, disc);
    _sender.frame = left;
    _spy.frame = left;
    /* the pin takes the left corner of a unique gift, which has no sender picture, and the right one of a regular gift */
    _pinDisc.frame = _pinLeft ? left : right;
    _pinDisc.layer.cornerRadius = disc / 2;
    _pin.frame = _pinDisc.bounds;
    CGFloat veil = floor(size.width * VEIL_MARK);
    _veil.frame = CGRectMake(floor((size.width - veil) / 2), floor((size.height - veil) / 2), veil, veil);
    _veil.layer.cornerRadius = veil / 2;
    _veilEye.frame = _veil.bounds;
}

- (void)configureWithInfo:(ExteriaGiftTileInfo *)info media:(ExteriaMediaCache *)media avatars:(ExteriaAvatarCache *)avatars {
    ++_token;
    NSUInteger token = _token;
    _card = info.card;
    _story = info.story;
    _picture.contentMode = _story ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    BOOL plain = !info.hasBackdrop;
    self.backgroundColor = plain ? ExteriaColorCard() : ExteriaGiftRgb(info.backdropEdge);
    _backdrop.hidden = plain;
    _backdrop.symbol = nil;
    _ribbonView.hidden = plain || !info.ribbon.length;
    _ribbonView.text = plain ? nil : info.ribbon;
    _ribbonView.edgeColor = info.backdropEdge;
    _backdrop.expressive = info.expressive;
    if (!plain) {
        _backdrop.centerColor = info.backdropCenter;
        _backdrop.edgeColor = info.backdropEdge;
        _backdrop.patternColor = info.patternColor;
        if (info.patternSticker) {
            ExteriaGiftLoadPatternSymbol(media, info.patternSticker, info.patternColor, ^(UIImage *symbol) {
                if (token == _token) _backdrop.symbol = symbol;
            });
        }
    }
    _title.text = info.starsAmount > 0 ? nil : info.title;
    _title.textColor = _story ? [UIColor whiteColor] : (plain ? ExteriaColorTitle() : [UIColor whiteColor]);
    _title.textAlignment = _story ? ExteriaTextAlignmentLeft : ExteriaTextAlignmentCenter;
    _title.backgroundColor = _story ? [UIColor colorWithWhite:0 alpha:0.45] : [UIColor clearColor];
    _price.image = info.starsAmount > 0 ? ExteriaStarsImage(nil, info.starsAmount, _title.font, _title.textColor) : nil;
    _caption.text = info.caption;
    _caption.textColor = _story ? [UIColor whiteColor] : (plain ? ExteriaColorSecondary() : [UIColor colorWithWhite:1 alpha:0.8]);
    _caption.textAlignment = _story ? ExteriaTextAlignmentLeft : ExteriaTextAlignmentCenter;
    _caption.backgroundColor = _story ? [UIColor colorWithWhite:0 alpha:0.45] : [UIColor clearColor];
    _badge.text = info.badge;
    _badge.textColor = _story ? [UIColor whiteColor] : (plain ? ExteriaColorSecondary() : [UIColor whiteColor]);
    _caption.hidden = (!_story && info.badge.length > 0) || _card || !info.caption.length;
    _title.hidden = _card;
    _price.hidden = _card;
    _badge.hidden = _card;
    [self configureMarks:info avatars:avatars];
    self.alpha = info.dimmed ? 0.5 : 1.0;
    _picture.image = nil;
    [_poster removeFromSuperview];
    [_poster release];
    _poster = nil;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if (info.localImage) {
        _picture.image = info.localImage;
        return;
    }
    ExteriaMedia *sticker = info.sticker;
    if (!sticker && !info.pictureFile) return;
    CGRect pictureFrame = [self pictureFrame];
    CGFloat pixels = MAX(pictureFrame.size.width, pictureFrame.size.height) * ExteriaScreenScale();
    BOOL still = sticker.stickerFormat == EXTERIA_STICKER_STATIC || info.pictureFile != nil;
    ExteriaRemoteFile *file = info.pictureFile ? info.pictureFile : (still ? sticker.file : sticker.previewFile);
    if (file) {
        UIImage *ready = [media cachedImageForFile:file maxSide:pixels];
        if (ready) { _picture.image = ready; return; }
        [media loadImageForFile:file maxSide:pixels completion:^(UIImage *image) {
            if (token == _token && image) _picture.image = image;
            else if (token == _token && !still) [self loadPosterOf:sticker media:media token:token];
        }];
        return;
    }
    if (!still) [self loadPosterOf:sticker media:media token:token];
}

/* the corner marks of a profile card: the sender (or the spy) on the left of a regular gift, the pin where it belongs and the
   hidden mark over the picture */
- (void)configureMarks:(ExteriaGiftTileInfo *)info avatars:(ExteriaAvatarCache *)avatars {
    BOOL sender = _card && !info.unique;
    BOOL spy = sender && info.anonymous;
    _sender.hidden = !sender || spy;
    _spy.hidden = !spy;
    if (!_sender.hidden) {
        _sender.seed = info.fromSeed;
        _sender.initials = info.fromInitials;
        [_sender setPhoto:info.fromPhoto cache:avatars];
    }
    BOOL pinned = _card && info.pinned;
    _pinDisc.hidden = !pinned;
    _pinLeft = info.unique;
    if (pinned) _pin.image = ExteriaSymbolImage(ExteriaSymbolPin, 15, [UIColor whiteColor]);
    _veil.hidden = !(_card && info.hiddenMark);
    if (!_veil.hidden) _veilEye.image = ExteriaSymbolImage(ExteriaSymbolEyeSlash, 22, [UIColor whiteColor]);
}

/* an animated gift without a usable thumbnail shows the first frame of its animation */
- (void)loadPosterOf:(ExteriaMedia *)sticker media:(ExteriaMediaCache *)media token:(NSUInteger)token {
    ExteriaRemoteFile *file = sticker.file;
    if (!file) return;
    [media loadDataForFile:file completion:^(NSData *data) {
        if (token != _token || !data) return;
        _poster = [[ExteriaLottieView alloc] initWithPackedData:data key:file.key];
        _poster.frame = _picture.frame;
        [self insertSubview:_poster aboveSubview:_picture];
        [_poster setLoaded:YES];
    }];
}

@end

@interface ExteriaGiftRow : UITableViewCell {
    NSMutableArray *_tiles;
}
@property (nonatomic, readonly) NSMutableArray *tiles;
@end

@implementation ExteriaGiftRow

@synthesize tiles = _tiles;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.backgroundColor = [UIColor clearColor];
    _tiles = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_tiles release];
    [super dealloc];
}

@end

@interface ExteriaGiftGridView () {
    ExteriaMediaCache *_media;
    ExteriaAvatarCache *_avatars;
    UITableView *_table;
    NSArray *_tiles;
    NSInteger _columns;
    CGFloat _tileWidth;
    CGFloat _margin;
    UIView *_headerView;
    CGFloat _bottomInset;
    CGFloat _topInset;
}
@end

@implementation ExteriaGiftGridView

@synthesize delegate = _delegate;
@synthesize avatars = _avatars;
@synthesize headerView = _headerView;
@synthesize bottomInset = _bottomInset;
@synthesize topInset = _topInset;

- (id)initWithMedia:(ExteriaMediaCache *)media {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _media = [media retain];
    _table = [[UITableView alloc] init];
    ExteriaScrollViewOwnsInsets(_table);
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.allowsSelection = NO;
    [self addSubview:_table];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    tap.delegate = self;
    [_table addGestureRecognizer:tap];
    _tiles = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    _table.dataSource = nil;
    _table.delegate = nil;
    [_media release];
    [_avatars release];
    [_table release];
    [_tiles release];
    [_headerView release];
    [super dealloc];
}

- (void)setHeaderView:(UIView *)view {
    if (view != _headerView) {
        [_headerView release];
        _headerView = [view retain];
    }
    /* a table drops its offset to the top when the header changes height, so a profile scrolled to its tabs jumped to the start on every
       tab switch; the offset is put back, held inside the new content */
    CGPoint offset = _table.contentOffset;
    _table.tableHeaderView = view;
    CGFloat lowest = _table.contentSize.height - _table.bounds.size.height + _table.contentInset.bottom;
    CGFloat highest = MAX(-_table.contentInset.top, lowest);
    offset.y = MAX(-_table.contentInset.top, MIN(offset.y, highest));
    _table.contentOffset = offset;
}

/* the last tiles clear whichever is deeper, the strip a screen above a tab bar gives or the home indicator; the table does not add the indicator itself */
- (void)applyBottomInset {
    UIEdgeInsets insets = _table.contentInset;
    CGFloat bottom = MAX(_bottomInset, ExteriaSafeInsets(self).bottom);
    if (insets.bottom == bottom) return;
    insets.bottom = bottom;
    _table.contentInset = insets;
    _table.scrollIndicatorInsets = insets;
}

- (void)setTopInset:(CGFloat)inset {
    if (fabs(inset - _topInset) < 0.5) return;
    UIEdgeInsets insets = _table.contentInset;
    BOOL atTop = _table.contentOffset.y <= -insets.top + 0.5;
    _topInset = inset;
    insets.top = inset;
    _table.contentInset = insets;
    UIEdgeInsets indicator = _table.scrollIndicatorInsets;
    indicator.top = inset;
    _table.scrollIndicatorInsets = indicator;
    if (atTop) _table.contentOffset = CGPointMake(_table.contentOffset.x, -inset);
}

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    [self applyBottomInset];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ([_delegate respondsToSelector:@selector(giftGrid:didScrollToOffset:)]) [_delegate giftGrid:self didScrollToOffset:scrollView.contentOffset.y];
}

- (void)setTiles:(NSArray *)tiles {
    [_tiles release];
    _tiles = [tiles copy];
    [_table reloadData];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _table.frame = self.bounds;
    [self applyBottomInset];
    NSInteger columns = MAX(2, (NSInteger)floor((width - TILE_GAP) / (TILE_TARGET + TILE_GAP)));
    /* a rotation changes the tile width even when the column count stays, and the rows hold frames from the old width */
    CGFloat tileWidth = MIN(TILE_MAX, (width - TILE_GAP * (CGFloat)(columns + 1)) / (CGFloat)columns);
    CGFloat margin = floor((width - tileWidth * (CGFloat)columns - TILE_GAP * (CGFloat)(columns - 1)) / 2);
    BOOL changed = columns != _columns || tileWidth != _tileWidth || margin != _margin;
    _columns = columns;
    _tileWidth = tileWidth;
    _margin = margin;
    if (changed) [_table reloadData];
}

/* profile cards are square, stories follow the portrait proportions of the media grid */
- (CGFloat)tileHeight {
    if (_tiles.count && ((ExteriaGiftTileInfo *)[_tiles objectAtIndex:0]).story) return floor(_tileWidth * 1.25);
    if (_tiles.count && ((ExteriaGiftTileInfo *)[_tiles objectAtIndex:0]).card) return _tileWidth;
    return PICTURE + 44;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if (!_columns) return 0;
    return ((NSInteger)_tiles.count + _columns - 1) / _columns;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [self tileHeight] + TILE_GAP;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"gifts";
    ExteriaGiftRow *row = (ExteriaGiftRow *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!row) row = [[[ExteriaGiftRow alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    while ((NSInteger)row.tiles.count < _columns) {
        ExteriaGiftTile *tile = [[[ExteriaGiftTile alloc] init] autorelease];
        [row.contentView addSubview:tile];
        [row.tiles addObject:tile];
    }
    for (NSInteger i = 0; i < (NSInteger)row.tiles.count; ++i) {
        ExteriaGiftTile *tile = [row.tiles objectAtIndex:(NSUInteger)i];
        NSInteger index = indexPath.row * _columns + i;
        if (i >= _columns || index >= (NSInteger)_tiles.count) {
            tile.hidden = YES;
            continue;
        }
        tile.hidden = NO;
        tile.tag = index;
        tile.frame = CGRectMake(_margin + (CGFloat)i * (_tileWidth + TILE_GAP), 0, _tileWidth, [self tileHeight]);
        [tile configureWithInfo:[_tiles objectAtIndex:(NSUInteger)index] media:_media avatars:_avatars];
    }
    if ((indexPath.row + 1) * _columns >= (NSInteger)_tiles.count && [_delegate respondsToSelector:@selector(giftGridReachedEnd:)]) {
        [_delegate giftGridReachedEnd:self];
    }
    return row;
}

/* the head above the tiles has buttons of its own, and a recognizer that took their touches would leave them dead */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return !(_headerView && [touch.view isDescendantOfView:_headerView]);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:_table];
    NSIndexPath *path = [_table indexPathForRowAtPoint:point];
    if (!path) return;
    ExteriaGiftRow *row = (ExteriaGiftRow *)[_table cellForRowAtIndexPath:path];
    CGPoint inRow = [tap locationInView:row.contentView];
    for (ExteriaGiftTile *tile in row.tiles) {
        if (!tile.hidden && CGRectContainsPoint(tile.frame, inRow)) {
            [_delegate giftGrid:self didSelectIndex:(NSUInteger)tile.tag];
            return;
        }
    }
}

@end
