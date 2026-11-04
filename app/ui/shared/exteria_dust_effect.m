#import "exteria_dust_effect.h"

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

#import "exteria_lite_mode.h"
#import "exteria_platform.h"

/* match the exteraless Thanos shader's motion in points */
#define TIME_SCALE 1.15
#define WAVE_WIDTH 0.6
#define RAMP 0.2
#define SPEED_MIN 26.0
#define SPEED_SPREAD 26.0
#define PUSH_UP 65.0
#define PUSH_SIDE 19.0
#define PUSH_FADE 0.35
#define LIFE_MIN 0.7
#define LIFE_SPREAD 0.8
#define LIFE_DRAIN 1.2
#define FADE_AT 0.55
/* nothing is left after this much shader time: the last column starts at 0.5, ramps for 0.2 and its longest life drains in about a second */
#define END_TIME 2.4

typedef struct {
    CGFloat x, y, vx, vy, life, wave;
    CALayer *layer;
} ExteriaDustSquare;

@interface ExteriaDustPlayer : NSObject {
    CALayer *_container;
    ExteriaDustSquare *_squares;
    NSUInteger _count;
    CADisplayLink *_link;
    CFTimeInterval _last;
    double _time;
}
- (id)initWithContainer:(CALayer *)container squares:(ExteriaDustSquare *)squares count:(NSUInteger)count;
- (void)start;
@end

@implementation ExteriaDustPlayer

- (id)initWithContainer:(CALayer *)container squares:(ExteriaDustSquare *)squares count:(NSUInteger)count {
    self = [super init];
    if (!self) return nil;
    _container = [container retain];
    _squares = squares;
    _count = count;
    return self;
}

- (void)dealloc {
    [_container release];
    free(_squares);
    [super dealloc];
}

- (void)start {
    /* the display link keeps its target, which is what keeps the player alive until it ends */
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)finish {
    [_link invalidate];
    _link = nil;
    [_container removeFromSuperlayer];
}

- (void)step:(CADisplayLink *)link {
    CFTimeInterval real = _last > 0 ? link.timestamp - _last : 1.0 / 60;
    _last = link.timestamp;
    /* a frame that was held up is stepped as an ordinary one, so the squares never jump */
    if (real > 1.0 / 20) real = 1.0 / 30;
    double delta = real * TIME_SCALE;
    _time += delta;
    double effect = MAX(0, MIN(PUSH_FADE, _time)) / PUSH_FADE;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _count; ++i) {
        ExteriaDustSquare *q = &_squares[i];
        double fraction = MAX(0, MIN(RAMP, 0.1 + _time - q->wave * WAVE_WIDTH)) / RAMP;
        if (fraction > 0) {
            q->x += q->vx * delta * fraction;
            q->y += q->vy * delta * fraction;
            q->vx += PUSH_SIDE * (q->vx > 0 ? 1 : -1) * (1 - effect) * delta * fraction;
            q->vy -= PUSH_UP * delta * fraction;
            q->life = MAX(0, q->life - LIFE_DRAIN * delta * fraction);
            q->layer.position = CGPointMake(q->x, q->y);
            q->layer.opacity = (float)(MIN(FADE_AT, q->life) / FADE_AT);
        }
    }
    [CATransaction commit];
    if (_time > END_TIME) [self finish];
}

@end

UIImage *ExteriaDustSnapshot(UIView *view) {
    CGSize size = view.bounds.size;
    if (size.width < 1 || size.height < 1) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return picture;
}

static CGFloat ExteriaDustRandom(void) {
    return (CGFloat)arc4random_uniform(10001) / 10000.0f;
}

static NSUInteger ExteriaDustSquareLimit(void) {
    switch (ExteriaLiteClass()) {
    case EXTERIA_LITE_CLASS_LOW: return 70;
    case EXTERIA_LITE_CLASS_AVERAGE: return 140;
    default: return 240;
    }
}

static void ExteriaDustDisperseLayers(UIImage *picture, CGRect frame, UIView *host) {
    if (!picture || !host.window || ![UIView areAnimationsEnabled] || ExteriaReduceMotionEnabled()) return;
    CGImageRef image = picture.CGImage;
    if (!image || frame.size.width < 1 || frame.size.height < 1) return;
    CGFloat side = MAX(4, ceil(sqrt(frame.size.width * frame.size.height / (CGFloat)ExteriaDustSquareLimit())));
    NSUInteger columns = (NSUInteger)ceil(frame.size.width / side), rows = (NSUInteger)ceil(frame.size.height / side);
    ExteriaDustSquare *squares = calloc(columns * rows, sizeof(*squares));
    if (!squares) return;
    CALayer *container = [CALayer layer];
    container.frame = frame;
    container.masksToBounds = NO;
    NSUInteger count = 0;
    for (NSUInteger row = 0; row < rows; ++row) {
        for (NSUInteger column = 0; column < columns; ++column) {
            CGFloat x = column * side, y = row * side;
            CGFloat width = MIN(side, frame.size.width - x), height = MIN(side, frame.size.height - y);
            CALayer *square = [CALayer layer];
            square.bounds = CGRectMake(0, 0, width, height);
            square.position = CGPointMake(x + width / 2, y + height / 2);
            square.contents = (id)image;
            square.contentsScale = picture.scale;
            square.contentsRect = CGRectMake(x / frame.size.width, y / frame.size.height, width / frame.size.width, height / frame.size.height);
            /* a square moves by its own steps, and an implicit animation on each would trail behind the display link */
            square.actions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"opacity", nil];
            [container addSublayer:square];
            CGFloat direction = ExteriaDustRandom() * (CGFloat)(2 * M_PI);
            CGFloat speed = SPEED_MIN + SPEED_SPREAD * ExteriaDustRandom();
            ExteriaDustSquare *q = &squares[count++];
            q->x = square.position.x;
            q->y = square.position.y;
            q->vx = cos(direction) * speed;
            q->vy = sin(direction) * speed;
            q->life = (LIFE_MIN + LIFE_SPREAD * ExteriaDustRandom()) / TIME_SCALE;
            q->wave = (x + width / 2) / frame.size.width;
            q->layer = square;
        }
    }
    [host.layer addSublayer:container];
    ExteriaDustPlayer *player = [[[ExteriaDustPlayer alloc] initWithContainer:container squares:squares count:count] autorelease];
    [player start];
}


/* ---- the fine dust: thousands of one pixel sprites, moved by the same rules as the layers above and drawn by one GL view over the host ---- */

static NSUInteger ExteriaDustParticleLimit(void) {
    switch (ExteriaLiteClass()) {
    case EXTERIA_LITE_CLASS_LOW: return 16000;
    case EXTERIA_LITE_CLASS_AVERAGE: return 32000;
    default: return 60000;
    }
}

@interface ExteriaDustRun : NSObject {
  @public
    GLuint texture;
    NSUInteger count;
    float *x, *y, *vx, *vy, *life, *u, *v, *wave;
    float originX, originY, spriteSize, uvWidth, uvHeight;
    double time;
}
@end
@implementation ExteriaDustRun
- (void)dealloc {
    free(x); free(y); free(vx); free(vy); free(life); free(u); free(v); free(wave);
    [super dealloc];
}
@end

@interface ExteriaDustView : UIView {
    EAGLContext *_context;
    GLuint _framebuffer, _renderbuffer, _program;
    GLint _sizeUniform, _uvSizeUniform;
    GLsizei _pixelWidth, _pixelHeight;
    NSMutableArray *_runs;
    CADisplayLink *_link;
    CFTimeInterval _last;
    float *_vertices;
    NSUInteger _capacity;
}
- (BOOL)setUp;
- (BOOL)addPicture:(UIImage *)picture frame:(CGRect)frame;
@end

static GLuint ExteriaDustShader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) { glDeleteShader(shader); return 0; }
    return shader;
}

@implementation ExteriaDustView

+ (Class)layerClass { return [CAEAGLLayer class]; }

- (void)dealloc {
    [self tearDown];
    [_runs release];
    [super dealloc];
}

- (BOOL)setUp {
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
    layer.opaque = NO;
    layer.contentsScale = ExteriaScreenScale();
    layer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking,
                                kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_context || ![EAGLContext setCurrentContext:_context]) return NO;
    glGenFramebuffers(1, &_framebuffer);
    glGenRenderbuffers(1, &_renderbuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    if (![_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer]) return NO;
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbuffer);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_pixelWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_pixelHeight);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE || _pixelWidth < 1 || _pixelHeight < 1) return NO;
    GLuint vertex = ExteriaDustShader(GL_VERTEX_SHADER,
        "attribute vec2 aPos; attribute vec2 aUV; attribute float aAlpha; uniform float uSize;\n"
        "varying vec2 vUV; varying float vAlpha;\n"
        "void main() { gl_Position = vec4(aPos, 0.0, 1.0); gl_PointSize = uSize; vUV = aUV; vAlpha = aAlpha; }");
    GLuint fragment = ExteriaDustShader(GL_FRAGMENT_SHADER,
        "#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#else\nprecision mediump float;\n#endif\n"
        "uniform sampler2D uTex; uniform vec2 uUVSize; varying vec2 vUV; varying float vAlpha;\n"
        "void main() { if (vAlpha <= 0.0) discard; gl_FragColor = texture2D(uTex, vUV + gl_PointCoord * uUVSize) * vAlpha; }");
    if (!vertex || !fragment) return NO;
    _program = glCreateProgram();
    glAttachShader(_program, vertex);
    glAttachShader(_program, fragment);
    glBindAttribLocation(_program, 0, "aPos");
    glBindAttribLocation(_program, 1, "aUV");
    glBindAttribLocation(_program, 2, "aAlpha");
    glLinkProgram(_program);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    GLint linked = 0;
    glGetProgramiv(_program, GL_LINK_STATUS, &linked);
    if (!linked) return NO;
    _sizeUniform = glGetUniformLocation(_program, "uSize");
    _uvSizeUniform = glGetUniformLocation(_program, "uUVSize");
    glUniform1i(glGetUniformLocation(_program, "uTex"), 0);
    _runs = [[NSMutableArray alloc] init];
    return YES;
}

- (void)tearDown {
    [_link invalidate]; _link = nil;
    if (_context && [EAGLContext setCurrentContext:_context]) {
        for (ExteriaDustRun *run in _runs) if (run->texture) glDeleteTextures(1, &run->texture);
        if (_program) glDeleteProgram(_program);
        if (_framebuffer) glDeleteFramebuffers(1, &_framebuffer);
        if (_renderbuffer) glDeleteRenderbuffers(1, &_renderbuffer);
        [EAGLContext setCurrentContext:nil];
    }
    _program = _framebuffer = _renderbuffer = 0;
    [_runs removeAllObjects];
    [_context release]; _context = nil;
    free(_vertices); _vertices = NULL;
}

- (BOOL)addPicture:(UIImage *)picture frame:(CGRect)frame {
    CGFloat scale = ExteriaScreenScale();
    GLsizei width = (GLsizei)ceil(frame.size.width * scale), height = (GLsizei)ceil(frame.size.height * scale);
    if (width < 1 || height < 1 || width > 2048 || height > 2048 || !picture.CGImage) return NO;
    if (![EAGLContext setCurrentContext:_context]) return NO;
    void *pixels = calloc((size_t)width * height, 4);
    if (!pixels) return NO;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, (size_t)width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) { free(pixels); return NO; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), picture.CGImage);
    CGContextRelease(context);
    ExteriaDustRun *run = [[[ExteriaDustRun alloc] init] autorelease];
    glGenTextures(1, &run->texture);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, run->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    free(pixels);
    /* the grid of the android effect: about one particle for each pixel, at most the limit of the device */
    NSUInteger want = MAX((NSUInteger)10, MIN((NSUInteger)width * (NSUInteger)height, ExteriaDustParticleLimit()));
    double aspect = (double)width / height;
    NSUInteger rows = MAX((NSUInteger)1, (NSUInteger)llround(sqrt(want / aspect))), columns = (NSUInteger)llround((double)want / rows);
    while (columns * rows < want) { if ((double)columns / rows < aspect) ++columns; else ++rows; }
    NSUInteger count = columns * rows;
    run->count = count;
    run->x = malloc(count * sizeof(float)); run->y = malloc(count * sizeof(float));
    run->vx = malloc(count * sizeof(float)); run->vy = malloc(count * sizeof(float));
    run->life = malloc(count * sizeof(float)); run->wave = malloc(count * sizeof(float));
    run->u = malloc(count * sizeof(float)); run->v = malloc(count * sizeof(float));
    if (!run->x || !run->y || !run->vx || !run->vy || !run->life || !run->wave || !run->u || !run->v) { glDeleteTextures(1, &run->texture); return NO; }
    float cell = MAX((float)width / columns, (float)height / rows);
    run->spriteSize = cell + 1;
    run->uvWidth = (cell + 1) / width;
    run->uvHeight = (cell + 1) / height;
    run->originX = frame.origin.x;
    run->originY = frame.origin.y;
    for (NSUInteger i = 0; i < count; ++i) {
        float cu = (float)(i % columns) / columns, cv = (float)(i / columns) / rows;
        run->u[i] = cu; run->v[i] = cv; run->wave[i] = cu;
        run->x[i] = (cu + 0.5f / columns) * frame.size.width;
        run->y[i] = (cv + 0.5f / rows) * frame.size.height;
        float direction = ExteriaDustRandom() * (float)(2 * M_PI), speed = SPEED_MIN + SPEED_SPREAD * ExteriaDustRandom();
        run->vx[i] = cosf(direction) * speed;
        run->vy[i] = sinf(direction) * speed;
        run->life[i] = (LIFE_MIN + LIFE_SPREAD * ExteriaDustRandom()) / TIME_SCALE;
    }
    [_runs addObject:run];
    if (!_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _last = 0;
    }
    [self draw];
    return YES;
}

- (void)step:(CADisplayLink *)link {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) { [self finish]; return; }
    CFTimeInterval real = _last > 0 ? link.timestamp - _last : 1.0 / 60;
    _last = link.timestamp;
    if (real > 1.0 / 20) real = 1.0 / 30;
    float delta = (float)(real * TIME_SCALE);
    for (ExteriaDustRun *run in _runs) {
        run->time += delta;
        float effect = (float)(MAX(0.0, MIN(PUSH_FADE, run->time)) / PUSH_FADE);
        for (NSUInteger i = 0; i < run->count; ++i) {
            float fraction = (float)(MAX(0.0, MIN(RAMP, 0.1 + run->time - run->wave[i] * WAVE_WIDTH)) / RAMP);
            if (fraction <= 0) continue;
            float step = delta * fraction;
            run->x[i] += run->vx[i] * step;
            run->y[i] += run->vy[i] * step;
            run->vx[i] += PUSH_SIDE * (run->vx[i] > 0 ? 1 : -1) * (1 - effect) * step;
            run->vy[i] -= PUSH_UP * step;
            float life = run->life[i] - LIFE_DRAIN * step;
            run->life[i] = life > 0 ? life : 0;
        }
    }
    for (NSInteger i = (NSInteger)_runs.count - 1; i >= 0; --i) {
        ExteriaDustRun *run = [_runs objectAtIndex:(NSUInteger)i];
        if (run->time > END_TIME) {
            [EAGLContext setCurrentContext:_context];
            glDeleteTextures(1, &run->texture);
            [_runs removeObjectAtIndex:(NSUInteger)i];
        }
    }
    if (!_runs.count) { [self finish]; return; }
    [self draw];
}

- (void)finish {
    [self tearDown];
    [self removeFromSuperview];
}

- (void)draw {
    if (![EAGLContext setCurrentContext:_context]) return;
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glViewport(0, 0, _pixelWidth, _pixelHeight);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    glUseProgram(_program);
    float width = (float)self.bounds.size.width, height = (float)self.bounds.size.height;
    for (ExteriaDustRun *run in _runs) {
        if (run->count > _capacity) {
            free(_vertices);
            _capacity = run->count;
            _vertices = malloc(_capacity * 5 * sizeof(float));
            if (!_vertices) { _capacity = 0; return; }
        }
        float *out = _vertices;
        NSUInteger shown = 0;
        for (NSUInteger i = 0; i < run->count; ++i) {
            if (run->life[i] <= 0) continue;
            float alpha = MIN(FADE_AT, run->life[i]) / (float)FADE_AT;
            out[0] = (run->originX + run->x[i]) / width * 2 - 1;
            out[1] = 1 - (run->originY + run->y[i]) / height * 2;
            out[2] = run->u[i]; out[3] = run->v[i]; out[4] = alpha;
            out += 5; ++shown;
        }
        if (!shown) continue;
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, run->texture);
        glUniform1f(_sizeUniform, run->spriteSize);
        glUniform2f(_uvSizeUniform, run->uvWidth, run->uvHeight);
        glEnableVertexAttribArray(0); glEnableVertexAttribArray(1); glEnableVertexAttribArray(2);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 20, _vertices);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 20, _vertices + 2);
        glVertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE, 20, _vertices + 4);
        glDrawArrays(GL_POINTS, 0, (GLsizei)shown);
    }
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

@end

void ExteriaDustDisperse(UIImage *picture, CGRect frame, UIView *host) {
    if (!picture || !host.window || ![UIView areAnimationsEnabled] || ExteriaReduceMotionEnabled()) return;
    ExteriaDustView *view = nil;
    for (UIView *sub in host.subviews) if ([sub isKindOfClass:[ExteriaDustView class]]) { view = (ExteriaDustView *)sub; break; }
    BOOL created = NO;
    if (!view) {
        view = [[[ExteriaDustView alloc] initWithFrame:host.bounds] autorelease];
        if (![view setUp]) { ExteriaDustDisperseLayers(picture, frame, host); return; }
        [host addSubview:view];
        created = YES;
    }
    CGRect local = CGRectOffset(frame, -host.bounds.origin.x, -host.bounds.origin.y);
    if (![view addPicture:picture frame:local]) {
        if (created) [view removeFromSuperview];
        ExteriaDustDisperseLayers(picture, frame, host);
    }
}
