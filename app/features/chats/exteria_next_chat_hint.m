#import "exteria_next_chat_hint.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_dialog.h"
#import "exteria_theme.h"

#define HINT_PULL 110.0
#define PLATE_RADIUS 28.0
#define RELEASE_IN 0.25
#define RELEASE_OUT 0.22
#define BOUNCE_UP 0.18
#define BOUNCE_DOWN 0.12
#define BOUNCE_BACK 0.10

@interface ExteriaNextChatHint () {
    NSString *_title;
    NSInteger _unread;
    UIImage *_icon;
    CGFloat _progress;
    CGFloat _release;
    CGFloat _releaseFrom;
    CGFloat _releaseTo;
    CGFloat _bounce;
    BOOL _bouncing;
    CFTimeInterval _started;
    CADisplayLink *_link;
}
@end

@implementation ExteriaNextChatHint
@synthesize progress = _progress;

+ (CGFloat)pullDistance {
    return HINT_PULL;
}

+ (ExteriaDialog *)nextUnreadTopicIn:(NSArray *)topics after:(ExteriaDialog *)current seen:(NSMutableSet *)seen {
    [seen addObject:[NSNumber numberWithInt:current.topicId]];
    for (ExteriaDialog *topic in topics) {
        if (topic.topicId <= 0 || topic.unreadCount <= 0 || [seen containsObject:[NSNumber numberWithInt:topic.topicId]]) continue;
        return topic;
    }
    return nil;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.hidden = YES;
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_title release];
    [_icon release];
    [super dealloc];
}

- (void)setTitle:(NSString *)title unread:(NSInteger)unread icon:(UIImage *)icon {
    if (title != _title) {
        [_title release];
        _title = [title copy];
    }
    _unread = unread;
    [self setIcon:icon];
}

- (void)setIcon:(UIImage *)icon {
    if (icon != _icon) {
        [_icon release];
        _icon = [icon retain];
    }
    [self setNeedsDisplay];
}

- (void)setProgress:(CGFloat)progress {
    CGFloat clamped = MAX(0, MIN(1, progress));
    if (clamped == _progress) return;
    BOOL wasReleased = _progress >= 1;
    _progress = clamped;
    self.hidden = clamped <= 0 && _release <= 0;
    if (clamped >= 1 && !wasReleased) [self animateReleaseTo:1];
    else if (clamped < 1 && wasReleased) [self animateReleaseTo:0];
    [self setNeedsDisplay];
}

- (void)animateReleaseTo:(CGFloat)target {
    _releaseFrom = _release;
    _releaseTo = target;
    _bouncing = target > 0;
    _bounce = 0;
    _started = CACurrentMediaTime();
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

static CGFloat ExteriaEaseOutQuint(CGFloat t) {
    CGFloat u = 1 - t;
    return 1 - u * u * u * u * u;
}

static CGFloat ExteriaEaseBoth(CGFloat t) {
    return t * t * (3 - 2 * t);
}

/* the bounce of the plate when it turns into the picture: up, a little past rest downwards, then home */
static CGFloat ExteriaBounceAt(CFTimeInterval t) {
    if (t < BOUNCE_UP) return ExteriaEaseBoth((CGFloat)(t / BOUNCE_UP));
    t -= BOUNCE_UP;
    if (t < BOUNCE_DOWN) return 1 + (-0.5f - 1) * ExteriaEaseBoth((CGFloat)(t / BOUNCE_DOWN));
    t -= BOUNCE_DOWN;
    if (t < BOUNCE_BACK) return -0.5f + 0.5f * ExteriaEaseBoth((CGFloat)(t / BOUNCE_BACK));
    return 0;
}

- (void)step:(CADisplayLink *)link {
    (void)link;
    CFTimeInterval elapsed = CACurrentMediaTime() - _started;
    CFTimeInterval duration = _releaseTo > 0 ? RELEASE_IN : RELEASE_OUT;
    CGFloat t = (CGFloat)MIN(1, elapsed / duration);
    CGFloat eased = _releaseTo > 0 ? ExteriaEaseOutQuint(t) : ExteriaEaseBoth(t);
    _release = _releaseFrom + (_releaseTo - _releaseFrom) * eased;
    _bounce = _bouncing ? ExteriaBounceAt(elapsed) : 0;
    BOOL done = t >= 1 && (!_bouncing || elapsed >= BOUNCE_UP + BOUNCE_DOWN + BOUNCE_BACK);
    if (done) {
        _release = _releaseTo;
        _bounce = 0;
        [_link invalidate];
        _link = nil;
        self.hidden = _progress <= 0 && _release <= 0;
    }
    [self setNeedsDisplay];
}

static UIColor *ExteriaPlateColor(CGFloat alpha) {
    return [UIColor colorWithWhite:0 alpha:0.42f * alpha];
}

- (void)drawArrowAt:(CGPoint)center size:(CGFloat)size context:(CGContextRef)context {
    CGFloat scale = size / 24.0;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, center.x, center.y - 20);
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, -center.x, -(center.y - 20));
    CGContextTranslateCTM(context, center.x - 12, center.y - 12);
    CGContextMoveToPoint(context, 12.5, 4);
    CGContextAddLineToPoint(context, 12.5, 22);
    CGContextMoveToPoint(context, 3.5, 12);
    CGContextAddLineToPoint(context, 12.5, 3.5);
    CGContextAddLineToPoint(context, 21.5, 12);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

- (void)drawRect:(CGRect)dirty {
    (void)dirty;
    CGFloat p = _progress, s = _release;
    CGFloat offset = HINT_PULL * p;
    if (offset < 8) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat alpha = p < 0.2f ? p * 5 : 1;
    CGFloat cx = self.bounds.size.width / 2;
    CGFloat bounceOffset = _bounce * -4;
    CGFloat radius = MAX(0, MIN(PLATE_RADIUS, offset / 2 - 16 * p - 4));
    CGFloat radius2 = MAX(0, MIN(PLATE_RADIUS * p, offset / 2 - 8 * p));
    CGFloat size = (radius2 * 2 - 16) * (1 - s) + 56 * s;

    if (s < 1) {
        CGFloat bottom = offset * (1 - s) - 8 * (1 - s) + 56 * s;
        CGRect plate = CGRectMake(cx - radius, 0, radius * 2, MAX(0, bottom));
        CGFloat plateAlpha = alpha;
        if (s > 0) {
            plate = CGRectInset(plate, 16 * s, 16 * s);
            plateAlpha = alpha * (1 - s);
        }
        if (plate.size.width > 0 && plate.size.height > 0) {
            CGFloat corner = MIN(plate.size.width, plate.size.height) / 2;
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:plate cornerRadius:corner];
            [ExteriaPlateColor(plateAlpha) setFill];
            [path fill];
            CGContextSaveGState(context);
            CGContextClipToRect(context, CGRectInset(plate, 1, 1));
            CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:1 alpha:plateAlpha].CGColor);
            CGContextSetLineWidth(context, 2.8f);
            CGContextSetLineCap(context, kCGLineCapRound);
            CGContextSetLineJoin(context, kCGLineJoinRound);
            [self drawArrowAt:CGPointMake(cx, 24 + 8 * (1 - p) - 36 * s) size:24 * p context:context];
            CGContextRestoreGState(context);
        }
    }

    if (s > 0 && _title.length) {
        UIFont *font = ExteriaFontSemibold(13);
        CGFloat maxWidth = self.bounds.size.width - 60;
        CGSize measured = [_title sizeWithFont:font];
        CGFloat width = MIN(ceil(measured.width), maxWidth);
        CGFloat y = offset + 20 * (1 - s) - 36 * s + bounceOffset;
        CGRect pill = CGRectMake(cx - width / 2 - 8, y - 4, width + 16, measured.height + 8);
        [ExteriaPlateColor(alpha) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:15] fill];
        [[UIColor colorWithWhite:1 alpha:alpha] set];
        [_title drawInRect:CGRectMake(cx - width / 2, y, width, measured.height) withFont:font lineBreakMode:UILineBreakModeTailTruncation alignment:(NSTextAlignment)ExteriaTextAlignmentCenter];
    }

    if (size > 0) {
        CGFloat top = offset * (1 - s) + (-8 - 8 * p - size) * (1 - s) + 4 * s + bounceOffset;
        CGRect face = CGRectMake(cx - size / 2, top, size, size);
        CGContextSaveGState(context);
        CGContextSetAlpha(context, alpha);
        CGContextAddEllipseInRect(context, face);
        CGContextClip(context);
        if (_icon) {
            [_icon drawInRect:face];
        } else {
            [ExteriaColorAccent() setFill];
            CGContextFillRect(context, face);
            NSString *letter = _title.length ? [[_title substringToIndex:1] uppercaseString] : @"";
            UIFont *font = ExteriaFontSemibold(MAX(8, size * 0.42f));
            CGSize letterSize = [letter sizeWithFont:font];
            [[UIColor whiteColor] set];
            [letter drawAtPoint:CGPointMake(CGRectGetMidX(face) - letterSize.width / 2, CGRectGetMidY(face) - letterSize.height / 2) withFont:font];
        }
        CGContextRestoreGState(context);
        if (s > 0 && _unread > 0) {
            NSString *count = _unread > 999 ? @"999+" : [NSString stringWithFormat:@"%ld", (long)_unread];
            UIFont *font = ExteriaFontSemibold(12);
            CGSize measured = [count sizeWithFont:font];
            CGFloat width = MAX(20, ceil(measured.width) + 12);
            CGRect badge = CGRectMake(cx + 12, top - 6, width, 20);
            CGContextSaveGState(context);
            CGContextTranslateCTM(context, CGRectGetMidX(badge), CGRectGetMidY(badge));
            CGContextScaleCTM(context, s, s);
            CGContextTranslateCTM(context, -CGRectGetMidX(badge), -CGRectGetMidY(badge));
            [ExteriaColorAccent() setFill];
            [[UIBezierPath bezierPathWithRoundedRect:badge cornerRadius:10] fill];
            [[UIColor whiteColor] set];
            [count drawInRect:CGRectMake(badge.origin.x, badge.origin.y + (20 - measured.height) / 2, width, measured.height) withFont:font lineBreakMode:UILineBreakModeClip alignment:(NSTextAlignment)ExteriaTextAlignmentCenter];
            CGContextRestoreGState(context);
        }
    }
}

@end
