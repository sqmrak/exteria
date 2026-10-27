#import "exteria_markup_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_title_button.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define CORNER 8.0
#define MARK_SIDE 14.0
#define FONT_SIZE 14.5

/* a button that draws the small mark in its corner which says what pressing it does */
@interface ExteriaMarkupButtonView : ExteriaEmojiTitleButton {
    exteria_button_kind _mark;
    UIActivityIndicatorView *_spinner;
    NSString *_title;
}
@property (nonatomic, assign) exteria_button_kind mark;
@property (nonatomic, copy) NSString *shownTitle;
- (void)setBusy:(BOOL)busy;
@end

@implementation ExteriaMarkupButtonView

@synthesize mark = _mark;
@synthesize shownTitle = _title;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    self.layer.cornerRadius = CORNER;
    self.clipsToBounds = YES;
    return self;
}

- (void)dealloc {
    [_spinner release];
    [_title release];
    [super dealloc];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)setBusy:(BOOL)busy {
    if (busy && !_spinner) {
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        [self addSubview:_spinner];
    }
    if (busy) {
        _spinner.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
        [_spinner startAnimating];
        [self setFaceHidden:YES];
    } else {
        [_spinner stopAnimating];
        [self setFaceText:_title font:ExteriaFontMedium(FONT_SIZE) color:[UIColor whiteColor]];
        [self setFaceHidden:NO];
    }
}

/* a press darkens the button, drawn over the fill the layer has */
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    if (self.highlighted) {
        CGContextSetRGBFillColor(context, 0, 0, 0, 0.25);
        CGContextFillRect(context, bounds);
    }
    ExteriaSymbol mark;
    switch (_mark) {
    case EXTERIA_BUTTON_URL:
    case EXTERIA_BUTTON_URL_AUTH:
    case EXTERIA_BUTTON_SWITCH_INLINE:
        mark = ExteriaSymbolExternalLink;
        break;
    case EXTERIA_BUTTON_COPY:
        mark = ExteriaSymbolCopy;
        break;
    default:
        return;
    }
    UIImage *image = ExteriaSymbolImage(mark, MARK_SIDE, [UIColor whiteColor]);
    [image drawAtPoint:CGPointMake(bounds.size.width - MARK_SIDE - 3, 2) blendMode:kCGBlendModeNormal alpha:0.85];
}

@end

@implementation ExteriaMarkupView

@synthesize pressHandler = _pressHandler;
@synthesize markup = _markup;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _buttons = [[NSMutableArray alloc] init];
    _busy = -1;
    return self;
}

- (void)dealloc {
    [_markup release];
    [_buttons release];
    [_frames release];
    [_pressHandler release];
    [super dealloc];
}

static UIColor *ExteriaMarkupFill(ExteriaMarkupButton *button) {
    switch (button.style) {
    case EXTERIA_BUTTON_STYLE_PRIMARY: return ExteriaColorAccent();
    case EXTERIA_BUTTON_STYLE_DANGER: return [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:0.9];
    case EXTERIA_BUTTON_STYLE_SUCCESS: return [UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:0.9];
    case EXTERIA_BUTTON_STYLE_PLAIN: break;
    }
    return ExteriaColorBubbleCapsule();
}

- (void)setMarkup:(ExteriaMarkup *)markup frames:(NSData *)frames {
    [_markup release];
    _markup = [markup retain];
    [_frames release];
    _frames = [frames retain];
    _busy = -1;
    NSUInteger index = 0;
    const CGRect *rects = frames.bytes;
    for (NSArray *row in markup.rows) {
        for (ExteriaMarkupButton *button in row) {
            if (index * sizeof(CGRect) >= frames.length) break;
            ExteriaMarkupButtonView *view;
            if (index < _buttons.count) {
                view = [_buttons objectAtIndex:index];
            } else {
                view = [[[ExteriaMarkupButtonView alloc] initWithFrame:CGRectZero] autorelease];
                view.backgroundColor = ExteriaColorBubbleCapsule();
                [view addTarget:self action:@selector(pressed:) forControlEvents:UIControlEventTouchUpInside];
                [self addSubview:view];
                [_buttons addObject:view];
            }
            view.tag = (NSInteger)index;
            view.hidden = NO;
            view.frame = rects[index];
            view.backgroundColor = ExteriaMarkupFill(button);
            view.mark = button.kind;
            view.shownTitle = button.text;
            [view setBusy:NO];
            view.enabled = button.enabled;
            view.alpha = button.enabled ? 1 : 0.5;
            view.accessibilityLabel = button.text;
            [view setNeedsDisplay];
            ++index;
        }
    }
    for (NSUInteger i = index; i < _buttons.count; ++i) [[_buttons objectAtIndex:i] setHidden:YES];
}

- (ExteriaMarkupButton *)buttonAtIndex:(NSInteger)index {
    NSInteger at = 0;
    for (NSArray *row in _markup.rows) {
        for (ExteriaMarkupButton *button in row) if (at++ == index) return button;
    }
    return nil;
}

- (void)pressed:(UIButton *)view {
    ExteriaMarkupButton *button = [self buttonAtIndex:view.tag];
    if (!button || !button.enabled) return;
    /* the handler may reload the row and with it this view's buttons, so the button object is held across the call */
    [button retain];
    void (^handler)(ExteriaMarkupButton *) = [_pressHandler copy];
    if (handler) handler(button);
    [handler release];
    [button release];
}

- (void)setBusyButton:(ExteriaMarkupButton *)button {
    NSInteger index = -1, at = 0;
    for (NSArray *row in _markup.rows) {
        for (ExteriaMarkupButton *one in row) {
            if (one == button) index = at;
            ++at;
        }
    }
    if (_busy >= 0 && _busy < (NSInteger)_buttons.count) [[_buttons objectAtIndex:(NSUInteger)_busy] setBusy:NO];
    _busy = index;
    if (index >= 0 && index < (NSInteger)_buttons.count) [[_buttons objectAtIndex:(NSUInteger)index] setBusy:YES];
}

@end
