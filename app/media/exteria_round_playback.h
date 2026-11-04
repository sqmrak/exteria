#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

/* a view whose layer plays a video, for a round message that plays in its own circle */
@interface ExteriaRoundVideoView : UIView
@end

/* posted on the main thread when a video message starts, pauses, resumes or ends */
extern NSString *const ExteriaRoundPlaybackDidChangeNotification;

@class ExteriaRoundPlayback;

/* the chat that started a video message: it knows the messages around it, which a floating circle left alone in another screen cannot walk */
@protocol ExteriaRoundChain <NSObject>
/* starts the message before (-1) or after (+1) the one with this file key, as a tap on it would; NO when there is none to start */
- (BOOL)roundPlayback:(ExteriaRoundPlayback *)playback stepFromKey:(NSString *)key direction:(NSInteger)direction;
/* the message with this file key played to its end */
- (void)roundPlayback:(ExteriaRoundPlayback *)playback didFinishKey:(NSString *)key;
@end

/* the one video message that plays on the device. the player lives here and not in the cell of the message, so the circle goes on
   when its row scrolls away or the chat is left: it then floats over the app until the person pauses it or sends it away */
@interface ExteriaRoundPlayback : NSObject

+ (ExteriaRoundPlayback *)sharedPlayback;

@property (nonatomic, readonly) AVPlayer *player;
/* the file key of the message that plays, nil while none does */
@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly) BOOL playing;
/* the cell that draws the circle inside its row; while there is none, the circle floats */
@property (nonatomic, assign) id host;

- (BOOL)isActiveKey:(NSString *)key;
- (NSTimeInterval)duration;
- (CGFloat)progress;

/* NO when the audio session or the file did not let it start; a video message that plays is replaced */
- (BOOL)beginWithURL:(NSURL *)url key:(NSString *)key chain:(id<ExteriaRoundChain>)chain;
- (void)togglePause;
- (void)seekToFraction:(CGFloat)fraction;
- (void)step:(NSInteger)direction;
- (void)stop;
/* a chat that goes away takes its hand off the chain; what plays goes on, and ends when it ends */
- (void)forgetChain:(id)chain;
/* the cell that was the host lets go of the circle */
- (void)releaseHost:(id)host;

@end
