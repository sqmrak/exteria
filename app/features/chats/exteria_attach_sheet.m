#import "exteria_attach_sheet.h"
#import "exteria_chat_settings.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#import "exteria_attach_options.h"
#import "exteria_centered_hint_field.h"
#import "exteria_platform.h"
#import "exteria_plural.h"
#import "exteria_popup_menu.h"
#import "exteria_photo_library.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"


#define ASSETS_MAX 300
#define SELECTION_MAX 10
#define BAR_HEIGHT 70.0
#define CAPTION_HEIGHT 64.0
#define HEADER_HEIGHT 56.0

#define PANEL_RADIUS 14.0
/* the sheet comes and goes like the card of the Shiro screen: the same time, the same curves, the same throw that sends it away */
#define SLIDE_SECONDS 0.3
#define SETTLE_SECONDS 0.2
#define DISMISS_DISTANCE 110.0
#define DISMISS_VELOCITY 700.0
#define DIM_ALPHA 0.45
#define GRABBER_WIDTH 40.0
#define GRABBER_HEIGHT 5.0
/* the ring in the corner of a picture that marks it for sending */
#define CHECK_SIDE 22.0
#define CHECK_TARGET 44.0
#define SEND_SIDE 44.0
/* the room above a sheet that rises over the keyboard */
#define KEYBOARD_TOP_ROOM 24.0

@interface ExteriaAttachSheet () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate, UITextFieldDelegate> {
    UIView *_dim;
    UIView *_panel;
    CAShapeLayer *_panelMask;
    CGFloat _panelRestY;
    CGFloat _pullStart;
    CGFloat _pullRestY;
    UIView *_bar;
    UIView *_line;
    UIView *_grabber;
    UILabel *_title;
    UIButton *_more;
    UIView *_captionBar;
    ExteriaCenteredHintField *_caption;
    UIButton *_send;
    UILabel *_count;
    UITableView *_grid;
    ALAssetsLibrary *_library;
    NSMutableArray *_assets;
    NSMutableArray *_selected;
    NSArray *_buttons;
    NSArray *_labels;
    NSInteger _columns;
    CGFloat _cellSide;
    CGFloat _keyboard;
    BOOL _leaving;
    BOOL _photos;
    BOOL _pulling;
    /* the choices of the menu behind the dots, kept for as long as the sheet is open */
    BOOL _asFiles;
    BOOL _spoiler;
    BOOL _standard;
    BOOL _viewOnce;
    ExteriaPopupMenu *_menu;
}
@end

/* a picture picked to go under a spoiler shows as the receiver will see it: shrunk to a few points and drawn large again with smoothing, a blur that costs nothing in a scrolling grid */
static UIImage *ExteriaAttachBlurred(UIImage *image) {
    CGSize size = image.size;
    if (size.width < 1 || size.height < 1) return image;
    CGFloat scale = MIN(1, 12.0 / MAX(size.width, size.height));
    CGSize small = CGSizeMake(MAX(2, floor(size.width * scale)), MAX(2, floor(size.height * scale)));
    UIGraphicsBeginImageContextWithOptions(small, YES, 1);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [image drawInRect:CGRectMake(0, 0, small.width, small.height)];
    UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return made ? made : image;
}

@implementation ExteriaAttachSheet
@synthesize delegate = _delegate;
@synthesize offersGift = _offersGift;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _assets = [[NSMutableArray alloc] init];
    _selected = [[NSMutableArray alloc] init];
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor blackColor];
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:_dim];
    _panel = [[UIView alloc] init];
    _panel.backgroundColor = ExteriaColorCard();
    _panelMask = [[CAShapeLayer alloc] init];
    _panel.layer.mask = _panelMask;
    [self addSubview:_panel];
    /* a pull down on the header, on the bar or on the pictures at their top edge takes the sheet away, as the card of the Shiro screen goes */
    UIPanGestureRecognizer *pull = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pulled:)] autorelease];
    pull.delegate = self;
    [_panel addGestureRecognizer:pull];
    /* the pill that says the sheet can be pulled down */
    _grabber = [[UIView alloc] init];
    _grabber.backgroundColor = ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.22] : [UIColor colorWithWhite:0 alpha:0.18];
    _grabber.layer.cornerRadius = GRABBER_HEIGHT / 2;
    _grabber.userInteractionEnabled = NO;
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.font = ExteriaFontBold(20);
    _title.textColor = ExteriaColorTitle();
    _more = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_more setImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_more addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    _more.accessibilityLabel = NSLocalizedString(@"attach.more", nil);
    _more.hidden = YES;
    _grid = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _grid.backgroundColor = ExteriaColorField();
    _grid.separatorStyle = UITableViewCellSeparatorStyleNone;
    _grid.dataSource = self; _grid.delegate = self;
    _grid.scrollsToTop = NO;
    [_panel addSubview:_grid];
    [_panel addSubview:_title];
    [_panel addSubview:_more];
    [_panel addSubview:_grabber];
    _bar = [[UIView alloc] init];
    _bar.backgroundColor = ExteriaColorCard();
    [_panel addSubview:_bar];
    _line = [[UIView alloc] init];
    _line.backgroundColor = ExteriaColorSecondary();
    _line.alpha = 0.25;
    [_bar addSubview:_line];
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"attach.gallery", nil), NSLocalizedString(@"attach.file", nil),
        NSLocalizedString(@"attach.location", nil), NSLocalizedString(@"attach.gift", nil), NSLocalizedString(@"attach.contact", nil), nil];
    ExteriaSymbol symbols[] = {ExteriaSymbolGallery, ExteriaSymbolDocument, ExteriaSymbolMapPin, ExteriaSymbolGift, ExteriaSymbolPerson};
    NSMutableArray *buttons = [NSMutableArray array], *labels = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setImage:ExteriaSymbolImage(symbols[i], 25, i == 0 ? ExteriaColorAccent() : ExteriaColorSecondary()) forState:UIControlStateNormal];
        button.tag = (NSInteger)i;
        button.accessibilityLabel = [titles objectAtIndex:i];
        [button addTarget:self action:@selector(chosen:) forControlEvents:UIControlEventTouchUpInside];
        [_bar addSubview:button]; [buttons addObject:button];
        UILabel *label = [[[UILabel alloc] init] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.font = ExteriaFontRegular(11);
        label.textColor = i == 0 ? ExteriaColorAccent() : ExteriaColorTitle();
        label.textAlignment = ExteriaTextAlignmentCenter;
        /* the five labels keep one size, and one that is too long for its column is cut instead of shrunk */
        label.lineBreakMode = UILineBreakModeTailTruncation;
        label.text = [titles objectAtIndex:i];
        [_bar addSubview:label]; [labels addObject:label];
    }
    _buttons = [buttons copy]; _labels = [labels copy];

    /* once something is picked the bar of five buttons gives way to the words for the pictures and the round button that sends them */
    _captionBar = [[UIView alloc] init];
    _captionBar.backgroundColor = ExteriaColorCard();
    _captionBar.hidden = YES;
    [_panel addSubview:_captionBar];
    UIView *field = [[[UIView alloc] init] autorelease];
    field.backgroundColor = ExteriaColorField();
    field.layer.cornerRadius = SEND_SIDE / 2;
    field.tag = 1;
    [_captionBar addSubview:field];
    _caption = [[ExteriaCenteredHintField alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.font = ExteriaFontRegular(16);
    _caption.textColor = ExteriaColorTitle();
    _caption.leftAligned = YES;
    _caption.placeholder = NSLocalizedString(@"attach.caption", nil);
    _caption.returnKeyType = UIReturnKeyDone;
    _caption.delegate = self;
    _caption.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    [field addSubview:_caption];
    _send = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _send.backgroundColor = ExteriaColorAccent();
    _send.layer.cornerRadius = SEND_SIDE / 2;
    [_send setImage:ExteriaSymbolImage(ExteriaSymbolSendArrow, 20, [UIColor whiteColor]) forState:UIControlStateNormal];
    _send.accessibilityLabel = NSLocalizedString(@"attach.send", nil);
    [_send addTarget:self action:@selector(sendSelected) forControlEvents:UIControlEventTouchUpInside];
    [_captionBar addSubview:_send];
    _count = [[UILabel alloc] init];
    _count.backgroundColor = ExteriaColorCard();
    _count.textColor = ExteriaColorAccent();
    _count.font = ExteriaFontBold(11);
    _count.textAlignment = ExteriaTextAlignmentCenter;
    _count.layer.cornerRadius = 9;
    _count.layer.masksToBounds = YES;
    _count.userInteractionEnabled = NO;
    [_captionBar addSubview:_count];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [self updateSelection];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _grid.delegate = nil; _grid.dataSource = nil;
    _caption.delegate = nil;
    [_menu release];
    [_dim release]; [_panelMask release]; [_panel release]; [_bar release]; [_line release]; [_grabber release]; [_title release]; [_more release]; [_captionBar release];
    [_caption release]; [_send release]; [_count release]; [_grid release];
    [_library release]; [_assets release]; [_selected release];
    [_buttons release]; [_labels release];
    [super dealloc];
}

- (void)galleryMessage:(NSString *)text {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.text = text; label.numberOfLines = 0;
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.font = ExteriaFontRegular(14); label.textColor = ExteriaColorSecondary();
    label.backgroundColor = [UIColor clearColor];
    _grid.backgroundView = text.length ? label : nil;
}

- (void)loadGallery {
    [self galleryMessage:NSLocalizedString(@"attach.gallery.loading", nil)];
    _photos = ExteriaPhotosAvailable();
    if (_photos) {
        ExteriaRecentPhotos(ASSETS_MAX, ^(NSArray *assets, NSString *error) {
            if (_leaving) return;
            if (assets) {
                [_assets addObjectsFromArray:assets]; [_grid reloadData];
                [self galleryMessage:assets.count ? @"" : NSLocalizedString(@"attach.gallery.empty", nil)];
            } else {
                [self galleryMessage:NSLocalizedString(@"attach.gallery.unavailable", nil)];
                NSLog(@"exteria: attachment gallery not loaded: %@", error);
            }
        });
        return;
    }
    Class libraryClass = NSClassFromString(@"ALAssetsLibrary");
    if (!libraryClass) { [self galleryMessage:NSLocalizedString(@"attach.gallery.unavailable", nil)]; return; }
    _library = [[libraryClass alloc] init];
    [_library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        (void)stop;
        if (!group) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!_leaving && !_assets.count) [self galleryMessage:NSLocalizedString(@"attach.gallery.empty", nil)];
            });
            return;
        }
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [group setAssetsFilter:[ALAssetsFilter allAssets]];
        NSMutableArray *assets = [NSMutableArray array];
        [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *asset, NSUInteger index, BOOL *stopAssets) {
            (void)index;
            if (assets.count >= ASSETS_MAX) { *stopAssets = YES; return; }
            if (asset && [(ALAsset *)asset defaultRepresentation].url) [assets addObject:asset];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!_leaving) {
                [_assets addObjectsFromArray:assets]; [_grid reloadData];
                [self galleryMessage:assets.count ? @"" : NSLocalizedString(@"attach.gallery.empty", nil)];
            }
        });
        [pool drain];
    } failureBlock:^(NSError *error) {
        NSLog(@"exteria: attachment gallery not available: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{ if (!_leaving) [self galleryMessage:NSLocalizedString(@"attach.gallery.unavailable", nil)]; });
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    UIEdgeInsets safe = ExteriaSafeInsets(self);
    /* a tablet gets a panel the width of a page and a phone in landscape one clear of the notch, both on the screen's own dim; every width below is the panel's */
    CGRect column = ExteriaContentColumn(size, safe, EXTERIA_COLUMN_PAGE);
    CGFloat width = column.size.width;
    _dim.frame = self.bounds;
    /* the panel is a share of the screen, and with the keyboard up it is what fits between the top and the keyboard */
    CGFloat height = MIN(size.height, MAX(220, floor(size.height * 0.82)));
    if (_keyboard > 0) height = MIN(height, MAX(220, size.height - _keyboard - KEYBOARD_TOP_ROOM));
    _panelRestY = size.height - height - _keyboard;
    if (!_pulling && !_leaving) _panel.frame = CGRectMake(column.origin.x, _panelRestY, width, height);
    /* only the top corners are round, since the bottom of the sheet is the bottom of the screen */
    if (!CGRectEqualToRect(_panelMask.bounds, _panel.bounds)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _panelMask.frame = _panel.bounds;
        _panelMask.path = [UIBezierPath bezierPathWithRoundedRect:_panel.bounds byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight cornerRadii:CGSizeMake(PANEL_RADIUS, PANEL_RADIUS)].CGPath;
        [CATransaction commit];
    }
    _grabber.frame = CGRectMake(floor((width - GRABBER_WIDTH) / 2), 7, GRABBER_WIDTH, GRABBER_HEIGHT);
    _more.frame = CGRectMake(width - 52, 14, 44, 44);
    _title.frame = CGRectMake(20, 16, width - 20 - 56, 40);
    CGFloat bottom = _keyboard > 0 ? 0 : safe.bottom;
    BOOL picking = _selected.count > 0;
    CGFloat barHeight = (picking ? CAPTION_HEIGHT : BAR_HEIGHT) + bottom;
    _bar.frame = CGRectMake(0, height - BAR_HEIGHT - bottom, width, BAR_HEIGHT + bottom);
    _captionBar.frame = CGRectMake(0, height - barHeight, width, barHeight);
    _line.frame = CGRectMake(0, 0, width, 1 / ExteriaScreenScale());
    _grid.frame = CGRectMake(0, HEADER_HEIGHT, width, MAX(0, height - HEADER_HEIGHT - barHeight));
    UIView *field = [_captionBar viewWithTag:1];
    /* the field runs the whole width of the sheet and the round button sits inside its right end */
    field.frame = CGRectMake(12, (CAPTION_HEIGHT - SEND_SIDE) / 2, width - 24, SEND_SIDE);
    _caption.frame = CGRectMake(18, 0, field.frame.size.width - 18 - SEND_SIDE - 6, SEND_SIDE);
    _send.frame = CGRectMake(width - 12 - SEND_SIDE, (CAPTION_HEIGHT - SEND_SIDE) / 2, SEND_SIDE, SEND_SIDE);
    _send.layer.borderWidth = 3;
    _send.layer.borderColor = ExteriaColorField().CGColor;
    _count.frame = CGRectMake(CGRectGetMaxX(_send.frame) - 14, CGRectGetMinY(_send.frame) - 4, MAX(18, ceil([_count.text sizeWithFont:_count.font].width) + 8), 18);
    NSInteger columns = MAX(3, (NSInteger)(width / 120));
    CGFloat cellSide = floor(width / columns);
    if (_columns != columns || _cellSide != cellSide) {
        _columns = columns; _cellSide = cellSide; [_grid reloadData];
    }
    NSUInteger count = _offersGift ? 5 : 4;
    CGFloat slotWidth = width / count;
    NSUInteger slot = 0;
    for (NSUInteger i = 0; i < _buttons.count; ++i) {
        UIView *button = [_buttons objectAtIndex:i], *label = [_labels objectAtIndex:i];
        button.hidden = label.hidden = (i == ExteriaAttachGift && !_offersGift);
        if (button.hidden) continue;
        button.frame = CGRectMake(slot * slotWidth, 4, slotWidth, 42);
        label.frame = CGRectMake(slot * slotWidth + 2, 46, slotWidth - 4, 18);
        ++slot;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return _columns ? ((NSInteger)_assets.count + [self tileCount] + _columns - 1) / _columns : 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return _cellSide;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *row = [tableView dequeueReusableCellWithIdentifier:@"assets"];
    if (!row) row = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"assets"] autorelease];
    row.selectionStyle = UITableViewCellSelectionStyleNone;
    row.backgroundColor = [UIColor clearColor]; row.contentView.backgroundColor = [UIColor clearColor];
    for (UIView *view in [[row.contentView.subviews copy] autorelease]) [view removeFromSuperview];
    for (NSInteger col = 0; col < _columns; ++col) {
        NSInteger index = indexPath.row * _columns + col;
        if (index >= (NSInteger)_assets.count + [self tileCount]) break;
        UIButton *image = [UIButton buttonWithType:UIButtonTypeCustom];
        image.frame = CGRectMake(col * _cellSide, 0, _cellSide - 1, _cellSide - 1);
        image.clipsToBounds = YES;
        image.tag = index;
        image.imageView.contentMode = UIViewContentModeScaleAspectFill;
        [image addTarget:self action:@selector(previewAsset:) forControlEvents:UIControlEventTouchUpInside];
        [row.contentView addSubview:image];
        if ([self tileCount] && !index) {
            image.backgroundColor = ExteriaColorField();
            image.imageView.contentMode = UIViewContentModeCenter;
            [image setImage:ExteriaSymbolImage(ExteriaSymbolVideoCamera, 30, ExteriaColorAccent()) forState:UIControlStateNormal];
            image.accessibilityLabel = NSLocalizedString(@"attach.camera", nil);
            continue;
        }
        id asset = [_assets objectAtIndex:(NSUInteger)(index - [self tileCount])];
        /* the picture is a view of its own that fills the cell: a button draws its image at the image's own size from ios 15 on, which left each thumbnail small in the middle of its cell */
        UIImageView *thumbView = [[[UIImageView alloc] initWithFrame:image.bounds] autorelease];
        thumbView.contentMode = UIViewContentModeScaleAspectFill;
        thumbView.clipsToBounds = YES;
        thumbView.userInteractionEnabled = NO;
        [image addSubview:thumbView];
        BOOL covered = _spoiler && [_selected containsObject:[self urlOfAsset:asset]];
        if (_photos) ExteriaPhotoThumbnail(asset, _cellSide * ExteriaScreenScale(), ^(UIImage *thumbnail) {
            if (!_leaving && image.superview == row.contentView) thumbView.image = covered ? ExteriaAttachBlurred(thumbnail) : thumbnail;
        });
        else {
            CGImageRef thumbnail = [(ALAsset *)asset thumbnail];
            if (thumbnail) {
                UIImage *picture = [UIImage imageWithCGImage:thumbnail];
                thumbView.image = covered ? ExteriaAttachBlurred(picture) : picture;
            }
        }
        NSTimeInterval length = [self videoDurationOfAsset:asset];
        if (length > 0) {
            /* a video says how long it is in the corner of its picture, so it is told from a photo before it is
               opened */
            UILabel *time = [[[UILabel alloc] init] autorelease];
            time.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45f];
            time.textColor = [UIColor whiteColor];
            time.font = ExteriaFontSemibold(12);
            time.textAlignment = ExteriaTextAlignmentCenter;
            time.layer.cornerRadius = 7;
            time.layer.masksToBounds = YES;
            time.userInteractionEnabled = NO;
            time.text = ExteriaAttachClockText(length);
            CGSize fit = [time sizeThatFits:CGSizeMake(_cellSide, 20)];
            CGFloat width = ceil(fit.width) + 12, height = 18;
            time.frame = CGRectMake(_cellSide - 1 - 5 - width, _cellSide - 1 - 5 - height, width, height);
            [image addSubview:time];
        }
        /* the button is a larger target than the ring it shows, which is small so that the picture stays in view */
        UIButton *check = [UIButton buttonWithType:UIButtonTypeCustom];
        check.frame = CGRectMake((col + 1) * _cellSide - CHECK_TARGET, 0, CHECK_TARGET, CHECK_TARGET);
        check.tag = index;
        BOOL selected = [_selected containsObject:[self urlOfAsset:asset]];
        UIImageView *ring = [[[UIImageView alloc] initWithFrame:CGRectMake(CHECK_TARGET - 6 - CHECK_SIDE, 5, CHECK_SIDE, CHECK_SIDE)] autorelease];
        ring.userInteractionEnabled = NO;
        ring.contentMode = UIViewContentModeCenter;
        ring.backgroundColor = selected ? ExteriaColorAccent() : [UIColor colorWithWhite:0 alpha:0.3];
        ring.layer.cornerRadius = CHECK_SIDE / 2;
        ring.layer.borderColor = [UIColor whiteColor].CGColor; ring.layer.borderWidth = 1.5;
        [check addSubview:ring];
        if (selected) {
            /* the ring says in which order the pictures were picked */
            UILabel *number = [[[UILabel alloc] initWithFrame:ring.bounds] autorelease];
            number.backgroundColor = [UIColor clearColor];
            number.textColor = [UIColor whiteColor];
            number.font = ExteriaFontSemibold(13);
            number.textAlignment = ExteriaTextAlignmentCenter;
            number.text = [NSString stringWithFormat:@"%lu", (unsigned long)([_selected indexOfObject:[self urlOfAsset:asset]] + 1)];
            [ring addSubview:number];
        }
        check.accessibilityLabel = NSLocalizedString(@"attach.select", nil);
        check.accessibilityTraits = selected ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
        [check addTarget:self action:@selector(toggleAsset:) forControlEvents:UIControlEventTouchUpInside];
        [row.contentView addSubview:check];
    }
    return row;
}

/* seconds as 0:08, or 1:02:03 for a long one */
static NSString *ExteriaAttachClockText(NSTimeInterval length) {
    long total = (long)(length + 0.5);
    if (total >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", total / 3600, (total / 60) % 60, total % 60];
    return [NSString stringWithFormat:@"%ld:%02ld", total / 60, total % 60];
}

- (NSTimeInterval)videoDurationOfAsset:(id)asset {
    if (_photos) return ExteriaPhotoVideoDuration(asset);
    ALAsset *legacy = asset;
    if (![[legacy valueForProperty:ALAssetPropertyType] isEqual:ALAssetTypeVideo]) return 0;
    return [[legacy valueForProperty:ALAssetPropertyDuration] doubleValue];
}

/* the first cell of the grid is the camera, unless the setting leaves it out */
- (NSInteger)tileCount {
    return ExteriaChatFlagGet(ExteriaChatFlagHideCameraTile) ? 0 : 1;
}

- (NSURL *)urlOfAsset:(id)asset {
    return _photos ? ExteriaPhotoURL(asset) : [(ALAsset *)asset defaultRepresentation].url;
}

- (void)updateSelection {
    BOOL picking = _selected.count > 0;
    _bar.hidden = picking;
    _captionBar.hidden = !picking;
    _more.hidden = !picking;
    if (picking) {
        NSString *form = [@"attach.selected." stringByAppendingString:ExteriaPluralForm((NSInteger)_selected.count)];
        _title.text = [NSString stringWithFormat:NSLocalizedString(form, nil), (long)_selected.count];
    } else {
        _title.text = NSLocalizedString(@"attach.gallery", nil);
        [_caption resignFirstResponder];
    }
    _count.text = [NSString stringWithFormat:@"%lu", (unsigned long)_selected.count];
    [self setNeedsLayout];
}

- (void)toggleAsset:(UIButton *)button {
    NSInteger slot = button.tag - [self tileCount];
    if (slot < 0 || slot >= (NSInteger)_assets.count) return;
    NSURL *url = [self urlOfAsset:[_assets objectAtIndex:(NSUInteger)slot]];
    if ([_selected containsObject:url]) [_selected removeObject:url];
    else if (_selected.count < SELECTION_MAX) [_selected addObject:url];
    [self updateSelection]; [_grid reloadData];
}

/* what the sheet hands over: the words, and the choices of the menu */
- (ExteriaAttachOptions *)currentOptions {
    ExteriaAttachOptions *options = [[[ExteriaAttachOptions alloc] init] autorelease];
    NSString *words = [_caption.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    options->caption = [words copy];
    options->asFiles = _asFiles;
    options->spoiler = _spoiler;
    options->standard = _standard;
    options->viewOnce = _viewOnce && !_asFiles;
    return options;
}

/* a tap on a picture opens it in the editor, with the choices of the menu but not the words of the sheet */
- (void)previewAsset:(UIButton *)button {
    if ([self tileCount] && !button.tag) { [self choose:ExteriaAttachCamera]; return; }
    NSInteger slot = button.tag - [self tileCount];
    if (slot < 0 || slot >= (NSInteger)_assets.count) return;
    NSArray *urls = [NSArray arrayWithObject:[self urlOfAsset:[_assets objectAtIndex:(NSUInteger)slot]]];
    ExteriaAttachOptions *options = [self currentOptions];
    options->preview = YES;
    id<ExteriaAttachSheetDelegate> delegate = _delegate;
    [self leaveThen:^{ [delegate attachSheet:self didChooseAssets:urls options:options]; }];
}

- (void)sendSelected {
    if (!_selected.count) return;
    NSArray *urls = [[_selected copy] autorelease];
    ExteriaAttachOptions *options = [self currentOptions];
    if (urls.count != 1) options->viewOnce = NO;
    id<ExteriaAttachSheetDelegate> delegate = _delegate;
    [self leaveThen:^{ [delegate attachSheet:self didChooseAssets:urls options:options]; }];
}

#pragma mark menu

/* the dots open the card: send without compression, hide under a spoiler, send in standard quality; a row that is
   on offers to undo itself */
- (void)showMenu {
    [_caption resignFirstResponder];
    NSArray *titles = [NSArray arrayWithObjects:
        NSLocalizedString(_asFiles ? @"attach.opt.compressed" : @"attach.opt.files", nil),
        NSLocalizedString(_spoiler ? @"attach.opt.visible" : @"attach.opt.spoiler", nil),
        NSLocalizedString(_standard ? @"attach.opt.regular" : @"attach.opt.standard", nil),
        NSLocalizedString(_viewOnce ? @"attach.opt.keep" : @"attach.opt.viewonce", nil), nil];
    ExteriaSymbol symbols[] = {ExteriaSymbolFileHQ, ExteriaSymbolSpoiler, _standard ? ExteriaSymbolQualityHD : ExteriaSymbolQualitySD, ExteriaSymbolEye};
    [_menu release];
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    _menu = [[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        ExteriaAttachSheet *sheet = weak.target;
        if (!sheet) return;
        /* a send without compression is the original, so it and the lighter quality cannot both be asked for */
        if (index == 0) { sheet->_asFiles = !sheet->_asFiles; if (sheet->_asFiles) { sheet->_standard = NO; sheet->_viewOnce = NO; } }
        else if (index == 1) { sheet->_spoiler = !sheet->_spoiler; [sheet->_grid reloadData]; }
        else if (index == 2) { sheet->_standard = !sheet->_standard; if (sheet->_standard) sheet->_asFiles = NO; }
        /* a document stays on the server for good, so a one-time send is a send of a picture or a video and not of a file */
        else { sheet->_viewOnce = !sheet->_viewOnce; if (sheet->_viewOnce) sheet->_asFiles = NO; }
    }];
    CGPoint anchor = [self convertPoint:CGPointMake(CGRectGetMaxX(_more.frame) - 6, CGRectGetMaxY(_more.frame) - 8) fromView:_panel];
    [_menu showInView:self anchor:anchor];
}

#pragma mark keyboard

/* the caption field is the only thing here that takes the keyboard: the sheet rises with it and gets shorter if it must */
- (void)keyboardChanged:(NSNotification *)note {
    if (_leaving || !self.window) return;
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    BOOL showing = [note.name isEqualToString:UIKeyboardWillShowNotification];
    CGRect inSheet = [self convertRect:end fromView:nil];
    _keyboard = showing ? MAX(0, self.bounds.size.height - inSheet.origin.y) : 0;
    NSTimeInterval duration = [[note.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [self setNeedsLayout];
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ [self layoutIfNeeded]; } completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

#pragma mark showing

- (void)showInView:(UIView *)host {
    self.frame = host.bounds;
    [host addSubview:self]; [self layoutIfNeeded];
    _dim.alpha = 0;
    CGRect rest = _panel.frame;
    _panel.frame = CGRectOffset(rest, 0, self.bounds.size.height - rest.origin.y);
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ _dim.alpha = DIM_ALPHA; _panel.frame = rest; } completion:nil];
    [self loadGallery];
}

- (void)leaveThen:(void (^)(void))after {
    if (_leaving) return;
    _leaving = YES; self.userInteractionEnabled = NO;
    [_caption resignFirstResponder];
    /* from wherever the sheet is, so a throw does not snap back before it goes */
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        _dim.alpha = 0;
        CGRect frame = _panel.frame;
        frame.origin.y = self.bounds.size.height;
        _panel.frame = frame;
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview]; if (after) after();
    }];
}

- (void)dismiss { [self leaveThen:nil]; }

/* the pull starts on the header, on the bar, or on the pictures once they are at their top, and only downwards at
   first */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![gesture isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    if (_leaving) return NO;
    CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:self];
    if (velocity.y <= 0 || velocity.y < fabs(velocity.x)) return NO;
    CGPoint at = [gesture locationInView:_panel];
    if (CGRectContainsPoint(_captionBar.frame, at) && !_captionBar.hidden) return NO;
    return at.y < HEADER_HEIGHT || CGRectContainsPoint(_bar.frame, at) || _grid.contentOffset.y <= 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture;
    return other == _grid.panGestureRecognizer;
}

/* while the sheet is pulled the pictures stay at their top, or the bounce of the list would move under the finger on top of the sheet */
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_pulling && scrollView.contentOffset.y < 0) scrollView.contentOffset = CGPointZero;
}

- (void)pulled:(UIPanGestureRecognizer *)pan {
    if (_leaving) return;
    CGFloat height = _panel.bounds.size.height;
    CGFloat pulled = MAX(0, _pullStart + [pan translationInView:self].y);
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
        _pulling = YES;
        CALayer *shown = _panel.layer.presentationLayer;
        if (shown) _panel.frame = shown.frame;
        [_panel.layer removeAllAnimations];
        CALayer *dim = _dim.layer.presentationLayer;
        if (dim) _dim.alpha = dim.opacity;
        [_dim.layer removeAllAnimations];
        _pullRestY = _panelRestY;
        _pullStart = MAX(0, _panel.frame.origin.y - _pullRestY);
        _grid.scrollEnabled = NO;
        [_caption resignFirstResponder];
        break;
    case UIGestureRecognizerStateChanged: {
        CGRect frame = _panel.frame;
        frame.origin.y = _pullRestY + pulled;
        _panel.frame = frame;
        _dim.alpha = DIM_ALPHA * (1 - MIN(1, pulled / height));
        break;
    }
    case UIGestureRecognizerStateEnded:
        _pulling = NO;
        _grid.scrollEnabled = YES;
        if (pulled > DISMISS_DISTANCE || [pan velocityInView:self].y > DISMISS_VELOCITY) {
            [self leaveThen:nil];
            break;
        }
        [self settle];
        break;
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        _pulling = NO;
        _grid.scrollEnabled = YES;
        [self settle];
        break;
    default: break;
    }
}

- (void)settle {
    [self setNeedsLayout];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : SETTLE_SECONDS delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
        CGRect frame = _panel.frame;
        frame.origin.y = _panelRestY;
        _panel.frame = frame;
        [self layoutIfNeeded];
        _dim.alpha = DIM_ALPHA;
    } completion:nil];
}

- (void)choose:(ExteriaAttachChoice)choice {
    id<ExteriaAttachSheetDelegate> delegate = _delegate;
    [self leaveThen:^{ [delegate attachSheet:self didChoose:choice]; }];
}
- (void)chosen:(UIButton *)button { [self choose:(ExteriaAttachChoice)button.tag]; }
@end
