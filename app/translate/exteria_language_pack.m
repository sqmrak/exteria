#import "exteria_language_pack.h"

#import "exteria_language.h"

#include "exteria_langpack.h"

NSString *ExteriaInterfaceLanguageForPackCode(NSString *packCode) {
    NSString *wanted = ExteriaNormalizedLanguageCode(packCode);
    if (!wanted.length) return nil;
    for (NSString *code in ExteriaInterfaceLanguageCodes()) {
        if (ExteriaIsCustomLanguage(code)) continue;
        if ([ExteriaNormalizedLanguageCode(code) isEqualToString:wanted]) return code;
    }
    return nil;
}

static NSDictionary *ExteriaStringsOf(NSString *code) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:code];
    NSDictionary *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    if (path && !strings) NSLog(@"exteria: the texts of %@ could not be read from %@", code, path);
    return strings;
}

int ExteriaInterfaceLanguageCompleteness(NSString *code) {
    NSDictionary *english = ExteriaStringsOf(@"en"), *own = ExteriaStringsOf(code);
    if (!english.count || !own.count) return 0;
    if ([code isEqualToString:@"en"]) return 100;
    NSUInteger translated = 0;
    for (NSString *key in english) {
        NSString *text = [own objectForKey:key];
        if ([text isKindOfClass:[NSString class]] && text.length) ++translated;
    }
    return exteria_langpack_percent((int32_t)translated, (int32_t)english.count);
}
