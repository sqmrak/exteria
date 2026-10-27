#import "exteria_translator_controller.h"

#import "exteria_alert.h"
#import "exteria_language.h"
#import "exteria_translate_config.h"
#import "exteria_translate_languages_controller.h"
#import "exteria_weak_reference.h"

@interface ExteriaTranslatorSettingsController () {
    ExteriaWeakReference *_weak;
    int _openedWith;
}
@end

@implementation ExteriaTranslatorSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _openedWith = ExteriaTranslateProviderChoice();
    self.pageTitle = NSLocalizedString(@"tr.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

/* the AI translator without a key cannot translate, so a choice of it left without one goes back to the service the screen was opened with, or to Google
   when that was the AI translator itself */
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (![self isMovingFromParentViewController]) return;
    if (ExteriaTranslateProviderChoice() != ExteriaTranslateProviderLLM || ExteriaLlmKey(ExteriaLlmPresetChoice()).length) return;
    ExteriaTranslateSetProviderChoice(_openedWith == ExteriaTranslateProviderLLM ? ExteriaTranslateProviderGoogle : _openedWith);
}

static NSString *ExteriaSecretText(NSString *key) {
    if (!key.length) return NSLocalizedString(@"tr.none.value", nil);
    return key.length <= 4 ? @"••••" : [@"••••" stringByAppendingString:[key substringFromIndex:key.length - 4]];
}

static NSString *ExteriaPlainText(NSString *text, NSString *empty) {
    if (!text.length) return empty;
    NSString *line = [[text componentsSeparatedByString:@"\n"] objectAtIndex:0];
    return line.length > 60 ? [[line substringToIndex:60] stringByAppendingString:@"…"] : line;
}

- (NSString *)skippedSummary {
    NSArray *codes = ExteriaTranslateSkippedLanguages();
    if (!codes.count) return NSLocalizedString(@"tr.none.value", nil);
    if (codes.count < 3) {
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *code in codes) [names addObject:ExteriaLanguageName(code)];
        return [names componentsJoinedByString:@", "];
    }
    NSString *form = codes.count == 1 ? @"one" : @"other";
    return [NSString stringWithFormat:NSLocalizedString([@"tr.languages." stringByAppendingString:form], nil), (int)codes.count];
}

- (NSString *)targetSummary {
    NSString *choice = ExteriaTranslateTargetChoice();
    return choice.length ? ExteriaLanguageName(choice) : NSLocalizedString(@"tr.target.app", nil);
}

/* the sheet for a key or a prompt: the notice as the message, the stored text in the field, an empty field clears it */
- (void)edit:(NSString *)title notice:(NSString *)notice initial:(NSString *)initial placeholder:(NSString *)placeholder save:(void (^)(NSString *text))save {
    ExteriaWeakReference *weak = _weak;
    void (^store)(NSString *) = [save copy];
    ExteriaPromptText(title, notice, initial, placeholder, ^(NSString *text) {
        store(text);
        [(ExteriaTranslatorSettingsController *)weak.target rebuild];
    });
    [store release];
}

- (NSArray *)optionTitles:(NSArray *)ids name:(NSString *(*)(int))name {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *item in ids) [titles addObject:name([item intValue])];
    return titles;
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaTranslatorSettingsController *(^me)(void) = ^ExteriaTranslatorSettingsController *{ return weak.target; };
    NSMutableArray *sections = [NSMutableArray array];

    ExteriaSettingsRow *show = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.show", nil) subtitle:nil on:ExteriaTranslateButtonEnabled()
                                                              toggle:^(BOOL on) { ExteriaTranslateSetButtonEnabled(on); }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"tr.options", nil) footer:NSLocalizedString(@"tr.messages.info", nil)
                                                             rows:[NSArray arrayWithObject:show]]];

    NSMutableArray *translate = [NSMutableArray array];
    int provider = ExteriaTranslateProviderChoice();
    [translate addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.provider", nil) value:ExteriaTranslateProviderName(provider) tap:^{
        ExteriaTranslatorSettingsController *screen = me();
        NSArray *ids = ExteriaTranslateProviderList();
        ExteriaSettingsChoose(screen, NSLocalizedString(@"tr.provider", nil), [screen optionTitles:ids name:ExteriaTranslateProviderName], ^(NSUInteger index) {
            ExteriaTranslateSetProviderChoice([[ids objectAtIndex:index] intValue]);
            [me() rebuild];
        });
    }]];
    NSArray *modes = [NSArray arrayWithObjects:NSLocalizedString(@"tr.original.off", nil), NSLocalizedString(@"tr.original.manual", nil), NSLocalizedString(@"tr.original.on", nil), nil];
    [translate addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.original", nil) value:[modes objectAtIndex:(NSUInteger)ExteriaTranslateOriginalMode()] tap:^{
        ExteriaSettingsChoose(me(), NSLocalizedString(@"tr.original", nil), modes, ^(NSUInteger index) {
            ExteriaTranslateSetOriginalMode((int)index);
            [me() rebuild];
        });
    }]];
    [translate addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.target", nil) value:[self targetSummary] tap:^{
        ExteriaTranslatorSettingsController *screen = me();
        [screen.navigationController pushViewController:[[[ExteriaTranslateLanguagesController alloc] initWithMode:ExteriaTranslateLanguagesTarget] autorelease] animated:YES];
    }]];
    [translate addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.skip", nil) value:[self skippedSummary] tap:^{
        ExteriaTranslatorSettingsController *screen = me();
        [screen.navigationController pushViewController:[[[ExteriaTranslateLanguagesController alloc] initWithMode:ExteriaTranslateLanguagesSkipped] autorelease] animated:YES];
    }]];
    [translate addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.preferred", nil) subtitle:ExteriaPlainText(ExteriaTranslatePreferredText(), NSLocalizedString(@"tr.none.value", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.preferred.title", nil) notice:NSLocalizedString(@"tr.preferred.example", nil) initial:ExteriaTranslatePreferredText()
       placeholder:NSLocalizedString(@"tr.preferred.example", nil) save:^(NSString *text) { ExteriaTranslateSetPreferredText(text); }];
    }]];
    if (provider == ExteriaTranslateProviderGoogle && !ExteriaTranslateGoogleNew()) {
        [translate addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.google.key", nil) subtitle:ExteriaSecretText(ExteriaTranslateGoogleKey()) value:nil tap:^{
            [me() edit:NSLocalizedString(@"tr.google.key", nil) notice:NSLocalizedString(@"tr.google.key.notice", nil) initial:ExteriaTranslateGoogleKey()
           placeholder:NSLocalizedString(@"tr.llm.key", nil) save:^(NSString *text) { ExteriaTranslateSetGoogleKey(text); }];
        }]];
    } else if (provider == ExteriaTranslateProviderDeepL) {
        [translate addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.deepl.key", nil) subtitle:ExteriaSecretText(ExteriaTranslateDeepLKey()) value:nil tap:^{
            [me() edit:NSLocalizedString(@"tr.deepl.key", nil) notice:NSLocalizedString(@"tr.deepl.key.notice", nil) initial:ExteriaTranslateDeepLKey()
           placeholder:NSLocalizedString(@"tr.llm.key", nil) save:^(NSString *text) { ExteriaTranslateSetDeepLKey(text); }];
        }]];
        NSArray *tones = [NSArray arrayWithObjects:NSLocalizedString(@"tr.deepl.formality.default", nil), NSLocalizedString(@"tr.deepl.formality.informal", nil),
                          NSLocalizedString(@"tr.deepl.formality.formal", nil), nil];
        [translate addObject:[ExteriaSettingsRow rowWithTitle:[tones objectAtIndex:(NSUInteger)ExteriaTranslateDeepLFormality()] value:nil tap:^{
            ExteriaSettingsChoose(me(), nil, tones, ^(NSUInteger index) {
                ExteriaTranslateSetDeepLFormality((int)index);
                [me() rebuild];
            });
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"tr.translate", nil) footer:nil rows:translate]];
    [sections addObject:[self aiSection]];

    ExteriaSettingsRow *fresh = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.google.new", nil) subtitle:nil on:ExteriaTranslateGoogleNew() toggle:^(BOOL on) {
        ExteriaTranslateSetGoogleNew(on);
        [me() rebuild];
    }];
    ExteriaSettingsRow *keep = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.keep", nil) subtitle:NSLocalizedString(@"tr.keep.notice", nil) on:ExteriaTranslateKeepsPreferences()
                                                              toggle:^(BOOL on) { ExteriaTranslateSetKeepsPreferences(on); }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"tr.experimental", nil) footer:nil rows:[NSArray arrayWithObjects:fresh, keep, nil]]];
    self.sections = sections;
}

- (ExteriaSettingsSection *)aiSection {
    ExteriaWeakReference *weak = _weak;
    ExteriaTranslatorSettingsController *(^me)(void) = ^ExteriaTranslatorSettingsController *{ return weak.target; };
    int preset = ExteriaLlmPresetChoice();
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.preset", nil) value:ExteriaLlmPresetName(preset) tap:^{
        ExteriaTranslatorSettingsController *screen = me();
        NSArray *ids = ExteriaLlmPresetList();
        ExteriaSettingsChoose(screen, NSLocalizedString(@"tr.llm.preset", nil), [screen optionTitles:ids name:ExteriaLlmPresetName], ^(NSUInteger index) {
            ExteriaLlmSetPresetChoice([[ids objectAtIndex:index] intValue]);
            [me() rebuild];
        });
    }]];
    NSString *model = ExteriaLlmModel(preset);
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.model", nil) subtitle:ExteriaPlainText(model, NSLocalizedString(@"tr.none.value", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.model", nil) notice:nil initial:ExteriaLlmSavedModel(preset) placeholder:ExteriaLlmDefaultModel(preset)
              save:^(NSString *text) { ExteriaLlmSetModel(preset, text); }];
    }]];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.key", nil) subtitle:ExteriaSecretText(ExteriaLlmKey(preset)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.key", nil) notice:NSLocalizedString(@"tr.llm.key.notice", nil) initial:ExteriaLlmKey(preset)
       placeholder:NSLocalizedString(@"tr.llm.key", nil) save:^(NSString *text) { ExteriaLlmSetKey(preset, text); }];
    }]];
    if (preset == ExteriaLlmPresetCustom) {
        NSString *url = ExteriaLlmCustomURL();
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.url", nil) subtitle:url.length ? url : ExteriaLlmBaseURL(ExteriaLlmPresetCustom) value:nil tap:^{
            ExteriaWeakReference *inner = weak;
            ExteriaPromptText(NSLocalizedString(@"tr.llm.url", nil), NSLocalizedString(@"tr.llm.url.notice", nil), ExteriaLlmCustomURL(), NSLocalizedString(@"tr.llm.url.hint", nil),
                              ^(NSString *text) {
                NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length && !ExteriaLlmNormalizedURL(trimmed).length) {
                    ExteriaShowNotice(nil, NSLocalizedString(@"tr.url.invalid", nil));
                    return;
                }
                ExteriaLlmSetCustomURL(trimmed);
                [(ExteriaTranslatorSettingsController *)inner.target rebuild];
            });
        }]];
    }
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.system", nil) subtitle:ExteriaPlainText(ExteriaLlmSystemPrompt(), NSLocalizedString(@"tr.default", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.system", nil) notice:NSLocalizedString(@"tr.llm.system.notice", nil) initial:ExteriaLlmSystemPrompt()
       placeholder:NSLocalizedString(@"tr.llm.system.hint", nil) save:^(NSString *text) { ExteriaLlmSetSystemPrompt(text); }];
    }]];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.user", nil) subtitle:ExteriaPlainText(ExteriaLlmUserPrompt(), NSLocalizedString(@"tr.default", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.user", nil) notice:NSLocalizedString(@"tr.llm.user.notice", nil) initial:ExteriaLlmUserPrompt()
       placeholder:NSLocalizedString(@"tr.llm.user.hint", nil) save:^(NSString *text) { ExteriaLlmSetUserPrompt(text); }];
    }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.llm.context", nil) subtitle:NSLocalizedString(@"tr.llm.context.notice", nil) on:ExteriaLlmUsesContext() toggle:^(BOOL on) {
        ExteriaLlmSetUsesContext(on);
        [me() rebuild];
    }]];
    if (ExteriaLlmUsesContext()) {
        NSArray *counts = ExteriaLlmContextCounts();
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.context.size", nil) value:[NSString stringWithFormat:@"%d", ExteriaLlmContextCount()] tap:^{
            NSMutableArray *titles = [NSMutableArray array];
            for (NSNumber *count in counts) [titles addObject:[count stringValue]];
            ExteriaSettingsChoose(me(), NSLocalizedString(@"tr.llm.context.title", nil), titles, ^(NSUInteger index) {
                ExteriaLlmSetContextIndex((int)index);
                [me() rebuild];
            });
        }]];
    }
    if (ExteriaLlmSupportsTemperature(preset, model)) {
        [rows addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"tr.llm.temperature", nil) format:@"%.1f" value:ExteriaLlmTemperature() minimum:0 maximum:2
                                                        change:^(float value) { ExteriaLlmSetTemperature(roundf(value * 10) / 10); }]];
    }
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"tr.ai", nil) footer:nil rows:rows];
}

@end
