#import "exteria_translate_languages_controller.h"

#import "exteria_language.h"
#import "exteria_translate_config.h"
#import "exteria_weak_reference.h"

@interface ExteriaTranslateLanguagesController () {
    ExteriaTranslateLanguagesMode _mode;
    ExteriaWeakReference *_weak;
    NSArray *_order;
    NSMutableArray *_chosen;
}
@end

@implementation ExteriaTranslateLanguagesController

- (id)initWithMode:(ExteriaTranslateLanguagesMode)mode {
    self = [super init];
    if (!self) return nil;
    _mode = mode;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(mode == ExteriaTranslateLanguagesTarget ? @"tr.target.title" : @"tr.skip.title", nil);
    self.searchable = YES;
    _chosen = [[NSMutableArray alloc] initWithArray:ExteriaTranslateSkippedLanguages()];
    _order = [[self orderedCodes] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_order release];
    [_chosen release];
    [super dealloc];
}

/* the display name is looked up once for the sort, which asks for it many times */
- (NSArray *)sortedByName:(NSArray *)codes {
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSString *code in codes) [names setObject:ExteriaLanguageName(code) forKey:code];
    return [codes sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [[names objectForKey:a] localizedCaseInsensitiveCompare:[names objectForKey:b]];
    }];
}

/* target mode: the preferred languages first, then the rest by name */
- (NSArray *)orderedCodes {
    NSMutableArray *all = [NSMutableArray arrayWithArray:ExteriaTranslationLanguageCodes()];
    NSMutableArray *front = [NSMutableArray array];
    if (_mode == ExteriaTranslateLanguagesTarget) {
        for (NSString *code in ExteriaTranslatePreferredLanguages()) {
            NSString *match = nil;
            for (NSString *known in all) {
                if ([ExteriaNormalizedLanguageCode(known) isEqualToString:code]) { match = known; break; }
            }
            if (match && ![front containsObject:match]) [front addObject:match];
        }
    } else {
        NSString *own = ExteriaInterfaceLanguage();
        for (NSString *code in _chosen) {
            if ([ExteriaNormalizedLanguageCode(code) isEqualToString:own]) { [front insertObject:code atIndex:0]; continue; }
            [front addObject:code];
        }
    }
    NSMutableSet *taken = [NSMutableSet set];
    for (NSString *code in front) [taken addObject:ExteriaNormalizedLanguageCode(code)];
    NSMutableArray *rest = [NSMutableArray array];
    for (NSString *code in all) {
        if (![taken containsObject:ExteriaNormalizedLanguageCode(code)]) [rest addObject:code];
    }
    all = rest;
    NSMutableArray *ordered = [NSMutableArray arrayWithArray:front];
    [ordered addObjectsFromArray:[self sortedByName:all]];
    return ordered;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (BOOL)isChosen:(NSString *)code {
    if (_mode == ExteriaTranslateLanguagesTarget) {
        NSString *choice = ExteriaTranslateTargetChoice();
        return choice.length && [ExteriaNormalizedLanguageCode(choice) isEqualToString:ExteriaNormalizedLanguageCode(code)];
    }
    NSString *wanted = ExteriaNormalizedLanguageCode(code);
    for (NSString *chosen in _chosen) {
        if ([ExteriaNormalizedLanguageCode(chosen) isEqualToString:wanted]) return YES;
    }
    return NO;
}

- (ExteriaSettingsRow *)rowForCode:(NSString *)code {
    ExteriaWeakReference *weak = _weak;
    NSString *own = ExteriaNativeLanguageName(code);
    NSString *name = ExteriaLanguageName(code);
    NSString *line = [own isEqualToString:name] ? nil : own;
    BOOL star = _mode == ExteriaTranslateLanguagesTarget && [ExteriaTranslatePreferredLanguages() containsObject:ExteriaNormalizedLanguageCode(code)];
    NSString *title = star ? [@"⭐ " stringByAppendingString:name] : name;
    return [ExteriaSettingsRow checkRowWithTitle:title subtitle:line checked:[self isChosen:code] tap:^{
        [(ExteriaTranslateLanguagesController *)weak.target pick:code];
    }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    if (_mode == ExteriaTranslateLanguagesTarget) {
        NSString *app = ExteriaLanguageName(ExteriaInterfaceLanguage());
        ExteriaSettingsRow *follow = [ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"tr.target.app", nil) subtitle:app
                                                                   checked:ExteriaTranslateTargetChoice().length == 0
                                                                       tap:^{ [(ExteriaTranslateLanguagesController *)weak.target pick:@""]; }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:follow]]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *code in _order) [rows addObject:[self rowForCode:code]];
    NSString *footer = _mode == ExteriaTranslateLanguagesSkipped ? NSLocalizedString(@"tr.skip.info", nil) : nil;
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    self.sections = sections;
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSString *wanted = [query lowercaseString];
    NSMutableArray *starts = [NSMutableArray array], *contains = [NSMutableArray array];
    for (NSString *code in _order) {
        NSString *name = [ExteriaLanguageName(code) lowercaseString];
        NSString *own = [ExteriaNativeLanguageName(code) lowercaseString];
        NSString *english = [ExteriaEnglishLanguageName(code) lowercaseString];
        if ([name hasPrefix:wanted] || [own hasPrefix:wanted] || [english hasPrefix:wanted] || [[code lowercaseString] hasPrefix:wanted]) [starts addObject:[self rowForCode:code]];
        else if ([name rangeOfString:wanted].location != NSNotFound || [own rangeOfString:wanted].location != NSNotFound
                 || [english rangeOfString:wanted].location != NSNotFound) [contains addObject:[self rowForCode:code]];
    }
    [starts addObjectsFromArray:contains];
    return starts.count ? [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:starts]] : [NSArray array];
}

- (void)pick:(NSString *)code {
    if (_mode == ExteriaTranslateLanguagesTarget) {
        ExteriaTranslateSetTargetChoice(code);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSString *wanted = ExteriaNormalizedLanguageCode(code);
    NSString *found = nil;
    for (NSString *chosen in _chosen) {
        if ([ExteriaNormalizedLanguageCode(chosen) isEqualToString:wanted]) { found = chosen; break; }
    }
    if (found) [_chosen removeObject:found];
    else [_chosen addObject:[code lowercaseString]];
    ExteriaTranslateSetSkippedLanguages(_chosen);
    [self rebuild];
    /* the search results hold rows made before the toggle, so they are asked for again */
    [self reloadSearchResults];
}

@end
