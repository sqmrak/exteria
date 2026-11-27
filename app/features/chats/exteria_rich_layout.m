#import "exteria_rich_layout.h"

#import "exteria_message.h"
#import "exteria_platform.h"
#import "exteria_rich_document.h"
#import "exteria_symbol.h"
#import "exteria_text_layout.h"
#import "exteria_theme.h"

#define RICH_GAP 8.0
#define RICH_GAP_HEADING 12.0
#define RICH_GAP_TIGHT 4.0
#define RICH_INDENT 16.0
#define RICH_QUOTE_INDENT 12.0
#define RICH_LABEL_GAP 6.0
#define RICH_MEDIA_HEIGHT_MAX 360.0
#define RICH_MEDIA_HEIGHT_MIN 60.0
#define RICH_MEDIA_RADIUS 8.0
#define RICH_CELL_PAD 6.0
#define RICH_DIVIDER_HEIGHT 9.0
/* a spoiler picture is drawn from a copy this many pixels wide, scaled back up, so its shapes show and its content does not */
#define RICH_SPOILER_PIXELS 12.0

typedef enum {
    ExteriaRichPieceText,
    ExteriaRichPieceFill,
    ExteriaRichPieceStroke,
    ExteriaRichPieceMedia
} ExteriaRichPieceKind;

@interface ExteriaRichPiece : NSObject {
@public
    ExteriaRichPieceKind kind;
    CGRect frame;
    ExteriaTextLayout *layout;
    UIColor *color;
    NSUInteger media;
    CGFloat radius;
}
@end

@implementation ExteriaRichPiece
- (void)dealloc {
    [layout release];
    [color release];
    [super dealloc];
}
@end

@implementation ExteriaRichLayout

@synthesize size = _size;
@synthesize trailingLineWidth = _trailingLineWidth;
@synthesize spoilersRevealed = _spoilersRevealed;

- (ExteriaRichPiece *)addPiece:(ExteriaRichPieceKind)kind frame:(CGRect)frame {
    ExteriaRichPiece *piece = [[[ExteriaRichPiece alloc] init] autorelease];
    piece->kind = kind;
    piece->frame = frame;
    [_pieces addObject:piece];
    return piece;
}

- (void)addFill:(CGRect)frame color:(UIColor *)color radius:(CGFloat)radius {
    ExteriaRichPiece *piece = [self addPiece:ExteriaRichPieceFill frame:frame];
    piece->color = [color retain];
    piece->radius = radius;
}

- (void)addStroke:(CGRect)frame color:(UIColor *)color {
    ExteriaRichPiece *piece = [self addPiece:ExteriaRichPieceStroke frame:frame];
    piece->color = [color retain];
}

- (ExteriaTextLayout *)addText:(ExteriaTextLayout *)layout at:(CGPoint)origin {
    ExteriaRichPiece *piece = [self addPiece:ExteriaRichPieceText frame:CGRectMake(origin.x, origin.y, layout.size.width, layout.size.height)];
    piece->layout = [layout retain];
    layout.spoilersRevealed = _spoilersRevealed;
    return layout;
}

static UIFont *ExteriaRichFont(ExteriaRichBlock *block, CGFloat textSize) {
    switch (block.kind) {
    case EXTERIA_RICH_HEADING:
        switch (block.level) {
        case 1: return ExteriaFontBold(textSize + 7);
        case 2: return ExteriaFontBold(textSize + 4);
        case 3: return ExteriaFontSemibold(textSize + 2);
        default: return ExteriaFontSemibold(textSize);
        }
    case EXTERIA_RICH_SUBTITLE: return ExteriaFontMedium(textSize - 1);
    case EXTERIA_RICH_FOOTER:
    case EXTERIA_RICH_CAPTION: return ExteriaFontRegular(textSize - 3);
    case EXTERIA_RICH_PULLQUOTE: return ExteriaFontMedium(textSize + 1);
    case EXTERIA_RICH_DETAILS: return ExteriaFontSemibold(textSize);
    default: return ExteriaFontRegular(textSize);
    }
}

/* the entities of a block, with a quote over the words of a quoted block and a code block over preformatted ones, so they are drawn the way a message draws them */
static NSArray *ExteriaRichEntities(ExteriaRichBlock *block) {
    NSRange whole = NSMakeRange(0, block.text.length);
    NSMutableArray *entities = [NSMutableArray arrayWithArray:block.entities];
    if (block.kind == EXTERIA_RICH_PREFORMATTED) {
        [entities insertObject:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStylePre range:whole url:nil] autorelease] atIndex:0];
    } else if (block.quote > 0 || block.kind == EXTERIA_RICH_PULLQUOTE) {
        [entities insertObject:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleQuote range:whole url:nil] autorelease] atIndex:0];
    }
    if (block.kind == EXTERIA_RICH_PULLQUOTE) [entities addObject:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleItalic range:whole url:nil] autorelease]];
    return entities;
}

+ (ExteriaRichLayout *)layoutForDocument:(ExteriaRichDocument *)document width:(CGFloat)width textSize:(CGFloat)textSize color:(UIColor *)color
                               secondary:(UIColor *)secondary linkColor:(UIColor *)linkColor revealed:(BOOL)revealed toggled:(NSIndexSet *)toggled {
    if (!document.blocks.count || width < 40) return nil;
    ExteriaRichLayout *layout = [[[ExteriaRichLayout alloc] init] autorelease];
    layout->_pieces = [[NSMutableArray alloc] init];
    layout->_media = [[NSMutableArray alloc] init];
    layout->_captions = [[NSMutableArray alloc] init];
    layout->_zooms = [[NSMutableArray alloc] init];
    layout->_details = [[NSMutableArray alloc] init];
    layout->_spoilersRevealed = revealed;
    layout->_placeholder = [[color colorWithAlphaComponent:0.12f] retain];
    [layout layoutBlocks:document.blocks width:width textSize:textSize color:color secondary:secondary linkColor:linkColor rtl:document.rtl toggled:toggled];
    return layout;
}

- (void)dealloc {
    [_pieces release];
    [_media release];
    [_captions release];
    [_zooms release];
    [_details release];
    [_placeholder release];
    [super dealloc];
}

- (CGFloat)gapBefore:(ExteriaRichBlock *)block after:(ExteriaRichBlock *)previous {
    if (!previous) return 0;
    if (block.kind == EXTERIA_RICH_CAPTION) return RICH_GAP_TIGHT;
    if (block.kind == EXTERIA_RICH_HEADING) return RICH_GAP_HEADING;
    if (previous.kind == EXTERIA_RICH_HEADING) return RICH_GAP_TIGHT;
    if (block.kind == EXTERIA_RICH_LIST_ITEM && previous.kind == EXTERIA_RICH_LIST_ITEM) return RICH_GAP_TIGHT;
    if (block.indent > previous.indent && (previous.kind == EXTERIA_RICH_LIST_ITEM || previous.kind == EXTERIA_RICH_DETAILS)) return RICH_GAP_TIGHT;
    return RICH_GAP;
}

- (void)layoutBlocks:(NSArray *)blocks width:(CGFloat)width textSize:(CGFloat)textSize color:(UIColor *)color secondary:(UIColor *)secondary
           linkColor:(UIColor *)linkColor rtl:(BOOL)rtl toggled:(NSIndexSet *)toggled {
    CGFloat y = 0, right = 0;
    ExteriaRichBlock *previous = nil;
    ExteriaRichPiece *last = nil;
    CGFloat lastFlush = 0;
    NSUInteger count = blocks.count;
    for (NSUInteger i = 0; i < count; ++i) {
        ExteriaRichBlock *block = [blocks objectAtIndex:i];
        /* a cell outside a table has no grid to stand in */
        if (block.kind == EXTERIA_RICH_CELL) continue;
        BOOL open = block.kind == EXTERIA_RICH_DETAILS && (((block.flags & EXTERIA_RICH_OPEN) != 0) != [toggled containsIndex:i]);
        BOOL textual = block.kind != EXTERIA_RICH_MEDIA && block.kind != EXTERIA_RICH_DIVIDER && block.kind != EXTERIA_RICH_TABLE;
        CGFloat x = MIN(width - 40, block.indent * RICH_INDENT + (textual ? MAX(0, block.quote - 1) : block.quote) * RICH_QUOTE_INDENT);
        CGFloat avail = width - x;
        y += [self gapBefore:block after:previous];
        previous = block;
        last = nil;
        switch (block.kind) {
        case EXTERIA_RICH_DIVIDER: {
            CGFloat hair = 1.0 / ExteriaScreenScale();
            [self addFill:CGRectMake(x, y + floor(RICH_DIVIDER_HEIGHT / 2), avail, hair) color:[secondary colorWithAlphaComponent:0.35f] radius:0];
            y += RICH_DIVIDER_HEIGHT;
            right = MAX(right, width);
            break;
        }
        case EXTERIA_RICH_MEDIA: {
            ExteriaMedia *media = block.media;
            if (!media || media.width <= 0 || media.height <= 0) break;
            CGFloat height = round(MIN(RICH_MEDIA_HEIGHT_MAX, MAX(RICH_MEDIA_HEIGHT_MIN, avail * media.height / media.width)));
            ExteriaRichPiece *piece = [self addPiece:ExteriaRichPieceMedia frame:CGRectMake(x, y, avail, height)];
            piece->media = _media.count;
            piece->radius = RICH_MEDIA_RADIUS;
            [_media addObject:media];
            [_zooms addObject:[NSNumber numberWithInt:media.kind == EXTERIA_PREVIEW_LOCATION ? block.level : 0]];
            /* the captions that follow a picture are its words in the viewer */
            NSMutableArray *words = [NSMutableArray array];
            for (NSUInteger k = i + 1; k < count && ((ExteriaRichBlock *)[blocks objectAtIndex:k]).kind == EXTERIA_RICH_CAPTION; ++k) [words addObject:((ExteriaRichBlock *)[blocks objectAtIndex:k]).text];
            [_captions addObject:[words componentsJoinedByString:@"\n"]];
            y += height;
            right = MAX(right, width);
            break;
        }
        case EXTERIA_RICH_TABLE: {
            NSUInteger end = i + 1;
            while (end < count && ((ExteriaRichBlock *)[blocks objectAtIndex:end]).kind == EXTERIA_RICH_CELL) ++end;
            y = [self layoutTable:block cells:[blocks subarrayWithRange:NSMakeRange(i + 1, end - i - 1)] x:x y:y width:avail textSize:textSize
                            color:color secondary:secondary linkColor:linkColor];
            right = MAX(right, width);
            i = end - 1;
            break;
        }
        case EXTERIA_RICH_LIST_ITEM:
        case EXTERIA_RICH_DETAILS: {
            UIFont *font = ExteriaRichFont(block, textSize);
            NSString *mark = block.kind == EXTERIA_RICH_DETAILS ? (open ? @"▾" : @"▸") : ((block.flags & EXTERIA_RICH_CHECKBOX) ? ((block.flags & EXTERIA_RICH_CHECKED) ? @"☑" : @"☐") : block.label);
            ExteriaTextLayout *label = [ExteriaTextLayout layoutForText:mark entities:nil font:font color:secondary linkColor:secondary width:MAX(1, avail / 3) maxLines:1 flush:0];
            CGFloat labelWidth = MAX(ceil(label.size.width), 10);
            CGFloat textX = x + labelWidth + RICH_LABEL_GAP;
            CGFloat height = label.size.height;
            if (block.text.length) {
                ExteriaTextLayout *text = [ExteriaTextLayout layoutForText:block.text entities:ExteriaRichEntities(block) font:font color:color linkColor:linkColor
                                                                     width:MAX(20, width - textX) maxLines:0 flush:rtl ? 1 : 0];
                [self addText:text at:CGPointMake(textX, y)];
                last = [_pieces lastObject];
                lastFlush = rtl ? 1 : 0;
                height = MAX(height, text.size.height);
                right = MAX(right, textX + text.size.width);
            }
            [self addText:label at:CGPointMake(x, y)];
            if (block.kind == EXTERIA_RICH_DETAILS) {
                [_details addObject:[NSArray arrayWithObjects:[NSValue valueWithCGRect:CGRectMake(x, y, width - x, height)], [NSNumber numberWithUnsignedInteger:i], nil]];
                /* a closed summary hides the blocks under it, which stand deeper than it */
                if (!open) {
                    while (i + 1 < count && ((ExteriaRichBlock *)[blocks objectAtIndex:i + 1]).indent > block.indent) ++i;
                }
            }
            y += height;
            break;
        }
        default: {
            if (!block.text.length) break;
            CGFloat flush = block.kind == EXTERIA_RICH_PULLQUOTE ? 0.5 : (rtl ? 1 : 0);
            BOOL quiet = block.kind == EXTERIA_RICH_SUBTITLE || block.kind == EXTERIA_RICH_FOOTER || block.kind == EXTERIA_RICH_CAPTION;
            ExteriaTextLayout *text = [ExteriaTextLayout layoutForText:block.text entities:ExteriaRichEntities(block) font:ExteriaRichFont(block, textSize)
                                                                 color:quiet ? secondary : color linkColor:linkColor width:avail maxLines:0 flush:flush];
            /* centered and right aligned words take the whole column, so the flush has room to act */
            CGFloat textX = flush > 0 ? x + floor((avail - text.size.width) * flush) : x;
            [self addText:text at:CGPointMake(textX, y)];
            last = [_pieces lastObject];
            lastFlush = flush;
            y += text.size.height;
            right = MAX(right, textX + text.size.width);
            break;
        }
        }
    }
    _size = CGSizeMake(ceil(MIN(width, right)), ceil(y));
    _trailingLineWidth = -1;
    if (last && lastFlush == 0 && last->frame.origin.x == 0 && fabs(CGRectGetMaxY(last->frame) - y) < 0.5) _trailingLineWidth = last->layout.lastLineWidth;
}

/* the grid of a table: equal columns over the width, each row as tall as its tallest cell, and a cell that spans rows as tall as those rows together */
- (CGFloat)layoutTable:(ExteriaRichBlock *)table cells:(NSArray *)cells x:(CGFloat)x y:(CGFloat)y width:(CGFloat)width textSize:(CGFloat)textSize
                 color:(UIColor *)color secondary:(UIColor *)secondary linkColor:(UIColor *)linkColor {
    if (table.text.length) {
        ExteriaTextLayout *title = [ExteriaTextLayout layoutForText:table.text entities:table.entities font:ExteriaFontSemibold(textSize - 1) color:color
                                                          linkColor:linkColor width:width maxLines:0 flush:0];
        [self addText:title at:CGPointMake(x, y)];
        y += title.size.height + RICH_GAP_TIGHT;
    }
    NSUInteger columns = MAX(1, table.column), rows = table.row;
    if (!cells.count || !rows) return y;
    CGFloat columnWidth = floor(width / columns);
    UIFont *regular = ExteriaFontRegular(textSize - 2), *header = ExteriaFontSemibold(textSize - 2);
    CGFloat lineHeight = ceil(regular.lineHeight) + 2 * RICH_CELL_PAD;
    CGFloat *heights = calloc(rows, sizeof(CGFloat));
    if (!heights) return y;
    for (NSUInteger r = 0; r < rows; ++r) heights[r] = lineHeight;
    NSMutableArray *layouts = [NSMutableArray arrayWithCapacity:cells.count];
    for (ExteriaRichBlock *cell in cells) {
        CGFloat cellWidth = columnWidth * MIN(cell.colspan, columns - MIN(cell.column, columns - 1)) - 2 * RICH_CELL_PAD;
        CGFloat flush = (cell.flags & EXTERIA_RICH_ALIGN_RIGHT) ? 1 : ((cell.flags & EXTERIA_RICH_ALIGN_CENTER) ? 0.5 : 0);
        ExteriaTextLayout *text = cell.text.length && cell.column < columns && cell.row < rows ?
            [ExteriaTextLayout layoutForText:cell.text entities:cell.entities font:(cell.flags & EXTERIA_RICH_HEADER_CELL) ? header : regular color:color
                                   linkColor:linkColor width:MAX(10, cellWidth) maxLines:0 flush:flush] : nil;
        [layouts addObject:text ? (id)text : (id)[NSNull null]];
        if (text && cell.rowspan <= 1) heights[cell.row] = MAX(heights[cell.row], ceil(text.size.height) + 2 * RICH_CELL_PAD);
    }
    /* a tall cell that needs more than its rows give grows the last of them */
    for (NSUInteger k = 0; k < cells.count; ++k) {
        ExteriaRichBlock *cell = [cells objectAtIndex:k];
        id text = [layouts objectAtIndex:k];
        if (cell.rowspan <= 1 || text == [NSNull null]) continue;
        NSUInteger lastRow = MIN(rows, (NSUInteger)cell.row + cell.rowspan) - 1;
        CGFloat have = 0;
        for (NSUInteger r = cell.row; r <= lastRow; ++r) have += heights[r];
        CGFloat need = ceil(((ExteriaTextLayout *)text).size.height) + 2 * RICH_CELL_PAD;
        if (need > have) heights[lastRow] += need - have;
    }
    CGFloat *tops = calloc(rows + 1, sizeof(CGFloat));
    if (!tops) {
        free(heights);
        return y;
    }
    tops[0] = y;
    for (NSUInteger r = 0; r < rows; ++r) tops[r + 1] = tops[r] + heights[r];
    CGFloat tableWidth = columnWidth * columns;
    if (table.flags & EXTERIA_RICH_STRIPED) {
        for (NSUInteger r = 1; r < rows; r += 2) [self addFill:CGRectMake(x, tops[r], tableWidth, heights[r]) color:[color colorWithAlphaComponent:0.05f] radius:0];
    }
    UIColor *rule = [secondary colorWithAlphaComponent:(table.flags & EXTERIA_RICH_BORDERED) ? 0.45f : 0.25f];
    for (NSUInteger k = 0; k < cells.count; ++k) {
        ExteriaRichBlock *cell = [cells objectAtIndex:k];
        if (cell.column >= columns || cell.row >= rows) continue;
        NSUInteger lastRow = MIN(rows, (NSUInteger)cell.row + cell.rowspan) - 1;
        NSUInteger span = MIN(cell.colspan, columns - cell.column);
        CGRect box = CGRectMake(x + columnWidth * cell.column, tops[cell.row], columnWidth * span, tops[lastRow + 1] - tops[cell.row]);
        if (cell.flags & EXTERIA_RICH_HEADER_CELL) [self addFill:box color:[color colorWithAlphaComponent:0.08f] radius:0];
        if (table.flags & EXTERIA_RICH_BORDERED) [self addStroke:box color:rule];
        id text = [layouts objectAtIndex:k];
        if (text == [NSNull null]) continue;
        ExteriaTextLayout *words = text;
        CGFloat inner = box.size.width - 2 * RICH_CELL_PAD;
        CGFloat flush = (cell.flags & EXTERIA_RICH_ALIGN_RIGHT) ? 1 : ((cell.flags & EXTERIA_RICH_ALIGN_CENTER) ? 0.5 : 0);
        [self addText:words at:CGPointMake(box.origin.x + RICH_CELL_PAD + floor((inner - words.size.width) * flush), box.origin.y + RICH_CELL_PAD)];
    }
    /* a table without borders keeps its rows apart with a thin line under each */
    if (!(table.flags & EXTERIA_RICH_BORDERED)) {
        CGFloat hair = 1.0 / ExteriaScreenScale();
        for (NSUInteger r = 1; r < rows; ++r) [self addFill:CGRectMake(x, tops[r], tableWidth, hair) color:rule radius:0];
    }
    y = tops[rows];
    free(tops);
    free(heights);
    return y;
}

- (void)setSpoilersRevealed:(BOOL)revealed {
    _spoilersRevealed = revealed;
    for (ExteriaRichPiece *piece in _pieces) if (piece->kind == ExteriaRichPieceText) piece->layout.spoilersRevealed = revealed;
}

static CGRect ExteriaAspectFill(CGSize image, CGRect box) {
    if (image.width <= 0 || image.height <= 0) return box;
    CGFloat scale = MAX(box.size.width / image.width, box.size.height / image.height);
    CGSize size = CGSizeMake(image.width * scale, image.height * scale);
    return CGRectMake(box.origin.x + (box.size.width - size.width) / 2, box.origin.y + (box.size.height - size.height) / 2, size.width, size.height);
}

- (void)drawMedia:(ExteriaRichPiece *)piece frame:(CGRect)frame image:(UIImage *)image context:(CGContextRef)context {
    ExteriaMedia *media = [_media objectAtIndex:piece->media];
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:piece->radius] addClip];
    [_placeholder setFill];
    CGContextFillRect(context, frame);
    if (image) {
        BOOL covered = media.spoiler && !_spoilersRevealed;
        if (covered) {
            /* drawn from a few pixels and smoothed back up: a blur the old devices make without a filter */
            CGFloat side = RICH_SPOILER_PIXELS;
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side * frame.size.height / frame.size.width), YES, 1);
            [image drawInRect:ExteriaAspectFill(image.size, CGRectMake(0, 0, side, side * frame.size.height / frame.size.width))];
            UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
            [small drawInRect:frame];
        } else {
            [image drawInRect:ExteriaAspectFill(image.size, frame)];
        }
    }
    if (media.kind == EXTERIA_PREVIEW_VIDEO || media.kind == EXTERIA_PREVIEW_GIF) {
        CGFloat side = 44;
        CGRect disc = CGRectMake(CGRectGetMidX(frame) - side / 2, CGRectGetMidY(frame) - side / 2, side, side);
        [[UIColor colorWithWhite:0 alpha:0.45f] setFill];
        CGContextFillEllipseInRect(context, disc);
        UIImage *glyph = ExteriaSymbolImage(ExteriaSymbolPlay, 22, [UIColor whiteColor]);
        [glyph drawAtPoint:CGPointMake(CGRectGetMidX(disc) - glyph.size.width / 2, CGRectGetMidY(disc) - glyph.size.height / 2)];
    }
    CGContextRestoreGState(context);
}

- (void)drawAtPoint:(CGPoint)origin images:(NSDictionary *)images {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    for (ExteriaRichPiece *piece in _pieces) {
        CGRect frame = CGRectOffset(piece->frame, origin.x, origin.y);
        switch (piece->kind) {
        case ExteriaRichPieceFill:
            [piece->color setFill];
            if (piece->radius > 0) [[UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:piece->radius] fill];
            else CGContextFillRect(context, frame);
            break;
        case ExteriaRichPieceStroke: {
            CGFloat hair = 1.0 / ExteriaScreenScale();
            [piece->color setStroke];
            CGContextSetLineWidth(context, hair);
            CGContextStrokeRect(context, CGRectInset(frame, hair / 2, hair / 2));
            break;
        }
        case ExteriaRichPieceMedia:
            [self drawMedia:piece frame:frame image:[images objectForKey:[NSNumber numberWithUnsignedInteger:piece->media]] context:context];
            break;
        case ExteriaRichPieceText:
            [piece->layout drawAtPoint:frame.origin];
            break;
        }
    }
}

- (NSString *)linkAtPoint:(CGPoint)point {
    for (ExteriaRichPiece *piece in _pieces) {
        if (piece->kind != ExteriaRichPieceText || !CGRectContainsPoint(piece->frame, point)) continue;
        NSString *url = [piece->layout linkAtPoint:CGPointMake(point.x - piece->frame.origin.x, point.y - piece->frame.origin.y)];
        if (url) return url;
    }
    return nil;
}

- (NSUInteger)mediaCount {
    return _media.count;
}

- (ExteriaMedia *)mediaAtIndex:(NSUInteger)index {
    return index < _media.count ? [_media objectAtIndex:index] : nil;
}

- (CGRect)frameOfMediaAtIndex:(NSUInteger)index {
    for (ExteriaRichPiece *piece in _pieces) if (piece->kind == ExteriaRichPieceMedia && piece->media == index) return piece->frame;
    return CGRectZero;
}

- (NSString *)captionOfMediaAtIndex:(NSUInteger)index {
    return index < _captions.count ? [_captions objectAtIndex:index] : @"";
}

- (int)zoomOfMediaAtIndex:(NSUInteger)index {
    return index < _zooms.count ? [[_zooms objectAtIndex:index] intValue] : 0;
}

- (NSUInteger)detailsAtPoint:(CGPoint)point {
    for (NSArray *row in _details) {
        if (CGRectContainsPoint([[row objectAtIndex:0] CGRectValue], point)) return [[row objectAtIndex:1] unsignedIntegerValue];
    }
    return NSNotFound;
}

- (NSUInteger)mediaIndexAtPoint:(CGPoint)point {
    for (ExteriaRichPiece *piece in _pieces) if (piece->kind == ExteriaRichPieceMedia && CGRectContainsPoint(piece->frame, point)) return piece->media;
    return NSNotFound;
}

@end
