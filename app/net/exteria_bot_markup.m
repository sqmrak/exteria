#import "exteria_bot_markup.h"

static NSString *ExteriaUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaMarkupButton

@synthesize row = _row;
@synthesize text = _text;
@synthesize argument = _argument;
@synthesize data = _data;

+ (ExteriaMarkupButton *)buttonWithRow:(const exteria_markup_button *)row markup:(const exteria_markup *)markup {
    ExteriaMarkupButton *button = [[[ExteriaMarkupButton alloc] init] autorelease];
    button->_row = *row;
    button->_text = [ExteriaUtf8(row->text) copy];
    button->_argument = [ExteriaUtf8(exteria_markup_arg(markup, row)) copy];
    if (row->kind == EXTERIA_BUTTON_CALLBACK) button->_data = [[NSData alloc] initWithBytes:row->data length:row->data_len];
    return button;
}

- (void)dealloc {
    [_text release];
    [_argument release];
    [_data release];
    [super dealloc];
}

- (exteria_button_kind)kind { return (exteria_button_kind)_row.kind; }
- (exteria_button_style)style { return (exteria_button_style)_row.style; }
- (BOOL)enabled { return _row.kind != EXTERIA_BUTTON_DISABLED; }

@end

@implementation ExteriaMarkup

@synthesize kind = _kind;
@synthesize resize = _resize;
@synthesize singleUse = _singleUse;
@synthesize persistent = _persistent;
@synthesize selective = _selective;
@synthesize placeholder = _placeholder;
@synthesize rows = _rows;
@synthesize buttonCount = _buttonCount;

+ (ExteriaMarkup *)markupWithValue:(const exteria_tl_value *)value {
    if (!value) return nil;
    /* about 22 KB, so it lives on the heap and not on the worker's stack */
    exteria_markup *raw = calloc(1, sizeof(*raw));
    if (!raw) return nil;
    exteria_status status = exteria_markup_read(value, raw);
    if (status != EXTERIA_OK || raw->kind == EXTERIA_MARKUP_NONE) {
        if (status != EXTERIA_OK && status != EXTERIA_E_UNSUPPORTED) NSLog(@"exteria: reply markup rejected: %s", exteria_status_name(status));
        free(raw);
        return nil;
    }
    ExteriaMarkup *markup = [[[ExteriaMarkup alloc] init] autorelease];
    markup->_kind = (exteria_markup_kind)raw->kind;
    markup->_resize = raw->resize;
    markup->_singleUse = raw->single_use;
    markup->_persistent = raw->persistent;
    markup->_selective = raw->selective;
    markup->_placeholder = [ExteriaUtf8(raw->placeholder) copy];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:raw->row_count];
    NSUInteger at = 0;
    for (unsigned r = 0; r < raw->row_count; ++r) {
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:raw->row_size[r]];
        for (unsigned k = 0; k < raw->row_size[r]; ++k) [row addObject:[ExteriaMarkupButton buttonWithRow:&raw->buttons[at++] markup:raw]];
        [rows addObject:row];
    }
    markup->_rows = [rows copy];
    markup->_rowSizes = [[NSData alloc] initWithBytes:raw->row_size length:raw->row_count];
    markup->_buttonCount = at;
    free(raw);
    return markup;
}

- (void)dealloc {
    [_placeholder release];
    [_rows release];
    [_rowSizes release];
    [super dealloc];
}

- (NSData *)framesForWidth:(CGFloat)width rowHeight:(CGFloat)rowHeight gap:(CGFloat)gap height:(CGFloat *)height {
    if (height) *height = 0;
    if (!_buttonCount) return [NSData data];
    exteria_rect *frames = calloc(_buttonCount, sizeof(*frames));
    if (!frames) return nil;
    double total = 0;
    exteria_status status = exteria_markup_layout(_rowSizes.bytes, _rowSizes.length, width, rowHeight, gap, frames, _buttonCount, &total);
    if (status != EXTERIA_OK) {
        free(frames);
        return nil;
    }
    CGRect *rects = calloc(_buttonCount, sizeof(CGRect));
    if (!rects) {
        free(frames);
        return nil;
    }
    for (NSUInteger i = 0; i < _buttonCount; ++i) rects[i] = CGRectMake((CGFloat)frames[i].x, (CGFloat)frames[i].y, (CGFloat)frames[i].width, (CGFloat)frames[i].height);
    free(frames);
    if (height) *height = (CGFloat)total;
    return [NSData dataWithBytesNoCopy:rects length:_buttonCount * sizeof(CGRect) freeWhenDone:YES];
}

- (BOOL)isEqualMarkup:(ExteriaMarkup *)other {
    if (self == other) return YES;
    if (!other || _kind != other->_kind || _buttonCount != other->_buttonCount || ![_rowSizes isEqualToData:other->_rowSizes]) return NO;
    for (NSUInteger r = 0; r < _rows.count; ++r) {
        NSArray *a = [_rows objectAtIndex:r], *b = [other->_rows objectAtIndex:r];
        for (NSUInteger k = 0; k < a.count; ++k) {
            ExteriaMarkupButton *x = [a objectAtIndex:k], *y = [b objectAtIndex:k];
            if (x.kind != y.kind || x.style != y.style || ![x.text isEqualToString:y.text] || ![x.argument isEqualToString:y.argument] ||
                (x.data != y.data && ![x.data isEqualToData:y.data])) return NO;
        }
    }
    return YES;
}

@end
