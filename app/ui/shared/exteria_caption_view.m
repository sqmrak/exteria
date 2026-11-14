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
    self.alwaysBounceVertical = NO;
    self.bounces = NO;
    /* ios 7 and later put 8 points above and below the words and 5 at the sides; the measure and the hint assume the ios 5 and 6 padding (the 6.1 sdk has no declaration, so the setter is reached by key), so the words sat 4 points low in a pill */
    if ([self respondsToSelector:NSSelectorFromString(@"setTextContainerInset:")]) [self setValue:[NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(TOP_PAD, SIDE_PAD - 5, TOP_PAD, SIDE_PAD - 5)] forKey:@"textContainerInset"];
    /* ios 5 and 6 show the correction as a bubble under the word, and a caption stands on the keyboard, so the bubble came out under the keys where it cannot be tapped; ios 7 and later offer it in the bar above the keys */
    BOOL bubbleUnderWord = ![self respondsToSelector:NSSelectorFromString(@"setTextContainerInset:")];
    self.autocorrectionType = bubbleUnderWord ? UITextAutocorrectionTypeNo : UITextAutocorrectionTypeDefault;
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

/* the words of a field that holds them all stand still, and those of a longer one scroll only between their first and last line: a finger on the field dragged a one line caption off
   its pill, half of it out of sight */
- (void)setContentOffset:(CGPoint)offset {
    CGFloat room = self.bounds.size.height - self.contentInset.top - self.contentInset.bottom;
    CGFloat most = MAX(0, self.contentSize.height - room);
    offset.y = most <= 0.5 ? -self.contentInset.top : MAX(-self.contentInset.top, MIN(most - self.contentInset.top, offset.y));
    offset.x = 0;
    [super setContentOffset:offset];
}

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    CGFloat room = self.bounds.size.height - self.contentInset.top - self.contentInset.bottom;
    CGFloat most = MAX(0, self.contentSize.height - room);
    offset.y = most <= 0.5 ? -self.contentInset.top : MAX(-self.contentInset.top, MIN(most - self.contentInset.top, offset.y));
    offset.x = 0;
    [super setContentOffset:offset animated:animated];
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
