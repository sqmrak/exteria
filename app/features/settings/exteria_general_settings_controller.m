#import "exteria_general_settings_controller.h"

#import "exteria_chat_settings.h"
#import "exteria_language.h"
#import "exteria_translate_config.h"
#import "exteria_translate_languages_controller.h"
#import "exteria_translator_controller.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"
#import "exteria_time.h"
#import "exteria_time_zone_controller.h"

/* a switch that sets a flag of the chat settings and tells what listens (the chat list, the demo dialog) */
static ExteriaSettingsRow *ExteriaGeneralFlagRow(NSString *titleKey, NSString *infoKey, ExteriaChatFlag flag) {
    return [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil
                                               on:ExteriaChatFlagGet(flag) toggle:^(BOOL on) {
        ExteriaChatFlagSet(flag, on);
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
    }];
}

@interface ExteriaGeneralSettingsController () {
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaGeneralSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"about.main", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* the translator page and the language lists change what the first section shows */
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaGeneralSettingsController alloc] init] autorelease];
}

- (NSString *)targetSummary {
    NSString *choice = ExteriaTranslateTargetChoice();
    return choice.length ? ExteriaLanguageName(choice) : NSLocalizedString(@"tr.target.app", nil);
}

- (NSString *)skippedSummary {
    NSUInteger count = ExteriaTranslateSkippedLanguages().count;
    return count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil;
}

- (ExteriaSettingsSection *)translateSection {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"general.translate.button", nil) subtitle:nil on:ExteriaTranslateButtonEnabled()
                                                    toggle:^(BOOL on) { ExteriaTranslateSetButtonEnabled(on); }]];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.provider", nil) value:ExteriaTranslateProviderName(ExteriaTranslateProviderChoice()) tap:^{
        ExteriaGeneralSettingsController *me = weak.target;
        if (!me) return;
        NSArray *ids = ExteriaTranslateProviderList();
        NSMutableArray *titles = [NSMutableArray array];
        for (NSNumber *provider in ids) [titles addObject:ExteriaTranslateProviderName(provider.intValue)];
        ExteriaSettingsChoose(me, NSLocalizedString(@"tr.provider", nil), titles, ^(NSUInteger index) {
            ExteriaTranslateSetProviderChoice([[ids objectAtIndex:index] intValue]);
            [(ExteriaGeneralSettingsController *)weak.target rebuild];
        });
    }]];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.target", nil) value:[self targetSummary] tap:^{
        [[(ExteriaGeneralSettingsController *)weak.target navigationController] pushViewController:[[[ExteriaTranslateLanguagesController alloc] initWithMode:ExteriaTranslateLanguagesTarget] autorelease] animated:YES];
    }]];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.skip", nil) value:[self skippedSummary] tap:^{
        [[(ExteriaGeneralSettingsController *)weak.target navigationController] pushViewController:[[[ExteriaTranslateLanguagesController alloc] initWithMode:ExteriaTranslateLanguagesSkipped] autorelease] animated:YES];
    }]];
    [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolTranslate tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"tr.title", nil) subtitle:nil value:nil tap:^{
        [[(ExteriaGeneralSettingsController *)weak.target navigationController] pushViewController:[[[ExteriaTranslatorSettingsController alloc] init] autorelease] animated:YES];
    }]];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"general.translate.header", nil) footer:NSLocalizedString(@"general.translate.info", nil) rows:rows];
}

- (void)rebuild {
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self translateSection]];

    NSMutableArray *general = [NSMutableArray array];
    [general addObject:ExteriaGeneralFlagRow(@"general.exactnumbers", @"general.exactnumbers.value", ExteriaChatFlagExactNumbers)];
    [general addObject:ExteriaGeneralFlagRow(@"general.seconds", @"general.seconds.value", ExteriaChatFlagSeconds)];
    ExteriaWeakReference *weak = _weak;
    [general addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"time.zone.title", nil) value:ExteriaTimeZoneChoiceText() tap:^{
        [[(ExteriaGeneralSettingsController *)weak.target navigationController] pushViewController:[[[ExteriaTimeZoneController alloc] init] autorelease] animated:YES];
    }]];
    [general addObject:ExteriaGeneralFlagRow(@"general.relativeseen", nil, ExteriaChatFlagRelativeSeen)];
    [general addObject:ExteriaGeneralFlagRow(@"general.zalgo", nil, ExteriaChatFlagFilterZalgo)];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"general.header", nil) footer:NSLocalizedString(@"general.zalgo.info", nil) rows:general]];

    NSMutableArray *profile = [NSMutableArray array];
    [profile addObject:ExteriaGeneralFlagRow(@"general.hidephone", nil, ExteriaChatFlagHidePhone)];
    [profile addObject:ExteriaGeneralFlagRow(@"general.showids", nil, ExteriaChatFlagShowIds)];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"general.profile.header", nil) footer:NSLocalizedString(@"general.showids.info", nil) rows:profile]];

    NSMutableArray *archive = [NSMutableArray array];
    [archive addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"general.hidearchive", nil) subtitle:nil on:ExteriaArchiveHidden() toggle:^(BOOL on) {
        ExteriaArchiveSetHidden(on);
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
    }]];
    [archive addObject:ExteriaGeneralFlagRow(@"general.nounarchive", nil, ExteriaChatFlagNoUnarchiveSwipe)];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"general.archive.header", nil) footer:NSLocalizedString(@"general.nounarchive.info", nil) rows:archive]];

    self.sections = sections;
    [self reloadSettings];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

@end
