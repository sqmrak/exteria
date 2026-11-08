#import "exteria_video_crop_view.h"

#include <math.h>

/* the sides a drag holds, as bits, and the whole frame for a drag that moves it */
enum { GrabNone = 0, GrabLeft = 1, GrabRight = 2, GrabTop = 4, GrabBottom = 8, GrabMove = 16 };

/* how far from a corner or a side a finger still takes it, in points, and the smallest share of the picture the frame may shrink to however small the picture is */
#define GRAB_REACH 30.0
#define MIN_SHARE 0.06
/* the encoder takes nothing under a few pixels, so the frame stops a little above the least the core accepts */
#define MIN_PIXELS 24.0

@interface ExteriaVideoCropView () <UIGestureRecognizerDelegate> {
    CGRect _crop;
    CGFloat _ratio;
    CGSize _pictureSize;
    void (^_changed)(CGRect);
    CGRect _start;
    CGPoint _startPoint;
    int _grab;
}
@end

@implementation ExteriaVideoCropView

@synthesize crop = _crop, ratio = _ratio, pictureSize = _pictureSize, changed = _changed;

+ (CGRect)centeredCropOfRatio:(double)ratio inPicture:(CGSize)picture {
    if (ratio <= 0 || picture.width < 1 || picture.height < 1) return CGRectMake(0, 0, 1, 1);
    double shape = picture.width / picture.height, width = 1, height = 1;
    if (shape > ratio) width = ratio / shape;
    else height = shape / ratio;
    return CGRectMake((1 - width) / 2, (1 - height) / 2, width, height);
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    _crop = CGRectMake(0, 0, 1, 1);
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)] autorelease];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [self addGestureRecognizer:pan];
    return self;
}

- (void)dealloc {
    [_changed release];
    [super dealloc];
}

- (void)setCrop:(CGRect)crop {
    CGRect clean = CGRectStandardize(crop);
    CGFloat left = MAX(0, MIN(1, clean.origin.x)), top = MAX(0, MIN(1, clean.origin.y));
    CGFloat right = MAX(left, MIN(1, CGRectGetMaxX(clean))), bottom = MAX(top, MIN(1, CGRectGetMaxY(clean)));
    CGRect next = CGRectMake(left, top, right - left, bottom - top);
    if (CGRectEqualToRect(next, _crop)) return;
    _crop = next;
    [self setNeedsDisplay];
}

- (void)setPictureSize:(CGSize)size {
    _pictureSize = size;
}

- (void)setRatio:(CGFloat)ratio {
    _ratio = ratio > 0 ? ratio : 0;
}

/* the frame in the points of the view */
- (CGRect)frameInView {
    CGSize size = self.bounds.size;
    return CGRectMake(_crop.origin.x * size.width, _crop.origin.y * size.height, _crop.size.width * size.width, _crop.size.height * size.height);
}

- (CGPoint)normalized:(CGPoint)point {
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1) return CGPointZero;
    return CGPointMake(MAX(0, MIN(1, point.x / size.width)), MAX(0, MIN(1, point.y / size.height)));
}

- (CGFloat)smallestWidth {
    CGFloat share = _pictureSize.width > 1 ? MIN_PIXELS / _pictureSize.width : MIN_SHARE;
    return MIN(0.5, MAX(MIN_SHARE, share));
}

- (CGFloat)smallestHeight {
    CGFloat share = _pictureSize.height > 1 ? MIN_PIXELS / _pictureSize.height : MIN_SHARE;
    return MIN(0.5, MAX(MIN_SHARE, share));
}

/* what a touch at this point takes: a corner, a side (only while the frame may take any shape), the whole frame, or nothing */
- (int)grabAtPoint:(CGPoint)point {
    CGRect frame = [self frameInView];
    CGFloat reach = MIN(GRAB_REACH, MAX(10, MIN(frame.size.width, frame.size.height) / 2));
    int best = GrabNone;
    CGFloat distance = CGFLOAT_MAX;
    for (int corner = 0; corner < 4; ++corner) {
        CGPoint handle = CGPointMake(corner & 1 ? CGRectGetMaxX(frame) : frame.origin.x, corner & 2 ? CGRectGetMaxY(frame) : frame.origin.y);
        CGFloat d = hypot(point.x - handle.x, point.y - handle.y);
        if (d < reach && d < distance) {
            distance = d;
            best = (corner & 1 ? GrabRight : GrabLeft) | (corner & 2 ? GrabBottom : GrabTop);
        }
    }
    if (best != GrabNone) return best;
    if (_ratio <= 0) {
        BOOL withinX = point.x > frame.origin.x - reach && point.x < CGRectGetMaxX(frame) + reach;
        BOOL withinY = point.y > frame.origin.y - reach && point.y < CGRectGetMaxY(frame) + reach;
        if (withinY) {
            CGFloat left = fabs(point.x - frame.origin.x), right = fabs(point.x - CGRectGetMaxX(frame));
            if (left < reach && left <= right && left < distance) { distance = left; best = GrabLeft; }
            else if (right < reach && right < distance) { distance = right; best = GrabRight; }
        }
        if (withinX) {
            CGFloat top = fabs(point.y - frame.origin.y), bottom = fabs(point.y - CGRectGetMaxY(frame));
            if (top < reach && top <= bottom && top < distance) { distance = top; best = GrabTop; }
            else if (bottom < reach && bottom < distance) { distance = bottom; best = GrabBottom; }
        }
        if (best != GrabNone) return best;
    }
    return CGRectContainsPoint(frame, point) ? GrabMove : GrabNone;
}

/* a touch that takes nothing belongs to the picture under the frame, whose tap plays and pauses the video */
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return [self grabAtPoint:point] != GrabNone;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    (void)gesture;
    _grab = [self grabAtPoint:[touch locationInView:self]];
    return _grab != GrabNone;
}

/* the frame as the drag has it: the moved frame stays inside the picture, a dragged side stops short of the opposite one, and with a ratio the corner follows the finger along
   the shape and the far corner stays where it was */
- (CGRect)frameFromStart:(CGRect)start grab:(int)grab toPoint:(CGPoint)point {
    CGFloat minWidth = [self smallestWidth], minHeight = [self smallestHeight];
    if (grab == GrabMove) {
        CGRect moved = start;
        moved.origin.x = MAX(0, MIN(1 - start.size.width, start.origin.x + point.x - _startPoint.x));
        moved.origin.y = MAX(0, MIN(1 - start.size.height, start.origin.y + point.y - _startPoint.y));
        return moved;
    }
    CGFloat left = start.origin.x, right = CGRectGetMaxX(start), top = start.origin.y, bottom = CGRectGetMaxY(start);
    if (_ratio > 0 && (grab & (GrabLeft | GrabRight)) && (grab & (GrabTop | GrabBottom))) {
        CGFloat anchorX = grab & GrabRight ? start.origin.x : CGRectGetMaxX(start);
        CGFloat anchorY = grab & GrabBottom ? start.origin.y : CGRectGetMaxY(start);
        CGFloat width = MAX(fabs(point.x - anchorX), fabs(point.y - anchorY) * _ratio);
        CGFloat farWidth = grab & GrabRight ? 1 - anchorX : anchorX;
        CGFloat farHeight = grab & GrabBottom ? 1 - anchorY : anchorY;
        CGFloat most = MIN(farWidth, farHeight * _ratio), least = MIN(most, MAX(minWidth, minHeight * _ratio));
        width = MAX(least, MIN(width, most));
        CGFloat height = width / _ratio;
        left = grab & GrabRight ? anchorX : anchorX - width;
        top = grab & GrabBottom ? anchorY : anchorY - height;
        return CGRectMake(left, top, width, height);
    }
    if (grab & GrabRight) right = MAX(left + minWidth, MIN(1, point.x));
    if (grab & GrabLeft) left = MAX(0, MIN(right - minWidth, point.x));
    if (grab & GrabBottom) bottom = MAX(top + minHeight, MIN(1, point.y));
    if (grab & GrabTop) top = MAX(0, MIN(bottom - minHeight, point.y));
    return CGRectMake(left, top, right - left, bottom - top);
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    CGPoint point = [self normalized:[pan locationInView:self]];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _start = _crop;
        /* the finger has moved a little before the drag was known, so the drag measures from where the touch came down */
        _startPoint = [self normalized:[pan locationInView:self]];
        CGPoint translation = [pan translationInView:self];
        CGSize size = self.bounds.size;
        if (size.width > 1 && size.height > 1) _startPoint = CGPointMake(MAX(0, MIN(1, _startPoint.x - translation.x / size.width)), MAX(0, MIN(1, _startPoint.y - translation.y / size.height)));
    }
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        self.crop = [self frameFromStart:_start grab:_grab toPoint:point];
        if (_changed) _changed(_crop);
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        if (_changed) _changed(_crop);
    } else if (pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        self.crop = _start;
        if (_changed) _changed(_crop);
    }
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGRect bounds = self.bounds;
    CGRect frame = [self frameInView];
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0 alpha:0.58].CGColor);
    CGContextAddRect(context, bounds);
    CGContextAddRect(context, frame);
    CGContextEOFillPath(context);
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:1 alpha:0.55].CGColor);
    CGContextSetLineWidth(context, 1);
    CGContextStrokeRect(context, frame);
    for (int i = 1; i < 3; ++i) {
        CGFloat x = frame.origin.x + frame.size.width * i / 3, y = frame.origin.y + frame.size.height * i / 3;
        CGContextMoveToPoint(context, x, frame.origin.y);
        CGContextAddLineToPoint(context, x, CGRectGetMaxY(frame));
        CGContextMoveToPoint(context, frame.origin.x, y);
        CGContextAddLineToPoint(context, CGRectGetMaxX(frame), y);
    }
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:1 alpha:0.28].CGColor);
    CGContextStrokePath(context);
    /* the corners are brackets that lie along the frame, thick enough to grab and out of the way of the picture */
    CGFloat arm = MIN(22, MIN(frame.size.width, frame.size.height) / 3);
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, 3.5);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    for (int corner = 0; corner < 4; ++corner) {
        CGFloat dx = corner & 1 ? -1 : 1, dy = corner & 2 ? -1 : 1;
        CGFloat x = corner & 1 ? CGRectGetMaxX(frame) : frame.origin.x, y = corner & 2 ? CGRectGetMaxY(frame) : frame.origin.y;
        CGContextMoveToPoint(context, x + dx * arm, y);
        CGContextAddLineToPoint(context, x, y);
        CGContextAddLineToPoint(context, x, y + dy * arm);
    }
    CGContextStrokePath(context);
}

@end
