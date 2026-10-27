#import <Foundation/Foundation.h>

/* records the microphone and hands back an Ogg Opus file with the waveform bars a voice note carries */
@interface ExteriaVoiceRecorder : NSObject

/* NO when the microphone cannot be used, such as during a phone call */
- (BOOL)start;
/* how long the recording has run */
@property (nonatomic, readonly) NSTimeInterval elapsed;
/* the loudness right now, from zero to one */
@property (nonatomic, readonly) float level;
/* stops and encodes off the main thread; the completion runs on the main thread; the path is nil when the
   recording was too short to send or could not be encoded */
- (void)finishWithCompletion:(void (^)(NSString *path, int32_t durationMs, NSData *waveform))completion;
/* stops and throws the recording away */
- (void)cancel;

@end
