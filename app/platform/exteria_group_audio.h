#import <Foundation/Foundation.h>

/* the microphone and the speaker of a group call: one encoder for this phone and a decoder with a jitter buffer for each source that speaks, mixed into one
   stream for the speaker */
@interface ExteriaGroupAudio : NSObject

/* frameHandler runs on a queue of its own for each encoded 20 ms frame while the microphone is not muted; level is the level of the frame in -dBov (0 loud,
   127 silent) and voice says it holds speech. it must not block */
- (id)initWithFrameHandler:(void (^)(NSData *frame, int level, BOOL voice))frameHandler;

/* called about five times a second on the codec queue with the ssrcs heard in the last moments, and whether this phone's own microphone carried speech */
@property (nonatomic, copy) void (^speakingHandler)(NSArray *sources, BOOL selfSpeaking);

/* NO when the system will not give the unit or a codec cannot be made; the reason is logged */
- (BOOL)start;
/* stops the unit and waits for the codec queue; safe to call twice */
- (void)stop;

/* an Opus packet of a source with the sequence number of its RTP header; any thread */
- (void)receivePacket:(NSData *)packet source:(uint32_t)source sequence:(uint16_t)sequence;
/* a source that left the call: its decoder and buffer go */
- (void)forgetSource:(uint32_t)source;

/* the volume of one source as a factor, 1 for the default and up to 2; it holds when the source is dropped and comes back */
- (void)setGain:(float)gain forSource:(uint32_t)source;

/* while muted nothing is encoded or handed on */
@property (nonatomic, assign) BOOL muted;

@end
