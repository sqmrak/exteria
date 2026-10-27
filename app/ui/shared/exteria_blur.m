#import "exteria_blur.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#import "exteria_theme.h"

/* a box blur of radius r run passes times over the rows and the columns, the edge pixel standing in for what is beyond it; the image is returned as it was when
   the memory for the work is not there */
static void ExteriaBoxPass(const uint8_t *from, uint8_t *to, size_t lines, size_t length, size_t lineStride, size_t itemStride, int r) {
    for (size_t line = 0; line < lines; ++line) {
        for (size_t channel = 0; channel < 3; ++channel) {
            const uint8_t *in = from + line * lineStride + channel;
            uint8_t *out = to + line * lineStride + channel;
            long sum = (long)in[0] * (r + 1);
            for (int k = 1; k <= r; ++k) sum += in[MIN((size_t)k, length - 1) * itemStride];
            for (size_t i = 0; i < length; ++i) {
                out[i * itemStride] = (uint8_t)(sum / (2 * r + 1));
                sum += in[MIN(i + (size_t)r + 1, length - 1) * itemStride];
                sum -= in[(i > (size_t)r ? i - (size_t)r : 0) * itemStride];
            }
        }
    }
}

static UIImage *ExteriaBoxBlurred(UIImage *image, int r, int passes) {
    CGImageRef source = image.CGImage;
    size_t w = CGImageGetWidth(source), h = CGImageGetHeight(source);
    if (!source || w < 2 || h < 2) return image;
    uint8_t *a = calloc(w * h, 4), *b = calloc(w * h, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = a && b ? CGBitmapContextCreate(a, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast) : NULL;
    UIImage *result = image;
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, w, h), source);
        for (int i = 0; i < passes; ++i) {
            ExteriaBoxPass(a, b, h, w, w * 4, 4, r);
            ExteriaBoxPass(b, a, w, h, 4, w * 4, r);
        }
        CGImageRef blurred = CGBitmapContextCreateImage(context);
        if (blurred) {
            result = [UIImage imageWithCGImage:blurred];
            CGImageRelease(blurred);
        }
    }
    if (context) CGContextRelease(context);
    CGColorSpaceRelease(space);
    free(a);
    free(b);
    return result;
}

UIView *ExteriaBlurBackdrop(UIView *host, CGRect bounds) {
    Class effect = NSClassFromString(@"UIBlurEffect"), view = NSClassFromString(@"UIVisualEffectView");
    if (effect && view) {
        NSInteger style = ExteriaThemeIsDark() ? 2 : 1;
        id blur = ((id (*)(id, SEL, NSInteger))objc_msgSend)(effect, NSSelectorFromString(@"effectWithStyle:"), style);
        id made = ((id (*)(id, SEL, id))objc_msgSend)([view alloc], NSSelectorFromString(@"initWithEffect:"), blur);
        if (made) {
            UIView *blurView = [(UIView *)made autorelease];
            blurView.frame = bounds;
            return blurView;
        }
    }
    /* the picture is taken at an eighth of its size and blurred by a box filter twice over, which leaves no grid of blocks when it is stretched back */
    CGFloat divisor = 8;
    CGSize small = CGSizeMake(MAX(2, floor(bounds.size.width / divisor)), MAX(2, floor(bounds.size.height / divisor)));
    UIGraphicsBeginImageContextWithOptions(small, YES, 1);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextScaleCTM(context, small.width / bounds.size.width, small.height / bounds.size.height);
    [host.layer renderInContext:context];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!image) return nil;
    image = ExteriaBoxBlurred(image, 2, 2);
    UIImageView *picture = [[[UIImageView alloc] initWithImage:image] autorelease];
    picture.frame = bounds;
    return picture;
}
