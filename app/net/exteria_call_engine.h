#import <Foundation/Foundation.h>

#import "exteria_call_state.h"
#import "exteria_dialog.h"

#include "exteria_call.h"

@class ExteriaCallVideo;
@class ExteriaSession;

/* the one active call of a session: the signaling over the session's link, the key */
@interface ExteriaCallEngine : NSObject

- (id)initWithSession:(ExteriaSession *)session;

/* a call to the user of a chat; a call already running makes this one end at once as failed */
- (void)startCallToDialog:(ExteriaDialog *)dialog;
/* the same, as a video call when video is YES */
- (void)startCallToDialog:(ExteriaDialog *)dialog video:(BOOL)video;
/* answers the call that rings, or turns it down */
- (void)acceptIncoming;
- (void)declineIncoming;
/* ends whichever call runs, at any stage */
- (void)hangUp;
- (void)setMuted:(BOOL)muted;
/* the camera of the call that runs, on or off */
- (void)setCameraOn:(BOOL)on;
/* main thread: the camera and the pictures of the call that runs, nil between calls */
- (ExteriaCallVideo *)activeVideo;

/* worker only: a PhoneCall the link delivered, from a push or from the answer to one of our requests; the value is valid for this call only */
- (void)handlePhoneCall:(const exteria_phone_call *)call;
/* worker only: the signaling bytes of the other phone for the call with this id, from an updatePhoneCallSignalingData; early ones wait for the media to start */
- (void)handleSignalingData:(NSData *)data callId:(int64_t)callId;
/* worker only: the session is going down, so the call goes with it */
- (void)shutdown;

@end
