#import "exteria_ayu.h"

#import "exteria_chat_settings.h"

static NSString *const ExteriaAyuRegexKey = @"exteria.ayu.regexlist";
#define PATTERNS_MAX 50
#define PATTERN_LENGTH_MAX 200

NSArray *ExteriaAyuRegexList(void) {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:ExteriaAyuRegexKey];
    NSMutableArray *list = [NSMutableArray array];
    for (id item in stored) if ([item isKindOfClass:[NSString class]] && [(NSString *)item length]) [list addObject:item];
    return list;
}

/* the compiled expressions are kept with the list they came from, so a change of the list builds them again */
static NSArray *ExteriaAyuCompiledFrom;
static NSArray *ExteriaAyuCompiled;
/* what the list said of a text. the chat asks for every loaded message at every rebuild, and running up to fifty expressions over each of thousands of texts took the main
   thread; the list is only written by ExteriaAyuSetRegexList, which empties this */
static NSCache *ExteriaAyuVerdicts;
#define VERDICTS_MAX 8192

void ExteriaAyuSetRegexList(NSArray *patterns) {
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *pattern in patterns) {
        if (pattern.length && pattern.length <= PATTERN_LENGTH_MAX && list.count < PATTERNS_MAX) [list addObject:pattern];
    }
    [ExteriaAyuVerdicts removeAllObjects];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:ExteriaAyuRegexKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the filters were not saved");
}

NSString *ExteriaAyuRegexProblem(NSString *pattern) {
    if (!pattern.length) return NSLocalizedString(@"ayu.regex.empty", nil);
    if (pattern.length > PATTERN_LENGTH_MAX) return NSLocalizedString(@"ayu.regex.long", nil);
    NSError *error = nil;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    return expression ? nil : NSLocalizedString(@"ayu.regex.bad", nil);
}

BOOL ExteriaAyuHidesText(NSString *text) {
    if (!text.length || !ExteriaChatFlagGet(ExteriaChatFlagAyuRegex)) return NO;
    if (!ExteriaAyuVerdicts) {
        ExteriaAyuVerdicts = [[NSCache alloc] init];
        ExteriaAyuVerdicts.countLimit = VERDICTS_MAX;
    }
    NSNumber *known = [ExteriaAyuVerdicts objectForKey:text];
    if (known) return known.boolValue;
    NSArray *list = ExteriaAyuRegexList();
    if (!list.count) return NO;
    if (!ExteriaAyuCompiled || ![ExteriaAyuCompiledFrom isEqualToArray:list]) {
        NSMutableArray *compiled = [NSMutableArray array];
        for (NSString *pattern in list) {
            NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
            if (expression) [compiled addObject:expression];
        }
        [ExteriaAyuCompiledFrom release];
        [ExteriaAyuCompiled release];
        ExteriaAyuCompiledFrom = [list copy];
        ExteriaAyuCompiled = [compiled retain];
    }
    NSRange all = NSMakeRange(0, text.length);
    BOOL hides = NO;
    for (NSRegularExpression *expression in ExteriaAyuCompiled) {
        if ([expression firstMatchInString:text options:0 range:all]) { hides = YES; break; }
    }
    [ExteriaAyuVerdicts setObject:[NSNumber numberWithBool:hides] forKey:text];
    return hides;
}
