#import "exteria_avatar_viewer.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_platform.h"
#import "exteria_remote_file.h"
#import "exteria_session_profile.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define PHOTO_MAX_SIDE 1280.0
#define CLOSE_SIZE 44.0

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
    return self;
}

- (void)dealloc {
    _pager.delegate = nil;
    [_session release];
    [_dialog release];
    [_avatars release];
    [_media release];
    [_photos release];
    [_pager release];
    [_counter release];
    [_close release];
    [_save release];
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
    _pager.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _pager.pagingEnabled = YES;
    ExteriaScrollViewOwnsInsets(_pager);
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.showsVerticalScrollIndicator = NO;
    _pager.delegate = self;
    [_pager addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)] autorelease]];
    [root addSubview:_pager];

    _counter = [[UILabel alloc] init];
    _counter.backgroundColor = [UIColor clearColor];
    _counter.textColor = [UIColor whiteColor];
    _counter.textAlignment = ExteriaTextAlignmentCenter;
    _counter.font = ExteriaFontSemibold(16);
    _counter.hidden = YES;
    [root addSubview:_counter];

    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:ExteriaSymbolImage(ExteriaSymbolClose, 20, [UIColor whiteColor]) forState:UIControlStateNormal];
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    _close.accessibilityLabel = NSLocalizedString(@"story.close", nil);
    [root addSubview:_close];

    /* the day the photo was set, at the foot, and the button that keeps the photo in the gallery */
    _dateLabel = [[UILabel alloc] init];
    _dateLabel.backgroundColor = [UIColor clearColor];
    _dateLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _dateLabel.font = ExteriaFontRegular(15);
    _dateLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
    _dateLabel.shadowOffset = CGSizeMake(0, 1);
    [root addSubview:_dateLabel];
    _save = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_save setImage:ExteriaSymbolImage(ExteriaSymbolArrowDown, 22, [UIColor whiteColor]) forState:UIControlStateNormal];
    _save.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _save.layer.cornerRadius = CLOSE_SIZE / 2;
    _save.accessibilityLabel = NSLocalizedString(@"avatar.save", nil);
    [_save addTarget:self action:@selector(savePhoto) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_save];
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
    UIApplication *application = [UIApplication sharedApplication];
    _statusWasHidden = application.statusBarHidden;
    /* the bar is hidden by the application before iOS 7, which has no prefersStatusBarHidden */
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
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
        [_pager setContentOffset:CGPointZero animated:NO];
        [self loadPagesAround:0];
        [self updateCounter];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) [application setStatusBarHidden:_statusWasHidden withAnimation:UIStatusBarAnimationFade];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    /* the photo runs under the notch; the close button and the counter stand clear of it */
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = insets.top;
    _close.frame = CGRectMake(bounds.size.width - insets.right - CLOSE_SIZE - 6, top + 4, CLOSE_SIZE, CLOSE_SIZE);
    _counter.frame = CGRectMake(insets.left + CLOSE_SIZE + 12, top + 4, MAX(0, bounds.size.width - insets.left - insets.right - 2 * (CLOSE_SIZE + 12)), CLOSE_SIZE);
    CGFloat bottom = insets.bottom + 14;
    _save.frame = CGRectMake(bounds.size.width - insets.right - CLOSE_SIZE - 16, bounds.size.height - bottom - CLOSE_SIZE, CLOSE_SIZE, CLOSE_SIZE);
    _dateLabel.frame = CGRectMake(insets.left + 20, bounds.size.height - bottom - CLOSE_SIZE, MAX(0, CGRectGetMinX(_save.frame) - insets.left - 32), CLOSE_SIZE);
    _toast.frame = CGRectMake(floor((bounds.size.width - 200) / 2), CGRectGetMinY(_save.frame) - 44, 200, 28);
    _spinner.center = CGPointMake(CGRectGetMidX(bounds), bounds.size.height - 90);
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
    int32_t date = _index < (NSInteger)_photos.count ? [[_photos objectAtIndex:(NSUInteger)_index] date] : 0;
    if (date <= 0) { _dateLabel.text = @""; return; }
    NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
    format.dateStyle = NSDateFormatterMediumStyle;
    format.timeStyle = NSDateFormatterShortStyle;
    _dateLabel.text = [NSString stringWithFormat:NSLocalizedString(@"avatar.date", nil), [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]]];
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
    _counter.text = [NSString stringWithFormat:@"%ld / %ld", (long)_index + 1, (long)total];
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
