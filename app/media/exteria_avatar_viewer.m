#import "exteria_avatar_viewer.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_popup_menu.h"
#import "exteria_remote_file.h"
#import "exteria_session_profile.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define PHOTO_MAX_SIDE 1280.0
#define BUTTON_SIZE 44.0
#define STRIP_HEIGHT 64.0
#define THUMB_SIDE 46.0
#define THUMB_SELECTED_SIDE 58.0
#define THUMB_GAP 4.0
#define THUMB_MAX_SIDE 120.0

@interface ExteriaAvatarPage : UIView {
@public
    UIImageView *image;
    UIActivityIndicatorView *spinner;
    BOOL loading;
    BOOL loaded;
}
@end

@implementation ExteriaAvatarPage

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    image = [[UIImageView alloc] initWithFrame:self.bounds];
    image.contentMode = UIViewContentModeScaleAspectFit;
    image.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:image];
    spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin |
                               UIViewAutoresizingFlexibleBottomMargin;
    [self addSubview:spinner];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    spinner.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)dealloc {
    [image release];
    [spinner release];
    [super dealloc];
}

@end

@implementation ExteriaAvatarViewer

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _pages = [[NSMutableArray alloc] init];
    _thumbs = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    ExteriaStatusBarShow(self, UIStatusBarAnimationNone);
    _pager.delegate = nil;
    [_session release];
    [_dialog release];
    [_avatars release];
    [_media release];
    [_photos release];
    [_pager release];
    [_counter release];
    [_back release];
    [_more release];
    [_titleLabel release];
    [_strip release];
    [_thumbs release];
    [_dateLabel release];
    [_toast release];
    [_spinner release];
    [_pages release];
    [super dealloc];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    (void)orientation;
    return YES;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
    root.backgroundColor = [UIColor blackColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *root = self.view;
    _pager = [[UIScrollView alloc] initWithFrame:root.bounds];
    _pager.pagingEnabled = YES;
    ExteriaScrollViewOwnsInsets(_pager);
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.showsVerticalScrollIndicator = NO;
    _pager.delegate = self;
    /* a flick down takes the photos away, as it does in the story viewer */
    UISwipeGestureRecognizer *down = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(close)] autorelease];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    [_pager addGestureRecognizer:down];
    [root addSubview:_pager];

    _back = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_back setImage:ExteriaSymbolImage(ExteriaSymbolBack, 24, [UIColor whiteColor]) forState:UIControlStateNormal];
    [_back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    _back.accessibilityLabel = NSLocalizedString(@"story.close", nil);
    [root addSubview:_back];
    _more = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_more setImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 24, [UIColor whiteColor]) forState:UIControlStateNormal];
    [_more addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    _more.accessibilityLabel = NSLocalizedString(@"avatar.save", nil);
    [root addSubview:_more];
    _titleLabel = [[ExteriaEmojiLabel alloc] init];
    /* the title is a person's name: a styled nick would show as boxes with a code in them in the system label */
    _titleLabel.dropsUndrawable = YES;
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = ExteriaFontSemibold(20);
    /* the own profile hands over the name of the person, as its dialog is the Saved Messages chat */
    _titleLabel.text = self.title.length ? self.title : _dialog.title;
    [root addSubview:_titleLabel];
    _dateLabel = [[UILabel alloc] init];
    _dateLabel.backgroundColor = [UIColor clearColor];
    _dateLabel.textColor = [UIColor colorWithWhite:1 alpha:0.75f];
    _dateLabel.font = ExteriaFontRegular(15);
    [root addSubview:_dateLabel];
    _counter = [[UILabel alloc] init];
    _counter.backgroundColor = [UIColor clearColor];
    _counter.textColor = [UIColor whiteColor];
    _counter.textAlignment = ExteriaTextAlignmentCenter;
    _counter.font = ExteriaFontSemibold(16);
    _counter.hidden = YES;
    [root addSubview:_counter];
    _strip = [[UIScrollView alloc] init];
    _strip.showsHorizontalScrollIndicator = NO;
    _strip.scrollsToTop = NO;
    _strip.hidden = YES;
    [root addSubview:_strip];
    _toast = [[UILabel alloc] init];
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    _toast.textColor = [UIColor whiteColor];
    _toast.font = ExteriaFontMedium(14);
    _toast.textAlignment = ExteriaTextAlignmentCenter;
    _toast.layer.cornerRadius = 14;
    _toast.clipsToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [root addSubview:_spinner];

    /* the photo the profile shows is on the screen before the list arrives */
    [self buildPages:1];
    [self showCurrentPhoto];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (animated && !ExteriaReduceMotionEnabled()) {
        /* the photo grows out of the profile's wide photo while the black comes in under it */
        _pager.transform = CGAffineTransformMakeScale(0.86f, 0.86f);
        _pager.alpha = 0;
        [UIView animateWithDuration:0.32 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            _pager.transform = CGAffineTransformIdentity;
            _pager.alpha = 1;
        } completion:nil];
    }
    /* the bar is hidden by the application before iOS 7, which has no prefersStatusBarHidden */
    ExteriaStatusBarHide(self, UIStatusBarAnimationFade);
    if (_requested) return;
    _requested = YES;
    [_spinner startAnimating];
    [_session loadAvatarsOfDialog:_dialog completion:^(NSArray *photos, NSString *errorName) {
        [_spinner stopAnimating];
        if (errorName || photos.count == 0) return;
        [_photos release];
        _photos = [photos retain];
        _index = 0;
        [self buildPages:(NSInteger)photos.count];
        [self buildThumbs];
        [_pager setContentOffset:CGPointZero animated:NO];
        [self loadPagesAround:0];
        [self updateCounter];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    ExteriaStatusBarShow(self, UIStatusBarAnimationFade);
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    /* the photos stand between the bars of the top and the strip along the foot; the notch is left to the bars */
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = insets.top;
    CGFloat side = insets.left + 4;
    _back.frame = CGRectMake(side, top + 6, BUTTON_SIZE, BUTTON_SIZE);
    _more.frame = CGRectMake(bounds.size.width - insets.right - BUTTON_SIZE - 4, top + 6, BUTTON_SIZE, BUTTON_SIZE);
    CGFloat textLeft = CGRectGetMaxX(_back.frame) + 8;
    CGFloat textWidth = MAX(0, CGRectGetMinX(_more.frame) - textLeft - 4);
    /* without a date the name stands alone, so it is centred on the arrow instead of sitting on the top line */
    CGFloat titleTop = _dateLabel.text.length ? top + 6 : top + 6 + (BUTTON_SIZE - 24) / 2;
    _titleLabel.frame = CGRectMake(textLeft, titleTop, textWidth, 24);
    _dateLabel.frame = CGRectMake(textLeft, top + 30, textWidth, 20);
    _counter.frame = CGRectMake(insets.left, top + 6 + BUTTON_SIZE + 18, bounds.size.width - insets.left - insets.right, 24);
    CGFloat stripTop = bounds.size.height - insets.bottom - STRIP_HEIGHT - 12;
    _strip.frame = CGRectMake(insets.left, stripTop, bounds.size.width - insets.left - insets.right, STRIP_HEIGHT);
    CGFloat pagerTop = top + 6 + BUTTON_SIZE + 48;
    _pager.frame = CGRectMake(0, pagerTop, bounds.size.width, MAX(0, stripTop - 12 - pagerTop));
    _toast.frame = CGRectMake(floor((bounds.size.width - 200) / 2), stripTop - 44, 200, 28);
    _spinner.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(_pager.frame));
    [self layoutThumbs];
    [self layoutPages];
}

- (void)buildPages:(NSInteger)count {
    for (UIView *page in _pages) [page removeFromSuperview];
    [_pages removeAllObjects];
    for (NSInteger i = 0; i < count; ++i) {
        ExteriaAvatarPage *page = [[[ExteriaAvatarPage alloc] initWithFrame:CGRectZero] autorelease];
        [_pager addSubview:page];
        [_pages addObject:page];
    }
    [self layoutPages];
}

- (void)layoutPages {
    CGSize size = _pager.bounds.size;
    _pager.contentSize = CGSizeMake(size.width * (CGFloat)_pages.count, size.height);
    for (NSUInteger i = 0; i < _pages.count; ++i) {
        [[_pages objectAtIndex:i] setFrame:CGRectMake(size.width * (CGFloat)i, 0, size.width, size.height)];
    }
    _pager.contentOffset = CGPointMake(size.width * (CGFloat)_index, 0);
}

- (void)showCurrentPhoto {
    ExteriaAvatarPage *page = [_pages objectAtIndex:0];
    ExteriaPhoto *small = _dialog.photo;
    UIImage *cached = small ? [_avatars cachedImageForPhoto:small] : nil;
    page->image.image = cached;
    if (!cached && small) {
        [_avatars loadImageForPhoto:small completion:^(UIImage *image) {
            /* the full list replaces this page; a small picture must not land on top of a sharp one */
            if (!page->loaded && !page->image.image) page->image.image = image;
        }];
    }
    [self updateCounter];
}

- (void)loadPagesAround:(NSInteger)index {
    for (NSInteger i = index - 1; i <= index + 1; ++i) {
        if (i < 0 || i >= (NSInteger)_pages.count || i >= (NSInteger)_photos.count) continue;
        ExteriaAvatarPage *page = [_pages objectAtIndex:(NSUInteger)i];
        if (page->loading || page->loaded) continue;
        ExteriaMedia *photo = [_photos objectAtIndex:(NSUInteger)i];
        exteria_media_ref ref = photo.ref;
        ExteriaRemoteFile *file = [ExteriaRemoteFile fileForMedia:&ref];
        if (!file) continue;
        page->loading = YES;
        [page->spinner startAnimating];
        [_media loadImageForFile:file maxSide:PHOTO_MAX_SIDE completion:^(UIImage *image) {
            page->loading = NO;
            [page->spinner stopAnimating];
            if (!image) return;
            page->loaded = YES;
            page->image.image = image;
        }];
    }
}

- (void)updateDate {
    int32_t date = _index < (NSInteger)_photos.count ? [(ExteriaMedia *)[_photos objectAtIndex:(NSUInteger)_index] date] : 0;
    if (date <= 0) { _dateLabel.text = @""; [self.view setNeedsLayout]; return; }
    NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
    format.dateStyle = NSDateFormatterMediumStyle;
    format.timeStyle = NSDateFormatterShortStyle;
    _dateLabel.text = [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
    [self.view setNeedsLayout];
}

/* the small pictures along the foot: the shown one is larger, a tap goes to the photo; they come from the same files as the pages, decoded small */
- (void)buildThumbs {
    for (UIView *thumb in _thumbs) [thumb removeFromSuperview];
    [_thumbs removeAllObjects];
    _strip.hidden = _photos.count < 2;
    for (NSUInteger i = 0; i < _photos.count; ++i) {
        UIImageView *thumb = [[[UIImageView alloc] init] autorelease];
        thumb.contentMode = UIViewContentModeScaleAspectFill;
        thumb.clipsToBounds = YES;
        thumb.layer.cornerRadius = 4;
        thumb.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12f];
        thumb.userInteractionEnabled = YES;
        thumb.tag = (NSInteger)i;
        [thumb addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(thumbTapped:)] autorelease]];
        [_strip addSubview:thumb];
        [_thumbs addObject:thumb];
        ExteriaMedia *photo = [_photos objectAtIndex:i];
        exteria_media_ref ref = photo.ref;
        ExteriaRemoteFile *file = [ExteriaRemoteFile fileForMedia:&ref];
        if (!file) continue;
        [_media loadImageForFile:file maxSide:THUMB_MAX_SIDE completion:^(UIImage *image) {
            if (image) thumb.image = image;
        }];
    }
    [self layoutThumbs];
}

- (void)layoutThumbs {
    CGFloat x = 8;
    for (NSUInteger i = 0; i < _thumbs.count; ++i) {
        BOOL selected = (NSInteger)i == _index;
        CGFloat side = selected ? THUMB_SELECTED_SIDE : THUMB_SIDE;
        UIView *thumb = [_thumbs objectAtIndex:i];
        thumb.frame = CGRectMake(x, (STRIP_HEIGHT - side) / 2, side, side);
        x += side + THUMB_GAP;
    }
    _strip.contentSize = CGSizeMake(x + 4, STRIP_HEIGHT);
    if (_index >= 0 && _index < (NSInteger)_thumbs.count) {
        CGRect shown = [[_thumbs objectAtIndex:(NSUInteger)_index] frame];
        CGFloat target = MAX(0, MIN(CGRectGetMidX(shown) - _strip.bounds.size.width / 2, _strip.contentSize.width - _strip.bounds.size.width));
        [_strip setContentOffset:CGPointMake(target, 0) animated:NO];
    }
}

- (void)thumbTapped:(UITapGestureRecognizer *)tap {
    NSInteger index = tap.view.tag;
    if (index < 0 || index >= (NSInteger)_pages.count || index == _index) return;
    [_pager setContentOffset:CGPointMake(_pager.bounds.size.width * (CGFloat)index, 0) animated:YES];
}

- (void)showMenu {
    ExteriaSymbol symbols[1] = {ExteriaSymbolArrowDown};
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"avatar.save", nil)] symbols:symbols
                                                               handler:^(NSUInteger index) {
        (void)index;
        [self savePhoto];
    }] autorelease];
    CGRect more = _more.frame;
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(more), CGRectGetMaxY(more))];
}

/* the photo on the page that is shown goes to the gallery as it is on screen, the sharp one when it has come and the small one before */
- (void)savePhoto {
    if (_index < 0 || _index >= (NSInteger)_pages.count) return;
    UIImage *image = ((ExteriaAvatarPage *)[_pages objectAtIndex:(NSUInteger)_index])->image.image;
    if (!image) { [self showToast:NSLocalizedString(@"avatar.save.wait", nil)]; return; }
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)context {
    (void)image; (void)context;
    if (error) NSLog(@"exteria: the profile photo was not saved: %@", error);
    [self showToast:NSLocalizedString(error ? @"avatar.save.failed" : @"avatar.saved", nil)];
}

- (void)showToast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.4 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

- (void)updateCounter {
    [self updateDate];
    NSInteger total = (NSInteger)_photos.count;
    _counter.hidden = total < 2;
    _counter.text = [NSString stringWithFormat:NSLocalizedString(@"avatar.counter", nil), (long)_index + 1, (long)total];
    [UIView animateWithDuration:0.2 animations:^{ [self layoutThumbs]; }];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat width = scrollView.bounds.size.width;
    if (width <= 0 || _photos.count == 0) return;
    NSInteger index = (NSInteger)floor((scrollView.contentOffset.x + width / 2) / width);
    index = MAX(0, MIN(index, (NSInteger)_photos.count - 1));
    if (index == _index) return;
    _index = index;
    [self updateCounter];
    [self loadPagesAround:index];
}

- (void)close {
    if ([self respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

@end
