#import "exteria_call_audio.h"

#import <AudioToolbox/AudioToolbox.h>

#include <opus.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_jitter.h"
#include "exteria_pcm_ring.h"

#define SAMPLE_RATE 48000
#define FRAME_SAMPLES 960
#define TICK_MS 10
/* the speaker ring is topped up to this many samples (60 ms), which the jitter buffer then has to refill from */
#define PLAYBACK_TARGET (FRAME_SAMPLES * 3)
#define JITTER_TARGET 3
#define MAX_ENCODED 1275
#define MAX_DECODED 5760
#define ENCODER_BITRATE 24000
#define ENCODER_COMPLEXITY 4
#define ENCODER_LOSS_PERCENT 10
#define MAX_RENDER_FRAMES 2048

@interface ExteriaCallAudio () {
@public
    AudioUnit _unit;
    OpusEncoder *_encoder;
    OpusDecoder *_decoder;
    exteria_pcm_ring *_capture;
    exteria_pcm_ring *_playback;
    exteria_jitter *_jitter;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    void (^_frameHandler)(NSData *);
    volatile int32_t _running;
    volatile int32_t _muted;
}
- (void)pump;
@end

/* the system's audio thread: it takes the microphone samples into the capture ring and fills the speaker from the playback ring, and touches nothing else */
static OSStatus ExteriaCallInput(void *refcon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *stamp, UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    ExteriaCallAudio *audio = (ExteriaCallAudio *)refcon;
    int16_t samples[MAX_RENDER_FRAMES];
    AudioBufferList list;
    OSStatus status;
    (void)unused;
    if (frames > MAX_RENDER_FRAMES) return kAudio_ParamError;
    list.mNumberBuffers = 1;
    list.mBuffers[0].mNumberChannels = 1;
    list.mBuffers[0].mDataByteSize = frames * sizeof(int16_t);
    list.mBuffers[0].mData = samples;
    status = AudioUnitRender(audio->_unit, flags, stamp, 1, frames, &list);
    if (status == noErr && audio->_capture) exteria_pcm_ring_write(audio->_capture, samples, frames);
    (void)bus;
    return status;
}

static OSStatus ExteriaCallOutput(void *refcon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *stamp, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    ExteriaCallAudio *audio = (ExteriaCallAudio *)refcon;
    UInt32 i;
    (void)flags;
    (void)stamp;
    (void)bus;
    for (i = 0; i < data->mNumberBuffers; ++i) {
        AudioBuffer *buffer = &data->mBuffers[i];
        UInt32 room = buffer->mDataByteSize / sizeof(int16_t);
        UInt32 want = frames < room ? frames : room;
        int16_t *out = (int16_t *)buffer->mData;
        size_t got = audio->_playback ? exteria_pcm_ring_read(audio->_playback, out, want) : 0;
        if (got < want) memset(out + got, 0, (want - got) * sizeof(int16_t));
    }
    return noErr;
}

@implementation ExteriaCallAudio

@dynamic muted;

- (id)initWithFrameHandler:(void (^)(NSData *))frameHandler {
    self = [super init];
    if (!self) return nil;
    _frameHandler = [frameHandler copy];
    _queue = dispatch_queue_create("exteria.call.audio", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)dealloc {
    [self stop];
    if (_queue) dispatch_release(_queue);
    [_frameHandler release];
    [super dealloc];
}

- (BOOL)muted { return _muted != 0; }
- (void)setMuted:(BOOL)muted { _muted = muted ? 1 : 0; }

- (BOOL)start {
    int opusError = OPUS_OK;
    AudioComponentDescription description;
    AudioComponent component;
    AudioStreamBasicDescription format;
    UInt32 enabled = 1;
    AURenderCallbackStruct input, output;
    if (_running) return YES;
    _capture = (exteria_pcm_ring *)calloc(1, sizeof(*_capture));
    _playback = (exteria_pcm_ring *)calloc(1, sizeof(*_playback));
    _jitter = (exteria_jitter *)calloc(1, sizeof(*_jitter));
    if (!_capture || !_playback || !_jitter || exteria_jitter_init(_jitter, JITTER_TARGET) != EXTERIA_OK) goto failure;
    _encoder = opus_encoder_create(SAMPLE_RATE, 1, OPUS_APPLICATION_VOIP, &opusError);
    if (!_encoder || opusError != OPUS_OK) goto failure;
    opus_encoder_ctl(_encoder, OPUS_SET_BITRATE(ENCODER_BITRATE));
    opus_encoder_ctl(_encoder, OPUS_SET_COMPLEXITY(ENCODER_COMPLEXITY));
    opus_encoder_ctl(_encoder, OPUS_SET_INBAND_FEC(1));
    opus_encoder_ctl(_encoder, OPUS_SET_PACKET_LOSS_PERC(ENCODER_LOSS_PERCENT));
    _decoder = opus_decoder_create(SAMPLE_RATE, 1, &opusError);
    if (!_decoder || opusError != OPUS_OK) goto failure;

    memset(&description, 0, sizeof(description));
    description.componentType = kAudioUnitType_Output;
    description.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    description.componentManufacturer = kAudioUnitManufacturer_Apple;
    component = AudioComponentFindNext(NULL, &description);
    if (!component || AudioComponentInstanceNew(component, &_unit) != noErr) goto failure;
    if (AudioUnitSetProperty(_unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, sizeof(enabled)) != noErr) goto failure;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = SAMPLE_RATE;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mFramesPerPacket = 1;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;
    format.mBytesPerFrame = 2;
    format.mBytesPerPacket = 2;
    if (AudioUnitSetProperty(_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format)) != noErr ||
        AudioUnitSetProperty(_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)) != noErr) goto failure;
    input.inputProc = ExteriaCallInput;
    input.inputProcRefCon = self;
    output.inputProc = ExteriaCallOutput;
    output.inputProcRefCon = self;
    if (AudioUnitSetProperty(_unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &input, sizeof(input)) != noErr ||
        AudioUnitSetProperty(_unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &output, sizeof(output)) != noErr ||
        AudioUnitInitialize(_unit) != noErr) goto failure;

    _running = 1;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_event_handler(_timer, ^{ [self pump]; });
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)TICK_MS * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);
    dispatch_resume(_timer);
    if (AudioOutputUnitStart(_unit) != noErr) {
        _running = 0;
        goto failure;
    }
    return YES;
failure:
    NSLog(@"exteria: the call audio could not start (opus %d)", opusError);
    [self stop];
    return NO;
}

- (void)stop {
    dispatch_source_t timer = _timer;
    _running = 0;
    _timer = NULL;
    if (timer) {
        dispatch_source_cancel(timer);
        dispatch_release(timer);
    }
    if (_unit) {
        AudioOutputUnitStop(_unit);
        AudioUnitUninitialize(_unit);
        AudioComponentInstanceDispose(_unit);
        _unit = NULL;
    }
    /* whatever the codec queue still holds finishes before the codecs go */
    if (_queue) dispatch_sync(_queue, ^{});
    if (_encoder) {
        opus_encoder_destroy(_encoder);
        _encoder = NULL;
    }
    if (_decoder) {
        opus_decoder_destroy(_decoder);
        _decoder = NULL;
    }
    free(_capture);
    free(_playback);
    free(_jitter);
    _capture = NULL;
    _playback = NULL;
    _jitter = NULL;
}

- (void)receivePacket:(NSData *)packet sequence:(uint16_t)sequence {
    NSData *copy;
    if (!_running || packet.length == 0 || packet.length > EXTERIA_JITTER_MAX_PACKET) return;
    copy = [packet copy];
    dispatch_async(_queue, ^{
        if (_running && _jitter) exteria_jitter_put(_jitter, sequence, copy.bytes, copy.length);
        [copy release];
    });
}

/* every 10 ms on the codec queue: what the microphone gave becomes encoded frames, and the speaker's ring is topped up from the jitter buffer */
- (void)pump {
    int16_t pcm[FRAME_SAMPLES];
    uint8_t encoded[MAX_ENCODED];
    int16_t decoded[MAX_DECODED];
    uint8_t packet[EXTERIA_JITTER_MAX_PACKET];
    int guard;
    if (!_running || !_capture || !_playback || !_jitter || !_encoder || !_decoder) return;
    while (exteria_pcm_ring_fill(_capture) >= FRAME_SAMPLES) {
        int length;
        exteria_pcm_ring_read(_capture, pcm, FRAME_SAMPLES);
        if (_muted) continue;
        length = opus_encode(_encoder, pcm, FRAME_SAMPLES, encoded, sizeof(encoded));
        if (length > 0 && _frameHandler) _frameHandler([NSData dataWithBytes:encoded length:(NSUInteger)length]);
    }
    for (guard = 0; guard < 8 && exteria_pcm_ring_fill(_playback) < PLAYBACK_TARGET; ++guard) {
        size_t length = 0;
        int count = 0;
        exteria_jitter_kind kind = exteria_jitter_get(_jitter, packet, sizeof(packet), &length);
        if (kind == EXTERIA_JITTER_EMPTY) break;
        if (kind == EXTERIA_JITTER_FRAME) count = opus_decode(_decoder, packet, (opus_int32)length, decoded, MAX_DECODED, 0);
        else count = opus_decode(_decoder, NULL, 0, decoded, FRAME_SAMPLES, 0);
        if (count > 0) exteria_pcm_ring_write(_playback, decoded, (size_t)count);
    }
}

@end
