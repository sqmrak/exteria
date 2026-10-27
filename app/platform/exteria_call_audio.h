#import <Foundation/Foundation.h>

/* the microphone and the speaker of a call */
@interface ExteriaCallAudio : NSObject

/* frameHandler runs on a queue of its own for each encoded frame while the microphone is not muted; it must not block */
- (id)initWithFrameHandler:(void (^)(NSData *frame))frameHandler;

/* NO when the system will not give the unit or the codec cannot be made; the reason is logged */
- (BOOL)start;
/* stops the unit and waits for the codec queue; safe to call twice */
- (void)stop;

/* an Opus packet of the other side with the sequence number of its RTP header; any thread */
- (void)receivePacket:(NSData *)packet sequence:(uint16_t)sequence;

/* while muted nothing is encoded or handed on */
@property (nonatomic, assign) BOOL muted;

@end
