#import "exteria_story_camera_controller.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_photo_library.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define STORY_SIDE 1280.0
#define STORY_QUALITY 0.85
#define BOTTOM_ROW 132.0
#define SHUTTER 76.0
#define SIDE_BUTTON 52.0
#define THUMB 48.0

@interface ExteriaStoryCameraController () {
    AVCaptureSession *_capture;
    AVCaptureDeviceInput *_input;
    AVCaptureStillImageOutput *_still;
    AVCaptureVideoPreviewLayer *_preview;
    dispatch_queue_t _queue;
    ExteriaWeakReference *_weak;
    UIView *_stage;
    UIView *_grid;
    UIButton *_back;
    UIButton *_gridButton;
    UIButton *_shutter;
    UIButton *_flip;
    UIButton *_gallery;
    UIImageView *_thumb;
    UIImageView *_held;
    UIButton *_retake;
    UIButton *_publish;
    UIActivityIndicatorView *_spinner;
    NSString *_heldPath;
    BOOL _shooting;
    BOOL _closed;
}
@end

@implementation ExteriaStoryCameraController

@synthesize publishHandler = _publishHandler;
@synthesize galleryHandler = _galleryHandler;
@synthesize closeHandler = _closeHandler;

static AVCaptureDevice *ExteriaStoryCamera(AVCaptureDevicePosition position) {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == position) return device;
    }
    return nil;
}

+ (BOOL)cameraAvailable {
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 0;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _queue = dispatch_queue_create("exteria.story.camera", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_capture stopRunning];
    [_capture release];
    dispatch_release(_queue);
    if (_heldPath) [[NSFileManager defaultManager] removeItemAtPath:_heldPath error:NULL];
    [_heldPath release];
    [_publishHandler release];
    [_galleryHandler release];
    [_closeHandler release];
    [_stage release];
    [_grid release];
    [_back release];
    [_gridButton release];
    [_shutter release];
    [_flip release];
    [_gallery release];
    [_thumb release];
    [_held release];
    [_retake release];
    [_publish release];
    [_spinner release];
    [_input release];
    [_still release];
    [_preview release];
    [super dealloc];
}

#pragma mark view

static UIButton *ExteriaStoryRoundButton(ExteriaSymbol symbol, CGFloat side, UIColor *fill, UIColor *ink, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = fill;
    button.layer.cornerRadius = side / 2;
    [button setImage:ExteriaSymbolImage(symbol, side * 0.46, ink) forState:UIControlStateNormal];
    button.accessibilityLabel = label;
    return button;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = [UIColor blackColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _stage = [[UIView alloc] init];
    _stage.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    _stage.layer.cornerRadius = 18;
    _stage.layer.masksToBounds = YES;
    [root addSubview:_stage];
    _held = [[UIImageView alloc] init];
    _held.contentMode = UIViewContentModeScaleAspectFill;
    _held.clipsToBounds = YES;
    _held.hidden = YES;
    [_stage addSubview:_held];
    _grid = [[UIView alloc] init];
    _grid.userInteractionEnabled = NO;
    _grid.hidden = YES;
    [_stage addSubview:_grid];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];

    UIColor *glass = [UIColor colorWithWhite:0.12 alpha:0.72];
    _back = [ExteriaStoryRoundButton(ExteriaSymbolBack, 44, [UIColor clearColor], [UIColor whiteColor], NSLocalizedString(@"story.close", nil)) retain];
    [_back addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_back];
    _gridButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _gridButton.accessibilityLabel = NSLocalizedString(@"story.camera.grid", nil);
    [_gridButton setImage:[self gridIconLit:NO] forState:UIControlStateNormal];
    [_gridButton addTarget:self action:@selector(gridTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_gridButton];

    /* a white disc inside a white ring */
    _shutter = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _shutter.accessibilityLabel = NSLocalizedString(@"story.camera.shoot", nil);
    _shutter.layer.cornerRadius = SHUTTER / 2;
    _shutter.layer.borderWidth = 4;
    _shutter.layer.borderColor = [UIColor whiteColor].CGColor;
    UIView *disc = [[[UIView alloc] initWithFrame:CGRectMake(7, 7, SHUTTER - 14, SHUTTER - 14)] autorelease];
    disc.backgroundColor = [UIColor whiteColor];
    disc.layer.cornerRadius = (SHUTTER - 14) / 2;
    disc.userInteractionEnabled = NO;
    [_shutter addSubview:disc];
    [_shutter addTarget:self action:@selector(shutterTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_shutter];
    _flip = [ExteriaStoryRoundButton(ExteriaSymbolCameraFlip, SIDE_BUTTON, glass, [UIColor whiteColor], NSLocalizedString(@"story.camera.flip", nil)) retain];
    [_flip addTarget:self action:@selector(flipTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_flip];
    _gallery = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _gallery.accessibilityLabel = NSLocalizedString(@"story.camera.gallery", nil);
    _gallery.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    _gallery.layer.cornerRadius = 8;
    _gallery.layer.masksToBounds = YES;
    [_gallery addTarget:self action:@selector(galleryTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_gallery];
    _thumb = [[UIImageView alloc] init];
    _thumb.contentMode = UIViewContentModeScaleAspectFill;
    _thumb.userInteractionEnabled = NO;
    [_gallery addSubview:_thumb];

    _retake = [ExteriaStoryRoundButton(ExteriaSymbolClose, SIDE_BUTTON, glass, [UIColor whiteColor], NSLocalizedString(@"story.camera.retake", nil)) retain];
    [_retake addTarget:self action:@selector(retakeTapped) forControlEvents:UIControlEventTouchUpInside];
    _retake.hidden = YES;
    [root addSubview:_retake];
    _publish = [ExteriaStoryRoundButton(ExteriaSymbolCheck, SHUTTER, [UIColor whiteColor], [UIColor blackColor], NSLocalizedString(@"story.camera.publish", nil)) retain];
    [_publish addTarget:self action:@selector(publishTapped) forControlEvents:UIControlEventTouchUpInside];
    _publish.hidden = YES;
    [root addSubview:_publish];
}

/* the four cells of the grid switch, lit when the grid is on */
- (UIImage *)gridIconLit:(BOOL)lit {
    CGFloat side = 28;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    UIColor *ink = lit ? [UIColor colorWithRed:1 green:0.85 blue:0.3 alpha:1] : [UIColor whiteColor];
    [ink setStroke];
    UIBezierPath *frame = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 3, side - 6, side - 6) cornerRadius:3];
    frame.lineWidth = 2;
    [frame stroke];
    UIBezierPath *cross = [UIBezierPath bezierPath];
    [cross moveToPoint:CGPointMake(side / 2, 3)];
    [cross addLineToPoint:CGPointMake(side / 2, side - 3)];
    [cross moveToPoint:CGPointMake(3, side / 2)];
    [cross addLineToPoint:CGPointMake(side - 3, side / 2)];
    cross.lineWidth = 2;
    [cross stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = MAX(insets.top, 0), bottom = MAX(insets.bottom, 0);
    _stage.frame = CGRectMake(0, top, width, MAX(0, bounds.size.height - top - bottom - BOTTOM_ROW));
    _preview.frame = _stage.bounds;
    _held.frame = _stage.bounds;
    _grid.frame = _stage.bounds;
    [self drawGridLines];
    _spinner.center = _stage.center;
    _back.frame = CGRectMake(12, top + 10, 44, 44);
    _gridButton.frame = CGRectMake(width - 12 - 44, top + 10, 44, 44);
    CGFloat rowY = CGRectGetMaxY(_stage.frame) + (BOTTOM_ROW - SHUTTER) / 2;
    _shutter.frame = CGRectMake((width - SHUTTER) / 2, rowY, SHUTTER, SHUTTER);
    _publish.frame = _shutter.frame;
    CGFloat sideY = rowY + (SHUTTER - SIDE_BUTTON) / 2;
    _gallery.frame = CGRectMake(24, rowY + (SHUTTER - THUMB) / 2, THUMB, THUMB);
    _thumb.frame = _gallery.bounds;
    _flip.frame = CGRectMake(width - 24 - SIDE_BUTTON, sideY, SIDE_BUTTON, SIDE_BUTTON);
    _retake.frame = CGRectMake(24, sideY, SIDE_BUTTON, SIDE_BUTTON);
}

/* two lines each way, a third of the picture apart */
- (void)drawGridLines {
    for (CALayer *old in [[_grid.layer.sublayers copy] autorelease]) [old removeFromSuperlayer];
    CGSize size = _grid.bounds.size;
    for (int i = 1; i <= 2; ++i) {
        CALayer *vertical = [CALayer layer];
        vertical.backgroundColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
        vertical.frame = CGRectMake(floor(size.width * i / 3), 0, 1, size.height);
        [_grid.layer addSublayer:vertical];
        CALayer *horizontal = [CALayer layer];
        horizontal.backgroundColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
        horizontal.frame = CGRectMake(0, floor(size.height * i / 3), size.width, 1);
        [_grid.layer addSublayer:horizontal];
    }
}

#pragma mark lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadLatestThumbnail];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_capture) [self startCapture];
    else [self resumeCapture];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    AVCaptureSession *capture = _capture;
    if (capture) dispatch_async(_queue, ^{ [capture stopRunning]; });
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return orientation == UIInterfaceOrientationPortrait; }
- (BOOL)shouldAutorotate { return NO; }
/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return 1 << UIInterfaceOrientationPortrait; }
#pragma clang diagnostic pop

#pragma mark capture

- (void)startCapture {
    AVCaptureDevice *camera = ExteriaStoryCamera(AVCaptureDevicePositionBack);
    if (!camera) camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *input = camera ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error] : nil;
    AVCaptureSession *session = input ? [[AVCaptureSession alloc] init] : nil;
    AVCaptureStillImageOutput *still = [[AVCaptureStillImageOutput alloc] init];
    still.outputSettings = [NSDictionary dictionaryWithObject:AVVideoCodecJPEG forKey:AVVideoCodecKey];
    if (!session || ![session canAddInput:input] || ![session canAddOutput:still]) {
        NSLog(@"exteria: the story camera cannot start: %@", error);
        [session release];
        [still release];
        ExteriaShowNotice(nil, NSLocalizedString(@"story.camera.unavailable", nil));
        return;
    }
    if ([session canSetSessionPreset:AVCaptureSessionPresetPhoto]) session.sessionPreset = AVCaptureSessionPresetPhoto;
    [session addInput:input];
    [session addOutput:still];
    _capture = session;
    _input = [input retain];
    _still = still;
    _preview = [[AVCaptureVideoPreviewLayer layerWithSession:session] retain];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _preview.frame = _stage.bounds;
    [_stage.layer insertSublayer:_preview atIndex:0];
    [self resumeCapture];
}

/* startRunning blocks until the camera is up, so it never runs on the main thread */
- (void)resumeCapture {
    AVCaptureSession *capture = _capture;
    if (capture) dispatch_async(_queue, ^{ [capture startRunning]; });
}

- (void)flipTapped {
    if (!_capture || _shooting || _heldPath) return;
    AVCaptureDevicePosition target = _input.device.position == AVCaptureDevicePositionBack ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    AVCaptureDevice *camera = ExteriaStoryCamera(target);
    NSError *error = nil;
    AVCaptureDeviceInput *input = camera ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error] : nil;
    if (!input) {
        NSLog(@"exteria: the story camera did not switch: %@", error);
        return;
    }
    [_capture beginConfiguration];
    [_capture removeInput:_input];
    if ([_capture canAddInput:input]) {
        [_capture addInput:input];
        [_input release];
        _input = [input retain];
    } else {
        [_capture addInput:_input];
    }
    [_capture commitConfiguration];
}

- (void)gridTapped {
    _grid.hidden = !_grid.hidden;
    [_gridButton setImage:[self gridIconLit:!_grid.hidden] forState:UIControlStateNormal];
}

- (void)shutterTapped {
    if (_shooting || _heldPath || !_still) return;
    AVCaptureConnection *connection = [_still connectionWithMediaType:AVMediaTypeVideo];
    if (!connection) return;
    if (connection.supportsVideoOrientation) connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    _shooting = YES;
    [_spinner startAnimating];
    ExteriaWeakReference *weak = _weak;
    [_still captureStillImageAsynchronouslyFromConnection:connection completionHandler:^(CMSampleBufferRef buffer, NSError *error) {
        NSData *jpeg = buffer ? [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:buffer] : nil;
        if (!jpeg) NSLog(@"exteria: the story shot failed: %@", error);
        [jpeg retain];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSString *path = [ExteriaStoryCameraController fittedJpegPathFromData:jpeg];
            [jpeg release];
            NSString *delivered = [path retain];
            dispatch_async(dispatch_get_main_queue(), ^{
                ExteriaStoryCameraController *me = weak.target;
                [me shotWrittenAtPath:delivered];
                if (!me && delivered) [[NSFileManager defaultManager] removeItemAtPath:delivered error:NULL];
                [delivered release];
            });
            [pool drain];
        });
    }];
}

/* the shot shrunk to at most 1280 points on its long side and written as a jpeg, with the orientation drawn in; nil when it cannot be written */
+ (NSString *)fittedJpegPathFromData:(NSData *)data {
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    CGSize size = image.size;
    CGFloat longest = MAX(size.width, size.height);
    if (longest < 1) return nil;
    CGFloat scale = longest > STORY_SIDE ? STORY_SIDE / longest : 1;
    CGSize out = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
    UIGraphicsBeginImageContextWithOptions(out, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, out.width, out.height)];
    UIImage *fitted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *jpeg = UIImageJPEGRepresentation(fitted, STORY_QUALITY);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"story-%u.jpg", arc4random()]];
    if (!jpeg || ![jpeg writeToFile:path atomically:YES]) {
        NSLog(@"exteria: the story shot was not written");
        return nil;
    }
    return path;
}

- (void)shotWrittenAtPath:(NSString *)path {
    _shooting = NO;
    [_spinner stopAnimating];
    if (!path) {
        ExteriaShowNotice(nil, NSLocalizedString(@"story.camera.unavailable", nil));
        return;
    }
    _heldPath = [path copy];
    _held.image = [UIImage imageWithContentsOfFile:path];
    [self showHeld:YES];
}

/* a held shot replaces the camera controls with the ones that take it back or publish it */
- (void)showHeld:(BOOL)held {
    _held.hidden = !held;
    _retake.hidden = !held;
    _publish.hidden = !held;
    _shutter.hidden = held;
    _flip.hidden = held;
    _gallery.hidden = held;
    _gridButton.hidden = held;
}

- (void)retakeTapped {
    if (_heldPath) [[NSFileManager defaultManager] removeItemAtPath:_heldPath error:NULL];
    [_heldPath release];
    _heldPath = nil;
    _held.image = nil;
    [self showHeld:NO];
}

- (void)publishTapped {
    if (!_heldPath || !_publishHandler) return;
    /* the receiver deletes the file, so the screen lets go of it first */
    NSString *path = [_heldPath autorelease];
    _heldPath = nil;
    _publishHandler(path);
}

- (void)galleryTapped {
    if (_galleryHandler) _galleryHandler();
}

- (void)backTapped {
    if (_closeHandler) _closeHandler();
}

- (void)loadLatestThumbnail {
    if (!ExteriaPhotosAvailable()) return;
    ExteriaWeakReference *weak = _weak;
    /* the library calls back on whatever queue it likes, and the picture belongs to a view */
    ExteriaRecentPhotos(1, ^(NSArray *assets, NSString *error) {
        if (!assets.count) {
            if (error) NSLog(@"exteria: the latest photo for the story camera: %@", error);
            return;
        }
        id latest = [assets objectAtIndex:0];
        ExteriaPhotoThumbnail(latest, THUMB * 2, ^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ExteriaStoryCameraController *me = weak.target;
                if (me && image) me->_thumb.image = image;
            });
        });
    });
}

@end
