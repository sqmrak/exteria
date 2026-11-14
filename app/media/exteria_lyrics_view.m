#import "exteria_lyrics_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_music_player.h"
#import "exteria_theme.h"

#define LINE_FONT 24.0
#define SIDE_INSET 22.0
#define LINE_GAP 18.0
/* the room above the first line and below the last: a line that is sung stands near the upper third once the list is long enough, and the first and last lines just rest at the edges */
#define EDGE_TOP 12.0
#define EDGE_BOTTOM 28.0
#define DIM_ALPHA 0.38
#define DIM_SCALE 0.9
#define FOLLOW_INTERVAL 0.1

@interface ExteriaLyricsView () <UIScrollViewDelegate> {
    UIScrollView *_scroll;
    UILabel *_status;
    ExteriaLyrics *_lyrics;
    NSMutableArray *_labels;
    NSMutableArray *_frames;
    NSInteger _active;
    CGFloat _laidWidth;
    BOOL _dragging;
    BOOL _skeuomorphic;
    NSTimer *_timer;
}
@end

@implementation ExteriaLyricsView
@synthesize onSeek;
@synthesize skeuomorphic = _skeuomorphic;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.clipsToBounds = YES;
    _active = -2;
    _scroll = [[UIScrollView alloc] init];
    _scroll.delegate = self;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.alwaysBounceVertical = YES;
    [_scroll addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease]];
    [self addSubview:_scroll];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.font = ExteriaFontRegular(16);
    _status.textColor = ExteriaColorSecondary();
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [self addSubview:_status];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    _scroll.delegate = nil;
    [_scroll release]; [_status release]; [_lyrics release];
    [_labels release]; [_frames release]; [onSeek release];
    [super dealloc];
}

- (void)setSkeuomorphic:(BOOL)skeuomorphic {
    _skeuomorphic = skeuomorphic;
    _status.textColor = skeuomorphic ? [UIColor colorWithWhite:1 alpha:0.6f] : ExteriaColorSecondary();
}

/* how small the lines that wait are: the skeuomorphic look keeps one size */
- (CGFloat)dimScale { return _skeuomorphic ? 1 : DIM_SCALE; }

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    _status.frame = CGRectMake(SIDE_INSET, 0, MAX(0, self.bounds.size.width - SIDE_INSET * 2), self.bounds.size.height * 0.6);
    /* a turn of the phone changes the width the lines wrap at */
    if (_lyrics && fabs(self.bounds.size.width - _laidWidth) > 0.5) [self layoutLines];
}

- (UIFont *)lineFont { return ExteriaFontBold(LINE_FONT); }

- (void)clearLabels {
    for (UILabel *label in _labels) [label removeFromSuperview];
    [_labels release]; _labels = nil;
    [_frames release]; _frames = nil;
    _active = -2;
}

- (void)showStatus:(NSString *)text {
    [_lyrics release]; _lyrics = nil;
    [self clearLabels];
    _scroll.contentSize = CGSizeZero;
    _status.text = text;
    _status.hidden = !text.length;
    [self updateTimer];
}

- (void)showLyrics:(ExteriaLyrics *)lyrics {
    [self clearLabels];
    [_lyrics release];
    _lyrics = [lyrics retain];
    _status.hidden = YES;
    _labels = [[NSMutableArray alloc] initWithCapacity:lyrics.lines.count];
    for (NSString *line in lyrics.lines) {
        UILabel *label = [[UILabel alloc] init];
        label.backgroundColor = [UIColor clearColor];
        label.font = [self lineFont];
        label.textColor = _skeuomorphic ? [UIColor whiteColor] : ExteriaColorTitle();
        label.numberOfLines = 0;
        label.text = line;
        label.layer.anchorPoint = CGPointMake(0, 0.5);
        [_scroll addSubview:label];
        [_labels addObject:label];
        [label release];
    }
    _scroll.contentOffset = CGPointZero;
    [self layoutLines];
    [self updatePosition:[ExteriaMusicPlayer sharedPlayer].position animated:NO];
    [self updateTimer];
}

/* sizes and places every line for the current width; the synced lines are dim and small until their turn */
- (void)layoutLines {
    CGFloat width = self.bounds.size.width;
    if (width <= 0 || !_labels.count) return;
    _laidWidth = width;
    CGFloat textWidth = width - SIDE_INSET * 2;
    UIFont *font = [self lineFont];
    [_frames release];
    _frames = [[NSMutableArray alloc] initWithCapacity:_labels.count];
    CGFloat y = EDGE_TOP;
    BOOL synced = _lyrics.synced;
    for (UILabel *label in _labels) {
        CGFloat lineHeight = ceil([label.text sizeWithFont:font constrainedToSize:CGSizeMake(textWidth, 4000)].height) + 4;
        CGRect frame = CGRectMake(SIDE_INSET, y, textWidth, lineHeight);
        [label.layer removeAllAnimations];
        ExteriaPlaceView(label, frame);
        label.transform = synced ? CGAffineTransformMakeScale([self dimScale], [self dimScale]) : CGAffineTransformIdentity;
        label.alpha = synced ? DIM_ALPHA : 1;
        [_frames addObject:[NSValue valueWithCGRect:frame]];
        y += lineHeight + LINE_GAP;
    }
    _scroll.contentSize = CGSizeMake(width, y - LINE_GAP + EDGE_BOTTOM);
    NSInteger active = _active;
    _active = -2;
    if (synced && active != -2) [self setActive:active animated:NO];
}

- (CGFloat)offsetCenteringLine:(NSInteger)index {
    CGRect frame = [[_frames objectAtIndex:(NSUInteger)index] CGRectValue];
    CGFloat maximum = MAX(0, _scroll.contentSize.height - _scroll.bounds.size.height);
    return MAX(0, MIN(CGRectGetMidY(frame) - _scroll.bounds.size.height * 0.38, maximum));
}

- (void)setActive:(NSInteger)active animated:(BOOL)animated {
    if (active == _active || !_labels.count) return;
    NSInteger previous = _active;
    _active = active;
    if (previous >= 0 && (NSUInteger)previous < _labels.count) {
        ExteriaAnimateView([_labels objectAtIndex:(NSUInteger)previous], CGAffineTransformMakeScale([self dimScale], [self dimScale]), DIM_ALPHA,
                           animated ? EXTERIA_MOTION_DISMISS : EXTERIA_MOTION_ENTER, nil);
    }
    if (active < 0 || (NSUInteger)active >= _labels.count) return;
    ExteriaAnimateView([_labels objectAtIndex:(NSUInteger)active], CGAffineTransformIdentity, 1, animated ? (_skeuomorphic ? EXTERIA_MOTION_ENTER : EXTERIA_MOTION_WOBBLE) : EXTERIA_MOTION_ENTER, nil);
    if (_dragging) return;
    CGFloat target = [self offsetCenteringLine:active];
    if (animated) [_scroll setContentOffset:CGPointMake(0, target) animated:YES];
    else _scroll.contentOffset = CGPointMake(0, target);
}

- (void)updatePosition:(NSTimeInterval)seconds animated:(BOOL)animated {
    if (!_lyrics.synced) return;
    [self setActive:[_lyrics activeLineAt:seconds] animated:animated];
}

- (void)follow:(NSTimer *)timer {
    (void)timer;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    /* a paused song still moves its line: a tap on a line seeks while paused, and the highlight has to follow the new position without play */
    if (player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStatePaused) [self updatePosition:player.position animated:YES];
}

/* the timer runs only while synced lyrics are on a screen, and it holds the view, so it is stopped the moment the view leaves the window */
- (void)updateTimer {
    BOOL wanted = self.window && _lyrics.synced && !self.hidden;
    if (wanted && !_timer) _timer = [NSTimer scheduledTimerWithTimeInterval:FOLLOW_INTERVAL target:self selector:@selector(follow:) userInfo:nil repeats:YES];
    else if (!wanted && _timer) { [_timer invalidate]; _timer = nil; }
}
- (void)willMoveToWindow:(UIWindow *)window {
    [super willMoveToWindow:window];
    if (!window && _timer) { [_timer invalidate]; _timer = nil; }
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateTimer];
}
- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updateTimer];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (!_lyrics.synced || !self.onSeek) return;
    CGPoint point = [tap locationInView:_scroll];
    for (NSUInteger i = 0; i < _frames.count; ++i) {
        CGRect frame = CGRectInset([[_frames objectAtIndex:i] CGRectValue], -4, -LINE_GAP / 2);
        if (CGRectContainsPoint(frame, point)) {
            /* a hair past the stamp so the rounding of the player keeps this line the active one */
            self.onSeek([_lyrics startOfLine:(NSInteger)i] + 0.05);
            _dragging = NO;
            return;
        }
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { (void)scrollView; _dragging = YES; }
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate { (void)scrollView; if (!decelerate) _dragging = NO; }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView { (void)scrollView; _dragging = NO; }

@end
