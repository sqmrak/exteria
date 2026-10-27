#import "exteria_lottie.h"

#import <zlib.h>
#import <rlottie_capi.h>

/* sticker files in the bundle are a few dozen kilobytes; anything larger is not one of ours */
#define EXTERIA_TGS_MAX_PACKED (512 * 1024)
#define EXTERIA_TGS_MAX_JSON (4 * 1024 * 1024)
#define EXTERIA_LOTTIE_MAX_FRAMES 600
#define EXTERIA_LOTTIE_MAX_SIDE 512

static void ExteriaReleaseBuffer(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    free((void *)data);
}

static NSData *ExteriaInflateTGS(NSData *packed) {
    z_stream stream;
    NSMutableData *json = [NSMutableData data];
    uint8_t chunk[16 * 1024];
    int status;
    if (!packed.length || packed.length > EXTERIA_TGS_MAX_PACKED) return nil;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, MAX_WBITS + 16) != Z_OK) return nil;
    stream.next_in = (Bytef *)packed.bytes;
    stream.avail_in = (uInt)packed.length;
    do {
        stream.next_out = chunk;
        stream.avail_out = sizeof(chunk);
        status = inflate(&stream, Z_NO_FLUSH);
        if (status != Z_OK && status != Z_STREAM_END) break;
        if (json.length + (sizeof(chunk) - stream.avail_out) >= EXTERIA_TGS_MAX_JSON) {
            status = Z_DATA_ERROR;
            break;
        }
        [json appendBytes:chunk length:sizeof(chunk) - stream.avail_out];
    } while (status != Z_STREAM_END);
    inflateEnd(&stream);
    if (status != Z_STREAM_END) return nil;
    /* rlottie reads the document as a C string */
    [json appendBytes:"" length:1];
    return json;
}

/* every animation parses and renders on one serial queue: old devices have one or two cores, and
   rlottie keeps shared state (gradient cache, rasteriser) that two animations should not hit at once */
static dispatch_queue_t ExteriaLottieQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("exteria.lottie", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@interface ExteriaLottie () {
    Lottie_Animation *_animation;
    NSLock *_lock;
    CGColorSpaceRef _colorSpace;
    CGImageRef _finished;
    BOOL _ready;
    BOOL _failed;
    BOOL _busy;
    BOOL _invalid;
}
- (id)initWithJSON:(NSData *)json key:(NSString *)key;
- (CGImageRef)newImageForFrame:(NSUInteger)frame side:(NSUInteger)side;
@end

@implementation ExteriaLottie

@synthesize frameCount = _frameCount;
@synthesize framesPerSecond = _framesPerSecond;

+ (ExteriaLottie *)animationNamed:(NSString *)name {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"tgs"];
    NSData *packed = path ? [NSData dataWithContentsOfFile:path] : nil;
    return [self animationWithPackedData:packed key:name];
}

+ (ExteriaLottie *)animationWithPackedData:(NSData *)packed key:(NSString *)key {
    NSData *json = ExteriaInflateTGS(packed);
    if (!json) {
        NSLog(@"exteria: animation %@ did not load", key);
        return nil;
    }
    return [[[ExteriaLottie alloc] initWithJSON:json key:key] autorelease];
}

- (id)initWithJSON:(NSData *)json key:(NSString *)key {
    self = [super init];
    if (!self) return nil;
    _lock = [[NSLock alloc] init];
    _colorSpace = CGColorSpaceCreateDeviceRGB();
    /* the block retains self, and json and key stay alive through their own copies */
    dispatch_async(ExteriaLottieQueue(), ^{
        Lottie_Animation *animation = lottie_animation_from_data((const char *)json.bytes, key.UTF8String, "");
        size_t total = animation ? lottie_animation_get_totalframe(animation) : 0;
        double rate = animation ? lottie_animation_get_framerate(animation) : 0;
        BOOL usable = animation && total >= 2 && total <= EXTERIA_LOTTIE_MAX_FRAMES && rate >= 1 && rate <= 120;
        if (animation && !usable) {
            lottie_animation_destroy(animation);
            animation = NULL;
        }
        if (!usable) NSLog(@"exteria: animation %@ is not a usable lottie document", key);
        [_lock lock];
        _animation = animation;
        _frameCount = usable ? total : 0;
        _framesPerSecond = usable ? rate : 0;
        _ready = usable;
        _failed = !usable;
        [_lock unlock];
    });
    return self;
}

- (BOOL)ready {
    [_lock lock];
    BOOL ready = _ready;
    [_lock unlock];
    return ready;
}

- (BOOL)failed {
    [_lock lock];
    BOOL failed = _failed;
    [_lock unlock];
    return failed;
}

- (NSTimeInterval)duration {
    return _framesPerSecond > 0 ? _frameCount / _framesPerSecond : 0;
}

/* renders on the shared queue; the caller owns the image */
- (CGImageRef)newImageForFrame:(NSUInteger)frame side:(NSUInteger)side {
    uint32_t *pixels = calloc(side * side, sizeof(uint32_t));
    CGImageRef image = NULL;
    if (!pixels) return NULL;
    lottie_animation_render(_animation, frame, pixels, side, side, side * 4);
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, side * side * 4, ExteriaReleaseBuffer);
    if (provider) {
        /* rlottie writes premultiplied bgra, which is little endian alpha first */
        image = CGImageCreate(side, side, 8, 32, side * 4, _colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
                              provider, NULL, false, kCGRenderingIntentDefault);
        CGDataProviderRelease(provider);
    } else {
        free(pixels);
    }
    return image;
}

- (void)renderStillAtSide:(NSUInteger)side completion:(void (^)(CGImageRef image))completion {
    void (^done)(CGImageRef) = [completion copy];
    if (side > EXTERIA_LOTTIE_MAX_SIDE) side = EXTERIA_LOTTIE_MAX_SIDE;
    /* the document is parsed by a block queued before this one, so _animation is set by the time this runs */
    dispatch_async(ExteriaLottieQueue(), ^{
        CGImageRef image = _animation && side >= 8 ? [self newImageForFrame:0 side:side] : NULL;
        dispatch_async(dispatch_get_main_queue(), ^{
            done(image);
            if (image) CGImageRelease(image);
            [done release];
        });
    });
}

- (BOOL)requestFrame:(NSUInteger)frame side:(NSUInteger)side {
    if (side < 8) return NO;
    if (side > EXTERIA_LOTTIE_MAX_SIDE) side = EXTERIA_LOTTIE_MAX_SIDE;
    [_lock lock];
    BOOL refused = !_ready || _busy || _invalid;
    NSUInteger last = _frameCount - 1;
    if (!refused) _busy = YES;
    [_lock unlock];
    if (refused) return NO;
    if (frame > last) frame = last;
    /* the copied block retains self, so the handle never dies mid frame */
    dispatch_async(ExteriaLottieQueue(), ^{
        CGImageRef image = [self newImageForFrame:frame side:side];
        [_lock lock];
        _busy = NO;
        if (image && !_invalid) {
            if (_finished) CGImageRelease(_finished);
            _finished = image;
        } else if (image) {
            CGImageRelease(image);
        }
        [_lock unlock];
    });
    return YES;
}

- (CGImageRef)copyFinishedFrame {
    [_lock lock];
    CGImageRef image = _finished;
    _finished = NULL;
    [_lock unlock];
    return image;
}

- (void)invalidate {
    [_lock lock];
    _invalid = YES;
    if (_finished) CGImageRelease(_finished);
    _finished = NULL;
    [_lock unlock];
}

- (void)dealloc {
    if (_finished) CGImageRelease(_finished);
    if (_animation) lottie_animation_destroy(_animation);
    if (_colorSpace) CGColorSpaceRelease(_colorSpace);
    [_lock release];
    [super dealloc];
}

@end
