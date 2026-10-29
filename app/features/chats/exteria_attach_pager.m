#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "exteria_attach_pager.h"

#import "exteria_chat_settings.h"
#import "exteria_image_decoder.h"
#import "exteria_photo_library.h"
#import "exteria_photo_editor.h"
#import "exteria_platform.h"
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

- (void)dealloc {
    [image release];
    [movie release];
    [poster release];
    [super dealloc];
}

@end

@interface ExteriaAttachPager () <UIScrollViewDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate> {
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
    UITextField *_caption;
    UIButton *_sendButton;
    NSInteger _index;
    CGFloat _keyboardHeight;
    BOOL _finished;
    BOOL _loadingPhoto;
    UIImagePickerController *_picker;
    UIPopoverController *_popover;
}
@end

@implementation ExteriaAttachPager

- (id)initWithItems:(NSArray *)items caption:(NSString *)caption send:(void (^)(NSArray *, NSString *))send cancel:(void (^)(void))cancel {
    self = [super init];
    if (!self) return nil;
    _items = [items mutableCopy];
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
    [_weak clear];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _pages.delegate = nil;
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
    [_strip release];
    [_top release];
    [_bottom release];
    [_count release];
    [_edit release];
    [_add release];
    [_remove release];
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
    _remove = [self newButtonWithSymbol:ExteriaSymbolTrash action:@selector(remove) label:NSLocalizedString(@"attach.pager.remove", nil)];
    [_top addSubview:_remove];
    _caption = [[UITextField alloc] init];
    _caption.textColor = [UIColor whiteColor];
    _caption.font = [UIFont systemFontOfSize:16];
    _caption.placeholder = NSLocalizedString(@"media.caption", nil);
    _caption.text = _initialCaption;
    _caption.returnKeyType = UIReturnKeyDone;
    _caption.textAlignment = ExteriaTextAlignmentCenter;
    _caption.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
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
    [self rebuild];
    [self loadPosters];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return YES; }

#pragma mark content

/* the first frame of each movie, made off the main thread, since the pages and thumbnails of a movie are empty until it is there */
- (void)loadPosters {
    ExteriaWeakReference *weak = _weak;
    for (ExteriaAttachItem *item in _items) {
        if (!item->movie || item->poster) continue;
        NSURL *url = [item->movie retain];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:url options:nil]];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(POSTER_SIDE, POSTER_SIDE);
            NSError *error = nil;
            CGImageRef frame = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:&error];
            if (!frame) NSLog(@"exteria: no poster for the selected movie: %@", error);
            UIImage *poster = frame ? [[UIImage imageWithCGImage:frame] retain] : nil;
            if (frame) CGImageRelease(frame);
            dispatch_async(dispatch_get_main_queue(), ^{
                ExteriaAttachPager *me = weak.target;
                if (me && poster && [me->_items containsObject:item]) {
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
    if (_index >= (NSInteger)_items.count) _index = (NSInteger)_items.count - 1;
    if (_index < 0) _index = 0;
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

- (void)layoutAll {
    if (!self.isViewLoaded) return;
    CGSize size = self.view.bounds.size;
    UIEdgeInsets safe = [self safeInsets];
    /* the keyboard covers the home indicator, so the bar only clears it while the keyboard is down */
    CGFloat bottomInset = _keyboardHeight > 0 ? 0 : safe.bottom;
    CGFloat inputBottom = size.height - _keyboardHeight;
    CGFloat barTop = safe.top;
    _top.frame = CGRectMake(0, 0, size.width, barTop + BAR_HEIGHT);
    _bottom.frame = CGRectMake(0, inputBottom - INPUT_BAR - bottomInset, size.width, INPUT_BAR + bottomInset);
    _strip.frame = CGRectMake(0, CGRectGetMinY(_bottom.frame) - THUMB_STRIP, size.width, THUMB_STRIP);
    CGFloat pagesTop = CGRectGetMaxY(_top.frame), pagesHeight = MAX(0, CGRectGetMinY(_strip.frame) - pagesTop);
    CGRect pagesFrame = CGRectMake(0, pagesTop, size.width, pagesHeight);
    BOOL resized = !CGSizeEqualToSize(_pages.frame.size, pagesFrame.size);
    _pages.frame = pagesFrame;
    _pages.contentSize = CGSizeMake(size.width * (CGFloat)_items.count, pagesHeight);
    for (UIView *view in _pages.subviews) {
        NSInteger tag = view.tag;
        if (tag >= 1000) {
            view.center = CGPointMake((CGFloat)(tag - 1000) * size.width + size.width / 2, pagesHeight / 2);
        } else {
            view.frame = CGRectMake((CGFloat)tag * size.width, 0, size.width, pagesHeight);
        }
    }
    CGFloat x = THUMB_GAP;
    for (UIView *view in _strip.subviews) {
        view.frame = CGRectMake(x, (THUMB_STRIP - THUMB_SIDE) / 2, THUMB_SIDE, THUMB_SIDE);
        x += THUMB_SIDE + THUMB_GAP;
    }
    _strip.contentSize = CGSizeMake(x, THUMB_STRIP);
    CGFloat buttonSide = 48;
    UIView *close = [_top viewWithTag:1];
    close.frame = CGRectMake(safe.left, barTop + 2, buttonSide, buttonSide);
    _remove.frame = CGRectMake(size.width - safe.right - buttonSide, barTop + 2, buttonSide, buttonSide);
    _edit.frame = CGRectMake(size.width - safe.right - 2 * buttonSide, barTop + 2, buttonSide, buttonSide);
    _add.frame = CGRectMake(size.width - safe.right - 3 * buttonSide, barTop + 2, buttonSide, buttonSide);
    _count.frame = CGRectMake(buttonSide + 8 + safe.left, barTop + 2, MAX(0, size.width - 4 * buttonSide - 16 - safe.left - safe.right), buttonSide);
    _sendButton.frame = CGRectMake(size.width - safe.right - buttonSide - 8, (INPUT_BAR - buttonSide) / 2, buttonSide, buttonSide);
    _caption.frame = CGRectMake(16 + safe.left, 8, MAX(0, size.width - safe.left - safe.right - buttonSide - 32), INPUT_BAR - 16);
    if (resized) _pages.contentOffset = CGPointMake((CGFloat)_index * size.width, 0);
    [self showSelection];
}

- (void)showSelection {
    _count.text = [NSString stringWithFormat:@"%ld / %lu", (long)_index + 1, (unsigned long)_items.count];
    ExteriaAttachItem *current = _index < (NSInteger)_items.count ? [_items objectAtIndex:(NSUInteger)_index] : nil;
    _edit.hidden = !current || current->movie != nil;
    _add.enabled = _items.count < 10 && !_loadingPhoto;
    _add.alpha = _add.enabled ? 1 : 0.4;
    for (UIView *view in _strip.subviews) {
        BOOL selected = view.tag == _index;
        view.layer.borderWidth = selected ? 2 : 0;
        view.layer.borderColor = ExteriaColorAccent().CGColor;
    }
    CGRect shown = CGRectMake(THUMB_GAP + (CGFloat)_index * (THUMB_SIDE + THUMB_GAP), 0, THUMB_SIDE, THUMB_STRIP);
    [_strip scrollRectToVisible:CGRectInset(shown, -THUMB_GAP, 0) animated:NO];
}

#pragma mark paging

- (void)scrollViewDidScroll:(UIScrollView *)scroll {
    if (scroll != _pages || scroll.bounds.size.width <= 0 || !_items.count) return;
    NSInteger index = (NSInteger)floor(scroll.contentOffset.x / scroll.bounds.size.width + 0.5);
    index = MAX(0, MIN((NSInteger)_items.count - 1, index));
    if (index == _index) return;
    _index = index;
    [self showSelection];
}

- (void)thumbTapped:(UIButton *)thumb {
    _index = thumb.tag;
    [_pages setContentOffset:CGPointMake((CGFloat)_index * _pages.bounds.size.width, 0) animated:YES];
    [self showSelection];
}

#pragma mark actions

- (void)addPhoto {
    if (_finished || _loadingPhoto || _picker || _items.count >= 10) return;
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
    Class alertClass = NSClassFromString(@"UIAlertView");
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
                if (image && pager->_items.count < 10) {
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
    if (!item->image) return;
    ExteriaWeakReference *weak = _weak;
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

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return YES;
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:[self.view.window convertRect:end fromWindow:nil] fromView:nil];
    _keyboardHeight = MAX(0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(local));
    NSTimeInterval duration = [[note.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{ [self layoutAll]; }];
}

@end
