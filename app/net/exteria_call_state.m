#import "exteria_call_state.h"

@implementation ExteriaCall

@synthesize callId = _callId;
@synthesize peerId = _peerId;
@synthesize peerName = _peerName;
@synthesize outgoing = _outgoing;
@synthesize phase = _phase;
@synthesize end = _end;
@synthesize emoji = _emoji;
@synthesize startedAt = _startedAt;
@synthesize muted = _muted;
@synthesize bars = _bars;
@synthesize photo = _photo;
@synthesize video = _video;
@synthesize cameraOn = _cameraOn;
@synthesize remoteVideo = _remoteVideo;
@synthesize remoteMuted = _remoteMuted;

- (id)initWithCallId:(long long)callId peerId:(long long)peerId peerName:(NSString *)peerName outgoing:(BOOL)outgoing phase:(ExteriaCallPhase)phase
                 end:(ExteriaCallEnd)end emoji:(NSArray *)emoji startedAt:(NSTimeInterval)startedAt muted:(BOOL)muted bars:(int)bars {
    self = [super init];
    if (!self) return nil;
    _callId = callId;
    _peerId = peerId;
    _peerName = [(peerName ? peerName : @"") copy];
    _outgoing = outgoing;
    _phase = phase;
    _end = end;
    _emoji = [(emoji ? emoji : [NSArray array]) retain];
    _startedAt = startedAt;
    _muted = muted;
    _bars = bars;
    return self;
}

- (void)dealloc {
    [_peerName release];
    [_emoji release];
    [_photo release];
    [super dealloc];
}

@end
