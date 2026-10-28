#import "exteria_round_recorder.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreMedia/CoreMedia.h>
#import "exteria_audio_session.h"

/* the picture the clients draw in a circle; small enough for an old phone to encode while it records */
#define SIDE 384
#define VIDEO_BITRATE 700000
#define MIN_SECONDS 0.6

@interface ExteriaRoundRecorder () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate> {
    AVCaptureSession *_session;
    AVCaptureVideoPreviewLayer *_preview;
    AVCaptureDeviceInput *_cameraInput;
    AVCaptureVideoDataOutput *_videoOutput;
    AVCaptureAudioDataOutput *_audioOutput;
    dispatch_queue_t _queue;
    /* a swap of the cameras and a change of the zoom, one after another, off the main thread */
    dispatch_queue_t _configQueue;
    NSString *_path;
    NSDate *_startedAt;
    NSString *_failure;
    /* a swap of the cameras is on its way; main thread */
    BOOL _switching;
    BOOL _captureStopped;
    BOOL _torchOn;
    /* the fields below belong to the capture queue once recording starts */
    AVAssetWriter *_writer;
    AVAssetWriterInput *_videoInput;
    AVAssetWriterInput *_audioInput;
    BOOL _sessionStarted;
    BOOL _stopped;
    /* sound the writer was not ready for: while the camera swaps no pictures arrive, the writer keeps the two tracks close in time and stops taking sound, which
       cut the phrase that was being said; the sound waits here for the next turn of the writer */
    NSMutableArray *_pendingAudio;
    CMTime _first;
    CMTime _last;
}
@end

@implementation ExteriaRoundRecorder

/* marks the capture queue, so cancel can tell when it already runs there */
static char ExteriaRoundQueueKey;
static char ExteriaRoundConfigQueueKey;

static NSString *ExteriaClipPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-%08x%08x.mp4", arc4random(), arc4random()]];
}

static AVCaptureDevice *ExteriaCamera(AVCaptureDevicePosition position) {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == position) return device;
    }
    return nil;
}

/* the capture pipeline rotates the buffers upright, so the writer and the preview never turn them afterwards */
static void ExteriaUpright(AVCaptureVideoDataOutput *output) {
    AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
    if (connection.supportsVideoOrientation) connection.videoOrientation = AVCaptureVideoOrientationPortrait;
}

- (NSString *)failure {
    return _failure;
}

- (CALayer *)previewLayer {
    return _preview;
}

- (void)dealloc {
    [_failure release];
    [self cancel];
    [super dealloc];
}

- (BOOL)start {
    AVCaptureDevice *camera = ExteriaCamera(AVCaptureDevicePositionFront);
    if (!camera) camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *microphone = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSError *error = nil;
    if (!camera || !microphone) return NO;
    AVCaptureDeviceInput *cameraInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    AVCaptureDeviceInput *micInput = cameraInput ? [AVCaptureDeviceInput deviceInputWithDevice:microphone error:&error] : nil;
    if (!cameraInput || !micInput) {
        NSLog(@"exteria: capture inputs refused: %@", error);
        return NO;
    }
    AVAudioSession *audio = ExteriaAudioSession();
    NSString *mode = ExteriaAudioConstant("AVAudioSessionModeDefault");
    if (!audio || !mode || ![audio setCategory:ExteriaAudioCategoryPlayAndRecord() error:&error] ||
        ![audio setMode:mode error:&error] || ![audio setActive:YES error:&error]) {
        NSLog(@"exteria: audio session refused the video: %@", error);
        return NO;
    }
    _session = [[AVCaptureSession alloc] init];
    /* keep ios 7 camera swaps from changing the microphone route during recording */
    if ([_session respondsToSelector:NSSelectorFromString(@"setAutomaticallyConfiguresApplicationAudioSession:")]) {
        [_session setValue:[NSNumber numberWithBool:YES] forKey:@"usesApplicationAudioSession"];
        [_session setValue:[NSNumber numberWithBool:NO] forKey:@"automaticallyConfiguresApplicationAudioSession"];
    }
    if ([_session canSetSessionPreset:AVCaptureSessionPreset640x480]) _session.sessionPreset = AVCaptureSessionPreset640x480;
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    if (![_session canAddInput:cameraInput] || ![_session canAddInput:micInput] || ![_session canAddOutput:_videoOutput] ||
        ![_session canAddOutput:_audioOutput]) {
        NSLog(@"exteria: the capture session cannot take the camera and the microphone");
        [self cancel];
        return NO;
    }
    [_session addInput:cameraInput];
    [_session addInput:micInput];
    [_session addOutput:_videoOutput];
    [_session addOutput:_audioOutput];
    _cameraInput = [cameraInput retain];
    ExteriaUpright(_videoOutput);
    _preview = [[AVCaptureVideoPreviewLayer layerWithSession:_session] retain];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    /* the layer's own connection came with ios 6; ios 5 turns the picture through the layer's orientation property */
    if ([_preview respondsToSelector:@selector(connection)]) {
        AVCaptureConnection *previewConnection = [_preview valueForKey:@"connection"];
        if (previewConnection.supportsVideoOrientation) previewConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    } else if (_preview.isOrientationSupported) {
        _preview.orientation = AVCaptureVideoOrientationPortrait;
    }
    _path = [ExteriaClipPath() retain];
    _writer = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:_path] fileType:AVFileTypeMPEG4 error:&error];
    if (!_writer) {
        NSLog(@"exteria: cannot make the clip writer: %@", error);
        [self cancel];
        return NO;
    }
    NSDictionary *compression = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:VIDEO_BITRATE], AVVideoAverageBitRateKey,
        AVVideoProfileLevelH264Baseline31, AVVideoProfileLevelKey, nil];
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
        AVVideoCodecH264, AVVideoCodecKey,
        [NSNumber numberWithInt:SIDE], AVVideoWidthKey,
        [NSNumber numberWithInt:SIDE], AVVideoHeightKey,
        AVVideoScalingModeResizeAspectFill, AVVideoScalingModeKey,
        compression, AVVideoCompressionPropertiesKey, nil];
    /* the writer raises an exception for an audio input without a channel layout, which on ios 5 aborted the app at this call */
    AudioChannelLayout mono;
    memset(&mono, 0, sizeof(mono));
    mono.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    NSDictionary *audioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:kAudioFormatMPEG4AAC], ExteriaAudioConstant("AVFormatIDKey"),
        [NSNumber numberWithInt:1], ExteriaAudioConstant("AVNumberOfChannelsKey"),
        [NSNumber numberWithFloat:44100], ExteriaAudioConstant("AVSampleRateKey"),
        [NSData dataWithBytes:&mono length:sizeof(mono)], ExteriaAudioConstant("AVChannelLayoutKey"),
        [NSNumber numberWithInt:64000], ExteriaAudioConstant("AVEncoderBitRateKey"), nil];
    /* the writer reports settings it does not take by raising, so the call is the boundary where that becomes a failed start */
    @try {
        _videoInput = [[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings] retain];
        _audioInput = [[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings] retain];
    } @catch (NSException *exception) {
        NSLog(@"exteria: the clip writer refused its settings: %@", exception);
        _failure = [[exception reason] copy];
        [self cancel];
        return NO;
    }
    _videoInput.expectsMediaDataInRealTime = YES;
    _audioInput.expectsMediaDataInRealTime = YES;
    if (![_writer canAddInput:_videoInput] || ![_writer canAddInput:_audioInput]) {
        NSLog(@"exteria: the clip writer refused the settings");
        [self cancel];
        return NO;
    }
    [_writer addInput:_videoInput];
    [_writer addInput:_audioInput];
    _queue = dispatch_queue_create("exteria.round", DISPATCH_QUEUE_SERIAL);
    _configQueue = dispatch_queue_create("exteria.round.config", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_queue, &ExteriaRoundQueueKey, &ExteriaRoundQueueKey, NULL);
    dispatch_queue_set_specific(_configQueue, &ExteriaRoundConfigQueueKey, self, NULL);
    [_videoOutput setSampleBufferDelegate:self queue:_queue];
    [_audioOutput setSampleBufferDelegate:self queue:_queue];
    _first = kCMTimeZero;
    _last = kCMTimeZero;
    _startedAt = [[NSDate date] retain];
    [_session startRunning];
    return YES;
}

/* the lens zoom of ios 7 is reached by name, so the armv7 slice built against the older headers still links and the older systems do not try it */
static BOOL ExteriaDeviceZooms(AVCaptureDevice *device) {
    return device && [device respondsToSelector:NSSelectorFromString(@"setVideoZoomFactor:")];
}

#define ZOOM_MAX 5.0

- (BOOL)canUseTorch {
    AVCaptureDevice *device = _cameraInput.device;
    return !_captureStopped && !_switching && device.hasTorch && device.torchAvailable && [device isTorchModeSupported:AVCaptureTorchModeOn];
}

- (BOOL)torchOn { return _torchOn; }

- (void)setTorchOn:(BOOL)on completion:(void (^)(BOOL success))completion {
    void (^done)(BOOL) = [completion copy];
    if (!_configQueue || ![self canUseTorch]) {
        if (done) done(NO);
        [done release];
        return;
    }
    AVCaptureDevice *device = _cameraInput.device;
    dispatch_async(_configQueue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        BOOL ok = [device lockForConfiguration:&error];
        if (ok) {
            AVCaptureTorchMode mode = on ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
            ok = device.torchAvailable && [device isTorchModeSupported:mode];
            if (ok) device.torchMode = mode;
            [device unlockForConfiguration];
        }
        if (!ok) NSLog(@"exteria: the round video torch could not change: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL current = !_captureStopped && !_switching && _cameraInput.device == device;
            if (ok && current) _torchOn = on;
            if (done) done(ok && current);
            [done release];
        });
        [pool drain];
    });
}

- (BOOL)canZoom {
    return ExteriaDeviceZooms(_cameraInput.device);
}

- (CGFloat)zoom {
    AVCaptureDevice *device = _cameraInput.device;
    return ExteriaDeviceZooms(device) ? (CGFloat)[[device valueForKey:@"videoZoomFactor"] doubleValue] : 1;
}

- (void)setZoom:(CGFloat)zoom {
    AVCaptureDevice *device = _cameraInput.device;
    if (_captureStopped || !ExteriaDeviceZooms(device) || !_configQueue) return;
    double lens = [[[device valueForKey:@"activeFormat"] valueForKey:@"videoMaxZoomFactor"] doubleValue];
    double wanted = MAX(1.0, MIN(MIN(lens, ZOOM_MAX), (double)zoom));
    dispatch_async(_configQueue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        if (![device lockForConfiguration:&error]) {
            NSLog(@"exteria: the camera would not zoom: %@", error);
            [pool drain];
            return;
        }
        [device setValue:[NSNumber numberWithDouble:wanted] forKey:@"videoZoomFactor"];
        [device unlockForConfiguration];
        [pool drain];
    });
}

- (void)switchCameraWithCompletion:(void (^)(BOOL switched))completion {
    void (^done)(BOOL) = [completion copy];
    if (_captureStopped || !_session || !_cameraInput || !_configQueue) {
        if (done) done(NO);
        [done release];
        return;
    }
    if (_switching) {
        if (done) done(NO);
        [done release];
        return;
    }
    _switching = YES;
    AVCaptureDevicePosition target = _cameraInput.device.position == AVCaptureDevicePositionFront ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    AVCaptureDevice *camera = ExteriaCamera(target);
    if (!camera) {
        _switching = NO;
        if (done) done(NO);
        [done release];
        return;
    }
    AVCaptureDeviceInput *old = _cameraInput;
    dispatch_async(_configQueue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
        BOOL swapped = NO;
        if (!input) {
            NSLog(@"exteria: the other camera refused: %@", error);
        } else {
            if (old.device.hasTorch && old.device.torchMode != AVCaptureTorchModeOff) {
                if ([old.device lockForConfiguration:&error]) {
                    old.device.torchMode = AVCaptureTorchModeOff;
                    [old.device unlockForConfiguration];
                } else NSLog(@"exteria: the round video torch could not turn off: %@", error);
            }
            [_session beginConfiguration];
            [_session removeInput:old];
            swapped = [_session canAddInput:input];
            /* a camera that cannot be taken leaves the old one in place, so the clip goes on */
            [_session addInput:swapped ? input : old];
            ExteriaUpright(_videoOutput);
            [_session commitConfiguration];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            _switching = NO;
            if (!_captureStopped && swapped && _cameraInput == old) {
                [_cameraInput release];
                _cameraInput = [input retain];
            }
            _torchOn = !_captureStopped && _cameraInput.device.hasTorch && _cameraInput.device.torchMode == AVCaptureTorchModeOn;
            if (done) done(!_captureStopped && swapped);
            [done release];
        });
        [pool drain];
    });
}

- (NSTimeInterval)elapsed {
    return _startedAt ? -[_startedAt timeIntervalSinceNow] : 0;
}

/* capture queue: the first picture opens the file, so the clip never starts with sound alone */
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)buffer fromConnection:(AVCaptureConnection *)connection {
    (void)connection;
    if (_stopped || !CMSampleBufferDataIsReady(buffer)) return;
    BOOL video = output == _videoOutput;
    CMTime time = CMSampleBufferGetPresentationTimeStamp(buffer);
    if (!_sessionStarted) {
        if (!video || _writer.status != AVAssetWriterStatusUnknown) return;
        if (![_writer startWriting]) {
            NSLog(@"exteria: the clip writer did not start: %@", _writer.error);
            _stopped = YES;
            return;
        }
        [_writer startSessionAtSourceTime:time];
        _first = time;
        _last = time;
        _sessionStarted = YES;
    }
    if (_writer.status != AVAssetWriterStatusWriting) return;
    [self appendPendingAudio];
    if (!video) {
        if (_pendingAudio.count || !_audioInput.readyForMoreMediaData) [self holdAudio:buffer];
        else [self appendSample:buffer time:time toInput:_audioInput];
        return;
    }
    if (_videoInput.readyForMoreMediaData) [self appendSample:buffer time:time toInput:_videoInput];
}

/* capture queue: a picture the writer is not ready for is dropped, the next one comes in a frame; sound is never dropped, since a gap in it is heard */
- (void)appendSample:(CMSampleBufferRef)buffer time:(CMTime)time toInput:(AVAssetWriterInput *)input {
    if ([input appendSampleBuffer:buffer]) {
        if (CMTimeCompare(time, _last) > 0) _last = time;
    } else {
        NSLog(@"exteria: a clip sample was refused: %@", _writer.error);
    }
}

/* about four seconds of sound at the size of a capture buffer; a camera that takes longer than that to swap loses the oldest part, which is logged */
#define PENDING_AUDIO_MAX 200

- (void)holdAudio:(CMSampleBufferRef)buffer {
    if (!_pendingAudio) _pendingAudio = [[NSMutableArray alloc] init];
    if (_pendingAudio.count >= PENDING_AUDIO_MAX) {
        NSLog(@"exteria: the writer took no sound for too long, the oldest part is dropped");
        [_pendingAudio removeObjectAtIndex:0];
    }
    [_pendingAudio addObject:(id)buffer];
}

- (void)appendPendingAudio {
    while (_pendingAudio.count && _audioInput.readyForMoreMediaData) {
        CMSampleBufferRef held = (CMSampleBufferRef)[_pendingAudio objectAtIndex:0];
        [self appendSample:held time:CMSampleBufferGetPresentationTimeStamp(held) toInput:_audioInput];
        [_pendingAudio removeObjectAtIndex:0];
    }
}

- (void)teardownCapture {
    /* a later cancel must not deactivate the next recording's audio session */
    if (_captureStopped) return;
    _captureStopped = YES;
    /* stopping during a camera commit races the session graph and the microphone teardown */
    void (^stop)(void) = ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        AVCaptureDevice *device = _cameraInput.device;
        if (device.hasTorch && device.torchMode != AVCaptureTorchModeOff) {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                device.torchMode = AVCaptureTorchModeOff;
                [device unlockForConfiguration];
            } else NSLog(@"exteria: the round video torch could not turn off: %@", error);
        }
        [_session stopRunning];
        [_videoOutput setSampleBufferDelegate:nil queue:NULL];
        [_audioOutput setSampleBufferDelegate:nil queue:NULL];
        [pool drain];
    };
    if (_configQueue && dispatch_get_specific(&ExteriaRoundConfigQueueKey) != self) dispatch_sync(_configQueue, stop);
    else stop();
    NSError *error = nil;
    if (![ExteriaAudioSession() setActive:NO error:&error]) NSLog(@"exteria: audio session would not close after the clip: %@", error);
}

- (void)finishWithCompletion:(void (^)(NSString *, int32_t, int32_t))completion {
    void (^done)(NSString *, int32_t, int32_t) = [completion copy];
    /* the clip now belongs to the completion, so releasing the recorder later must not delete it */
    NSString *path = _path;
    _path = nil;
    [self teardownCapture];
    dispatch_queue_t queue = _queue;
    if (!queue) {
        done(nil, 0, 0);
        [done release];
        [path release];
        return;
    }
    dispatch_async(queue, ^{
        _stopped = YES;
        int32_t durationMs = 0;
        BOOL ok = NO;
        if (_sessionStarted && _writer.status == AVAssetWriterStatusWriting) {
            durationMs = (int32_t)(CMTimeGetSeconds(CMTimeSubtract(_last, _first)) * 1000.0);
            [self appendPendingAudio];
            [_videoInput markAsFinished];
            [_audioInput markAsFinished];
            ok = [_writer finishWriting] && _writer.status == AVAssetWriterStatusCompleted;
            if (!ok) NSLog(@"exteria: the clip was not finished: %@", _writer.error);
        }
        NSLog(@"exteria: round clip closed: written %d, %d ms, writer status %d", ok, durationMs, (int)_writer.status);
        if (!ok || durationMs < (int32_t)(MIN_SECONDS * 1000)) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            ok = NO;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            done(ok ? path : nil, durationMs, ok ? SIDE : 0);
            [done release];
            [path release];
        });
    });
}

- (void)cancel {
    [self teardownCapture];
    if (_queue) {
        /* the writer is touched on its queue only, so the file is dropped there */
        NSString *path = [_path retain];
        AVAssetWriter *writer = [_writer retain];
        void (^stop)(void) = ^{
            _stopped = YES;
            if (writer.status == AVAssetWriterStatusWriting) [writer cancelWriting];
        };
        /* the block that finishes the clip holds the recorder, so its last release can land on the capture queue, where a sync call to that queue aborts the app
           on ios 15 */
        if (dispatch_get_specific(&ExteriaRoundQueueKey)) stop();
        else dispatch_sync(_queue, stop);
        [writer release];
        if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [path release];
        dispatch_release(_queue);
        _queue = NULL;
        if (_configQueue) {
            dispatch_release(_configQueue);
            _configQueue = NULL;
        }
    } else if (_path) {
        [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    }
    [_writer release];
    _writer = nil;
    [_videoInput release];
    _videoInput = nil;
    [_audioInput release];
    _audioInput = nil;
    [_pendingAudio release];
    _pendingAudio = nil;
    [_videoOutput release];
    _videoOutput = nil;
    [_cameraInput release];
    _cameraInput = nil;
    [_audioOutput release];
    _audioOutput = nil;
    [_preview release];
    _preview = nil;
    [_session release];
    _session = nil;
    [_path release];
    _path = nil;
    [_startedAt release];
    _startedAt = nil;
}

@end
