#import "exteria_next_chat_hint.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_theme.h"

#define HINT_HEIGHT 36
#define HINT_PULL 72

@interface ExteriaNextChatHint () {
    UILabel *_label;
    NSString *_title;
    NSInteger _unread;
}
@end

@implementation ExteriaNextChatHint
@synthesize progress = _progress;

+ (CGFloat)pullDistance {
    return HINT_PULL;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = HINT_HEIGHT / 2;
    self.userInteractionEnabled = NO;
    self.alpha = 0;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = ExteriaColorTitle();
    _label.font = ExteriaFontSemibold(14);
    _label.textAlignment = ExteriaTextAlignmentCenter;
    _label.adjustsFontSizeToFitWidth = YES;
    _label.minimumFontSize = 11;
    [self addSubview:_label];
    return self;
}

- (void)dealloc {
    [_label release];
    [_title release];
    [super dealloc];
}

- (void)refreshText {
    NSString *key = _progress >= 1 ? @"chat.next.release" : @"chat.next.pull";
    NSString *line = [NSString stringWithFormat:NSLocalizedString(key, nil), _title ? _title : @""];
    if (_unread > 0) line = [line stringByAppendingFormat:@" (%ld)", (long)_unread];
    _label.text = line;
}

- (void)setTitle:(NSString *)title unread:(NSInteger)unread {
    if (title != _title) {
        [_title release];
        _title = [title copy];
    }
    _unread = unread;
    [self refreshText];
}

- (void)setProgress:(CGFloat)progress {
    CGFloat clamped = MAX(0, MIN(1, progress));
    BOOL crossed = (clamped >= 1) != (_progress >= 1);
    _progress = clamped;
    self.alpha = clamped;
    if (crossed) [self refreshText];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = CGRectInset(self.bounds, 14, 0);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(MIN(size.width - 32, 300), HINT_HEIGHT);
}

@end
