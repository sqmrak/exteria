#import <Foundation/Foundation.h>

/* one message of a long text: the words and the styled runs that fall inside them, counted from the start of the piece */
@interface ExteriaTextPart : NSObject {
    NSString *_text;
    NSArray *_entities;
}
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSArray *entities;
@end

/* cuts a text the server would refuse for its length into the messages that carry it, by the rules of core/layout/exteria_text_split.c. a text within the limit
   comes back as one part with the same words, trimmed. a styled run that crosses a cut is shortened to each side; a custom emoji or a mention that a cut would
   split is dropped, since half of one means nothing. limit is 4096 units, 8192 for a Premium account */
NSArray *ExteriaTextPartsForLimit(NSString *text, NSArray *entities, NSUInteger limit);
