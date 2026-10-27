#import "exteria_profile_photo_picker.h"

#define PHOTO_SIDE 640.0
#define STORY_SIDE 1280.0
#define PHOTO_QUALITY 0.85

@interface ExteriaProfilePhotoPicker () {
    void (^_picked)(NSString *);
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
    /* off the main thread: the middle square of the picture, or the whole of it for a story, shrunk, written as a jpeg */
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
            CGFloat side = MIN(size.width, size.height);
            CGFloat out = MIN(PHOTO_SIDE, side);
            if (side > 0) {
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(out, out), YES, 1.0);
                CGFloat scale = out / side;
                [image drawInRect:CGRectMake(-(size.width - side) / 2 * scale, -(size.height - side) / 2 * scale, size.width * scale, size.height * scale)];
                UIImage *square = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                NSData *jpeg = UIImageJPEGRepresentation(square, PHOTO_QUALITY);
                NSString *candidate = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"profile-%u.jpg", arc4random()]];
                if (jpeg && [jpeg writeToFile:candidate atomically:YES]) path = [[candidate copy] autorelease];
                else NSLog(@"exteria: the profile photo was not written");
            }
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

@end
