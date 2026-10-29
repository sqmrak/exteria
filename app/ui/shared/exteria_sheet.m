#import "exteria_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define CARD_RADIUS 14.0
#define ROW_HEIGHT 54.0
#define GAP 8.0
#define SIDE 10.0
#define TEXT_PAD 18.0

@interface ExteriaSheet () {
    UIView *_dim;
    UIView *_stack;
    void (^_handler)(NSUInteger index);
    BOOL _closing;
    CGFloat _bottomInset;
}
@end

@implementation ExteriaSheet

- (void)dealloc {
    [_dim release];
    [_stack release];
    [_handler release];
    [super dealloc];
}

static UIView *ExteriaSheetCard(void) {
    UIView *card = [[[UIView alloc] init] autorelease];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = CARD_RADIUS;
    card.layer.masksToBounds = YES;
    return card;
}

static UILabel *ExteriaSheetLabel(UIFont *font, UIColor *color) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title color:(UIColor *)color font:(UIFont *)font tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    button.titleLabel.font = font;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.tag = tag;
    [button addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return button;
}

- (void)rowDown:(UIButton *)row { row.backgroundColor = ExteriaColorField(); }
- (void)rowUp:(UIButton *)row { row.backgroundColor = [UIColor clearColor]; }

+ (void)presentInView:(UIView *)host title:(NSString *)title message:(NSString *)message options:(NSArray *)options destructive:(NSIndexSet *)destructive
          cancelTitle:(NSString *)cancelTitle handler:(void (^)(NSUInteger))handler {
    ExteriaSheet *sheet = [[[ExteriaSheet alloc] initWithFrame:host.bounds] autorelease];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sheet->_handler = [handler copy];
    /* the sheet is built before it is in the window, so the home indicator is read from the host */
    sheet->_bottomInset = ExteriaSafeInsets(host).bottom;
    [sheet buildWithTitle:title message:message options:options destructive:destructive cancelTitle:cancelTitle];
    [host addSubview:sheet];
    [sheet enter];
}

- (void)buildWithTitle:(NSString *)title message:(NSString *)message options:(NSArray *)options destructive:(NSIndexSet *)destructive cancelTitle:(NSString *)cancelTitle {
    CGSize size = self.bounds.size;
    CGFloat width = MIN(size.width - 2 * SIDE, 420);
    _dim = [[UIView alloc] initWithFrame:self.bounds];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancel)] autorelease]];
    [self addSubview:_dim];

    UIView *card = ExteriaSheetCard();
    CGFloat y = 0;
    CGFloat textWidth = width - 2 * TEXT_PAD;
    if (title.length) {
        UILabel *label = ExteriaSheetLabel(ExteriaFontSemibold(16), ExteriaColorTitle());
        label.text = title;
        CGSize fit = [label sizeThatFits:CGSizeMake(textWidth, 200)];
        label.frame = CGRectMake(TEXT_PAD, y + 16, textWidth, fit.height);
        [card addSubview:label];
        y += 16 + fit.height + (message.length ? 4 : 12);
    }
    if (message.length) {
        UILabel *label = ExteriaSheetLabel(ExteriaFontRegular(14.5), ExteriaColorSecondary());
        label.text = message;
        CGSize fit = [label sizeThatFits:CGSizeMake(textWidth, 300)];
        label.frame = CGRectMake(TEXT_PAD, y + (title.length ? 0 : 16), textWidth, fit.height);
        [card addSubview:label];
        y += (title.length ? 0 : 16) + fit.height + 14;
    }
    CGFloat head = y;
    /* a long list scrolls inside the card, which keeps its room above the cancel card */
    CGFloat cancelHeight = ROW_HEIGHT;
    CGFloat limit = MAX(ROW_HEIGHT * 2, size.height - 120 - cancelHeight - GAP);
    CGFloat rows = ROW_HEIGHT * (CGFloat)options.count;
    CGFloat cardHeight = MIN(head + rows, limit);
    UIScrollView *list = [[[UIScrollView alloc] initWithFrame:CGRectMake(0, head, width, cardHeight - head)] autorelease];
    list.contentSize = CGSizeMake(width, rows);
    list.showsVerticalScrollIndicator = NO;
    list.bounces = rows > list.bounds.size.height;
    for (NSUInteger i = 0; i < options.count; ++i) {
        UIColor *color = [destructive containsIndex:i] ? ExteriaColorBadgeRed() : ExteriaColorTitle();
        UIButton *button = [self buttonWithTitle:[options objectAtIndex:i] color:color font:ExteriaFontMedium(17) tag:(NSInteger)i];
        button.frame = CGRectMake(0, ROW_HEIGHT * (CGFloat)i, width, ROW_HEIGHT);
        [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1.0 / ExteriaScreenScale())] autorelease];
        line.backgroundColor = ExteriaColorHairline();
        [button addSubview:line];
        [list addSubview:button];
    }
    [card addSubview:list];
    card.frame = CGRectMake(0, 0, width, cardHeight);

    UIView *cancel = ExteriaSheetCard();
    cancel.frame = CGRectMake(0, cardHeight + GAP, width, cancelHeight);
    UIButton *cancelButton = [self buttonWithTitle:cancelTitle color:ExteriaColorAccent() font:ExteriaFontSemibold(17) tag:-1];
    cancelButton.frame = cancel.bounds;
    [cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [cancel addSubview:cancelButton];

    CGFloat total = cardHeight + GAP + cancelHeight;
    _stack = [[UIView alloc] initWithFrame:CGRectMake((size.width - width) / 2, size.height - total - MAX(GAP + 4, _bottomInset + GAP), width, total)];
    _stack.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    ExteriaAddDismissPan(_stack, self, @selector(cancel));
    [_stack addSubview:card];
    [_stack addSubview:cancel];
    [self addSubview:_stack];
}

- (void)enter {
    CGFloat shift = _stack.frame.size.height + 40;
    _stack.transform = CGAffineTransformMakeTranslation(0, shift);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0.42, EXTERIA_MOTION_ENTER, nil);
    ExteriaAnimateView(_stack, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, nil);
}

- (void)leaveThen:(void (^)(void))after {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    void (^next)(void) = [after copy];
    [self retain];
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, EXTERIA_MOTION_EXIT, nil);
    ExteriaAnimateView(_stack, CGAffineTransformMakeTranslation(0, _stack.frame.size.height + 40), 1, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (next) next();
        [next release];
        [self release];
    });
}

- (void)cancel {
    [self leaveThen:nil];
}

- (void)picked:(UIButton *)button {
    NSUInteger index = (NSUInteger)button.tag;
    void (^handler)(NSUInteger) = [_handler retain];
    [self leaveThen:^{
        if (handler) handler(index);
        [handler release];
    }];
}

@end

void ExteriaConfirmAction(UIViewController *host, NSString *message, NSString *actionTitle, void (^confirmed)(void)) {
    if (!ExteriaThemeIsClassic() && host.view) {
        [ExteriaSheet presentInView:host.view title:nil message:message options:[NSArray arrayWithObject:actionTitle]
                        destructive:[NSIndexSet indexSetWithIndex:0] cancelTitle:NSLocalizedString(@"picker.cancel", nil)
                            handler:^(NSUInteger index) {
            (void)index;
            if (confirmed) confirmed();
        }];
        return;
    }
    /* the classic style keeps the system alert it always had */
    ExteriaConfirm(nil, message, actionTitle, confirmed);
}
