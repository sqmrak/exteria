#import "exteria_search_field.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_string_drawing.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

static const CGFloat ExteriaSearchIconWidth = 38.0;

@implementation ExteriaSearchField

+ (ExteriaSearchField *)fieldWithPlaceholder:(NSString *)placeholder height:(CGFloat)height {
    ExteriaSearchField *field = [[[ExteriaSearchField alloc] init] autorelease];
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.backgroundColor = ExteriaColorField();
    field.layer.cornerRadius = height / 2;
    field.placeholder = placeholder;
    field.font = ExteriaFontRegular(16);
    field.textColor = ExteriaColorTitle();
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    UIImageView *glass = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, 16, ExteriaColorMuted())] autorelease];
    glass.contentMode = UIViewContentModeCenter;
    glass.frame = CGRectMake(0, 0, ExteriaSearchIconWidth, height);
    field.leftView = glass;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

- (CGRect)textRectForBounds:(CGRect)bounds {
    return CGRectMake(ExteriaSearchIconWidth, 0, MAX(0, bounds.size.width - ExteriaSearchIconWidth - 30), bounds.size.height);
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
    return [self textRectForBounds:bounds];
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    return [self textRectForBounds:bounds];
}

- (void)drawPlaceholderInRect:(CGRect)rect {
    [ExteriaColorSecondary() set];
    CGFloat height = ceil(self.font.lineHeight);
    rect.origin.y += floor((rect.size.height - height) / 2);
    rect.size.height = height;
    ExteriaDrawStringIn(self.placeholder, self.font, rect, ExteriaStringTailTruncate, ExteriaTextAlignmentLeft);
}

- (CGRect)leftViewRectForBounds:(CGRect)bounds {
    return CGRectMake(0, 0, ExteriaSearchIconWidth, bounds.size.height);
}

- (CGRect)clearButtonRectForBounds:(CGRect)bounds {
    return CGRectMake(bounds.size.width - 30, 0, 30, bounds.size.height);
}

@end

