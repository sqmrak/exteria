#import "exteria_photo_library.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <dlfcn.h>

/* Photos is absent from the armv7 sdk, so every class is resolved after loading the optional framework */
@protocol ExteriaPhotosManager
- (int)requestImageForAsset:(id)asset targetSize:(CGSize)size contentMode:(NSInteger)mode options:(id)options resultHandler:(void (^)(UIImage *, NSDictionary *))handler;
- (int)requestAVAssetForVideo:(id)asset options:(id)options resultHandler:(void (^)(AVAsset *, AVAudioMix *, NSDictionary *))handler;
- (int)requestImageDataForAsset:(id)asset options:(id)options resultHandler:(void (^)(NSData *, NSString *, NSInteger, NSDictionary *))handler;
- (void)cancelImageRequest:(int)request;
@end

BOOL ExteriaPhotosAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/Frameworks/Photos.framework/Photos", RTLD_LAZY | RTLD_LOCAL);
        available = framework && NSClassFromString(@"PHAsset") && NSClassFromString(@"PHImageManager");
    });
    return available;
}

static id photo_manager(void) {
    return ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PHImageManager"), NSSelectorFromString(@"defaultManager"));
}

void ExteriaRecentPhotos(NSUInteger limit, void (^completion)(NSArray *, NSString *)) {
    if (!ExteriaPhotosAvailable() || !limit || limit > 300) { completion(nil, @"PHOTO_LIBRARY_UNAVAILABLE"); return; }
    ((void (*)(id, SEL, void (^)(NSInteger)))objc_msgSend)(NSClassFromString(@"PHPhotoLibrary"), NSSelectorFromString(@"requestAuthorization:"), ^(NSInteger status) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSMutableArray *assets = nil;
        /* ios 14 limited access returns only the photos the person allowed */
        if (status == 3 || status == 4) {
            id options = [[[NSClassFromString(@"PHFetchOptions") alloc] init] autorelease];
            [options setValue:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]] forKey:@"sortDescriptors"];
            id result = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"PHAsset"), NSSelectorFromString(@"fetchAssetsWithOptions:"), options);
            NSUInteger count = MIN(limit, [result count]);
            assets = [NSMutableArray arrayWithCapacity:count];
            for (NSUInteger i = 0; i < count; ++i) [assets addObject:[result objectAtIndex:i]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assets, assets ? nil : @"PHOTO_LIBRARY_DENIED"); });
        [pool drain];
    });
}

NSURL *ExteriaPhotoURL(id asset) {
    NSString *identifier = [asset valueForKey:@"localIdentifier"];
    return identifier.length ? [NSURL URLWithString:[@"exteria-photo:" stringByAppendingString:identifier]] : nil;
}

NSTimeInterval ExteriaPhotoVideoDuration(id asset) {
    if ([[asset valueForKey:@"mediaType"] integerValue] != 2) return 0;
    return [[asset valueForKey:@"duration"] doubleValue];
}

static id image_options(BOOL preview) {
    id options = [[[NSClassFromString(@"PHImageRequestOptions") alloc] init] autorelease];
    /* the grid asked for the fast format, which hands back the tiny cached thumbnail stretched over the cell; opportunistic gives that at once and the sharp image after it */
    [options setValue:[NSNumber numberWithInteger:preview ? 1 : 0] forKey:@"deliveryMode"];
    [options setValue:[NSNumber numberWithInteger:2] forKey:@"resizeMode"];
    [options setValue:[NSNumber numberWithBool:preview] forKey:@"networkAccessAllowed"];
    return options;
}

void ExteriaPhotoThumbnail(id asset, CGFloat side, void (^completion)(UIImage *)) {
    [(id<ExteriaPhotosManager>)photo_manager() requestImageForAsset:asset targetSize:CGSizeMake(side, side) contentMode:1 options:image_options(NO)
        resultHandler:^(UIImage *image, NSDictionary *info) {
            (void)info;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
        }];
}

int ExteriaPhotoPreview(NSURL *url, void (^completion)(UIImage *, NSURL *, NSString *)) {
    if (!ExteriaPhotosAvailable() || ![url.scheme isEqualToString:@"exteria-photo"]) { completion(nil, nil, @"PHOTO_NOT_FOUND"); return 0; }
    NSString *identifier = url.resourceSpecifier;
    id result = ((id (*)(id, SEL, id, id))objc_msgSend)(NSClassFromString(@"PHAsset"), NSSelectorFromString(@"fetchAssetsWithLocalIdentifiers:options:"),
        [NSArray arrayWithObject:identifier], nil);
    id asset = [result count] ? [result objectAtIndex:0] : nil;
    if (!asset) { completion(nil, nil, @"PHOTO_NOT_FOUND"); return 0; }
    if ([[asset valueForKey:@"mediaType"] integerValue] == 2) {
        id options = [[[NSClassFromString(@"PHVideoRequestOptions") alloc] init] autorelease];
        [options setValue:[NSNumber numberWithBool:YES] forKey:@"networkAccessAllowed"];
        return [(id<ExteriaPhotosManager>)photo_manager() requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *video, AVAudioMix *mix, NSDictionary *info) {
            (void)mix; (void)info;
            NSURL *movie = [video isKindOfClass:[AVURLAsset class]] ? [(AVURLAsset *)video URL] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, movie, movie ? nil : @"VIDEO_UNAVAILABLE"); });
        }];
    } else {
        return [(id<ExteriaPhotosManager>)photo_manager() requestImageForAsset:asset targetSize:CGSizeMake(1280, 1280) contentMode:0 options:image_options(YES)
            resultHandler:^(UIImage *image, NSDictionary *info) {
                if ([[info objectForKey:@"PHImageResultIsDegradedKey"] boolValue]) return;
                dispatch_async(dispatch_get_main_queue(), ^{ completion(image, nil, image ? nil : @"PHOTO_UNAVAILABLE"); });
            }];
    }
}

int ExteriaPhotoOriginal(NSURL *url, void (^completion)(NSData *, NSString *, NSString *, NSString *)) {
    if (!ExteriaPhotosAvailable() || ![url.scheme isEqualToString:@"exteria-photo"]) { completion(nil, nil, nil, @"PHOTO_NOT_FOUND"); return 0; }
    id result = ((id (*)(id, SEL, id, id))objc_msgSend)(NSClassFromString(@"PHAsset"), NSSelectorFromString(@"fetchAssetsWithLocalIdentifiers:options:"),
        [NSArray arrayWithObject:url.resourceSpecifier], nil);
    id asset = [result count] ? [result objectAtIndex:0] : nil;
    if (!asset) { completion(nil, nil, nil, @"PHOTO_NOT_FOUND"); return 0; }
    id options = [[[NSClassFromString(@"PHImageRequestOptions") alloc] init] autorelease];
    [options setValue:[NSNumber numberWithBool:YES] forKey:@"networkAccessAllowed"];
    return [(id<ExteriaPhotosManager>)photo_manager() requestImageDataForAsset:asset options:options
        resultHandler:^(NSData *data, NSString *uti, NSInteger orientation, NSDictionary *info) {
            (void)orientation;
            (void)info;
            /* a type the system names by its uniform type id: heic stays heic, since the server takes any file as a document */
            NSString *extension = [uti isEqualToString:@"public.png"] ? @"png" : ([uti isEqualToString:@"public.heic"] ? @"heic" : @"jpg");
            NSString *name = [NSString stringWithFormat:@"IMG_%@.%@", [url.resourceSpecifier substringToIndex:MIN((NSUInteger)8, url.resourceSpecifier.length)], extension];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, extension, name, data.length ? nil : @"PHOTO_UNAVAILABLE"); });
        }];
}

void ExteriaCancelPhotoRequest(int request) {
    if (request > 0 && ExteriaPhotosAvailable()) [(id<ExteriaPhotosManager>)photo_manager() cancelImageRequest:request];
}
