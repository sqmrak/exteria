#import <Foundation/Foundation.h>

#include "exteria_group_call.h"
#include "exteria_tgc_group.h"

@class ExteriaGroupRuntime;

/* what the runtime tells the engine; every method runs on the runtime's own queue, so the engine hops to its worker before touching its state */
@protocol ExteriaGroupRuntimeDelegate <NSObject>
- (void)groupRuntime:(ExteriaGroupRuntime *)runtime didChangeState:(exteria_tgc_group_state)state;
/* the sources heard in the last moments, and whether this phone's own microphone carried speech */
- (void)groupRuntime:(ExteriaGroupRuntime *)runtime speaking:(NSArray *)sources selfSpeaking:(BOOL)selfSpeaking;
@end

/* the media of one group call as the app runs it: the sockets of the server's endpoints, the 20 ms clock, the microphone and the speaker, around the portable
   connection of the core */
@interface ExteriaGroupRuntime : NSObject

/* nil when the connection could not be made (no certificate) */
- (id)initWithDelegate:(id<ExteriaGroupRuntimeDelegate>)delegate;

/* the ssrc this phone sends its audio with, and the JSON of the params of phone.joinGroupCall */
@property (nonatomic, readonly) uint32_t ssrc;
@property (nonatomic, readonly, copy) NSData *joinParams;

/* the JSON of the server's answer (updateGroupCallConnection): opens a socket for each endpoint and starts the clock. NO when the answer is not usable or no
   socket could be opened */
- (BOOL)applyTransport:(NSData *)json;
/* stops everything and waits for the queue; the delegate hears nothing afterwards */
- (void)stop;

- (void)setMuted:(BOOL)muted;
/* a member left the call: its decoder, buffer and SRTP state go. any thread */
- (void)forgetSource:(uint32_t)source;
/* the volume a member is heard at, as a factor; any thread */
- (void)setVolume:(float)gain forSource:(uint32_t)source;
/* the diagnostics line for the log: path stages and packet counts */
- (NSString *)diagnostics;

@end
