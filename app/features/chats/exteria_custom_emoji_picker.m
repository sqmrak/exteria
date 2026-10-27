#import "exteria_custom_emoji_picker.h"

#import "exteria_custom_emoji.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_platform.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define STRIP_HEIGHT 36.0
#define CELL_SIDE 44.0
#define PICTURE_SIDE 32.0
#define NAME_PADDING 14.0

/* the emoji of one set drawn in one pass, so a set of hundreds is one view and not hundreds; only the rows in the dirty rect are drawn */
@interface ExteriaCustomEmojiGrid : UIView {
    NSArray *_emoji;
    NSUInteger _columns;
    id _target;
}
@property (nonatomic, retain) NSArray *emoji;
@property (nonatomic, assign) NSUInteger columns;
@property (nonatomic, assign) id target;
@end

@implementation ExteriaCustomEmojiGrid

@synthesize emoji = _emoji;
@synthesize columns = _columns;
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
    [_emoji release];
    [super dealloc];
}

- (void)drawRect:(CGRect)rect {
    if (!_columns) return;
    NSUInteger first = (NSUInteger)MAX(0, floor(rect.origin.y / CELL_SIDE)) * _columns;
    NSUInteger last = MIN(_emoji.count, ((NSUInteger)ceil(CGRectGetMaxY(rect) / CELL_SIDE) + 1) * _columns);
    CGFloat inset = (CELL_SIDE - PICTURE_SIDE) / 2;
    for (NSUInteger i = first; i < last; ++i) {
        ExteriaCustomEmojiDocument *document = [_emoji objectAtIndex:i];
        UIImage *picture = [ExteriaCustomEmoji imageForDocument:document.documentId];
        CGRect cell = CGRectMake(CELL_SIDE * (CGFloat)(i % _columns) + inset, CELL_SIDE * (CGFloat)(i / _columns) + inset, PICTURE_SIDE, PICTURE_SIDE);
        if (picture) [picture drawInRect:cell];
    }
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:self];
    if (!_columns || point.x < 0 || point.y < 0) return;
    NSUInteger column = (NSUInteger)(point.x / CELL_SIDE), row = (NSUInteger)(point.y / CELL_SIDE);
    if (column >= _columns || row * _columns + column >= _emoji.count) return;
    [_target performSelector:@selector(gridDidPick:) withObject:[_emoji objectAtIndex:row * _columns + column]];
}

@end

@interface ExteriaCustomEmojiPicker () {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    UIScrollView *_strip;
    UIScrollView *_scroll;
    ExteriaCustomEmojiGrid *_grid;
    UILabel *_status;
    NSArray *_sets;
    NSMutableDictionary *_loaded;
    NSMutableArray *_buttons;
    UIButton *_leading;
    BOOL _hasLeading;
    BOOL _leadingSelected;
    BOOL _showsLocks;
    ExteriaSymbol _leadingSymbol;
    NSString *_leadingLabel;
    NSUInteger _current;
    BOOL _loadingSets;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaCustomEmojiPicker

@synthesize delegate = _delegate;
@synthesize hasLeading = _hasLeading;
@synthesize leadingSymbol = _leadingSymbol;
@synthesize leadingLabel = _leadingLabel;
@synthesize showsLocks = _showsLocks;

- (void)setShowsLocks:(BOOL)showsLocks {
    if (_showsLocks == showsLocks) return;
    _showsLocks = showsLocks;
    [self paintTabs];
    [self setNeedsLayout];
}

+ (CGFloat)stripHeight { return STRIP_HEIGHT; }

- (void)setHasLeading:(BOOL)hasLeading {
    _hasLeading = hasLeading;
    _leadingSelected = hasLeading;
    if (!hasLeading) {
        [_leading removeFromSuperview];
        [_leading release];
        _leading = nil;
        return;
    }
    if (_leading) return;
    _leading = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_leading addTarget:self action:@selector(leadingTapped) forControlEvents:UIControlEventTouchUpInside];
    [_strip addSubview:_leading];
    _scroll.hidden = YES;
    [self paintTabs];
    [self setNeedsLayout];
}

- (void)paintTabs {
    [_leading setImage:ExteriaSymbolImage(_leadingSymbol, 20, _leadingSelected ? ExteriaColorAccent() : ExteriaColorMuted()) forState:UIControlStateNormal];
    _leading.accessibilityLabel = _leadingLabel;
    for (UIButton *button in _buttons) {
        BOOL chosen = !_leadingSelected && (NSUInteger)button.tag == _current;
        [button setTitleColor:chosen ? ExteriaColorAccent() : ExteriaColorMuted() forState:UIControlStateNormal];
        [button setImage:_showsLocks ? ExteriaSymbolImage(ExteriaSymbolLock, 12, chosen ? ExteriaColorAccent() : ExteriaColorMuted()) : nil forState:UIControlStateNormal];
    }
}

- (void)leadingTapped {
    _leadingSelected = YES;
    _scroll.hidden = YES;
    [self showStatus:nil];
    [self paintTabs];
    if ([_delegate respondsToSelector:@selector(customEmojiPickerDidSelectLeading:)]) [_delegate customEmojiPickerDidSelectLeading:self];
}

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _loaded = [[NSMutableDictionary alloc] init];
    _buttons = [[NSMutableArray alloc] init];
    _strip = [[UIScrollView alloc] init];
    _strip.showsHorizontalScrollIndicator = NO;
    [self addSubview:_strip];
    _scroll = [[UIScrollView alloc] init];
    [self addSubview:_scroll];
    _grid = [[ExteriaCustomEmojiGrid alloc] init];
    _grid.target = self;
    [_scroll addSubview:_grid];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.font = ExteriaFontRegular(14);
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [self addSubview:_status];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _grid.target = nil;
    [_session release];
    [_media release];
    [_strip release];
    [_scroll release];
    [_grid release];
    [_status release];
    [_leading release];
    [_leadingLabel release];
    [_sets release];
    [_loaded release];
    [_buttons release];
    [super dealloc];
}

- (void)showStatus:(NSString *)text {
    _status.text = text;
    _status.hidden = text.length == 0;
    [self setNeedsLayout];
}

- (void)prepare {
    if (_sets || _loadingSets) {
        if (!_leadingSelected) [self loadCurrentSet];
        return;
    }
    _loadingSets = YES;
    if (!_leadingSelected) [self showStatus:NSLocalizedString(@"emoji.premium.loading", nil)];
    ExteriaWeakReference *weak = _weak;
    [_session loadEmojiSets:^(NSArray *items, NSString *errorName) {
        ExteriaCustomEmojiPicker *picker = weak.target;
        if (!picker) return;
        picker->_loadingSets = NO;
        if (!items) {
            NSLog(@"exteria: custom emoji sets not loaded: %@", errorName);
            [picker showStatus:NSLocalizedString(@"emoji.premium.failed", nil)];
            return;
        }
        picker->_sets = [items retain];
        [picker buildStrip];
        if (picker->_leadingSelected) [picker paintTabs];
        else [picker selectSet:0];
    }];
}

- (void)buildStrip {
    for (UIView *button in _buttons) [button removeFromSuperview];
    [_buttons removeAllObjects];
    for (NSUInteger i = 0; i < _sets.count; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = (NSInteger)i;
        button.titleLabel.font = ExteriaFontSemibold(14);
        [button setTitle:[[_sets objectAtIndex:i] title] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(setTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_strip addSubview:button];
        [_buttons addObject:button];
    }
    [self paintTabs];
    [self setNeedsLayout];
}

- (void)setTapped:(UIButton *)button {
    [self selectSet:(NSUInteger)button.tag];
}

- (void)selectSet:(NSUInteger)index {
    if (index >= _sets.count) {
        if (!_leadingSelected) [self showStatus:NSLocalizedString(@"emoji.premium.none", nil)];
        return;
    }
    _current = index;
    _leadingSelected = NO;
    _scroll.hidden = NO;
    [self paintTabs];
    if ([_delegate respondsToSelector:@selector(customEmojiPickerDidSelectSet:)]) [_delegate customEmojiPickerDidSelectSet:self];
    [_scroll setContentOffset:CGPointZero animated:NO];
    [self loadCurrentSet];
}

- (void)loadCurrentSet {
    if (_current >= _sets.count) return;
    ExteriaStickerSet *set = [_sets objectAtIndex:_current];
    NSNumber *key = [NSNumber numberWithLongLong:set.setId];
    NSArray *known = [_loaded objectForKey:key];
    if (known) {
        [self showEmoji:known];
        return;
    }
    _grid.emoji = nil;
    [self showStatus:NSLocalizedString(@"emoji.premium.loading", nil)];
    ExteriaWeakReference *weak = _weak;
    [_session loadEmojiOfSet:set completion:^(NSArray *items, NSString *errorName) {
        ExteriaCustomEmojiPicker *picker = weak.target;
        if (!picker) return;
        if (!items) {
            NSLog(@"exteria: custom emoji of set %lld not loaded: %@", set.setId, errorName);
            if (picker->_current < picker->_sets.count && [[picker->_sets objectAtIndex:picker->_current] setId] == set.setId)
                [picker showStatus:NSLocalizedString(@"emoji.premium.failed", nil)];
            return;
        }
        [picker->_loaded setObject:items forKey:key];
        if (picker->_current < picker->_sets.count && [[picker->_sets objectAtIndex:picker->_current] setId] == set.setId) [picker showEmoji:items];
    }];
}

- (void)showEmoji:(NSArray *)emoji {
    [self showStatus:emoji.count ? nil : NSLocalizedString(@"emoji.premium.none", nil)];
    _grid.emoji = emoji;
    [self setNeedsLayout];
    ExteriaWeakReference *weak = _weak;
    [ExteriaCustomEmojiLoader loadPicturesOfDocuments:emoji media:_media picture:^{
        ExteriaCustomEmojiPicker *picker = weak.target;
        if (picker) [picker->_grid setNeedsDisplay];
    }];
}

- (void)gridDidPick:(ExteriaCustomEmojiDocument *)emoji {
    [_delegate customEmojiPicker:self didPickEmoji:emoji];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _strip.frame = CGRectMake(0, 0, size.width, STRIP_HEIGHT);
    CGFloat x = 8;
    if (_leading) {
        _leading.frame = CGRectMake(x, 0, 44, STRIP_HEIGHT);
        x += 44;
    }
    for (UIButton *button in _buttons) {
        CGFloat width = ceil(ExteriaStringSize([button titleForState:UIControlStateNormal], button.titleLabel.font).width) + 2 * NAME_PADDING + (_showsLocks ? 16 : 0);
        button.frame = CGRectMake(x, 0, width, STRIP_HEIGHT);
        x += width;
    }
    _strip.contentSize = CGSizeMake(x + 8, STRIP_HEIGHT);
    _scroll.frame = CGRectMake(0, STRIP_HEIGHT, size.width, size.height - STRIP_HEIGHT);
    NSUInteger columns = MAX((NSUInteger)1, (NSUInteger)(size.width / CELL_SIDE));
    NSUInteger rows = (_grid.emoji.count + columns - 1) / columns;
    CGFloat left = floor((size.width - CELL_SIDE * (CGFloat)columns) / 2);
    _grid.columns = columns;
    _grid.frame = CGRectMake(left, 0, CELL_SIDE * (CGFloat)columns, CELL_SIDE * (CGFloat)rows);
    _scroll.contentSize = _grid.frame.size;
    _status.frame = CGRectMake(24, STRIP_HEIGHT + 24, size.width - 48, 60);
    [_grid setNeedsDisplay];
}

@end
