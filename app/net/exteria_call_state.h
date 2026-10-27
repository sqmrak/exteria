#import <Foundation/Foundation.h>

#import "exteria_photo.h"

/* where a one-to-one voice call stands, as the call screen words it */
typedef enum {
    ExteriaCallPhaseRequesting,     /* ours: the key parameters and the request are on their way */
    ExteriaCallPhaseCalling,        /* ours: the request is in, the callee's phone has not rung yet */
    ExteriaCallPhaseRinging,        /* ours: the callee's phone rings */
    ExteriaCallPhaseIncoming,       /* theirs: our phone rings */
    ExteriaCallPhaseExchanging,     /* the two sides make the key */
    ExteriaCallPhaseConnecting,     /* the key is made and the audio connects */
    ExteriaCallPhaseActive,         /* talking */
    ExteriaCallPhaseReconnecting,   /* the link broke while talking */
    ExteriaCallPhaseEnded
} ExteriaCallPhase;

/* why a call ended, for the screen and the notice that follows it */
typedef enum {
    ExteriaCallEndNone,
    ExteriaCallEndHangup,           /* one side hung up after the call began */
    ExteriaCallEndDeclined,         /* the callee turned it down */
    ExteriaCallEndBusy,
    ExteriaCallEndMissed,           /* nobody answered in time */
    ExteriaCallEndFailed,           /* the call could not be set up or the link was lost */
    ExteriaCallEndOutdated,         /* the other app is too old for calls with this one */
    ExteriaCallEndPrivacy           /* the person does not take calls from us */
} ExteriaCallEnd;

/* one call as the screens see it; the engine builds a new snapshot at every change; screens never change it */
@interface ExteriaCall : NSObject {
    long long _callId;
    long long _peerId;
    NSString *_peerName;
    BOOL _outgoing;
    ExteriaCallPhase _phase;
    ExteriaCallEnd _end;
    NSArray *_emoji;
    NSTimeInterval _startedAt;
    BOOL _muted;
    int _bars;
    ExteriaPhoto *_photo;
    BOOL _video;
    BOOL _cameraOn;
    BOOL _remoteVideo;
    BOOL _remoteMuted;
}
@property (nonatomic, readonly) long long callId;
/* the user on the other end */
@property (nonatomic, readonly) long long peerId;
@property (nonatomic, readonly, copy) NSString *peerName;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) ExteriaCallPhase phase;
@property (nonatomic, readonly) ExteriaCallEnd end;
/* the four emoji both people read aloud to check the key, empty before the key exists */
@property (nonatomic, readonly, retain) NSArray *emoji;
/* when the audio connected, on the clock of the device; zero before */
@property (nonatomic, readonly) NSTimeInterval startedAt;
@property (nonatomic, readonly) BOOL muted;
/* signal bars from 1 to 4 */
@property (nonatomic, readonly) int bars;
/* the other person's picture when the app knows it, else nil */
@property (nonatomic, retain) ExteriaPhoto *photo;
/* the call was asked for with video; the camera of this phone runs; the other phone sends its picture; the other microphone is muted */
@property (nonatomic, assign) BOOL video;
@property (nonatomic, assign) BOOL cameraOn;
@property (nonatomic, assign) BOOL remoteVideo;
@property (nonatomic, assign) BOOL remoteMuted;

- (id)initWithCallId:(long long)callId peerId:(long long)peerId peerName:(NSString *)peerName outgoing:(BOOL)outgoing phase:(ExteriaCallPhase)phase
                 end:(ExteriaCallEnd)end emoji:(NSArray *)emoji startedAt:(NSTimeInterval)startedAt muted:(BOOL)muted bars:(int)bars;
@end
