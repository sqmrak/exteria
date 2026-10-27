#import "exteria_language_controller.h"

#import "exteria_language.h"
#import "exteria_translate_config.h"
#import "exteria_translator_controller.h"
#import "exteria_weak_reference.h"

@interface ExteriaLanguageSettingsController () {
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaLanguageSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"language.title", nil);
    self.searchable = YES;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged) name:ExteriaLanguageDidChangeNotification object:nil];
    [self rebuild];
}

/* the provider shown on the translator row may have changed on the screen above */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

/* the title and every row are read again in the new language, and a search in the old words is closed closes it */
- (void)languageChanged {
    self.pageTitle = NSLocalizedString(@"language.title", nil);
    [self endSearch];
    [self rebuild];
}

- (ExteriaSettingsRow *)rowForCode:(NSString *)code {
    ExteriaWeakReference *weak = _weak;
    return [ExteriaSettingsRow checkRowWithTitle:ExteriaNativeLanguageName(code) subtitle:ExteriaEnglishLanguageName(code)
                                         checked:[code isEqualToString:ExteriaInterfaceLanguage()]
                                             tap:^{ [(ExteriaLanguageSettingsController *)weak.target choose:code]; }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *translator = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolTranslate tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"tr.title", nil) subtitle:nil
                                                                 value:ExteriaTranslateProviderName(ExteriaTranslateProviderChoice()) tap:^{
        ExteriaLanguageSettingsController *screen = weak.target;
        [screen.navigationController pushViewController:[[[ExteriaTranslatorSettingsController alloc] init] autorelease] animated:YES];
    }];
    NSMutableArray *languages = [NSMutableArray array];
    for (NSString *code in ExteriaInterfaceLanguageCodes()) [languages addObject:[self rowForCode:code]];
    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"tr.messages", nil) footer:nil rows:[NSArray arrayWithObject:translator]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"language.title", nil) footer:nil rows:languages], nil];
    [self reloadSearchResults];
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSString *wanted = [query lowercaseString];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *code in ExteriaInterfaceLanguageCodes()) {
        if ([[ExteriaNativeLanguageName(code) lowercaseString] hasPrefix:wanted] || [[ExteriaEnglishLanguageName(code) lowercaseString] hasPrefix:wanted]) {
            [rows addObject:[self rowForCode:code]];
        }
    }
    return rows.count ? [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:rows]] : [NSArray array];
}

- (void)choose:(NSString *)code {
    NSString *previous = ExteriaInterfaceLanguage();
    if ([previous isEqualToString:code]) return;
    ExteriaSetInterfaceLanguage(code);
    ExteriaTranslateInterfaceLanguageChanged(previous, ExteriaInterfaceLanguage());
}

@end
