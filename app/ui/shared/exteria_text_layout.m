#import "exteria_text_layout.h"

#import <CoreText/CoreText.h>
#include <stdint.h>

#import "exteria_custom_emoji.h"
#import "exteria_emoji_store.h"
#import "exteria_font_fallback.h"
#import "exteria_theme.h"

/* the attributes the layout keeps on the characters for itself */
static NSString *const ExteriaLinkAttribute = @"ExteriaLink";
static NSString *const ExteriaEmojiAttribute = @"ExteriaEmoji";
static NSString *const ExteriaCustomEmojiAttribute = @"ExteriaCustomEmoji";
static NSString *const ExteriaStrikeAttribute = @"ExteriaStrike";
static NSString *const ExteriaSpoilerAttribute = @"ExteriaSpoiler";
static NSString *const ExteriaMonoAttribute = @"ExteriaMono";
NSString *const ExteriaSpoilerTarget = @"exteria-spoiler:";

/* a quote is set in from the left edge by its bar, which is drawn in that room */
#define QUOTE_INDENT 11.0
#define QUOTE_BAR 3.0

/* an emoji picture is a little wider than the letters around it, as the system's own emoji are */
#define EMOJI_SCALE 1.25

static CTFontRef ExteriaCreateFont(UIFont *font, CGFloat size) {
    /* the system font is San Francisco from ios 9 and its name starts with a dot; CoreText resolves it by name
       only up to ios 12, and from ios 13 hands back Times, so the text of a bubble came out in a serif face */
    if ([font respondsToSelector:@selector(fontDescriptor)]) return CTFontCreateCopyWithAttributes((CTFontRef)font, size, NULL, NULL);
    CTFontRef created = CTFontCreateWithName((CFStringRef)font.fontName, size, NULL);
    if (!created) created = CTFontCreateWithName(CFSTR("HelveticaNeue"), size, NULL);
    return created;
}

static CTFontRef ExteriaCreateItalic(CTFontRef base) {
    CGAffineTransform skew = CGAffineTransformMake(1, 0, 0.2, 1, 0, 0);
    return CTFontCreateCopyWithAttributes(base, CTFontGetSize(base), &skew, NULL);
}

static CGFloat ExteriaEmojiSide(void *refcon) { return (CGFloat)(((uintptr_t)refcon >> 16) & 0xffff) / 100.0; }
static CGFloat ExteriaEmojiAscent(void *refcon) { return ExteriaEmojiSide(refcon) * 0.82; }
static CGFloat ExteriaEmojiDescent(void *refcon) { return ExteriaEmojiSide(refcon) * 0.23; }
static CGFloat ExteriaEmojiWidth(void *refcon) { return (CGFloat)((uintptr_t)refcon & 0xffff) / 100.0; }
static void ExteriaEmojiRelease(void *refcon) { (void)refcon; }

/* the run delegate carries height and width in hundredths of a point */
static CTRunDelegateRef ExteriaCreateEmojiDelegate(CGFloat side, CGFloat width) {
    CTRunDelegateCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.version = kCTRunDelegateCurrentVersion;
    callbacks.getAscent = ExteriaEmojiAscent;
    callbacks.getDescent = ExteriaEmojiDescent;
    callbacks.getWidth = ExteriaEmojiWidth;
    callbacks.dealloc = ExteriaEmojiRelease;
    uintptr_t dimensions = ((uintptr_t)(side * 100) << 16) | (uintptr_t)(width * 100);
    return CTRunDelegateCreate(&callbacks, (void *)dimensions);
}

static NSString *ExteriaLinkTarget(ExteriaTextEntity *entity, NSString *text) {
    if (entity.url.length) return entity.url;
    NSString *shown = [text substringWithRange:entity.range];
    if (entity.style == ExteriaTextStyleLink) {
        return [shown rangeOfString:@"://"].location == NSNotFound ? [@"http://" stringByAppendingString:shown] : shown;
    }
    /* a name opens the profile of whoever owns it; a name written with a user's real name instead of a @username has nothing to open */
    if (entity.style == ExteriaTextStyleMention && [shown hasPrefix:@"@"] && shown.length > 1) return [@"exteria-mention:" stringByAppendingString:[shown substringFromIndex:1]];
    if (entity.style == ExteriaTextStyleBotCommand) return [@"exteria-command:" stringByAppendingString:shown];
    if (entity.style == ExteriaTextStyleMentionName && entity.userId > 0) return [NSString stringWithFormat:@"exteria-user:%lld", entity.userId];
    if (entity.style == ExteriaTextStyleDate && entity.date > 0) return [NSString stringWithFormat:@"exteria-date:%d:%u", (int)entity.date, (unsigned)entity.flags];
    return nil;
}

@implementation ExteriaTextLayout

@synthesize size = _size;
@synthesize lastLineWidth = _lastLineWidth;
@synthesize lineCount = _lineCount;
@synthesize hasSpoilers = _hasSpoilers;
@synthesize spoilersRevealed = _spoilersRevealed;

/* the attributed string with its styles; emoji are not touched yet */
static NSMutableAttributedString *ExteriaStyledString(NSString *text, NSArray *entities, UIFont *font, UIColor *color, UIColor *linkColor) {
    CGFloat size = font.pointSize;
    CTFontRef regular = ExteriaCreateFont(font, size);
    CTFontRef bold = ExteriaCreateFont(ExteriaFontSemibold(size), size);
    CTFontRef italic = ExteriaCreateItalic(regular);
    CTFontRef code = CTFontCreateWithName(CFSTR("Courier"), size - 1, NULL);
    NSMutableAttributedString *string = [[[NSMutableAttributedString alloc] initWithString:text] autorelease];
    NSRange all = NSMakeRange(0, text.length);
    [string addAttribute:(id)kCTFontAttributeName value:(id)regular range:all];
    [string addAttribute:(id)kCTForegroundColorAttributeName value:(id)color.CGColor range:all];
    for (ExteriaTextEntity *entity in entities) {
        NSRange range = entity.range;
        if (range.location + range.length > text.length) continue;
        switch (entity.style) {
        case ExteriaTextStyleBold: [string addAttribute:(id)kCTFontAttributeName value:(id)bold range:range]; break;
        case ExteriaTextStyleItalic: [string addAttribute:(id)kCTFontAttributeName value:(id)italic range:range]; break;
        case ExteriaTextStyleCode:
        case ExteriaTextStylePre:
            [string addAttribute:(id)kCTFontAttributeName value:(id)code range:range];
            [string addAttribute:ExteriaMonoAttribute value:[NSNumber numberWithBool:YES] range:range];
            break;
        case ExteriaTextStyleUnderline: {
            int single = kCTUnderlineStyleSingle;
            CFNumberRef style = CFNumberCreate(NULL, kCFNumberIntType, &single);
            [string addAttribute:(id)kCTUnderlineStyleAttributeName value:(id)style range:range];
            CFRelease(style);
            break;
        }
        case ExteriaTextStyleStrike: [string addAttribute:ExteriaStrikeAttribute value:[NSNumber numberWithBool:YES] range:range]; break;
        case ExteriaTextStyleSpoiler: [string addAttribute:ExteriaSpoilerAttribute value:[NSNumber numberWithBool:YES] range:range]; break;
        /* a quote is shaped when the lines are broken, not here */
        case ExteriaTextStyleQuote:
        case ExteriaTextStyleCustomEmoji: break;
        case ExteriaTextStyleDate: {
            int single = kCTUnderlineStyleSingle;
            CFNumberRef style = CFNumberCreate(NULL, kCFNumberIntType, &single);
            [string addAttribute:(id)kCTUnderlineStyleAttributeName value:(id)style range:range];
            CFRelease(style);
            [string addAttribute:(id)kCTForegroundColorAttributeName value:(id)linkColor.CGColor range:range];
            NSString *target = ExteriaLinkTarget(entity, text);
            if (target) [string addAttribute:ExteriaLinkAttribute value:target range:range];
            break;
        }
        case ExteriaTextStyleMentionName:
        case ExteriaTextStyleMention: {
            [string addAttribute:(id)kCTFontAttributeName value:(id)bold range:range];
            [string addAttribute:(id)kCTForegroundColorAttributeName value:(id)ExteriaColorAccent().CGColor range:range];
            NSString *target = ExteriaLinkTarget(entity, text);
            if (target) [string addAttribute:ExteriaLinkAttribute value:target range:range];
            break;
        }
        case ExteriaTextStyleLink:
        case ExteriaTextStyleBotCommand:
        case ExteriaTextStyleHashtag: {
            [string addAttribute:(id)kCTForegroundColorAttributeName value:(id)linkColor.CGColor range:range];
            NSString *target = ExteriaLinkTarget(entity, text);
            if (target) [string addAttribute:ExteriaLinkAttribute value:target range:range];
            break;
        }
        }
    }
    CFRelease(regular);
    CFRelease(bold);
    CFRelease(italic);
    CFRelease(code);
    return string;
}

/* one run of the text that becomes a picture: an ordinary emoji, or a custom one with the ordinary emoji it stands for kept as the
   picture to show until its own has loaded */
typedef struct {
    NSUInteger start;
    NSUInteger length;
    size_t entry;
    long long document;
} ExteriaEmojiMark;

static const size_t ExteriaNoEntry = (size_t)-1;

static int ExteriaMarkOrder(const void *a, const void *b) {
    NSUInteger x = ((const ExteriaEmojiMark *)a)->start, y = ((const ExteriaEmojiMark *)b)->start;
    return x < y ? 1 : x > y ? -1 : 0;
}

/* every emoji becomes one placeholder character each with its own room, back to front so earlier ranges stay put */
static void ExteriaPlaceEmoji(NSMutableAttributedString *string, NSString *text, NSArray *entities, CGFloat fontSize) {
    NSUInteger length = text.length;
    uint16_t *units = malloc(sizeof(uint16_t) * (length ? length : 1));
    exteria_emoji_span *spans = malloc(sizeof(exteria_emoji_span) * (length ? length : 1));
    ExteriaEmojiMark *marks = malloc(sizeof(ExteriaEmojiMark) * (length ? length : 1));
    if (units && spans && marks) {
        [text getCharacters:units range:NSMakeRange(0, length)];
        size_t count = exteria_emoji_scan(units, length, spans, length);
        size_t total = 0;
        for (ExteriaTextEntity *entity in entities) {
            NSRange range = entity.range;
            if (entity.style != ExteriaTextStyleCustomEmoji || !entity.documentId || range.length == 0 || range.location + range.length > length) continue;
            BOOL overlaps = NO;
            for (size_t k = 0; k < total; ++k) {
                if (marks[k].document && range.location < marks[k].start + marks[k].length && marks[k].start < range.location + range.length) overlaps = YES;
            }
            if (overlaps || total >= length) continue;
            marks[total].start = range.location;
            marks[total].length = range.length;
            marks[total].document = entity.documentId;
            marks[total].entry = ExteriaNoEntry;
            for (size_t i = 0; i < count; ++i) {
                if (spans[i].start >= range.location && spans[i].start + spans[i].length <= range.location + range.length &&
                    ExteriaEmojiHasPicture(spans[i].entry)) {
                    marks[total].entry = spans[i].entry;
                    break;
                }
            }
            ++total;
        }
        size_t customs = total;
        for (size_t i = 0; i < count; ++i) {
            BOOL inside = NO;
            for (size_t k = 0; k < customs; ++k) {
                if (spans[i].start < marks[k].start + marks[k].length && marks[k].start < spans[i].start + spans[i].length) inside = YES;
            }
            if (inside || !ExteriaEmojiHasPicture(spans[i].entry) || total >= length) continue;
            marks[total].start = spans[i].start;
            marks[total].length = spans[i].length;
            marks[total].entry = spans[i].entry;
            marks[total].document = 0;
            ++total;
        }
        qsort(marks, total, sizeof(*marks), ExteriaMarkOrder);
        for (size_t i = 0; i < total; ++i) {
            const ExteriaEmojiMark *mark = &marks[i];
            [string replaceCharactersInRange:NSMakeRange(mark->start, mark->length) withString:@"\uFFFC"];
            NSRange place = NSMakeRange(mark->start, 1);
            CGFloat side = fontSize * EMOJI_SCALE;
            CGFloat width = mark->document == EXTERIA_CAUTION_DOCUMENT ? side * EXTERIA_CAUTION_BADGE_RATIO : side;
            CTRunDelegateRef delegate = ExteriaCreateEmojiDelegate(side, width);
            [string addAttribute:(id)kCTRunDelegateAttributeName value:(id)delegate range:place];
            CFRelease(delegate);
            if (mark->entry != ExteriaNoEntry) [string addAttribute:ExteriaEmojiAttribute value:[NSNumber numberWithUnsignedInteger:mark->entry] range:place];
            if (mark->document) [string addAttribute:ExteriaCustomEmojiAttribute value:[NSNumber numberWithLongLong:mark->document] range:place];
        }
    }
    free(units);
    free(spans);
    free(marks);
}

+ (ExteriaTextLayout *)layoutForText:(NSString *)text entities:(NSArray *)entities font:(UIFont *)font
                               color:(UIColor *)color linkColor:(UIColor *)linkColor width:(CGFloat)width
                            maxLines:(NSUInteger)maxLines flush:(CGFloat)flush {
    return [self layoutForText:text entities:entities font:font color:color linkColor:linkColor width:width maxLines:maxLines flush:flush
                  dropsUndrawable:NO];
}

+ (ExteriaTextLayout *)layoutForName:(NSString *)name font:(UIFont *)font color:(UIColor *)color width:(CGFloat)width {
    return [self layoutForName:name entities:nil font:font color:color width:width];
}

+ (ExteriaTextLayout *)layoutForName:(NSString *)name entities:(NSArray *)entities font:(UIFont *)font color:(UIColor *)color width:(CGFloat)width {
    return [self layoutForText:name entities:entities font:font color:color linkColor:color width:width maxLines:1 flush:0 dropsUndrawable:YES];
}

+ (ExteriaTextLayout *)layoutForText:(NSString *)text entities:(NSArray *)entities font:(UIFont *)font
                               color:(UIColor *)color linkColor:(UIColor *)linkColor width:(CGFloat)width
                            maxLines:(NSUInteger)maxLines flush:(CGFloat)flush dropsUndrawable:(BOOL)drops {
    ExteriaTextLayout *layout = [[[ExteriaTextLayout alloc] init] autorelease];
    NSMutableAttributedString *string = ExteriaStyledString(text, entities, font, color, linkColor);
    ExteriaPlaceEmoji(string, text, entities, font.pointSize);
    CTFontRef base = ExteriaCreateFont(font, font.pointSize);
    if (base) {
        /* the entities are offsets into the original text, so only a label that has none may lose characters */
        if (drops) ExteriaDropUndrawableCharacters(string, base);
        ExteriaApplyFontFallback(string, base, font.pointSize);
        CFRelease(base);
    }
    layout->_string = [string retain];
    layout->_ink = [color retain];
    layout->_width = width;
    layout->_hasSpoilers = NO;
    NSMutableArray *quotes = [NSMutableArray array];
    for (ExteriaTextEntity *entity in entities) {
        if (entity.style == ExteriaTextStyleQuote && NSMaxRange(entity.range) <= text.length) [quotes addObject:[NSValue valueWithRange:entity.range]];
        if (entity.style == ExteriaTextStyleSpoiler && NSMaxRange(entity.range) <= text.length) layout->_hasSpoilers = YES;
    }

    CTLineBreakMode breakMode = kCTLineBreakByWordWrapping;
    CTParagraphStyleSetting settings[] = {{kCTParagraphStyleSpecifierLineBreakMode, sizeof(breakMode), &breakMode}};
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(settings, 1);
    [string addAttribute:(id)kCTParagraphStyleAttributeName value:(id)paragraph range:NSMakeRange(0, string.length)];
    CFRelease(paragraph);

    CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString((CFAttributedStringRef)string);
    CFIndex length = (CFIndex)string.length;
    NSUInteger capacity = 16;
    layout->_lines = calloc(capacity, sizeof(CTLineRef));
    layout->_origins = calloc(capacity, sizeof(CGPoint));
    layout->_ascents = calloc(capacity, sizeof(CGFloat));
    layout->_descents = calloc(capacity, sizeof(CGFloat));
    layout->_quoted = calloc(capacity, sizeof(BOOL));
    CGFloat baseline = 0, widest = 0, previousDescent = 0;
    CFIndex start = 0;
    while (start < length && layout->_lines && layout->_origins && layout->_ascents && layout->_descents && layout->_quoted) {
        BOOL quoted = NO;
        for (NSValue *quote in quotes) {
            NSRange r = [quote rangeValue];
            if ((NSUInteger)start >= r.location && (NSUInteger)start < NSMaxRange(r)) quoted = YES;
        }
        CGFloat indent = quoted ? QUOTE_INDENT : 0, room = MAX(20, width - indent);
        if (layout->_lineCount == capacity) {
            capacity *= 2;
            layout->_lines = realloc(layout->_lines, capacity * sizeof(CTLineRef));
            layout->_origins = realloc(layout->_origins, capacity * sizeof(CGPoint));
            layout->_ascents = realloc(layout->_ascents, capacity * sizeof(CGFloat));
            layout->_descents = realloc(layout->_descents, capacity * sizeof(CGFloat));
            layout->_quoted = realloc(layout->_quoted, capacity * sizeof(BOOL));
            if (!layout->_lines || !layout->_origins || !layout->_ascents || !layout->_descents || !layout->_quoted) break;
        }
        CFIndex fit = CTTypesetterSuggestLineBreak(typesetter, start, room);
        if (fit <= 0) break;
        BOOL lastAllowed = maxLines && layout->_lineCount + 1 == maxLines;
        CTLineRef line;
        if (lastAllowed && start + fit < length) {
            /* the rest of the text goes into one line that is cut to the width and ends in an ellipsis */
            CTLineRef rest = CTTypesetterCreateLine(typesetter, CFRangeMake(start, length - start));
            NSMutableDictionary *tokenAttributes = [NSMutableDictionary dictionaryWithDictionary:[string attributesAtIndex:(NSUInteger)start effectiveRange:NULL]];
            /* an emoji at the start must not turn the truncation ellipsis into another emoji */
            [tokenAttributes removeObjectForKey:(id)kCTRunDelegateAttributeName];
            [tokenAttributes removeObjectForKey:ExteriaEmojiAttribute];
            [tokenAttributes removeObjectForKey:ExteriaCustomEmojiAttribute];
            CFAttributedStringRef token = CFAttributedStringCreate(NULL, (CFStringRef)@"\u2026", (CFDictionaryRef)tokenAttributes);
            CTLineRef ellipsis = CTLineCreateWithAttributedString(token);
            CFRelease(token);
            line = CTLineCreateTruncatedLine(rest, room, kCTLineTruncationEnd, ellipsis);
            CFRelease(ellipsis);
            CFRelease(rest);
            if (!line) line = CTTypesetterCreateLine(typesetter, CFRangeMake(start, fit));
            fit = length - start;
        } else {
            line = CTTypesetterCreateLine(typesetter, CFRangeMake(start, fit));
        }
        CGFloat ascent, descent, leading;
        CGFloat lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading) - CTLineGetTrailingWhitespaceWidth(line);
        baseline += (layout->_lineCount ? previousDescent : 0) + ascent + (layout->_lineCount ? leading : 0);
        double offset = CTLineGetPenOffsetForFlush(line, flush, room) + indent;
        NSUInteger i = layout->_lineCount++;
        layout->_lines[i] = line;
        layout->_quoted[i] = quoted;
        layout->_origins[i] = CGPointMake((CGFloat)offset, baseline);
        layout->_ascents[i] = ascent;
        layout->_descents[i] = descent;
        previousDescent = descent;
        lineWidth += indent;
        if (lineWidth > widest) widest = lineWidth;
        layout->_lastLineWidth = ceil(lineWidth);
        start += fit;
    }
    CFRelease(typesetter);
    layout->_size = CGSizeMake(ceil(widest), ceil(baseline + previousDescent) + 1);
    return layout;
}

- (void)dealloc {
    for (NSUInteger i = 0; i < _lineCount; ++i) CFRelease(_lines[i]);
    free(_lines);
    free(_origins);
    free(_ascents);
    free(_descents);
    free(_quoted);
    [_ink release];
    [_string release];
    [super dealloc];
}

/* the boxes of the runs that carry an attribute on one line, in the coordinates of the text box */
- (NSArray *)boxesOfAttribute:(NSString *)name inLine:(NSUInteger)i {
    NSMutableArray *boxes = [NSMutableArray array];
    CFArrayRef runs = CTLineGetGlyphRuns(_lines[i]);
    for (CFIndex j = 0; j < CFArrayGetCount(runs); ++j) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, j);
        if (![(NSDictionary *)CTRunGetAttributes(run) objectForKey:name]) continue;
        CGPoint position;
        CGFloat ascent, descent;
        CTRunGetPositions(run, CFRangeMake(0, 1), &position);
        CGFloat width = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, NULL);
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(_origins[i].x + position.x, _origins[i].y - ascent, width, ascent + descent)]];
    }
    return boxes;
}

- (void)drawAtPoint:(CGPoint)origin {
    [self drawAtPoint:origin hidingCustomEmoji:0];
}

- (void)drawAtPoint:(CGPoint)origin hidingCustomEmoji:(long long)hiddenDocument {
    if (!_lineCount) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL covered = _hasSpoilers && !_spoilersRevealed;
    UIColor *ink = _ink ? _ink : [UIColor blackColor];
    for (NSUInteger i = 0; i < _lineCount; ++i) {
        CGRect line = CGRectMake(origin.x, origin.y + _origins[i].y - _ascents[i], _width, _ascents[i] + _descents[i]);
        if (_quoted[i]) {
            /* a plate over the whole quote, one line at a time, with its bar on the left edge of the first and last line cut round */
            [[ink colorWithAlphaComponent:0.08] setFill];
            CGContextFillRect(context, line);
            [[ink colorWithAlphaComponent:0.55] setFill];
            CGContextFillRect(context, CGRectMake(origin.x, line.origin.y, QUOTE_BAR, line.size.height));
        }
        for (NSValue *box in [self boxesOfAttribute:ExteriaMonoAttribute inLine:i]) {
            CGRect rect = [box CGRectValue];
            [[ink colorWithAlphaComponent:0.12] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectOffset(rect, origin.x, origin.y), -1, 0) cornerRadius:3] fill];
        }
        NSArray *spoilers = covered ? [self boxesOfAttribute:ExteriaSpoilerAttribute inLine:i] : nil;
        CGContextSaveGState(context);
        if (spoilers.count) {
            /* the glyphs of a covered spoiler are never drawn: the clip is the whole line less the spoiler boxes */
            CGContextBeginPath(context);
            CGContextAddRect(context, CGRectInset(line, -4, -4));
            for (NSValue *box in spoilers) CGContextAddRect(context, CGRectOffset([box CGRectValue], origin.x, origin.y));
            CGContextEOClip(context);
        }
        /* CoreText draws with the origin at the bottom left, so each line is drawn in a flipped frame of its own */
        CGContextTranslateCTM(context, origin.x + _origins[i].x, origin.y + _origins[i].y);
        CGContextScaleCTM(context, 1, -1);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, 0, 0);
        CTLineDraw(_lines[i], context);
        CGContextRestoreGState(context);
        for (NSValue *box in spoilers) {
            [[ink colorWithAlphaComponent:0.3] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectOffset([box CGRectValue], origin.x, origin.y) cornerRadius:4] fill];
        }
        for (NSValue *box in [self boxesOfAttribute:ExteriaStrikeAttribute inLine:i]) {
            CGRect rect = CGRectOffset([box CGRectValue], origin.x, origin.y);
            [ink setFill];
            CGContextFillRect(context, CGRectMake(rect.origin.x, floor(rect.origin.y + rect.size.height * 0.45), rect.size.width, 1));
        }
        CFArrayRef runs = CTLineGetGlyphRuns(_lines[i]);
        for (CFIndex j = 0; j < CFArrayGetCount(runs); ++j) {
            CTRunRef run = CFArrayGetValueAtIndex(runs, j);
            NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
            NSNumber *entry = [attributes objectForKey:ExteriaEmojiAttribute];
            NSNumber *document = [attributes objectForKey:ExteriaCustomEmojiAttribute];
            if (!entry && !document) continue;
            if (document && hiddenDocument && [document longLongValue] == hiddenDocument) continue;
            /* an emoji inside a covered spoiler stays hidden with the words around it */
            if (covered && [attributes objectForKey:ExteriaSpoilerAttribute]) continue;
            CGPoint position;
            CGFloat ascent, descent;
            CTRunGetPositions(run, CFRangeMake(0, 1), &position);
            CGFloat width = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, NULL);
            CGRect rect = CGRectMake(origin.x + _origins[i].x + position.x, origin.y + _origins[i].y - ascent, width, ascent + descent);
            UIImage *picture = document ? [ExteriaCustomEmoji imageForDocument:[document longLongValue]] : nil;
            /* every emoji is a square of the width the line reserved, centered in its room; the room is a little taller than wide, and a
               picture drawn into all of it came out stretched */
            CGFloat side = document && [document longLongValue] == EXTERIA_CAUTION_DOCUMENT ?
                rect.size.width / EXTERIA_CAUTION_BADGE_RATIO : rect.size.width;
            CGFloat pictureWidth = document && [document longLongValue] == EXTERIA_CAUTION_DOCUMENT ? rect.size.width : side;
            CGRect square = CGRectMake(CGRectGetMidX(rect) - pictureWidth / 2, CGRectGetMidY(rect) - side / 2, pictureWidth, side);
            if (picture) {
                [picture drawInRect:square];
            } else if (entry) {
                ExteriaDrawEmoji([entry unsignedIntegerValue], square);
            }
        }
    }
}

- (NSString *)linkAtPoint:(CGPoint)point {
    for (NSUInteger i = 0; i < _lineCount; ++i) {
        if (point.y < _origins[i].y - _ascents[i] - 2 || point.y > _origins[i].y + _descents[i] + 2) continue;
        CGFloat width = CTLineGetTypographicBounds(_lines[i], NULL, NULL, NULL);
        if (point.x < _origins[i].x || point.x > _origins[i].x + width) return nil;
        CFIndex index = CTLineGetStringIndexForPosition(_lines[i], CGPointMake(point.x - _origins[i].x, 0));
        if (index == kCFNotFound || (NSUInteger)index >= _string.length) return nil;
        if (_hasSpoilers && !_spoilersRevealed && [_string attribute:ExteriaSpoilerAttribute atIndex:(NSUInteger)index effectiveRange:NULL]) return ExteriaSpoilerTarget;
        return [_string attribute:ExteriaLinkAttribute atIndex:(NSUInteger)index effectiveRange:NULL];
    }
    return nil;
}

- (CGRect)rectOfCustomEmoji:(long long)document {
    for (NSUInteger i = 0; i < _lineCount; ++i) {
        CFArrayRef runs = CTLineGetGlyphRuns(_lines[i]);
        for (CFIndex j = 0; j < CFArrayGetCount(runs); ++j) {
            CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, j);
            NSNumber *found = [(NSDictionary *)CTRunGetAttributes(run) objectForKey:ExteriaCustomEmojiAttribute];
            if (!found || found.longLongValue != document || CTRunGetGlyphCount(run) == 0) continue;
            CGPoint position;
            CTRunGetPositions(run, CFRangeMake(0, 1), &position);
            CGFloat width = (CGFloat)CTRunGetTypographicBounds(run, CFRangeMake(0, 0), NULL, NULL, NULL);
            return CGRectMake(_origins[i].x + position.x, _origins[i].y - _ascents[i], width, _ascents[i] + _descents[i]);
        }
    }
    return CGRectNull;
}

- (long long)customEmojiAtPoint:(CGPoint)point {
    for (NSUInteger i = 0; i < _lineCount; ++i) {
        if (point.y < _origins[i].y - _ascents[i] - 2 || point.y > _origins[i].y + _descents[i] + 2) continue;
        CFArrayRef runs = CTLineGetGlyphRuns(_lines[i]);
        for (CFIndex j = 0; j < CFArrayGetCount(runs); ++j) {
            CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, j);
            NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
            NSNumber *document = [attributes objectForKey:ExteriaCustomEmojiAttribute];
            if (!document || CTRunGetGlyphCount(run) == 0) continue;
            CGPoint position;
            CTRunGetPositions(run, CFRangeMake(0, 1), &position);
            CGFloat x = _origins[i].x + position.x;
            CGFloat width = (CGFloat)CTRunGetTypographicBounds(run, CFRangeMake(0, 0), NULL, NULL, NULL);
            if (point.x >= x && point.x < x + width) return document.longLongValue;
        }
        return 0;
    }
    return 0;
}

@end
