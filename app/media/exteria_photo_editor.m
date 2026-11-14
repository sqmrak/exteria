#import "exteria_slider.h"
#import "exteria_alert_view.h"
#import "exteria_photo_editor.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_classic_chrome.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_editor_chrome.h"
#import "exteria_photo_edit.h"
#import "exteria_photo_zoom.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"

#define EDIT_OPERATIONS_MAX 32
#define EDIT_POINTS_MAX 4096
#define EDIT_PREVIEW_SIDE_MAX 1280

static NSString *const ExteriaPhotoToolNames[EXTERIA_PHOTO_TOOLS] = {
    @"media.exposure", @"media.contrast", @"media.saturation", @"media.warmth", @"media.fade",
    @"media.shadows", @"media.highlights", @"media.vignette", @"media.grain", @"media.sharpen"
};

static CGRect ExteriaPhotoFit(CGSize image, CGRect bounds) {
    if (image.width < 1 || image.height < 1 || bounds.size.width < 1 || bounds.size.height < 1) return CGRectZero;
    CGFloat scale = MIN(bounds.size.width / image.width, bounds.size.height / image.height);
    CGSize size = CGSizeMake(image.width * scale, image.height * scale);
    return CGRectMake(CGRectGetMidX(bounds) - size.width / 2, CGRectGetMidY(bounds) - size.height / 2, size.width, size.height);
}

static UIImage *ExteriaPhotoAdjustment(UIImage *image, NSData *settings) {
    if (settings.length != sizeof(exteria_photo_adjustments)) return nil;
    size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    if (!width || !height || width > EXTERIA_PHOTO_SIDE_MAX || height > EXTERIA_PHOTO_SIDE_MAX) return nil;
    size_t stride = width * 4, capacity = stride * height;
    uint8_t *pixels = calloc(1, capacity);
    if (!pixels) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, stride, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    UIImage *result = nil;
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image.CGImage);
        if (exteria_photo_adjust(pixels, capacity, (uint32_t)width, (uint32_t)height, stride, settings.bytes) == EXTERIA_OK) {
            CGImageRef adjusted = CGBitmapContextCreateImage(context);
            if (adjusted) { result = [UIImage imageWithCGImage:adjusted]; CGImageRelease(adjusted); }
        }
        CGContextRelease(context);
    }
    free(pixels);
    return result;
}

static void ExteriaPhotoDrawStroke(NSDictionary *operation, CGSize size) {
    NSArray *points = [operation objectForKey:@"points"];
    if (!points.count) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat width = [[operation objectForKey:@"width"] doubleValue] * MIN(size.width, size.height);
    UIColor *color = [operation objectForKey:@"color"];
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, width);
    CGContextSetLineCap(context, kCGLineCapRound); CGContextSetLineJoin(context, kCGLineJoinRound);
    CGPoint first = [[points objectAtIndex:0] CGPointValue];
    BOOL arrow = [[operation objectForKey:@"arrow"] boolValue];
    if (arrow && points.count < 2) return;
    if (points.count == 1) {
        CGContextFillEllipseInRect(context, CGRectMake(first.x * size.width - width / 2, first.y * size.height - width / 2, width, width));
    } else {
        CGContextMoveToPoint(context, first.x * size.width, first.y * size.height);
        for (NSUInteger i = 1; i < points.count; ++i) {
            CGPoint point = [[points objectAtIndex:i] CGPointValue];
            CGContextAddLineToPoint(context, point.x * size.width, point.y * size.height);
        }
        CGContextStrokePath(context);
    }
    if (!arrow) return;
    /* the head follows the direction of the last stretch of the line, taken from a point far enough back that finger jitter at the tip cannot turn it */
    CGPoint last = [[points lastObject] CGPointValue];
    CGPoint tip = CGPointMake(last.x * size.width, last.y * size.height);
    CGFloat head = MAX(width * 4, MIN(size.width, size.height) * 0.05);
    CGPoint back = tip;
    BOOL found = NO;
    for (NSInteger i = (NSInteger)points.count - 2; i >= 0 && !found; --i) {
        CGPoint point = [[points objectAtIndex:(NSUInteger)i] CGPointValue];
        back = CGPointMake(point.x * size.width, point.y * size.height);
        found = hypot(tip.x - back.x, tip.y - back.y) >= head * 0.6;
    }
    CGFloat length = hypot(tip.x - back.x, tip.y - back.y);
    if (length < 1) return;
    head = MIN(head, length * 2);
    CGFloat angle = atan2(tip.y - back.y, tip.x - back.x), spread = 28 * M_PI / 180;
    CGContextMoveToPoint(context, tip.x - head * cos(angle - spread), tip.y - head * sin(angle - spread));
    CGContextAddLineToPoint(context, tip.x, tip.y);
    CGContextAddLineToPoint(context, tip.x - head * cos(angle + spread), tip.y - head * sin(angle + spread));
    CGContextStrokePath(context);
}

static CGRect ExteriaPhotoTextRect(NSDictionary *operation, CGSize size) {
    NSString *text = [operation objectForKey:@"text"];
    CGPoint point = [[operation objectForKey:@"point"] CGPointValue];
    NSNumber *storedSize = [operation objectForKey:@"size"];
    CGFloat fraction = storedSize ? [storedSize doubleValue] : 0.065;
    UIFont *font = [UIFont boldSystemFontOfSize:MAX(12, MIN(size.width, size.height) * fraction)];
    CGSize measured = [text sizeWithFont:font constrainedToSize:CGSizeMake(size.width * 0.9, size.height) lineBreakMode:UILineBreakModeWordWrap];
    return CGRectMake(MAX(0, MIN(size.width - measured.width, point.x * size.width - measured.width / 2)),
                      MAX(0, MIN(size.height - measured.height, point.y * size.height - measured.height / 2)), measured.width, measured.height);
}

/* the blur brush has one strength, the strongest the picture allows. the stroke is a brush that blurs: the picture under the stroke, and a margin of three radii round it, is blurred once, and only the stroke lets the blurred copy show. the
   work is as big as the stroke and not as the picture, which an old phone feels on a long edit */
static UIImage *ExteriaPhotoBlurStroke(UIImage *image, NSDictionary *operation) {
    NSArray *points = [operation objectForKey:@"points"];
    CGSize size = image.size;
    CGImageRef source = image.CGImage;
    if (!points.count || !source) return nil;
    size_t pixelsWide = CGImageGetWidth(source), pixelsHigh = CGImageGetHeight(source);
    if (!pixelsWide || !pixelsHigh || pixelsWide > EXTERIA_PHOTO_SIDE_MAX || pixelsHigh > EXTERIA_PHOTO_SIDE_MAX) return nil;
    CGFloat width = [[operation objectForKey:@"width"] doubleValue] * MIN(size.width, size.height);
    CGFloat left = CGFLOAT_MAX, top = CGFLOAT_MAX, right = -CGFLOAT_MAX, bottom = -CGFLOAT_MAX;
    for (NSValue *value in points) {
        CGPoint point = [value CGPointValue];
        left = MIN(left, point.x * size.width); right = MAX(right, point.x * size.width);
        top = MIN(top, point.y * size.height); bottom = MAX(bottom, point.y * size.height);
    }
    uint32_t radius = exteria_photo_blur_radius(1, (uint32_t)MIN(pixelsWide, pixelsHigh));
    exteria_photo_region region;
    if (exteria_photo_blur_region((uint32_t)pixelsWide, (uint32_t)pixelsHigh, left - width / 2, top - width / 2, right + width / 2, bottom + width / 2, radius, &region) != EXTERIA_OK) return nil;
    CGImageRef part = CGImageCreateWithImageInRect(source, CGRectMake(region.x, region.y, region.width, region.height));
    if (!part) return nil;
    size_t stride = (size_t)region.width * 4, capacity = stride * region.height;
    uint8_t *pixels = calloc(1, capacity);
    UIImage *blurred = nil;
    if (pixels) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(pixels, region.width, region.height, 8, stride, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (context) {
            CGContextDrawImage(context, CGRectMake(0, 0, region.width, region.height), part);
            exteria_photo_region whole = {0, 0, region.width, region.height};
            if (exteria_photo_blur(pixels, capacity, region.width, region.height, stride, &whole, radius) == EXTERIA_OK) {
                CGImageRef result = CGBitmapContextCreateImage(context);
                if (result) { blurred = [UIImage imageWithCGImage:result]; CGImageRelease(result); }
            }
            CGContextRelease(context);
        }
        free(pixels);
    }
    CGImageRelease(part);
    if (!blurred) return nil;
    UIGraphicsBeginImageContextWithOptions(size, YES, 1);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) { UIGraphicsEndImageContext(); return nil; }
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    CGContextSaveGState(context);
    CGPoint first = [[points objectAtIndex:0] CGPointValue];
    if (points.count == 1) {
        CGContextAddEllipseInRect(context, CGRectMake(first.x * size.width - width / 2, first.y * size.height - width / 2, width, width));
    } else {
        CGContextMoveToPoint(context, first.x * size.width, first.y * size.height);
        for (NSUInteger i = 1; i < points.count; ++i) {
            CGPoint point = [[points objectAtIndex:i] CGPointValue];
            CGContextAddLineToPoint(context, point.x * size.width, point.y * size.height);
        }
        CGContextSetLineWidth(context, width);
        CGContextSetLineCap(context, kCGLineCapRound); CGContextSetLineJoin(context, kCGLineJoinRound);
        CGContextReplacePathWithStrokedPath(context);
    }
    CGContextClip(context);
    [blurred drawInRect:CGRectMake(region.x, region.y, region.width, region.height)];
    CGContextRestoreGState(context);
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return result;
}

static UIImage *ExteriaPhotoApply(UIImage *image, NSDictionary *operation) {
    NSString *kind = [operation objectForKey:@"kind"];
    CGSize size = image.size;
    if ([kind isEqualToString:@"blur"]) return ExteriaPhotoBlurStroke(image, operation);
    if ([kind isEqualToString:@"adjust"]) return ExteriaPhotoAdjustment(image, [operation objectForKey:@"settings"]);
    if ([kind isEqualToString:@"crop"]) {
        CGRect rect = [[operation objectForKey:@"rect"] CGRectValue];
        exteria_photo_crop crop;
        if (exteria_photo_crop_pixels((uint32_t)size.width, (uint32_t)size.height, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, &crop) != EXTERIA_OK) return nil;
        CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, CGRectMake(crop.x, crop.y, crop.width, crop.height));
        if (!cropped) return nil;
        UIImage *result = [UIImage imageWithCGImage:cropped]; CGImageRelease(cropped); return result;
    }
    BOOL rotate = [kind isEqualToString:@"rotate"], flip = [kind isEqualToString:@"flip"];
    CGSize target = rotate ? CGSizeMake(size.height, size.width) : size;
    UIGraphicsBeginImageContextWithOptions(target, YES, 1);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) { UIGraphicsEndImageContext(); return nil; }
    if (rotate || flip) {
        CGContextTranslateCTM(context, target.width / 2, target.height / 2);
        if (rotate) CGContextRotateCTM(context, M_PI_2);
        if (flip) CGContextScaleCTM(context, -1, 1);
        [image drawInRect:CGRectMake(-size.width / 2, -size.height / 2, size.width, size.height)];
    } else {
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        if ([kind isEqualToString:@"stroke"]) ExteriaPhotoDrawStroke(operation, size);
        else if ([kind isEqualToString:@"text"]) {
            NSString *text = [operation objectForKey:@"text"];
            UIColor *color = [operation objectForKey:@"color"];
            NSNumber *storedSize = [operation objectForKey:@"size"];
            CGFloat fraction = storedSize ? [storedSize doubleValue] : 0.065;
            UIFont *font = [UIFont boldSystemFontOfSize:MAX(12, MIN(size.width, size.height) * fraction)];
            CGRect rect = ExteriaPhotoTextRect(operation, size);
            CGContextSetShadowWithColor(context, CGSizeMake(0, 1), 2, [UIColor blackColor].CGColor);
            [color set]; [text drawInRect:rect withFont:font lineBreakMode:UILineBreakModeWordWrap alignment:UITextAlignmentCenter];
        }
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return result;
}

static UIImage *ExteriaPhotoRender(UIImage *source, NSArray *operations, CGFloat maxSide) {
    CGFloat scale = MIN(1, maxSide / MAX(source.size.width, source.size.height));
    CGSize size = CGSizeMake(MAX(1, floor(source.size.width * scale)), MAX(1, floor(source.size.height * scale)));
    UIGraphicsBeginImageContextWithOptions(size, YES, 1);
    [source drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *image = [UIGraphicsGetImageFromCurrentImageContext() retain]; UIGraphicsEndImageContext();
    for (NSDictionary *operation in operations) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *next = [ExteriaPhotoApply(image, operation) retain];
        [image release]; image = next; [pool drain];
        if (!image) break;
    }
    return [image autorelease];
}

@interface ExteriaPhotoCanvas : UIView {
    UIImage *_image;
    CGRect _crop;
    BOOL _cropping;
    NSDictionary *_stroke;
    NSMutableArray *_pending;
    NSMutableArray *_trail;
    CGRect _selection;
    UIEdgeInsets _insets;
    CGFloat _scale;
}
@property (nonatomic, retain) UIImage *image;
@property (nonatomic, assign) CGRect crop;
@property (nonatomic, assign) BOOL cropping;
@property (nonatomic, retain) NSDictionary *stroke;
/* the strokes committed since the picture on screen was rendered: a render takes a while on an old phone, and the next stroke starts before it ends */
@property (nonatomic, readonly) NSMutableArray *pending;
/* where the finger has been since it touched down, in canvas points: a pan is only recognized after about ten points of travel, and a short line never gets that far */
@property (nonatomic, readonly) NSArray *trail;
@property (nonatomic, assign) CGRect selection;
/* the room the picture keeps clear of the edges of the canvas, which is where the bars stand */
@property (nonatomic, assign) UIEdgeInsets insets;
/* how much the canvas is enlarged on screen, so a hairline stays a hairline and a handle keeps its size while the picture is zoomed */
@property (nonatomic, assign) CGFloat scale;
@property (nonatomic, readonly) CGRect imageRect;
@end
@implementation ExteriaPhotoCanvas
@synthesize image = _image, crop = _crop, cropping = _cropping, stroke = _stroke, selection = _selection, insets = _insets, scale = _scale;
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { _scale = 1; _pending = [[NSMutableArray alloc] init]; _trail = [[NSMutableArray alloc] init]; }
    return self;
}
- (void)dealloc { [_image release]; [_stroke release]; [_pending release]; [_trail release]; [super dealloc]; }
- (void)logTouches:(NSSet *)touches event:(UIEvent *)event {
    if (event.allTouches.count != 1) { [_trail removeAllObjects]; return; }
    if (_trail.count < EDIT_POINTS_MAX) [_trail addObject:[NSValue valueWithCGPoint:[[touches anyObject] locationInView:self]]];
}
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [_trail removeAllObjects];
    [self logTouches:touches event:event];
    [super touchesBegan:touches withEvent:event];
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [self logTouches:touches event:event];
    [super touchesMoved:touches withEvent:event];
}
- (CGRect)imageRect { return ExteriaPhotoFit(_image.size, UIEdgeInsetsInsetRect(self.bounds, _insets)); }
- (void)drawRect:(CGRect)rect {
    CGRect imageRect = self.imageRect;
    if (CGRectIsEmpty(imageRect)) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat unit = 1 / MAX(0.2, _scale);
    NSMutableArray *strokes = [NSMutableArray arrayWithArray:_pending];
    if (_stroke) [strokes addObject:_stroke];
    for (NSDictionary *stroke in strokes) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, imageRect.origin.x, imageRect.origin.y);
        ExteriaPhotoDrawStroke(stroke, imageRect.size);
        CGContextRestoreGState(context);
    }
    if (!CGRectIsEmpty(_selection)) {
        CGRect selected = CGRectMake(imageRect.origin.x + _selection.origin.x * imageRect.size.width,
                                     imageRect.origin.y + _selection.origin.y * imageRect.size.height,
                                     _selection.size.width * imageRect.size.width, _selection.size.height * imageRect.size.height);
        UIBezierPath *frame = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(selected, -6 * unit, -6 * unit) cornerRadius:7 * unit];
        frame.lineWidth = 1.5 * unit;
        CGFloat dash[2] = {5 * unit, 4 * unit};
        [frame setLineDash:dash count:2 phase:0];
        [[UIColor colorWithWhite:1 alpha:0.95] setStroke];
        [frame stroke];
    }
    if (!_cropping) return;
    CGRect crop = CGRectMake(imageRect.origin.x + _crop.origin.x * imageRect.size.width, imageRect.origin.y + _crop.origin.y * imageRect.size.height,
                             _crop.size.width * imageRect.size.width, _crop.size.height * imageRect.size.height);
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0 alpha:0.58].CGColor);
    CGContextAddRect(context, imageRect); CGContextAddRect(context, crop); CGContextEOFillPath(context);
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:1 alpha:0.55].CGColor); CGContextSetLineWidth(context, unit);
    CGContextStrokeRect(context, crop);
    for (int i = 1; i < 3; ++i) {
        CGFloat x = crop.origin.x + crop.size.width * i / 3, y = crop.origin.y + crop.size.height * i / 3;
        CGContextMoveToPoint(context, x, crop.origin.y); CGContextAddLineToPoint(context, x, CGRectGetMaxY(crop));
        CGContextMoveToPoint(context, crop.origin.x, y); CGContextAddLineToPoint(context, CGRectGetMaxX(crop), y);
    }
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:1 alpha:0.28].CGColor);
    CGContextStrokePath(context);
    /* the corners are brackets that lie along the frame, thick enough to grab and out of the way of the picture */
    CGFloat arm = MIN(22 * unit, MIN(crop.size.width, crop.size.height) / 3);
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, 3.5 * unit);
    CGContextSetLineCap(context, kCGLineCapRound); CGContextSetLineJoin(context, kCGLineJoinRound);
    for (int corner = 0; corner < 4; ++corner) {
        CGFloat dx = corner & 1 ? -1 : 1, dy = corner & 2 ? -1 : 1;
        CGFloat x = corner & 1 ? CGRectGetMaxX(crop) : crop.origin.x, y = corner & 2 ? CGRectGetMaxY(crop) : crop.origin.y;
        CGContextMoveToPoint(context, x + dx * arm, y);
        CGContextAddLineToPoint(context, x, y);
        CGContextAddLineToPoint(context, x, y + dy * arm);
    }
    CGContextStrokePath(context);
}
@end

/* a round color chip of the draw panel. the chosen one wears a ring that springs out round it */
@interface ExteriaEditorSwatch : UIControl {
    UIColor *_color;
    UIView *_dot;
    UIView *_ring;
    BOOL _marked;
}
@property (nonatomic, retain) UIColor *color;
- (void)setMarked:(BOOL)marked animated:(BOOL)animated;
@end
@implementation ExteriaEditorSwatch
@synthesize color = _color;
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _ring = [[UIView alloc] init]; _ring.userInteractionEnabled = NO; _ring.alpha = 0;
    _ring.layer.borderWidth = 2.5; _ring.layer.borderColor = [UIColor whiteColor].CGColor;
    [self addSubview:_ring];
    _dot = [[UIView alloc] init]; _dot.userInteractionEnabled = NO;
    _dot.layer.borderWidth = 1; _dot.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    [self addSubview:_dot];
    ExteriaAttachBounce(self, 0.12);
    return self;
}
- (void)dealloc { [_color release]; [_dot release]; [_ring release]; [super dealloc]; }
- (void)setColor:(UIColor *)color {
    if (color == _color) return;
    [_color release]; _color = [color retain];
    _dot.backgroundColor = color;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _ring.frame = bounds; _ring.layer.cornerRadius = bounds.size.width / 2;
    CGRect dot = CGRectInset(bounds, 5, 5);
    _dot.frame = dot; _dot.layer.cornerRadius = dot.size.width / 2;
}
- (void)setMarked:(BOOL)marked animated:(BOOL)animated {
    if (_marked == marked) return;
    _marked = marked;
    self.accessibilityTraits = UIAccessibilityTraitButton | (marked ? UIAccessibilityTraitSelected : 0);
    _ring.alpha = marked ? 1 : 0;
    if (animated && marked) ExteriaAnimateEnter(_ring, CGAffineTransformMakeScale(0.6, 0.6), 0, EXTERIA_MOTION_WOBBLE);
}
@end

/* the magnifier of the pipette: a disc that shows the spot under the finger enlarged without smoothing, so a single pixel of the picture is a square, framed in the color
   it has picked up */
@interface ExteriaPhotoLoupe : UIView {
    UIView *_glass;
    UIView *_reticle;
}
- (void)setPicture:(CGImageRef)picture;
- (void)showCenter:(CGPoint)center color:(UIColor *)color window:(CGRect)window;
@end
#define LOUPE_SIDE ((CGFloat)(ExteriaIsPad() ? 136 : 104))
@implementation ExteriaPhotoLoupe
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, LOUPE_SIDE, LOUPE_SIDE)];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.layer.cornerRadius = LOUPE_SIDE / 2;
    self.layer.borderWidth = 6;
    self.layer.shadowColor = [UIColor blackColor].CGColor; self.layer.shadowOpacity = 0.45; self.layer.shadowRadius = 8; self.layer.shadowOffset = CGSizeMake(0, 3);
    self.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:self.bounds].CGPath;
    _glass = [[UIView alloc] initWithFrame:self.bounds];
    _glass.layer.cornerRadius = LOUPE_SIDE / 2; _glass.layer.masksToBounds = YES;
    _glass.layer.magnificationFilter = kCAFilterNearest;
    _glass.backgroundColor = [UIColor blackColor];
    [self addSubview:_glass];
    _reticle = [[UIView alloc] initWithFrame:CGRectMake(LOUPE_SIDE / 2 - 6, LOUPE_SIDE / 2 - 6, 12, 12)];
    _reticle.layer.borderWidth = 1.5; _reticle.layer.borderColor = [UIColor whiteColor].CGColor; _reticle.layer.cornerRadius = 2;
    [self addSubview:_reticle];
    UIView *inner = [[[UIView alloc] initWithFrame:CGRectInset(_reticle.frame, -1.5, -1.5)] autorelease];
    inner.layer.borderWidth = 0.5; inner.layer.borderColor = [UIColor blackColor].CGColor; inner.layer.cornerRadius = 3.5;
    [self addSubview:inner];
    self.alpha = 0;
    return self;
}
- (void)dealloc { [_glass release]; [_reticle release]; [super dealloc]; }
- (void)setPicture:(CGImageRef)picture { _glass.layer.contents = (id)picture; }
- (void)showCenter:(CGPoint)center color:(UIColor *)color window:(CGRect)window {
    self.center = center;
    self.layer.borderColor = color.CGColor;
    _glass.layer.contentsRect = window;
}
@end

@interface ExteriaPhotoEditor () <UIGestureRecognizerDelegate, UIAlertViewDelegate> {
    UIImage *_source;
    NSMutableArray *_operations;
    NSArray *_modeSnapshot;
    ExteriaWeakReference *_weak;
    void (^_completion)(UIImage *);
    dispatch_queue_t _work;
    UIView *_viewport;
    UIView *_stage;
    UIImageView *_photo;
    ExteriaPhotoCanvas *_canvas;
    ExteriaEditorPanel *_top;
    ExteriaEditorPanel *_tools;
    ExteriaEditorPanel *_options;
    ExteriaEditorPanel *_zoomChip;
    UIScrollView *_toolScroll;
    NSMutableArray *_toolButtons;
    ExteriaEditorButton *_done;
    ExteriaEditorButton *_cancel;
    ExteriaEditorButton *_apply;
    ExteriaEditorButton *_back;
    ExteriaEditorButton *_undo;
    ExteriaEditorButton *_zoomReset;
    ExteriaEditorButton *_arrowButton;
    ExteriaEditorButton *_blurButton;
    ExteriaEditorButton *_pipetteButton;
    ExteriaEditorSwatch *_currentSwatch;
    NSMutableArray *_swatches;
    ExteriaPhotoLoupe *_loupe;
    UILabel *_value;
    UISlider *_slider;
    UIScrollView *_choices;
    UIActivityIndicatorView *_spinner;
    UIPanGestureRecognizer *_drawPan;
    UIPinchGestureRecognizer *_pinch;
    UIPanGestureRecognizer *_zoomPan;
    NSMutableArray *_points;
    UIColor *_color;
    exteria_photo_adjustments _adjustments;
    NSUInteger _generation;
    NSUInteger _modeStart;
    NSInteger _tool;
    NSInteger _mode;
    NSInteger _panelMode;
    NSInteger _cropCorner;
    NSInteger _selectedText;
    NSInteger _alertText;
    NSInteger _enter;
    BOOL _movingText;
    CGRect _cropStart;
    CGRect _cropAnimationFrom;
    CGRect _cropAnimationTo;
    CADisplayLink *_cropAnimation;
    CFTimeInterval _cropAnimationStarted;
    CGPoint _panStart;
    CGPoint _textPoint;
    CGPoint _moveOriginal;
    CGFloat _brushWidth;
    CGFloat _cropRatio;
    double _zoom;
    double _offsetX;
    double _offsetY;
    CGFloat _fit;
    CGFloat _idleReserve;
    CGFloat _modeReserve;
    CGFloat _baseCenterX;
    CGFloat _baseCenterY;
    CGFloat _modeCenterY;
    CGSize _laidOut;
    BOOL _arrow;
    BOOL _blurBrush;
    BOOL _pipette;
    BOOL _rendering;
    BOOL _needsRender;
    BOOL _closed;
    BOOL _exporting;
    BOOL _entered;
}
@end

/* the kinds of settling a finished render plays on the stage */
enum { ExteriaPhotoEnterNone, ExteriaPhotoEnterRotate, ExteriaPhotoEnterFlip, ExteriaPhotoEnterPop };

#define TOOL_COUNT 6
#define TOOL_CROP 0
#define TOOL_ADJUST 1
#define TOOL_DRAW 2
#define TOOL_ROTATE 3
#define TOOL_MIRROR 4
#define TOOL_RESET 5

@implementation ExteriaPhotoEditor
- (id)initWithImage:(UIImage *)image completion:(void (^)(UIImage *))completion {
    self = [super init];
    if (self) {
        _source = [image retain]; _completion = [completion copy];
        _operations = [[NSMutableArray alloc] init]; _weak = [[ExteriaWeakReference referenceTo:self] retain];
        _work = dispatch_queue_create("com.exteria.photo-editor", DISPATCH_QUEUE_SERIAL);
        _selectedText = -1; _alertText = -1; _zoom = 1; _fit = 1;
        _color = [[UIColor whiteColor] retain]; _brushWidth = 0.012;
        self.wantsFullScreenLayout = YES; self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}
- (void)dealloc {
    ExteriaStatusBarShow(self, UIStatusBarAnimationNone);
    [_cropAnimation invalidate]; [_cropAnimation release];
    [_weak clear]; [_source release]; [_completion release]; [_operations release]; [_modeSnapshot release]; [_weak release];
    dispatch_release(_work);
    [_viewport release]; [_stage release]; [_photo release]; [_canvas release]; [_top release]; [_tools release]; [_options release]; [_zoomChip release];
    [_toolScroll release]; [_toolButtons release];
    [_done release]; [_cancel release]; [_apply release]; [_back release]; [_undo release]; [_zoomReset release]; [_arrowButton release]; [_blurButton release]; [_pipetteButton release];
    [_currentSwatch release]; [_swatches release]; [_loupe release];
    [_value release]; [_slider release]; [_choices release]; [_spinner release]; [_points release]; [_color release];
    [_drawPan release]; [_pinch release]; [_zoomPan release];
    [super dealloc];
}
- (BOOL)classic { return ExteriaThemeIsClassic(); }
- (ExteriaEditorButton *)iconButton:(ExteriaEditorButtonStyle)style symbol:(ExteriaSymbol)symbol title:(NSString *)key action:(SEL)action host:(UIView *)host {
    NSString *title = key ? NSLocalizedString(key, nil) : nil;
    ExteriaEditorButton *button = [[[ExteriaEditorButton alloc] initWithStyle:style symbol:symbol title:title] autorelease];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:button];
    return button;
}
- (ExteriaEditorButton *)textButton:(ExteriaEditorButtonStyle)style title:(NSString *)key action:(SEL)action host:(UIView *)host {
    ExteriaEditorButton *button = [[[ExteriaEditorButton alloc] initWithStyle:style title:key ? NSLocalizedString(key, nil) : nil] autorelease];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:button];
    return button;
}
/* the old system keeps words on its bars and the modern look keeps icons */
- (ExteriaEditorButton *)barButton:(NSString *)key symbol:(ExteriaSymbol)symbol action:(SEL)action host:(UIView *)host {
    if ([self classic]) return [self textButton:ExteriaEditorButtonPill title:key action:action host:host];
    ExteriaEditorButton *button = [self iconButton:ExteriaEditorButtonRound symbol:symbol title:nil action:action host:host];
    button.accessibilityLabel = NSLocalizedString(key, nil);
    return button;
}
- (void)loadView {
    BOOL classic = [self classic];
    self.view = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease]; self.view.backgroundColor = [UIColor blackColor];
    _viewport = [[UIView alloc] init]; _viewport.clipsToBounds = YES; [self.view addSubview:_viewport];
    _stage = [[UIView alloc] init]; [_viewport addSubview:_stage];
    _photo = [[UIImageView alloc] init]; _photo.image = _source; [_stage addSubview:_photo];
    _canvas = [[ExteriaPhotoCanvas alloc] init]; _canvas.backgroundColor = [UIColor clearColor]; _canvas.opaque = NO; _canvas.contentMode = UIViewContentModeRedraw;
    _canvas.image = _source; [_stage addSubview:_canvas];
    _drawPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    _drawPan.maximumNumberOfTouches = 1; _drawPan.delegate = self; [_canvas addGestureRecognizer:_drawPan];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    tap.delegate = self; [_canvas addGestureRecognizer:tap];
    /* a tap draws a dot, so text waits for a hold on the picture */
    UILongPressGestureRecognizer *hold = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)] autorelease];
    hold.minimumPressDuration = 1.2; hold.delegate = self; [_canvas addGestureRecognizer:hold];
    _pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)];
    _pinch.delegate = self; [_viewport addGestureRecognizer:_pinch];
    _zoomPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(zoomPanned:)];
    _zoomPan.minimumNumberOfTouches = 2; _zoomPan.maximumNumberOfTouches = 2; _zoomPan.delegate = self; [_viewport addGestureRecognizer:_zoomPan];

    _top = [[ExteriaEditorPanel alloc] init]; [self.view addSubview:_top];
    _cancel = [[self barButton:@"attach.cancel" symbol:ExteriaSymbolCross action:@selector(cancel) host:_top.content] retain];
    _undo = [[self barButton:@"media.undo" symbol:ExteriaSymbolUndo action:@selector(undo) host:_top.content] retain];
    /* a check and no word: the label stays for the screen reader */
    _done = [[self iconButton:ExteriaEditorButtonAccent symbol:ExteriaSymbolCheck title:nil action:@selector(done) host:_top.content] retain];
    _done.accessibilityLabel = NSLocalizedString(@"media.done", nil);

    _tools = [[ExteriaEditorPanel alloc] init]; [self.view addSubview:_tools];
    _toolScroll = [[UIScrollView alloc] init]; _toolScroll.showsHorizontalScrollIndicator = NO; _toolScroll.alwaysBounceHorizontal = NO;
    [_tools.content addSubview:_toolScroll];
    const ExteriaSymbol symbols[TOOL_COUNT] = {ExteriaSymbolCrop, ExteriaSymbolAdjust, ExteriaSymbolDraw, ExteriaSymbolRotate, ExteriaSymbolMirror, ExteriaSymbolBroom};
    NSArray *names = [NSArray arrayWithObjects:@"media.crop", @"media.adjust", @"media.draw", @"media.rotate", @"media.flip", @"media.reset", nil];
    _toolButtons = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < TOOL_COUNT; ++i) {
        ExteriaEditorButton *button = [self iconButton:ExteriaEditorButtonTool symbol:symbols[i] title:[names objectAtIndex:i] action:@selector(toolPressed:) host:_toolScroll];
        button.tag = (NSInteger)i; [_toolButtons addObject:button];
    }

    _options = [[ExteriaEditorPanel alloc] init]; [self.view addSubview:_options];
    _back = [[self barButton:@"attach.cancel" symbol:ExteriaSymbolCross action:@selector(cancelMode) host:_options.content] retain];
    if (classic) _apply = [[self textButton:ExteriaEditorButtonPill title:@"media.apply" action:@selector(applyMode) host:_options.content] retain];
    else {
        _apply = [[self iconButton:ExteriaEditorButtonAccent symbol:ExteriaSymbolCheck title:nil action:@selector(applyMode) host:_options.content] retain];
        _apply.accessibilityLabel = NSLocalizedString(@"media.apply", nil);
    }
    _value = [[UILabel alloc] init]; _value.backgroundColor = [UIColor clearColor]; _value.textColor = [UIColor colorWithWhite:1 alpha:0.9];
    _value.font = ExteriaFontSemibold(14); _value.adjustsFontSizeToFitWidth = YES; _value.minimumFontSize = 10; _value.textAlignment = (NSTextAlignment)ExteriaTextAlignmentCenter;
    [_options.content addSubview:_value];
    _slider = [[ExteriaSlider alloc] init];
    [_slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged]; [_options.content addSubview:_slider];
    _choices = [[UIScrollView alloc] init]; _choices.showsHorizontalScrollIndicator = NO; [_options.content addSubview:_choices];

    _zoomChip = [[ExteriaEditorPanel alloc] init]; [self.view addSubview:_zoomChip];
    _zoomReset = [[self textButton:ExteriaEditorButtonPill title:nil action:@selector(resetZoomPressed) host:_zoomChip.content] retain];
    _zoomReset.accessibilityLabel = NSLocalizedString(@"media.zoom.reset", nil);
    _loupe = [[ExteriaPhotoLoupe alloc] initWithFrame:CGRectZero]; [self.view addSubview:_loupe];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES; [self.view addSubview:_spinner];

    /* the cards start away from the screen; viewDidAppear brings them in once the editor has finished arriving */
    _top.alpha = 0; _tools.alpha = 0;
    ExteriaEditorPresent(_options, NO, 30);
    ExteriaEditorPresent(_zoomChip, NO, -10);
    [self refreshMode]; [self requestRender];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ExteriaStatusBarHide(self, UIStatusBarAnimationNone);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_entered) return;
    _entered = YES;
    ExteriaEditorRise([NSArray arrayWithObject:_top], -18, 0);
    ExteriaEditorRise([NSArray arrayWithObject:_tools], 26, 0);
    ExteriaEditorRise(_toolButtons, 14, 0.025);
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopCropAnimation];
    ExteriaStatusBarShow(self, UIStatusBarAnimationNone);
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
#else
- (NSUInteger)supportedInterfaceOrientations
#endif
{ return UIInterfaceOrientationMaskAll; }
- (void)layoutPhoto { _photo.frame = _canvas.imageRect; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL classic = [self classic], floating = !classic;
    CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
    /* the picture sits between the bars, so the notch and the home indicator are given to the bars: the buttons stand clear of them, in landscape too */
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = insets.top, bottom = insets.bottom, left = insets.left, right = insets.right;
    CGFloat k = ExteriaEditorScale();
    CGFloat gap = floating ? round(10 * k) : 0;
    CGFloat column = floating ? MIN(width - left - right - 2 * gap, round(560 * k)) : width;
    CGFloat panelX = floating ? left + gap + floor((width - left - right - 2 * gap - column) / 2) : 0;
    /* a bar of the old system runs to the edge, so it takes the strip of the home indicator under it too */
    CGFloat extend = floating ? 0 : bottom;
    BOOL compact = height < 500;

    CGFloat round40 = round(40 * k);
    CGFloat topY = floating ? top + 8 : top, topHeight = floating ? round(44 * k) : 48;
    ExteriaPlaceView(_top, CGRectMake(panelX, topY, column, topHeight));
    CGFloat edgeL = floating ? 4 : left + 4, edgeR = floating ? 4 : right + 4;
    CGFloat inner = floor((topHeight - round40) / 2);
    if (floating) {
        _cancel.frame = CGRectMake(edgeL, inner, round40, round40);
        _undo.frame = CGRectMake(edgeL + round40 + 4, inner, round40, round40);
        _done.frame = CGRectMake(column - edgeR - round40, inner, round40, round40);
    } else {
        _cancel.frame = CGRectMake(edgeL, 0, 84, 48);
        _undo.frame = CGRectMake(edgeL + 84, 0, 90, 48);
        _done.frame = CGRectMake(column - edgeR - 56, 0, 56, 48);
    }
    CGFloat viewportTop = topY + topHeight + (floating ? 8 : 0);

    CGFloat toolsHeight = floating ? round(64 * k) : 56;
    CGFloat toolsY = height - bottom - gap - toolsHeight;
    ExteriaPlaceView(_tools, CGRectMake(panelX, toolsY, column, toolsHeight + extend));
    _toolScroll.frame = CGRectMake(0, 0, column, toolsHeight);
    CGFloat avail = column - (floating ? 8 : left + right);
    CGFloat buttonWidth = MAX(round(54 * k), floor(avail / TOOL_COUNT));
    CGFloat startX = (floating ? 4 : left) + MAX(0, floor((avail - buttonWidth * TOOL_COUNT) / 2));
    for (ExteriaEditorButton *button in _toolButtons) button.frame = CGRectMake(startX + button.tag * buttonWidth, 0, buttonWidth, toolsHeight);
    _toolScroll.contentSize = CGSizeMake(startX * 2 + buttonWidth * TOOL_COUNT, toolsHeight);
    _idleReserve = height - toolsY + 6;

    /* the options card: a header with the two round buttons, a row of choices, and a slider; the crop card has no slider, and a phone on its side has no room for a header of its own */
    CGFloat buttonSide = floating ? round40 : 84, buttonHeight = floating ? round40 : 44;
    CGFloat rowHeight = round(44 * k), sliderHeight = 36;
    CGFloat choicesY = compact ? 4 : 4 + buttonHeight + 8;
    CGFloat sliderY = choicesY + rowHeight + (compact ? 6 : 4);
    NSInteger shown = _panelMode ? _panelMode : TOOL_ADJUST + 1;
    CGFloat optionsHeight = shown == 1 ? choicesY + rowHeight + 12 : sliderY + sliderHeight + 10;
    CGFloat optionsY = height - bottom - gap - optionsHeight;
    ExteriaPlaceView(_options, CGRectMake(panelX, optionsY, column, optionsHeight + extend));
    _modeReserve = height - optionsY + 6;
    CGFloat slideL = floating ? 18 : left + 18, slideR = floating ? 18 : right + 18;
    _back.frame = CGRectMake(edgeL, 4, buttonSide, buttonHeight);
    _apply.frame = CGRectMake(column - edgeR - buttonSide, 4, buttonSide, buttonHeight);
    if (compact) {
        _choices.frame = CGRectMake(edgeL + buttonSide + 4, choicesY, MAX(0, column - 2 * (edgeL + buttonSide + 4)), rowHeight);
        _value.frame = CGRectMake(slideL, sliderY, 104, sliderHeight);
        _value.textAlignment = (NSTextAlignment)ExteriaTextAlignmentLeft;
        _slider.frame = CGRectMake(slideL + 112, sliderY, MAX(0, column - slideL - slideR - 112), sliderHeight);
    } else {
        _value.frame = CGRectMake(edgeL + buttonSide + 8, 4, MAX(0, column - 2 * (edgeL + buttonSide + 8)), buttonHeight);
        _value.textAlignment = (NSTextAlignment)ExteriaTextAlignmentCenter;
        _choices.frame = CGRectMake(0, choicesY, column, rowHeight);
        _slider.frame = CGRectMake(slideL, sliderY, MAX(0, column - slideL - slideR), sliderHeight);
    }

    CGSize chip = CGSizeMake(round((floating ? 76 : 70) * k), round((floating ? 36 : 40) * k));
    ExteriaPlaceView(_zoomChip, CGRectMake(width - right - 12 - chip.width, viewportTop + 8, chip.width, chip.height));
    _zoomReset.frame = _zoomChip.bounds;

    CGRect viewport = CGRectMake(0, viewportTop, width, MAX(1, height - viewportTop));
    _viewport.frame = viewport;
    ExteriaPlaceView(_stage, CGRectMake(0, 0, viewport.size.width, viewport.size.height));
    _canvas.frame = _stage.bounds;
    _canvas.insets = UIEdgeInsetsMake(8, 12 + left, _idleReserve, 12 + right);
    [self layoutPhoto];
    _spinner.center = CGPointMake(width / 2, height / 2);
    [self updateFit];
    /* a new size of the screen puts the picture back where it belongs at once; a change of mode moves it with a spring from setMode */
    if (!CGSizeEqualToSize(_laidOut, viewport.size)) {
        _laidOut = viewport.size;
        [self clampZoomWithMinimum:1];
        [self applyStageAnimated:NO];
    }
    [_canvas setNeedsDisplay];
}

/* the stage is what moves and scales: the picture, and the strokes over it, are one picture to the gestures, and the graphics hardware does the work while it is pinched */
- (void)updateFit {
    CGFloat height = _stage.bounds.size.height, width = _stage.bounds.size.width;
    UIEdgeInsets insets = _canvas.insets;
    CGFloat baseTop = insets.top, baseBottom = height - _idleReserve;
    CGFloat modeBottom = height - (_mode ? _modeReserve : _idleReserve);
    CGFloat baseHeight = MAX(1, baseBottom - baseTop), modeHeight = MAX(1, modeBottom - baseTop);
    _fit = MIN(1, modeHeight / baseHeight);
    _baseCenterX = (insets.left + width - insets.right) / 2;
    _baseCenterY = (baseTop + baseBottom) / 2;
    _modeCenterY = (baseTop + modeBottom) / 2;
}
- (CGAffineTransform)stageTransform {
    CGFloat scale = (CGFloat)_zoom * _fit;
    CGFloat centerX = _stage.bounds.size.width / 2, centerY = _stage.bounds.size.height / 2;
    CGFloat tx = _baseCenterX + (CGFloat)_offsetX - centerX - (_baseCenterX - centerX) * scale;
    CGFloat ty = _modeCenterY + (CGFloat)_offsetY - centerY - (_baseCenterY - centerY) * scale;
    return CGAffineTransformMake(scale, 0, 0, scale, tx, ty);
}
- (void)clampZoomWithMinimum:(double)minimum {
    CGRect image = _canvas.imageRect;
    CGFloat height = _stage.bounds.size.height;
    CGFloat area = MAX(1, height - (_mode ? _modeReserve : _idleReserve) - _canvas.insets.top);
    if (image.size.width < 1 || image.size.height < 1) { _zoom = 1; _offsetX = _offsetY = 0; return; }
    if (exteria_photo_zoom_clamp(image.size.width * _fit, image.size.height * _fit, _stage.bounds.size.width, area, minimum, &_zoom, &_offsetX, &_offsetY) != EXTERIA_OK) {
        _zoom = 1; _offsetX = _offsetY = 0;
    }
}
- (void)applyStageAnimated:(BOOL)animated {
    CGAffineTransform transform = [self stageTransform];
    if (animated) ExteriaAnimateView(_stage, transform, 1, EXTERIA_MOTION_SPRING, nil);
    else { [_stage.layer removeAnimationForKey:@"exteria.motion"]; _stage.transform = transform; }
    CGFloat scale = (CGFloat)_zoom * _fit;
    BOOL scaleChanged = fabs(_canvas.scale - scale) > 0.01;
    _canvas.scale = scale;
    /* the strokes are drawn again at the size they are seen at, but never past four times the pixels of the screen: the canvas is a bitmap, and a big one costs an old phone */
    CGFloat contentScale = MIN(ExteriaScreenScale() * MAX(1, MIN(scale, 3)), 4);
    if (fabs(_canvas.contentScaleFactor - contentScale) > 0.01) _canvas.contentScaleFactor = contentScale;
    if (scaleChanged) [_canvas setNeedsDisplay];
    [self refreshZoomChip];
}
- (void)refreshZoomChip {
    BOOL shown = _zoom > 1.03;
    BOOL was = _zoomChip.userInteractionEnabled;
    if (shown) [_zoomReset setTitle:[NSString stringWithFormat:@"%.1f×", _zoom] animated:was];
    if (shown != was) ExteriaEditorPresent(_zoomChip, shown, -10);
}
- (void)resetZoomPressed {
    _zoom = 1; _offsetX = _offsetY = 0;
    [self applyStageAnimated:YES];
}
- (void)pinched:(UIPinchGestureRecognizer *)pinch {
    if (pinch.state == UIGestureRecognizerStateBegan) {
        /* the second finger turns the stroke or the handle under the first into a pinch: the draw gesture is given up, which drops the stroke */
        _drawPan.enabled = NO; _drawPan.enabled = YES;
        [_stage.layer removeAnimationForKey:@"exteria.motion"];
    }
    if (pinch.state == UIGestureRecognizerStateBegan || pinch.state == UIGestureRecognizerStateChanged) {
        CGPoint focus = [pinch locationInView:_viewport];
        double next = _zoom * pinch.scale, x = _offsetX, y = _offsetY;
        if (exteria_photo_zoom_about(_zoom, _offsetX, _offsetY, focus.x - _baseCenterX, focus.y - _modeCenterY, next, &x, &y) == EXTERIA_OK) {
            _zoom = next; _offsetX = x; _offsetY = y;
        }
        pinch.scale = 1;
        /* a little below 1 is allowed while the fingers are down, and the picture settles back when they leave */
        [self clampZoomWithMinimum:0.75];
        [self applyStageAnimated:NO];
    } else if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled || pinch.state == UIGestureRecognizerStateFailed) {
        [self clampZoomWithMinimum:1];
        [self applyStageAnimated:YES];
    }
}
- (void)zoomPanned:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        _drawPan.enabled = NO; _drawPan.enabled = YES;
        [_stage.layer removeAnimationForKey:@"exteria.motion"];
    }
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint move = [pan translationInView:_viewport];
        [pan setTranslation:CGPointZero inView:_viewport];
        _offsetX += move.x; _offsetY += move.y;
        [self clampZoomWithMinimum:0.75];
        [self applyStageAnimated:NO];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        [self clampZoomWithMinimum:1];
        [self applyStageAnimated:YES];
    }
}
- (void)notice:(NSString *)key {
    UIAlertView *alert = [[ExteriaAlertClass() alloc] initWithTitle:nil message:NSLocalizedString(key, nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show]; [alert release];
}

#pragma mark - modes

/* one capsule of a row of choices; a key is localized, a ratio such as 4:3 is shown as it is */
- (ExteriaEditorButton *)choice:(NSString *)title x:(CGFloat *)x action:(SEL)action tag:(NSInteger)tag {
    NSString *text = [title rangeOfString:@":"].location == NSNotFound ? NSLocalizedString(title, nil) : title;
    ExteriaEditorButton *button = [[[ExteriaEditorButton alloc] initWithStyle:ExteriaEditorButtonPill title:text] autorelease];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_choices addSubview:button];
    CGFloat width = ceil([text sizeWithFont:ExteriaFontSemibold(ExteriaIsPad() ? 17 : 15)].width) + 28;
    CGFloat k = ExteriaEditorScale(), row = round(44 * k), height = round(36 * k);
    button.frame = CGRectMake(*x, floor((row - height) / 2), MAX(round(48 * k), width), height);
    button.tag = tag;
    *x += button.frame.size.width + 6;
    return button;
}
- (void)litChoice:(NSInteger)tag {
    for (UIView *view in _choices.subviews)
        if ([view isKindOfClass:[ExteriaEditorButton class]] && view != _arrowButton && view != _blurButton && view != _pipetteButton)
            [(ExteriaEditorButton *)view setLit:view.tag == tag animated:YES];
}
- (BOOL)usesSlider { return _mode == 2 || _mode == 3; }
- (void)refreshMode {
    [self stopCropAnimation];
    _done.enabled = !_mode && !_exporting; _undo.enabled = [self undoAvailable];
    BOOL crossfade = _canvas.cropping != (_mode == 1);
    if (crossfade && _canvas.window && !ExteriaReduceMotionEnabled()) {
        CATransition *fade = [CATransition animation]; fade.type = kCATransitionFade; fade.duration = 0.25;
        [_canvas.layer addAnimation:fade forKey:@"exteria.fade"];
    }
    _canvas.cropping = _mode == 1;
    _canvas.crop = CGRectMake(0, 0, 1, 1); _cropRatio = 0;
    /* the card keeps its content while it fades out, so leaving a mode builds nothing */
    if (!_mode) { [_canvas setNeedsDisplay]; return; }
    _panelMode = _mode;
    _slider.alpha = [self usesSlider] ? 1 : 0; _slider.userInteractionEnabled = [self usesSlider];
    for (UIView *view in [[_choices.subviews copy] autorelease]) [view removeFromSuperview];
    [_arrowButton release]; _arrowButton = nil; [_blurButton release]; _blurButton = nil; [_pipetteButton release]; _pipetteButton = nil;
    [_currentSwatch release]; _currentSwatch = nil; [_swatches release]; _swatches = nil;
    _pipette = NO;
    CGFloat x = 8;
    if (_mode == 1) {
        NSArray *names = [NSArray arrayWithObjects:@"media.free", @"1:1", @"4:3", @"3:4", @"16:9", @"9:16", nil];
        for (NSUInteger i = 0; i < names.count; ++i) [self choice:[names objectAtIndex:i] x:&x action:@selector(aspect:) tag:(NSInteger)i];
        [self litChoice:0];
    } else if (_mode == 2) {
        for (NSInteger i = 0; i < EXTERIA_PHOTO_TOOLS; ++i) [self choice:ExteriaPhotoToolNames[i] x:&x action:@selector(adjustTool:) tag:i];
        [self selectAdjustment:0];
    } else if (_mode == 3) {
        _pipetteButton = [[ExteriaEditorButton alloc] initWithStyle:ExteriaEditorButtonPill symbol:ExteriaSymbolPipette title:nil];
        [_pipetteButton addTarget:self action:@selector(togglePipette) forControlEvents:UIControlEventTouchUpInside];
        _pipetteButton.accessibilityLabel = NSLocalizedString(@"media.pipette", nil);
        { CGFloat k = ExteriaEditorScale(), row = round(44 * k), h = round(36 * k), w = round(44 * k); _pipetteButton.frame = CGRectMake(8, floor((row - h) / 2), w, h); [_choices addSubview:_pipetteButton]; x = 8 + w + 8; }
        _swatches = [[NSMutableArray alloc] init];
        CGFloat sk = ExteriaEditorScale(), sRow = round(44 * sk), big = round(36 * sk), small = round(32 * sk);
        _currentSwatch = [[ExteriaEditorSwatch alloc] initWithFrame:CGRectMake(x, floor((sRow - big) / 2), big, big)];
        _currentSwatch.color = _color; [_currentSwatch setMarked:YES animated:NO]; _currentSwatch.userInteractionEnabled = NO;
        _currentSwatch.accessibilityLabel = NSLocalizedString(@"media.color", nil);
        [_choices addSubview:_currentSwatch]; x += big + 10;
        NSArray *colors = [NSArray arrayWithObjects:[UIColor whiteColor], [UIColor blackColor], [UIColor redColor], [UIColor yellowColor], [UIColor greenColor], [UIColor cyanColor], [UIColor blueColor], [UIColor magentaColor], nil];
        for (NSUInteger i = 0; i < colors.count; ++i) {
            ExteriaEditorSwatch *swatch = [[[ExteriaEditorSwatch alloc] initWithFrame:CGRectMake(x, floor((sRow - small) / 2), small, small)] autorelease];
            swatch.color = [colors objectAtIndex:i];
            [swatch addTarget:self action:@selector(color:) forControlEvents:UIControlEventTouchUpInside];
            [_choices addSubview:swatch]; [_swatches addObject:swatch]; x += small + 8;
        }
        [self refreshSwatches:NO];
        x += 4;
        _arrowButton = [[self choice:@"media.arrow" x:&x action:@selector(toggleArrow) tag:0] retain];
        _blurButton = [[self choice:@"media.blur" x:&x action:@selector(toggleBlur) tag:0] retain];
        [self refreshBrushButtons:NO];
        [self choice:@"media.text" x:&x action:@selector(addText) tag:0];
        _slider.minimumValue = 0.003; _slider.maximumValue = 0.06; _slider.value = _brushWidth;
    }
    _choices.contentSize = CGSizeMake(x + 8, round(44 * ExteriaEditorScale()));
    _choices.contentOffset = CGPointZero;
    [self refreshTitle];
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
    [_canvas setNeedsDisplay];
}
- (void)refreshTitle {
    NSString *text = @"";
    if (_mode == 1) text = NSLocalizedString(@"media.crop", nil);
    else if (_mode == 2) text = [NSString stringWithFormat:@"%@  %+.0f", NSLocalizedString(ExteriaPhotoToolNames[_tool], nil), _slider.value * 100];
    else if (_mode == 3) text = NSLocalizedString(_pipette ? @"media.pipette.hint" : (_selectedText >= 0 ? @"media.text" : @"media.brush"), nil);
    if (![_value.text isEqualToString:text]) {
        if (_options.window && !ExteriaReduceMotionEnabled()) {
            CATransition *fade = [CATransition animation]; fade.type = kCATransitionFade; fade.duration = 0.16;
            [_value.layer addAnimation:fade forKey:@"exteria.title"];
        }
        _value.text = text;
    }
}
/* the tools card goes down and the options card comes up, while the picture makes room for it */
- (void)showMode {
    [self updateFit];
    [self clampZoomWithMinimum:1];
    ExteriaEditorPresent(_tools, _mode == 0, 24);
    ExteriaEditorPresent(_options, _mode != 0, 30);
    [self applyStageAnimated:YES];
    if (_mode) {
        NSMutableArray *rows = [NSMutableArray array];
        for (UIView *view in _choices.subviews) [rows addObject:view];
        ExteriaEditorRise(rows, 12, 0.018);
    }
}
- (void)toolPressed:(ExteriaEditorButton *)button {
    if (_exporting || _rendering) return;
    if (button.tag <= TOOL_DRAW) {
        _mode = button.tag + 1; _modeStart = _operations.count; memset(&_adjustments, 0, sizeof(_adjustments));
        [_modeSnapshot release]; _modeSnapshot = [_operations copy]; _selectedText = -1;
        [self refreshMode]; [self showMode];
    } else if (button.tag == TOOL_RESET) {
        if (!_operations.count) return;
        [_operations removeAllObjects]; _enter = ExteriaPhotoEnterPop; [self requestRender];
    } else {
        BOOL rotate = button.tag == TOOL_ROTATE;
        if (rotate) [button playQuarterTurn]; else [button playFlip];
        NSUInteger count = _operations.count;
        [self append:[NSDictionary dictionaryWithObject:rotate ? @"rotate" : @"flip" forKey:@"kind"]];
        if (_operations.count > count) _enter = rotate ? ExteriaPhotoEnterRotate : ExteriaPhotoEnterFlip;
    }
}
- (void)append:(NSDictionary *)operation {
    if (_operations.count >= EDIT_OPERATIONS_MAX) { [self notice:@"media.edit.limit"]; return; }
    [_operations addObject:operation];
    NSString *kind = [operation objectForKey:@"kind"];
    if ([kind isEqualToString:@"stroke"] || [kind isEqualToString:@"blur"]) { [_canvas.pending addObject:operation]; [_canvas setNeedsDisplay]; }
    [self requestRender];
}
/* undo takes back what this visit to a tool added: the strokes kept by an earlier visit are not its to remove, and crop and text have nothing to take back before they are applied */
- (BOOL)undoAvailable {
    if (_exporting) return NO;
    if (_mode == 2) return _operations.count > 0;
    if (_mode) return _operations.count > _modeStart;
    return _operations.count > 0;
}
- (void)undo {
    if (_exporting) return;
    if (_mode == 3) [self selectText:-1];
    if (_mode == 2) { memset(&_adjustments, 0, sizeof(_adjustments)); [self selectAdjustment:_tool]; }
    else if (_operations.count && (!_mode || _operations.count > _modeStart)) [_operations removeLastObject];
    [self requestRender];
}
- (void)stopCropAnimation {
    [_cropAnimation invalidate]; [_cropAnimation release]; _cropAnimation = nil;
}
- (void)cropAnimationTick:(CADisplayLink *)link {
    CGFloat t = MIN(1, MAX(0, (link.timestamp - _cropAnimationStarted) / 0.3));
    CGFloat progress = (1 - cos(M_PI * t)) / 2;
    CGRect from = _cropAnimationFrom, to = _cropAnimationTo;
    _canvas.crop = CGRectMake(from.origin.x + (to.origin.x - from.origin.x) * progress,
                              from.origin.y + (to.origin.y - from.origin.y) * progress,
                              from.size.width + (to.size.width - from.size.width) * progress,
                              from.size.height + (to.size.height - from.size.height) * progress);
    [_canvas setNeedsDisplay];
    if (t >= 1) [self stopCropAnimation];
}
- (void)aspect:(ExteriaEditorButton *)button {
    const double ratios[] = {0, 1, 4.0/3, 3.0/4, 16.0/9, 9.0/16};
    if (button.tag < 0 || button.tag > 5 || !_canvas.image) return;
    [self litChoice:button.tag];
    double ratio = ratios[button.tag], imageRatio = _canvas.image.size.width / _canvas.image.size.height;
    CGRect rect = CGRectMake(0, 0, 1, 1);
    if (ratio > 0) {
        if (imageRatio > ratio) { rect.size.width = ratio / imageRatio; rect.origin.x = (1 - rect.size.width) / 2; }
        else { rect.size.height = imageRatio / ratio; rect.origin.y = (1 - rect.size.height) / 2; }
    }
    _cropRatio = ratio > 0 ? rect.size.width / rect.size.height : 0;
    [self stopCropAnimation];
    if (ExteriaReduceMotionEnabled() || ![UIView areAnimationsEnabled] || !_canvas.window) {
        _canvas.crop = rect; [_canvas setNeedsDisplay];
    } else {
        _cropAnimationFrom = _canvas.crop; _cropAnimationTo = rect;
        _cropAnimationStarted = CACurrentMediaTime();
        _cropAnimation = [[CADisplayLink displayLinkWithTarget:self selector:@selector(cropAnimationTick:)] retain];
        [_cropAnimation addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}
- (void)adjustTool:(ExteriaEditorButton *)button { [self litChoice:button.tag]; [self selectAdjustment:button.tag]; }
- (void)selectAdjustment:(NSInteger)tool {
    if (tool < 0 || tool >= EXTERIA_PHOTO_TOOLS) return;
    _tool = tool;
    _slider.minimumValue = tool == EXTERIA_PHOTO_FADE || tool >= EXTERIA_PHOTO_VIGNETTE ? 0 : -1;
    _slider.maximumValue = 1; _slider.value = _adjustments.values[tool];
    [self litChoice:tool];
    [self refreshTitle];
    _slider.accessibilityLabel = NSLocalizedString(ExteriaPhotoToolNames[tool], nil);
}
- (void)sliderChanged {
    if (_mode == 3) {
        if (_selectedText >= 0) [self updateSelectedText:@"size" value:[NSNumber numberWithFloat:_slider.value]];
        else _brushWidth = _slider.value;
        return;
    }
    _adjustments.values[_tool] = _slider.value;
    [self refreshTitle]; [self requestRender];
}
- (NSDictionary *)adjustmentOperation {
    return [NSDictionary dictionaryWithObjectsAndKeys:@"adjust", @"kind", [NSData dataWithBytes:&_adjustments length:sizeof(_adjustments)], @"settings", nil];
}
- (void)leaveMode {
    _mode = 0; _selectedText = -1; _pipette = NO; _canvas.selection = CGRectZero; _canvas.stroke = nil;
    [self hideLoupe];
    [_modeSnapshot release]; _modeSnapshot = nil;
    [self refreshMode]; [self showMode]; [self requestRender];
}
- (void)applyMode {
    if (_cropAnimation) { _canvas.crop = _cropAnimationTo; [self stopCropAnimation]; }
    if (_mode == 1) {
        [self append:[NSDictionary dictionaryWithObjectsAndKeys:@"crop", @"kind", [NSValue valueWithCGRect:_canvas.crop], @"rect", nil]];
        _enter = ExteriaPhotoEnterPop;
    } else if (_mode == 2) [self append:[self adjustmentOperation]];
    [self leaveMode];
}
- (void)cancelMode {
    if (_modeSnapshot) [_operations setArray:_modeSnapshot];
    [self leaveMode];
}

#pragma mark - draw panel

/* the arrow is on while its button is lit; the pen is what is left when it is off */
- (void)toggleArrow {
    _arrow = !_arrow;
    if (_arrow) _blurBrush = NO;
    [self refreshBrushButtons:YES];
}
/* the blur brush paints no color and no arrow, so lighting one puts the other out */
- (void)toggleBlur {
    _blurBrush = !_blurBrush;
    if (_blurBrush) _arrow = NO;
    [self refreshBrushButtons:YES];
}
- (void)refreshBrushButtons:(BOOL)animated {
    [_arrowButton setLit:_arrow animated:animated];
    [_blurButton setLit:_blurBrush animated:animated];
}
- (BOOL)color:(UIColor *)a isNear:(UIColor *)b {
    CGFloat ar, ag, ab, aa, br, bg, bb, ba;
    if (![a getRed:&ar green:&ag blue:&ab alpha:&aa] || ![b getRed:&br green:&bg blue:&bb alpha:&ba]) return [a isEqual:b];
    return fabs(ar - br) < 0.02 && fabs(ag - bg) < 0.02 && fabs(ab - bb) < 0.02;
}
- (void)refreshSwatches:(BOOL)animated {
    _currentSwatch.color = _color;
    for (ExteriaEditorSwatch *swatch in _swatches) [swatch setMarked:[self color:swatch.color isNear:_color] animated:animated];
}
- (void)setPaintColor:(UIColor *)color {
    /* the blur brush paints no color, so a color chosen for the pen takes the person back to it, also when it is the one already set */
    if (_blurBrush && _selectedText < 0) { _blurBrush = NO; [self refreshBrushButtons:YES]; }
    if (color == _color) return;
    [_color release]; _color = [color retain];
    if (_currentSwatch.window) ExteriaEditorPop(_currentSwatch);
    [self refreshSwatches:YES];
    if (_selectedText >= 0) [self updateSelectedText:@"color" value:_color];
}
- (void)color:(ExteriaEditorSwatch *)swatch { [self setPaintColor:swatch.color]; }
- (void)togglePipette {
    if (_mode != 3) return;
    _pipette = !_pipette;
    [_pipetteButton setLit:_pipette animated:YES];
    if (_pipette) [self selectText:-1];
    [self refreshTitle];
}
- (void)endPipette {
    _pipette = NO;
    [_pipetteButton setLit:NO animated:YES];
    [self hideLoupe];
    [self refreshTitle];
}
/* the color of the pixel of the picture on screen under a point of the canvas; the picture is drawn into a bitmap of one pixel, shifted so the wanted pixel falls in it */
- (UIColor *)colorAtCanvasPoint:(CGPoint)canvasPoint {
    CGImageRef image = _canvas.image.CGImage;
    CGRect rect = _canvas.imageRect;
    if (!image || rect.size.width < 1 || rect.size.height < 1) return nil;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (!width || !height) return nil;
    double fx = MAX(0, MIN(1, (canvasPoint.x - rect.origin.x) / rect.size.width)), fy = MAX(0, MIN(1, (canvasPoint.y - rect.origin.y) / rect.size.height));
    size_t px = MIN(width - 1, (size_t)(fx * width)), py = MIN(height - 1, (size_t)(fy * height));
    uint8_t pixel[4] = {0, 0, 0, 0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(-(CGFloat)px, -(CGFloat)(height - 1 - py), (CGFloat)width, (CGFloat)height), image);
    CGContextRelease(context);
    if (!pixel[3]) return nil;
    CGFloat alpha = pixel[3] / 255.0;
    return [UIColor colorWithRed:pixel[0] / 255.0 / alpha green:pixel[1] / 255.0 / alpha blue:pixel[2] / 255.0 / alpha alpha:1];
}
- (void)showLoupeAtCanvasPoint:(CGPoint)canvasPoint color:(UIColor *)color {
    CGRect rect = _canvas.imageRect;
    if (rect.size.width < 1 || rect.size.height < 1) return;
    BOOL appearing = _loupe.alpha < 0.05 && !_loupe.layer.animationKeys.count;
    if (appearing) [_loupe setPicture:_canvas.image.CGImage];
    CGPoint point = [_canvas convertPoint:canvasPoint toView:self.view];
    CGFloat radius = LOUPE_SIDE / 2.0, lift = radius + 44;
    CGFloat y = point.y - lift < radius + 6 ? point.y + lift : point.y - lift;
    CGFloat x = MAX(radius + 6, MIN(self.view.bounds.size.width - radius - 6, point.x));
    /* the disc shows eight times the picture as it is seen, so the window is a few points of the picture wide; kept inside the picture, so the edge never shows */
    CGFloat shown = (CGFloat)(_zoom * _fit);
    CGFloat windowW = MIN(1, (LOUPE_SIDE / 8.0) / (rect.size.width * shown)), windowH = MIN(1, (LOUPE_SIDE / 8.0) / (rect.size.height * shown));
    CGFloat fx = (canvasPoint.x - rect.origin.x) / rect.size.width, fy = (canvasPoint.y - rect.origin.y) / rect.size.height;
    CGRect window = CGRectMake(MAX(0, MIN(1 - windowW, fx - windowW / 2)), MAX(0, MIN(1 - windowH, fy - windowH / 2)), windowW, windowH);
    [_loupe showCenter:CGPointMake(x, y) color:color window:window];
    if (appearing) {
        _loupe.transform = CGAffineTransformMakeScale(0.4, 0.4);
        ExteriaAnimateView(_loupe, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
    }
}
- (void)hideLoupe {
    if (_loupe.alpha < 0.01 && !_loupe.layer.animationKeys.count) return;
    ExteriaAnimateView(_loupe, CGAffineTransformMakeScale(0.5, 0.5), 0, EXTERIA_MOTION_DISMISS, nil);
}
- (void)pipettePanned:(UIPanGestureRecognizer *)pan {
    CGPoint point = [pan locationInView:_canvas];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        UIColor *color = [self colorAtCanvasPoint:point];
        if (color) [self showLoupeAtCanvasPoint:point color:color];
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        UIColor *color = [self colorAtCanvasPoint:point];
        if (color) [self setPaintColor:color];
        [self endPipette];
    } else if (pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) [self hideLoupe];
}

#pragma mark - gestures

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (_exporting) return NO;
    if (gesture == _pinch || gesture == _zoomPan) return YES;
    /* a stroke may start while the last one is still being rendered, it is shown from the canvas until the render has it */
    return (_mode == 1 && !_rendering) || _mode == 3;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return a == _pinch || b == _pinch || a == _zoomPan || b == _zoomPan;
}
- (CGPoint)normalized:(CGPoint)point {
    CGRect rect = _canvas.imageRect;
    if (rect.size.width <= 0 || rect.size.height <= 0) return CGPointZero;
    return CGPointMake(MAX(0, MIN(1, (point.x - rect.origin.x) / rect.size.width)), MAX(0, MIN(1, (point.y - rect.origin.y) / rect.size.height)));
}
- (NSArray *)trailPoints {
    NSMutableArray *points = [NSMutableArray array];
    for (NSValue *value in _canvas.trail) [points addObject:[NSValue valueWithCGPoint:[self normalized:[value CGPointValue]]]];
    return points;
}
- (NSDictionary *)stroke {
    /* a blurred band is wider than a line of ink to hide the same thing, so the brush is three times the size the slider shows; while it is drawn it shows as a pale band */
    if (_blurBrush)
        return [NSDictionary dictionaryWithObjectsAndKeys:@"blur", @"kind", [[_points copy] autorelease], @"points", [UIColor colorWithWhite:1 alpha:0.32], @"color",
                [NSNumber numberWithDouble:MIN(0.25, _brushWidth * 3)], @"width", nil];
    return [NSDictionary dictionaryWithObjectsAndKeys:@"stroke", @"kind", [[_points copy] autorelease], @"points", _color, @"color", [NSNumber numberWithDouble:_brushWidth], @"width", [NSNumber numberWithBool:_arrow], @"arrow", nil];
}
- (void)panned:(UIPanGestureRecognizer *)pan {
    if (_pipette && _mode == 3) { [self pipettePanned:pan]; return; }
    BOOL drawing = _mode == 3;
    CGPoint point = [self normalized:[pan locationInView:_canvas]];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _panStart = point;
        if (_mode == 1) {
            [self stopCropAnimation];
            _cropStart = _canvas.crop; _cropCorner = -1;
            CGFloat distance = CGFLOAT_MAX;
            /* a handle is grabbed within a fingertip of it as seen, however far the picture is zoomed in */
            CGFloat reach = 44 / MAX(0.2, (CGFloat)(_zoom * _fit));
            for (NSInteger corner = 0; corner < 4; ++corner) {
                CGPoint handle = CGPointMake(corner & 1 ? CGRectGetMaxX(_cropStart) : _cropStart.origin.x, corner & 2 ? CGRectGetMaxY(_cropStart) : _cropStart.origin.y);
                CGFloat dx = (point.x - handle.x) * _canvas.imageRect.size.width, dy = (point.y - handle.y) * _canvas.imageRect.size.height;
                CGFloat d = hypot(dx, dy);
                if (d < distance && d < reach) { distance = d; _cropCorner = corner; }
            }
        } else if (drawing) {
            _movingText = _mode == 3 && _selectedText >= 0 && [self textAtPoint:point] == _selectedText;
            if (_movingText) _moveOriginal = [[[_operations objectAtIndex:(NSUInteger)_selectedText] objectForKey:@"point"] CGPointValue];
            if (!_movingText) { if (_mode == 3) [self selectText:-1]; [_points release]; _points = [[NSMutableArray alloc] initWithArray:[self trailPoints]]; }
        }
    }
    if (_mode == 1) {
        CGRect rect = _cropStart;
        if (_cropCorner < 0) {
            rect.origin.x = MAX(0, MIN(1 - rect.size.width, rect.origin.x + point.x - _panStart.x));
            rect.origin.y = MAX(0, MIN(1 - rect.size.height, rect.origin.y + point.y - _panStart.y));
        } else {
            CGFloat left = rect.origin.x, right = CGRectGetMaxX(rect), top = rect.origin.y, bottom = CGRectGetMaxY(rect);
            if (_cropCorner & 1) right = MAX(left + 0.08, MIN(1, point.x)); else left = MAX(0, MIN(right - 0.08, point.x));
            if (_cropCorner & 2) bottom = MAX(top + 0.08, MIN(1, point.y)); else top = MAX(0, MIN(bottom - 0.08, point.y));
            if (_cropRatio > 0) {
                CGFloat anchorX = _cropCorner & 1 ? _cropStart.origin.x : CGRectGetMaxX(_cropStart);
                CGFloat anchorY = _cropCorner & 2 ? _cropStart.origin.y : CGRectGetMaxY(_cropStart);
                CGFloat width = MAX(fabs(point.x - anchorX), fabs(point.y - anchorY) * _cropRatio);
                CGFloat height = width / _cropRatio;
                CGFloat maximumWidth = _cropCorner & 1 ? 1 - anchorX : anchorX;
                CGFloat maximumHeight = _cropCorner & 2 ? 1 - anchorY : anchorY;
                width = MAX(0.02, MIN(width, MIN(maximumWidth, maximumHeight * _cropRatio)));
                height = width / _cropRatio;
                left = _cropCorner & 1 ? anchorX : anchorX - width; right = left + width;
                top = _cropCorner & 2 ? anchorY : anchorY - height; bottom = top + height;
            }
            rect = CGRectMake(left, top, right - left, bottom - top);
        }
        _canvas.crop = rect;
    } else if (_mode == 3 && _movingText) {
        CGPoint moved = CGPointMake(MAX(0, MIN(1, _moveOriginal.x + point.x - _panStart.x)), MAX(0, MIN(1, _moveOriginal.y + point.y - _panStart.y)));
        [self updateSelectedText:@"point" value:[NSValue valueWithCGPoint:moved]];
    } else if (drawing && _points) {
        if (_points.count < EDIT_POINTS_MAX) [_points addObject:[NSValue valueWithCGPoint:point]];
        _canvas.stroke = [self stroke];
    }
    [_canvas setNeedsDisplay];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        if (_mode == 1 && pan.state != UIGestureRecognizerStateEnded) _canvas.crop = _cropStart;
        if (drawing) {
            if (_movingText && pan.state != UIGestureRecognizerStateEnded) [self updateSelectedText:@"point" value:[NSValue valueWithCGPoint:_moveOriginal]];
            _movingText = NO;
            if (pan.state == UIGestureRecognizerStateEnded && _points.count && (_points.count >= 2 || !_arrow)) [self append:[self stroke]];
            _canvas.stroke = nil;
            [_canvas setNeedsDisplay];
            [_points release]; _points = nil;
        }
    }
}
- (NSInteger)textAtPoint:(CGPoint)point {
    CGSize size = _canvas.image.size;
    if (size.width < 1 || size.height < 1) return -1;
    for (NSInteger i = (NSInteger)_operations.count - 1; i >= 0; --i) {
        NSDictionary *operation = [_operations objectAtIndex:(NSUInteger)i];
        NSString *kind = [operation objectForKey:@"kind"];
        if ([kind isEqualToString:@"text"]) {
            CGRect rect = CGRectInset(ExteriaPhotoTextRect(operation, size), -12, -12);
            if (CGRectContainsPoint(rect, CGPointMake(point.x * size.width, point.y * size.height))) return i;
        } else if (![kind isEqualToString:@"stroke"] && ![kind isEqualToString:@"blur"]) break;
    }
    return -1;
}
- (void)selectText:(NSInteger)index {
    _selectedText = index;
    _canvas.selection = CGRectZero;
    if (index >= 0 && (NSUInteger)index < _operations.count) {
        NSDictionary *operation = [_operations objectAtIndex:(NSUInteger)index];
        CGSize size = _canvas.image.size;
        CGRect rect = ExteriaPhotoTextRect(operation, size);
        if (size.width > 0 && size.height > 0)
            _canvas.selection = CGRectMake(rect.origin.x / size.width, rect.origin.y / size.height, rect.size.width / size.width, rect.size.height / size.height);
        NSNumber *value = [operation objectForKey:@"size"];
        _slider.minimumValue = 0.02; _slider.maximumValue = 0.20; _slider.value = value ? [value floatValue] : 0.065;
        _slider.accessibilityLabel = NSLocalizedString(@"media.text", nil);
    } else {
        _selectedText = -1; _slider.minimumValue = 0.003; _slider.maximumValue = 0.06; _slider.value = _brushWidth;
        _slider.accessibilityLabel = NSLocalizedString(@"media.brush", nil);
    }
    [self refreshTitle];
    [_canvas setNeedsDisplay];
}
- (void)updateSelectedText:(NSString *)key value:(id)value {
    if (_selectedText < 0 || (NSUInteger)_selectedText >= _operations.count) return;
    NSMutableDictionary *operation = [[[_operations objectAtIndex:(NSUInteger)_selectedText] mutableCopy] autorelease];
    [operation setObject:value forKey:key];
    [_operations replaceObjectAtIndex:(NSUInteger)_selectedText withObject:operation];
    [self selectText:_selectedText]; [self requestRender];
}
- (void)tapped:(UITapGestureRecognizer *)tap {
    if (_mode != 3 || _exporting) return;
    if (_pipette) {
        UIColor *color = [self colorAtCanvasPoint:[tap locationInView:_canvas]];
        if (color) [self setPaintColor:color];
        [self endPipette];
        return;
    }
    CGPoint point = [self normalized:[tap locationInView:_canvas]];
    NSInteger selected = [self textAtPoint:point];
    if (selected >= 0) { [self selectText:selected]; return; }
    if (_selectedText >= 0) { [self selectText:-1]; return; }
    if (_points) return;
    NSMutableArray *trail = [NSMutableArray arrayWithArray:[self trailPoints]];
    if (!trail.count) [trail addObject:[NSValue valueWithCGPoint:point]];
    if (_arrow && trail.count < 2) return;
    _points = [[NSMutableArray alloc] initWithArray:trail];
    [self append:[self stroke]];
    [_points release]; _points = nil;
}
- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan || _mode != 3 || _exporting || _pipette || _points) return;
    _textPoint = [self normalized:[hold locationInView:_canvas]];
    NSInteger selected = [self textAtPoint:_textPoint];
    if (selected >= 0) [self selectText:selected]; else [self selectText:-1];
    [self addText];
}
- (void)addText {
    if (_mode != 3) return;
    _alertText = _selectedText;
    if (_textPoint.x == 0 && _textPoint.y == 0) _textPoint = CGPointMake(0.5, 0.5);
    UIAlertView *alert = [[ExteriaAlertClass() alloc] initWithTitle:NSLocalizedString(@"media.text", nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"attach.cancel", nil) otherButtonTitles:NSLocalizedString(@"media.apply", nil), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.textColor = [UIColor blackColor]; field.backgroundColor = [UIColor whiteColor];
    if (_alertText >= 0 && (NSUInteger)_alertText < _operations.count) field.text = [[_operations objectAtIndex:(NSUInteger)_alertText] objectForKey:@"text"];
    [alert show]; [alert release];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
    if (index == alert.cancelButtonIndex || _closed || _mode != 3) return;
    NSString *text = [alert textFieldAtIndex:0].text;
    if (!text.length) return;
    if (text.length > 256) { [self notice:@"media.text.limit"]; return; }
    if (_alertText >= 0 && _selectedText == _alertText) [self updateSelectedText:@"text" value:text];
    else {
        NSUInteger count = _operations.count;
        [self append:[NSDictionary dictionaryWithObjectsAndKeys:@"text", @"kind", text, @"text", [NSValue valueWithCGPoint:_textPoint], @"point", _color, @"color", nil]];
        if (_operations.count > count) [self selectText:(NSInteger)count];
    }
}

#pragma mark - render

- (void)requestRender {
    ++_generation; _needsRender = YES;
    if (_rendering || _closed || _exporting) return;
    [self startRender];
}
/* the settling a finished edit plays: a turn for rotate, a flip for mirror, a small pop for the rest that change the picture as a whole */
- (void)playEnter {
    NSInteger kind = _enter;
    _enter = ExteriaPhotoEnterNone;
    if (kind == ExteriaPhotoEnterNone || !_stage.window) return;
    CGAffineTransform now = _stage.transform, from = now;
    if (kind == ExteriaPhotoEnterRotate) from = CGAffineTransformConcat(CGAffineTransformMakeRotation((CGFloat)(-M_PI_2)), now);
    else if (kind == ExteriaPhotoEnterFlip) from = CGAffineTransformConcat(CGAffineTransformMakeScale(-1, 1), now);
    else from = CGAffineTransformConcat(CGAffineTransformMakeScale(0.9, 0.9), now);
    ExteriaAnimateEnter(_stage, from, kind == ExteriaPhotoEnterPop ? 0.4 : 1, EXTERIA_MOTION_SPRING);
}
- (void)startRender {
    _rendering = YES; _needsRender = NO;
    NSUInteger generation = _generation;
    NSMutableArray *operations = [NSMutableArray arrayWithArray:_operations];
    if (_mode == 2) [operations addObject:[self adjustmentOperation]];
    NSArray *snapshot = [operations copy]; UIImage *source = [_source retain]; ExteriaWeakReference *weak = _weak;
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *image = [ExteriaPhotoRender(source, snapshot, EDIT_PREVIEW_SIDE_MAX) retain];
        [source release]; [snapshot release];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaPhotoEditor *me = weak.target;
            if (me && !me->_closed) {
                me->_rendering = NO;
                if (me->_generation == generation) {
                    [me->_canvas.pending removeAllObjects];
                    if (image) {
                        BOOL reshaped = !CGSizeEqualToSize(me->_canvas.image.size, image.size);
                        me->_canvas.image = image; me->_photo.image = image;
                        if (reshaped) { me->_zoom = 1; me->_offsetX = me->_offsetY = 0; [me applyStageAnimated:NO]; }
                        [me layoutPhoto];
                        if (me->_selectedText >= 0) [me selectText:me->_selectedText];
                        [me->_canvas setNeedsDisplay];
                        [me playEnter];
                    }
                    else { me->_enter = ExteriaPhotoEnterNone; [me notice:@"media.edit.failed"]; }
                }
                me->_undo.enabled = [me undoAvailable];
                if (me->_needsRender && !me->_exporting) [me startRender];
            }
            [image release];
        });
        [pool drain];
    });
}
- (void)done {
    if (_mode || _exporting || _closed) return;
    _exporting = YES; _done.enabled = NO; _undo.enabled = NO; _tools.userInteractionEnabled = NO;
    [_spinner startAnimating];
    NSArray *snapshot = [_operations copy]; UIImage *source = [_source retain]; ExteriaWeakReference *weak = _weak;
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *result = [ExteriaPhotoRender(source, snapshot, EXTERIA_PHOTO_SIDE_MAX) retain];
        [source release]; [snapshot release];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaPhotoEditor *me = weak.target;
            if (me && !me->_closed) {
                [me->_spinner stopAnimating]; me->_exporting = NO; me->_done.enabled = YES; me->_undo.enabled = [me undoAvailable]; me->_tools.userInteractionEnabled = YES;
                if (!result) [me notice:@"media.edit.failed"];
                else {
                    me->_closed = YES;
                    void (^completion)(UIImage *) = [[me->_completion copy] autorelease];
                    [me dismissViewControllerAnimated:YES completion:^{ if (completion) completion(result); }];
                }
            }
            [result release];
        });
        [pool drain];
    });
}
- (void)cancel { _closed = YES; ++_generation; [self dismissViewControllerAnimated:YES completion:nil]; }
@end
