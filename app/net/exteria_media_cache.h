#import <UIKit/UIKit.h>

#import "exteria_session.h"

@class ExteriaMedia;

/* files of messages, kept by key on disk and decoded pictures kept in memory under a byte limit; one request goes
   to the network per file however many bubbles ask, and a file that failed is not asked for again for a while */
@interface ExteriaMediaCache : NSObject {
    ExteriaSession *_session;
}

- (id)initWithSession:(ExteriaSession *)session directory:(NSString *)directory;

/* the decoded picture when it is in memory, without any work */
- (UIImage *)cachedImageForFile:(ExteriaRemoteFile *)file maxSide:(CGFloat)maxSide;
/* a picture or the first frame of tgs/vp9, bounded by maxSide pixels; completion runs on main with nil on failure */
- (void)loadImageForFile:(ExteriaRemoteFile *)file maxSide:(CGFloat)maxSide completion:(void (^)(UIImage *image))completion;
/* the cover of a music track, bounded by maxSide pixels: the thumbnail Telegram stored with the track, else the picture in the ID3 tag at the head of the
   file, which costs one ranged request of 64 KiB (a second one, up to 1 MiB, when the tag is larger) and is kept on disk, an empty copy standing for a
   file that has none. nil on the main thread's completion for a track without a cover or when the network failed */
- (void)loadCoverForTrack:(ExteriaMedia *)track maxSide:(CGFloat)maxSide completion:(void (^)(UIImage *image))completion;
/* starts the fetch and decode of a picture a row below the fold will ask for, so it is in memory by then */
- (void)prepareImageForFile:(ExteriaRemoteFile *)file maxSide:(CGFloat)maxSide;
/* the raw bytes, for formats that are not pictures (a lottie sticker); the completion runs on the main thread */
- (void)loadDataForFile:(ExteriaRemoteFile *)file completion:(void (^)(NSData *data))completion;

/* a file too large for one part, such as a story video */
- (NSUInteger)loadPathForFile:(ExteriaRemoteFile *)file size:(long long)size progress:(void (^)(float fraction))progress
             completion:(void (^)(NSString *path))completion;
/* the path of a file that is on the disk whole already, nil when it is not; the answer a screen needs to pick its
   button (the arrow of a file that has to come, or the triangle of one that is here) without starting a fetch */
- (NSString *)cachedPathForFile:(ExteriaRemoteFile *)file size:(long long)size;
/* drops one request's interest: the parts stop when no other request waits, and its completion never runs */
- (void)cancelPathRequest:(NSUInteger)request;
/* remembers which message of which chat each file of these messages came from */
- (void)noteMessages:(NSArray *)messages ofDialog:(ExteriaDialog *)dialog;
/* an explicit retry may bypass the automatic failure cooldown for this file */
- (void)retryFile:(ExteriaRemoteFile *)file;

/* removes the files nobody has touched for that many days; on the work queue, so a long cache does not hold the
   screen */
- (void)removeFilesOlderThanDays:(NSInteger)days;
- (unsigned long long)diskBytes;
- (void)clear;

@end
