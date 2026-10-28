#import "exteria_emoji_label.h"

#import "exteria_emoji_store.h"
#import "exteria_text_layout.h"
#import "exteria_theme.h"

@interface ExteriaEmojiLabel () {
    ExteriaTextLayout *_layout;
    CGFloat _layoutWidth;
    BOOL _dropsUndrawable;
}
@end

@implementation ExteriaEmojiLabel

@synthesize text = _text;
@synthesize font = _font;
@synthesize textColor = _textColor;
@synthesize textAlignment = _textAlignment;
@synthesize numberOfLines = _numberOfLines;
@synthesize shadowOffset = _shadowOffset;
@synthesize dropsUndrawable = _dropsUndrawable;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
    _text = [@"" copy];
    _font = [ExteriaFontRegular(16) retain];
    _textColor = [[UIColor blackColor] retain];
    _numberOfLines = 1;
    return self;
}

- (void)dealloc {
    [_text release];
    [_font release];
    [_textColor release];
    [_linkColor release];
    [_entities release];
    [_shadowColor release];
    [_prefixColor release];
    [_layout release];
    [super dealloc];
}

- (void)invalidate {
    [_layout release];
    _layout = nil;
    [self setNeedsDisplay];
}

- (void)setText:(NSString *)text {
    if (text == _text || [text isEqualToString:_text]) return;
    [_text release];
    _text = [(text ? text : @"") copy];
    [self invalidate];
}

- (void)setFont:(UIFont *)font {
    if (font == _font) return;
    [_font release];
    _font = [font retain];
    [self invalidate];
}

- (void)setTextColor:(UIColor *)color {
    if (color == _textColor) return;
    [_textColor release];
    _textColor = [color retain];
    [self invalidate];
}

- (UIColor *)linkColor { return _linkColor; }
- (void)setLinkColor:(UIColor *)color {
    if (color == _linkColor) return;
    [_linkColor release];
    _linkColor = [color retain];
    [self invalidate];
}

- (void)setTextAlignment:(NSInteger)alignment {
    if (alignment == _textAlignment) return;
    _textAlignment = alignment;
    [self invalidate];
}

- (void)setEntities:(NSArray *)entities {
    if (entities == _entities) return;
    [_entities release];
    _entities = [entities retain];
    [self invalidate];
}

- (UIColor *)shadowColor {
    return _shadowColor;
}

- (void)setShadowColor:(UIColor *)color {
    if (color == _shadowColor) return;
    [_shadowColor release];
    _shadowColor = [color retain];
    [self setNeedsDisplay];
}

- (void)setShadowOffset:(CGSize)offset {
    _shadowOffset = offset;
    [self setNeedsDisplay];
}

- (void)setPrefixLength:(NSUInteger)length color:(UIColor *)color {
    if (length == _prefixLength && (length == 0 || color == _prefixColor)) return;
    _prefixLength = color ? length : 0;
    [_prefixColor release];
    _prefixColor = _prefixLength ? [color retain] : nil;
    [self invalidate];
}

- (void)setNumberOfLines:(NSInteger)lines {
    if (lines == _numberOfLines) return;
    _numberOfLines = lines;
    [self invalidate];
}

/* a list row that scrolls back into view asks for the layout it had a moment ago, and typesetting it again is the
   main thread's share of a scroll */
static NSCache *ExteriaLabelLayoutCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 200;
    });
    return cache;
}

- (ExteriaTextLayout *)layoutForWidth:(CGFloat)width {
    if (_layout && width == _layoutWidth) return _layout;
    /* a left aligned text that already fits the new width breaks at the same places as it did at the wider one,
       and a cell measures a title at its maximum width and then draws it at its own */
    if (_layout && _textAlignment == ExteriaTextAlignmentLeft && width >= _layout.size.width && width <= _layoutWidth) return _layout;
    NSMutableString *custom = [NSMutableString string];
    for (ExteriaTextEntity *entity in _entities) [custom appendFormat:@"%ld:%lld:%lu:%lu:%@;", (long)entity.style, entity.documentId, (unsigned long)entity.range.location, (unsigned long)entity.range.length, entity.url];
    NSMutableString *key = [NSMutableString stringWithFormat:@"%.2f|%ld|%ld|%d|%@ %.2f|%@|%@|%@|%lu %@", width, (long)_textAlignment, (long)_numberOfLines, _dropsUndrawable,
                     _font.fontName, _font.pointSize, _textColor, custom, _text, (unsigned long)_prefixLength, _prefixColor];
    [key appendFormat:@"|%@", _linkColor];
    ExteriaTextLayout *layout = [ExteriaLabelLayoutCache() objectForKey:key];
    if (!layout) {
        CGFloat flush = _textAlignment == ExteriaTextAlignmentCenter ? 0.5 : (_textAlignment == ExteriaTextAlignmentRight ? 1.0 : 0.0);
        NSArray *entities = _entities;
        if (_prefixLength && _prefixLength <= _text.length) {
            /* the layout colors a link run with its link color and the label has no taps, so a link run over the prefix is a colored span */
            ExteriaTextEntity *span = [[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleLink range:NSMakeRange(0, _prefixLength) url:@""] autorelease];
            entities = [NSArray arrayWithObject:span];
            if (_entities.count) entities = [entities arrayByAddingObjectsFromArray:_entities];
        }
        layout = [ExteriaTextLayout layoutForText:_text entities:entities font:_font color:_textColor linkColor:_prefixLength ? _prefixColor : (_linkColor ? _linkColor : _textColor) width:MAX(1, width)
                                         maxLines:(NSUInteger)(_numberOfLines > 0 ? _numberOfLines : 0) flush:flush dropsUndrawable:_dropsUndrawable];
        [ExteriaLabelLayoutCache() setObject:layout forKey:key];
    }
    [layout retain];
    [_layout release];
    _layout = layout;
    _layoutWidth = width;
    return _layout;
}

- (NSString *)linkAtPoint:(CGPoint)point {
    ExteriaTextLayout *layout = [self layoutForWidth:self.bounds.size.width];
    point.y -= floor((self.bounds.size.height - layout.size.height) / 2);
    return [layout linkAtPoint:point];
}

- (long long)customEmojiAtPoint:(CGPoint)point {
    ExteriaTextLayout *layout = [self layoutForWidth:self.bounds.size.width];
    point.y -= floor((self.bounds.size.height - layout.size.height) / 2);
    return [layout customEmojiAtPoint:point];
}

- (CGRect)customEmojiRect:(long long)document {
    ExteriaTextLayout *layout = [self layoutForWidth:self.bounds.size.width];
    CGRect rect = [layout rectOfCustomEmoji:document];
    if (CGRectIsNull(rect)) return rect;
    rect.origin.y += floor((self.bounds.size.height - layout.size.height) / 2);
    return rect;
}

- (CGSize)sizeThatFits:(CGSize)size {
    ExteriaTextLayout *layout = [self layoutForWidth:size.width];
    return CGSizeMake(MIN(size.width, layout.size.width), layout.size.height);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_text.length) return;
    ExteriaTextLayout *layout = [self layoutForWidth:self.bounds.size.width];
    NSUInteger misses = ExteriaEmojiMissCount();
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    if (_shadowColor) CGContextSetShadowWithColor(context, _shadowOffset, 0, _shadowColor.CGColor);
    /* the text sits on the vertical middle, as a label's does */
    [layout drawAtPoint:CGPointMake(0, floor((self.bounds.size.height - layout.size.height) / 2))];
    CGContextRestoreGState(context);
    if (ExteriaEmojiMissCount() != misses) ExteriaEmojiRedrawWhenLoaded(self);
}

@end
