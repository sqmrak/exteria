#import "exteria_language.h"

#import <objc/runtime.h>

#include <string.h>

NSString *const ExteriaLanguageDidChangeNotification = @"ExteriaLanguageDidChange";

static NSString *const ExteriaLanguageKey = @"exteria.language";

/* the playful russian: its texts have an lproj of their own, and everything that is not a text (plurals, dates, the translator, the notifications) treats it as russian */
static NSString *const ExteriaPlayfulRussian = @"sqmrak";

static NSString *const ExteriaCustomLanguagesKey = @"exteria.language.custom";
#define CUSTOM_FILE_BYTES_MAX (2 * 1024 * 1024)
#define CUSTOM_KEYS_MAX 20000
#define CUSTOM_LANGUAGES_MAX 12

static NSString *ExteriaCustomDirectory(void) {
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [[support stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"Languages"];
}

static NSString *ExteriaCustomBundlePath(NSString *code) {
    return [[ExteriaCustomDirectory() stringByAppendingPathComponent:code] stringByAppendingPathExtension:@"lproj"];
}

/* code -> {name, english, base} */
static NSDictionary *ExteriaCustomLanguages(void) {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:ExteriaCustomLanguagesKey];
    return all ? all : [NSDictionary dictionary];
}

NSArray *ExteriaCustomLanguageCodes(void) {
    return [[ExteriaCustomLanguages() allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

BOOL ExteriaIsCustomLanguage(NSString *code) {
    return code && [ExteriaCustomLanguages() objectForKey:code] != nil;
}

NSArray *ExteriaInterfaceLanguageCodes(void) {
    return [[NSArray arrayWithObjects:@"en", @"ru", ExteriaPlayfulRussian, nil] arrayByAddingObjectsFromArray:ExteriaCustomLanguageCodes()];
}

NSString *ExteriaInterfaceLanguageChoice(void) {
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:ExteriaLanguageKey];
    return [ExteriaInterfaceLanguageCodes() containsObject:code] ? code : @"";
}

NSString *ExteriaInterfaceLanguage(void) {
    NSString *choice = ExteriaInterfaceLanguageChoice();
    if ([choice isEqualToString:ExteriaPlayfulRussian]) return @"ru";
    if (ExteriaIsCustomLanguage(choice)) {
        NSString *base = [[ExteriaCustomLanguages() objectForKey:choice] objectForKey:@"base"];
        return base.length ? base : @"en";
    }
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

static NSBundle *ExteriaEnglishBundle;

@implementation ExteriaLocalizedBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    NSBundle *chosen = ExteriaChosenBundle;
    if (!chosen) return [super localizedStringForKey:key value:value table:table];
    NSString *text = [chosen localizedStringForKey:key value:value table:table];
    /* a text the chosen language lacks (a custom one translates what it can) is the English one, not the bare key */
    if ((!text.length || [text isEqualToString:key]) && ExteriaEnglishBundle && chosen != ExteriaEnglishBundle) return [ExteriaEnglishBundle localizedStringForKey:key value:value table:table];
    return text;
}
@end

NSString *ExteriaInterfaceLanguageVariant(void) {
    NSString *choice = ExteriaInterfaceLanguageChoice();
    return choice.length ? choice : ExteriaInterfaceLanguage();
}

void ExteriaApplyInterfaceLanguage(void) {
    NSString *choice = ExteriaInterfaceLanguageChoice();
    NSBundle *main = [NSBundle mainBundle];
    if (!choice.length) {
        [ExteriaChosenBundle release];
        ExteriaChosenBundle = nil;
        return;
    }
    if (!ExteriaEnglishBundle) {
        NSString *english = [main pathForResource:@"en" ofType:@"lproj"];
        ExteriaEnglishBundle = english ? [[NSBundle bundleWithPath:english] retain] : nil;
    }
    NSString *path = ExteriaIsCustomLanguage(choice) ? ExteriaCustomBundlePath(choice) : [main pathForResource:choice ofType:@"lproj"];
    NSBundle *bundle = path ? [NSBundle bundleWithPath:path] : nil;
    if (!bundle) {
        NSLog(@"exteria: no texts for the language %@", choice);
        [ExteriaChosenBundle release];
        ExteriaChosenBundle = nil;
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

/* the placeholders of a text in order, as the letters that end each: "%@ of %lld" gives "@", "d" */
static NSString *ExteriaPlaceholders(NSString *text) {
    NSMutableString *kinds = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; ++i) {
        if ([text characterAtIndex:i] != '%') continue;
        ++i;
        while (i < text.length && strchr("-+ #0123456789.$lhqLzjt", (int)[text characterAtIndex:i]) && [text characterAtIndex:i] < 128) ++i;
        if (i >= text.length) return nil;
        unichar kind = [text characterAtIndex:i];
        if (kind == '%') continue;
        [kinds appendFormat:@"%C", kind];
    }
    return kinds;
}

static NSDictionary *ExteriaEnglishTexts(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"];
    return path ? [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Localizable.strings"]] : nil;
}

NSString *ExteriaInstallCustomLanguage(NSString *path, NSUInteger *accepted, NSUInteger *skipped) {
    if (accepted) *accepted = 0;
    if (skipped) *skipped = 0;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (!attributes) return NSLocalizedString(@"language.custom.unreadable", nil);
    if ([attributes fileSize] > CUSTOM_FILE_BYTES_MAX) return NSLocalizedString(@"language.custom.large", nil);
    NSDictionary *texts = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![texts isKindOfClass:[NSDictionary class]] || !texts.count) return NSLocalizedString(@"language.custom.unreadable", nil);
    if (texts.count > CUSTOM_KEYS_MAX) return NSLocalizedString(@"language.custom.large", nil);
    NSDictionary *english = ExteriaEnglishTexts();
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-_"];
    NSString *stem = [[path lastPathComponent] stringByDeletingPathExtension];
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < stem.length && name.length < 32; ++i) {
        unichar c = [stem characterAtIndex:i];
        if (c < 128 && [allowed characterIsMember:c]) [name appendFormat:@"%C", c];
    }
    if (!name.length) return NSLocalizedString(@"language.custom.name", nil);
    NSString *code = [@"x-" stringByAppendingString:[name lowercaseString]];
    BOOL replacing = ExteriaIsCustomLanguage(code);
    if (!replacing && ExteriaCustomLanguageCodes().count >= CUSTOM_LANGUAGES_MAX) return NSLocalizedString(@"language.custom.many", nil);
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    NSUInteger skippedCount = 0;
    for (id key in texts) {
        id value = [texts objectForKey:key];
        if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]] || ![(NSString *)value length]) continue;
        NSString *original = [english objectForKey:key];
        if (!original) continue;
        if (![ExteriaPlaceholders(value) isEqualToString:ExteriaPlaceholders(original)]) { ++skippedCount; continue; }
        [kept setObject:value forKey:key];
    }
    if (!kept.count) return NSLocalizedString(@"language.custom.empty", nil);
    NSString *own = [texts objectForKey:@"language.name"], *englishName = [texts objectForKey:@"language.english"], *base = [texts objectForKey:@"language.base"];
    if (![own isKindOfClass:[NSString class]] || !own.length) own = stem;
    if (![englishName isKindOfClass:[NSString class]] || !englishName.length) englishName = own;
    base = [base isKindOfClass:[NSString class]] && [ExteriaTranslationLanguageCodes() containsObject:base] ? base : @"en";
    NSString *bundlePath = ExteriaCustomBundlePath(code);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:bundlePath withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: custom language directory: %@", error);
        return NSLocalizedString(@"language.custom.save", nil);
    }
    if (![kept writeToFile:[bundlePath stringByAppendingPathComponent:@"Localizable.strings"] atomically:YES]) return NSLocalizedString(@"language.custom.save", nil);
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:ExteriaCustomLanguages()];
    [all setObject:[NSDictionary dictionaryWithObjectsAndKeys:own, @"name", englishName, @"english", base, @"base", nil] forKey:code];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:ExteriaCustomLanguagesKey];
    if (accepted) *accepted = kept.count;
    if (skipped) *skipped = skippedCount;
    /* a pack that is in force again is read again from its new file */
    if ([ExteriaInterfaceLanguageChoice() isEqualToString:code]) ExteriaApplyInterfaceLanguage();
    return nil;
}

void ExteriaRemoveCustomLanguage(NSString *code) {
    if (!ExteriaIsCustomLanguage(code)) return;
    BOOL inForce = [ExteriaInterfaceLanguageChoice() isEqualToString:code];
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:ExteriaCustomLanguages()];
    [all removeObjectForKey:code];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:ExteriaCustomLanguagesKey];
    [[NSFileManager defaultManager] removeItemAtPath:ExteriaCustomBundlePath(code) error:NULL];
    if (inForce) ExteriaSetInterfaceLanguage(@"");
}

NSString *ExteriaCustomLanguageTemplatePath(NSString *language) {
    NSString *source = [[[NSBundle mainBundle] pathForResource:language ofType:@"lproj"] stringByAppendingPathComponent:@"Localizable.strings"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:source]) return nil;
    NSString *target = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-template-%@.strings", language]];
    [[NSFileManager defaultManager] removeItemAtPath:target error:NULL];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:source toPath:target error:&error]) {
        NSLog(@"exteria: language template: %@", error);
        return nil;
    }
    return target;
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
    if (ExteriaIsCustomLanguage(code)) return [[ExteriaCustomLanguages() objectForKey:code] objectForKey:@"name"];
    if ([code isEqualToString:ExteriaPlayfulRussian]) return @"русский by sqmrak :3";
    return ExteriaNameIn(code, code);
}

NSString *ExteriaEnglishLanguageName(NSString *code) {
    if (ExteriaIsCustomLanguage(code)) return [[ExteriaCustomLanguages() objectForKey:code] objectForKey:@"english"];
    if ([code isEqualToString:ExteriaPlayfulRussian]) return @"Russian by sqmrak";
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
