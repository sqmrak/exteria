#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "exteria_call.h"
#include "exteria_tgc_call.h"

@class ExteriaCallVideo;
@class ExteriaTgcRuntime;

/* what the runtime tells the call engine; every method runs on the runtime's own queue, so the engine hops to its
   worker before touching its state */
@protocol ExteriaTgcRuntimeDelegate <NSObject>
/* sealed signaling bytes for the other phone */
- (void)tgcRuntime:(ExteriaTgcRuntime *)runtime sendSignaling:(NSData *)data;
- (void)tgcRuntime:(ExteriaTgcRuntime *)runtime didChangeState:(exteria_tgc_call_state)state;
/* the other phone's microphone and camera: muted, video state (0 off, 1 paused, 2 on) and the rotation of its picture */
- (void)tgcRuntime:(ExteriaTgcRuntime *)runtime remoteMuted:(BOOL)muted video:(int)videoState rotation:(int)rotation;
/* the agreed channels changed (video came or went) */
- (void)tgcRuntimeDidChangeStreams:(ExteriaTgcRuntime *)runtime;
@end

/* one call over tgcalls 7.0.0 as the app runs it: the sockets of the reflectors, the 20 ms clock, the microphone
   and the speaker, around the portable call of the core */
@interface ExteriaTgcRuntime : NSObject

/* endpoints are the connections of the call (only the UDP ones are used) and turns its TURN servers, through which
   the other phone is reached when its reflector is blocked; key is the 256 byte call key */
- (id)initWithConnections:(const exteria_call_connection *)connections count:(size_t)count turns:(const exteria_call_turn *)turns turnCount:(size_t)turnCount
                      key:(const uint8_t *)key outgoing:(BOOL)outgoing video:(BOOL)video delegate:(id<ExteriaTgcRuntimeDelegate>)delegate;

/* opens the sockets and starts the clock; NO when no socket could be opened */
- (BOOL)start;
/* stops everything and waits for the queue; the delegate hears nothing afterwards */
- (void)stop;

- (void)receiveSignaling:(NSData *)data;
- (void)setMuted:(BOOL)muted;

/* the camera of the call, any thread */
- (void)setCameraOn:(BOOL)on completion:(void (^)(BOOL ok))completion;
- (BOOL)cameraOn;
/* the camera and the pictures of the call for its screen; previewLayer is nil until the camera runs,
   remoteImageHandler gets each picture of the other side on the main thread, and the other camera and the turn of
   the screen go through the object */
@property (nonatomic, readonly) ExteriaCallVideo *video;
/* the diagnostics line for the log: path stages and the counters of the signaling */
- (NSString *)diagnostics;

@end
