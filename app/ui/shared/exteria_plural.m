#import "exteria_plural.h"

#import "exteria_language.h"

NSString *ExteriaPluralForm(NSInteger count) {
    if ([ExteriaInterfaceLanguage() isEqualToString:@"ru"]) {
        NSInteger tail = count % 100, last = count % 10;
        if (tail >= 11 && tail <= 14) return @"other";
        if (last == 1) return @"one";
        if (last >= 2 && last <= 4) return @"few";
        return @"other";
    }
    return count == 1 ? @"one" : @"other";
}
