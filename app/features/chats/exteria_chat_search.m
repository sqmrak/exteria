#import "exteria_chat_search.h"

#import "exteria_platform.h"
#import "exteria_search_field.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define BAR_SIDE 8.0
#define BAR_FIELD_HEIGHT 36.0
#define CANCEL_WIDTH 84.0

@implementation ExteriaChatSearchBar

@synthesize changeHandler = _changeHandler;
@synthesize cancelHandler = _cancelHandler;
@synthesize field = _field;

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = ExteriaColorBar();
        _field = [[ExteriaSearchField fieldWithPlaceholder:NSLocalizedString(@"chat.search.field", nil) height:BAR_FIELD_HEIGHT] retain];
        _field.delegate = self;
        _field.returnKeyType = UIReturnKeySearch;
        _field.enablesReturnKeyAutomatically = YES;
        [_field addTarget:self action:@selector(edited) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_field];
        _cancel = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_cancel setTitle:NSLocalizedString(@"picker.cancel", nil) forState:UIControlStateNormal];
        [_cancel setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        _cancel.titleLabel.font = ExteriaFontRegular(17);
        [_cancel addTarget:self action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_cancel];
    }
    return self;
}

- (void)dealloc {
    _field.delegate = nil;
    [_field release];
    [_cancel release];
    [_changeHandler release];
    [_cancelHandler release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _cancel.frame = CGRectMake(width - CANCEL_WIDTH - BAR_SIDE + 8, height - EXTERIA_CHAT_SEARCH_BAR_HEIGHT, CANCEL_WIDTH, EXTERIA_CHAT_SEARCH_BAR_HEIGHT);
    CGFloat fieldTop = height - EXTERIA_CHAT_SEARCH_BAR_HEIGHT + (EXTERIA_CHAT_SEARCH_BAR_HEIGHT - BAR_FIELD_HEIGHT) / 2;
    _field.frame = CGRectMake(BAR_SIDE + 4, fieldTop, MAX(0, width - CANCEL_WIDTH - 2 * BAR_SIDE - 4 + 8), BAR_FIELD_HEIGHT);
}

- (void)edited {
    if (_changeHandler) _changeHandler(_field.text);
}

- (void)cancelPressed {
    if (_cancelHandler) _cancelHandler();
}

/* the key only puts the keyboard away, so the strip and the matches stay in view */
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    field.text = @"";
    [self edited];
    return NO;
}

@end

@implementation ExteriaChatSearchNav

@synthesize olderHandler = _olderHandler;
@synthesize newerHandler = _newerHandler;

static UIButton *ExteriaNavButton(id target, SEL action, BOOL flipped) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:ExteriaSymbolImage(ExteriaSymbolArrowDown, 22, ExteriaColorAccent()) forState:UIControlStateNormal];
    [button setImage:ExteriaSymbolImage(ExteriaSymbolArrowDown, 22, ExteriaColorMuted()) forState:UIControlStateDisabled];
    /* the arrow that points up is the one that points down, turned over */
    if (flipped) button.transform = CGAffineTransformMakeRotation((CGFloat)M_PI);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = ExteriaColorBar();
        _line = [[UIView alloc] init];
        _line.backgroundColor = ExteriaColorHairline();
        [self addSubview:_line];
        _count = [[UILabel alloc] init];
        _count.backgroundColor = [UIColor clearColor];
        _count.font = ExteriaFontRegular(15);
        _count.textColor = ExteriaColorSecondary();
        [self addSubview:_count];
        _older = [ExteriaNavButton(self, @selector(olderPressed), YES) retain];
        _newer = [ExteriaNavButton(self, @selector(newerPressed), NO) retain];
        [self addSubview:_older];
        [self addSubview:_newer];
        [self showIdle];
    }
    return self;
}

- (void)dealloc {
    [_count release];
    [_older release];
    [_newer release];
    [_line release];
    [_olderHandler release];
    [_newerHandler release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _line.frame = CGRectMake(0, 0, width, 1.0 / ExteriaScreenScale());
    /* the buttons stand in the 48 points above the bottom inset, which the strip may extend under */
    CGFloat top = 0, side = EXTERIA_CHAT_SEARCH_NAV_HEIGHT;
    _newer.frame = CGRectMake(width - side - 4, top, side, side);
    _older.frame = CGRectMake(width - 2 * side - 4, top, side, side);
    _count.frame = CGRectMake(16, top, MAX(0, width - 2 * side - 24), side);
}

- (void)olderPressed { if (_olderHandler) _olderHandler(); }
- (void)newerPressed { if (_newerHandler) _newerHandler(); }

- (void)setSteps:(BOOL)enabledOlder newer:(BOOL)enabledNewer {
    _older.enabled = enabledOlder;
    _newer.enabled = enabledNewer;
}

- (void)showIdle {
    _count.text = @"";
    [self setSteps:NO newer:NO];
}

- (void)showSearching {
    _count.text = NSLocalizedString(@"chat.search.searching", nil);
    [self setSteps:NO newer:NO];
}

- (void)showNone {
    _count.text = NSLocalizedString(@"chat.search.none", nil);
    [self setSteps:NO newer:NO];
}

/* position counts from the newest match, which is the first one shown; the arrow that points up goes to an older one */
- (void)showPosition:(NSUInteger)position of:(NSUInteger)total {
    _count.text = [NSString stringWithFormat:NSLocalizedString(@"chat.search.position", nil), (unsigned long)position, (unsigned long)total];
    [self setSteps:position < total newer:position > 1];
}

@end
