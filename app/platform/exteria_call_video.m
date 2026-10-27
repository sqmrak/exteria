#import "exteria_call_video.h"

#import <CoreVideo/CoreVideo.h>
#import <libkern/OSAtomic.h>
#import <mach/mach_time.h>

#include "exteria_vp8.h"
#include "exteria_yuv.h"

#define PORTRAIT_WIDTH 240
#define PORTRAIT_HEIGHT 320
#define FRAME_RATE 15
#define BITRATE_KBPS 300
#define MAX_ENCODED (128 * 1024)
/* the other phone raises its picture once our reports tell it there is room (360 by 640 at first, then up to 720 by 1280), and a picture over the cap was refused
   whole, which left the screen black */
#define DECODE_MAX_PIXELS (720 * 1280)
/* the picture of the other phone (360 by 640 at the start of a call) is shown as it comes: the old cap of 480 shrank it by the nearest pixel and the screen then stretched it back */
#define SHOWN_SIDE 720
#define MAX_PENDING_FRAMES 6

@interface ExteriaCallVideo () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    void (^_frameHandler)(NSData *, BOOL, uint32_t);
    void (^_remoteImageHandler)(CGImageRef);
    void (^_keyFrameNeededHandler)(void);
    void (^_traceHandler)(NSString *);
    AVCaptureSession *_session;
    AVCaptureDeviceInput *_input;
    AVCaptureVideoDataOutput *_output;
    AVCaptureVideoPreviewLayer *_preview;
    dispatch_queue_t _captureQueue;
    dispatch_queue_t _decodeQueue;
    exteria_vp8_encoder *_encoder;
    int _encoderWidth, _encoderHeight;
    uint8_t *_planes;
    uint8_t *_encoded;
    BOOL _landscape;
    int _rotation;
    volatile int32_t _forceKey;
    volatile int32_t _running;
    uint64_t _lastFrameNs;
    int64_t _frames;
    exteria_vp8_decoder *_decoder;
    volatile int32_t _pending;
    volatile int32_t _needKey;
    int _capturedFrames, _encodedFrames, _encodeFailures, _decodedPictures, _decodeFailures;
    BOOL _usingFront;
}
@end

static uint64_t ExteriaVideoNowNs(void) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return mach_absolute_time() * base.numer / base.denom;
}

static AVCaptureDevice *ExteriaVideoCamera(AVCaptureDevicePosition position) {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == position) return device;
    }
    return nil;
}

static void ExteriaVideoReleasePixels(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    free((void *)data);
}

@implementation ExteriaCallVideo

@synthesize keyFrameNeededHandler = _keyFrameNeededHandler;
@synthesize traceHandler = _traceHandler;

- (void)setRemoteImageHandler:(void (^)(CGImageRef))handler {
    @synchronized (self) {
        if (_remoteImageHandler == handler) return;
        [_remoteImageHandler release];
        _remoteImageHandler = [handler copy];
    }
}

- (void (^)(CGImageRef))remoteImageHandler {
    @synchronized (self) {
        return [[_remoteImageHandler copy] autorelease];
    }
}

- (id)initWithFrameHandler:(void (^)(NSData *, BOOL, uint32_t))frameHandler {
    self = [super init];
    if (!self) return nil;
    _frameHandler = [frameHandler copy];
    _captureQueue = dispatch_queue_create("exteria.call.capture", DISPATCH_QUEUE_SERIAL);
    _decodeQueue = dispatch_queue_create("exteria.call.decode", DISPATCH_QUEUE_SERIAL);
    _usingFront = YES;
    return self;
}

- (void)dealloc {
    [self stop];
    if (_captureQueue) dispatch_release(_captureQueue);
    if (_decodeQueue) dispatch_release(_decodeQueue);
    [_frameHandler release];
    [_remoteImageHandler release];
    [_keyFrameNeededHandler release];
    [_traceHandler release];
    [super dealloc];
}

- (void)trace:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list arguments;
    void (^handler)(NSString *) = _traceHandler;
    if (!handler) return;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    handler(line);
    [line release];
}

- (CALayer *)previewLayer { return _preview; }
- (BOOL)cameraRunning { return _session != nil && _running != 0; }
- (BOOL)usingFrontCamera { return _usingFront; }

- (void)requestKeyFrame { _forceKey = 1; }

#pragma mark camera

- (BOOL)attachCamera:(AVCaptureDevice *)camera {
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (!input) {
        NSLog(@"exteria: the call camera was refused: %@", error);
        return NO;
    }
    if (_input) [_session removeInput:_input];
    if (![_session canAddInput:input]) {
        if (_input) [_session addInput:_input];
        return NO;
    }
    [_session addInput:input];
    [_input release];
    _input = [input retain];
    _usingFront = camera.position == AVCaptureDevicePositionFront;
    return YES;
}

- (void)applyOrientation:(UIInterfaceOrientation)orientation {
    AVCaptureVideoOrientation value = AVCaptureVideoOrientationPortrait;
    exteria_capture_orientation capture = EXTERIA_CAPTURE_PORTRAIT;
    int rotation = 0;
    switch (orientation) {
    case UIInterfaceOrientationPortraitUpsideDown:
        value = AVCaptureVideoOrientationPortraitUpsideDown;
        capture = EXTERIA_CAPTURE_PORTRAIT_UPSIDE_DOWN;
        break;
    case UIInterfaceOrientationLandscapeLeft:
        value = AVCaptureVideoOrientationLandscapeLeft;
        capture = EXTERIA_CAPTURE_LANDSCAPE_LEFT;
        break;
    case UIInterfaceOrientationLandscapeRight:
        value = AVCaptureVideoOrientationLandscapeRight;
        capture = EXTERIA_CAPTURE_LANDSCAPE_RIGHT;
        break;
    default: break;
    }
    AVCaptureConnection *outputConnection = [_output connectionWithMediaType:AVMediaTypeVideo];
    BOOL rotates = outputConnection && outputConnection.supportsVideoOrientation;
    if (rotates) outputConnection.videoOrientation = value;
    if (outputConnection.supportsVideoMirroring) {
        SEL automatic = NSSelectorFromString(@"setAutomaticallyAdjustsVideoMirroring:");
        if ([outputConnection respondsToSelector:automatic]) {
            void (*setAutomatic)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))[outputConnection methodForSelector:automatic];
            setAutomatic(outputConnection, automatic, NO);
        }
        outputConnection.videoMirrored = NO;
    }
    exteria_yuv_capture_rotation(capture, rotates ? 1 : 0, &rotation);
    BOOL landscape = orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight;
    /* the capture queue reads both while it encodes */
    dispatch_sync(_captureQueue, ^{
        _rotation = rotation;
        _landscape = landscape;
    });
    if ([_preview respondsToSelector:@selector(connection)]) {
        AVCaptureConnection *previewConnection = [_preview valueForKey:@"connection"];
        if (previewConnection.supportsVideoOrientation) previewConnection.videoOrientation = value;
    } else {
        /* ios 5 has the orientation on the layer itself, the connection property of the layer starts at ios 6 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (_preview.isOrientationSupported) _preview.orientation = value;
#pragma clang diagnostic pop
    }
}

- (void)setInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (_output) [self applyOrientation:orientation];
}

- (void)statusBarOrientationChanged:(NSNotification *)note {
    (void)note;
    [self setInterfaceOrientation:[UIApplication sharedApplication].statusBarOrientation];
}

- (BOOL)startCamera {
    AVCaptureDevice *camera;
    if (_session) return YES;
    camera = ExteriaVideoCamera(AVCaptureDevicePositionFront);
    if (!camera) camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!camera) {
        NSLog(@"exteria: this device has no camera for a video call");
        return NO;
    }
    _session = [[AVCaptureSession alloc] init];
    if ([_session canSetSessionPreset:AVCaptureSessionPreset640x480]) _session.sessionPreset = AVCaptureSessionPreset640x480;
    _output = [[AVCaptureVideoDataOutput alloc] init];
    _output.alwaysDiscardsLateVideoFrames = YES;
    _output.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                                                         forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [_output setSampleBufferDelegate:self queue:_captureQueue];
    if (![self attachCamera:camera] || ![_session canAddOutput:_output]) {
        NSLog(@"exteria: the capture session cannot take the call camera");
        [self stopCamera];
        return NO;
    }
    [_session addOutput:_output];
    _preview = [[AVCaptureVideoPreviewLayer layerWithSession:_session] retain];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self applyOrientation:[UIApplication sharedApplication].statusBarOrientation];
    _planes = (uint8_t *)malloc((size_t)PORTRAIT_WIDTH * PORTRAIT_HEIGHT * 3 / 2);
    _encoded = (uint8_t *)malloc(MAX_ENCODED);
    if (!_planes || !_encoded) {
        [self stopCamera];
        return NO;
    }
    _forceKey = 1;
    _frames = 0;
    _lastFrameNs = 0;
    _capturedFrames = _encodedFrames = _encodeFailures = 0;
    _running = 1;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarOrientationChanged:)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    [_session startRunning];
    [self trace:@"camera started (%@, preset %@)", _usingFront ? @"front" : @"back", _session.sessionPreset];
    return YES;
}

- (void)stopCamera {
    _running = 0;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    if (_session) {
        [_output setSampleBufferDelegate:nil queue:NULL];
        if ([_session isRunning]) [_session stopRunning];
    }
    /* a frame in flight finishes before the buffers and the encoder go */
    dispatch_sync(_captureQueue, ^{});
    [_preview release];
    _preview = nil;
    [_output release];
    _output = nil;
    [_input release];
    _input = nil;
    [_session release];
    _session = nil;
    if (_encoder) {
        exteria_vp8_encoder_close(_encoder);
        _encoder = NULL;
    }
    free(_planes);
    free(_encoded);
    _planes = NULL;
    _encoded = NULL;
}

- (BOOL)switchCamera {
    AVCaptureDevice *other;
    if (!_session) return NO;
    other = ExteriaVideoCamera(_usingFront ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront);
    if (!other) return NO;
    [_session beginConfiguration];
    BOOL ok = [self attachCamera:other];
    [_session commitConfiguration];
    /* switching inputs replaces the output connection on ios 5 */
    [self applyOrientation:[UIApplication sharedApplication].statusBarOrientation];
    _forceKey = 1;
    return ok;
}

- (BOOL)openEncoderForWidth:(int)width height:(int)height {
    if (_encoder && _encoderWidth == width && _encoderHeight == height) return YES;
    if (_encoder) {
        exteria_vp8_encoder_close(_encoder);
        _encoder = NULL;
    }
    if (exteria_vp8_encoder_open(&_encoder, width, height, FRAME_RATE, BITRATE_KBPS) != EXTERIA_OK) {
        NSLog(@"exteria: the video encoder could not be opened at %dx%d", width, height);
        [self trace:@"video encoder could not be opened at %dx%d", width, height];
        return NO;
    }
    [self trace:@"video encoder opened at %dx%d", width, height];
    _encoderWidth = width;
    _encoderHeight = height;
    _forceKey = 1;
    return YES;
}

/* the camera's frame becomes I420 of the size the encoder wants, is encoded, and goes to the owner; frames arrive faster than the rate and the surplus is dropped */
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    uint64_t now = ExteriaVideoNowNs();
    CVImageBufferRef buffer;
    int width, height, targetWidth, targetHeight;
    exteria_yuv_target target;
    size_t encodedLength = 0;
    int key = 0, force;
    (void)captureOutput;
    (void)connection;
    if (!_running || !_frameHandler) return;
    if (_lastFrameNs && now - _lastFrameNs < 1000000000ull / FRAME_RATE - 5000000ull) return;
    buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!buffer || !CVPixelBufferIsPlanar(buffer) || CVPixelBufferGetPlaneCount(buffer) < 2) return;
    _lastFrameNs = now;
    if (++_capturedFrames == 1) {
        [self trace:@"first camera frame %dx%d, turn %d degrees, %@", (int)CVPixelBufferGetWidthOfPlane(buffer, 0), (int)CVPixelBufferGetHeightOfPlane(buffer, 0), _rotation,
                    _landscape ? @"landscape" : @"portrait"];
    }
    CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    width = (int)CVPixelBufferGetWidthOfPlane(buffer, 0);
    height = (int)CVPixelBufferGetHeightOfPlane(buffer, 0);
    targetWidth = _landscape ? PORTRAIT_HEIGHT : PORTRAIT_WIDTH;
    targetHeight = _landscape ? PORTRAIT_WIDTH : PORTRAIT_HEIGHT;
    if ([self openEncoderForWidth:targetWidth height:targetHeight]) {
        target.width = targetWidth;
        target.height = targetHeight;
        target.plane[0] = _planes;
        target.plane[1] = _planes + (size_t)targetWidth * targetHeight;
        target.plane[2] = target.plane[1] + (size_t)targetWidth * targetHeight / 4;
        target.stride[0] = targetWidth;
        target.stride[1] = targetWidth / 2;
        target.stride[2] = targetWidth / 2;
        /* the front camera is sent as the camera sees it, only the local preview is mirrored */
        if (exteria_yuv_nv12_to_i420(CVPixelBufferGetBaseAddressOfPlane(buffer, 0), (int)CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
                                     CVPixelBufferGetBaseAddressOfPlane(buffer, 1), (int)CVPixelBufferGetBytesPerRowOfPlane(buffer, 1), width & ~1, height & ~1, _rotation, 0,
                                     &target) == EXTERIA_OK) {
            exteria_i420 image;
            int i;
            for (i = 0; i < 3; ++i) {
                image.plane[i] = target.plane[i];
                image.stride[i] = target.stride[i];
            }
            image.width = targetWidth;
            image.height = targetHeight;
            if (_encodedFrames < 3) {
                /* the mean of the luma of what goes to the encoder: about 16 is a black picture, whatever the camera was asked for */
                unsigned long sum = 0, count = 0;
                int sx, sy;
                for (sy = 0; sy < targetHeight; sy += 8)
                    for (sx = 0; sx < targetWidth; sx += 8, ++count) sum += target.plane[0][sy * target.stride[0] + sx];
                [self trace:@"video input luma %lu", count ? sum / count : 0ul];
            }
            force = _forceKey;
            _forceKey = 0;
            exteria_status encoded = exteria_vp8_encoder_encode(_encoder, &image, _frames++, force, _encoded, MAX_ENCODED, &encodedLength, &key);
            if (encoded != EXTERIA_OK && ++_encodeFailures <= 3) [self trace:@"video encode failed (%s)", exteria_status_name(encoded)];
            if (encoded == EXTERIA_OK && encodedLength > 0) {
                if (++_encodedFrames <= 3) [self trace:@"video frame %d encoded (%u bytes, %s)", _encodedFrames, (unsigned)encodedLength, key ? "key" : "delta"];
                _frameHandler([NSData dataWithBytes:_encoded length:encodedLength], key != 0, (uint32_t)(now / 1000000ull * 90ull));
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
}

#pragma mark remote picture

/* a decoded picture becomes pixels the screen can show, at most SHOWN_SIDE on its longer side */
static CGImageRef ExteriaVideoMakeImage(const exteria_i420 *picture) {
    int out_w = picture->width, out_h = picture->height, longer = out_w > out_h ? out_w : out_h;
    uint8_t *pixels;
    CGDataProviderRef provider;
    CGColorSpaceRef space;
    CGImageRef image;
    if (longer > SHOWN_SIDE) {
        out_w = out_w * SHOWN_SIDE / longer;
        out_h = out_h * SHOWN_SIDE / longer;
        if (out_w < 1) out_w = 1;
        if (out_h < 1) out_h = 1;
    }
    pixels = (uint8_t *)malloc((size_t)out_w * (size_t)out_h * 4);
    if (!pixels) return NULL;
    if (exteria_yuv_i420_to_bgra(picture, pixels, out_w * 4, out_w, out_h) != EXTERIA_OK) {
        free(pixels);
        return NULL;
    }
    provider = CGDataProviderCreateWithData(NULL, pixels, (size_t)out_w * (size_t)out_h * 4, ExteriaVideoReleasePixels);
    space = CGColorSpaceCreateDeviceRGB();
    image = provider && space ? CGImageCreate((size_t)out_w, (size_t)out_h, 8, 32, (size_t)out_w * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little,
                                              provider, NULL, false, kCGRenderingIntentDefault) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (provider) CGDataProviderRelease(provider);
    else free(pixels);
    return image;
}

- (void)receiveFrame:(NSData *)frame keyFrame:(BOOL)keyFrame {
    NSData *copy;
    if (frame.length == 0 || !_decodeQueue) return;
    if (_pending >= MAX_PENDING_FRAMES && !keyFrame) {
        /* the decoder is behind: this frame is dropped, and what follows is useless until a key frame comes */
        _needKey = 1;
        if (_keyFrameNeededHandler) _keyFrameNeededHandler();
        return;
    }
    copy = [frame copy];
    OSAtomicIncrement32((volatile int32_t *)&_pending);
    dispatch_async(_decodeQueue, ^{
        exteria_i420 picture;
        exteria_status status;
        if (_needKey && !keyFrame) {
            OSAtomicDecrement32((volatile int32_t *)&_pending);
            [copy release];
            return;
        }
        if (keyFrame) _needKey = 0;
        if (!_decoder && exteria_vp8_decoder_open(&_decoder, DECODE_MAX_PIXELS) != EXTERIA_OK) {
            OSAtomicDecrement32((volatile int32_t *)&_pending);
            [copy release];
            return;
        }
        status = exteria_vp8_decoder_decode(_decoder, copy.bytes, copy.length, &picture);
        if (status == EXTERIA_OK && picture.plane[0] && ++_decodedPictures == 1) [self trace:@"first remote picture %dx%d", picture.width, picture.height];
        if (status != EXTERIA_OK && ++_decodeFailures <= 3) [self trace:@"remote video frame refused (%s)", exteria_status_name(status)];
        if (status == EXTERIA_OK && picture.plane[0]) {
            void (^handler)(CGImageRef) = nil;
            @synchronized (self) { handler = [_remoteImageHandler copy]; }
            if (handler) {
                CGImageRef image = ExteriaVideoMakeImage(&picture);
                if (image) dispatch_async(dispatch_get_main_queue(), ^{
                    handler(image);
                    CGImageRelease(image);
                    [handler release];
                });
                else [handler release];
            }
        } else if (status != EXTERIA_OK) {
            /* a frame the decoder refused leaves its references doubtful: a key frame is asked for, and the frames between are skipped */
            _needKey = 1;
            if (_keyFrameNeededHandler) _keyFrameNeededHandler();
        }
        OSAtomicDecrement32((volatile int32_t *)&_pending);
        [copy release];
    });
}

- (void)stop {
    [self stopCamera];
    if (_decodeQueue) dispatch_sync(_decodeQueue, ^{});
    if (_decoder) {
        exteria_vp8_decoder_close(_decoder);
        _decoder = NULL;
    }
}

@end
