#import "exteria_gallery_saver.h"

#import "exteria_image_decoder.h"
#import "exteria_weak_reference.h"

/* a photo is saved as the viewer shows it, which is as large as the library has any use for here */
#define PHOTO_SIDE_MAX 4096.0
/* the pasteboard keeps the decoded image in memory for every app that reads it, so it gets less than the library does */
#define PASTE_SIDE_MAX 2048.0

@interface ExteriaGallerySaver () {
    void (^_completion)(NSString *failureKey);
    NSString *_stagedPath;
}
@end

@implementation ExteriaGallerySaver

- (id)initWithCompletion:(void (^)(NSString *))completion {
    self = [super init];
    if (!self) return nil;
    _completion = [completion copy];
    return self;
}

- (void)dealloc {
    [_completion release];
    [_stagedPath release];
    [super dealloc];
}

- (void)finishWithKey:(NSString *)key {
    if (_stagedPath) [[NSFileManager defaultManager] removeItemAtPath:_stagedPath error:NULL];
    void (^done)(NSString *) = _completion;
    _completion = nil;
    if (done) done(key);
    [done release];
    [self release];
}

/* the answer of the library for a photo */
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)context {
    (void)image;
    (void)context;
    if (error) NSLog(@"exteria: the photo was not saved to the library: %@", error);
    [self finishWithKey:error ? @"media.save.failed" : nil];
}

/* and for a video */
- (void)video:(NSString *)path didFinishSavingWithError:(NSError *)error contextInfo:(void *)context {
    (void)path;
    (void)context;
    if (error) NSLog(@"exteria: the video was not saved to the library: %@", error);
    [self finishWithKey:error ? @"media.save.failed" : nil];
}

- (void)savePhotoAtPath:(NSString *)path {
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *image = [ExteriaDecodeImageAtURL([NSURL fileURLWithPath:path], PHOTO_SIDE_MAX) retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaGallerySaver *saver = weak.target;
            if (!saver) {
                [image release];
                return;
            }
            if (!image) {
                NSLog(@"exteria: the photo to save did not decode");
                [saver finishWithKey:@"media.save.failed"];
            } else {
                UIImageWriteToSavedPhotosAlbum(image, saver, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
            }
            [image release];
        });
        [pool drain];
    });
}

- (void)saveVideoAtPath:(NSString *)path {
    /* a hard link keeps the cached movie where it is without copying it on the main thread; the library wants a name that ends in .mp4 */
    NSString *staged = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-save-%08x.mp4", arc4random()]];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] linkItemAtPath:path toPath:staged error:&error]) {
        NSLog(@"exteria: the video could not be staged for the library: %@", error);
        [self finishWithKey:@"media.save.failed"];
        return;
    }
    _stagedPath = [staged copy];
    if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(staged)) {
        NSLog(@"exteria: the library does not take this video");
        [self finishWithKey:@"media.save.failed"];
        return;
    }
    UISaveVideoAtPathToSavedPhotosAlbum(staged, self, @selector(video:didFinishSavingWithError:contextInfo:), NULL);
}

+ (void)saveMedia:(ExteriaMedia *)media cache:(ExteriaMediaCache *)cache completion:(void (^)(NSString *))completion {
    BOOL photo = media.kind == EXTERIA_PREVIEW_PHOTO;
    BOOL video = media.kind == EXTERIA_PREVIEW_VIDEO || media.kind == EXTERIA_PREVIEW_GIF || media.kind == EXTERIA_PREVIEW_VIDEO_MESSAGE;
    ExteriaRemoteFile *file = photo && media.fullPhotoFile ? media.fullPhotoFile : media.file;
    long long size = photo && media.fullPhotoFile ? media.fullPhotoSize : media.size;
    if ((!photo && !video) || !file || !cache) {
        completion(@"media.save.failed");
        return;
    }
    /* self owns itself until the library answers; finishWithKey: lets go */
    ExteriaGallerySaver *saver = [[ExteriaGallerySaver alloc] initWithCompletion:completion];
    [cache loadPathForFile:file size:size progress:nil completion:^(NSString *path) {
        if (!path) {
            NSLog(@"exteria: the file to save did not load");
            [saver finishWithKey:@"media.save.failed"];
            return;
        }
        if (photo) [saver savePhotoAtPath:path];
        else [saver saveVideoAtPath:path];
    }];
}

+ (void)copyPhotoOfMedia:(ExteriaMedia *)media cache:(ExteriaMediaCache *)cache completion:(void (^)(NSString *))completion {
    ExteriaRemoteFile *file = media.fullPhotoFile ? media.fullPhotoFile : media.file;
    long long size = media.fullPhotoFile ? media.fullPhotoSize : media.size;
    if (media.kind != EXTERIA_PREVIEW_PHOTO || !file || !cache) {
        completion(@"media.save.failed");
        return;
    }
    void (^done)(NSString *) = [completion copy];
    [cache loadPathForFile:file size:size progress:nil completion:^(NSString *path) {
        if (!path) {
            NSLog(@"exteria: the photo to copy did not load");
            done(@"media.save.failed");
            [done release];
            return;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            UIImage *image = [ExteriaDecodeImageAtURL([NSURL fileURLWithPath:path], PASTE_SIDE_MAX) retain];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (image) [UIPasteboard generalPasteboard].image = image;
                else NSLog(@"exteria: the photo to copy did not decode");
                done(image ? nil : @"media.save.failed");
                [done release];
                [image release];
            });
            [pool drain];
        });
    }];
}

@end
