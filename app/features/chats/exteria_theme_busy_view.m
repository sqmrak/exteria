#import "exteria_theme_busy_view.h"

#import "exteria_lottie_view.h"
#import "exteria_shiro_style.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define DUCK_SIDE 132.0
#define LABEL_GAP 6.0

@interface ExteriaThemeBusyView () {
    ExteriaLottieView *_duck;
    UILabel *_label;
    BOOL _ready;
    void (^_waiting)(void);
}
@end

@implementation ExteriaThemeBusyView

- (id)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame animation:@"theme_duck"];
}

- (id)initWithFrame:(CGRect)frame animation:(NSString *)animation {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42f];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.userInteractionEnabled = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = NSLocalizedString(@"theme.applying", nil);
    _duck = [[ExteriaLottieView alloc] initWithAnimationNamed:animation];
    [self addSubview:_duck];
    /* the animation is parsed when the view is made, long before it is shown: the parse took longer than the darkening, and the duck was missing */
    ExteriaThemeBusyView *me = self;
    _duck.firstFrameHandler = ^{ [me duckReady]; };
    [_duck setLoaded:YES];
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = ExteriaTextAlignmentCenter;
    _label.font = ExteriaShiroFontBody(17, YES);
    _label.numberOfLines = 2;
    _label.text = NSLocalizedString(@"theme.applying", nil);
    [self addSubview:_label];
    return self;
}

- (NSString *)text {
    return _label.text;
}

- (void)setText:(NSString *)text {
    _label.text = text;
    self.accessibilityLabel = text;
    [self setNeedsLayout];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(duckReady) object:nil];
    _duck.firstFrameHandler = nil;
    [_waiting release];
    [_duck release];
    [_label release];
    [super dealloc];
}

- (void)duckReady {
    _ready = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(duckReady) object:nil];
    void (^block)(void) = _waiting;
    _waiting = nil;
    if (block) {
        block();
        [block release];
    }
}

- (void)whenReady:(void (^)(void))block {
    if (_ready) {
        block();
        return;
    }
    [_waiting release];
    _waiting = [block copy];
    /* the first frame may never come (the animation failed to parse), and the work must not wait for it for ever */
    [self performSelector:@selector(duckReady) withObject:nil afterDelay:0.8];
}

- (void)startAnimating {
    [_duck setPlaying:YES];
}

/* the animation stays parsed for the next change; only its playing stops */
- (void)stopAnimating {
    [_duck setPlaying:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat textWidth = MIN(size.width - 48, 300);
    CGSize fit = [_label sizeThatFits:CGSizeMake(textWidth, 80)];
    CGFloat total = DUCK_SIDE + LABEL_GAP + fit.height;
    CGFloat top = floor((size.height - total) / 2);
    _duck.frame = CGRectMake(floor((size.width - DUCK_SIDE) / 2), top, DUCK_SIDE, DUCK_SIDE);
    _label.frame = CGRectMake(floor((size.width - textWidth) / 2), top + DUCK_SIDE + LABEL_GAP, textWidth, ceil(fit.height));
}

@end
