#import "exteria_group_audio.h"

#import <AudioToolbox/AudioToolbox.h>

#include <math.h>
#include <opus.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_jitter.h"
#include "exteria_pcm_ring.h"

#define SAMPLE_RATE 48000
#define FRAME_SAMPLES 960
#define MIX_SAMPLES 480
#define TICK_MS 10
/* the speaker ring is topped up to this many samples (60 ms) */
#define PLAYBACK_TARGET (FRAME_SAMPLES * 3)
#define JITTER_TARGET 3
#define MAX_ENCODED 1275
#define MAX_DECODED 5760
#define ENCODER_BITRATE 24000
#define ENCODER_COMPLEXITY 4
#define ENCODER_LOSS_PERCENT 10
#define MAX_RENDER_FRAMES 2048
/* a phone mixes only so many speakers: old cores decode each one, so the number is bounded and a source that has been silent for a while gives its place up */
#define SOURCES_MAX 10
#define SOURCE_IDLE_SECONDS 5
/* speech: a frame louder than this many -dBov, held for 300 ms so a pause between words does not flicker the ring */
#define VOICE_LEVEL_LIMIT 55
#define VOICE_HOLD_FRAMES 15
#define SPEAKING_REPORT_TICKS 20
#define SPEAKING_RMS 400.0f

typedef struct group_source {
    uint32_t ssrc;
    OpusDecoder *decoder;
    exteria_jitter *jitter;
    exteria_pcm_ring *ring;
    int last_frame_samples;
    CFAbsoluteTime last_packet;
    float energy;
    float gain;
} group_source;

/* the volume a person set for a member outlives the decoder of its source, which is dropped after a silence and made again at the next packet */
#define GAINS_MAX 64
typedef struct group_gain {
    uint32_t ssrc;
    float gain;
} group_gain;

@interface ExteriaGroupAudio () {
@public
    AudioUnit _unit;
    OpusEncoder *_encoder;
    exteria_pcm_ring *_capture;
    exteria_pcm_ring *_playback;
    group_source _sources[SOURCES_MAX];
    group_gain _gains[GAINS_MAX];
    unsigned _gainCount;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    void (^_frameHandler)(NSData *, int, BOOL);
    void (^_speakingHandler)(NSArray *, BOOL);
    volatile int32_t _running;
    volatile int32_t _muted;
    int _voiceHold;
    unsigned _ticks;
}
- (void)pump;
@end

static OSStatus ExteriaGroupInput(void *refcon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *stamp, UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    ExteriaGroupAudio *audio = (ExteriaGroupAudio *)refcon;
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

static OSStatus ExteriaGroupOutput(void *refcon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *stamp, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    ExteriaGroupAudio *audio = (ExteriaGroupAudio *)refcon;
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

static void ExteriaGroupSourceFree(group_source *source) {
    if (source->decoder) opus_decoder_destroy(source->decoder);
    free(source->jitter);
    free(source->ring);
    memset(source, 0, sizeof(*source));
}

static float ExteriaGroupGainOf(const ExteriaGroupAudio *audio, uint32_t ssrc) {
    unsigned i;
    for (i = 0; i < audio->_gainCount; ++i) {
        if (audio->_gains[i].ssrc == ssrc) return audio->_gains[i].gain;
    }
    return 1.0f;
}

/* the slot of this ssrc, a free one, or the one that has been silent longest past SOURCE_IDLE_SECONDS; NULL when every speaker is current */
static group_source *ExteriaGroupSourceFor(ExteriaGroupAudio *audio, uint32_t ssrc, CFAbsoluteTime now) {
    group_source *free_slot = NULL, *stale = NULL;
    int i;
    for (i = 0; i < SOURCES_MAX; ++i) {
        group_source *s = &audio->_sources[i];
        if (s->decoder && s->ssrc == ssrc) return s;
        if (!s->decoder && !free_slot) free_slot = s;
        if (s->decoder && now - s->last_packet > SOURCE_IDLE_SECONDS && (!stale || s->last_packet < stale->last_packet)) stale = s;
    }
    if (!free_slot && stale) {
        ExteriaGroupSourceFree(stale);
        free_slot = stale;
    }
    if (!free_slot) return NULL;
    {
        int error = OPUS_OK;
        free_slot->decoder = opus_decoder_create(SAMPLE_RATE, 1, &error);
        free_slot->jitter = (exteria_jitter *)calloc(1, sizeof(exteria_jitter));
        free_slot->ring = (exteria_pcm_ring *)calloc(1, sizeof(exteria_pcm_ring));
        if (!free_slot->decoder || error != OPUS_OK || !free_slot->jitter || !free_slot->ring || exteria_jitter_init(free_slot->jitter, JITTER_TARGET) != EXTERIA_OK) {
            ExteriaGroupSourceFree(free_slot);
            return NULL;
        }
        free_slot->ssrc = ssrc;
        free_slot->last_frame_samples = FRAME_SAMPLES;
        free_slot->last_packet = now;
        free_slot->gain = ExteriaGroupGainOf(audio, ssrc);
    }
    return free_slot;
}

/* the level of a frame in -dBov, 0 for full scale and 127 for silence */
static int ExteriaGroupLevel(const int16_t *pcm, size_t count) {
    double sum = 0;
    size_t i;
    double rms, db;
    for (i = 0; i < count; ++i) sum += (double)pcm[i] * (double)pcm[i];
    rms = sqrt(sum / (double)count);
    if (rms < 1.0) return 127;
    db = -20.0 * log10(rms / 32768.0);
    return db < 0 ? 0 : (db > 127 ? 127 : (int)db);
}

@implementation ExteriaGroupAudio

@dynamic muted;
@synthesize speakingHandler = _speakingHandler;

- (id)initWithFrameHandler:(void (^)(NSData *, int, BOOL))frameHandler {
    self = [super init];
    if (!self) return nil;
    _frameHandler = [frameHandler copy];
    _queue = dispatch_queue_create("exteria.group.audio", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)dealloc {
    [self stop];
    if (_queue) dispatch_release(_queue);
    [_frameHandler release];
    [_speakingHandler release];
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
    if (!_capture || !_playback) goto failure;
    _encoder = opus_encoder_create(SAMPLE_RATE, 1, OPUS_APPLICATION_VOIP, &opusError);
    if (!_encoder || opusError != OPUS_OK) goto failure;
    opus_encoder_ctl(_encoder, OPUS_SET_BITRATE(ENCODER_BITRATE));
    opus_encoder_ctl(_encoder, OPUS_SET_COMPLEXITY(ENCODER_COMPLEXITY));
    opus_encoder_ctl(_encoder, OPUS_SET_INBAND_FEC(1));
    opus_encoder_ctl(_encoder, OPUS_SET_PACKET_LOSS_PERC(ENCODER_LOSS_PERCENT));

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
    input.inputProc = ExteriaGroupInput;
    input.inputProcRefCon = self;
    output.inputProc = ExteriaGroupOutput;
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
    NSLog(@"exteria: the group call audio could not start (opus %d)", opusError);
    [self stop];
    return NO;
}

- (void)stop {
    dispatch_source_t timer = _timer;
    int i;
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
    for (i = 0; i < SOURCES_MAX; ++i) ExteriaGroupSourceFree(&_sources[i]);
    free(_capture);
    free(_playback);
    _capture = NULL;
    _playback = NULL;
}

- (void)receivePacket:(NSData *)packet source:(uint32_t)source sequence:(uint16_t)sequence {
    NSData *copy;
    if (!_running || packet.length == 0 || packet.length > EXTERIA_JITTER_MAX_PACKET) return;
    copy = [packet copy];
    dispatch_async(_queue, ^{
        if (_running) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            group_source *s = ExteriaGroupSourceFor(self, source, now);
            if (s) {
                s->last_packet = now;
                exteria_jitter_put(s->jitter, sequence, copy.bytes, copy.length);
            }
        }
        [copy release];
    });
}

- (void)setGain:(float)gain forSource:(uint32_t)source {
    dispatch_async(_queue, ^{
        unsigned i;
        int k;
        for (i = 0; i < _gainCount && _gains[i].ssrc != source; ++i) {}
        if (i == _gainCount) {
            /* a full table drops its oldest entry: a member that spoke long ago is the likeliest to be gone */
            if (_gainCount == GAINS_MAX) {
                memmove(_gains, _gains + 1, (GAINS_MAX - 1) * sizeof(_gains[0]));
                --_gainCount;
                i = _gainCount;
            }
            ++_gainCount;
        }
        _gains[i].ssrc = source;
        _gains[i].gain = gain;
        for (k = 0; k < SOURCES_MAX; ++k) {
            if (_sources[k].decoder && _sources[k].ssrc == source) _sources[k].gain = gain;
        }
    });
}

- (void)forgetSource:(uint32_t)source {
    dispatch_async(_queue, ^{
        int i;
        for (i = 0; i < SOURCES_MAX; ++i) {
            if (_sources[i].decoder && _sources[i].ssrc == source) ExteriaGroupSourceFree(&_sources[i]);
        }
    });
}

/* one packet of one source into its ring: a lost one is concealed with the length of the last */
- (void)decodeNextOfSource:(group_source *)source {
    int16_t decoded[MAX_DECODED];
    uint8_t packet[EXTERIA_JITTER_MAX_PACKET];
    size_t length = 0;
    int count;
    exteria_jitter_kind kind = exteria_jitter_get(source->jitter, packet, sizeof(packet), &length);
    if (kind == EXTERIA_JITTER_EMPTY) return;
    if (kind == EXTERIA_JITTER_FRAME) count = opus_decode(source->decoder, packet, (opus_int32)length, decoded, MAX_DECODED, 0);
    else count = opus_decode(source->decoder, NULL, 0, decoded, source->last_frame_samples, 0);
    if (count <= 0) return;
    source->last_frame_samples = count;
    exteria_pcm_ring_write(source->ring, decoded, (size_t)count);
}

/* every 10 ms on the codec queue: the microphone becomes encoded frames, the packets of the speakers become decoded samples, and the speaker's ring is topped
   up with their sum */
- (void)pump {
    int16_t pcm[FRAME_SAMPLES];
    uint8_t encoded[MAX_ENCODED];
    int guard, i;
    if (!_running || !_capture || !_playback || !_encoder) return;
    while (exteria_pcm_ring_fill(_capture) >= FRAME_SAMPLES) {
        int length, level;
        exteria_pcm_ring_read(_capture, pcm, FRAME_SAMPLES);
        if (_muted) {
            _voiceHold = 0;
            continue;
        }
        level = ExteriaGroupLevel(pcm, FRAME_SAMPLES);
        if (level <= VOICE_LEVEL_LIMIT) _voiceHold = VOICE_HOLD_FRAMES;
        else if (_voiceHold > 0) --_voiceHold;
        length = opus_encode(_encoder, pcm, FRAME_SAMPLES, encoded, sizeof(encoded));
        if (length > 0 && _frameHandler) _frameHandler([NSData dataWithBytes:encoded length:(NSUInteger)length], level, _voiceHold > 0);
    }
    for (guard = 0; guard < 16 && exteria_pcm_ring_fill(_playback) < PLAYBACK_TARGET; ++guard) {
        int16_t mix[MIX_SAMPLES];
        int32_t sum[MIX_SAMPLES];
        BOOL any = NO;
        memset(sum, 0, sizeof(sum));
        for (i = 0; i < SOURCES_MAX; ++i) {
            group_source *s = &_sources[i];
            int16_t chunk[MIX_SAMPLES];
            size_t got, k;
            if (!s->decoder) continue;
            if (exteria_pcm_ring_fill(s->ring) < MIX_SAMPLES) [self decodeNextOfSource:s];
            if (exteria_pcm_ring_fill(s->ring) < MIX_SAMPLES) continue;
            got = exteria_pcm_ring_read(s->ring, chunk, MIX_SAMPLES);
            any = YES;
            {
                float energy = 0;
                for (k = 0; k < got; ++k) {
                    sum[k] += (int32_t)((float)chunk[k] * s->gain);
                    energy += (float)chunk[k] * (float)chunk[k];
                }
                s->energy = sqrtf(energy / (float)(got ? got : 1));
            }
        }
        if (!any) break;
        for (i = 0; i < MIX_SAMPLES; ++i) {
            int32_t v = sum[i];
            mix[i] = (int16_t)(v > 32767 ? 32767 : (v < -32768 ? -32768 : v));
        }
        exteria_pcm_ring_write(_playback, mix, MIX_SAMPLES);
    }
    if (++_ticks % SPEAKING_REPORT_TICKS == 0 && _speakingHandler) {
        NSMutableArray *speaking = [NSMutableArray array];
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        for (i = 0; i < SOURCES_MAX; ++i) {
            group_source *s = &_sources[i];
            if (s->decoder && now - s->last_packet < 0.6 && s->energy > SPEAKING_RMS) [speaking addObject:[NSNumber numberWithUnsignedInt:s->ssrc]];
        }
        _speakingHandler(speaking, !_muted && _voiceHold > 0);
    }
}

@end
