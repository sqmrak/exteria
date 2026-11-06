#import "exteria_classic_bubble.h"

#import "exteria_theme.h"

/* the corners and the tail of the cut pictures, in points: the side with the tail holds the tail and a corner, the others a corner */
#define CAP_CORNER 12.0
#define CAP_PLAIN 13.0
/* lightness of the grey template at which the body color sits; the edge goes dark below it, and everything above it is the body */
#define BODY_LIGHTNESS_OUT 0.72
#define BODY_LIGHTNESS_IN 0.84
/* the cache holds a few colors; a change of accent or look makes a new one and the old ones go when it is full */
#define CACHE_MAX 12

static void ExteriaBubbleRGB(UIColor *color, CGFloat rgb[3]) {
    CGFloat alpha;
    if (![color getRed:&rgb[0] green:&rgb[1] blue:&rgb[2] alpha:&alpha]) {
        CGFloat white;
        [color getWhite:&white alpha:&alpha];
        rgb[0] = rgb[1] = rgb[2] = white;
    }
}

static void ExteriaBubbleMix(const CGFloat from[3], const CGFloat to[3], CGFloat share, CGFloat out[3]) {
    for (int i = 0; i < 3; ++i) out[i] = from[i] + (to[i] - from[i]) * share;
}

/* the grey of a pixel picks a point on a ramp from the outline to the body color. the template's gloss is not used: its hard edge sits in the stretched rows, so a tall message
   showed two bands of different lightness with a line between them; the light is drawn over the picture at the real size instead */
static UIImage *ExteriaMakeBubble(BOOL outgoing, BOOL tail) {
    NSString *name = [NSString stringWithFormat:@"classic_bubble_%@%@.png", outgoing ? @"out" : @"in", tail ? @"" : @"_plain"];
    UIImage *template = [UIImage imageNamed:name];
    CGImageRef source = template.CGImage;
    if (!source) {
        NSLog(@"exteria: the bubble picture %@ is missing from the bundle", name);
        return nil;
    }
    UIColor *top, *bottom, *outline;
    ExteriaClassicBubbleColors(outgoing, &top, &bottom, &outline);
    /* the picture is filled with the lower color, as the lit rows and the gloss are drawn over it by ExteriaClassicBubbleGloss: the tail, which they do not reach, then
       matches the bottom of the body */
    (void)top;
    CGFloat edge[3], body[3];
    ExteriaBubbleRGB(outline, edge);
    ExteriaBubbleRGB(bottom, body);
    CGFloat bodyAt = outgoing ? BODY_LIGHTNESS_OUT : BODY_LIGHTNESS_IN;

    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        NSLog(@"exteria: no bitmap for the bubble picture %@", name);
        return nil;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), source);
    uint8_t *pixels = CGBitmapContextGetData(context);
    for (size_t i = 0; i < width * height; ++i) {
        uint8_t *px = pixels + i * 4;
        if (!px[3]) continue;
        /* the template has no hue, so the red channel is its grey once the alpha is divided out of it */
        CGFloat grey = MIN(1.0, (CGFloat)px[0] / (CGFloat)px[3]);
        CGFloat color[3];
        if (grey < bodyAt) ExteriaBubbleMix(edge, body, grey / bodyAt, color);
        else memcpy(color, body, sizeof color);
        for (int c = 0; c < 3; ++c) px[c] = (uint8_t)(color[c] * (CGFloat)px[3] + 0.5);
    }
    CGImageRef tinted = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!tinted) return nil;
    UIImage *image = [UIImage imageWithCGImage:tinted scale:template.scale orientation:UIImageOrientationUp];
    CGImageRelease(tinted);
    UIEdgeInsets caps;
    if (!tail) caps = UIEdgeInsetsMake(CAP_CORNER, CAP_PLAIN, CAP_CORNER, CAP_PLAIN);
    else if (outgoing) caps = UIEdgeInsetsMake(CAP_CORNER, CAP_CORNER, CAP_CORNER, CAP_CORNER + EXTERIA_CLASSIC_BUBBLE_TAIL);
    else caps = UIEdgeInsetsMake(CAP_CORNER, CAP_CORNER + EXTERIA_CLASSIC_BUBBLE_TAIL, CAP_CORNER, CAP_CORNER);
    return [image resizableImageWithCapInsets:caps];
}

UIImage *ExteriaClassicBubbleImage(BOOL outgoing, BOOL tail) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    UIColor *top, *bottom, *outline;
    ExteriaClassicBubbleColors(outgoing, &top, &bottom, &outline);
    CGFloat key[3];
    ExteriaBubbleRGB(bottom, key);
    NSString *id = [NSString stringWithFormat:@"%d%d%d:%.3f:%.3f:%.3f", outgoing, tail, ExteriaThemeIsDark(), key[0], key[1], key[2]];
    UIImage *image = [cache objectForKey:id];
    if (image) return image;
    image = ExteriaMakeBubble(outgoing, tail);
    if (!image) return nil;
    if (cache.count >= CACHE_MAX) [cache removeAllObjects];
    [cache setObject:image forKey:id];
    return image;
}

/* the radius of the body inside the rim, and how far the gloss stays from the rim */
#define GLOSS_RADIUS 11.0
#define GLOSS_MARGIN 3.0
#define GLOSS_MAX_HEIGHT 22.0

void ExteriaClassicBubbleGloss(CGContextRef context, CGRect bounds, BOOL outgoing, BOOL tail) {
    CGRect body = bounds;
    if (tail) {
        body.size.width -= EXTERIA_CLASSIC_BUBBLE_TAIL;
        if (!outgoing) body.origin.x += EXTERIA_CLASSIC_BUBBLE_TAIL;
    }
    CGRect inner = CGRectInset(body, 1, 1);
    if (inner.size.width < 2 * GLOSS_RADIUS || inner.size.height < 2 * GLOSS_RADIUS) return;
    UIColor *top, *bottom, *outline;
    ExteriaClassicBubbleColors(outgoing, &top, &bottom, &outline);
    BOOL dark = ExteriaThemeIsDark();
    CGFloat t[3], b[3], o[3], mid[3], step[3];
    ExteriaBubbleRGB(top, t);
    ExteriaBubbleRGB(bottom, b);
    ExteriaBubbleRGB(outline, o);
    ExteriaBubbleMix(t, b, 0.35, mid);
    ExteriaBubbleMix(mid, o, 0.10, step);
    /* the upper half fades from the lit edge to the body, the lower half starts a shade darker at the middle, with the hard edge of the glass of the old chrome, and warms
       back to the bottom color */
    CGFloat colors[] = {t[0], t[1], t[2], 1,  mid[0], mid[1], mid[2], 1,  step[0], step[1], step[2], 1,  b[0], b[1], b[2], 1};
    CGFloat at[] = {0, 0.49, 0.5, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef ramp = CGGradientCreateWithColorComponents(space, colors, at, 4);
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:GLOSS_RADIUS] addClip];
    CGContextDrawLinearGradient(context, ramp, CGPointMake(0, inner.origin.y), CGPointMake(0, CGRectGetMaxY(inner)), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(ramp);
    /* a capsule of light on the upper part, with the oval of the glossy balloons of the old messaging apps */
    CGFloat height = MIN(GLOSS_MAX_HEIGHT, floor(inner.size.height * 0.46));
    CGRect capsule = CGRectMake(inner.origin.x + GLOSS_MARGIN, inner.origin.y + 2, inner.size.width - 2 * GLOSS_MARGIN, height);
    CGFloat shine[] = {1, 1, 1, dark ? 0.30 : (outgoing ? 0.58 : 0.85),  1, 1, 1, dark ? 0.05 : 0.14};
    CGGradientRef light = CGGradientCreateWithColorComponents(space, shine, NULL, 2);
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:capsule cornerRadius:MIN(height / 2, GLOSS_RADIUS - 2)] addClip];
    CGContextDrawLinearGradient(context, light, CGPointMake(0, capsule.origin.y), CGPointMake(0, CGRectGetMaxY(capsule)), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(light);
    CGColorSpaceRelease(space);
}
