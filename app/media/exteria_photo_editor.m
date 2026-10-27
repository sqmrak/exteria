#import "exteria_slider.h"
#import "exteria_photo_editor.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_photo_edit.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"

#define EDIT_OPERATIONS_MAX 32
#define EDIT_POINTS_MAX 4096

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
    if ([[operation objectForKey:@"arrow"] boolValue]) {
        /* an arrow runs straight from where the finger came down to where it is, and ends in two strokes that make the head, as the arrow of the original editor does */
        if (points.count < 2) return;
        CGPoint last = [[points lastObject] CGPointValue];
        CGPoint from = CGPointMake(first.x * size.width, first.y * size.height), tip = CGPointMake(last.x * size.width, last.y * size.height);
        CGFloat length = hypot(tip.x - from.x, tip.y - from.y);
        if (length < 1) return;
        /* the head is as long as the stroke is thick several times over, never more than half of the arrow */
        CGFloat head = MIN(length * 0.5, MAX(width * 4, MIN(size.width, size.height) * 0.05));
        CGFloat angle = atan2(tip.y - from.y, tip.x - from.x), spread = 28 * M_PI / 180;
        CGContextMoveToPoint(context, from.x, from.y);
        CGContextAddLineToPoint(context, tip.x, tip.y);
        CGContextMoveToPoint(context, tip.x - head * cos(angle - spread), tip.y - head * sin(angle - spread));
        CGContextAddLineToPoint(context, tip.x, tip.y);
        CGContextAddLineToPoint(context, tip.x - head * cos(angle + spread), tip.y - head * sin(angle + spread));
        CGContextStrokePath(context);
        return;
    }
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

static UIImage *ExteriaPhotoApply(UIImage *image, NSDictionary *operation) {
    NSString *kind = [operation objectForKey:@"kind"];
    CGSize size = image.size;
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
    CGRect _selection;
}
@property (nonatomic, retain) UIImage *image;
@property (nonatomic, assign) CGRect crop;
@property (nonatomic, assign) BOOL cropping;
@property (nonatomic, retain) NSDictionary *stroke;
@property (nonatomic, assign) CGRect selection;
@property (nonatomic, readonly) CGRect imageRect;
@end
@implementation ExteriaPhotoCanvas
@synthesize image = _image, crop = _crop, cropping = _cropping, stroke = _stroke, selection = _selection;
- (void)dealloc { [_image release]; [_stroke release]; [super dealloc]; }
- (CGRect)imageRect { return ExteriaPhotoFit(_image.size, CGRectInset(self.bounds, 12, 12)); }
- (void)drawRect:(CGRect)rect {
    CGRect imageRect = self.imageRect;
    if (CGRectIsEmpty(imageRect)) return;
    [_image drawInRect:imageRect];
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (_stroke) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, imageRect.origin.x, imageRect.origin.y);
        ExteriaPhotoDrawStroke(_stroke, imageRect.size);
        CGContextRestoreGState(context);
    }
    if (!CGRectIsEmpty(_selection)) {
        CGRect selected = CGRectMake(imageRect.origin.x + _selection.origin.x * imageRect.size.width,
                                     imageRect.origin.y + _selection.origin.y * imageRect.size.height,
                                     _selection.size.width * imageRect.size.width, _selection.size.height * imageRect.size.height);
        CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextSetLineWidth(context, 1);
        CGContextStrokeRect(context, CGRectInset(selected, -5, -5));
    }
    if (!_cropping) return;
    CGRect crop = CGRectMake(imageRect.origin.x + _crop.origin.x * imageRect.size.width, imageRect.origin.y + _crop.origin.y * imageRect.size.height,
                             _crop.size.width * imageRect.size.width, _crop.size.height * imageRect.size.height);
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
    CGContextAddRect(context, imageRect); CGContextAddRect(context, crop); CGContextEOFillPath(context);
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor); CGContextSetLineWidth(context, 1);
    CGContextStrokeRect(context, crop);
    for (int i = 1; i < 3; ++i) {
        CGFloat x = crop.origin.x + crop.size.width * i / 3, y = crop.origin.y + crop.size.height * i / 3;
        CGContextMoveToPoint(context, x, crop.origin.y); CGContextAddLineToPoint(context, x, CGRectGetMaxY(crop));
        CGContextMoveToPoint(context, crop.origin.x, y); CGContextAddLineToPoint(context, CGRectGetMaxX(crop), y);
    }
    CGContextStrokePath(context);
    for (int corner = 0; corner < 4; ++corner) {
        CGFloat x = corner & 1 ? CGRectGetMaxX(crop) : crop.origin.x;
        CGFloat y = corner & 2 ? CGRectGetMaxY(crop) : crop.origin.y;
        CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextFillEllipseInRect(context, CGRectMake(x - 5, y - 5, 10, 10));
    }
}
@end

@interface ExteriaPhotoEditor () <UIGestureRecognizerDelegate, UIAlertViewDelegate> {
    UIImage *_source;
    NSMutableArray *_operations;
    NSArray *_modeSnapshot;
    ExteriaWeakReference *_weak;
    void (^_completion)(UIImage *);
    dispatch_queue_t _work;
    ExteriaPhotoCanvas *_canvas;
    UIView *_top;
    UIScrollView *_tools;
    UIView *_options;
    UIButton *_done;
    UIButton *_cancel;
    UIButton *_apply;
    UIButton *_back;
    UIButton *_undo;
    UILabel *_value;
    UISlider *_slider;
    UIScrollView *_choices;
    UIActivityIndicatorView *_spinner;
    NSMutableArray *_points;
    UIColor *_color;
    exteria_photo_adjustments _adjustments;
    NSUInteger _generation;
    NSUInteger _modeStart;
    NSInteger _tool;
    NSInteger _mode;
    NSInteger _cropCorner;
    NSInteger _selectedText;
    NSInteger _alertText;
    BOOL _movingText;
    CGRect _cropStart;
    CGPoint _panStart;
    CGPoint _textPoint;
    CGPoint _moveOriginal;
    CGFloat _brushWidth;
    CGFloat _cropRatio;
    BOOL _arrow;
    UIButton *_arrowButton;
    BOOL _rendering;
    BOOL _needsRender;
    BOOL _closed;
    BOOL _exporting;
    BOOL _statusHidden;
}
@end

@implementation ExteriaPhotoEditor
- (id)initWithImage:(UIImage *)image completion:(void (^)(UIImage *))completion {
    self = [super init];
    if (self) {
        _source = [image retain]; _completion = [completion copy];
        _operations = [[NSMutableArray alloc] init]; _weak = [[ExteriaWeakReference referenceTo:self] retain];
        _work = dispatch_queue_create("com.exteria.photo-editor", DISPATCH_QUEUE_SERIAL);
        _selectedText = -1; _alertText = -1;
        _color = [[UIColor whiteColor] retain]; _brushWidth = 0.012;
        self.wantsFullScreenLayout = YES; self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}
- (void)dealloc {
    [_weak clear]; [_source release]; [_completion release]; [_operations release]; [_modeSnapshot release]; [_weak release];
    dispatch_release(_work);
    [_canvas release]; [_top release]; [_tools release]; [_options release];
    [_done release]; [_cancel release]; [_apply release]; [_back release]; [_undo release]; [_arrowButton release];
    [_value release]; [_slider release]; [_choices release]; [_spinner release]; [_points release]; [_color release];
    [super dealloc];
}
- (UIButton *)textButton:(NSString *)title action:(SEL)action host:(UIView *)host {
    UIButton *button = [[UIButton alloc] init];
    [button setTitle:NSLocalizedString(title, nil) forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1 alpha:0.55] forState:UIControlStateHighlighted];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:button]; return button;
}
- (void)loadView {
    self.view = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease]; self.view.backgroundColor = [UIColor blackColor];
    _canvas = [[ExteriaPhotoCanvas alloc] init]; _canvas.backgroundColor = [UIColor blackColor];
    _canvas.image = _source; [self.view addSubview:_canvas];
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)] autorelease];
    pan.maximumNumberOfTouches = 1; pan.delegate = self; [_canvas addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    [_canvas addGestureRecognizer:tap];
    _top = [[UIView alloc] init]; [self.view addSubview:_top];
    if (!ExteriaThemeIsClassic()) {
        _top.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        _top.layer.cornerRadius = 12;
    }
    _cancel = [self textButton:@"attach.cancel" action:@selector(cancel) host:_top];
    _done = [self textButton:@"media.done" action:@selector(done) host:_top];
    _undo = [self textButton:@"media.undo" action:@selector(undo) host:_top];
    _tools = [[UIScrollView alloc] init]; _tools.showsHorizontalScrollIndicator = NO; [self.view addSubview:_tools];
    const ExteriaSymbol symbols[] = {ExteriaSymbolCrop, ExteriaSymbolAdjust, ExteriaSymbolDraw, ExteriaSymbolRotate, ExteriaSymbolMirror, ExteriaSymbolBroom};
    NSArray *names = [NSArray arrayWithObjects:@"media.crop", @"media.adjust", @"media.draw", @"media.rotate", @"media.flip", @"media.reset", nil];
    for (NSUInteger i = 0; i < names.count; ++i) {
        UIButton *button = [self textButton:[names objectAtIndex:i] action:@selector(toolPressed:) host:_tools];
        [button setTitle:nil forState:UIControlStateNormal];
        [button setImage:ExteriaSymbolImage(symbols[i], 28, [UIColor whiteColor]) forState:UIControlStateNormal];
        button.accessibilityLabel = NSLocalizedString([names objectAtIndex:i], nil);
        button.tag = (NSInteger)i; button.frame = CGRectMake(i * 64, 0, 64, 52); [button release];
    }
    _tools.contentSize = CGSizeMake(names.count * 64, 52);
    _options = [[UIView alloc] init]; [self.view addSubview:_options];
    if (!ExteriaThemeIsClassic()) {
        _tools.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        _tools.layer.cornerRadius = 12;
        _options.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        _options.layer.cornerRadius = 12;
    }
    _back = [self textButton:@"attach.cancel" action:@selector(cancelMode) host:_options];
    _apply = [self textButton:@"media.apply" action:@selector(applyMode) host:_options];
    _value = [[UILabel alloc] init]; _value.backgroundColor = [UIColor clearColor]; _value.textColor = [UIColor whiteColor];
    _value.font = [UIFont systemFontOfSize:13]; _value.adjustsFontSizeToFitWidth = YES; _value.minimumFontSize = 10; _value.textAlignment = UITextAlignmentCenter; [_options addSubview:_value];
    _slider = [[ExteriaSlider alloc] init];
    [_slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged]; [_options addSubview:_slider];
    _choices = [[UIScrollView alloc] init]; _choices.showsHorizontalScrollIndicator = NO; [_options addSubview:_choices];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES; [self.view addSubview:_spinner];
    [self refreshMode]; [self requestRender];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _statusHidden = [UIApplication sharedApplication].statusBarHidden;
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:_statusHidden withAnimation:UIStatusBarAnimationNone];
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
#else
- (NSUInteger)supportedInterfaceOrientations
#endif
{ return UIInterfaceOrientationMaskAll; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
    /* the picture sits between the bars, so the notch and the home indicator are given to the bars: the buttons stand clear of them, in landscape too */
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = insets.top, bottom = insets.bottom, left = insets.left, right = insets.right, inner = MAX(0, width - left - right);
    _top.frame = CGRectMake(0, top, width, 48);
    _cancel.frame = CGRectMake(left + 4, 0, 84, 48); _done.frame = CGRectMake(width - right - 88, 0, 84, 48);
    _undo.frame = CGRectMake(width / 2 - 45, 0, 90, 48);
    CGFloat options = _mode == 2 || _mode == 3 ? 150 : 98;
    _tools.frame = CGRectMake(left, height - bottom - 52, inner, 52);
    _options.frame = CGRectMake(0, height - bottom - options, width, options);
    _canvas.frame = CGRectMake(0, top + 48, width, MAX(1, height - top - 48 - bottom - (_mode ? options : 52)));
    _back.frame = CGRectMake(left + 4, options - 44, 90, 44); _apply.frame = CGRectMake(width - right - 104, options - 44, 100, 44);
    _choices.frame = CGRectMake(left, 0, inner, 50);
    _value.frame = CGRectMake(left + 100, options - 42, MAX(0, inner - 204), 40);
    _slider.frame = CGRectMake(left + 20, 54, MAX(0, inner - 40), 40);
    _spinner.center = CGPointMake(width / 2, height / 2);
    [_canvas setNeedsDisplay];
}
- (void)notice:(NSString *)key {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:NSLocalizedString(key, nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show]; [alert release];
}
- (void)refreshMode {
    _tools.hidden = _mode != 0; _options.hidden = _mode == 0;
    _done.enabled = !_mode && !_exporting; _undo.enabled = _operations.count > 0 && !_exporting;
    _canvas.cropping = _mode == 1; _slider.hidden = _mode != 2 && _mode != 3;
    _canvas.crop = CGRectMake(0, 0, 1, 1); _cropRatio = 0;
    for (UIView *view in [[_choices.subviews copy] autorelease]) [view removeFromSuperview];
    if (_mode == 1) {
        NSArray *names = [NSArray arrayWithObjects:@"media.free", @"1:1", @"4:3", @"3:4", @"16:9", @"9:16", nil];
        for (NSUInteger i = 0; i < names.count; ++i) {
            UIButton *button = [self textButton:[names objectAtIndex:i] action:@selector(aspect:) host:_choices];
            button.frame = CGRectMake(i * 68, 0, 68, 48); button.tag = (NSInteger)i; [button release];
        }
        _choices.contentSize = CGSizeMake(names.count * 68, 48); _value.text = @"";
    } else if (_mode == 2) {
        for (NSInteger i = 0; i < EXTERIA_PHOTO_TOOLS; ++i) {
            UIButton *button = [self textButton:ExteriaPhotoToolNames[i] action:@selector(adjustTool:) host:_choices];
            button.frame = CGRectMake(i * 112, 0, 112, 48); button.tag = i; [button release];
        }
        _choices.contentSize = CGSizeMake(EXTERIA_PHOTO_TOOLS * 112, 48);
        [self selectAdjustment:0];
    } else if (_mode == 3) {
        NSArray *colors = [NSArray arrayWithObjects:[UIColor whiteColor], [UIColor blackColor], [UIColor redColor], [UIColor yellowColor], [UIColor greenColor], [UIColor cyanColor], [UIColor blueColor], [UIColor magentaColor], nil];
        for (NSUInteger i = 0; i < colors.count; ++i) {
            UIButton *button = [[[UIButton alloc] init] autorelease];
            button.backgroundColor = [colors objectAtIndex:i]; button.frame = CGRectMake(12 + i * 42, 10, 28, 28);
            button.layer.cornerRadius = 14; button.layer.borderWidth = 1; button.layer.borderColor = [UIColor grayColor].CGColor;
            [button addTarget:self action:@selector(color:) forControlEvents:UIControlEventTouchUpInside]; [_choices addSubview:button];
        }
        [_arrowButton release];
        _arrowButton = [self textButton:@"media.arrow" action:@selector(toggleArrow) host:_choices];
        _arrowButton.frame = CGRectMake(352, 0, 90, 48);
        [self refreshArrowButton];
        UIButton *text = [self textButton:@"media.text" action:@selector(addText) host:_choices];
        CGFloat textWidth = MAX(90, ceil([NSLocalizedString(@"media.text", nil) sizeWithFont:text.titleLabel.font].width) + 24);
        text.frame = CGRectMake(442, 0, textWidth, 48); [text release]; _choices.contentSize = CGSizeMake(442 + textWidth + 6, 48);
        _slider.minimumValue = 0.003; _slider.maximumValue = 0.06; _slider.value = _brushWidth;
        _value.text = NSLocalizedString(@"media.brush", nil);
    }
    [self.view setNeedsLayout]; [_canvas setNeedsDisplay];
}
- (void)toolPressed:(UIButton *)button {
    if (_exporting || _rendering) return;
    if (button.tag < 3) {
        _mode = button.tag + 1; _modeStart = _operations.count; memset(&_adjustments, 0, sizeof(_adjustments));
        [_modeSnapshot release]; _modeSnapshot = [_operations copy]; _selectedText = -1;
        [self refreshMode];
    } else if (button.tag == 5) {
        [_operations removeAllObjects]; [self requestRender];
    } else [self append:[NSDictionary dictionaryWithObject:button.tag == 3 ? @"rotate" : @"flip" forKey:@"kind"]];
}
- (void)append:(NSDictionary *)operation {
    if (_operations.count >= EDIT_OPERATIONS_MAX) { [self notice:@"media.edit.limit"]; return; }
    [_operations addObject:operation]; [self requestRender];
}
- (void)undo {
    if (_exporting) return;
    if (_mode == 3) [self selectText:-1];
    if (_mode == 2) { memset(&_adjustments, 0, sizeof(_adjustments)); [self selectAdjustment:_tool]; }
    else if (_operations.count && (!_mode || _operations.count > _modeStart)) [_operations removeLastObject];
    [self requestRender];
}
- (void)aspect:(UIButton *)button {
    const double ratios[] = {0, 1, 4.0/3, 3.0/4, 16.0/9, 9.0/16};
    if (button.tag < 0 || button.tag > 5 || !_canvas.image) return;
    double ratio = ratios[button.tag], imageRatio = _canvas.image.size.width / _canvas.image.size.height;
    CGRect rect = CGRectMake(0, 0, 1, 1);
    if (ratio > 0) {
        if (imageRatio > ratio) { rect.size.width = ratio / imageRatio; rect.origin.x = (1 - rect.size.width) / 2; }
        else { rect.size.height = imageRatio / ratio; rect.origin.y = (1 - rect.size.height) / 2; }
    }
    _cropRatio = ratio > 0 ? rect.size.width / rect.size.height : 0;
    _canvas.crop = rect; [_canvas setNeedsDisplay];
}
- (void)adjustTool:(UIButton *)button { [self selectAdjustment:button.tag]; }
- (void)selectAdjustment:(NSInteger)tool {
    if (tool < 0 || tool >= EXTERIA_PHOTO_TOOLS) return;
    _tool = tool;
    _slider.minimumValue = tool == EXTERIA_PHOTO_FADE || tool >= EXTERIA_PHOTO_VIGNETTE ? 0 : -1;
    _slider.maximumValue = 1; _slider.value = _adjustments.values[tool];
    _value.text = [NSString stringWithFormat:@"%+.0f", _slider.value * 100];
    _slider.accessibilityLabel = NSLocalizedString(ExteriaPhotoToolNames[tool], nil);
}
- (void)sliderChanged {
    if (_mode == 3) {
        if (_selectedText >= 0) [self updateSelectedText:@"size" value:[NSNumber numberWithFloat:_slider.value]];
        else _brushWidth = _slider.value;
        return;
    }
    _adjustments.values[_tool] = _slider.value;
    _value.text = [NSString stringWithFormat:@"%+.0f", _slider.value * 100]; [self requestRender];
}
- (NSDictionary *)adjustmentOperation {
    return [NSDictionary dictionaryWithObjectsAndKeys:@"adjust", @"kind", [NSData dataWithBytes:&_adjustments length:sizeof(_adjustments)], @"settings", nil];
}
- (void)applyMode {
    if (_mode == 1) [self append:[NSDictionary dictionaryWithObjectsAndKeys:@"crop", @"kind", [NSValue valueWithCGRect:_canvas.crop], @"rect", nil]];
    else if (_mode == 2) [self append:[self adjustmentOperation]];
    _mode = 0; _selectedText = -1; _canvas.selection = CGRectZero; _canvas.stroke = nil;
    [_modeSnapshot release]; _modeSnapshot = nil; [self refreshMode]; [self requestRender];
}
- (void)cancelMode {
    if (_modeSnapshot) [_operations setArray:_modeSnapshot];
    _mode = 0; _selectedText = -1; _canvas.selection = CGRectZero; _canvas.stroke = nil;
    [_modeSnapshot release]; _modeSnapshot = nil; [self refreshMode]; [self requestRender];
}
/* the arrow is on while its button is lit; the pen is what is left when it is off */
- (void)toggleArrow {
    _arrow = !_arrow;
    [self refreshArrowButton];
}
- (void)refreshArrowButton {
    [_arrowButton setTitleColor:_arrow ? [UIColor colorWithRed:0.35 green:0.65 blue:1 alpha:1] : [UIColor whiteColor] forState:UIControlStateNormal];
    _arrowButton.accessibilityTraits = UIAccessibilityTraitButton | (_arrow ? UIAccessibilityTraitSelected : 0);
}
- (void)color:(UIButton *)button {
    [_color release]; _color = [button.backgroundColor retain];
    if (_selectedText >= 0) [self updateSelectedText:@"color" value:_color];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture { return (_mode == 1 || _mode == 3) && !_exporting && !_rendering; }
- (CGPoint)normalized:(CGPoint)point {
    CGRect rect = _canvas.imageRect;
    if (rect.size.width <= 0 || rect.size.height <= 0) return CGPointZero;
    return CGPointMake(MAX(0, MIN(1, (point.x - rect.origin.x) / rect.size.width)), MAX(0, MIN(1, (point.y - rect.origin.y) / rect.size.height)));
}
- (NSDictionary *)stroke {
    return [NSDictionary dictionaryWithObjectsAndKeys:@"stroke", @"kind", [[_points copy] autorelease], @"points", _color, @"color", [NSNumber numberWithDouble:_brushWidth], @"width", [NSNumber numberWithBool:_arrow], @"arrow", nil];
}
- (void)panned:(UIPanGestureRecognizer *)pan {
    CGPoint point = [self normalized:[pan locationInView:_canvas]];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _panStart = point;
        if (_mode == 1) {
            _cropStart = _canvas.crop; _cropCorner = -1;
            CGFloat distance = CGFLOAT_MAX;
            for (NSInteger corner = 0; corner < 4; ++corner) {
                CGPoint handle = CGPointMake(corner & 1 ? CGRectGetMaxX(_cropStart) : _cropStart.origin.x, corner & 2 ? CGRectGetMaxY(_cropStart) : _cropStart.origin.y);
                CGFloat dx = (point.x - handle.x) * _canvas.imageRect.size.width, dy = (point.y - handle.y) * _canvas.imageRect.size.height;
                CGFloat d = hypot(dx, dy);
                if (d < distance && d < 44) { distance = d; _cropCorner = corner; }
            }
        } else if (_mode == 3) {
            _movingText = _selectedText >= 0 && [self textAtPoint:point] == _selectedText;
            if (_movingText) _moveOriginal = [[[_operations objectAtIndex:(NSUInteger)_selectedText] objectForKey:@"point"] CGPointValue];
            if (!_movingText) { [self selectText:-1]; [_points release]; _points = [[NSMutableArray alloc] init]; }
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
    } else if (_mode == 3 && _points) {
        /* an arrow keeps its first point and follows the finger with the second, however long the drag */
        if (_arrow && _points.count >= 2) [_points replaceObjectAtIndex:_points.count - 1 withObject:[NSValue valueWithCGPoint:point]];
        else if (_points.count < EDIT_POINTS_MAX) [_points addObject:[NSValue valueWithCGPoint:point]];
        _canvas.stroke = [self stroke];
    }
    [_canvas setNeedsDisplay];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        if (_mode == 1 && pan.state != UIGestureRecognizerStateEnded) _canvas.crop = _cropStart;
        if (_mode == 3) {
            if (_movingText && pan.state != UIGestureRecognizerStateEnded) [self updateSelectedText:@"point" value:[NSValue valueWithCGPoint:_moveOriginal]];
            _movingText = NO;
            if (pan.state == UIGestureRecognizerStateEnded && _points.count && (!_arrow || _points.count >= 2)) [self append:[self stroke]];
            if (pan.state != UIGestureRecognizerStateEnded) _canvas.stroke = nil;
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
        } else if (![kind isEqualToString:@"stroke"]) break;
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
        _value.text = NSLocalizedString(@"media.text", nil);
        _slider.accessibilityLabel = NSLocalizedString(@"media.text", nil);
    } else {
        _selectedText = -1; _slider.minimumValue = 0.003; _slider.maximumValue = 0.06; _slider.value = _brushWidth;
        _value.text = NSLocalizedString(@"media.brush", nil);
        _slider.accessibilityLabel = NSLocalizedString(@"media.brush", nil);
    }
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
    if (_mode != 3 || _exporting || _rendering) return;
    _textPoint = [self normalized:[tap locationInView:_canvas]];
    NSInteger selected = [self textAtPoint:_textPoint];
    if (selected >= 0) {
        if (selected == _selectedText) [self addText];
        else [self selectText:selected];
    } else {
        [self selectText:-1]; [self addText];
    }
}
- (void)addText {
    if (_mode != 3) return;
    _alertText = _selectedText;
    if (_textPoint.x == 0 && _textPoint.y == 0) _textPoint = CGPointMake(0.5, 0.5);
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"media.text", nil) message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"attach.cancel", nil) otherButtonTitles:NSLocalizedString(@"media.apply", nil), nil];
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
- (void)requestRender {
    ++_generation; _needsRender = YES;
    if (_rendering || _closed || _exporting) return;
    [self startRender];
}
- (void)startRender {
    _rendering = YES; _needsRender = NO;
    NSUInteger generation = _generation;
    NSMutableArray *operations = [NSMutableArray arrayWithArray:_operations];
    if (_mode == 2) [operations addObject:[self adjustmentOperation]];
    NSArray *snapshot = [operations copy]; UIImage *source = [_source retain]; ExteriaWeakReference *weak = _weak;
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *image = [ExteriaPhotoRender(source, snapshot, EXTERIA_PHOTO_SIDE_MAX) retain];
        [source release]; [snapshot release];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaPhotoEditor *me = weak.target;
            if (me && !me->_closed) {
                me->_rendering = NO;
                if (me->_generation == generation) {
                    if (image) { me->_canvas.image = image; me->_canvas.stroke = nil; if (me->_selectedText >= 0) [me selectText:me->_selectedText]; [me->_canvas setNeedsDisplay]; }
                    else [me notice:@"media.edit.failed"];
                }
                me->_undo.enabled = me->_operations.count > 0;
                if (me->_needsRender && !me->_exporting) [me startRender];
            }
            [image release];
        });
        [pool drain];
    });
}
- (void)done {
    if (_mode || _exporting || _closed) return;
    _exporting = YES; _done.enabled = NO; _tools.userInteractionEnabled = NO;
    [_spinner startAnimating];
    NSArray *snapshot = [_operations copy]; UIImage *source = [_source retain]; ExteriaWeakReference *weak = _weak;
    dispatch_async(_work, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *result = [ExteriaPhotoRender(source, snapshot, EXTERIA_PHOTO_SIDE_MAX) retain];
        [source release]; [snapshot release];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaPhotoEditor *me = weak.target;
            if (me && !me->_closed) {
                [me->_spinner stopAnimating]; me->_exporting = NO; me->_done.enabled = YES; me->_tools.userInteractionEnabled = YES;
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
