#import "exteria_devices_sticker.h"

#import "exteria_image_decoder.h"
#import "exteria_lottie_view.h"

/* the key names the animation in the log and in the file of its first frame */
static NSString *const ExteriaDevicesStickerKey = @"devices.laptop";

static NSString *ExteriaDevicesStickerPath(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if (!roots.count) return nil;
    return [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria/devices-sticker.tgs"];
}

@implementation ExteriaDevicesSticker

+ (NSData *)storedData {
    NSString *path = ExteriaDevicesStickerPath();
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    return data && ExteriaFileFormatOfData(data) == ExteriaFileFormatGzip ? data : nil;
}

+ (void)storeData:(NSData *)data {
    NSString *path = ExteriaDevicesStickerPath();
    if (!path || !data) return;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"exteria: the sticker of the devices screen was not kept: %@", error);
    }
}

+ (ExteriaLottieView *)animationWithData:(NSData *)data {
    ExteriaLottieView *view = [[[ExteriaLottieView alloc] initWithPackedData:data key:ExteriaDevicesStickerKey] autorelease];
    view.cachesPoster = YES;
    view.userInteractionEnabled = NO;
    return view;
}

@end
