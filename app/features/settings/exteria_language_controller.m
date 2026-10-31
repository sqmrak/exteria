#import "exteria_language_controller.h"

#import "exteria_language.h"
#import "exteria_alert.h"
#import "exteria_classic_chrome.h"
#import "exteria_file_picker.h"
#import "exteria_logs_controller.h"
#import "exteria_theme.h"
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
    BOOL custom = ExteriaIsCustomLanguage(code);
    return [ExteriaSettingsRow checkRowWithTitle:ExteriaNativeLanguageName(code) subtitle:ExteriaEnglishLanguageName(code)
                                         checked:[code isEqualToString:ExteriaInterfaceLanguageVariant()]
                                             tap:^{
        ExteriaLanguageSettingsController *me = weak.target;
        if (!me) return;
        if (!custom) {
            [me choose:code];
            return;
        }
        /* a language that came from a file can also be taken away */
        ExteriaSettingsChoose(me, ExteriaNativeLanguageName(code), [NSArray arrayWithObjects:NSLocalizedString(@"language.custom.use", nil), NSLocalizedString(@"language.custom.remove", nil), nil], ^(NSUInteger index) {
            ExteriaLanguageSettingsController *screen = weak.target;
            if (!screen) return;
            if (index == 0) [screen choose:code];
            else {
                ExteriaRemoveCustomLanguage(code);
                [screen rebuild];
            }
        });
    }];
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
    ExteriaSettingsRow *import = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolDocument tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"language.custom.import", nil)
                                                          subtitle:NSLocalizedString(@"language.custom.import.info", nil) value:nil tap:^{ [(ExteriaLanguageSettingsController *)weak.target importLanguageFile]; }];
    ExteriaSettingsRow *template = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolShare tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"language.custom.template", nil)
                                                            subtitle:NSLocalizedString(@"language.custom.template.info", nil) value:nil tap:^{
        ExteriaLanguageSettingsController *me = weak.target;
        NSString *path = ExteriaCustomLanguageTemplatePath();
        if (!me) return;
        if (path) ExteriaShareFile(me, path);
        else ExteriaShowNotice(nil, NSLocalizedString(@"language.custom.unreadable", nil));
    }];
    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"tr.messages", nil) footer:nil rows:[NSArray arrayWithObject:translator]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"language.title", nil) footer:nil rows:languages],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"language.custom.header", nil) footer:NSLocalizedString(@"language.custom.footer", nil)
                                             rows:[NSArray arrayWithObjects:import, template, nil]], nil];
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

/* a .strings file with the texts of the app in another language: the same browser as the one that picks a file to send, asking for a language */
- (void)importLanguageFile {
    ExteriaWeakReference *weak = _weak;
    ExteriaFilePicker *picker = [[[ExteriaFilePicker alloc] initWithDirectory:nil handler:^(NSString *path) {
        ExteriaLanguageSettingsController *me = weak.target;
        if (!me) return;
        NSUInteger accepted = 0, skipped = 0;
        NSString *error = ExteriaInstallCustomLanguage(path, &accepted, &skipped);
        if (error) {
            ExteriaShowNotice(NSLocalizedString(@"language.custom.import", nil), error);
            return;
        }
        [me rebuild];
        ExteriaShowNotice(NSLocalizedString(@"language.custom.import", nil), [NSString stringWithFormat:NSLocalizedString(@"language.custom.done", nil), (long)accepted, (long)skipped]);
    } cancel:nil] autorelease];
    picker.extensions = [NSArray arrayWithObject:@"strings"];
    picker.rootTitle = NSLocalizedString(@"language.custom.pick", nil);
    picker.searchPlaceholder = NSLocalizedString(@"language.custom.search", nil);
    picker.emptyText = NSLocalizedString(@"language.custom.empty.files", nil);
    picker.fileSymbol = ExteriaSymbolSettingsLanguage;
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:picker] autorelease];
    if (ExteriaThemeIsClassic()) ExteriaClassicStyleNavigationBar(navigation.navigationBar);
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)choose:(NSString *)code {
    if ([ExteriaInterfaceLanguageVariant() isEqualToString:code]) return;
    NSString *previous = ExteriaInterfaceLanguage();
    ExteriaSetInterfaceLanguage(code);
    ExteriaTranslateInterfaceLanguageChanged(previous, ExteriaInterfaceLanguage());
}

@end
