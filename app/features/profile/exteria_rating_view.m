#import "exteria_rating_view.h"
#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define RATING_DIM 0.55

@implementation ExteriaRatingBadge {
    int32_t _level;
}
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (int32_t)level { return _level; }
- (void)setLevel:(int32_t)level { _level = level; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    [ExteriaColorTitle() setFill];
    CGContextMoveToPoint(c, 3, 2);
    CGContextAddLineToPoint(c, w - 3, 2);
    CGContextAddLineToPoint(c, w - 3, h * 0.55);
    CGContextAddQuadCurveToPoint(c, w - 3, h * 0.8, w / 2, h - 2);
    CGContextAddQuadCurveToPoint(c, 3, h * 0.8, 3, h * 0.55);
    CGContextClosePath(c);
    CGContextFillPath(c);
    NSString *text = [NSString stringWithFormat:@"%d", (int)_level];
    UIFont *font = ExteriaFontBold(10);
    CGSize size = [text sizeWithFont:font];
    [ExteriaColorScreen() setFill];
    [text drawAtPoint:CGPointMake(floor((w - size.width) / 2), floor((h - size.height) / 2) - 1) withFont:font];
}
@end

@interface ExteriaRatingView : UIView {
    ExteriaFullUser *_user;
    UIView *_panel;
    UIScrollView *_scroll;
    UILabel *_level;
    UILabel *_amount;
    UIView *_track;
    UIView *_fill;
    UILabel *_pending;
    UIButton *_preview;
    UIButton *_close;
    BOOL _showPending;
    BOOL _closing;
}
- (id)initWithUser:(ExteriaFullUser *)user;
/* the dim comes in and the panel springs up from a little smaller */
- (void)enter;
@end

@implementation ExteriaRatingView
static UILabel *ratingLabel(NSString *text, UIFont *font, UIColor *color, NSInteger alignment) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    label.numberOfLines = 0;
    return label;
}
- (id)initWithUser:(ExteriaFullUser *)user {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _user = [user retain];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:RATING_DIM];
    _panel = [[UIView alloc] init];
    _panel.backgroundColor = ExteriaColorCard();
    _panel.layer.cornerRadius = 20;
    _panel.clipsToBounds = YES;
    [self addSubview:_panel];
    _scroll = [[UIScrollView alloc] init];
    [_panel addSubview:_scroll];
    _level = [ratingLabel(@"", ExteriaFontSemibold(17), ExteriaColorTitle(), ExteriaTextAlignmentLeft) retain];
    [_scroll addSubview:_level];
    _amount = [ratingLabel(@"", ExteriaFontSemibold(16), ExteriaColorAccent(), ExteriaTextAlignmentRight) retain];
    [_scroll addSubview:_amount];
    _track = [[UIView alloc] init];
    _track.backgroundColor = [ExteriaColorSecondary() colorWithAlphaComponent:0.25];
    _track.layer.cornerRadius = 5;
    _track.clipsToBounds = YES;
    [_scroll addSubview:_track];
    _fill = [[UIView alloc] init];
    _fill.backgroundColor = ExteriaColorAccent();
    [_track addSubview:_fill];
    _pending = [ratingLabel(@"", ExteriaFontRegular(14), ExteriaColorSecondary(), ExteriaTextAlignmentCenter) retain];
    [_scroll addSubview:_pending];
    _preview = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_preview setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    _preview.titleLabel.font = ExteriaFontSemibold(14);
    [_preview addTarget:self action:@selector(togglePreview) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_preview];
    NSArray *keys = [NSArray arrayWithObjects:@"rating.title", @"rating.about", @"rating.gifts", @"rating.users", @"rating.refunds", nil];
    for (NSUInteger i = 0; i < keys.count; ++i) {
        UILabel *label = ratingLabel(NSLocalizedString([keys objectAtIndex:i], nil), i == 0 ? ExteriaFontBold(24) : ExteriaFontRegular(i == 1 ? 15 : 14),
                                     i < 2 ? ExteriaColorTitle() : ExteriaColorSecondary(), i < 2 ? ExteriaTextAlignmentCenter : ExteriaTextAlignmentLeft);
        label.tag = 100 + (NSInteger)i;
        [_scroll addSubview:label];
    }
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setTitle:NSLocalizedString(@"rating.ok", nil) forState:UIControlStateNormal];
    [_close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _close.titleLabel.font = ExteriaFontSemibold(16);
    _close.backgroundColor = ExteriaColorAccent();
    _close.layer.cornerRadius = 18;
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_close];
    [self updateRating];
    return self;
}
- (void)dealloc {
    [_user release]; [_panel release]; [_scroll release]; [_level release]; [_amount release]; [_track release]; [_fill release];
    [_pending release]; [_preview release]; [_close release]; [super dealloc];
}
- (void)togglePreview { _showPending = !_showPending; [self updateRating]; }
- (void)enter {
    [self layoutIfNeeded];
    BOOL motion = !ExteriaReduceMotionEnabled();
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:motion ? 0 : RATING_DIM];
    if (!motion) return;
    _panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    _panel.alpha = 0;
    [UIView animateWithDuration:0.22 animations:^{ self.backgroundColor = [UIColor colorWithWhite:0 alpha:RATING_DIM]; }];
    ExteriaAnimateView(_panel, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}
- (void)close {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 animations:^{ self.backgroundColor = [UIColor colorWithWhite:0 alpha:0]; }];
    ExteriaAnimateView(_panel, CGAffineTransformMakeScale(0.94, 0.94), 0, EXTERIA_MOTION_DISMISS, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    });
}
- (void)updateRating {
    exteria_star_rating rating = _showPending ? _user.pendingRating : _user.rating;
    _level.text = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)rating.level];
    _amount.text = rating.has_next ? [NSString stringWithFormat:@"%lld / %lld", (long long)rating.stars, (long long)rating.next_level_stars]
                                   : [NSString stringWithFormat:@"%lld", (long long)rating.stars];
    if (_user.hasPendingRating) {
        NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
        format.dateStyle = NSDateFormatterMediumStyle;
        _pending.text = [NSString stringWithFormat:NSLocalizedString(@"rating.pending", nil), [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:_user.pendingRatingDate]]];
    } else _pending.text = @"";
    _preview.hidden = !_user.hasPendingRating;
    [_preview setTitle:NSLocalizedString(_showPending ? @"rating.current" : @"rating.preview", nil) forState:UIControlStateNormal];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets safe = ExteriaSafeInsets(self);
    CGFloat width = MIN(460, self.bounds.size.width - 24 - safe.left - safe.right);
    CGFloat height = MIN(600, self.bounds.size.height - safe.top - safe.bottom - 24);
    _panel.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), floor((self.bounds.size.height - height) / 2), width, height);
    _close.frame = CGRectMake(16, height - 60, width - 32, 44);
    _scroll.frame = CGRectMake(0, 0, width, height - 72);
    CGFloat inner = width - 40;
    _level.frame = CGRectMake(20, 20, inner * 0.45, 24);
    _amount.frame = CGRectMake(20 + inner * 0.45, 20, inner * 0.55, 24);
    _track.frame = CGRectMake(20, 52, inner, 10);
    exteria_star_rating rating = _showPending ? _user.pendingRating : _user.rating;
    double fraction = rating.has_next ? ((double)rating.stars - (double)rating.current_level_stars) / ((double)rating.next_level_stars - (double)rating.current_level_stars) : 1;
    _fill.frame = CGRectMake(0, 0, inner * MAX(0, MIN(1, fraction)), 10);
    CGFloat y = 76;
    if (_user.hasPendingRating) {
        _pending.frame = CGRectMake(20, y, inner, 34);
        y += 34;
        _preview.frame = CGRectMake(20, y, inner, 30);
        y += 38;
    }
    for (NSInteger i = 0; i < 5; ++i) {
        UILabel *label = (UILabel *)[_scroll viewWithTag:100 + i];
        CGSize size = [label sizeThatFits:CGSizeMake(inner, 1000)];
        label.frame = CGRectMake(20, y, inner, ceil(size.height));
        y += ceil(size.height) + (i == 0 ? 8 : 20);
    }
    _scroll.contentSize = CGSizeMake(width, y + 8);
}
@end

void ExteriaShowRating(UIView *host, ExteriaFullUser *user) {
    if (!host || !user.hasRating) return;
    ExteriaRatingView *view = [[[ExteriaRatingView alloc] initWithUser:user] autorelease];
    view.frame = host.bounds;
    [host addSubview:view];
    [view enter];
}
