#import "exteria_caption_view.h"

/* what UITextView keeps around its words before ios 7: the same in every direction it is asked in */
#define SIDE_PAD 8.0
#define TOP_PAD 4.0

@implementation ExteriaCaptionView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentInset = UIEdgeInsetsZero;
    self.showsHorizontalScrollIndicator = NO;
    self.alwaysBounceHorizontal = NO;
    self.autocorrectionType = UITextAutocorrectionTypeDefault;
    _hint = [[UILabel alloc] init];
    _hint.backgroundColor = [UIColor clearColor];
    _hint.userInteractionEnabled = NO;
    [self addSubview:_hint];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textChanged) name:UITextViewTextDidChangeNotification object:self];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_hint release];
    [_placeholder release];
    [super dealloc];
}

- (void)setPlaceholder:(NSString *)placeholder {
    [_placeholder release];
    _placeholder = [placeholder copy];
    _hint.text = _placeholder;
    self.accessibilityLabel = _placeholder;
    [self setNeedsLayout];
}

- (void)setText:(NSString *)text {
    [super setText:text];
    [self textChanged];
}

- (void)setFont:(UIFont *)font {
    [super setFont:font];
    _hint.font = font;
    [self setNeedsLayout];
}

- (void)textChanged {
    _hint.hidden = self.text.length > 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _hint.textColor = [self.textColor colorWithAlphaComponent:0.45f];
    CGFloat line = ceil(self.font.lineHeight);
    _hint.textAlignment = self.textAlignment;
    _hint.frame = CGRectMake(SIDE_PAD + 1, TOP_PAD + 1, MAX(0, self.bounds.size.width - 2 * SIDE_PAD), line);
}

- (CGFloat)contentHeightForWidth:(CGFloat)width {
    CGFloat line = ceil(self.font.lineHeight);
    NSString *text = self.text.length ? self.text : @" ";
    /* a trailing line break takes a line of its own that the measure of the words alone would drop */
    if ([text hasSuffix:@"\n"]) text = [text stringByAppendingString:@" "];
    CGSize room = [text sizeWithFont:self.font constrainedToSize:CGSizeMake(MAX(20, width - 2 * SIDE_PAD - 2), 10000) lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(line, ceil(room.height)) + 2 * TOP_PAD;
}

@end
