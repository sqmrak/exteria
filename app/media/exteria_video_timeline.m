#import "exteria_video_timeline.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_editor_chrome.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#include "exteria_video_edit.h"

#define HANDLE_WIDTH ((CGFloat)(ExteriaIsPad() ? 24 : 18))
#define STRIP_Y ((CGFloat)(ExteriaIsPad() ? 36 : 30))
#define STRIP_HEIGHT ((CGFloat)(ExteriaIsPad() ? 68 : 52))
#define BUBBLE_HEIGHT ((CGFloat)(ExteriaIsPad() ? 26 : 22))
#define GRAB_REACH ((CGFloat)(ExteriaIsPad() ? 40 : 32))
#define MIN_GAP_SECONDS 0.1

NSString *ExteriaVideoTimeText(double seconds) {
    NSInteger total = (NSInteger)MAX(0, seconds);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

@class ExteriaVideoTimeline;

/* a handle the screen reader can reach: it reads the time it stands at and moves by a second when the reader asks it to */
@interface ExteriaTrimHandle : UIView {
    ExteriaVideoTimeline *_owner;
    BOOL _end;
}
- (id)initWithOwner:(ExteriaVideoTimeline *)owner end:(BOOL)end;
@end

@interface ExteriaVideoTimeline () {
    double _duration;
    double _start;
    double _end;
    double _position;
    NSInteger _active;
    CGFloat _grabOffset;
    UIView *_strip;
    NSMutableArray *_frameViews;
    UIView *_dimLeft;
    UIView *_dimRight;
    UIView *_range;
    ExteriaTrimHandle *_startHandle;
    ExteriaTrimHandle *_endHandle;
    UIView *_playhead;
    UILabel *_startBubble;
    UILabel *_endBubble;
    UILabel *_headBubble;
}
- (void)stepHandle:(BOOL)end direction:(int)direction;
@end

@implementation ExteriaTrimHandle
- (id)initWithOwner:(ExteriaVideoTimeline *)owner end:(BOOL)end {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _owner = owner; _end = end;
    self.userInteractionEnabled = NO;
    self.layer.cornerRadius = 6;
    UIView *grip = [[[UIView alloc] initWithFrame:CGRectMake((HANDLE_WIDTH - 3) / 2, (STRIP_HEIGHT + 6 - 20) / 2, 3, 20)] autorelease];
    grip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55]; grip.layer.cornerRadius = 1.5; grip.tag = 1;
    [self addSubview:grip];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    self.accessibilityLabel = NSLocalizedString(end ? @"video.edit.end" : @"video.edit.start", nil);
    return self;
}
- (NSString *)accessibilityValue { return ExteriaVideoTimeText((_end ? _owner.end : _owner.start) * _owner.duration); }
- (void)accessibilityIncrement { [_owner stepHandle:_end direction:1]; }
- (void)accessibilityDecrement { [_owner stepHandle:_end direction:-1]; }
@end

@implementation ExteriaVideoTimeline
+ (CGFloat)preferredHeight { return STRIP_Y + STRIP_HEIGHT + 6; }
@synthesize duration = _duration, start = _start, end = _end, position = _position, activeHandle = _active;
- (UILabel *)bubble {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
    label.textColor = [UIColor whiteColor]; label.font = ExteriaFontSemibold(ExteriaIsPad() ? 14 : 12);
    label.textAlignment = (NSTextAlignment)ExteriaTextAlignmentCenter;
    label.layer.cornerRadius = BUBBLE_HEIGHT / 2; label.layer.masksToBounds = YES;
    label.alpha = 0; label.userInteractionEnabled = NO;
    [self addSubview:label];
    return label;
}
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _end = 1;
    _strip = [[UIView alloc] init]; _strip.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];
    _strip.layer.cornerRadius = 8; _strip.clipsToBounds = YES; _strip.userInteractionEnabled = NO;
    [self addSubview:_strip];
    _frameViews = [[NSMutableArray alloc] init];
    _dimLeft = [[UIView alloc] init]; _dimRight = [[UIView alloc] init];
    _dimLeft.backgroundColor = _dimRight.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    _dimLeft.userInteractionEnabled = _dimRight.userInteractionEnabled = NO;
    [self addSubview:_dimLeft]; [self addSubview:_dimRight];
    UIColor *tint = ExteriaThemeIsClassic() ? [UIColor colorWithRed:0.35 green:0.65 blue:1 alpha:1] : ExteriaMixedColor(ExteriaColorAccent(), [UIColor whiteColor], 0.3);
    _range = [[UIView alloc] init]; _range.userInteractionEnabled = NO;
    _range.layer.borderWidth = 3; _range.layer.borderColor = tint.CGColor;
    [self addSubview:_range];
    _startHandle = [[ExteriaTrimHandle alloc] initWithOwner:self end:NO];
    _endHandle = [[ExteriaTrimHandle alloc] initWithOwner:self end:YES];
    _startHandle.backgroundColor = _endHandle.backgroundColor = tint;
    [self addSubview:_startHandle]; [self addSubview:_endHandle];
    _playhead = [[UIView alloc] init]; _playhead.userInteractionEnabled = NO;
    _playhead.backgroundColor = [UIColor whiteColor]; _playhead.layer.cornerRadius = 1.5;
    _playhead.layer.shadowColor = [UIColor blackColor].CGColor; _playhead.layer.shadowOpacity = 0.5; _playhead.layer.shadowRadius = 2; _playhead.layer.shadowOffset = CGSizeMake(0, 1);
    [self addSubview:_playhead];
    _startBubble = [[self bubble] retain]; _endBubble = [[self bubble] retain]; _headBubble = [[self bubble] retain];
    self.isAccessibilityElement = NO;
    return self;
}
- (void)dealloc {
    [_strip release]; [_frameViews release]; [_dimLeft release]; [_dimRight release]; [_range release];
    [_startHandle release]; [_endHandle release]; [_playhead release];
    [_startBubble release]; [_endBubble release]; [_headBubble release];
    [super dealloc];
}
- (void)setFrames:(NSArray *)frames {
    for (UIView *view in _frameViews) [view removeFromSuperview];
    [_frameViews removeAllObjects];
    NSTimeInterval delay = 0;
    for (id value in frames) {
        UIImageView *view = [[[UIImageView alloc] init] autorelease];
        if (value != [NSNull null]) view.image = value;
        view.contentMode = UIViewContentModeScaleAspectFill; view.clipsToBounds = YES;
        [_strip addSubview:view]; [_frameViews addObject:view];
        view.alpha = 0;
        ExteriaAnimateViewAfter(view, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, delay, nil);
        delay += 0.035;
    }
    [self setNeedsLayout];
}
- (CGFloat)stripWidth { return MAX(1, self.bounds.size.width - 2 * HANDLE_WIDTH); }
- (double)gap {
    double seconds = _duration > 0 ? MIN(1, MIN_GAP_SECONDS / _duration) : 1;
    /* the two handles are never closer than their own width, however short the video is against the strip */
    return MAX(seconds, HANDLE_WIDTH / [self stripWidth]);
}
- (CGFloat)xOfFraction:(double)fraction { return HANDLE_WIDTH + (CGFloat)fraction * [self stripWidth]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, stripWidth = [self stripWidth];
    _strip.frame = CGRectMake(HANDLE_WIDTH, STRIP_Y, stripWidth, STRIP_HEIGHT);
    NSUInteger count = _frameViews.count;
    for (NSUInteger i = 0; i < count; ++i)
        [(UIView *)[_frameViews objectAtIndex:i] setFrame:CGRectMake(floor(i * stripWidth / count), 0, ceil(stripWidth / count) + 1, STRIP_HEIGHT)];
    CGFloat startX = [self xOfFraction:_start], endX = [self xOfFraction:_end];
    _dimLeft.frame = CGRectMake(HANDLE_WIDTH, STRIP_Y, MAX(0, startX - HANDLE_WIDTH), STRIP_HEIGHT);
    _dimRight.frame = CGRectMake(endX, STRIP_Y, MAX(0, width - HANDLE_WIDTH - endX), STRIP_HEIGHT);
    _range.frame = CGRectMake(startX, STRIP_Y - 3, MAX(0, endX - startX), STRIP_HEIGHT + 6);
    /* a handle that is held is a little taller, set by the transform so a layout pass does not undo it */
    ExteriaPlaceView(_startHandle, CGRectMake(startX - HANDLE_WIDTH, STRIP_Y - 3, HANDLE_WIDTH, STRIP_HEIGHT + 6));
    ExteriaPlaceView(_endHandle, CGRectMake(endX, STRIP_Y - 3, HANDLE_WIDTH, STRIP_HEIGHT + 6));
    CGFloat head = [self xOfFraction:MAX(0, MIN(1, _position))];
    ExteriaPlaceView(_playhead, CGRectMake(head - 1.5, STRIP_Y - 7, 3, STRIP_HEIGHT + 14));
    [self placeBubble:_startBubble at:startX - HANDLE_WIDTH / 2 time:_start * _duration];
    [self placeBubble:_endBubble at:endX + HANDLE_WIDTH / 2 time:_end * _duration];
    [self placeBubble:_headBubble at:head time:_position * _duration];
}
- (void)placeBubble:(UILabel *)bubble at:(CGFloat)x time:(double)seconds {
    bubble.text = ExteriaVideoTimeText(seconds);
    CGFloat width = ceil([bubble.text sizeWithFont:bubble.font].width) + 18;
    CGFloat left = MAX(0, MIN(self.bounds.size.width - width, x - width / 2));
    ExteriaPlaceView(bubble, CGRectMake(left, 0, width, BUBBLE_HEIGHT));
}
- (void)setDuration:(double)duration { _duration = duration; [self setNeedsLayout]; }
- (void)setStart:(double)start { _start = MAX(0, MIN(1, start)); [self setNeedsLayout]; }
- (void)setEnd:(double)end { _end = MAX(0, MIN(1, end)); [self setNeedsLayout]; }
- (void)setPosition:(double)position {
    _position = position;
    if (_active == 3) return;
    /* the playhead is moved straight, without a layout pass, so a playing video costs one position a frame */
    CGFloat head = [self xOfFraction:MAX(0, MIN(1, _position))];
    ExteriaPlaceView(_playhead, CGRectMake(head - 1.5, STRIP_Y - 7, 3, STRIP_HEIGHT + 14));
}
- (void)holdBubble:(UILabel *)bubble handle:(UIView *)handle shown:(BOOL)shown {
    CGAffineTransform away = CGAffineTransformMakeScale(0.7, 0.7);
    ExteriaAnimateView(bubble, shown ? CGAffineTransformIdentity : away, shown ? 1 : 0, shown ? EXTERIA_MOTION_SPRING : EXTERIA_MOTION_DISMISS, nil);
    if (handle) ExteriaAnimateView(handle, shown ? CGAffineTransformMakeScale(1.15, 1.06) : CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}
- (void)grab:(NSInteger)which shown:(BOOL)shown {
    if (which == 1) [self holdBubble:_startBubble handle:_startHandle shown:shown];
    else if (which == 2) [self holdBubble:_endBubble handle:_endHandle shown:shown];
    else if (which == 3) [self holdBubble:_headBubble handle:nil shown:shown];
}
- (void)moveTo:(CGFloat)x {
    double fraction = (x - HANDLE_WIDTH) / [self stripWidth], gap = [self gap];
    if (_active == 1) {
        _start = exteria_video_edit_handle(0, fraction, _end, gap);
        _position = _start;
    } else if (_active == 2) {
        _end = exteria_video_edit_handle(1, fraction, _start, gap);
        _position = _end;
    } else if (_active == 3) {
        _position = MAX(_start, MIN(_end, fraction));
    }
    [self setNeedsLayout]; [self layoutIfNeeded];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (_duration <= 0) return NO;
    CGFloat x = [touch locationInView:self].x;
    CGFloat startCenter = [self xOfFraction:_start] - HANDLE_WIDTH / 2, endCenter = [self xOfFraction:_end] + HANDLE_WIDTH / 2;
    CGFloat nearStart = fabs(x - startCenter), nearEnd = fabs(x - endCenter);
    if (nearStart <= GRAB_REACH || nearEnd <= GRAB_REACH) _active = nearStart <= nearEnd ? 1 : 2;
    else _active = 3;
    _grabOffset = _active == 1 ? x - startCenter : (_active == 2 ? x - endCenter : 0);
    [self grab:_active shown:YES];
    [self moveTo:x - _grabOffset + (_active == 1 ? HANDLE_WIDTH / 2 : (_active == 2 ? -HANDLE_WIDTH / 2 : 0))];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGFloat x = [touch locationInView:self].x;
    [self moveTo:x - _grabOffset + (_active == 1 ? HANDLE_WIDTH / 2 : (_active == 2 ? -HANDLE_WIDTH / 2 : 0))];
    return YES;
}
- (void)finishTracking {
    NSInteger which = _active;
    _active = 0;
    [self grab:which shown:NO];
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self finishTracking]; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { [self finishTracking]; }
- (void)stepHandle:(BOOL)end direction:(int)direction {
    if (_duration <= 0) return;
    double step = MAX(1.0 / _duration, 0.01) * direction, gap = [self gap];
    if (end) _end = exteria_video_edit_handle(1, _end + step, _start, gap);
    else _start = exteria_video_edit_handle(0, _start + step, _end, gap);
    _position = end ? _end : _start;
    [self setNeedsLayout]; [self layoutIfNeeded];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}
@end
