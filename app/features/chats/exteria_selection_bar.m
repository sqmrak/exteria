#import "exteria_selection_bar.h"

#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define HEIGHT 48.0
#define BUTTON_WIDTH 40.0
#define CANCEL_WIDTH 78.0

@interface ExteriaSelectionBar () {
    UIButton *_cancel;
    UILabel *_count;
    UIButton *_forward;
    UIButton *_copy;
    UIButton *_delete;
    UIButton *_range;
    UIView *_line;
    void (^_cancelHandler)(void);
    void (^_forwardHandler)(void);
    void (^_copyHandler)(void);
    void (^_deleteHandler)(void);
    void (^_rangeHandler)(void);
}
@end

@implementation ExteriaSelectionBar

@synthesize cancelHandler = _cancelHandler;
@synthesize forwardHandler = _forwardHandler;
@synthesize copyHandler = _copyHandler;
@synthesize deleteHandler = _deleteHandler;
@synthesize rangeHandler = _rangeHandler;

+ (CGFloat)height {
    return HEIGHT;
}

- (UIButton *)iconButton:(ExteriaSymbol)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:ExteriaSymbolImage(symbol, 24, ExteriaColorAccent()) forState:UIControlStateNormal];
    [button setImage:ExteriaSymbolImage(symbol, 24, ExteriaColorMuted()) forState:UIControlStateDisabled];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = label;
    [self addSubview:button];
    return button;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorBar();
    _cancel = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_cancel setTitle:NSLocalizedString(@"chat.msg.cancel", nil) forState:UIControlStateNormal];
    [_cancel setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    _cancel.titleLabel.font = ExteriaFontMedium(16);
    [_cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_cancel];
    _count = [[UILabel alloc] init];
    _count.backgroundColor = [UIColor clearColor];
    _count.textColor = ExteriaColorTitle();
    _count.font = ExteriaFontSemibold(15);
    _count.textAlignment = ExteriaTextAlignmentCenter;
    _count.adjustsFontSizeToFitWidth = YES;
    [self addSubview:_count];
    _forward = [[self iconButton:ExteriaSymbolForward label:NSLocalizedString(@"chat.msg.forward", nil) action:@selector(forwardTapped)] retain];
    _copy = [[self iconButton:ExteriaSymbolCopy label:NSLocalizedString(@"chat.msg.copy", nil) action:@selector(copyTapped)] retain];
    _delete = [[self iconButton:ExteriaSymbolTrash label:NSLocalizedString(@"chat.msg.delete", nil) action:@selector(deleteTapped)] retain];
    _range = [[self iconButton:ExteriaSymbolCheckDouble label:NSLocalizedString(@"chat.select.range", nil) action:@selector(rangeTapped)] retain];
    _line = [[UIView alloc] init];
    _line.backgroundColor = ExteriaColorHairline();
    [self addSubview:_line];
    return self;
}

- (void)dealloc {
    [_cancel release];
    [_count release];
    [_forward release];
    [_copy release];
    [_delete release];
    [_range release];
    [_line release];
    [_cancelHandler release];
    [_forwardHandler release];
    [_copyHandler release];
    [_deleteHandler release];
    [_rangeHandler release];
    [super dealloc];
}

- (void)setCount:(NSUInteger)count forward:(BOOL)forward copy:(BOOL)copy delete:(BOOL)delete range:(BOOL)range {
    _count.text = [NSString stringWithFormat:NSLocalizedString(@"chat.select.count", nil), (long)count];
    _forward.enabled = forward;
    _copy.enabled = copy;
    _delete.enabled = delete;
    _range.enabled = range;
}

- (void)cancelTapped { if (_cancelHandler) _cancelHandler(); }
- (void)forwardTapped { if (_forwardHandler) _forwardHandler(); }
- (void)copyTapped { if (_copyHandler) _copyHandler(); }
- (void)deleteTapped { if (_deleteHandler) _deleteHandler(); }
- (void)rangeTapped { if (_rangeHandler) _rangeHandler(); }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    /* the bar may be taller than its content by the bottom safe area, which the buttons stay above */
    CGFloat row = MIN(HEIGHT, size.height);
    _line.frame = CGRectMake(0, 0, size.width, 1.0 / ExteriaScreenScale());
    _cancel.frame = CGRectMake(4, 0, CANCEL_WIDTH, row);
    CGFloat right = size.width - 4;
    _delete.frame = CGRectMake(right - BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    _copy.frame = CGRectMake(right - 2 * BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    _forward.frame = CGRectMake(right - 3 * BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    _range.frame = CGRectMake(right - 4 * BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    CGFloat from = 4 + CANCEL_WIDTH;
    _count.frame = CGRectMake(from, 0, MAX(0, right - 4 * BUTTON_WIDTH - from), row);
}

@end
