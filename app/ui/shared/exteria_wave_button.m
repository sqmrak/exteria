#import "exteria_wave_button.h"
#import "exteria_animation.h"

#import "exteria_theme.h"
#import "exteria_wave.h"

@interface ExteriaWaveButton () {
    UILabel *_label;
    NSString *_title;
    CGFloat _cornerRadius;
    CGFloat _titleSize;
}
@end

@implementation ExteriaWaveButton

@synthesize cornerRadius = _cornerRadius;
@synthesize titleSize = _titleSize;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    ExteriaAttachBounce(self, 0.06);
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = ExteriaTextAlignmentCenter;
    _label.userInteractionEnabled = NO;
    _label.font = ExteriaFontBold(19);
    [self addSubview:_label];
    return self;
}

- (void)dealloc {
    [_label release];
    [_title release];
    [super dealloc];
}

- (NSString *)title {
    return _title;
}

- (void)setTitle:(NSString *)title {
    if (title == _title || [title isEqualToString:_title]) return;
    [_title release];
    _title = [title copy];
    _label.text = _title;
    self.accessibilityLabel = _title;
}

- (void)setTitleSize:(CGFloat)titleSize {
    _titleSize = titleSize;
    _label.font = ExteriaFontBold(titleSize);
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self setNeedsDisplay];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = self.bounds;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat radius = MIN(_cornerRadius, h / 2);
    CGRect box = self.bounds;
    CGFloat minX = CGRectGetMinX(box), maxX = CGRectGetMaxX(box);
    CGFloat minY = CGRectGetMinY(box), maxY = CGRectGetMaxY(box);

    CGContextSaveGState(context);
    CGContextMoveToPoint(context, minX + radius, minY);
    CGContextAddArcToPoint(context, maxX, minY, maxX, maxY, radius);
    CGContextAddArcToPoint(context, maxX, maxY, minX, maxY, radius);
    CGContextAddArcToPoint(context, minX, maxY, minX, minY, radius);
    CGContextAddArcToPoint(context, minX, minY, maxX, minY, radius);
    CGContextClosePath(context);
    CGContextClip(context);

    CGFloat top[4], bottom[4];
    [ExteriaColorAccent() getRed:&top[0] green:&top[1] blue:&top[2] alpha:&top[3]];
    [ExteriaColorAccentDark() getRed:&bottom[0] green:&bottom[1] blue:&bottom[2] alpha:&bottom[3]];
    CGFloat colors[8] = {top[0], top[1], top[2], 1, bottom[0], bottom[1], bottom[2], 1};
    ExteriaFillGradient(context, CGPointMake(0, 0), CGPointMake(0, h), colors, 2);

    CGMutablePathRef left = CGPathCreateMutable();
    CGPathMoveToPoint(left, NULL, 0, h);
    CGPathAddLineToPoint(left, NULL, 0, 0.45 * h);
    ExteriaAddWaveEdge(left, CGPointMake(0, 0.45 * h), CGPointMake(0.12 * w, 0.85 * h),
                       CGPointMake(0.5 * w, h), 0.05 * h, 2.5);
    CGPathCloseSubpath(left);
    CGContextSetRGBFillColor(context, 1, 1, 1, 0.1);
    CGContextAddPath(context, left);
    CGContextFillPath(context);
    CGPathRelease(left);

    CGMutablePathRef right = CGPathCreateMutable();
    CGPathMoveToPoint(right, NULL, w, 0);
    CGPathAddLineToPoint(right, NULL, 0.62 * w, 0);
    ExteriaAddWaveEdge(right, CGPointMake(0.62 * w, 0), CGPointMake(0.92 * w, 0.1 * h),
                       CGPointMake(w, 0.62 * h), 0.04 * h, 2);
    CGPathCloseSubpath(right);
    CGContextSetRGBFillColor(context, 1, 1, 1, 0.08);
    CGContextAddPath(context, right);
    CGContextFillPath(context);
    CGPathRelease(right);

    if (self.highlighted) {
        CGContextSetRGBFillColor(context, 0, 0, 0, 0.14);
        CGContextFillRect(context, box);
    }
    CGContextRestoreGState(context);
}

@end
