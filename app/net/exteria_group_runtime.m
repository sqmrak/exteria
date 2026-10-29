#import "exteria_group_runtime.h"

#import <mach/mach_time.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#import "exteria_audio_session.h"
#import "exteria_group_audio.h"
#import "exteria_shiro.h"
#import "exteria_shiro_network.h"

#include "exteria_bytes.h"
#include "exteria_udp.h"

#define TICK_MS 20
#define RECEIVE_BUFFER 2048
#define AUDIO_FRAME_SAMPLES 960
#define DIAGNOSTIC_INTERVAL_MS 3000
#define DIAGNOSTIC_LIMIT_MS 45000
#define ENDPOINTS_MAX EXTERIA_TGC_GROUP_CANDIDATES_MAX

typedef struct {
    int fd;
    dispatch_source_t source;
    /* a socket of the tunnel speaks frames and is not connected, so it remembers the endpoint it stands for */
    BOOL tunneled;
    uint32_t ip;
    uint16_t port;
} ExteriaGroupSocket;

static uint64_t ExteriaGroupNowMs(void) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return mach_absolute_time() * base.numer / base.denom / 1000000ull;
}

@interface ExteriaGroupRuntime () {
@public
    exteria_tgc_group *_group;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    ExteriaGroupSocket _sockets[ENDPOINTS_MAX];
    size_t _socketCount;
    id<ExteriaGroupRuntimeDelegate> _delegate;
    ExteriaGroupAudio *_audio;
    NSData *_joinParams;
    uint32_t _ssrc;
    BOOL _stopped, _applied, _muted, _audioSessionHeld;
    uint64_t _startedAt, _lastDiagnostic;
    unsigned _rxCount, _rxRefused, _txCount, _txFailed;
    int _txErrno;
    NSString *_diagnostics;
}
- (void)tick;
- (void)receiveOn:(size_t)index;
- (void)stateChanged:(exteria_tgc_group_state)state;
@end

static void ExteriaGroupTrace(void *context, const char *line) {
    NSLog(@"exteria: group %s", line);
    (void)context;
}

static void ExteriaGroupSend(void *context, unsigned index, const uint8_t *data, size_t len) {
    ExteriaGroupRuntime *runtime = (ExteriaGroupRuntime *)context;
    ssize_t sent;
    if (index >= runtime->_socketCount || runtime->_sockets[index].fd < 0) return;
    /* a datagram the socket will not take now is lost, which the path does to datagrams as well; the protocols above resend what matters */
    if (runtime->_sockets[index].tunneled) {
        uint8_t frame[EXTERIA_UDP_FRAME_HEADER + EXTERIA_UDP_MAX_PAYLOAD];
        size_t frame_len = 0;
        if (exteria_udp_frame_encode(runtime->_sockets[index].ip, runtime->_sockets[index].port, data, len, frame, sizeof(frame), &frame_len) != EXTERIA_OK) return;
        sent = send(runtime->_sockets[index].fd, frame, frame_len, 0);
    } else {
        sent = send(runtime->_sockets[index].fd, data, len, 0);
    }
    if (sent < 0) {
        ++runtime->_txFailed;
        runtime->_txErrno = errno;
    } else {
        ++runtime->_txCount;
    }
}

static void ExteriaGroupState(void *context, exteria_tgc_group_state state) {
    ExteriaGroupRuntime *runtime = (ExteriaGroupRuntime *)context;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [runtime stateChanged:state];
    [pool drain];
}

static void ExteriaGroupAudioIn(void *context, uint32_t ssrc, const uint8_t *opus, size_t len, uint16_t sequence, uint32_t timestamp, int level, int voice) {
    ExteriaGroupRuntime *runtime = (ExteriaGroupRuntime *)context;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    (void)timestamp;
    (void)level;
    (void)voice;
    [runtime->_audio receivePacket:[NSData dataWithBytes:opus length:len] source:ssrc sequence:sequence];
    [pool drain];
}

@implementation ExteriaGroupRuntime

@synthesize ssrc = _ssrc;
@synthesize joinParams = _joinParams;

- (id)initWithDelegate:(id<ExteriaGroupRuntimeDelegate>)delegate {
    exteria_tgc_group_events events;
    char json[EXTERIA_GROUP_JOIN_PARAMS_MAX];
    size_t length = 0, i;
    self = [super init];
    if (!self) return nil;
    _delegate = delegate;
    memset(&events, 0, sizeof(events));
    events.context = self;
    events.send_datagram = ExteriaGroupSend;
    events.state = ExteriaGroupState;
    events.audio = ExteriaGroupAudioIn;
    events.trace = ExteriaGroupTrace;
    if (exteria_tgc_group_new(&_group, &events) != EXTERIA_OK || exteria_tgc_group_join_payload(_group, json, sizeof(json), &length) != EXTERIA_OK) {
        NSLog(@"exteria: the group call connection could not be made");
        [self release];
        return nil;
    }
    _ssrc = exteria_tgc_group_ssrc(_group);
    _joinParams = [[NSData alloc] initWithBytes:json length:length];
    _queue = dispatch_queue_create("exteria.group", DISPATCH_QUEUE_SERIAL);
    for (i = 0; i < ENDPOINTS_MAX; ++i) _sockets[i].fd = -1;
    return self;
}

- (void)dealloc {
    [self stop];
    if (_queue) dispatch_release(_queue);
    [_joinParams release];
    [_diagnostics release];
    [super dealloc];
}

- (BOOL)watchSocket:(size_t)index descriptor:(int)fd {
    _sockets[index].fd = fd;
    _sockets[index].source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _queue);
    dispatch_source_set_event_handler(_sockets[index].source, ^{ [self receiveOn:index]; });
    dispatch_resume(_sockets[index].source);
    return YES;
}

/* the socket of endpoint number index: connected UDP, or a datagram socket of the tunnel when the app's VPN is the route */
- (BOOL)openSocketFor:(size_t)index ip:(uint32_t)ip port:(uint16_t)port {
    struct sockaddr_in address;
    int fd, flags, on = 1;
    int route = ExteriaShiroNetworkRoute();
    /* a VPN that is wanted and not up carries nothing; neither it nor a direct path stands in for the other */
    if (route == (int)ExteriaShiroRouteBlocked) return NO;
    if (route == (int)ExteriaShiroRouteTunnel) {
        fd = -1;
        if (ExteriaShiroNetworkOpenDatagram(&fd) != EXTERIA_OK) return NO;
        _sockets[index].tunneled = YES;
        _sockets[index].ip = ip;
        _sockets[index].port = port;
        return [self watchSocket:index descriptor:fd];
    }
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(ip);
    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return NO;
    flags = fcntl(fd, F_GETFL, 0);
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 || connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        close(fd);
        return NO;
    }
    _sockets[index].tunneled = NO;
    return [self watchSocket:index descriptor:fd];
}

- (BOOL)applyTransport:(NSData *)json {
    exteria_tgc_group_transport transport;
    size_t i, opened = 0;
    __block BOOL ok = NO;
    if (_applied || _stopped) return NO;
    if (exteria_tgc_group_transport_parse(json.bytes, json.length, &transport) != EXTERIA_OK) {
        NSLog(@"exteria: the answer of the group call could not be read");
        return NO;
    }
    _startedAt = ExteriaGroupNowMs();
    if (exteria_tgc_group_apply(_group, &transport, _startedAt) != EXTERIA_OK) {
        NSLog(@"exteria: the answer of the group call was refused");
        return NO;
    }
    _applied = YES;
    for (i = 0; i < ENDPOINTS_MAX; ++i) {
        uint32_t ip = 0;
        uint16_t port = 0;
        if (exteria_tgc_group_endpoint(_group, (unsigned)i, &ip, &port) != EXTERIA_OK) break;
        _socketCount = i + 1;
        if ([self openSocketFor:i ip:ip port:port]) ++opened;
    }
    if (opened == 0) {
        NSLog(@"exteria: no socket of the group call could be opened");
        return NO;
    }
    dispatch_sync(_queue, ^{
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        dispatch_source_set_event_handler(_timer, ^{ [self tick]; });
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)TICK_MS * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
        dispatch_resume(_timer);
        ok = YES;
    });
    return ok;
}

- (void)receiveOn:(size_t)index {
    uint8_t buffer[RECEIVE_BUFFER];
    int guard;
    if (_stopped || index >= _socketCount) return;
    for (guard = 0; guard < 64; ++guard) {
        ssize_t n = recv(_sockets[index].fd, buffer, sizeof(buffer), 0);
        const uint8_t *payload = buffer;
        size_t payload_len = (size_t)n;
        if (n <= 0) break;
        ++_rxCount;
        if (_sockets[index].tunneled) {
            uint32_t ip = 0;
            uint16_t port = 0;
            /* a socket of the tunnel hears every peer; the call talks to one endpoint, and a datagram from anyone else is not for it */
            if (exteria_udp_frame_decode(buffer, (size_t)n, &ip, &port, &payload, &payload_len) != EXTERIA_OK) continue;
            if (ip != _sockets[index].ip || port != _sockets[index].port) {
                ++_rxRefused;
                continue;
            }
        }
        exteria_tgc_group_datagram(_group, (unsigned)index, payload, payload_len, ExteriaGroupNowMs());
    }
}

- (void)tick {
    uint64_t now = ExteriaGroupNowMs();
    if (_stopped) return;
    exteria_tgc_group_tick(_group, now);
    if (now - _lastDiagnostic >= DIAGNOSTIC_INTERVAL_MS) {
        int ice = 0, dtls = 0;
        unsigned in = 0, out = 0;
        _lastDiagnostic = now;
        exteria_tgc_group_diagnostics(_group, &ice, &dtls, &in, &out);
        NSString *line = [NSString stringWithFormat:@"ice %d dtls %d, audio in %u out %u, %llus, sockets rx %u refused %u tx %u failed %u (errno %d)",
                          ice, dtls, in, out, (unsigned long long)((now - _startedAt) / 1000), _rxCount, _rxRefused, _txCount, _txFailed, _txErrno];
        @synchronized (self) {
            [_diagnostics release];
            _diagnostics = [line copy];
        }
        if (now - _startedAt < DIAGNOSTIC_LIMIT_MS) NSLog(@"exteria: group %@", line);
    }
}

- (NSString *)diagnostics {
    @synchronized (self) {
        return [[_diagnostics retain] autorelease];
    }
}

/* the media path came up: the audio session, the microphone and the speaker start, and go on until the call ends */
- (void)stateChanged:(exteria_tgc_group_state)state {
    if (_stopped) return;
    if (state == EXTERIA_TGC_GROUP_CONNECTED && !_audio) {
        ExteriaGroupRuntime *runtime = self;
        _audioSessionHeld = ExteriaAudioSessionBeginCall();
        _audio = [[ExteriaGroupAudio alloc] initWithFrameHandler:^(NSData *frame, int level, BOOL voice) {
            /* the audio queue is not the connection's: the frame goes over to it */
            NSData *copy = [frame retain];
            dispatch_async(runtime->_queue, ^{
                if (!runtime->_stopped) exteria_tgc_group_send_audio(runtime->_group, copy.bytes, copy.length, AUDIO_FRAME_SAMPLES, level, voice ? 1 : 0);
                [copy release];
            });
        }];
        _audio.muted = _muted;
        _audio.speakingHandler = ^(NSArray *sources, BOOL selfSpeaking) {
            if (!runtime->_stopped) [runtime->_delegate groupRuntime:runtime speaking:sources selfSpeaking:selfSpeaking];
        };
        if (![_audio start]) NSLog(@"exteria: the group call is up but the audio could not start");
    }
    [_delegate groupRuntime:self didChangeState:state];
}

- (void)setMuted:(BOOL)muted {
    dispatch_async(_queue, ^{
        if (_stopped) return;
        _muted = muted;
        _audio.muted = muted;
    });
}

- (void)setVolume:(float)gain forSource:(uint32_t)source {
    dispatch_async(_queue, ^{
        if (_stopped) return;
        [_audio setGain:gain forSource:source];
    });
}

- (void)forgetSource:(uint32_t)source {
    dispatch_async(_queue, ^{
        if (_stopped) return;
        exteria_tgc_group_forget(_group, source);
        [_audio forgetSource:source];
    });
}

- (void)stop {
    size_t i;
    if (!_queue) return;
    dispatch_sync(_queue, ^{
        _stopped = YES;
        _delegate = nil;
    });
    if (_timer) {
        dispatch_source_cancel(_timer);
        dispatch_release(_timer);
        _timer = NULL;
    }
    for (i = 0; i < _socketCount; ++i) {
        if (_sockets[i].source) {
            dispatch_source_cancel(_sockets[i].source);
            dispatch_release(_sockets[i].source);
            _sockets[i].source = NULL;
        }
    }
    /* what the sources had queued runs out before the sockets close and the connection goes */
    dispatch_sync(_queue, ^{});
    for (i = 0; i < _socketCount; ++i) {
        if (_sockets[i].fd >= 0) {
            close(_sockets[i].fd);
            _sockets[i].fd = -1;
        }
    }
    _socketCount = 0;
    [_audio stop];
    [_audio release];
    _audio = nil;
    if (_audioSessionHeld) {
        ExteriaAudioSessionEndCall();
        _audioSessionHeld = NO;
    }
    exteria_tgc_group_free(_group);
    _group = NULL;
}

@end
