#import "exteria_language.h"

#import <objc/runtime.h>

NSString *const ExteriaLanguageDidChangeNotification = @"ExteriaLanguageDidChange";

static NSString *const ExteriaLanguageKey = @"exteria.language";

NSArray *ExteriaInterfaceLanguageCodes(void) {
    return [NSArray arrayWithObjects:@"en", @"ru", nil];
}

NSString *ExteriaInterfaceLanguageChoice(void) {
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:ExteriaLanguageKey];
    return [ExteriaInterfaceLanguageCodes() containsObject:code] ? code : @"";
}

NSString *ExteriaInterfaceLanguage(void) {
    NSString *choice = ExteriaInterfaceLanguageChoice();
    if (choice.length) return choice;
    for (NSString *language in [NSLocale preferredLanguages]) {
        NSString *base = [[language componentsSeparatedByString:@"-"] objectAtIndex:0];
        if ([ExteriaInterfaceLanguageCodes() containsObject:base]) return base;
    }
    return @"en";
}

/* the main bundle answers the texts of the chosen lproj; its class is swapped once for this one, which is how NSLocalizedString can follow a choice made
   while the app runs */
static NSBundle *ExteriaChosenBundle;

@interface ExteriaLocalizedBundle : NSBundle
@end

@implementation ExteriaLocalizedBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    NSBundle *chosen = ExteriaChosenBundle;
    return chosen ? [chosen localizedStringForKey:key value:value table:table] : [super localizedStringForKey:key value:value table:table];
}
@end

void ExteriaApplyInterfaceLanguage(void) {
    NSString *choice = ExteriaInterfaceLanguageChoice();
    NSBundle *main = [NSBundle mainBundle];
    if (!choice.length) {
        [ExteriaChosenBundle release];
        ExteriaChosenBundle = nil;
        return;
    }
    NSString *path = [main pathForResource:choice ofType:@"lproj"];
    NSBundle *bundle = path ? [NSBundle bundleWithPath:path] : nil;
    if (!bundle) {
        NSLog(@"exteria: no texts for the language %@", choice);
        return;
    }
    [ExteriaChosenBundle release];
    ExteriaChosenBundle = [bundle retain];
    if (object_getClass(main) != [ExteriaLocalizedBundle class]) object_setClass(main, [ExteriaLocalizedBundle class]);
}

void ExteriaSetInterfaceLanguage(NSString *code) {
    NSString *kept = [ExteriaInterfaceLanguageCodes() containsObject:code] ? code : @"";
    [[NSUserDefaults standardUserDefaults] setObject:kept forKey:ExteriaLanguageKey];
    ExteriaApplyInterfaceLanguage();
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaLanguageDidChangeNotification object:nil];
}

NSLocale *ExteriaFormattingLocale(void) {
    NSArray *languages = [NSLocale preferredLanguages];
    NSString *system = languages.count ? [[[languages objectAtIndex:0] componentsSeparatedByString:@"-"] objectAtIndex:0] : @"en";
    NSString *own = ExteriaInterfaceLanguage();
    if ([system isEqualToString:own]) return [NSLocale currentLocale];
    return [[[NSLocale alloc] initWithLocaleIdentifier:own] autorelease];
}

NSArray *ExteriaTranslationLanguageCodes(void) {
    static NSArray *codes;
    if (!codes) {
        codes = [[@"sq ar am az ga et eu be bg is pl bs fa af da de ru fr tl fi fy km ka gu kk ht ko ha nl ky gl ca cs kn co hr ku la lv lo lt lb ro mg mt mr ml ms mk mi mn "
                   "bn my hmn xh zu ne no pa pt ps ny ja sv sm sr st si eo sk sl sw gd ceb so tg te ta th tr cy ur uk uz es iw el haw sd hu sn hy ig it yi hi su id jw en yo vi "
                   "zh-TW zh-CN zh" componentsSeparatedByString:@" "] retain];
    }
    return codes;
}

NSString *ExteriaNormalizedLanguageCode(NSString *code) {
    return [[code stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
}

static NSString *ExteriaCapitalized(NSString *name) {
    if (!name.length) return name;
    return [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]];
}

static NSString *ExteriaNameIn(NSString *code, NSString *inLanguage) {
    NSString *fixed = [code stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    /* "iw" and "jw" are the old codes of Hebrew and Javanese that the translators still use */
    if ([fixed isEqualToString:@"iw"]) fixed = @"he";
    if ([fixed isEqualToString:@"jw"]) fixed = @"jv";
    NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:inLanguage] autorelease];
    NSString *name = [locale displayNameForKey:NSLocaleIdentifier value:[fixed stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
    return name.length ? ExteriaCapitalized(name) : code;
}

NSString *ExteriaLanguageName(NSString *code) {
    return ExteriaNameIn(code, ExteriaInterfaceLanguage());
}

NSString *ExteriaNativeLanguageName(NSString *code) {
    return ExteriaNameIn(code, code);
}

NSString *ExteriaEnglishLanguageName(NSString *code) {
    return ExteriaNameIn(code, @"en");
}

NSString *ExteriaGuessLanguageOfText(NSString *text) {
    NSUInteger cyrillic = 0, latin = 0, greek = 0, hebrew = 0, arabic = 0, thai = 0, hangul = 0, kana = 0, han = 0, ukrainian = 0;
    NSUInteger length = MIN(text.length, 400);
    for (NSUInteger i = 0; i < length; ++i) {
        unichar c = [text characterAtIndex:i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= 0xC0 && c <= 0x24F)) ++latin;
        else if (c >= 0x400 && c <= 0x4FF) { ++cyrillic; if (c == 0x456 || c == 0x457 || c == 0x454 || c == 0x491 || c == 0x406 || c == 0x407 || c == 0x404 || c == 0x490) ++ukrainian; }
        else if (c >= 0x370 && c <= 0x3FF) ++greek;
        else if (c >= 0x590 && c <= 0x5FF) ++hebrew;
        else if (c >= 0x600 && c <= 0x6FF) ++arabic;
        else if (c >= 0xE00 && c <= 0xE7F) ++thai;
        else if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF)) ++hangul;
        else if (c >= 0x3040 && c <= 0x30FF) ++kana;
        else if (c >= 0x4E00 && c <= 0x9FFF) ++han;
    }
    NSUInteger total = cyrillic + latin + greek + hebrew + arabic + thai + hangul + kana + han;
    if (total < 2) return nil;
    NSUInteger best = MAX(MAX(MAX(cyrillic, latin), MAX(greek, hebrew)), MAX(MAX(arabic, thai), MAX(hangul, MAX(kana, han))));
    /* a text of no clear majority is a mix, which no guess can serve */
    if (best * 10 < total * 6) return nil;
    if (best == cyrillic) return ukrainian > 0 ? @"uk" : @"ru";
    if (best == latin) return @"en";
    if (best == greek) return @"el";
    if (best == hebrew) return @"iw";
    if (best == arabic) return @"ar";
    if (best == thai) return @"th";
    if (best == hangul) return @"ko";
    if (kana > 0) return @"ja";
    return @"zh";
}
