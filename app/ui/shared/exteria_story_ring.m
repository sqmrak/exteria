#import "exteria_story_ring.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_settings.h"
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
    } else if (ExteriaThemeIsClassic()) {
        /* the system blue and green of ios 5 and 6 badges, from a lit top edge to a deep one */
        *from = closeFriends ? ExteriaRingRGB(0x8c, 0xd8, 0x4a) : ExteriaRingRGB(0x6f, 0xa8, 0xf0);
        *to = closeFriends ? ExteriaRingRGB(0x2e, 0x8a, 0x1c) : ExteriaRingRGB(0x1c, 0x4f, 0xb8);
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

@synthesize followsAvatarShape = _followsAvatarShape;

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

- (void)setFollowsAvatarShape:(BOOL)follows {
    _followsAvatarShape = follows;
    [self setNeedsLayout];
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

/* the outline of the ring from twelve o'clock, clockwise: a circle, or a rounded square with the corner radius given. one path serves both layers, and the
   segments are cut from it by dashes, so the ring follows any corner radius and not only the circle */
static CGPathRef ExteriaRingPath(CGRect box, CGFloat radius) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat minX = CGRectGetMinX(box), maxX = CGRectGetMaxX(box), minY = CGRectGetMinY(box), maxY = CGRectGetMaxY(box);
    radius = MIN(radius, MIN(box.size.width, box.size.height) / 2);
    [path moveToPoint:CGPointMake(CGRectGetMidX(box), minY)];
    [path addLineToPoint:CGPointMake(maxX - radius, minY)];
    [path addArcWithCenter:CGPointMake(maxX - radius, minY + radius) radius:radius startAngle:-(CGFloat)M_PI_2 endAngle:0 clockwise:YES];
    [path addLineToPoint:CGPointMake(maxX, maxY - radius)];
    [path addArcWithCenter:CGPointMake(maxX - radius, maxY - radius) radius:radius startAngle:0 endAngle:(CGFloat)M_PI_2 clockwise:YES];
    [path addLineToPoint:CGPointMake(minX + radius, maxY)];
    [path addArcWithCenter:CGPointMake(minX + radius, maxY - radius) radius:radius startAngle:(CGFloat)M_PI_2 endAngle:(CGFloat)M_PI clockwise:YES];
    [path addLineToPoint:CGPointMake(minX, minY + radius)];
    [path addArcWithCenter:CGPointMake(minX + radius, minY + radius) radius:radius startAngle:(CGFloat)M_PI endAngle:(CGFloat)(M_PI * 1.5) clockwise:YES];
    [path closePath];
    return path.CGPath;
}

/* the length of ExteriaRingPath */
static CGFloat ExteriaRingLength(CGRect box, CGFloat radius) {
    radius = MIN(radius, MIN(box.size.width, box.size.height) / 2);
    return 2 * (box.size.width + box.size.height - 4 * radius) + (CGFloat)(2 * M_PI) * radius;
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
    /* the avatar of a list row is cut to the percent the person chose, in avatar sizes; 100 is a circle */
    CGFloat radius = _followsAvatarShape ? box.size.width * MIN(100, ExteriaAvatarCornerPercent()) / 200.0f : box.size.width / 2;
    CGPathRef path = ExteriaRingPath(box, radius);
    _seenStroke.path = path;
    _unseenStroke.path = path;
    /* the gap the arcs leave on each side of a joint, in degrees as the Telegram avatar does, turned into a length along the outline at the radius of a circle of this size */
    CGFloat length = ExteriaRingLength(box, radius);
    CGFloat step = length / (CGFloat)_count;
    CGFloat gap = (CGFloat)((_count > 20 ? 6 : 10) * M_PI / 180) * box.size.width / 2;
    if (_count == 1 || gap >= step) gap = 0;
    NSArray *dashes = gap > 0 ? [NSArray arrayWithObjects:[NSNumber numberWithDouble:step - gap], [NSNumber numberWithDouble:gap], nil] : nil;
    _seenStroke.lineDashPattern = dashes;
    _unseenStroke.lineDashPattern = dashes;
    /* a joint sits in the middle of a gap, so the dashes start half a gap in */
    _seenStroke.lineDashPhase = gap > 0 ? step - gap + gap / 2 : 0;
    _unseenStroke.lineDashPhase = _seenStroke.lineDashPhase;
    /* the seen arcs are the oldest stories, so they come first and the unseen ones follow */
    CGFloat boundary = (CGFloat)(_count - _unseen) / (CGFloat)_count;
    _seenStroke.strokeStart = 0;
    _seenStroke.strokeEnd = boundary;
    _unseenStroke.strokeStart = _unseen ? boundary : 1;
    _unseenStroke.strokeEnd = 1;
}

@end
