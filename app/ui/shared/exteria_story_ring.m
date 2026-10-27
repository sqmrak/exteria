#import "exteria_story_ring.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_theme.h"

#define RING_WIDTH 2.5
#define SEEN_WIDTH 1.5
#define RING_OUTSET 6.0

static UIColor *ExteriaRingRGB(int r, int g, int b) {
    return [UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1];
}

void ExteriaStoryRingColors(BOOL unseen, BOOL closeFriends, UIColor **from, UIColor **to) {
    if (!unseen) {
        *from = *to = ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.28] : [UIColor colorWithWhite:0 alpha:0.2];
    } else if (closeFriends) {
        *from = ExteriaRingRGB(0x81, 0xce, 0x2d);
        *to = ExteriaRingRGB(0x18, 0xbd, 0x36);
    } else {
        *from = ExteriaRingRGB(0x2c, 0x9e, 0xfc);
        *to = ExteriaRingRGB(0x2f, 0xc1, 0x83);
    }
}

/* the gap the arcs leave on each side of a joint, in degrees, as the Telegram avatar does; a long row of stories gets a smaller one */
#define MAX_SEGMENTS 100

@interface ExteriaStoryRing () {
    CAGradientLayer *_gradient;
    CAShapeLayer *_unseenStroke;
    CAShapeLayer *_seenStroke;
    NSInteger _count;
    NSInteger _unseen;
}
@end

@implementation ExteriaStoryRing

+ (CGFloat)outset {
    return RING_OUTSET;
}

static CAShapeLayer *ExteriaRingStroke(UIColor *color, CGFloat width) {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.fillColor = nil;
    layer.strokeColor = color.CGColor;
    layer.lineWidth = width;
    layer.lineCap = kCALineCapRound;
    return layer;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    _gradient = [[CAGradientLayer layer] retain];
    _gradient.startPoint = CGPointMake(1, 0);
    _gradient.endPoint = CGPointMake(0, 1);
    _unseenStroke = [ExteriaRingStroke([UIColor blackColor], RING_WIDTH) retain];
    _gradient.mask = _unseenStroke;
    _seenStroke = [ExteriaRingStroke([UIColor clearColor], SEEN_WIDTH) retain];
    [self.layer addSublayer:_seenStroke];
    [self.layer addSublayer:_gradient];
    return self;
}

- (void)dealloc {
    [_gradient release];
    [_unseenStroke release];
    [_seenStroke release];
    [super dealloc];
}

- (void)setCount:(NSInteger)count unseen:(NSInteger)unseen closeFriends:(BOOL)closeFriends {
    _count = MIN(MAX(count, 1), MAX_SEGMENTS);
    _unseen = MIN(MAX(unseen, 0), _count);
    UIColor *from, *to, *seen;
    ExteriaStoryRingColors(YES, closeFriends, &from, &to);
    ExteriaStoryRingColors(NO, closeFriends, &seen, &seen);
    _gradient.colors = [NSArray arrayWithObjects:(id)from.CGColor, (id)to.CGColor, nil];
    _seenStroke.strokeColor = seen.CGColor;
    [self setNeedsLayout];
}

- (void)setPeer:(ExteriaStoryPeer *)peer {
    [self setCount:peer.count unseen:peer.unread closeFriends:peer.closeFriends];
}

/* arcs of the segments from first up to last, clockwise from twelve o'clock; one story is the whole circle, since a gap
   would have no arc to separate */
static CGPathRef ExteriaRingPath(CGRect box, NSInteger count, NSInteger first, NSInteger last) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    if (first >= last) return path.CGPath;
    CGPoint center = CGPointMake(CGRectGetMidX(box), CGRectGetMidY(box));
    CGFloat radius = box.size.width / 2;
    if (count == 1) {
        [path addArcWithCenter:center radius:radius startAngle:-(CGFloat)M_PI_2 endAngle:(CGFloat)(M_PI * 1.5) clockwise:YES];
        return path.CGPath;
    }
    CGFloat step = (CGFloat)(2 * M_PI) / count;
    CGFloat gap = (CGFloat)((count > 20 ? 3 : 5) * M_PI / 180);
    if (gap * 2 >= step) gap = 0;
    for (NSInteger i = first; i < last; ++i) {
        CGFloat start = -(CGFloat)M_PI_2 + step * i + gap;
        [path moveToPoint:CGPointMake(center.x + radius * cosf(start), center.y + radius * sinf(start))];
        [path addArcWithCenter:center radius:radius startAngle:start endAngle:start + step - gap * 2 clockwise:YES];
    }
    return path.CGPath;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_count) return;
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat inset = RING_WIDTH / 2;
    CGRect box = CGRectMake(inset, inset, side - RING_WIDTH, side - RING_WIDTH);
    CGRect frame = CGRectMake(0, 0, side, side);
    _gradient.frame = frame;
    _unseenStroke.frame = frame;
    _seenStroke.frame = frame;
    /* the seen arcs are the oldest stories, so they come first and the unseen ones follow */
    _seenStroke.path = ExteriaRingPath(box, _count, 0, _count - _unseen);
    _unseenStroke.path = ExteriaRingPath(box, _count, _count - _unseen, _count);
}

@end
