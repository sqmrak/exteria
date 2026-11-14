#import <Foundation/Foundation.h>

/* the words of a song. with stamps (synced) each line says when it begins, without them the text is only shown */
@interface ExteriaLyrics : NSObject
@property (nonatomic, readonly) NSArray *lines;     /* NSString */
@property (nonatomic, readonly) NSArray *starts;    /* NSNumber of milliseconds, parallel to lines; nil when not synced */
@property (nonatomic, readonly) BOOL synced;
/* the line that is being sung at this second, -1 before the first line and always -1 for plain text */
- (NSInteger)activeLineAt:(NSTimeInterval)seconds;
/* the start of a line in seconds, for a tap that seeks */
- (NSTimeInterval)startOfLine:(NSInteger)index;
@end

/* one look-up of lyrics at LRCLIB (lrclib.net, open and keyless), by the performer and title tags with feat. credits and bracketed notes cut off. the exact match is tried
   first, then a search whose best hit must carry the title. the answer comes on the main thread: lyrics, or nil, with definitive NO when the failure was the network's
   (a later try may succeed). answers are kept for the run, nothing is written to disk. cancel (or releasing the request) stops it without a callback */
@interface ExteriaLyricsRequest : NSObject
+ (ExteriaLyricsRequest *)fetchForPerformer:(NSString *)performer title:(NSString *)title completion:(void (^)(ExteriaLyrics *lyrics, BOOL definitive))completion;
- (void)cancel;
@end
