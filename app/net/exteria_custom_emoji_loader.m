#import "exteria_custom_emoji_loader.h"

#import "exteria_custom_emoji.h"
#import "exteria_image_decoder.h"
#import "exteria_lottie.h"
#import "exteria_video_sticker.h"
#import "exteria_platform.h"

#define DOCUMENTS_PER_CALL 100

/* the server thumbnail stands in when the full document cannot be rendered */
static void ExteriaLoadPreview(ExteriaCustomEmojiDocument *document, ExteriaMediaCache *media, void (^done)(UIImage *image)) {
    if (!document.preview) {
        done(nil);
        return;
    }
    [media loadImageForFile:document.preview maxSide:[ExteriaCustomEmoji pictureSide] completion:done];
}

static void ExteriaLoadPicture(ExteriaCustomEmojiDocument *document, ExteriaMediaCache *media, void (^done)(UIImage *image)) {
    CGFloat side = [ExteriaCustomEmoji pictureSide];
    [media loadImageForFile:document.file maxSide:side completion:^(UIImage *image) {
        if (image) done(image);
        else ExteriaLoadPreview(document, media, done);
    }];
}

#define ANIMATION_FRAMES_MAX 36
#define ANIMATION_FPS_MAX 20.0

/* renders the frames of one animated emoji, one at a time on the lottie queue, and hands them to ExteriaCustomEmoji when the last is in: the first frame is what the line
   of text showed already, so the picture never goes blank while the others come. the builder keeps itself alive until it is done */
/* at most three animations render at once: a screen full of animated emoji would otherwise hold as many lottie renderers as it has kinds of emoji */
#define BUILDERS_ACTIVE_MAX 3
static NSMutableArray *sPendingBuilders;
static NSUInteger sActiveBuilders;
static void ExteriaEmojiBuilderEnded(void);

@interface ExteriaEmojiFrameBuilder : NSObject {
    long long _document;
    /* the frames come from a lottie file or from a webm one, through the same interface */
    id<ExteriaFrameAnimation> _lottie;
    NSMutableArray *_frames;
    NSUInteger _step;
    NSUInteger _next;
    NSUInteger _side;
    void (^_landed)(void);
}
/* landed runs on the main thread once the frames are in, so the places that drew the still picture draw the motion */
@property (nonatomic, copy) void (^landed)(void);
- (id)initWithDocument:(long long)document data:(NSData *)data key:(NSString *)key;
- (void)start;
@end

@implementation ExteriaEmojiFrameBuilder

@synthesize landed = _landed;

- (id)initWithDocument:(long long)document data:(NSData *)data key:(NSString *)key {
    self = [super init];
    if (!self) return nil;
    _document = document;
    _lottie = [(ExteriaFileFormatOfData(data) == ExteriaFileFormatMatroska ? (id<ExteriaFrameAnimation>)[ExteriaVideoSticker animationWithPackedData:data key:key]
                                                                             : (id<ExteriaFrameAnimation>)[ExteriaLottie animationWithPackedData:data key:key]) retain];
    if (!_lottie) {
        [self release];
        return nil;
    }
    _frames = [[NSMutableArray alloc] init];
    _side = (NSUInteger)ceil([ExteriaCustomEmoji pictureSide] / 2.0);
    return self;
}

- (void)dealloc {
    [_landed release];
    [_lottie invalidate];
    [_lottie release];
    [_frames release];
    [super dealloc];
}

- (void)start {
    [self retain];
    [self wait];
}

- (void)finish {
    ExteriaEmojiBuilderEnded();
    [self autorelease];
}

/* the parse runs on the render queue, so the counts are not known at once */
- (void)wait {
    if (_lottie.failed) {
        NSLog(@"exteria: the animation of custom emoji %lld could not be parsed", _document);
        [self finish];
        return;
    }
    if (!_lottie.ready) {
        [self performSelector:@selector(wait) withObject:nil afterDelay:0.02];
        return;
    }
    NSUInteger count = _lottie.frameCount;
    double fps = _lottie.framesPerSecond;
    if (count < 2 || fps <= 0) {
        [self finish];
        return;
    }
    /* every few frames, enough to keep the motion at about twenty a second without holding all of a long animation */
    _step = MAX((NSUInteger)ceil(fps / ANIMATION_FPS_MAX), (NSUInteger)ceil((double)count / ANIMATION_FRAMES_MAX));
    _next = 0;
    [self renderNext];
}

- (void)renderNext {
    if (_next >= _lottie.frameCount) {
        double fps = _lottie.framesPerSecond;
        [ExteriaCustomEmoji setAnimationFrames:_frames duration:(double)_lottie.frameCount / fps forDocument:_document];
        if (_landed) _landed();
        [self finish];
        return;
    }
    if (![_lottie requestFrame:_next side:_side]) {
        [self performSelector:@selector(renderNext) withObject:nil afterDelay:0.01];
        return;
    }
    [self collect];
}

- (void)collect {
    CGImageRef image = [_lottie copyFinishedFrame];
    if (!image) {
        if (_lottie.failed) {
            [self finish];
            return;
        }
        [self performSelector:@selector(collect) withObject:nil afterDelay:0.008];
        return;
    }
    UIImage *frame = [UIImage imageWithCGImage:image scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(image);
    UIImage *fitted = ExteriaFitEmojiImage(frame);
    [_frames addObject:fitted ? fitted : frame];
    _next += _step;
    [self renderNext];
}

@end

static void ExteriaEmojiBuilderEnded(void) {
    if (sActiveBuilders) --sActiveBuilders;
    while (sActiveBuilders < BUILDERS_ACTIVE_MAX && sPendingBuilders.count) {
        ExteriaEmojiFrameBuilder *next = [[sPendingBuilders objectAtIndex:0] retain];
        [sPendingBuilders removeObjectAtIndex:0];
        ++sActiveBuilders;
        [next start];
        [next release];
    }
}

static void ExteriaEmojiBuilderSubmit(ExteriaEmojiFrameBuilder *builder) {
    if (!sPendingBuilders) sPendingBuilders = [[NSMutableArray alloc] init];
    if (sActiveBuilders < BUILDERS_ACTIVE_MAX) {
        ++sActiveBuilders;
        [builder start];
        return;
    }
    [sPendingBuilders addObject:builder];
}

/* an animated emoji gets its frames after its picture landed: a lottie one from its file, a webm one (what most animated emoji of the other clients are) from the
   video decoder of the app, a few frames a second. the thumbnail stays until the frames are in */
static void ExteriaAnimateDocument(ExteriaCustomEmojiDocument *document, ExteriaMediaCache *media, void (^landed)(void)) {
    if ((document.format != EXTERIA_STICKER_ANIMATED && document.format != EXTERIA_STICKER_VIDEO) || !document.file || ExteriaReduceMotionEnabled()) return;
    long long identifier = document.documentId;
    if ([ExteriaCustomEmoji hasAnimationForDocument:identifier]) return;
    NSString *key = document.file.key;
    [media loadDataForFile:document.file completion:^(NSData *data) {
        if (!data || [ExteriaCustomEmoji hasAnimationForDocument:identifier]) return;
        ExteriaFileFormat format = ExteriaFileFormatOfData(data);
        if (format != ExteriaFileFormatGzip && format != ExteriaFileFormatMatroska) return;
        ExteriaEmojiFrameBuilder *builder = [[[ExteriaEmojiFrameBuilder alloc] initWithDocument:identifier data:data key:key] autorelease];
        builder.landed = landed;
        if (builder) ExteriaEmojiBuilderSubmit(builder);
    }];
}

@implementation ExteriaCustomEmojiLoader

+ (void)loadPicturesOfDocuments:(NSArray *)documents media:(ExteriaMediaCache *)media picture:(void (^)(void))picture {
    void (^landed)(void) = [picture copy];
    for (ExteriaCustomEmojiDocument *document in documents) {
        long long identifier = document.documentId;
        if (![ExteriaCustomEmoji needsLoad:identifier]) continue;
        [ExteriaCustomEmoji beginLoad:identifier];
        ExteriaLoadPicture(document, media, ^(UIImage *image) {
            [ExteriaCustomEmoji finishLoad:identifier image:image];
            if (image && landed) landed();
        });
    }
    [landed release];
}

+ (void)loadDocuments:(NSArray *)documentIds session:(ExteriaSession *)session media:(ExteriaMediaCache *)media
            documents:(void (^)(NSArray *))documents picture:(void (^)(void))picture {
    void (^knownDocuments)(NSArray *) = [documents copy];
    void (^landed)(void) = [picture copy];
    NSMutableArray *wanted = [NSMutableArray array];
    for (NSNumber *key in documentIds) {
        long long document = key.longLongValue;
        if (![ExteriaCustomEmoji needsLoad:document]) continue;
        [ExteriaCustomEmoji beginLoad:document];
        [wanted addObject:key];
    }
    for (NSUInteger from = 0; from < wanted.count; from += DOCUMENTS_PER_CALL) {
        NSArray *batch = [wanted subarrayWithRange:NSMakeRange(from, MIN((NSUInteger)DOCUMENTS_PER_CALL, wanted.count - from))];
        [session loadCustomEmojiDocuments:batch completion:^(NSArray *answered, NSString *errorName) {
            if (!answered) {
                /* a failed call says nothing about the documents, so a later screen asks again */
                NSLog(@"exteria: custom emoji not loaded: %@", errorName);
                for (NSNumber *key in batch) [ExteriaCustomEmoji abandonLoad:key.longLongValue];
                return;
            }
            NSMutableSet *known = [NSMutableSet set];
            for (ExteriaCustomEmojiDocument *document in answered) [known addObject:[NSNumber numberWithLongLong:document.documentId]];
            /* a document the server did not answer for is left alone for a minute */
            for (NSNumber *key in batch) {
                if (![known containsObject:key]) [ExteriaCustomEmoji finishLoad:key.longLongValue image:nil];
            }
            if (knownDocuments) knownDocuments(answered);
            for (ExteriaCustomEmojiDocument *document in answered) {
                long long identifier = document.documentId;
                ExteriaLoadPicture(document, media, ^(UIImage *image) {
                    [ExteriaCustomEmoji finishLoad:identifier image:image];
                    if (image) ExteriaAnimateDocument(document, media, landed);
                    if (image && landed) landed();
                });
            }
        }];
    }
    [knownDocuments release];
    [landed release];
}

@end
