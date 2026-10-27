#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>

#import "exteria_message.h"

/* what a tap on a covered spoiler answers in place of an address */
extern NSString *const ExteriaSpoilerTarget;

/* text laid out with CoreText: styles, links, and every emoji set in the lines as a picture of the app's one set;
   a layout can be limited to a few lines */
@interface ExteriaTextLayout : NSObject {
    NSAttributedString *_string;
    CTLineRef *_lines;
    CGPoint *_origins;
    CGFloat *_ascents;
    CGFloat *_descents;
    NSUInteger _lineCount;
    CGSize _size;
    CGFloat _lastLineWidth;
    BOOL *_quoted;
    CGFloat _width;
    UIColor *_ink;
    BOOL _hasSpoilers;
    BOOL _spoilersRevealed;
}

/* entities may be nil. maxLines of zero means no limit. flush is 0 for left aligned text, 0.5 for centered and 1
   for right aligned */
+ (ExteriaTextLayout *)layoutForText:(NSString *)text entities:(NSArray *)entities font:(UIFont *)font
                               color:(UIColor *)color linkColor:(UIColor *)linkColor width:(CGFloat)width
                            maxLines:(NSUInteger)maxLines flush:(CGFloat)flush;

/* one line for a person's name: the same layout, with the invisible marks and the characters no font can draw left out so they never
   show as boxes, and the name cut with an ellipsis at the width */
+ (ExteriaTextLayout *)layoutForName:(NSString *)name font:(UIFont *)font color:(UIColor *)color width:(CGFloat)width;
/* the same, for a name that carries custom emoji entities, such as the badge after the name of a Premium user; the
   characters no font can draw go before the emoji are placed, so the offsets of the entities stay right */
+ (ExteriaTextLayout *)layoutForName:(NSString *)name entities:(NSArray *)entities font:(UIFont *)font color:(UIColor *)color width:(CGFloat)width;

/* layoutForText with the choice of dropping the characters no font can draw, which a name needs and a message must
   not have (its entities count characters) */
+ (ExteriaTextLayout *)layoutForText:(NSString *)text entities:(NSArray *)entities font:(UIFont *)font
                               color:(UIColor *)color linkColor:(UIColor *)linkColor width:(CGFloat)width
                            maxLines:(NSUInteger)maxLines flush:(CGFloat)flush dropsUndrawable:(BOOL)drops;

/* the smallest box the text fits in at the width it was laid out for */
@property (nonatomic, readonly) CGSize size;
/* how far the last line reaches, to tell whether the time can sit beside it */
@property (nonatomic, readonly) CGFloat lastLineWidth;
@property (nonatomic, readonly) NSUInteger lineCount;

/* text under a spoiler is covered until this is set; the cover is drawn, not laid out, so setting it needs only a redraw */
@property (nonatomic, readonly) BOOL hasSpoilers;
@property (nonatomic, assign) BOOL spoilersRevealed;

/* draws with the top left corner of the text box at origin, in the current UIKit context */
- (void)drawAtPoint:(CGPoint)origin;
/* the address of the link under point (relative to the text box), nil when there is none */
- (NSString *)linkAtPoint:(CGPoint)point;
- (long long)customEmojiAtPoint:(CGPoint)point;

@end
