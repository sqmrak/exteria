#import "exteria_attach_flow.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AddressBookUI/AddressBookUI.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "exteria_attach_options.h"
#import "exteria_attach_pager.h"
#import "exteria_location_controller.h"
#import "exteria_classic_chrome.h"
#import "exteria_theme.h"
#import "exteria_file_picker.h"
#import "exteria_photo_library.h"
#import "exteria_image_decoder.h"
#import "exteria_media_viewer.h"
#import "exteria_weak_reference.h"
#import "exteria_chat_settings.h"

/* the small picture a bubble shows while its photo or video goes up */
#define OUTGOING_PREVIEW_SIDE 480.0

static UIImage *ExteriaOutgoingThumbnail(UIImage *image) {
    CGSize size = image.size;
    if (size.width < 1 || size.height < 1) return nil;
    CGFloat scale = MIN(1.0, OUTGOING_PREVIEW_SIDE / MAX(size.width, size.height));
    CGSize target = CGSizeMake(MAX(1, floor(size.width * scale)), MAX(1, floor(size.height * scale)));
    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumbnail;
}

/* a photo is sent at the size a small screen shows; a larger one only slows the upload of an old phone, so the larger size is the person's choice */
#define PHOTO_SIDE_MAX ((ExteriaChatFlagGet(ExteriaChatFlagAlwaysHD) || ExteriaPhotosAvailable()) ? 2560.0 : 1280.0)
#define PHOTO_QUALITY (ExteriaPhotosAvailable() ? 0.90 : 0.82)
/* the standard quality of the gallery sheet's menu: a smaller side and a lighter jpeg than usual */
#define PHOTO_SIDE_STANDARD 800.0
#define PHOTO_QUALITY_STANDARD 0.7
@interface ExteriaAttachFlow () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate, ABPeoplePickerNavigationControllerDelegate> {
    UIViewController *_host;
    void (^_handler)(ExteriaOutgoing *);
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaLocationController *_locationPicker;
    UIView *_busy;
    BOOL _cancelled;
    ExteriaWeakReference *_weak;
    ExteriaMediaViewer *_preview;
    /* a selection of several that waits in the pager: collected until every item is loaded, then the ones the person kept wait their turn to be prepared */
    NSMutableArray *_collected;
    NSMutableArray *_ready;
    ExteriaAttachPager *_pager;
    UIImagePickerController *_picker;
    UIPopoverController *_popover;
    AVAssetExportSession *_export;
    NSString *_caption;
    /* the choices of the sheet for the selection that is going through, and whether the first picture of it has taken the caption yet */
    ExteriaAttachOptions *_options;
    BOOL _captionTaken;
    NSMutableArray *_assetQueue;
    /* the photos and videos of one selection of several, held until the whole selection is through the previews, then sent as one album */
    NSMutableArray *_album;
    void (^_albumHandler)(NSArray *outgoings);
    int _photoRequest;
    ALAssetsLibrary *_assetLibrary;
    ABPeoplePickerNavigationController *_contacts;
}
@end

@implementation ExteriaAttachFlow

@synthesize albumHandler = _albumHandler;
@synthesize session = _session, dialog = _dialog;

- (id)initWithHost:(UIViewController *)host handler:(void (^)(ExteriaOutgoing *))handler {
    self = [super init];
    if (!self) return nil;
    _host = host;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _handler = [handler copy];
    return self;
}

- (void)dealloc {
    [self cancel];
    [_handler release];
    [_weak release];
    [_assetQueue release];
    [_album release];
    [_albumHandler release];
    [_assetLibrary release];
    [_caption release];
    [_options release];
    [_session release]; [_dialog release];
    [super dealloc];
}

static NSString *ExteriaTemporaryFile(NSString *extension) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-%08x%08x.%@", arc4random(), arc4random(), extension]];
}

- (void)alert:(NSString *)text {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (BOOL)cancelled { return _cancelled; }

- (void)showBusy {
    if (_busy) return;
    UIView *host = _host.view;
    _busy = [[UIView alloc] initWithFrame:host.bounds];
    _busy.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _busy.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge] autorelease];
    spinner.center = CGPointMake(host.bounds.size.width / 2, host.bounds.size.height / 2);
    spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [spinner startAnimating];
    [_busy addSubview:spinner];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake((host.bounds.size.width - 120) / 2, host.bounds.size.height / 2 + 36, 120, 44);
    cancel.autoresizingMask = spinner.autoresizingMask;
    [cancel setTitle:NSLocalizedString(@"attach.cancel", nil) forState:UIControlStateNormal];
    [cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [_busy addSubview:cancel];
    [host addSubview:_busy];
}

- (void)hideBusy {
    [_busy removeFromSuperview];
    [_busy release];
    _busy = nil;
}

- (void)deliver:(ExteriaOutgoing *)outgoing {
    [self hideBusy];
    if (_cancelled || !outgoing) {
        if (outgoing && outgoing->temporary && outgoing->path) [[NSFileManager defaultManager] removeItemAtPath:outgoing->path error:NULL];
        return;
    }
    if (_album) [_album addObject:outgoing];
    else _handler(outgoing);
    if (_ready.count) [self nextReady];
    else if (_assetQueue.count) [self nextAsset];
    else [self flushAlbum];
}

/* the selection is over, whole or cut short: what went through the previews goes out, as an album when there are two or more */
- (void)flushAlbum {
    NSArray *items = [_album autorelease];
    _album = nil;
    if (!items.count || _cancelled) return;
    if (items.count == 1 || !_albumHandler) {
        for (ExteriaOutgoing *outgoing in items) _handler(outgoing);
        return;
    }
    _albumHandler(items);
}

- (void)endQueue {
    [_assetQueue removeAllObjects];
    [_collected release]; _collected = nil;
    [_ready removeAllObjects];
    [self flushAlbum];
}

#pragma mark gallery

- (void)chooseGallery {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self alert:NSLocalizedString(@"attach.gallery.unavailable", nil)];
        return;
    }
    if (_cancelled || _picker || _preview || _export || _busy) return;
    [_options release]; _options = nil;
    UIImagePickerController *picker = [[[UIImagePickerController alloc] init] autorelease];
    _picker = [picker retain];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    picker.delegate = self;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        _popover = [[UIPopoverController alloc] initWithContentViewController:picker];
        _popover.delegate = self;
        CGRect bounds = _host.view.bounds;
        [_popover presentPopoverFromRect:CGRectMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - 48, 1, 1) inView:_host.view permittedArrowDirections:UIPopoverArrowDirectionDown animated:YES];
    } else [_host presentViewController:picker animated:YES completion:nil];
}

- (void)chooseCamera {
    if (_cancelled || _picker || _preview || _busy) return;
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self alert:NSLocalizedString(@"attach.camera.unavailable", nil)]; return;
    }
    [_options release]; _options = nil;
    _picker = [[UIImagePickerController alloc] init];
    _picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    _picker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
    _picker.delegate = self;
    [_host presentViewController:_picker animated:YES completion:nil];
}

- (void)chooseAssets:(NSArray *)urls options:(ExteriaAttachOptions *)options {
    if (_cancelled || _picker || _preview || _pager || _busy || !urls.count || urls.count > 10) return;
    [_options release];
    _options = [options retain];
    _captionTaken = NO;
    [_assetQueue release]; _assetQueue = [urls mutableCopy];
    [_album release];
    _album = urls.count > 1 ? [[NSMutableArray alloc] init] : nil;
    /* a selection of pictures that go out as they are is looked at first, so the person can page between them and edit; documents have nothing to edit */
    [_collected release]; _collected = nil;
    [_ready release]; _ready = nil;
    if (urls.count > 1 && !options->preview && !options->asFiles) _collected = [[NSMutableArray alloc] init];
    if (!_assetLibrary) _assetLibrary = [[NSClassFromString(@"ALAssetsLibrary") alloc] init];
    [self nextAsset];
}

/* a selection sent from the sheet goes straight out, with the words of the sheet on the first picture; one opened by a tap goes through the editor */
- (BOOL)sendsDirectly {
    return _options && !_options->preview;
}

- (void)takeCaptionForNextItem {
    [_caption release];
    _caption = nil;
    if (_captionTaken || ![self sendsDirectly]) return;
    _captionTaken = YES;
    _caption = [_options->caption copy];
}

- (void)nextAsset {
    if (_cancelled || !_assetQueue.count) return;
    NSURL *url = [[[_assetQueue objectAtIndex:0] retain] autorelease];
    [_assetQueue removeObjectAtIndex:0];
    BOOL direct = [self sendsDirectly];
    if (direct && !_collected) [self takeCaptionForNextItem];
    if ([url.scheme isEqualToString:@"exteria-photo"]) {
        [self showBusy];
        if (direct && _options->asFiles && !ExteriaPhotoURLIsVideo(url)) {
            _photoRequest = ExteriaPhotoOriginal(url, ^(NSData *data, NSString *extension, NSString *name, NSString *error) {
                _photoRequest = 0;
                if (_cancelled) return;
                if (!data) {
                    NSLog(@"exteria: selected photo not loaded: %@", error);
                    [self hideBusy]; [self endQueue]; [self alert:NSLocalizedString(@"attach.failed", nil)];
                    return;
                }
                [self prepareOriginalData:data extension:extension name:name];
            });
            return;
        }
        _photoRequest = ExteriaPhotoPreview(url, ^(UIImage *image, NSURL *movie, NSString *error) {
            _photoRequest = 0;
            [self hideBusy];
            if (_cancelled) return;
            if (movie) [self presentOrPrepareMovie:movie];
            else if (image) [self presentOrPreparePhoto:image];
            else {
                NSLog(@"exteria: selected photo not loaded: %@", error);
                [self endQueue]; [self alert:NSLocalizedString(@"attach.failed", nil)];
            }
        });
        return;
    }
    if (!_assetLibrary || ![url.scheme isEqualToString:@"assets-library"]) {
        [self endQueue]; [self alert:NSLocalizedString(@"attach.failed", nil)]; return;
    }
    [self showBusy];
    [_assetLibrary assetForURL:url resultBlock:^(ALAsset *asset) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideBusy];
            if (_cancelled) return;
            if (!asset) { [self endQueue]; [self alert:NSLocalizedString(@"attach.failed", nil)]; return; }
            if ([[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo]) {
                if (direct && _options->asFiles) [self prepareOriginalOfAsset:asset];
                else [self presentOrPrepareMovie:url];
            } else if (direct && _options->asFiles) {
                [self prepareOriginalOfAsset:asset];
            } else {
                ALAssetRepresentation *rep = asset.defaultRepresentation;
                CGImageRef screen = rep.fullScreenImage;
                UIImage *image = screen ? [UIImage imageWithCGImage:screen scale:1 orientation:UIImageOrientationUp] : nil;
                [self presentOrPreparePhoto:image];
            }
        });
    } failureBlock:^(NSError *error) {
        NSLog(@"exteria: selected asset not loaded: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideBusy]; [self endQueue];
            if (!_cancelled) [self alert:NSLocalizedString(@"attach.failed", nil)];
        });
    }];
}

- (void)collectItem:(ExteriaAttachItem *)item {
    [_collected addObject:item];
    if (_assetQueue.count) [self nextAsset];
    else [self showPager];
}

- (void)showPager {
    ExteriaWeakReference *weak = _weak;
    NSArray *items = [[_collected retain] autorelease];
    [_collected release]; _collected = nil;
    _pager = [[ExteriaAttachPager alloc] initWithItems:items caption:_options->caption send:^(NSArray *kept, NSString *caption) {
        ExteriaAttachFlow *flow = weak.target;
        if (!flow || flow->_cancelled) return;
        [flow->_pager release]; flow->_pager = nil;
        if (kept.count > 1) {
            flow->_options->viewOnce = NO;
            if (!flow->_album) flow->_album = [[NSMutableArray alloc] init];
        }
        /* the words of the pager replace those of the sheet, and the first item that goes out takes them */
        [flow->_options->caption release];
        flow->_options->caption = [caption copy];
        flow->_captionTaken = NO;
        [flow->_ready release];
        flow->_ready = [kept mutableCopy];
        [flow nextReady];
    } cancel:^{
        ExteriaAttachFlow *flow = weak.target;
        if (flow) { [flow->_pager release]; flow->_pager = nil; [flow endQueue]; }
    }];
    [_host presentViewController:_pager animated:YES completion:nil];
}

/* the next item the pager kept goes through the same preparation as a selection that is sent straight away */
- (void)nextReady {
    if (_cancelled || !_ready.count) {
        [self flushAlbum];
        return;
    }
    ExteriaAttachItem *item = [[[_ready objectAtIndex:0] retain] autorelease];
    [_ready removeObjectAtIndex:0];
    [self takeCaptionForNextItem];
    if (item->movie) [self prepareMovieAtURL:item->movie];
    else [self preparePhoto:item->image];
}

- (void)presentOrPrepareMovie:(NSURL *)movie {
    if (_collected) {
        ExteriaAttachItem *item = [[[ExteriaAttachItem alloc] init] autorelease];
        item->movie = [movie retain];
        [self collectItem:item];
        return;
    }
    if ([self sendsDirectly]) [self prepareMovieAtURL:movie];
    else [self previewMovie:movie];
}

- (void)presentOrPreparePhoto:(UIImage *)image {
    if (!image) {
        [self endQueue]; [self alert:NSLocalizedString(@"attach.failed", nil)];
        return;
    }
    if (_collected) {
        ExteriaAttachItem *item = [[[ExteriaAttachItem alloc] init] autorelease];
        item->image = [image retain];
        [self collectItem:item];
        return;
    }
    if (_options && _options->preview) {
        _options->preview = NO;
        _collected = [[NSMutableArray alloc] init];
        ExteriaAttachItem *item = [[[ExteriaAttachItem alloc] init] autorelease];
        item->image = [image retain];
        [self collectItem:item];
        return;
    }
    if ([self sendsDirectly]) [self preparePhoto:image];
    else [self previewPhoto:image url:nil];
}

static NSString *ExteriaMimeOfPath(NSString *path);

/* the bytes of a photo as the library keeps them, written out and sent as a document: nothing is scaled or recompressed on the way */
- (void)prepareOriginalData:(NSData *)data extension:(NSString *)extension name:(NSString *)name {
    NSString *path = ExteriaTemporaryFile(extension);
    NSString *caption = [[_caption copy] autorelease];
    ExteriaOutgoing *outgoing = nil;
    if ([data writeToFile:path atomically:YES]) {
        outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
        outgoing->kind = ExteriaOutgoingFile;
        outgoing->caption = [caption copy];
        outgoing->path = [path copy];
        outgoing->name = [name copy];
        outgoing->mime = [ExteriaMimeOfPath(path) copy];
        outgoing->temporary = YES;
    } else {
        NSLog(@"exteria: the original photo was not written");
        [self alert:NSLocalizedString(@"attach.failed", nil)];
    }
    [self deliver:outgoing];
}

/* the old library hands over a representation; it is copied in pieces, so a photo of twenty megabytes never sits in memory whole */
- (void)prepareOriginalOfAsset:(ALAsset *)asset {
    ALAssetRepresentation *rep = asset.defaultRepresentation;
    long long size = rep.size;
    NSString *name = rep.filename.length ? rep.filename : @"photo.jpg";
    NSString *path = ExteriaTemporaryFile(name.pathExtension.length ? name.pathExtension : @"jpg");
    BOOL ok = size > 0 && [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *out = ok ? [NSFileHandle fileHandleForWritingAtPath:path] : nil;
    enum { Piece = 256 * 1024 };
    uint8_t *buffer = out ? malloc(Piece) : NULL;
    long long done = 0;
    while (buffer && done < size) {
        NSError *error = nil;
        NSUInteger want = (NSUInteger)MIN((long long)Piece, size - done);
        NSUInteger got = [rep getBytes:buffer fromOffset:done length:want error:&error];
        if (!got || error) { NSLog(@"exteria: the original of an asset was not read: %@", error); break; }
        NSData *piece = [NSData dataWithBytesNoCopy:buffer length:got freeWhenDone:NO];
        [out writeData:piece];
        done += got;
    }
    [out closeFile];
    BOOL whole = buffer && done == size;
    free(buffer);
    if (!whole) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [self endQueue]; [self alert:NSLocalizedString(@"attach.failed", nil)];
        return;
    }
    NSString *caption = [[_caption copy] autorelease];
    ExteriaOutgoing *outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
    outgoing->kind = ExteriaOutgoingFile;
    outgoing->caption = [caption copy];
    outgoing->path = [path copy];
    outgoing->name = [name copy];
    outgoing->mime = [ExteriaMimeOfPath(path) copy];
    outgoing->temporary = YES;
    [self deliver:outgoing];
}

- (void)chooseContact {
    if (_cancelled || _contacts || _picker || _preview || _busy) return;
    Class pickerClass = NSClassFromString(@"ABPeoplePickerNavigationController");
    if (!pickerClass) { [self alert:NSLocalizedString(@"attach.contact.unavailable", nil)]; return; }
    _contacts = [[pickerClass alloc] init];
    _contacts.peoplePickerDelegate = self;
    if ([_contacts respondsToSelector:NSSelectorFromString(@"setPredicateForSelectionOfPerson:")])
        [_contacts setValue:[NSPredicate predicateWithValue:NO] forKey:@"predicateForSelectionOfPerson"];
    _contacts.displayedProperties = [NSArray arrayWithObject:[NSNumber numberWithInt:kABPersonPhoneProperty]];
    [_host presentViewController:_contacts animated:YES completion:nil];
}

- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)picker {
    picker.peoplePickerDelegate = nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
    [_contacts release]; _contacts = nil;
}

- (void)sharePerson:(ABRecordRef)person property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier {
    if (property != kABPersonPhoneProperty) return;
    ABMultiValueRef numbers = ABRecordCopyValue(person, kABPersonPhoneProperty);
    CFIndex index = numbers ? ABMultiValueGetIndexForIdentifier(numbers, identifier) : kCFNotFound;
    NSString *phone = index != kCFNotFound ? [(NSString *)ABMultiValueCopyValueAtIndex(numbers, index) autorelease] : nil;
    NSString *name = [(NSString *)ABRecordCopyCompositeName(person) autorelease];
    if (numbers) CFRelease(numbers);
    if (!phone.length) { [self alert:NSLocalizedString(@"attach.contact.unavailable", nil)]; return; }
    ExteriaOutgoing *outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
    outgoing->kind = ExteriaOutgoingContact;
    outgoing->phone = [phone copy]; outgoing->name = [(name.length ? name : phone) copy];
    _contacts.peoplePickerDelegate = nil;
    [_contacts dismissViewControllerAnimated:YES completion:^{ [self deliver:outgoing]; }];
    [_contacts release]; _contacts = nil;
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)picker shouldContinueAfterSelectingPerson:(ABRecordRef)person {
    (void)picker; (void)person; return YES;
}
- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)picker shouldContinueAfterSelectingPerson:(ABRecordRef)person
                              property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier {
    (void)picker; [self sharePerson:person property:property identifier:identifier]; return NO;
}
/* ios 8 replaces shouldContinueAfterSelectingPerson with didSelectPerson */
- (void)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)picker didSelectPerson:(ABRecordRef)person
                              property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier {
    (void)picker; [self sharePerson:person property:property identifier:identifier];
}

- (void)dismissPicker:(UIImagePickerController *)picker completion:(void (^)(void))completion {
    if (_popover) {
        _popover.delegate = nil; [_popover dismissPopoverAnimated:NO];
        [_popover release]; _popover = nil;
        if (completion) completion();
    } else [picker dismissViewControllerAnimated:YES completion:completion];
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popover {
    (void)popover;
    _picker.delegate = nil; [_picker release]; _picker = nil;
    _popover.delegate = nil; [_popover release]; _popover = nil;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    picker.delegate = nil;
    [self dismissPicker:picker completion:nil];
    [_picker release]; _picker = nil;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    NSString *type = [info objectForKey:UIImagePickerControllerMediaType];
    UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];
    NSURL *movie = [info objectForKey:UIImagePickerControllerMediaURL];
    NSURL *imageURL = [info objectForKey:@"UIImagePickerControllerImageURL"];
    picker.delegate = nil;
    [self dismissPicker:picker completion:^{
        if (_cancelled) return;
        if ([type isEqualToString:(NSString *)kUTTypeMovie] && movie) [self previewMovie:movie];
        else if (image || imageURL) [self previewPhoto:image url:imageURL];
        else [self alert:NSLocalizedString(@"attach.failed", nil)];
    }];
    [_picker release]; _picker = nil;
}

- (void)previewMovie:(NSURL *)url {
    ExteriaWeakReference *weak = _weak;
    _preview = [[ExteriaMediaViewer alloc] initWithVideoURL:url send:^(NSString *caption) {
        ExteriaAttachFlow *flow = weak.target;
        if (!flow || flow->_cancelled) return;
        [flow->_caption release]; flow->_caption = [caption copy];
        [flow->_preview release]; flow->_preview = nil;
        [flow prepareMovieAtURL:url];
    }];
    _preview.cancelHandler = ^{
        ExteriaAttachFlow *flow = weak.target;
        if (flow) { [flow->_preview release]; flow->_preview = nil; [flow endQueue]; }
    };
    [_host presentViewController:_preview animated:YES completion:nil];
}

- (void)previewPhoto:(UIImage *)image url:(NSURL *)url {
    [self showBusy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *bounded = url ? ExteriaDecodeImageAtURL(url, PHOTO_SIDE_MAX) : nil;
        if (!bounded && image.size.width > 0 && image.size.height > 0) {
            CGFloat scale = MIN(1, PHOTO_SIDE_MAX / MAX(image.size.width, image.size.height));
            CGSize size = CGSizeMake(MAX(1, floor(image.size.width * scale)), MAX(1, floor(image.size.height * scale)));
            UIGraphicsBeginImageContextWithOptions(size, YES, 1);
            [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
            bounded = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
        }
        [bounded retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideBusy];
            if (!_cancelled && bounded) {
                if (!_options) _options = [[ExteriaAttachOptions alloc] init];
                _options->preview = NO;
                _collected = [[NSMutableArray alloc] init];
                ExteriaAttachItem *item = [[[ExteriaAttachItem alloc] init] autorelease];
                item->image = [bounded retain];
                [self collectItem:item];
            } else if (!_cancelled) [self alert:NSLocalizedString(@"attach.failed", nil)];
            [bounded release];
        });
        [pool drain];
    });
}

/* off the main thread: the picture is turned upright, shrunk to the longest side the app sends and written as a jpeg */
- (void)preparePhoto:(UIImage *)image {
    [self showBusy];
    NSString *caption = [[_caption copy] autorelease];
    BOOL standard = _options && _options->standard, spoiler = _options && _options->spoiler;
    CGFloat sideMax = standard ? PHOTO_SIDE_STANDARD : PHOTO_SIDE_MAX;
    CGFloat quality = standard ? PHOTO_QUALITY_STANDARD : PHOTO_QUALITY;
    [image retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        CGSize size = image.size;
        CGFloat scale = MIN(1.0, sideMax / MAX(size.width, size.height));
        CGSize target = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
        UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
        [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
        UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSData *jpeg = UIImageJPEGRepresentation(scaled, quality);
        NSString *path = ExteriaTemporaryFile(@"jpg");
        ExteriaOutgoing *outgoing = nil;
        if (jpeg && [jpeg writeToFile:path atomically:YES]) {
            outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
            outgoing->kind = ExteriaOutgoingPhoto;
            outgoing->spoiler = spoiler;
            outgoing->viewOnce = _options && _options->viewOnce;
            outgoing->caption = [caption copy];
            outgoing->path = [path copy];
            outgoing->name = [path.lastPathComponent copy];
            outgoing->width = (int32_t)target.width;
            outgoing->height = (int32_t)target.height;
            outgoing->temporary = YES;
            outgoing->preview = [ExteriaOutgoingThumbnail(scaled) retain];
        } else {
            NSLog(@"exteria: the photo was not written");
        }
        [image release];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!outgoing && !_cancelled) [self alert:NSLocalizedString(@"attach.failed", nil)];
            [self deliver:outgoing];
        });
        [pool drain];
    });
}

/* normal videos are exported to mp4; files keep their encoded tracks */
- (void)prepareMovieAtURL:(NSURL *)url {
    [self showBusy];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    BOOL asFile = _options && _options->asFiles;
    NSString *path = ExteriaTemporaryFile(asFile ? @"mov" : @"mp4");
    NSString *preset = ExteriaPhotosAvailable() ? AVAssetExportPresetHighestQuality : AVAssetExportPresetMediumQuality;
    if (_options && _options->standard) preset = AVAssetExportPresetLowQuality;
    if (asFile) preset = AVAssetExportPresetPassthrough;
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    NSString *fileType = asFile ? AVFileTypeQuickTimeMovie : AVFileTypeMPEG4;
    if (!export || ![export.supportedFileTypes containsObject:fileType]) {
        [export release]; [self hideBusy]; [self alert:NSLocalizedString(@"attach.failed", nil)]; return;
    }
    _export = [export retain];
    export.outputURL = [NSURL fileURLWithPath:path];
    export.outputFileType = fileType;
    export.shouldOptimizeForNetworkUse = YES;
    [export exportAsynchronouslyWithCompletionHandler:^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        BOOL done = export.status == AVAssetExportSessionStatusCompleted;
        if (!done) NSLog(@"exteria: the movie was not exported: %@", export.error);
        AVURLAsset *made = done ? [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil] : nil;
        NSArray *tracks = [made tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *track = tracks.count ? [tracks objectAtIndex:0] : nil;
        CGSize natural = track ? CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform) : CGSizeZero;
        double seconds = made ? CMTimeGetSeconds(made.duration) : 0;
        /* the first frame, made here and not on the main thread, is what the bubble shows until the server has the video */
        UIImage *poster = nil;
        if (made && track) {
            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:made];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(OUTGOING_PREVIEW_SIDE, OUTGOING_PREVIEW_SIDE);
            CGImageRef frame = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:NULL];
            if (frame) {
                poster = [UIImage imageWithCGImage:frame];
                CGImageRelease(frame);
            }
        }
        [poster retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaOutgoing *outgoing = nil;
            [_export release]; _export = nil;
            if (!_cancelled && done && track && isfinite(seconds) && seconds > 0 && seconds <= INT32_MAX / 1000.0 && fabs(natural.width) > 0 && fabs(natural.height) > 0 && fabs(natural.width) <= INT32_MAX && fabs(natural.height) <= INT32_MAX) {
                outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
                outgoing->kind = asFile ? ExteriaOutgoingFile : ExteriaOutgoingVideo;
                outgoing->spoiler = _options && _options->spoiler;
                outgoing->viewOnce = !asFile && _options && _options->viewOnce;
                outgoing->caption = [_caption copy];
                outgoing->path = [path copy];
                outgoing->name = [path.lastPathComponent copy];
                if (asFile) outgoing->mime = [@"video/quicktime" copy];
                outgoing->durationMs = (int32_t)(seconds * 1000);
                outgoing->width = (int32_t)fabs(natural.width);
                outgoing->height = (int32_t)fabs(natural.height);
                outgoing->temporary = YES;
                outgoing->preview = [poster retain];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
                if (!_cancelled) [self alert:NSLocalizedString(@"attach.failed", nil)];
            }
            [poster release];
            [self deliver:outgoing];
        });
        [export release];
        [pool drain];
    }];
}

#pragma mark file

static NSString *ExteriaMimeOfPath(NSString *path) {
    NSString *extension = path.pathExtension;
    if (!extension.length) return @"application/octet-stream";
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL);
    NSString *mime = uti ? [(NSString *)UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType) autorelease] : nil;
    if (uti) CFRelease(uti);
    return mime.length ? mime : @"application/octet-stream";
}

- (void)chooseFile {
    ExteriaFilePicker *picker = [[[ExteriaFilePicker alloc] initWithDirectory:nil handler:^(NSString *path) {
        ExteriaOutgoing *outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
        outgoing->kind = ExteriaOutgoingFile;
        outgoing->path = [path copy];
        outgoing->name = [path.lastPathComponent copy];
        outgoing->mime = [ExteriaMimeOfPath(path) copy];
        [self deliver:outgoing];
    } cancel:nil] autorelease];
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:picker] autorelease];
    if (ExteriaThemeIsClassic()) ExteriaClassicStyleNavigationBar(navigation.navigationBar);
    [_host presentViewController:navigation animated:YES completion:nil];
}

#pragma mark location

- (void)chooseLocation {
    if (_cancelled || _locationPicker) return;
    exteria_geo_point point;
    memset(&point,0,sizeof(point));
    ExteriaWeakReference *weak=_weak;
    _locationPicker=[[ExteriaLocationController alloc] initWithSession:_session dialog:_dialog location:point selection:^(exteria_geo_point selected) {
        ExteriaAttachFlow *flow=weak.target;
        if (!flow || flow->_cancelled) return;
        [flow->_locationPicker dismissViewControllerAnimated:YES completion:nil];
        [flow->_locationPicker release]; flow->_locationPicker=nil;
        ExteriaOutgoing *outgoing=[[[ExteriaOutgoing alloc] init] autorelease];
        outgoing->kind=ExteriaOutgoingLocation;
        outgoing->latitude=selected.latitude; outgoing->longitude=selected.longitude;
        outgoing->location=selected;
        [flow deliver:outgoing];
    }];
    _locationPicker.closeHandler=^{
        ExteriaAttachFlow *flow=weak.target;
        if (!flow) return;
        [flow->_locationPicker release]; flow->_locationPicker=nil;
    };
    UINavigationController *navigation=[[[UINavigationController alloc] initWithRootViewController:_locationPicker] autorelease];
    if (ExteriaThemeIsClassic()) ExteriaClassicStyleNavigationBar(navigation.navigationBar);
    [_host presentViewController:navigation animated:YES completion:nil];
}

- (void)cancel {
    _cancelled = YES;
    ExteriaCancelPhotoRequest(_photoRequest); _photoRequest = 0;
    [_assetQueue removeAllObjects];
    for (ExteriaOutgoing *held in _album) if (held->temporary && held->path) [[NSFileManager defaultManager] removeItemAtPath:held->path error:NULL];
    [_album release]; _album = nil;
    [_collected release]; _collected = nil;
    [_ready release]; _ready = nil;
    if (_pager.presentingViewController) [_pager dismissViewControllerAnimated:NO completion:nil];
    [_pager release]; _pager = nil;
    _contacts.peoplePickerDelegate = nil;
    if (_contacts.presentingViewController) [_contacts dismissViewControllerAnimated:NO completion:nil];
    [_contacts release]; _contacts = nil;
    [_weak clear];
    [_export cancelExport];
    _popover.delegate = nil; [_popover dismissPopoverAnimated:NO]; [_popover release]; _popover = nil;
    _picker.delegate = nil;
    if (_picker.presentingViewController) [_picker dismissViewControllerAnimated:NO completion:nil];
    [_picker release]; _picker = nil;
    if (_preview.presentingViewController) [_preview dismissViewControllerAnimated:NO completion:nil];
    [_preview release]; _preview = nil;
    [_locationPicker cancel];
    if (_locationPicker.presentingViewController || _locationPicker.navigationController.presentingViewController)
        [_locationPicker dismissViewControllerAnimated:NO completion:nil];
    [_locationPicker release]; _locationPicker=nil;
    [self hideBusy];
}

@end
