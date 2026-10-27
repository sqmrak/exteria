#import <UIKit/UIKit.h>

/* UILabel shows empty boxes for emoji absent from older systems */
@interface ExteriaEmojiLabel : UIView {
    NSString *_text;
    UIFont *_font;
    UIColor *_textColor;
    NSInteger _textAlignment;
    NSInteger _numberOfLines;
    NSArray *_entities;
    UIColor *_shadowColor;
    CGSize _shadowOffset;
    UIColor *_prefixColor;
    NSUInteger _prefixLength;
}

@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) UIFont *font;
@property (nonatomic, retain) UIColor *textColor;
/* one of the ExteriaTextAlignment values */
@property (nonatomic, assign) NSInteger textAlignment;
@property (nonatomic, assign) NSInteger numberOfLines;
/* ExteriaTextEntity items for the text, such as a custom emoji drawn as its own picture; nil for plain text */
@property (nonatomic, retain) NSArray *entities;
/* the label holds a person's name: characters no font can draw (and that show as boxes, or throw the first emoji after them off its place) are left out */
@property (nonatomic, assign) BOOL dropsUndrawable;
/* the engraved shadow of the old bars, with the meaning UILabel gives it: a nil color draws none, and the offset is in points with y down */
@property (nonatomic, retain) UIColor *shadowColor;
@property (nonatomic, assign) CGSize shadowOffset;

/* the first prefixLength characters are drawn in prefixColor, such as the red "Draft:" before the words of a draft; zero length draws one color */
- (void)setPrefixLength:(NSUInteger)length color:(UIColor *)color;

@end
