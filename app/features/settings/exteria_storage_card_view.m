#import "exteria_storage_card_view.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_chat_settings.h"
#import "exteria_theme.h"

#define ROW_HEIGHT 56.0
#define CARD_PAD 16.0
#define BUTTON_HEIGHT 52.0
#define DOT_SIDE 26.0
#define TEXT_LEFT 62.0

/* the round check of a row: a filled disc with a white tick, or a ring when the row is not checked */
@interface ExteriaStorageDot : UIView {
    UIColor *_color;
    BOOL _checked;
}
- (void)setColor:(UIColor *)color checked:(BOOL)checked;
@end

@implementation ExteriaStorageDot

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    return self;
}

- (void)dealloc {
    [_color release];
    [super dealloc];
}

- (void)setColor:(UIColor *)color checked:(BOOL)checked {
    if (color != _color) {
        [_color release];
        _color = [color retain];
    }
    _checked = checked;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    CGRect disc = CGRectMake(0, 0, side, side);
    if (_checked) {
        CGContextSetFillColorWithColor(context, _color.CGColor);
        CGContextFillEllipseInRect(context, disc);
        CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextSetLineWidth(context, 2.2);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        CGContextMoveToPoint(context, side * 0.27, side * 0.53);
        CGContextAddLineToPoint(context, side * 0.43, side * 0.68);
        CGContextAddLineToPoint(context, side * 0.74, side * 0.35);
        CGContextStrokePath(context);
    } else {
        CGContextSetStrokeColorWithColor(context, _color.CGColor);
        CGContextSetLineWidth(context, 2);
        CGContextStrokeEllipseInRect(context, CGRectInset(disc, 1, 1));
    }
}

@end

@interface ExteriaStorageRow : UIControl {
@public
    ExteriaStorageDot *dot;
    UILabel *title;
    UILabel *share;
    UILabel *size;
    UIView *line;
}
@end

@implementation ExteriaStorageRow

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    dot = [[ExteriaStorageDot alloc] initWithFrame:CGRectMake(CARD_PAD, (ROW_HEIGHT - DOT_SIDE) / 2, DOT_SIDE, DOT_SIDE)];
    [self addSubview:dot];
    title = [[UILabel alloc] init];
    title.backgroundColor = [UIColor clearColor];
    title.font = ExteriaFontSemibold(17);
    title.textColor = ExteriaColorTitle();
    [self addSubview:title];
    share = [[UILabel alloc] init];
    share.backgroundColor = [UIColor clearColor];
    share.font = ExteriaFontSemibold(15);
    share.textColor = ExteriaColorTitle();
    [self addSubview:share];
    size = [[UILabel alloc] init];
    size.backgroundColor = [UIColor clearColor];
    size.font = ExteriaFontMedium(16);
    size.textColor = ExteriaColorSecondary();
    size.textAlignment = ExteriaTextAlignmentRight;
    [self addSubview:size];
    line = [[UIView alloc] init];
    line.backgroundColor = ExteriaColorHairline();
    line.userInteractionEnabled = NO;
    [self addSubview:line];
    return self;
}

- (void)dealloc {
    [dot release];
    [title release];
    [share release];
    [size release];
    [line release];
    [super dealloc];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [ExteriaColorHairline() colorWithAlphaComponent:0.5f] : [UIColor clearColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat sizeWidth = MIN(120, [size.text sizeWithFont:size.font].width + 2);
    size.frame = CGRectMake(width - CARD_PAD - sizeWidth, 0, sizeWidth, ROW_HEIGHT);
    CGFloat room = size.frame.origin.x - TEXT_LEFT - 8;
    CGFloat shareWidth = [share.text sizeWithFont:share.font].width + 1;
    CGFloat titleWidth = MIN([title.text sizeWithFont:title.font].width + 1, room - shareWidth - 8);
    title.frame = CGRectMake(TEXT_LEFT, 0, MAX(titleWidth, 0), ROW_HEIGHT);
    share.frame = CGRectMake(TEXT_LEFT + MAX(titleWidth, 0) + 8, 1, shareWidth, ROW_HEIGHT);
    line.frame = CGRectMake(TEXT_LEFT, ROW_HEIGHT - 0.5f, width - TEXT_LEFT, 0.5f);
}

@end

@interface ExteriaStorageCardView () {
    NSMutableArray *_rows;
    NSMutableArray *_colors;
    UIControl *_button;
    UILabel *_buttonTitle;
    UILabel *_buttonSize;
    BOOL _enabled;
    void (^_toggleHandler)(NSUInteger);
    void (^_clearHandler)(void);
}
@end

@implementation ExteriaStorageCardView

@synthesize toggleHandler = _toggleHandler;
@synthesize clearHandler = _clearHandler;

+ (CGFloat)heightForRows:(NSUInteger)rows {
    return rows * ROW_HEIGHT + CARD_PAD + BUTTON_HEIGHT + CARD_PAD;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = ExteriaSectionRadius();
    self.clipsToBounds = YES;
    _rows = [[NSMutableArray alloc] init];
    _colors = [[NSMutableArray alloc] init];
    _button = [[UIControl alloc] init];
    _button.backgroundColor = ExteriaColorAccent();
    _button.layer.cornerRadius = BUTTON_HEIGHT / 2;
    [_button addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    ExteriaAttachBounce(_button, 0.03f);
    [self addSubview:_button];
    _buttonTitle = [[UILabel alloc] init];
    _buttonTitle.backgroundColor = [UIColor clearColor];
    _buttonTitle.font = ExteriaFontBold(17);
    _buttonTitle.textColor = [UIColor whiteColor];
    _buttonTitle.userInteractionEnabled = NO;
    [_button addSubview:_buttonTitle];
    _buttonSize = [[UILabel alloc] init];
    _buttonSize.backgroundColor = [UIColor clearColor];
    _buttonSize.font = ExteriaFontMedium(17);
    _buttonSize.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.75f];
    _buttonSize.userInteractionEnabled = NO;
    [_button addSubview:_buttonSize];
    return self;
}

- (void)dealloc {
    [_rows release];
    [_colors release];
    [_button release];
    [_buttonTitle release];
    [_buttonSize release];
    [_toggleHandler release];
    [_clearHandler release];
    [super dealloc];
}

- (void)setButtonSize:(NSString *)buttonSize enabled:(BOOL)enabled {
    _buttonSize.text = buttonSize;
    _enabled = enabled;
    _button.enabled = enabled;
    _button.alpha = enabled ? 1 : 0.45f;
    [self setNeedsLayout];
}

- (void)setTitles:(NSArray *)titles shares:(NSArray *)shares sizes:(NSArray *)sizes colors:(NSArray *)colors checked:(NSArray *)checked
        buttonTitle:(NSString *)buttonTitle buttonSize:(NSString *)buttonSize enabled:(BOOL)enabled {
    for (UIView *row in _rows) [row removeFromSuperview];
    [_rows removeAllObjects];
    [_colors setArray:colors];
    NSUInteger count = MIN(MIN(titles.count, shares.count), MIN(sizes.count, MIN(colors.count, checked.count)));
    for (NSUInteger i = 0; i < count; ++i) {
        ExteriaStorageRow *row = [[[ExteriaStorageRow alloc] init] autorelease];
        row.tag = (NSInteger)i;
        row->title.text = [titles objectAtIndex:i];
        row->share.text = [shares objectAtIndex:i];
        row->size.text = [sizes objectAtIndex:i];
        row->line.hidden = NO;
        [row->dot setColor:[colors objectAtIndex:i] checked:[[checked objectAtIndex:i] boolValue]];
        [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self insertSubview:row belowSubview:_button];
        [_rows addObject:row];
    }
    _buttonTitle.text = buttonTitle;
    [self setButtonSize:buttonSize enabled:enabled];
}

- (void)setChecked:(BOOL)checked atIndex:(NSUInteger)index {
    if (index >= _rows.count) return;
    [((ExteriaStorageRow *)[_rows objectAtIndex:index])->dot setColor:[_colors objectAtIndex:index] checked:checked];
}

- (void)rowTapped:(ExteriaStorageRow *)row {
    if (_toggleHandler) _toggleHandler((NSUInteger)row.tag);
}

- (void)clearTapped {
    if (_enabled && _clearHandler) _clearHandler();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    for (NSUInteger i = 0; i < _rows.count; ++i) {
        ExteriaStorageRow *row = [_rows objectAtIndex:i];
        row.frame = CGRectMake(0, i * ROW_HEIGHT, width, ROW_HEIGHT);
        /* the button stands under the last row, which has no rule of its own */
        row->line.hidden = i + 1 == _rows.count;
    }
    _button.frame = CGRectMake(CARD_PAD, _rows.count * ROW_HEIGHT + CARD_PAD, width - 2 * CARD_PAD, BUTTON_HEIGHT);
    CGFloat titleWidth = [_buttonTitle.text sizeWithFont:_buttonTitle.font].width + 1;
    CGFloat sizeWidth = _buttonSize.text.length ? [_buttonSize.text sizeWithFont:_buttonSize.font].width + 1 : 0;
    CGFloat gap = sizeWidth ? 8 : 0;
    CGFloat left = floor((_button.bounds.size.width - titleWidth - gap - sizeWidth) / 2);
    _buttonTitle.frame = CGRectMake(left, 0, titleWidth, BUTTON_HEIGHT);
    _buttonSize.frame = CGRectMake(left + titleWidth + gap, 0, sizeWidth, BUTTON_HEIGHT);
}

@end
