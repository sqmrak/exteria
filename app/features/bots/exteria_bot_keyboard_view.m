#import "exteria_bot_keyboard_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_title_button.h"
#import "exteria_theme.h"

#define KEY_HEIGHT 42.0
#define KEY_GAP 6.0
#define KEY_INSET 6.0

@implementation ExteriaBotKeyboardView

@synthesize pressHandler = _pressHandler;
@synthesize markup = _markup;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorBar();
    _scroll = [[UIScrollView alloc] init];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = NO;
    [self addSubview:_scroll];
    _keys = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_markup release];
    [_scroll release];
    [_keys release];
    [_pressHandler release];
    [super dealloc];
}

- (void)setMarkup:(ExteriaMarkup *)markup {
    [_markup release];
    _markup = [markup retain];
    for (UIView *key in _keys) [key removeFromSuperview];
    [_keys removeAllObjects];
    for (NSArray *row in markup.rows) {
        for (ExteriaMarkupButton *button in row) {
            ExteriaEmojiTitleButton *key = [[[ExteriaEmojiTitleButton alloc] initWithFrame:CGRectZero] autorelease];
            key.backgroundColor = ExteriaColorCard();
            key.layer.cornerRadius = 8;
            [key setFaceText:button.text font:ExteriaFontRegular(16) color:ExteriaColorTitle()];
            key.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
            key.enabled = button.enabled;
            key.alpha = button.enabled ? 1 : 0.5;
            key.tag = (NSInteger)_keys.count;
            [key addTarget:self action:@selector(pressed:) forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:key];
            [_keys addObject:key];
        }
    }
    [self setNeedsLayout];
}

- (CGFloat)contentHeightForWidth:(CGFloat)width {
    (void)width;
    NSUInteger rows = _markup.rows.count;
    return rows ? KEY_INSET * 2 + rows * KEY_HEIGHT + (rows - 1) * KEY_GAP : 0;
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight {
    if (!_markup.resize) return maxHeight;
    return MIN(maxHeight, [self contentHeightForWidth:width]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width - 2 * KEY_INSET;
    _scroll.frame = self.bounds;
    CGFloat contentHeight = [self contentHeightForWidth:self.bounds.size.width];
    /* a keyboard that does not resize and has fewer rows than room spreads them over the whole height */
    CGFloat rowHeight = KEY_HEIGHT, gap = KEY_GAP;
    NSUInteger rows = _markup.rows.count;
    if (!_markup.resize && rows && contentHeight < self.bounds.size.height) {
        rowHeight = (self.bounds.size.height - 2 * KEY_INSET - (rows - 1) * KEY_GAP) / rows;
        contentHeight = self.bounds.size.height;
    }
    CGFloat height = 0;
    NSData *data = [_markup framesForWidth:width rowHeight:rowHeight gap:gap height:&height];
    const CGRect *frames = data.bytes;
    for (NSUInteger i = 0; i < _keys.count && (i + 1) * sizeof(CGRect) <= data.length; ++i) {
        [[_keys objectAtIndex:i] setFrame:CGRectOffset(frames[i], KEY_INSET, KEY_INSET)];
    }
    _scroll.contentSize = CGSizeMake(self.bounds.size.width, contentHeight);
}

- (void)pressed:(UIButton *)key {
    NSInteger at = 0;
    for (NSArray *row in _markup.rows) {
        for (ExteriaMarkupButton *button in row) {
            if (at++ != key.tag) continue;
            [button retain];
            void (^handler)(ExteriaMarkupButton *) = [_pressHandler copy];
            if (handler) handler(button);
            [handler release];
            [button release];
            return;
        }
    }
}

@end
