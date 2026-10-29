#import "exteria_bar_button.h"
#import "exteria_animation.h"

#import "exteria_symbol.h"
#import "exteria_theme.h"

/* the arrow glyph fills 0.8 of its square, the width the label has to clear */
#define EXTERIA_CHEVRON_SIDE 22.0
#define EXTERIA_CHEVRON_WIDTH 17.6
#define EXTERIA_CHEVRON_GAP 6.0
#define EXTERIA_BAR_PADDING 14.0

@interface ExteriaBarButton () {
    NSString *_title;
    BOOL _chevron;
    BOOL _bold;
    BOOL _dimmed;
    CGFloat _titleSize;
    UILabel *_label;
    UIColor *_inkColor;
}
@end

@implementation ExteriaBarButton

@synthesize chevron = _chevron;
@synthesize bold = _bold;
@synthesize titleSize = _titleSize;
@synthesize dimmed = _dimmed;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    ExteriaAttachBounce(self, 0.08);
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _titleSize = 17;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.userInteractionEnabled = NO;
    _label.adjustsFontSizeToFitWidth = YES;
    _label.minimumFontSize = 10;
    [self addSubview:_label];
    [self refreshLabel];
    return self;
}

- (void)dealloc {
    [_title release];
    [_label release];
    [_inkColor release];
    [super dealloc];
}

- (NSString *)title {
    return _title;
}

- (void)refreshLabel {
    _label.text = _title;
    _label.font = _bold ? ExteriaFontSemibold(_titleSize) : ExteriaFontRegular(_titleSize);
    _label.textColor = _inkColor ? _inkColor : ExteriaColorAccent();
    _label.alpha = _dimmed ? 0.4 : (self.highlighted ? 0.5 : 1.0);
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)setTitle:(NSString *)title {
    if (title == _title || [title isEqualToString:_title]) return;
    [_title release];
    _title = [title copy];
    self.accessibilityLabel = _title;
    [self refreshLabel];
}

- (UIColor *)inkColor { return _inkColor; }
- (void)setInkColor:(UIColor *)color {
    if (_inkColor == color) return;
    [_inkColor release];
    _inkColor = [color retain];
    [self refreshLabel];
}

- (void)setChevron:(BOOL)chevron { _chevron = chevron; [self refreshLabel]; }
- (void)setBold:(BOOL)bold { _bold = bold; [self refreshLabel]; }
- (void)setTitleSize:(CGFloat)titleSize { _titleSize = titleSize; [self refreshLabel]; }
- (void)setDimmed:(BOOL)dimmed { _dimmed = dimmed; [self refreshLabel]; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; [self refreshLabel]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    [_label sizeToFit];
    CGFloat inset = EXTERIA_BAR_PADDING + (_chevron ? EXTERIA_CHEVRON_WIDTH + EXTERIA_CHEVRON_GAP : 0);
    CGRect frame = _label.frame;
    frame.size.width = MIN(frame.size.width, MAX(0, self.bounds.size.width - inset));
    /* the back button hugs the left edge and the forward one the right edge */
    frame.origin.x = _chevron ? inset : MAX(0, self.bounds.size.width - EXTERIA_BAR_PADDING - frame.size.width);
    frame.origin.y = (self.bounds.size.height - frame.size.height) / 2;
    _label.frame = CGRectIntegral(frame);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_chevron) return;
    UIImage *arrow = ExteriaSymbolImage(ExteriaSymbolBack, EXTERIA_CHEVRON_SIDE, _inkColor ? _inkColor : ExteriaColorAccent());
    CGFloat margin = (EXTERIA_CHEVRON_SIDE - EXTERIA_CHEVRON_WIDTH) / 2;
    CGRect box = CGRectMake(EXTERIA_BAR_PADDING - margin, (self.bounds.size.height - EXTERIA_CHEVRON_SIDE) / 2, EXTERIA_CHEVRON_SIDE, EXTERIA_CHEVRON_SIDE);
    [arrow drawInRect:box blendMode:kCGBlendModeNormal alpha:_dimmed ? 0.4 : (self.highlighted ? 0.5 : 1.0)];
}

@end
