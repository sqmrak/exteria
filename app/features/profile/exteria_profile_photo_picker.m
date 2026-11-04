#import "exteria_profile_photo_picker.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>

#import <objc/runtime.h>

#import "exteria_photo_library.h"

#define PHOTO_SIDE 640.0
#define STORY_SIDE 1280.0
#define PHOTO_QUALITY 0.85

static NSString *ExteriaProfileSquarePath(UIImage *image) {
    CGSize size = image.size;
    CGFloat side = MIN(size.width, size.height);
    CGFloat out = MIN(PHOTO_SIDE, side);
    if (side <= 0 || !image.CGImage) return nil;
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(image.CGImage);
    BOOL transparent = alpha != kCGImageAlphaNone && alpha != kCGImageAlphaNoneSkipFirst && alpha != kCGImageAlphaNoneSkipLast;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(out, out), !transparent, 1.0);
    CGFloat scale = out / side;
    [image drawInRect:CGRectMake(-(size.width - side) / 2 * scale, -(size.height - side) / 2 * scale, size.width * scale, size.height * scale)];
    UIImage *square = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *data = transparent ? UIImagePNGRepresentation(square) : UIImageJPEGRepresentation(square, PHOTO_QUALITY);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"profile-%u.%@", arc4random(), transparent ? @"png" : @"jpg"]];
    if (!data || ![data writeToFile:path atomically:YES]) {
        NSLog(@"exteria: the profile photo was not written");
        return nil;
    }
    return path;
}

@interface ExteriaProfilePhotoPicker () {
    void (^_picked)(NSString *);
    void (^_sheetPicked)(NSString *, BOOL);
    void (^_failed)(void);
    BOOL _whole;
    UIPopoverController *_popover;
}
@end

@implementation ExteriaProfilePhotoPicker

+ (void)pickFrom:(UIViewController *)host picked:(void (^)(NSString *))picked unavailable:(void (^)(void))unavailable {
    [self pickFrom:host whole:NO picked:picked unavailable:unavailable];
}

+ (void)pickWholeFrom:(UIViewController *)host picked:(void (^)(NSString *))picked unavailable:(void (^)(void))unavailable {
    [self pickFrom:host whole:YES picked:picked unavailable:unavailable];
}

+ (void)pickFrom:(UIViewController *)host whole:(BOOL)whole picked:(void (^)(NSString *))picked unavailable:(void (^)(void))unavailable {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        unavailable();
        return;
    }
    ExteriaProfilePhotoPicker *me = [[ExteriaProfilePhotoPicker alloc] init];
    me->_picked = [picked copy];
    me->_whole = whole;
    UIImagePickerController *picker = [[[UIImagePickerController alloc] init] autorelease];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = me;
    /* the picker holds its delegate weakly; the extra count from alloc is given back when the picker is done */
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        me->_popover = [[UIPopoverController alloc] initWithContentViewController:picker];
        me->_popover.delegate = me;
        CGRect bounds = host.view.bounds;
        [me->_popover presentPopoverFromRect:CGRectMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds), 1, 1)
                                      inView:host.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else [host presentViewController:picker animated:YES completion:nil];
}

- (void)dealloc {
    _popover.delegate = nil;
    [_popover release];
    [_picked release];
    [_sheetPicked release];
    [_failed release];
    [super dealloc];
}

- (void)dismissPicker:(UIImagePickerController *)picker {
    picker.delegate = nil;
    if (_popover) {
        _popover.delegate = nil;
        [_popover dismissPopoverAnimated:YES];
        [_popover release]; _popover = nil;
    } else [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popover {
    (void)popover;
    [(UIImagePickerController *)_popover.contentViewController setDelegate:nil];
    _popover.delegate = nil;
    [_popover release]; _popover = nil;
    [self release];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissPicker:picker];
    [self release];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [[info objectForKey:UIImagePickerControllerOriginalImage] retain];
    [self dismissPicker:picker];
    void (^picked)(NSString *) = [_picked retain];
    BOOL whole = _whole;
    /* the image work stays off the main thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        CGSize size = image.size;
        NSString *path = nil;
        if (whole) {
            CGFloat longest = MAX(size.width, size.height);
            CGFloat scale = longest > STORY_SIDE ? STORY_SIDE / longest : 1;
            CGSize out = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
            if (out.width >= 1 && out.height >= 1) {
                UIGraphicsBeginImageContextWithOptions(out, YES, 1.0);
                [image drawInRect:CGRectMake(0, 0, out.width, out.height)];
                UIImage *fitted = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                NSData *jpeg = UIImageJPEGRepresentation(fitted, PHOTO_QUALITY);
                NSString *candidate = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"story-%u.jpg", arc4random()]];
                if (jpeg && [jpeg writeToFile:candidate atomically:YES]) path = [[candidate copy] autorelease];
                else NSLog(@"exteria: the story photo was not written");
            }
        } else {
            path = ExteriaProfileSquarePath(image);
        }
        [image release];
        NSString *delivered = [path retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            picked(delivered);
            [delivered release];
            [picked release];
        });
        [pool drain];
    });
    [self release];
}

static char ExteriaPickerSheetKey;

+ (void)pickWithSheetIn:(UIView *)host picked:(void (^)(NSString *, BOOL))picked failed:(void (^)(void))failed {
    if (!host) return;
    ExteriaProfilePhotoPicker *me = [[[ExteriaProfilePhotoPicker alloc] init] autorelease];
    me->_sheetPicked = [picked copy];
    me->_failed = [failed copy];
    ExteriaAttachSheet *sheet = [[[ExteriaAttachSheet alloc] init] autorelease];
    sheet.profilePicker = YES;
    sheet.delegate = me;
    /* the sheet holds its delegate weakly, so the sheet holds the picker, and both go together */
    objc_setAssociatedObject(sheet, &ExteriaPickerSheetKey, me, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sheet showInView:host];
}

- (void)attachSheet:(ExteriaAttachSheet *)sheet didChoose:(ExteriaAttachChoice)choice {
    (void)sheet; (void)choice;
}

- (void)attachSheet:(ExteriaAttachSheet *)sheet didChooseAssets:(NSArray *)urls options:(ExteriaAttachOptions *)options {
    (void)sheet; (void)options;
    NSURL *url = urls.count ? [urls objectAtIndex:0] : nil;
    if (!url) return;
    ExteriaProfilePhotoPicker *me = [self retain];
    [ExteriaProfilePhotoPicker loadAssetURL:url completion:^(UIImage *image, NSURL *movie) {
        void (^fail)(void) = ^{ if (me->_failed) me->_failed(); [me release]; };
        if (movie) {
            [ExteriaProfilePhotoPicker squareVideoPathFromURL:movie completion:^(NSString *path) {
                if (!path) { fail(); return; }
                if (me->_sheetPicked) me->_sheetPicked(path, YES);
                [me release];
            }];
            return;
        }
        if (!image) { fail(); return; }
        [ExteriaProfilePhotoPicker squarePathFromImage:image completion:^(NSString *path) {
            if (!path) { fail(); return; }
            if (me->_sheetPicked) me->_sheetPicked(path, NO);
            [me release];
        }];
    }];
}

+ (void)squarePathFromImage:(UIImage *)image completion:(void (^)(NSString *path))completion {
    if (!image || !completion) { if (completion) completion(nil); return; }
    void (^done)(NSString *) = [completion copy];
    UIImage *source = [image retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *path = ExteriaProfileSquarePath(source);
        [source release];
        NSString *delivered = [path retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            done(delivered);
            [delivered release];
            [done release];
        });
        [pool drain];
    });
}

+ (void)loadAssetURL:(NSURL *)url completion:(void (^)(UIImage *, NSURL *))completion {
    void (^done)(UIImage *, NSURL *) = [completion copy];
    if ([url.scheme isEqualToString:@"exteria-photo"]) {
        ExteriaPhotoPreview(url, ^(UIImage *image, NSURL *movie, NSString *error) {
            if (error) NSLog(@"exteria: the picked photo was not loaded: %@", error);
            done(image, movie);
            [done release];
        });
        return;
    }
    Class libraryClass = NSClassFromString(@"ALAssetsLibrary");
    if (!libraryClass || ![url.scheme isEqualToString:@"assets-library"]) {
        done(nil, nil);
        [done release];
        return;
    }
    ALAssetsLibrary *library = [[libraryClass alloc] init];
    [library assetForURL:url resultBlock:^(ALAsset *asset) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL video = asset && [[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo];
            CGImageRef screen = asset && !video ? asset.defaultRepresentation.fullScreenImage : NULL;
            UIImage *image = screen ? [UIImage imageWithCGImage:screen scale:1 orientation:UIImageOrientationUp] : nil;
            done(image, video ? asset.defaultRepresentation.url : nil);
            [done release];
            [library release];
        });
    } failureBlock:^(NSError *error) {
        NSLog(@"exteria: the picked asset was not loaded: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            done(nil, nil);
            [done release];
            [library release];
        });
    }];
}

/* the clip is cut to its middle square, shrunk, kept to ten seconds and stripped of sound, as a moving profile picture has to be; the rotation of the camera is applied to the picture before it is
   cut, since a phone records a portrait clip as a landscape one with a turn in its metadata */
+ (void)squareVideoPathFromURL:(NSURL *)movie completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    void (^fail)(NSString *) = ^(NSString *why) {
        NSLog(@"exteria: the profile video was not made: %@", why);
        done(nil);
        [done release];
    };
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:movie options:nil];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (!tracks.count) { fail(@"no video track"); return; }
    AVAssetTrack *track = [tracks objectAtIndex:0];
    CGSize natural = track.naturalSize;
    CGRect shown = CGRectApplyAffineTransform(CGRectMake(0, 0, natural.width, natural.height), track.preferredTransform);
    CGFloat side = MIN(shown.size.width, shown.size.height);
    if (side < 1) { fail(@"empty picture"); return; }
    CGFloat out = MIN(640, floor(side / 2) * 2);
    CMTime length = CMTimeMinimum(asset.duration, CMTimeMakeWithSeconds(10, 600));
    CMTimeRange range = CMTimeRangeMake(kCMTimeZero, length);
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *kept = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    if (![kept insertTimeRange:range ofTrack:track atTime:kCMTimeZero error:&error]) { fail([error description]); return; }
    CGAffineTransform place = CGAffineTransformConcat(track.preferredTransform,
        CGAffineTransformMakeTranslation(-shown.origin.x - (shown.size.width - side) / 2, -shown.origin.y - (shown.size.height - side) / 2));
    place = CGAffineTransformConcat(place, CGAffineTransformMakeScale(out / side, out / side));
    AVMutableVideoCompositionLayerInstruction *layer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:kept];
    [layer setTransform:place atTime:kCMTimeZero];
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, length);
    instruction.layerInstructions = [NSArray arrayWithObject:layer];
    AVMutableVideoComposition *video = [AVMutableVideoComposition videoComposition];
    video.renderSize = CGSizeMake(out, out);
    video.frameDuration = CMTimeMake(1, 30);
    video.instructions = [NSArray arrayWithObject:instruction];
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetMediumQuality];
    if (!session) { fail(@"no export session"); return; }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"profile-%u.mp4", arc4random()]];
    session.outputURL = [NSURL fileURLWithPath:path];
    session.outputFileType = AVFileTypeMPEG4;
    session.videoComposition = video;
    session.fileLengthLimit = 2 * 1024 * 1024;
    session.shouldOptimizeForNetworkUse = YES;
    [session exportAsynchronouslyWithCompletionHandler:^{
        BOOL ok = session.status == AVAssetExportSessionStatusCompleted;
        NSString *why = ok ? nil : [session.error description];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) { done(path); [done release]; }
            else {
                [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
                fail(why ? why : @"export failed");
            }
            [session release];
        });
    }];
}

@end
