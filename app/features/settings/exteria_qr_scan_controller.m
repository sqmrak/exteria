#import "exteria_qr_scan_controller.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#include <stdlib.h>
#include <string.h>
#include <zbar.h>

#import "exteria_alert.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define FRAME_SIDE 240.0
#define TIMEOUT_SECONDS 8.0
#define LINK_PREFIX @"tg://login?token="

@interface ExteriaQrScanController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    AVCaptureSession *_capture;
    AVCaptureVideoDataOutput *_frames;
    AVCaptureVideoPreviewLayer *_preview;
    dispatch_queue_t _queue;
    zbar_image_scanner_t *_scanner;
    zbar_image_t *_image;
    uint8_t *_pixels;
    size_t _capacity;
    UIButton *_back;
    UILabel *_hint;
    UIView *_frame;
    BOOL _delivered;
    BOOL _closed;
    BOOL _started;
}
@end

@implementation ExteriaQrScanController

@synthesize scanHandler = _scanHandler;
@synthesize closeHandler = _closeHandler;

+ (BOOL)scanningAvailable {
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 0;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _queue = dispatch_queue_create("exteria.qr.scan", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    /* the frame callback runs on the queue, so it is cut off before the decoder goes */
    [_frames setSampleBufferDelegate:nil queue:NULL];
    [_capture stopRunning];
    dispatch_sync(_queue, ^{});
    if (_image) zbar_image_destroy(_image);
    if (_scanner) zbar_image_scanner_destroy(_scanner);
    free(_pixels);
    [_frames release];
    [_capture release];
    [_preview release];
    dispatch_release(_queue);
    [_back release];
    [_hint release];
    [_frame release];
    [_scanHandler release];
    [_closeHandler release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = [UIColor blackColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _frame = [[UIView alloc] init];
    _frame.layer.borderColor = [UIColor whiteColor].CGColor;
    _frame.layer.borderWidth = 3;
    _frame.layer.cornerRadius = 22;
    _frame.userInteractionEnabled = NO;
    [root addSubview:_frame];
    _hint = [[UILabel alloc] init];
    _hint.backgroundColor = [UIColor clearColor];
    _hint.textColor = [UIColor whiteColor];
    _hint.textAlignment = ExteriaTextAlignmentCenter;
    _hint.numberOfLines = 0;
    _hint.font = ExteriaFontRegular(16);
    _hint.text = NSLocalizedString(@"devices.scan.hint", nil);
    [root addSubview:_hint];
    _back = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_back setImage:ExteriaSymbolImage(ExteriaSymbolBack, 24, [UIColor whiteColor]) forState:UIControlStateNormal];
    _back.accessibilityLabel = NSLocalizedString(@"story.close", nil);
    [_back addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_back];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    _preview.frame = bounds;
    _back.frame = CGRectMake(8, insets.top + 8, 44, 44);
    _frame.frame = CGRectMake((bounds.size.width - FRAME_SIDE) / 2, (bounds.size.height - FRAME_SIDE) / 2 - 20, FRAME_SIDE, FRAME_SIDE);
    _hint.frame = CGRectMake(32, CGRectGetMaxY(_frame.frame) + 24, bounds.size.width - 64, 70);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _closed = NO;
    [self performSelector:@selector(showTimeout) withObject:nil afterDelay:TIMEOUT_SECONDS];
    if (!_started) [self startCapture];
    else [self resume];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _closed = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showTimeout) object:nil];
    AVCaptureSession *capture = _capture;
    if (capture) dispatch_async(_queue, ^{ [capture stopRunning]; });
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return orientation == UIInterfaceOrientationPortrait; }
- (BOOL)shouldAutorotate { return NO; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return 1 << UIInterfaceOrientationPortrait; }
#pragma clang diagnostic pop

- (void)showTimeout {
    if (_delivered || _closed) return;
    _hint.text = NSLocalizedString(@"devices.scan.timeout", nil);
}

- (void)showProblem:(NSString *)text {
    _hint.text = text;
}

#pragma mark capture

/* a code that never comes into focus never decodes, and a camera left alone keeps the focus it woke up with */
static void ExteriaFocusForScanning(AVCaptureDevice *camera) {
    if (![camera lockForConfiguration:NULL]) return;
    if ([camera isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) camera.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    if ([camera isFocusPointOfInterestSupported]) camera.focusPointOfInterest = CGPointMake(0.5f, 0.5f);
    if ([camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) camera.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    /* 1 is AVCaptureAutoFocusRangeRestrictionNear, and a code is held near; the call exists from ios 7 */
    SEL supported = NSSelectorFromString(@"isAutoFocusRangeRestrictionSupported");
    SEL setRange = NSSelectorFromString(@"setAutoFocusRangeRestriction:");
    if ([camera respondsToSelector:supported] && [camera respondsToSelector:setRange] && ((BOOL (*)(id, SEL))objc_msgSend)(camera, supported))
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(camera, setRange, 1);
    [camera unlockForConfiguration];
}

- (AVCaptureDevice *)backCamera {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == AVCaptureDevicePositionBack) return device;
    }
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

/* ios 7 asks the person for the camera the first time a session opens it; this asks first so a refusal can be told in words */
- (BOOL)cameraAllowed {
    Class deviceClass = [AVCaptureDevice class];
    SEL statusSelector = NSSelectorFromString(@"authorizationStatusForMediaType:");
    if (![deviceClass respondsToSelector:statusSelector]) return YES;
    NSInteger status = ((NSInteger (*)(id, SEL, id))objc_msgSend)(deviceClass, statusSelector, AVMediaTypeVideo);
    /* 0 not asked, 1 restricted, 2 denied, 3 authorized */
    if (status == 1 || status == 2) {
        [self showProblem:NSLocalizedString(@"devices.scan.denied", nil)];
        return NO;
    }
    if (status == 0) {
        SEL requestSelector = NSSelectorFromString(@"requestAccessForMediaType:completionHandler:");
        if ([deviceClass respondsToSelector:requestSelector]) {
            ExteriaQrScanController *me = self;
            [me retain];
            ((void (*)(id, SEL, id, void (^)(BOOL)))objc_msgSend)(deviceClass, requestSelector, AVMediaTypeVideo, ^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted && !me->_closed) [me startCapture];
                    else if (!granted) [me showProblem:NSLocalizedString(@"devices.scan.denied", nil)];
                    [me release];
                });
            });
            return NO;
        }
    }
    return YES;
}

- (void)startCapture {
    if (_started || ![self cameraAllowed]) return;
    AVCaptureDevice *camera = [self backCamera];
    NSError *error = nil;
    AVCaptureDeviceInput *input = camera ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error] : nil;
    _scanner = zbar_image_scanner_create();
    _image = zbar_image_create();
    AVCaptureSession *session = input && _scanner && _image ? [[AVCaptureSession alloc] init] : nil;
    AVCaptureVideoDataOutput *frames = session ? [[AVCaptureVideoDataOutput alloc] init] : nil;
    if (!session || !frames || ![session canAddInput:input] || ![session canAddOutput:frames]) {
        NSLog(@"exteria: the qr scanner cannot start: %@", error);
        [session release];
        [frames release];
        [self showProblem:NSLocalizedString(@"story.camera.unavailable", nil)];
        return;
    }
    zbar_image_scanner_set_config(_scanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1);
    zbar_image_scanner_enable_cache(_scanner, 0);
    /* a link of a login token is a small code, but 640x480 leaves too few pixels per module at reading distance */
    [session beginConfiguration];
    [session addInput:input];
    if ([session canSetSessionPreset:AVCaptureSessionPreset1280x720]) session.sessionPreset = AVCaptureSessionPreset1280x720;
    else if ([session canSetSessionPreset:AVCaptureSessionPreset640x480]) session.sessionPreset = AVCaptureSessionPreset640x480;
    [session commitConfiguration];
    frames.alwaysDiscardsLateVideoFrames = YES;
    [session addOutput:frames];
    /* the list of formats answers once the output belongs to the session, and a format the device does not publish delivers no frames */
    NSArray *formats = [frames availableVideoCVPixelFormatTypes];
    static const unsigned wanted[] = {kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_32BGRA};
    for (size_t i = 0; i < sizeof(wanted) / sizeof(wanted[0]); ++i) {
        if ([formats containsObject:[NSNumber numberWithUnsignedInt:wanted[i]]]) {
            frames.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:wanted[i]] forKey:(NSString *)kCVPixelBufferPixelFormatTypeKey];
            break;
        }
    }
    [frames setSampleBufferDelegate:self queue:_queue];
    ExteriaFocusForScanning(camera);
    _capture = session;
    _frames = frames;
    _preview = [[AVCaptureVideoPreviewLayer layerWithSession:session] retain];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _preview.frame = self.view.bounds;
    [self.view.layer insertSublayer:_preview atIndex:0];
    _started = YES;
    [self resume];
}

/* startRunning blocks until the camera is up, so it never runs on the main thread */
- (void)resume {
    AVCaptureSession *capture = _capture;
    if (capture) dispatch_async(_queue, ^{ [capture startRunning]; });
}

#pragma mark decoding

/* the luminance plane of the frame, as the greyscale image zbar reads */
- (BOOL)loadPixelsOfBuffer:(CVImageBufferRef)buffer width:(size_t)width height:(size_t)height {
    if (!width || !height || width > SIZE_MAX / height) return NO;
    size_t count = width * height;
    if (count > _capacity) {
        zbar_image_set_data(_image, NULL, 0, NULL);
        uint8_t *grown = (uint8_t *)realloc(_pixels, count);
        if (!grown) return NO;
        _pixels = grown;
        _capacity = count;
    }
    OSType format = CVPixelBufferGetPixelFormatType(buffer);
    if (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(buffer, 0);
        size_t stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
        if (!base) return NO;
        for (size_t y = 0; y < height; ++y) memcpy(_pixels + y * width, base + y * stride, width);
    } else {
        uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
        size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        if (!base) return NO;
        for (size_t y = 0; y < height; ++y) {
            const uint8_t *row = base + y * stride;
            uint8_t *out = _pixels + y * width;
            for (size_t x = 0; x < width; ++x) out[x] = (uint8_t)((row[x * 4 + 2] * 77 + row[x * 4 + 1] * 150 + row[x * 4] * 29) >> 8);
        }
    }
    zbar_image_set_format(_image, zbar_fourcc('Y', '8', '0', '0'));
    zbar_image_set_size(_image, (unsigned)width, (unsigned)height);
    zbar_image_set_data(_image, _pixels, (unsigned long)count, NULL);
    return YES;
}

/* on the capture queue, at the frame rate */
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection {
    (void)output;
    (void)connection;
    if (_delivered || !_scanner || !_image) return;
    CVImageBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer) return;
    /* every decoded text is an autoreleased string, and a queue without a pool of its own would collect them for the whole scan */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    size_t width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer);
    OSType format = CVPixelBufferGetPixelFormatType(buffer);
    if (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        width = CVPixelBufferGetWidthOfPlane(buffer, 0);
        height = CVPixelBufferGetHeightOfPlane(buffer, 0);
    }
    if ([self loadPixelsOfBuffer:buffer width:width height:height]) {
        zbar_scan_image(_scanner, _image);
        for (const zbar_symbol_t *symbol = zbar_image_first_symbol(_image); symbol; symbol = zbar_symbol_next(symbol)) {
            if (zbar_symbol_get_type(symbol) != ZBAR_QRCODE) continue;
            NSString *text = [[[NSString alloc] initWithBytes:zbar_symbol_get_data(symbol) length:zbar_symbol_get_data_length(symbol) encoding:NSUTF8StringEncoding] autorelease];
            if ([text hasPrefix:LINK_PREFIX]) {
                [self performSelectorOnMainThread:@selector(accept:) withObject:text waitUntilDone:NO];
                break;
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    [pool release];
}

- (void)accept:(NSString *)link {
    if (_delivered || _closed) return;
    _delivered = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showTimeout) object:nil];
    if (_scanHandler) _scanHandler(link);
}

- (void)backTapped {
    if (_closeHandler) _closeHandler();
}

@end
