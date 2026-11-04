#import "exteria_video_stage.h"

#include "exteria_fmp4.h"

BOOL ExteriaWritePlainVideo(NSString *source, NSString *destination) {
    exteria_status status = exteria_fmp4_scan(source.fileSystemRepresentation);
    if (status != EXTERIA_OK) {
        if (status != EXTERIA_E_NOTFOUND) NSLog(@"exteria: the video %@ could not be looked at: %s", source.lastPathComponent, exteria_status_name(status));
        return NO;
    }
    status = exteria_fmp4_remux(source.fileSystemRepresentation, destination.fileSystemRepresentation);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: the fragmented video %@ could not be made plain: %s", source.lastPathComponent, exteria_status_name(status));
        return NO;
    }
    return YES;
}

BOOL ExteriaStageVideo(NSString *source, NSString *destination, NSError **error) {
    if (ExteriaWritePlainVideo(source, destination)) return YES;
    return [[NSFileManager defaultManager] linkItemAtPath:source toPath:destination error:error];
}

dispatch_queue_t ExteriaVideoStageQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("exteria.video.stage", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

void ExteriaStageVideoAsync(NSString *source, NSString *destination, void (^completion)(BOOL, NSError *)) {
    void (^done)(BOOL, NSError *) = [completion copy];
    NSString *from = [source copy], *to = [destination copy];
    dispatch_async(ExteriaVideoStageQueue(), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        BOOL staged = ExteriaStageVideo(from, to, &error);
        [error retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            done(staged, error);
            [error release];
            [done release];
        });
        [from release];
        [to release];
        [pool drain];
    });
}
