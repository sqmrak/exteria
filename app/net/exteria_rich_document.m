#import "exteria_rich_document.h"

#import "exteria_message.h"

@implementation ExteriaRichBlock

@synthesize kind = _kind;
@synthesize level = _level;
@synthesize indent = _indent;
@synthesize quote = _quote;
@synthesize flags = _flags;
@synthesize row = _row;
@synthesize column = _column;
@synthesize colspan = _colspan;
@synthesize rowspan = _rowspan;
@synthesize label = _label;
@synthesize text = _text;
@synthesize entities = _entities;
@synthesize media = _media;

- (id)initWithBlock:(const exteria_rich_block *)block doc:(const exteria_rich_doc *)doc {
    self = [super init];
    if (!self) return nil;
    _kind = (exteria_rich_kind)block->kind;
    _level = block->level;
    _indent = block->indent;
    _quote = block->quote;
    _flags = block->flags;
    _row = block->row;
    _column = block->column;
    _colspan = block->colspan;
    _rowspan = block->rowspan;
    _label = [[NSString alloc] initWithUTF8String:block->label];
    /* the core wrote valid UTF-8, so the string has the UTF-16 units the entity offsets count */
    _text = [[NSString alloc] initWithBytes:doc->text + block->text_offset length:block->text_length encoding:NSUTF8StringEncoding];
    if (!_text || !_label) {
        [self release];
        return nil;
    }
    _entities = [ExteriaTextEntities(_text, doc->entities + block->entity_start, block->entity_count, doc->urls) retain];
    if (_kind == EXTERIA_RICH_MEDIA && block->media < doc->media_count) _media = [[ExteriaMedia mediaWithInfo:&doc->media[block->media]] retain];
    return self;
}

- (void)dealloc {
    [_label release];
    [_text release];
    [_entities release];
    [_media release];
    [super dealloc];
}

@end

@implementation ExteriaRichDocument

@synthesize blocks = _blocks;
@synthesize rtl = _rtl;
@synthesize truncated = _truncated;

+ (ExteriaRichDocument *)documentOfMessage:(const exteria_tl_value *)message {
    if (!message || !exteria_tl_get(message, "rich_message")) return nil;
    /* a few hundred kilobytes at most, so it lives on the heap and only while it is read */
    exteria_rich_doc *doc = calloc(1, sizeof(*doc));
    if (!doc) return nil;
    exteria_status status = exteria_rich_read(message, doc);
    if (status != EXTERIA_OK) {
        if (status != EXTERIA_E_NOTFOUND) NSLog(@"exteria: article not shown: %s", exteria_status_name(status));
        free(doc);
        return nil;
    }
    NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:doc->block_count];
    for (uint16_t i = 0; i < doc->block_count; ++i) {
        ExteriaRichBlock *block = [[ExteriaRichBlock alloc] initWithBlock:&doc->blocks[i] doc:doc];
        if (block) [blocks addObject:block];
        [block release];
    }
    ExteriaRichDocument *document = nil;
    if (blocks.count) {
        document = [[[ExteriaRichDocument alloc] init] autorelease];
        document->_blocks = [blocks copy];
        document->_rtl = doc->rtl != 0;
        document->_truncated = doc->truncated != 0;
        if (doc->truncated) NSLog(@"exteria: article cut at %u blocks, %u bytes of text", (unsigned)doc->block_count, (unsigned)doc->text_length);
    }
    free(doc);
    return document;
}

- (void)dealloc {
    [_blocks release];
    [super dealloc];
}

@end
