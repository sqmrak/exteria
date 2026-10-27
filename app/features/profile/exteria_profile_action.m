#import "exteria_profile_action.h"
#import "exteria_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_theme.h"

@implementation ExteriaUserAction

- (id)initWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    ExteriaAttachBounce(self, 0.06);
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 14;
    _icon = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(symbol, 24, ExteriaColorAccent())];
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textAlignment = ExteriaTextAlignmentCenter;
    _caption.font = ExteriaFontMedium(13);
    _caption.textColor = ExteriaColorTitle();
    _caption.adjustsFontSizeToFitWidth = YES;
    _caption.text = title;
    [self addSubview:_caption];
    self.accessibilityLabel = title;
    return self;
}

- (void)setSymbol:(ExteriaSymbol)symbol title:(NSString *)title {
    _icon.image = ExteriaSymbolImage(symbol, 24, ExteriaColorAccent());
    _caption.text = title;
    self.accessibilityLabel = title;
}

- (void)dealloc {
    [_icon release];
    [_caption release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _icon.frame = CGRectMake(0, 8, size.width, 28);
    _caption.frame = CGRectMake(6, 38, size.width - 12, 18);
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1 : 0.45;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (self.enabled) self.alpha = highlighted ? 0.6 : 1;
}

@end

CGFloat ExteriaLayoutActions(NSArray *actions, CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat gap) {
    NSUInteger count = actions.count;
    if (!count) return 0;
    NSUInteger rows = (count + 3) / 4;
    NSUInteger perRow = (count + rows - 1) / rows;
    for (NSUInteger i = 0; i < count; ++i) {
        NSUInteger row = i / perRow;
        NSUInteger inRow = MIN(perRow, count - row * perRow);
        CGFloat each = (width - gap * (CGFloat)(inRow - 1)) / (CGFloat)inRow;
        ((UIView *)[actions objectAtIndex:i]).frame = CGRectMake(x + (CGFloat)(i - row * perRow) * (each + gap), y + (CGFloat)row * (height + gap), each, height);
    }
    return (CGFloat)rows * height + (CGFloat)(rows - 1) * gap;
}
