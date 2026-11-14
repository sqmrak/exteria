#import "exteria_image_decoder.h"
#import "exteria_avatar_view.h"

#import "exteria_chat_settings.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_shape.h"
#import "exteria_theme.h"
#import <QuartzCore/QuartzCore.h>
#import "exteria_wave.h"

#define AVATAR_COLORS 7
/* the corner radius is the percent the person chose, in avatar sizes: 64 percent are the rounded squares of the official apps, 100 a circle */

@interface ExteriaAvatarView () {
    ExteriaEmojiLabel *_label;
    UIImage *_image;
    BOOL _imageHasAlpha;
    BOOL _imageIsRound;
    NSString *_photoKey;
}
@end

/* the gloss, the dark rim and the lit edge of a classic avatar of one size and corner, as a picture kept for the next ones */
static UIImage *ExteriaAvatarGlossOverlay(CGSize size, CGFloat radius) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 24;
    });
    NSString *key = [NSString stringWithFormat:@"%.1f|%.1f|%.1f|%.1f|%ld", size.width, size.height, radius, ExteriaScreenScale(), (long)ExteriaClassicGlossLevel()];
    UIImage *kept = [[[cache objectForKey:key] retain] autorelease];
    if (kept) return kept;
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    /* the gloss level of the customization lights the top of the picture: none, as before, or half again as strong */
    static const CGFloat levels[3] = {0, 1, 1.6f};
    CGFloat lit = levels[ExteriaClassicGlossLevel()];
    const CGFloat gloss[8] = {1, 1, 1, MIN(1, 0.26f * lit), 1, 1, 1, MIN(1, 0.02f * lit)};
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(-bounds.size.width * 0.15, -bounds.size.height * 0.52, bounds.size.width * 1.3, bounds.size.height * 1.1));
    CGContextClip(context);
    ExteriaFillGradient(context, CGPointZero, CGPointMake(0, bounds.size.height * 0.6), gloss, 2);
    CGContextRestoreGState(context);
    UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, 0.5, 0.5) cornerRadius:MAX(0, radius - 0.5)];
    [[UIColor colorWithWhite:0 alpha:0.24] setStroke];
    [rim stroke];
    CGContextClipToRect(context, CGRectMake(0, 0, bounds.size.width, bounds.size.height * 0.5));
    UIBezierPath *highlight = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, 1.5, 1.5) cornerRadius:MAX(0, radius - 1.5)];
    [[UIColor colorWithWhite:1 alpha:0.28] setStroke];
    [highlight stroke];
    UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (made) [cache setObject:made forKey:key];
    return made;
}

@implementation ExteriaAvatarView

@synthesize initials = _initials;
@synthesize showsSymbol = _showsSymbol;
@synthesize symbol = _symbol;
@synthesize accent = _accent;
@synthesize seed = _seed;
@synthesize circular = _circular;
@synthesize transparentPhoto = _transparentPhoto;
@synthesize deleted = _deleted;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    _label = [[ExteriaEmojiLabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = ExteriaTextAlignmentCenter;
    [self addSubview:_label];
    return self;
}

- (void)dealloc {
    [_image release];
    [_photoKey release];
    [_label release];
    [_initials release];
    [super dealloc];
}

- (void)setInitials:(NSString *)initials {
    if (initials == _initials || [initials isEqualToString:_initials]) return;
    [_initials release];
    _initials = [initials copy];
    _label.text = _initials;
    [self setNeedsDisplay];
}

/* the soft shadow of the classic customization falls under the picture, along its outline; a path keeps it from being worked out from the pixels at every frame */
- (void)applyClassicShadow {
    BOOL on = ExteriaThemeIsClassic() && ExteriaClassicAvatarShadow() && !CGRectIsEmpty(self.bounds);
    if (!on) {
        if (self.layer.shadowOpacity > 0) self.layer.shadowOpacity = 0;
        return;
    }
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat radius = side * (_circular || (_image && _imageIsRound) ? 0.5 : (CGFloat)ExteriaAvatarCornerPercent() / 200.0);
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.45f;
    self.layer.shadowRadius = MAX(1.5f, side * 0.05f);
    self.layer.shadowOffset = CGSizeMake(0, 1.5f);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyClassicShadow];
    /* the text layout uses at least 20 points, so center that width on small avatars */
    CGFloat labelWidth = MAX(20, self.bounds.size.width);
    _label.frame = CGRectMake((self.bounds.size.width - labelWidth) / 2, 0, labelWidth, self.bounds.size.height);
    UIFont *font = ExteriaFontSemibold(MIN(self.bounds.size.width, self.bounds.size.height) * 0.38);
    if (font != _label.font) _label.font = font;
    _label.hidden = _showsSymbol || _image != nil;
}

- (void)setShowsSymbol:(BOOL)showsSymbol { if (showsSymbol == _showsSymbol) return; _showsSymbol = showsSymbol; _label.hidden = showsSymbol || _image != nil; [self setNeedsDisplay]; }

- (void)showImage:(UIImage *)image {
    if (image == _image) return;
    [_image release];
    _image = [image retain];
    CGImageAlphaInfo alpha = image.CGImage ? CGImageGetAlphaInfo(image.CGImage) : kCGImageAlphaNone;
    _imageHasAlpha = alpha != kCGImageAlphaNone && alpha != kCGImageAlphaNoneSkipFirst && alpha != kCGImageAlphaNoneSkipLast;
    _imageIsRound = image && ExteriaImageIsRound(image);
    _label.hidden = _showsSymbol || _image != nil;
    [self setNeedsDisplay];
}

- (void)setPhoto:(ExteriaPhoto *)photo cache:(ExteriaAvatarCache *)cache {
    NSString *key = photo.key;
    if (key == _photoKey || [key isEqualToString:_photoKey]) return;
    [_photoKey release];
    _photoKey = [key copy];
    [self showImage:nil];
    if (!photo || !cache) return;
    UIImage *cached = [cache cachedImageForPhoto:photo];
    if (cached) {
        [self showImage:cached];
        return;
    }
    /* the view can be released while the download runs, when a screen is rebuilt or a cell is dropped */
    [self retain];
    [cache loadImageForPhoto:photo completion:^(UIImage *image) {
        [self autorelease];
        if (!image || ![key isEqualToString:_photoKey]) return;
        /* a photo that came after the row was shown fades over the initials; one the cache already held was there with the row and appears with it */
        if (self.window && !ExteriaReduceMotionEnabled()) {
            CATransition *fade = [CATransition animation];
            fade.type = kCATransitionFade;
            fade.duration = 0.2;
            [self.layer addAnimation:fade forKey:@"photo"];
        }
        [self showImage:image];
    }];
}
- (void)setSymbol:(ExteriaSymbol)symbol { if (symbol == _symbol) return; _symbol = symbol; [self setNeedsDisplay]; }
- (void)setAccent:(BOOL)accent { if (accent == _accent) return; _accent = accent; [self setNeedsDisplay]; }
- (void)setSeed:(NSUInteger)seed { if (seed == _seed) return; _seed = seed; [self setNeedsDisplay]; }
- (void)setDeleted:(BOOL)deleted { if (deleted == _deleted) return; _deleted = deleted; [self setNeedsDisplay]; }
- (void)setCircular:(BOOL)circular { if (circular == _circular) return; _circular = circular; [self setNeedsDisplay]; }
- (void)setTransparentPhoto:(BOOL)transparentPhoto { if (transparentPhoto == _transparentPhoto) return; _transparentPhoto = transparentPhoto; [self setNeedsDisplay]; }

/* the accent color of the app as the two ends of the gradient: a lighter top over the color itself */
static void ExteriaAccentGradient(CGFloat out[8]) {
    CGColorRef color = ExteriaColorAccent().CGColor;
    const CGFloat *c = CGColorGetComponents(color);
    size_t count = CGColorGetNumberOfComponents(color);
    CGFloat r = c[0], g = count >= 3 ? c[1] : c[0], b = count >= 3 ? c[2] : c[0];
    out[0] = r + (1 - r) * 0.28f; out[1] = g + (1 - g) * 0.28f; out[2] = b + (1 - b) * 0.28f; out[3] = 1;
    out[4] = r; out[5] = g; out[6] = b; out[7] = 1;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    static const CGFloat palette[AVATAR_COLORS][8] = {
        {1.00, 0.52, 0.39, 1, 1.00, 0.32, 0.42, 1},
        {1.00, 0.74, 0.37, 1, 1.00, 0.62, 0.04, 1},
        {0.63, 0.52, 1.00, 1, 0.49, 0.36, 0.89, 1},
        {0.50, 0.84, 0.50, 1, 0.29, 0.71, 0.41, 1},
        {0.42, 0.80, 0.86, 1, 0.24, 0.66, 0.78, 1},
        {0.43, 0.69, 1.00, 1, 0.26, 0.52, 0.96, 1},
        {1.00, 0.49, 0.78, 1, 0.86, 0.33, 0.67, 1},
    };
    /* the gradient of the special avatars is the accent of the app, lighter at the top */
    CGFloat accent[8];
    ExteriaAccentGradient(accent);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat side = MIN(bounds.size.width, bounds.size.height);
    /* a photo that is a round shape on white or on nothing is cut to its circle in every shape of avatar, or the white of the corners shows */
    /* the shape the person chose in the customization; the classic style keeps its rounded squares, and a round picture keeps its circle */
    ExteriaShape shape = ExteriaThemeIsClassic() ? ExteriaShapeRounded : (ExteriaShape)ExteriaAvatarShapeStored();
    /* a view that asks to be circular is a circle only in the classic style, which keeps its look; in the others it takes the shape the person chose, so the picture in the profile, in the
       bar, in the chat and in the profile of another person all change with the list */
    BOOL forcedRound = (_circular && ExteriaThemeIsClassic()) || (_image && _imageIsRound);
    BOOL outline = !forcedRound && ExteriaShapeIsOutline(shape);
    CGFloat radius = side * (forcedRound || shape == ExteriaShapeCircle ? 0.5 : (CGFloat)ExteriaAvatarCornerPercent() / 200.0);
    BOOL classicSymbol = ExteriaThemeIsClassic() && _showsSymbol && !_image &&
                         (_symbol == ExteriaSymbolArchive || _symbol == ExteriaSymbolBookmark || _symbol == ExteriaSymbolReply);
    CGContextSaveGState(context);
    if (outline) {
        CGContextAddPath(context, ExteriaShapePath(shape, bounds, 0).CGPath);
    } else if (radius >= side * 0.5 && bounds.size.width == bounds.size.height) {
        CGContextAddEllipseInRect(context, bounds);
    } else {
        CGContextMoveToPoint(context, CGRectGetMinX(bounds) + radius, CGRectGetMinY(bounds));
        CGContextAddArcToPoint(context, CGRectGetMaxX(bounds), CGRectGetMinY(bounds), CGRectGetMaxX(bounds), CGRectGetMaxY(bounds), radius);
        CGContextAddArcToPoint(context, CGRectGetMaxX(bounds), CGRectGetMaxY(bounds), CGRectGetMinX(bounds), CGRectGetMaxY(bounds), radius);
        CGContextAddArcToPoint(context, CGRectGetMinX(bounds), CGRectGetMaxY(bounds), CGRectGetMinX(bounds), CGRectGetMinY(bounds), radius);
        CGContextAddArcToPoint(context, CGRectGetMinX(bounds), CGRectGetMinY(bounds), CGRectGetMaxX(bounds), CGRectGetMinY(bounds), radius);
        CGContextClosePath(context);
    }
    CGContextClip(context);
    if (_image) {
        if (_imageHasAlpha && !_transparentPhoto) {
            ExteriaFillGradient(context, CGPointMake(0, 0), CGPointMake(0, bounds.size.height), _accent ? accent : palette[_seed % AVATAR_COLORS], 2);
        }
        /* the photo fills the square, cropped to its middle */
        CGSize size = _image.size;
        CGFloat scale = MAX(bounds.size.width / size.width, bounds.size.height / size.height);
        CGSize drawn = CGSizeMake(size.width * scale, size.height * scale);
        [_image drawInRect:CGRectMake((bounds.size.width - drawn.width) / 2, (bounds.size.height - drawn.height) / 2, drawn.width, drawn.height)];
    } else {
        ExteriaFillGradient(context, CGPointMake(0, 0), CGPointMake(0, bounds.size.height),
                            _accent ? accent : palette[_seed % AVATAR_COLORS], 2);
    }
    /* the classic style lights every picture like a glass button: a gloss over the top half and a lit rim. a list has dozens of pictures, and the gloss, the two outlines and their
       clips were worked out again for each at every redraw, so they are drawn once for a size and a corner and the picture is laid over */
    if (ExteriaThemeIsClassic() && ExteriaClassicAvatarGloss()) [ExteriaAvatarGlossOverlay(bounds.size, radius) drawInRect:bounds];
    CGContextRestoreGState(context);

    if (_showsSymbol && !_image) {
        CGFloat glyph = side * 0.46;
        UIImage *image = ExteriaSymbolImage(_symbol, glyph, [UIColor whiteColor]);
        CGContextSaveGState(context);
        if (classicSymbol) CGContextSetShadowWithColor(context, CGSizeMake(0, 1), 1, [UIColor colorWithWhite:0 alpha:0.3].CGColor);
        [image drawInRect:CGRectMake((bounds.size.width - image.size.width) / 2, (bounds.size.height - image.size.height) / 2,
                                     image.size.width, image.size.height)];
        CGContextRestoreGState(context);
    } else if (_deleted && !_image) {
        /* the mask is the ghost.webp canv, 32 units drawn on a 54 unit avatar */
        UIImage *ghost = ExteriaSymbolImage(ExteriaSymbolGhost, side * 0.6, [UIColor whiteColor]);
        [ghost drawInRect:CGRectMake((bounds.size.width - ghost.size.width) / 2, (bounds.size.height - ghost.size.height) / 2,
                                     ghost.size.width, ghost.size.height)];
    }
}

@end

@implementation ExteriaOnlineDotView
@synthesize inverted = _inverted;
- (void)setInverted:(BOOL)inverted {
    if (inverted == _inverted) return;
    _inverted = inverted;
    [self setNeedsDisplay];
}
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.userInteractionEnabled = NO; }
    return self;
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    [(_inverted ? [UIColor whiteColor] : [UIColor colorWithRed:0.30f green:0.78f blue:0.37f alpha:1]) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:self.bounds] fill];
}
@end
