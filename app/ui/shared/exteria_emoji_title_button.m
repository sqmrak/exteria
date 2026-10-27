#import "exteria_emoji_title_button.h"

#import "exteria_theme.h"

@implementation ExteriaEmojiTitleButton

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _face = [[ExteriaEmojiLabel alloc] init];
    _face.textAlignment = ExteriaTextAlignmentCenter;
    [self addSubview:_face];
    return self;
}

- (void)dealloc {
    [_face release];
    [super dealloc];
}

- (void)setFaceText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    _face.text = text;
    _face.font = font;
    _face.textColor = color;
    self.accessibilityLabel = text;
    [self setNeedsLayout];
}

- (void)setFaceHidden:(BOOL)hidden {
    _face.hidden = hidden;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _face.frame = UIEdgeInsetsInsetRect(self.bounds, self.contentEdgeInsets);
    [self bringSubviewToFront:_face];
}

@end
