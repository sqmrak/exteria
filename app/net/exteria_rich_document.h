#import <Foundation/Foundation.h>

#include "exteria_rich.h"

@class ExteriaMedia;

/* one block of an article, as exteria_rich_read laid it out: its words with their entities, or the picture it shows */
@interface ExteriaRichBlock : NSObject {
    exteria_rich_kind _kind;
    uint8_t _level;
    uint8_t _indent;
    uint8_t _quote;
    uint8_t _flags;
    uint16_t _row;
    uint16_t _column;
    uint16_t _colspan;
    uint16_t _rowspan;
    NSString *_label;
    NSString *_text;
    NSArray *_entities;
    ExteriaMedia *_media;
}
@property (nonatomic, readonly) exteria_rich_kind kind;
@property (nonatomic, readonly) uint8_t level;
@property (nonatomic, readonly) uint8_t indent;
@property (nonatomic, readonly) uint8_t quote;
@property (nonatomic, readonly) uint8_t flags;
@property (nonatomic, readonly) uint16_t row;
@property (nonatomic, readonly) uint16_t column;
@property (nonatomic, readonly) uint16_t colspan;
@property (nonatomic, readonly) uint16_t rowspan;
@property (nonatomic, readonly) NSString *label;
@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) NSArray *entities;
@property (nonatomic, readonly) ExteriaMedia *media;
@end

/* the article of a message (its rich_message), read once on the worker that parsed the answer */
@interface ExteriaRichDocument : NSObject {
    NSArray *_blocks;
    BOOL _rtl;
    BOOL _truncated;
}
/* nil when the message has no article, or none of its blocks can be shown */
+ (ExteriaRichDocument *)documentOfMessage:(const exteria_tl_value *)message;
@property (nonatomic, readonly) NSArray *blocks;
@property (nonatomic, readonly) BOOL rtl;
/* the article was longer than the bounds of the reader, and its end is not shown */
@property (nonatomic, readonly) BOOL truncated;
@end
