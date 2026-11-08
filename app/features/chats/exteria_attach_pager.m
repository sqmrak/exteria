#import <AVFoundation/AVFoundation.h>
#import "exteria_alert_view.h"
#import <QuartzCore/QuartzCore.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "exteria_attach_pager.h"
#import "exteria_caption_view.h"
#import "exteria_attach_options.h"
#import "exteria_album_layout.h"

#import "exteria_chat_settings.h"
#import "exteria_image_decoder.h"
#import "exteria_photo_library.h"
#import "exteria_photo_editor.h"
#import "exteria_video_editor.h"
#import "exteria_video_composition.h"
#include "exteria_video_edit.h"
#import "exteria_animation.h"
#import "exteria_platform.h"
#include "exteria_photo_zoom.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define BAR_HEIGHT 52.0
#define THUMB_SIDE 52.0
#define THUMB_GAP 8.0
#define THUMB_STRIP 68.0
#define INPUT_BAR 56.0
#define POSTER_SIDE 1024.0

@implementation ExteriaAttachItem

- (id)init {
    self = [super init];
    if (self) trimEnd = 1;
    return self;
}

- (void)dealloc {
    [image release];
    [movie release];
    [poster release];
    [super dealloc];
}

@end

@interface ExteriaAttachPager () <UIScrollViewDelegate, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate, UIGestureRecognizerDelegate> {
    NSMutableArray *_items;
    NSString *_initialCaption;
    void (^_send)(NSArray *, NSString *);
    void (^_cancel)(void);
    ExteriaWeakReference *_weak;
    UIScrollView *_pages;
    UIScrollView *_strip;
    UIView *_top;
    UIView *_bottom;
    UILabel *_count;
    UIButton *_edit;
    UIButton *_add;
    UIButton *_remove;
    /* a selection of two or more opens as the collage the chat will show, and a tap on a picture goes into it; the button in the bar comes back */
    UIView *_collage;
    UIButton *_grid;
    BOOL _collageMode;
    ExteriaCaptionView *_caption;
    UIButton *_sendButton;
    NSInteger _index;
    CGFloat _keyboardHeight;
    BOOL _finished;
    BOOL _loadingPhoto;
    UIImagePickerController *_picker;
    UIPopoverController *_popover;
    UIPinchGestureRecognizer *_pinch;
    UIPanGestureRecognizer *_zoomPan;
    double _zoom;
    double _zoomX;
    double _zoomY;
    /* the movie of the page in view while it plays: the view over the pages that holds its layer, and what ends it */
    AVPlayer *_player;
    UIView *_playerView;
    AVPlayerLayer *_playerLayer;
    id _playerTimer;
    NSUInteger _playToken;
    CMTime _playEnd;
    /* the item of the player, watched until it can play: ios 6 raises an exception for a seek made before that */
    AVPlayerItem *_playerItem;
    double _playFrom;
    BOOL _playStarted;
}
@end

static char ExteriaPlayerStatusContext;

@implementation ExteriaAttachPager

- (id)initWithItems:(NSArray *)items caption:(NSString *)caption send:(void (^)(NSArray *, NSString *))send cancel:(void (^)(void))cancel {
    self = [super init];
    if (!self) return nil;
    _items = [items mutableCopy];
    _collageMode = _items.count > 1;
    _initialCaption = [caption copy];
    _send = [send copy];
    _cancel = [cancel copy];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.wantsFullScreenLayout = YES;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    return self;
}

- (void)dealloc {
    ExteriaStatusBarShow(self, UIStatusBarAnimationNone);
    [self stopPlayback];
    [_weak clear];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _pages.delegate = nil;
    _pinch.delegate = nil; _zoomPan.delegate = nil;
    _caption.delegate = nil;
    _picker.delegate = nil;
    _popover.delegate = nil;
    [_popover dismissPopoverAnimated:NO];
    [_popover release];
    [_picker release];
    [_items release];
    [_initialCaption release];
    [_send release];
    [_cancel release];
    [_weak release];
    [_pages release];
    [_pinch release]; [_zoomPan release];
    [_strip release];
    [_top release];
    [_bottom release];
    [_count release];
    [_edit release];
    [_add release];
    [_remove release];
    [_collage release];
    [_grid release];
    [_caption release];
    [_sendButton release];
    [super dealloc];
}

- (UIButton *)newButtonWithSymbol:(ExteriaSymbol)symbol action:(SEL)action label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:ExteriaSymbolImage(symbol, 23, [UIColor whiteColor]) forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = label;
    return [button retain];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
    root.backgroundColor = [UIColor blackColor];
    self.view = root;
    _pages = [[UIScrollView alloc] init];
    _pages.pagingEnabled = YES;
    _pages.delegate = self;
    _pages.showsHorizontalScrollIndicator = NO;
    _pages.showsVerticalScrollIndicator = NO;
    _pages.bounces = NO;
    ExteriaScrollViewOwnsInsets(_pages);
    [root addSubview:_pages];
    _strip = [[UIScrollView alloc] init];
    _strip.showsHorizontalScrollIndicator = NO;
    ExteriaScrollViewOwnsInsets(_strip);
    [root addSubview:_strip];
    _collage = [[UIView alloc] init];
    _collage.backgroundColor = [UIColor blackColor];
    [root addSubview:_collage];
    _top = [[UIView alloc] init];
    _top.backgroundColor = [UIColor blackColor];
    [root addSubview:_top];
    _bottom = [[UIView alloc] init];
    _bottom.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    [root addSubview:_bottom];
    UIButton *close = [self newButtonWithSymbol:ExteriaSymbolBack action:@selector(close) label:NSLocalizedString(@"attach.cancel", nil)];
    [_top addSubview:close];
    close.tag = 1;
    [close release];
    _count = [[UILabel alloc] init];
    _count.backgroundColor = [UIColor clearColor];
    _count.textColor = [UIColor whiteColor];
    _count.font = [UIFont boldSystemFontOfSize:17];
    _count.textAlignment = ExteriaTextAlignmentCenter;
    [_top addSubview:_count];
    _edit = [self newButtonWithSymbol:ExteriaSymbolHeaderDraw action:@selector(edit) label:NSLocalizedString(@"media.edit", nil)];
    [_top addSubview:_edit];
    _add = [self newButtonWithSymbol:ExteriaSymbolPlusCircle action:@selector(addPhoto) label:NSLocalizedString(@"attach.pager.add", nil)];
    [_top addSubview:_add];
    _grid = [self newButtonWithSymbol:ExteriaSymbolGallery action:@selector(showCollage) label:NSLocalizedString(@"attach.pager.collage", nil)];
    [_top addSubview:_grid];
    _remove = [self newButtonWithSymbol:ExteriaSymbolTrash action:@selector(remove) label:NSLocalizedString(@"attach.pager.remove", nil)];
    [_top addSubview:_remove];
    _caption = [[ExteriaCaptionView alloc] init];
    _caption.textColor = [UIColor whiteColor];
    _caption.font = [UIFont systemFontOfSize:16];
    _caption.placeholder = NSLocalizedString(@"media.caption", nil);
    _caption.text = _initialCaption;
    /* the return key makes a new line; the round button sends */
    _caption.returnKeyType = UIReturnKeyDefault;
    _caption.textAlignment = ExteriaTextAlignmentLeft;
    _caption.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    _caption.layer.cornerRadius = 20;
    _caption.delegate = self;
    _caption.accessibilityLabel = NSLocalizedString(@"media.caption", nil);
    [_bottom addSubview:_caption];
    _sendButton = [self newButtonWithSymbol:ExteriaSymbolSendArrow action:@selector(send) label:NSLocalizedString(@"attach.send", nil)];
    [_bottom addSubview:_sendButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    UITapGestureRecognizer *dismiss = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)] autorelease];
    [_pages addGestureRecognizer:dismiss];
    _zoom = 1;
    _pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)];
    _pinch.delegate = self; [_pages addGestureRecognizer:_pinch];
    /* a picture that is enlarged is moved by the finger, so the paging gives way to it while the picture is zoomed */
    _zoomPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(zoomPanned:)];
    _zoomPan.delegate = self; _zoomPan.maximumNumberOfTouches = 2; [_pages addGestureRecognizer:_zoomPan];
    UITapGestureRecognizer *twice = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)] autorelease];
    twice.numberOfTapsRequired = 2; [_pages addGestureRecognizer:twice];
    /* a double tap on a movie zooms it, so the single tap that plays it waits for the second one not to come */
    UITapGestureRecognizer *once = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playTapped:)] autorelease];
    [once requireGestureRecognizerToFail:twice];
    [_pages addGestureRecognizer:once];
    [self rebuild];
    [self loadPosters];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ExteriaStatusBarHide(self, UIStatusBarAnimationNone);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPlayback];
    ExteriaStatusBarShow(self, UIStatusBarAnimationNone);
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return ExteriaAllowsOrientation(orientation); }
- (BOOL)shouldAutorotate { return YES; }

/* without a mask of its own the pager answers with the default of the system, and the keyboard of an ipad came up in the landscape layout under a portrait screen, wider than the
   display; the mask is the one the lists give. the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return ExteriaOrientationMask(); }
#pragma clang diagnostic pop

#pragma mark content

/* the first frame of each movie, made off the main thread, since the pages and thumbnails of a movie are empty until it is there */
- (void)loadPosters {
    ExteriaWeakReference *weak = _weak;
    for (ExteriaAttachItem *item in _items) {
        if (!item->movie || item->poster) continue;
        NSURL *url = [item->movie retain];
        NSUInteger generation = ++item->posterGeneration;
        double start = item->trimStart;
        NSInteger turns = item->turns;
        BOOL mirrored = item->mirrored;
        CGRect crop = item->crop;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            if (turns || mirrored || !CGRectIsEmpty(crop)) {
                generator.videoComposition = ExteriaVideoComposition(asset, turns, mirrored, crop);
                if (!generator.videoComposition) NSLog(@"exteria: the edited video poster could not be composed");
            }
            generator.maximumSize = CGSizeMake(POSTER_SIDE, POSTER_SIDE);
            NSError *error = nil;
            double duration = CMTimeGetSeconds(asset.duration);
            CMTime time = isfinite(duration) && duration > 0 ? CMTimeMakeWithSeconds(duration * start, 600) : kCMTimeZero;
            CGImageRef frame = [generator copyCGImageAtTime:time actualTime:NULL error:&error];
            if (!frame) NSLog(@"exteria: no poster for the selected movie: %@", error);
            UIImage *poster = frame ? [[UIImage imageWithCGImage:frame] retain] : nil;
            if (frame) CGImageRelease(frame);
            dispatch_async(dispatch_get_main_queue(), ^{
                ExteriaAttachPager *me = weak.target;
                if (me && poster && item->posterGeneration == generation && [me->_items containsObject:item]) {
                    item->poster = [poster retain];
                    [me rebuild];
                }
                [poster release];
                [url release];
            });
            [pool drain];
        });
    }
}

- (UIImage *)pictureOfItem:(ExteriaAttachItem *)item {
    return item->image ? item->image : item->poster;
}

/* every page and thumbnail is made again: a selection holds ten items at most, so this is cheaper than keeping the two lists in step */
- (void)rebuild {
    [self stopPlayback];
    [self resetZoomAnimated:NO];
    for (UIView *view in [[_pages.subviews copy] autorelease]) [view removeFromSuperview];
    for (UIView *view in [[_strip.subviews copy] autorelease]) [view removeFromSuperview];
    for (NSUInteger i = 0; i < _items.count; ++i) {
        ExteriaAttachItem *item = [_items objectAtIndex:i];
        UIImageView *page = [[[UIImageView alloc] initWithImage:[self pictureOfItem:item]] autorelease];
        page.contentMode = UIViewContentModeScaleAspectFit;
        page.tag = (NSInteger)i;
        [_pages addSubview:page];
        if (item->movie) {
            UIImageView *play = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPlay, 44, [UIColor whiteColor])] autorelease];
            play.tag = 1000 + (NSInteger)i;
            [_pages addSubview:play];
        }
        UIButton *thumb = [UIButton buttonWithType:UIButtonTypeCustom];
        thumb.tag = (NSInteger)i;
        thumb.clipsToBounds = YES;
        thumb.layer.cornerRadius = 6;
        thumb.imageView.contentMode = UIViewContentModeScaleAspectFill;
        [thumb setImage:[self pictureOfItem:item] forState:UIControlStateNormal];
        thumb.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        [thumb addTarget:self action:@selector(thumbTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_strip addSubview:thumb];
    }
    if (_items.count < 2) _collageMode = NO;
    [self rebuildCollage];
    if (_index >= (NSInteger)_items.count) _index = (NSInteger)_items.count - 1;
    if (_index < 0) _index = 0;
    [self.view setNeedsLayout];
    [self layoutAll];
}

- (void)rebuildCollage {
    for (UIView *view in [[_collage.subviews copy] autorelease]) [view removeFromSuperview];
    if (_items.count < 2) return;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        ExteriaAttachItem *item = [_items objectAtIndex:i];
        UIImageView *tile = [[[UIImageView alloc] initWithImage:[self pictureOfItem:item]] autorelease];
        tile.contentMode = UIViewContentModeScaleAspectFill;
        tile.clipsToBounds = YES;
        tile.userInteractionEnabled = YES;
        tile.tag = (NSInteger)i;
        tile.accessibilityLabel = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)i + 1, (unsigned long)_items.count];
        [tile addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tileTapped:)] autorelease]];
        [_collage addSubview:tile];
        if (item->movie) {
            UIImageView *play = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPlay, 30, [UIColor whiteColor])] autorelease];
            play.contentMode = UIViewContentModeCenter;
            play.tag = -1;
            [tile addSubview:play];
        }
    }
}

/* the tiles take the width of the screen less a margin, and a collage taller than the room is laid out again narrower so the whole of it shows */
- (void)layoutCollageInSize:(CGSize)room {
    NSMutableArray *ratios = [NSMutableArray arrayWithCapacity:_items.count];
    for (ExteriaAttachItem *item in _items) {
        UIImage *picture = [self pictureOfItem:item];
        CGFloat ratio = picture.size.height > 0 ? picture.size.width / picture.size.height : 1;
        [ratios addObject:[NSNumber numberWithFloat:(float)MAX(0.2, MIN(5, ratio))]];
    }
    CGFloat width = floor(MAX(0, MIN(room.width - 32, 480)));
    NSMutableArray *frames = [NSMutableArray array];
    CGFloat height = ExteriaAlbumLayout(ratios, width, frames);
    if (height > room.height - 24 && height > 0 && room.height > 60) {
        width = floor(width * (room.height - 24) / height);
        [frames removeAllObjects];
        height = ExteriaAlbumLayout(ratios, width, frames);
    }
    CGFloat left = floor((room.width - width) / 2), top = floor((room.height - height) / 2);
    for (UIView *tile in _collage.subviews) {
        if (tile.tag < 0 || (NSUInteger)tile.tag >= frames.count) continue;
        CGRect frame = [[frames objectAtIndex:(NSUInteger)tile.tag] CGRectValue];
        tile.frame = CGRectOffset(frame, left, top);
        UIView *play = [tile viewWithTag:-1];
        play.frame = tile.bounds;
    }
}

- (void)tileTapped:(UITapGestureRecognizer *)tap {
    [self.view endEditing:YES];
    _index = tap.view.tag;
    _collageMode = NO;
    [self.view setNeedsLayout];
    [self layoutAll];
    [_pages setContentOffset:CGPointMake((CGFloat)_index * _pages.bounds.size.width, 0) animated:NO];
}

- (void)showCollage {
    [self stopPlayback];
    [self resetZoomAnimated:NO];
    _collageMode = _items.count > 1;
    [self.view setNeedsLayout];
    [self layoutAll];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutAll];
}

/* the notch and the home indicator of ios 11 and later; the property does not exist before, and the struct is read through key-value coding since
   objc_msgSend_stret is needed for it on armv7 */
- (UIEdgeInsets)safeInsets {
    if (![self.view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")]) return UIEdgeInsetsZero;
    return [[self.view valueForKey:@"safeAreaInsets"] UIEdgeInsetsValue];
}

/* the buttons that are shown stand from the right edge, and the counter is centered between the margins that the wider side needs; a hidden button used to keep its place,
   which left the plus floating in the bar of the collage and the counter off the middle of an ipad */
- (void)layoutBarButtons {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets safe = [self safeInsets];
    CGFloat barTop = safe.top;
    CGFloat buttonSide = 48;
    UIView *close = [_top viewWithTag:1];
    close.frame = CGRectMake(safe.left, barTop + 2, buttonSide, buttonSide);
    CGFloat edge = size.width - safe.right;
    UIView *rightButtons[] = {_remove, _edit, _add, _grid};
    for (NSUInteger i = 0; i < sizeof(rightButtons) / sizeof(rightButtons[0]); ++i) {
        if (rightButtons[i].hidden) continue;
        edge -= buttonSide;
        rightButtons[i].frame = CGRectMake(edge, barTop + 2, buttonSide, buttonSide);
    }
    CGFloat leftReserve = safe.left + buttonSide + 8, rightReserve = size.width - edge + 8;
    CGFloat margin = MAX(leftReserve, rightReserve);
    _count.frame = CGRectMake(margin, barTop + 2, MAX(0, size.width - 2 * margin), buttonSide);
}

- (void)layoutAll {
    if (!self.isViewLoaded) return;
    CGSize size = self.view.bounds.size;
    UIEdgeInsets safe = [self safeInsets];
    /* the keyboard covers the home indicator, so the bar only clears it while the keyboard is down */
    /* a keyboard that would leave no room for the bars is not counted: it was reported with a wrong frame once, and the screen came up black with only the counter in its bar */
    CGFloat keyboard = _keyboardHeight;
    if (size.height - keyboard < safe.top + BAR_HEIGHT + INPUT_BAR + 60) keyboard = 0;
    /* on a 3.5 inch screen the keyboard leaves about 265 points, and the strip of thumbnails would push the caption field under the keyboard or the picture to nothing,
       so the strip steps aside while the person types */
    BOOL stripShown = !_collageMode && (keyboard <= 0 || size.height - keyboard >= safe.top + BAR_HEIGHT + INPUT_BAR + THUMB_STRIP + 160);
    CGFloat stripHeight = stripShown ? THUMB_STRIP : 0;
    CGFloat bottomInset = keyboard > 0 ? 0 : safe.bottom;
    CGFloat inputBottom = size.height - keyboard;
    CGFloat barTop = safe.top;
    _top.frame = CGRectMake(0, 0, size.width, barTop + BAR_HEIGHT);
    _bottom.frame = CGRectMake(0, inputBottom - INPUT_BAR - bottomInset, size.width, INPUT_BAR + bottomInset);
    _strip.hidden = !stripShown;
    _strip.frame = CGRectMake(0, CGRectGetMinY(_bottom.frame) - stripHeight, size.width, stripHeight);
    CGFloat pagesTop = CGRectGetMaxY(_top.frame), pagesHeight = MAX(0, CGRectGetMinY(_strip.frame) - pagesTop);
    CGRect pagesFrame = CGRectMake(0, pagesTop, size.width, pagesHeight);
    BOOL resized = !CGSizeEqualToSize(_pages.frame.size, pagesFrame.size);
    _pages.frame = pagesFrame;
    _pages.hidden = _collageMode;
    _collage.hidden = !_collageMode;
    _collage.frame = pagesFrame;
    if (_collageMode) [self layoutCollageInSize:pagesFrame.size];
    _pages.contentSize = CGSizeMake(size.width * (CGFloat)_items.count, pagesHeight);
    for (UIView *view in _pages.subviews) {
        NSInteger tag = view.tag;
        if (tag >= 1000) {
            view.center = CGPointMake((CGFloat)(tag - 1000) * size.width + size.width / 2, pagesHeight / 2);
        } else {
            /* the page in view may be enlarged, and the frame of a scaled view is not where it stands */
            ExteriaPlaceView(view, CGRectMake((CGFloat)tag * size.width, 0, size.width, pagesHeight));
        }
    }
    if (_zoom != 1 || _zoomX != 0 || _zoomY != 0) { [self clampZoomWithMinimum:1]; [self applyZoomAnimated:NO]; }
    if (_playerView) {
        _playerView.frame = pagesFrame;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _playerLayer.frame = _playerView.bounds;
        [CATransaction commit];
    }
    CGFloat x = THUMB_GAP;
    for (UIView *view in _strip.subviews) {
        view.frame = CGRectMake(x, (THUMB_STRIP - THUMB_SIDE) / 2, THUMB_SIDE, THUMB_SIDE);
        x += THUMB_SIDE + THUMB_GAP;
    }
    _strip.contentSize = CGSizeMake(x, THUMB_STRIP);
    [self showSelection];
    CGFloat buttonSide = 48;
    _sendButton.frame = CGRectMake(size.width - safe.right - buttonSide - 8, (INPUT_BAR - buttonSide) / 2, buttonSide, buttonSide);
    _caption.frame = CGRectMake(16 + safe.left, 8, MAX(0, size.width - safe.left - safe.right - buttonSide - 32), INPUT_BAR - 16);
    [self centerCaptionLines];
    if (resized) _pages.contentOffset = CGPointMake((CGFloat)_index * size.width, 0);
}

- (void)showSelection {
    _count.text = _collageMode ? [NSString stringWithFormat:@"%lu", (unsigned long)_items.count]
                               : [NSString stringWithFormat:@"%ld / %lu", (long)_index + 1, (unsigned long)_items.count];
    ExteriaAttachItem *current = _index < (NSInteger)_items.count ? [_items objectAtIndex:(NSUInteger)_index] : nil;
    _edit.hidden = !current || _collageMode;
    _remove.hidden = _collageMode;
    _grid.hidden = _collageMode || _items.count < 2;
    _add.enabled = _items.count < ATTACH_SELECTION_MAX && !_loadingPhoto;
    _add.alpha = _add.enabled ? 1 : 0.4;
    for (UIView *view in _strip.subviews) {
        BOOL selected = view.tag == _index;
        view.layer.borderWidth = selected ? 2 : 0;
        view.layer.borderColor = ExteriaColorAccent().CGColor;
    }
    CGRect shown = CGRectMake(THUMB_GAP + (CGFloat)_index * (THUMB_SIDE + THUMB_GAP), 0, THUMB_SIDE, THUMB_STRIP);
    [_strip scrollRectToVisible:CGRectInset(shown, -THUMB_GAP, 0) animated:NO];
    [self layoutBarButtons];
}

#pragma mark zoom

- (UIView *)pageAtIndex:(NSInteger)index kind:(BOOL)play {
    for (UIView *view in _pages.subviews)
        if (view.tag == (play ? 1000 + index : index) && [view isKindOfClass:[UIImageView class]]) return view;
    return nil;
}
/* what the picture of the page in view takes of the page: the picture is fitted in, so a tall one is enlarged less in height than in width before it reaches the edge */
- (CGSize)fittedPictureSize {
    ExteriaAttachItem *item = _index >= 0 && _index < (NSInteger)_items.count ? [_items objectAtIndex:(NSUInteger)_index] : nil;
    CGSize picture = [self pictureOfItem:item].size, area = _pages.bounds.size;
    if (picture.width < 1 || picture.height < 1 || area.width < 1 || area.height < 1) return CGSizeZero;
    CGFloat scale = MIN(area.width / picture.width, area.height / picture.height);
    return CGSizeMake(picture.width * scale, picture.height * scale);
}
- (void)clampZoomWithMinimum:(double)minimum {
    CGSize fitted = [self fittedPictureSize], area = _pages.bounds.size;
    if (fitted.width < 1 || exteria_photo_zoom_clamp(fitted.width, fitted.height, area.width, area.height, minimum, &_zoom, &_zoomX, &_zoomY) != EXTERIA_OK) {
        _zoom = 1; _zoomX = _zoomY = 0;
    }
}
- (void)applyZoomAnimated:(BOOL)animated {
    UIView *page = [self pageAtIndex:_index kind:NO];
    CGAffineTransform transform = CGAffineTransformMake((CGFloat)_zoom, 0, 0, (CGFloat)_zoom, (CGFloat)_zoomX, (CGFloat)_zoomY);
    if (page) {
        if (animated) ExteriaAnimateView(page, transform, 1, EXTERIA_MOTION_SPRING, nil);
        else { [page.layer removeAnimationForKey:@"exteria.motion"]; page.transform = transform; }
    }
    UIView *play = [self pageAtIndex:_index kind:YES];
    BOOL zoomed = _zoom > 1.03;
    if (play) ExteriaAnimateView(play, zoomed ? CGAffineTransformMakeScale(0.6, 0.6) : CGAffineTransformIdentity, zoomed ? 0 : 1, EXTERIA_MOTION_SPRING, nil);
    _pages.scrollEnabled = !zoomed;
}
- (void)resetZoomAnimated:(BOOL)animated {
    BOOL was = _zoom != 1 || _zoomX != 0 || _zoomY != 0;
    _zoom = 1; _zoomX = _zoomY = 0;
    if (was) [self applyZoomAnimated:animated];
    for (UIView *view in _pages.subviews) {
        if (view.tag >= 1000 || (view.tag == _index && was)) continue;
        [view.layer removeAnimationForKey:@"exteria.motion"]; view.transform = CGAffineTransformIdentity;
    }
    _pages.scrollEnabled = YES;
}
/* the offsets are measured from the middle of the page in view */
- (CGPoint)focalOfTouchPoint:(CGPoint)point {
    CGSize area = _pages.bounds.size;
    return CGPointMake(point.x - ((CGFloat)_index * area.width + area.width / 2), point.y - area.height / 2);
}
- (void)pinched:(UIPinchGestureRecognizer *)pinch {
    if (pinch.state == UIGestureRecognizerStateBegan) {
        UIView *page = [self pageAtIndex:_index kind:NO];
        [page.layer removeAnimationForKey:@"exteria.motion"];
        [self dismissKeyboard];
    }
    if (pinch.state == UIGestureRecognizerStateBegan || pinch.state == UIGestureRecognizerStateChanged) {
        CGPoint focus = [self focalOfTouchPoint:[pinch locationInView:_pages]];
        double next = _zoom * pinch.scale, x = _zoomX, y = _zoomY;
        if (exteria_photo_zoom_about(_zoom, _zoomX, _zoomY, focus.x, focus.y, next, &x, &y) == EXTERIA_OK) { _zoom = next; _zoomX = x; _zoomY = y; }
        pinch.scale = 1;
        [self clampZoomWithMinimum:0.75];
        [self applyZoomAnimated:NO];
    } else if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled || pinch.state == UIGestureRecognizerStateFailed) {
        [self clampZoomWithMinimum:1];
        [self applyZoomAnimated:YES];
    }
}
- (void)zoomPanned:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) [[self pageAtIndex:_index kind:NO].layer removeAnimationForKey:@"exteria.motion"];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint move = [pan translationInView:_pages];
        [pan setTranslation:CGPointZero inView:_pages];
        _zoomX += move.x; _zoomY += move.y;
        [self clampZoomWithMinimum:0.75];
        [self applyZoomAnimated:NO];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        [self clampZoomWithMinimum:1];
        [self applyZoomAnimated:YES];
    }
}
/* a double tap enlarges the picture about the spot, and puts it back when it is already enlarged */
- (void)doubleTapped:(UITapGestureRecognizer *)tap {
    if (_zoom > 1.03) { [self resetZoomAnimated:YES]; return; }
    CGPoint focus = [self focalOfTouchPoint:[tap locationInView:_pages]];
    double x = 0, y = 0;
    if (exteria_photo_zoom_about(1, 0, 0, focus.x, focus.y, 2.5, &x, &y) != EXTERIA_OK) return;
    _zoom = 2.5; _zoomX = x; _zoomY = y;
    [self clampZoomWithMinimum:1];
    [self applyZoomAnimated:YES];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == _zoomPan) return _zoom > 1.03;
    /* the movie that plays is a layer over the pages that the zoom does not move */
    if (gesture == _pinch) return _playerView == nil;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return (a == _pinch && b == _zoomPan) || (a == _zoomPan && b == _pinch);
}

#pragma mark playback

- (void)playTapped:(UITapGestureRecognizer *)tap {
    (void)tap;
    ExteriaAttachItem *item = _index >= 0 && _index < (NSInteger)_items.count ? [_items objectAtIndex:(NSUInteger)_index] : nil;
    if (!item || !item->movie || _zoom > 1.03) return;
    if (_playerView) [self stopPlayback];
    else [self startPlaybackOfItem:item];
}

/* the movie as it will be sent: its trim, turns, mirror and crop, and without sound when it is muted */
- (void)startPlaybackOfItem:(ExteriaAttachItem *)item {
    NSUInteger token = ++_playToken;
    NSURL *url = [item->movie retain];
    double trimStart = item->trimStart, trimEnd = item->trimEnd;
    NSInteger turns = item->turns;
    BOOL mirrored = item->mirrored, muted = item->muted;
    CGRect crop = item->crop;
    ExteriaWeakReference *weak = _weak;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    [url release];
    [asset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObjects:@"duration", @"playable", @"tracks", nil] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaAttachPager *me = weak.target;
            if (!me || token != me->_playToken) return;
            NSError *error = nil;
            double duration = CMTimeGetSeconds(asset.duration);
            double from = 0, length = 0;
            BOOL ready = [asset statusOfValueForKey:@"duration" error:&error] == AVKeyValueStatusLoaded && [asset statusOfValueForKey:@"playable" error:&error] == AVKeyValueStatusLoaded
                && asset.playable && isfinite(duration) && exteria_video_edit_range(duration, trimStart, trimEnd, &from, &length) == EXTERIA_OK;
            AVVideoComposition *composition = nil;
            if (ready && (turns || mirrored || !CGRectIsEmpty(crop))) {
                composition = ExteriaVideoComposition(asset, turns, mirrored, crop);
                ready = composition != nil;
            }
            if (!ready) {
                NSLog(@"exteria: the selected movie cannot be played: %@", error);
                [me photoError:NSLocalizedString(@"attach.video.failed", nil)];
                return;
            }
            [me beginPlaybackOfAsset:asset composition:composition from:from length:length muted:muted];
        });
    }];
}

- (void)beginPlaybackOfAsset:(AVAsset *)asset composition:(AVVideoComposition *)composition from:(double)from length:(double)length muted:(BOOL)muted {
    [self resetZoomAnimated:NO];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.videoComposition = composition;
    if (muted) {
        NSMutableArray *parameters = [NSMutableArray array];
        for (AVAssetTrack *track in [asset tracksWithMediaType:AVMediaTypeAudio]) {
            AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
            [input setVolume:0 atTime:kCMTimeZero];
            [parameters addObject:input];
        }
        AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
        mix.inputParameters = parameters;
        item.audioMix = mix;
    }
    _player = [[AVPlayer playerWithPlayerItem:item] retain];
    _playerView = [[UIView alloc] initWithFrame:_pages.frame];
    _playerView.backgroundColor = [UIColor clearColor];
    _playerView.userInteractionEnabled = NO;
    _playerLayer = [[AVPlayerLayer playerLayerWithPlayer:_player] retain];
    _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    _playerLayer.frame = _playerView.bounds;
    [_playerView.layer addSublayer:_playerLayer];
    [self.view insertSubview:_playerView aboveSubview:_pages];
    UIView *glyph = [self pageAtIndex:_index kind:YES];
    glyph.alpha = 0;
    _playEnd = CMTimeMakeWithSeconds(from + length, 600);
    ExteriaWeakReference *weak = _weak;
    /* the clip ends at its trim, which is before the end of the file when the movie was cut */
    _playerTimer = [[_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        ExteriaAttachPager *me = weak.target;
        if (me && me->_player && CMTimeCompare(time, me->_playEnd) >= 0) [me stopPlayback];
    }] retain];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(playbackEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [center addObserver:self selector:@selector(playbackFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    _playerItem = [item retain];
    _playFrom = from;
    _playStarted = NO;
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:&ExteriaPlayerStatusContext];
}

/* the status of an item changes on a thread of the framework's own choosing */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &ExteriaPlayerStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    NSUInteger token = _playToken;
    dispatch_async(dispatch_get_main_queue(), ^{
        ExteriaAttachPager *me = weak.target;
        if (me && token == me->_playToken && object == me->_playerItem) [me playerItemStatusChanged];
    });
}

/* a seek with a completion handler is refused before the item is ready, so the movie is put at its start and started once it is */
- (void)playerItemStatusChanged {
    AVPlayerItemStatus status = _playerItem.status;
    if (status == AVPlayerItemStatusUnknown || _playStarted) return;
    if (status == AVPlayerItemStatusFailed) {
        NSLog(@"exteria: the selected movie cannot be played: %@", _playerItem.error);
        [self stopPlayback];
        [self photoError:NSLocalizedString(@"attach.video.failed", nil)];
        return;
    }
    _playStarted = YES;
    ExteriaWeakReference *weak = _weak;
    AVPlayerItem *item = _playerItem;
    [_player seekToTime:CMTimeMakeWithSeconds(_playFrom, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        ExteriaAttachPager *me = weak.target;
        if (finished && me && me->_playerItem == item) [me->_player play];
    }];
}

- (void)playbackEnded:(NSNotification *)note {
    (void)note;
    [self stopPlayback];
}

- (void)playbackFailed:(NSNotification *)note {
    NSLog(@"exteria: the selected movie stopped playing: %@", [[note userInfo] objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey]);
    [self stopPlayback];
    [self photoError:NSLocalizedString(@"attach.video.failed", nil)];
}

/* every way out of a playback goes through here, so the observer, the timer and the layer are gone together */
- (void)stopPlayback {
    ++_playToken;
    if (_playerItem) {
        [_playerItem removeObserver:self forKeyPath:@"status" context:&ExteriaPlayerStatusContext];
        [_playerItem release];
        _playerItem = nil;
    }
    if (!_player) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_player.currentItem];
    [_player removeTimeObserver:_playerTimer];
    [_playerTimer release];
    _playerTimer = nil;
    [_player pause];
    [_playerLayer removeFromSuperlayer];
    [_playerLayer release];
    _playerLayer = nil;
    [_playerView removeFromSuperview];
    [_playerView release];
    _playerView = nil;
    [_player release];
    _player = nil;
    [self pageAtIndex:_index kind:YES].alpha = 1;
}

#pragma mark paging

- (void)scrollViewDidScroll:(UIScrollView *)scroll {
    if (scroll != _pages || scroll.bounds.size.width <= 0 || !_items.count) return;
    NSInteger index = (NSInteger)floor(scroll.contentOffset.x / scroll.bounds.size.width + 0.5);
    index = MAX(0, MIN((NSInteger)_items.count - 1, index));
    if (index == _index) return;
    [self stopPlayback];
    _index = index;
    [self resetZoomAnimated:NO];
    [self showSelection];
}

- (void)thumbTapped:(UIButton *)thumb {
    [self stopPlayback];
    [self resetZoomAnimated:NO];
    _index = thumb.tag;
    [_pages setContentOffset:CGPointMake((CGFloat)_index * _pages.bounds.size.width, 0) animated:YES];
    [self showSelection];
}

#pragma mark actions

- (void)addPhoto {
    if (_finished || _loadingPhoto || _picker || _items.count >= ATTACH_SELECTION_MAX) return;
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self photoError:NSLocalizedString(@"attach.gallery.unavailable", nil)];
        return;
    }
    [self.view endEditing:YES];
    _picker = [[UIImagePickerController alloc] init];
    _picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    _picker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    _picker.delegate = self;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        _popover = [[UIPopoverController alloc] initWithContentViewController:_picker];
        _popover.delegate = self;
        [_popover presentPopoverFromRect:_add.bounds inView:_add permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self presentViewController:_picker animated:YES completion:nil];
    }
}

- (void)photoError:(NSString *)message {
    Class alertClass = ExteriaAlertClass();
    id alert = [[alertClass alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)releasePicker {
    _picker.delegate = nil;
    _popover.delegate = nil;
    [_popover dismissPopoverAnimated:YES];
    [_popover release]; _popover = nil;
    [_picker release]; _picker = nil;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popover {
    if (popover == _popover) [self releasePicker];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    if (!_popover) [picker dismissViewControllerAnimated:YES completion:nil];
    [self releasePicker];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *source = [info objectForKey:UIImagePickerControllerOriginalImage];
    NSURL *url = [info objectForKey:@"UIImagePickerControllerImageURL"];
    NSURL *movie = [info objectForKey:UIImagePickerControllerMediaURL];
    NSString *type = [info objectForKey:UIImagePickerControllerMediaType];
    if ([type isEqualToString:(NSString *)kUTTypeMovie] && movie) {
        ExteriaAttachItem *item = [[[ExteriaAttachItem alloc] init] autorelease];
        item->movie = [movie retain];
        [_items addObject:item];
        _index = (NSInteger)_items.count - 1;
        if (!_popover) [picker dismissViewControllerAnimated:YES completion:nil];
        [self releasePicker];
        [self rebuild];
        [_pages setContentOffset:CGPointMake((CGFloat)_index * _pages.bounds.size.width, 0) animated:NO];
        [self loadPosters];
        return;
    }
    _loadingPhoto = YES;
    _sendButton.enabled = NO;
    [self showSelection];
    if (!_popover) [picker dismissViewControllerAnimated:YES completion:nil];
    [self releasePicker];
    ExteriaWeakReference *weak = _weak;
    CGFloat side = (ExteriaChatFlagGet(ExteriaChatFlagAlwaysHD) || ExteriaPhotosAvailable()) ? 2560.0 : 1280.0;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *image = url ? ExteriaDecodeImageAtURL(url, side) : nil;
        if (!image && source.size.width > 0 && source.size.height > 0) {
            CGFloat scale = MIN(1, side / MAX(source.size.width, source.size.height));
            CGSize size = CGSizeMake(MAX(1, floor(source.size.width * scale)), MAX(1, floor(source.size.height * scale)));
            UIGraphicsBeginImageContextWithOptions(size, YES, 1);
            [source drawInRect:CGRectMake(0, 0, size.width, size.height)];
            image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        [image retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaAttachPager *pager = weak.target;
            if (pager && !pager->_finished) {
                pager->_loadingPhoto = NO;
                pager->_sendButton.enabled = YES;
                if (image && pager->_items.count < ATTACH_SELECTION_MAX) {
                    ExteriaAttachItem *item = [[[ExteriaAttachItem alloc] init] autorelease];
                    item->image = [image retain];
                    [pager->_items addObject:item];
                    pager->_index = (NSInteger)pager->_items.count - 1;
                    [pager rebuild];
                    [pager->_pages setContentOffset:CGPointMake((CGFloat)pager->_index * pager->_pages.bounds.size.width, 0) animated:NO];
                } else if (!image) {
                    [pager showSelection];
                    [pager photoError:NSLocalizedString(@"attach.failed", nil)];
                }
            }
            [image release];
        });
        [pool drain];
    });
}

- (void)edit {
    if (_index >= (NSInteger)_items.count) return;
    ExteriaAttachItem *item = [_items objectAtIndex:(NSUInteger)_index];
    ExteriaWeakReference *weak = _weak;
    if (item->movie) {
        ExteriaVideoEditor *editor = [[[ExteriaVideoEditor alloc] initWithURL:item->movie start:item->trimStart end:item->trimEnd muted:item->muted
            turns:item->turns mirrored:item->mirrored crop:item->crop completion:^(double start, double end, BOOL muted, NSInteger turns, BOOL mirrored, CGRect crop) {
                ExteriaAttachPager *me = weak.target;
                if (!me || ![me->_items containsObject:item]) return;
                item->trimStart = start;
                item->trimEnd = end;
                item->muted = muted;
                item->turns = turns;
                item->mirrored = mirrored;
                item->crop = crop;
                [item->poster release]; item->poster = nil;
                [me loadPosters];
            }] autorelease];
        [self presentViewController:editor animated:YES completion:nil];
        return;
    }
    if (!item->image) return;
    ExteriaPhotoEditor *editor = [[[ExteriaPhotoEditor alloc] initWithImage:item->image completion:^(UIImage *edited) {
        ExteriaAttachPager *me = weak.target;
        if (!me || !edited || ![me->_items containsObject:item]) return;
        [item->image release];
        item->image = [edited retain];
        [me rebuild];
    }] autorelease];
    [self presentViewController:editor animated:YES completion:nil];
}

- (void)remove {
    if (_index >= (NSInteger)_items.count) return;
    [_items removeObjectAtIndex:(NSUInteger)_index];
    if (!_items.count) {
        [self close];
        return;
    }
    [self rebuild];
    [_pages setContentOffset:CGPointMake((CGFloat)_index * _pages.bounds.size.width, 0) animated:NO];
}

- (void)finishWith:(void (^)(void))after {
    if (_finished) return;
    _finished = YES;
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:after];
}

- (void)close {
    void (^cancel)(void) = [[_cancel copy] autorelease];
    [self finishWith:^{ if (cancel) cancel(); }];
}

- (void)send {
    NSArray *items = [[_items copy] autorelease];
    NSString *caption = [[_caption.text copy] autorelease];
    void (^send)(NSArray *, NSString *) = [[_send copy] autorelease];
    [self finishWith:^{ if (send) send(items, caption ? caption : @""); }];
}

#pragma mark keyboard

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

/* one line stands in the middle of the pill; more fill it and scroll */
- (void)centerCaptionLines {
    /* the words start a little in from the round edge of the pill */
    const CGFloat edge = 10;
    CGFloat pill = _caption.bounds.size.height, lines = [_caption contentHeightForWidth:MAX(20, _caption.bounds.size.width - edge)];
    CGFloat inset = MAX(0, floor((pill - lines) / 2));
    _caption.contentInset = UIEdgeInsetsMake(inset, edge, inset, 0);
    /* the insets are what centers a line, and a text view that scrolls lets a finger drag the words anywhere inside them and bounce back; while the words fit in the pill the
       view stays still, and it scrolls only once they overflow */
    BOOL overflow = lines > pill + 0.5;
    _caption.scrollEnabled = overflow;
    _caption.bounces = overflow;
    _caption.alwaysBounceVertical = overflow;
    if (!overflow) _caption.contentOffset = CGPointMake(-edge, -inset);
}

- (void)textViewDidChange:(UITextView *)textView {
    (void)textView;
    [self centerCaptionLines];
    [_caption scrollRangeToVisible:_caption.selectedRange];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    return textView.text.length - range.length + text.length <= 1024;
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:[self.view.window convertRect:end fromWindow:nil] fromView:nil];
    _keyboardHeight = MAX(0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(local));
    NSTimeInterval duration = [[note.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{ [self layoutAll]; }];
}

@end
