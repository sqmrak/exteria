#import "exteria_bubble_shape.h"

#include <math.h>

/* the margins of the picture: a point for the stroke of Telegram and a point more round it */
#define STROKE_INSET 1.0
#define ADDITIONAL_INSET 1.0
#define FIXED_MAIN_DIAMETER 33.0
#define CACHE_LIMIT 64

static const CGFloat minRadiusForFullTailCorner = 14.0f;

ExteriaTelegramNeighbors ExteriaTelegramNeighborsFor(BOOL joinsPrevious, BOOL joinsNext) {
    if (joinsPrevious && joinsNext) return ExteriaTelegramNeighborsBoth;
    if (joinsPrevious) return ExteriaTelegramNeighborsBottom;
    if (joinsNext) return ExteriaTelegramNeighborsTop;
    return ExteriaTelegramNeighborsNone;
}

BOOL ExteriaTelegramNeighborsHaveTail(ExteriaTelegramNeighbors neighbors) {
    return neighbors == ExteriaTelegramNeighborsNone || neighbors == ExteriaTelegramNeighborsBottom;
}

typedef void (^ExteriaBubbleDrawBlock)(CGContextRef context);

/* the DrawingContext of Display: an ARGB bitmap in the y-up coordinates of Core Graphics, scaled to the screen */
static UIImage *ExteriaBubbleGenerateImage(CGSize size, ExteriaBubbleDrawBlock draw) {
    CGFloat scale = [UIScreen mainScreen].scale;
    size_t w = (size_t)ceil(size.width * scale), h = (size_t)ceil(size.height * scale);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextClearRect(context, CGRectMake(0, 0, w, h));
    CGContextScaleCTM(context, scale, scale);
    draw(context);
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    UIImage *image = [UIImage imageWithCGImage:cgImage scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return image;
}

static UIImage *ExteriaTelegramBubbleRender(CGFloat maxCornerRadius, CGFloat minCornerRadius, BOOL incoming, UIColor *fillColor,
                                            ExteriaTelegramNeighbors neighbors) {
    CGFloat topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius;
    BOOL drawTail;
    switch (neighbors) {
        case ExteriaTelegramNeighborsNone:
            topLeftRadius = maxCornerRadius;
            topRightRadius = maxCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = maxCornerRadius;
            drawTail = YES;
            break;
        case ExteriaTelegramNeighborsBoth:
            topLeftRadius = maxCornerRadius;
            topRightRadius = minCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = minCornerRadius;
            drawTail = NO;
            break;
        case ExteriaTelegramNeighborsBottom:
            topLeftRadius = maxCornerRadius;
            topRightRadius = minCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = maxCornerRadius;
            drawTail = YES;
            break;
        case ExteriaTelegramNeighborsTop:
        default:
            topLeftRadius = maxCornerRadius;
            topRightRadius = maxCornerRadius;
            bottomLeftRadius = maxCornerRadius;
            bottomRightRadius = minCornerRadius;
            drawTail = NO;
            break;
    }

    const CGFloat fixedMainDiameter = FIXED_MAIN_DIAMETER;
    CGSize innerSize = CGSizeMake(fixedMainDiameter + EXTERIA_TELEGRAM_TAIL_ROOM, fixedMainDiameter);
    const CGFloat strokeInset = STROKE_INSET;
    CGSize sourceRawSize = CGSizeMake(innerSize.width + strokeInset * 2.0f, innerSize.height + strokeInset * 2.0f);
    const CGFloat additionalInset = ADDITIONAL_INSET;
    CGSize imageSize = CGSizeMake(sourceRawSize.width + additionalInset * 2.0f, sourceRawSize.height + additionalInset * 2.0f);
    int outgoingStretchX = (int)(additionalInset + strokeInset + roundf(fixedMainDiameter / 2.0f)) - 1;
    int outgoingStretchY = (int)(additionalInset + strokeInset + roundf(fixedMainDiameter / 2.0f));
    int incomingStretchX = (int)sourceRawSize.width - outgoingStretchX + (int)additionalInset;
    int incomingStretchY = outgoingStretchY;

    CGSize rawSize = imageSize;
    CGRect bottomEllipse = CGRectMake(24.0f, 16.0f, 27.0f, 17.0f);
    CGRect topEllipse = CGRectMake(33.0f, 14.0f, 23.0f, 21.0f);

    UIImage *formImage = ExteriaBubbleGenerateImage(imageSize, ^(CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, rawSize.width, rawSize.height));
        CGContextTranslateCTM(context, additionalInset + strokeInset, additionalInset + strokeInset);

        CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);

        CGContextMoveToPoint(context, 0.0f, topLeftRadius);
        CGContextAddArcToPoint(context, 0.0f, 0.0f, topLeftRadius, 0.0f, topLeftRadius);
        CGContextAddLineToPoint(context, fixedMainDiameter - topRightRadius, 0.0f);
        CGContextAddArcToPoint(context, fixedMainDiameter, 0.0f, fixedMainDiameter, topRightRadius, topRightRadius);
        CGContextAddLineToPoint(context, fixedMainDiameter, fixedMainDiameter - bottomRightRadius);
        CGContextAddArcToPoint(context, fixedMainDiameter, fixedMainDiameter, fixedMainDiameter - bottomRightRadius, fixedMainDiameter, bottomRightRadius);
        CGContextAddLineToPoint(context, bottomLeftRadius, fixedMainDiameter);
        CGContextAddArcToPoint(context, 0.0f, fixedMainDiameter, 0.0f, fixedMainDiameter - bottomLeftRadius, bottomLeftRadius);
        CGContextAddLineToPoint(context, 0.0f, topLeftRadius);
        CGContextFillPath(context);

        if (drawTail) {
            if (maxCornerRadius >= minRadiusForFullTailCorner) {
                CGContextMoveToPoint(context, CGRectGetMinX(bottomEllipse), CGRectGetMidY(bottomEllipse));
                CGContextAddQuadCurveToPoint(context, CGRectGetMinX(bottomEllipse), CGRectGetMaxY(bottomEllipse), CGRectGetMidX(bottomEllipse), CGRectGetMaxY(bottomEllipse));
                CGContextAddQuadCurveToPoint(context, CGRectGetMaxX(bottomEllipse), CGRectGetMaxY(bottomEllipse), CGRectGetMaxX(bottomEllipse), CGRectGetMidY(bottomEllipse));
                CGContextFillPath(context);
            } else {
                CGContextFillRect(context, CGRectMake(CGRectGetMinX(bottomEllipse) - 2.0f, CGRectGetMidY(bottomEllipse), bottomEllipse.size.width + 2.0f, bottomEllipse.size.height / 2.0f));
            }
            CGContextFillRect(context, CGRectMake(fixedMainDiameter / 2.0f, floorf(fixedMainDiameter / 2.0f), fixedMainDiameter / 2.0f,
                                                  ceilf(CGRectGetMidY(bottomEllipse)) - floorf(fixedMainDiameter / 2.0f)));
            CGContextSetFillColorWithColor(context, [UIColor clearColor].CGColor);
            CGContextSetBlendMode(context, kCGBlendModeCopy);
            CGContextFillEllipseInRect(context, topEllipse);
        }
    });
    if (!formImage) return nil;

    UIImage *image = ExteriaBubbleGenerateImage(imageSize, ^(CGContextRef context) {
        CGContextClearRect(context, CGRectMake(0, 0, rawSize.width, rawSize.height));
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        CGContextSetFillColorWithColor(context, fillColor.CGColor);

        CGContextSaveGState(context);
        CGContextTranslateCTM(context, rawSize.width / 2.0f, rawSize.height / 2.0f);
        CGContextScaleCTM(context, incoming ? -1.0f : 1.0f, -1.0f);
        CGContextTranslateCTM(context, -rawSize.width / 2.0f, -rawSize.height / 2.0f);
        CGContextClipToMask(context, CGRectMake(0, 0, rawSize.width, rawSize.height), formImage.CGImage);
        CGContextFillRect(context, CGRectMake(0, 0, rawSize.width, rawSize.height));
        CGContextRestoreGState(context);
    });

    return [image stretchableImageWithLeftCapWidth:(incoming ? incomingStretchX : outgoingStretchX)
                                      topCapHeight:(incoming ? incomingStretchY : outgoingStretchY)];
}

UIImage *ExteriaTelegramBubbleImage(CGFloat maxCornerRadius, CGFloat minCornerRadius, BOOL incoming, UIColor *fillColor,
                                    ExteriaTelegramNeighbors neighbors) {
    static NSMutableDictionary *cache = nil;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![fillColor getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [fillColor getWhite:&white alpha:&a];
        r = g = b = white;
    }
    NSString *key = [NSString stringWithFormat:@"%.1f/%.1f/%d/%d/%.4f/%.4f/%.4f/%.4f/%.1f", maxCornerRadius, minCornerRadius, incoming ? 1 : 0,
                     (int)neighbors, r, g, b, a, [UIScreen mainScreen].scale];
    UIImage *image = [cache objectForKey:key];
    if (image) return image;
    image = ExteriaTelegramBubbleRender(maxCornerRadius, minCornerRadius, incoming, fillColor, neighbors);
    if (!image) return nil;
    /* a change of the theme or of the corners leaves the old pictures behind, so the cache starts over when it grows */
    if (cache.count >= CACHE_LIMIT) [cache removeAllObjects];
    [cache setObject:image forKey:key];
    return image;
}

CGRect ExteriaTelegramBubbleImageFrame(CGRect body, BOOL incoming) {
    CGFloat margin = STROKE_INSET + ADDITIONAL_INSET;
    CGRect frame = CGRectInset(body, -margin, -margin);
    frame.size.width += EXTERIA_TELEGRAM_TAIL_ROOM;
    if (incoming) frame.origin.x -= EXTERIA_TELEGRAM_TAIL_ROOM;
    return frame;
}
