#import "exteria_team_picture.h"

/* the pictures of the people of the credits are kept: in memory for the next time the page opens, and on disk for the next launch, so the page shows them at once and
   the server only corrects them; a picture was drawn into its wavy outline again at every arrival of a name or a photo, a dozen times for a page */
static NSMutableDictionary *ExteriaTeamImageMemory(void) {
    static NSMutableDictionary *images;
    if (!images) images = [[NSMutableDictionary alloc] init];
    return images;
}

static NSString *ExteriaTeamImageDirectory(void) {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [caches stringByAppendingPathComponent:@"exteria-team"];
}

UIImage *ExteriaStoredTeamImage(NSNumber *identifier) {
    UIImage *image = [ExteriaTeamImageMemory() objectForKey:identifier];
    if (image) return image;
    NSString *path = [ExteriaTeamImageDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%lld.png", identifier.longLongValue]];
    image = [UIImage imageWithContentsOfFile:path];
    if (image) [ExteriaTeamImageMemory() setObject:image forKey:identifier];
    return image;
}

void ExteriaKeepTeamImage(NSNumber *identifier, UIImage *image) {
    if (!image) return;
    [ExteriaTeamImageMemory() setObject:image forKey:identifier];
    NSString *directory = ExteriaTeamImageDirectory();
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%lld.png", identifier.longLongValue]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
            NSData *data = UIImagePNGRepresentation(image);
            if (data) [data writeToFile:path atomically:YES];
        }
    });
}

