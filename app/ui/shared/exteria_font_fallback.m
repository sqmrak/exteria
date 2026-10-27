#import "exteria_font_fallback.h"

#include "exteria_text_class.h"

#define FALLBACK_COUNT 5
/* what a lookup answers: the base font or the system draws the character, a bundled font does (its index plus one), or nothing does */
#define FALLBACK_NONE 0
#define FALLBACK_MISSING 255
/* the coverage of a bundled font is read at this size, which is only a handle for the lookup */
#define PROBE_SIZE 12.0

/* in the order they are tried: math letters, symbols of the basic plane, symbols of the other planes */
static NSString *const ExteriaFallbackFiles[FALLBACK_COUNT] = {
    @"NotoSansMath-Regular.ttf", @"NotoSansSymbols-Regular.ttf", @"NotoSansSymbols2-Regular.ttf", @"Unifont.otf", @"UnifontUpper.otf",
};

static CGFontRef ExteriaFallbackGraphics[FALLBACK_COUNT];
static CTFontRef ExteriaFallbackProbes[FALLBACK_COUNT];
static BOOL ExteriaFallbackTried[FALLBACK_COUNT];
/* base font family -> (code point -> lookup answer), and "index@size" -> font of a bundled file at a size */
static NSMutableDictionary *ExteriaCoverage;
static NSMutableDictionary *ExteriaSizedFonts;
static BOOL ExteriaCoverageDirty;

/* a lookup of a character that no base font has opens the bundled fonts and asks each of them, which took seconds
   on the main thread for a name in an unusual script */
static NSString *ExteriaCoveragePath(void) {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [caches stringByAppendingPathComponent:@"exteria-glyph-coverage.plist"];
}

static NSString *ExteriaCoverageSignature(void) {
    id build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    return [NSString stringWithFormat:@"%@|%@|%@", build ? build : @"", [[NSProcessInfo processInfo] operatingSystemVersionString],
            [[NSArray arrayWithObjects:ExteriaFallbackFiles count:FALLBACK_COUNT] componentsJoinedByString:@","]];
}

static void ExteriaLoadCoverage(void) {
    NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:ExteriaCoveragePath()];
    if (![[file objectForKey:@"signature"] isEqual:ExteriaCoverageSignature()]) return;
    NSDictionary *families = [file objectForKey:@"families"];
    if (![families isKindOfClass:[NSDictionary class]]) return;
    for (NSString *family in families) {
        NSDictionary *stored = [families objectForKey:family];
        if (![stored isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *answers = [NSMutableDictionary dictionaryWithCapacity:stored.count];
        for (NSString *key in stored) {
            NSNumber *answer = [stored objectForKey:key];
            if ([answer isKindOfClass:[NSNumber class]]) [answers setObject:answer forKey:[NSNumber numberWithUnsignedInt:(unsigned)[key intValue]]];
        }
        [ExteriaCoverage setObject:answers forKey:family];
    }
}

static NSObject *ExteriaFallbackLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSObject alloc] init];
        ExteriaCoverage = [[NSMutableDictionary alloc] init];
        ExteriaSizedFonts = [[NSMutableDictionary alloc] init];
        ExteriaLoadCoverage();
    });
    return lock;
}

/* the new answers are written a few seconds after the first of them, in one file, off the thread that asked; the caller holds the lock */
static void ExteriaCoverageChanged(void) {
    if (ExteriaCoverageDirty) return;
    ExteriaCoverageDirty = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSMutableDictionary *families = [NSMutableDictionary dictionary];
        @synchronized (ExteriaFallbackLock()) {
            ExteriaCoverageDirty = NO;
            for (NSString *family in ExteriaCoverage) {
                NSDictionary *answers = [ExteriaCoverage objectForKey:family];
                NSMutableDictionary *stored = [NSMutableDictionary dictionaryWithCapacity:answers.count];
                for (NSNumber *cp in answers) [stored setObject:[answers objectForKey:cp] forKey:[NSString stringWithFormat:@"%u", [cp unsignedIntValue]]];
                [families setObject:stored forKey:family];
            }
        }
        NSDictionary *file = [NSDictionary dictionaryWithObjectsAndKeys:ExteriaCoverageSignature(), @"signature", families, @"families", nil];
        if (![file writeToFile:ExteriaCoveragePath() atomically:YES]) NSLog(@"exteria: the glyph coverage was not saved");
    });
}

/* a bundled file is loaded once, from the file itself, so the 11 MB of Unifont are not held in memory */
static CTFontRef ExteriaFallbackProbe(NSUInteger index) {
    if (!ExteriaFallbackTried[index]) {
        ExteriaFallbackTried[index] = YES;
        NSString *path = [[NSBundle mainBundle] pathForResource:ExteriaFallbackFiles[index] ofType:nil];
        CGDataProviderRef provider = path ? CGDataProviderCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path]) : NULL;
        CGFontRef graphics = provider ? CGFontCreateWithDataProvider(provider) : NULL;
        if (provider) CGDataProviderRelease(provider);
        if (graphics) {
            ExteriaFallbackGraphics[index] = graphics;
            ExteriaFallbackProbes[index] = CTFontCreateWithGraphicsFont(graphics, PROBE_SIZE, NULL, NULL);
        }
        if (!ExteriaFallbackProbes[index]) NSLog(@"exteria: fallback font %@ did not load", ExteriaFallbackFiles[index]);
    }
    return ExteriaFallbackProbes[index];
}

static BOOL ExteriaFontHasGlyph(CTFontRef font, const UniChar *chars, CFIndex count) {
    CGGlyph glyphs[2] = {0, 0};
    CTFontGetGlyphsForCharacters(font, chars, glyphs, count);
    /* a pair of units maps to one glyph, kept at the first of them */
    return glyphs[0] != 0;
}

/* the font the system would substitute is the box font when it has nothing for the character, and the box font maps every code
   point, so its name has to be told apart */
static BOOL ExteriaSystemDraws(CTFontRef base, const UniChar *chars, CFIndex count) {
    CFStringRef text = CFStringCreateWithCharacters(NULL, chars, count);
    CTFontRef substitute = text ? CTFontCreateForString(base, text, CFRangeMake(0, count)) : NULL;
    BOOL draws = NO;
    if (substitute) {
        CFStringRef name = CTFontCopyPostScriptName(substitute);
        BOOL box = name && CFStringFind(name, CFSTR("LastResort"), 0).length > 0;
        if (name) CFRelease(name);
        draws = !box && ExteriaFontHasGlyph(substitute, chars, count);
        CFRelease(substitute);
    }
    if (text) CFRelease(text);
    return draws;
}

static NSUInteger ExteriaLookup(uint32_t cp, CTFontRef base, NSMutableDictionary *answers) {
    NSNumber *key = [NSNumber numberWithUnsignedInt:cp];
    NSNumber *known = [answers objectForKey:key];
    if (known) return [known unsignedIntegerValue];
    UniChar chars[2];
    CFIndex count = 1;
    if (cp > 0xFFFF) {
        chars[0] = (UniChar)(0xD800 + ((cp - 0x10000) >> 10));
        chars[1] = (UniChar)(0xDC00 + ((cp - 0x10000) & 0x3FF));
        count = 2;
    } else {
        chars[0] = (UniChar)cp;
    }
    NSUInteger answer = FALLBACK_MISSING;
    if (ExteriaFontHasGlyph(base, chars, count) || ExteriaSystemDraws(base, chars, count)) {
        answer = FALLBACK_NONE;
    } else {
        for (NSUInteger i = 0; i < FALLBACK_COUNT; ++i) {
            CTFontRef probe = ExteriaFallbackProbe(i);
            if (probe && ExteriaFontHasGlyph(probe, chars, count)) {
                answer = i + 1;
                break;
            }
        }
    }
    [answers setObject:[NSNumber numberWithUnsignedInteger:answer] forKey:key];
    ExteriaCoverageChanged();
    return answer;
}

static CTFontRef ExteriaSizedFallback(NSUInteger index, CGFloat size) {
    NSString *key = [NSString stringWithFormat:@"%lu@%.2f", (unsigned long)index, size];
    CTFontRef font = (CTFontRef)[ExteriaSizedFonts objectForKey:key];
    if (font) return font;
    if (!ExteriaFallbackProbe(index)) return NULL;
    font = CTFontCreateWithGraphicsFont(ExteriaFallbackGraphics[index], size, NULL, NULL);
    if (!font) return NULL;
    [ExteriaSizedFonts setObject:(id)font forKey:key];
    CFRelease(font);
    return font;
}

static void ExteriaSetFallbackRun(NSMutableAttributedString *string, NSUInteger from, NSUInteger to, NSUInteger answer, CGFloat size) {
    if (answer == FALLBACK_NONE || answer == FALLBACK_MISSING || to <= from) return;
    CTFontRef font = ExteriaSizedFallback(answer - 1, size);
    if (font) [string addAttribute:(id)kCTFontAttributeName value:(id)font range:NSMakeRange(from, to - from)];
}

/* the answers of one base font family; the caller holds the lock; the weights of a family cover the same
   characters, and a name set in the regular */
static NSMutableDictionary *ExteriaAnswersFor(CTFontRef base) {
    CFStringRef name = CTFontCopyFamilyName(base);
    NSString *baseName = name ? [NSString stringWithString:(NSString *)name] : @"";
    if (name) CFRelease(name);
    NSMutableDictionary *answers = [ExteriaCoverage objectForKey:baseName];
    if (!answers) {
        answers = [NSMutableDictionary dictionary];
        [ExteriaCoverage setObject:answers forKey:baseName];
    }
    return answers;
}

void ExteriaApplyFontFallback(NSMutableAttributedString *string, CTFontRef base, CGFloat size) {
    NSUInteger length = string.length;
    if (!length || !base) return;
    uint16_t *units = malloc(sizeof(uint16_t) * length);
    if (!units) {
        NSLog(@"exteria: no room to look for fallback fonts in %lu units of text", (unsigned long)length);
        return;
    }
    [string.string getCharacters:units range:NSMakeRange(0, length)];
    @synchronized (ExteriaFallbackLock()) {
        NSMutableDictionary *answers = ExteriaAnswersFor(base);
        NSUInteger runStart = 0, runAnswer = FALLBACK_NONE;
        size_t at = 0;
        while (at < length) {
            uint32_t cp;
            size_t used = exteria_utf16_next(units, length, at, &cp);
            NSUInteger want = FALLBACK_NONE;
            switch (exteria_cp_class_of(cp)) {
            case EXTERIA_CP_CHECK: want = ExteriaLookup(cp, base, answers); break;
            /* a joiner or a selector has no shape of its own and stays in the font of the character before it */
            case EXTERIA_CP_ATTACH: want = runAnswer; break;
            case EXTERIA_CP_PLAIN: break;
            }
            if (want != runAnswer) {
                ExteriaSetFallbackRun(string, runStart, at, runAnswer, size);
                runStart = at;
                runAnswer = want;
            }
            at += used;
        }
        ExteriaSetFallbackRun(string, runStart, length, runAnswer, size);
    }
    free(units);
}

/* marks that take room in no font and say nothing in a name; the joiner and the selectors stay, since emoji sequences are built with them */
static BOOL ExteriaIsInvisibleMark(uint32_t cp) {
    return cp == 0x00AD || cp == 0x061C || cp == 0x180E || cp == 0x200B || cp == 0x200C || (cp >= 0x200E && cp <= 0x200F) ||
           (cp >= 0x202A && cp <= 0x202E) || (cp >= 0x2060 && cp <= 0x2064) || (cp >= 0x2066 && cp <= 0x206F) || cp == 0xFEFF ||
           (cp >= 0xE0000 && cp <= 0xE007F);
}

void ExteriaDropUndrawableCharacters(NSMutableAttributedString *string, CTFontRef base) {
    NSUInteger length = string.length;
    if (!length || !base) return;
    uint16_t *units = malloc(sizeof(uint16_t) * length);
    if (!units) {
        NSLog(@"exteria: no room to look for undrawable characters in %lu units of text", (unsigned long)length);
        return;
    }
    [string.string getCharacters:units range:NSMakeRange(0, length)];
    NSMutableArray *dropped = [NSMutableArray array];
    @synchronized (ExteriaFallbackLock()) {
        NSMutableDictionary *answers = ExteriaAnswersFor(base);
        static NSMutableSet *logged;
        if (!logged) logged = [[NSMutableSet alloc] init];
        size_t at = 0;
        while (at < length) {
            uint32_t cp;
            size_t used = exteria_utf16_next(units, length, at, &cp);
            BOOL invisible = ExteriaIsInvisibleMark(cp);
            BOOL missing = !invisible && exteria_cp_class_of(cp) == EXTERIA_CP_CHECK && ExteriaLookup(cp, base, answers) == FALLBACK_MISSING;
            if (invisible || missing) {
                [dropped addObject:[NSValue valueWithRange:NSMakeRange(at, used)]];
                NSNumber *key = [NSNumber numberWithUnsignedInt:cp];
                if (![logged containsObject:key]) {
                    [logged addObject:key];
                    NSLog(@"exteria: a name is drawn without U+%04X (%@)", cp, invisible ? @"invisible mark" : @"no font has a glyph");
                }
            }
            at += used;
        }
    }
    free(units);
    for (NSValue *range in [dropped reverseObjectEnumerator]) [string deleteCharactersInRange:[range rangeValue]];
}
