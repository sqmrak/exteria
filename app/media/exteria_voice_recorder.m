#import "exteria_voice_recorder.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import "exteria_audio_session.h"
#import "exteria_chat_settings.h"

#include <stdio.h>

#include "exteria_voice.h"

/* a tap that ends under this is a slip of the finger, not a note */
#define MIN_SECONDS 0.6
#define CHUNK_SAMPLES 3200

@interface ExteriaVoiceRecorder () {
    AVAudioRecorder *_recorder;
    NSString *_wavPath;
}
@end

@implementation ExteriaVoiceRecorder

static NSString *ExteriaTemporaryPath(NSString *extension) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-%08x%08x.%@", arc4random(), arc4random(), extension]];
}

- (void)dealloc {
    [self cancel];
    [super dealloc];
}

- (BOOL)start {
    NSError *error = nil;
    if (!ExteriaAudioSessionBeginRecording(ExteriaChatRecordViaBluetooth())) return NO;
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:kAudioFormatLinearPCM], ExteriaAudioConstant("AVFormatIDKey"),
        [NSNumber numberWithFloat:EXTERIA_VOICE_RATE], ExteriaAudioConstant("AVSampleRateKey"),
        [NSNumber numberWithInt:1], ExteriaAudioConstant("AVNumberOfChannelsKey"),
        [NSNumber numberWithInt:16], ExteriaAudioConstant("AVLinearPCMBitDepthKey"),
        [NSNumber numberWithBool:NO], ExteriaAudioConstant("AVLinearPCMIsBigEndianKey"),
        [NSNumber numberWithBool:NO], ExteriaAudioConstant("AVLinearPCMIsFloatKey"), nil];
    _wavPath = [ExteriaTemporaryPath(@"wav") retain];
    _recorder = [[ExteriaAudioRecorderClass() alloc] initWithURL:[NSURL fileURLWithPath:_wavPath] settings:settings error:&error];
    if (!_recorder) {
        NSLog(@"exteria: cannot make the recorder: %@", error);
        [self cancel];
        return NO;
    }
    _recorder.meteringEnabled = YES;
    if (![_recorder record]) {
        NSLog(@"exteria: the microphone did not start");
        [self cancel];
        return NO;
    }
    return YES;
}

- (NSTimeInterval)elapsed {
    return _recorder.recording ? _recorder.currentTime : 0;
}

- (float)level {
    if (!_recorder.recording) return 0;
    [_recorder updateMeters];
    /* decibels from about -50 (a quiet room) to 0 (clipping) mapped onto a straight scale */
    float power = [_recorder averagePowerForChannel:0];
    return MAX(0.0f, MIN(1.0f, (power + 50.0f) / 50.0f));
}

- (void)cancel {
    [_recorder stop];
    [_recorder release];
    _recorder = nil;
    if (_wavPath) {
        [[NSFileManager defaultManager] removeItemAtPath:_wavPath error:NULL];
        [_wavPath release];
        _wavPath = nil;
    }
    [ExteriaAudioSession() setActive:NO error:NULL];
}

static int ExteriaWriteOgg(void *ctx, const uint8_t *bytes, size_t len) {
    return fwrite(bytes, 1, len, (FILE *)ctx) == len ? 0 : 1;
}

/* off the main thread: the recorded wav becomes an ogg file next to it; NO leaves no file behind */
static BOOL ExteriaEncode(NSString *wavPath, NSString *oggPath, int32_t *durationMs, NSMutableData *waveform) {
    NSData *wav = [NSData dataWithContentsOfFile:wavPath options:NSDataReadingMappedIfSafe error:NULL];
    size_t offset = 0, count = 0;
    exteria_status status = wav ? exteria_wav_pcm16(wav.bytes, wav.length, EXTERIA_VOICE_RATE, &offset, &count) : EXTERIA_E_IO;
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: the recording is not usable: %s", exteria_status_name(status));
        return NO;
    }
    int16_t *samples = malloc(count * sizeof(int16_t));
    if (!samples) return NO;
    memcpy(samples, (const uint8_t *)wav.bytes + offset, count * sizeof(int16_t));
    FILE *out = fopen(oggPath.fileSystemRepresentation, "wb");
    exteria_voice_encoder *encoder = NULL;
    status = out ? exteria_voice_encoder_new(&encoder, ExteriaWriteOgg, out) : EXTERIA_E_IO;
    for (size_t at = 0; status == EXTERIA_OK && at < count; at += CHUNK_SAMPLES) {
        status = exteria_voice_encoder_feed(encoder, samples + at, MIN((size_t)CHUNK_SAMPLES, count - at));
    }
    if (status == EXTERIA_OK) status = exteria_voice_encoder_finish(encoder);
    else exteria_voice_encoder_free(encoder);
    if (out && fclose(out) != 0 && status == EXTERIA_OK) status = EXTERIA_E_IO;
    if (status == EXTERIA_OK) status = exteria_waveform_build(samples, count, waveform.mutableBytes, waveform.length);
    free(samples);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: the voice note was not encoded: %s", exteria_status_name(status));
        [[NSFileManager defaultManager] removeItemAtPath:oggPath error:NULL];
        return NO;
    }
    *durationMs = (int32_t)((uint64_t)count * 1000u / EXTERIA_VOICE_RATE);
    return YES;
}

- (void)finishWithCompletion:(void (^)(NSString *, int32_t, NSData *))completion {
    NSTimeInterval length = _recorder.currentTime;
    NSString *wavPath = [_wavPath retain];
    void (^done)(NSString *, int32_t, NSData *) = [completion copy];
    [_recorder stop];
    [_recorder release];
    _recorder = nil;
    [_wavPath release];
    _wavPath = nil;
    [ExteriaAudioSession() setActive:NO error:NULL];
    if (!wavPath || length < MIN_SECONDS) {
        if (wavPath) [[NSFileManager defaultManager] removeItemAtPath:wavPath error:NULL];
        [wavPath release];
        done(nil, 0, nil);
        [done release];
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *oggPath = ExteriaTemporaryPath(@"ogg");
        NSMutableData *waveform = [NSMutableData dataWithLength:EXTERIA_WAVEFORM_BYTES];
        int32_t durationMs = 0;
        BOOL ok = ExteriaEncode(wavPath, oggPath, &durationMs, waveform);
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:NULL];
        NSData *delivered = [[waveform copy] autorelease];
        NSString *deliveredPath = ok ? [[oggPath copy] autorelease] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            done(deliveredPath, durationMs, delivered);
            [done release];
            [wavPath release];
        });
        [pool drain];
    });
}

@end
