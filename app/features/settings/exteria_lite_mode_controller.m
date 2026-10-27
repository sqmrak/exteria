#import "exteria_lite_mode_controller.h"

#import "exteria_alert.h"
#import "exteria_lite_mode.h"
#import "exteria_weak_reference.h"

/* the sections, in the order of the screen */
enum { SectionLevel, SectionOptions, SectionTransitions, SectionClass };

@interface ExteriaLiteModeSettingsController () {
    ExteriaWeakReference *_weak;
    BOOL _builtUnderSaver;
}
@end

@implementation ExteriaLiteModeSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"lite.title", nil);
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liteModeChanged) name:ExteriaLiteModeDidChangeNotification object:nil];
    [self rebuild];
}

#pragma mark texts

static NSString *ExteriaPercentText(int percent) {
    return [NSString stringWithFormat:@"%d%%", percent];
}

/* what the footer under the slider says of a level */
static NSString *ExteriaLevelInfo(int percent) {
    if (percent <= 0) return NSLocalizedString(@"lite.battery.info.off", nil);
    if (percent >= 100) return NSLocalizedString(@"lite.battery.info.on", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"lite.battery.info.below", nil), ExteriaPercentText(percent)];
}

static NSDictionary *ExteriaLevelDescription(int percent) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (percent <= 0) {
        [info setObject:NSLocalizedString(@"lite.battery.always.off", nil) forKey:@"line"];
        [info setObject:[NSNumber numberWithBool:YES] forKey:@"left"];
    } else if (percent >= 100) {
        [info setObject:NSLocalizedString(@"lite.battery.always.on", nil) forKey:@"line"];
        [info setObject:[NSNumber numberWithBool:YES] forKey:@"right"];
    } else {
        [info setObject:[NSString stringWithFormat:NSLocalizedString(@"lite.battery.below", nil), ExteriaPercentText(percent)] forKey:@"line"];
        [info setObject:[NSNumber numberWithFloat:(float)percent / 100.0f] forKey:@"fill"];
        /* the badge says whether the saver is working at this moment, which the battery decides */
        BOOL applied = exteria_lite_power_saver_applied(percent, ExteriaLiteBatteryPercent()) != 0;
        [info setObject:NSLocalizedString(applied ? @"lite.battery.on" : @"lite.battery.off", nil) forKey:@"badge"];
    }
    return info;
}

- (NSArray *)classNames {
    return [NSArray arrayWithObjects:[NSString stringWithFormat:@"%@ [%@]", NSLocalizedString(@"lite.class.auto", nil), ExteriaLiteClassName(ExteriaLiteMeasuredClass())],
            NSLocalizedString(@"lite.class.high", nil), NSLocalizedString(@"lite.class.average", nil), NSLocalizedString(@"lite.class.low", nil), nil];
}

#pragma mark sections

- (ExteriaSettingsSection *)levelSection {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *level = [ExteriaSettingsRow levelRowWithTitle:NSLocalizedString(@"lite.battery.title", nil) leftCaption:NSLocalizedString(@"lite.battery.off", nil)
                                                        rightCaption:NSLocalizedString(@"lite.battery.on", nil) percent:ExteriaLitePowerSaverLevel()
                                                            describe:^NSDictionary *(int percent) { return ExteriaLevelDescription(percent); }
                                                              change:^(int percent) {
        ExteriaLiteSetPowerSaverLevel(percent);
        [(ExteriaLiteModeSettingsController *)weak.target setFooter:ExteriaLevelInfo(percent) forSectionAtIndex:SectionLevel];
    }];
    return [ExteriaSettingsSection sectionWithHeader:nil footer:ExteriaLevelInfo(ExteriaLitePowerSaverLevel()) rows:[NSArray arrayWithObject:level]];
}

/* a switch of one animation; the power saver holds them all off, and a touch on a row says so */
- (ExteriaSettingsRow *)switchForFlag:(uint32_t)flag symbol:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone key:(NSString *)key {
    BOOL saver = ExteriaLitePowerSaverApplied();
    ExteriaSettingsRow *row = [ExteriaSettingsRow switchRowWithSymbol:symbol tone:tone title:NSLocalizedString(key, nil) subtitle:nil on:ExteriaLiteEnabled(flag)
                                                              toggle:^(BOOL on) { ExteriaLiteSetFlag(flag, on); }];
    if (saver) {
        row.disabled = YES;
        row.tap = ^{ ExteriaShowNotice(nil, NSLocalizedString(@"lite.restricted", nil)); };
    }
    return row;
}

- (ExteriaSettingsSection *)optionsSection {
    _builtUnderSaver = ExteriaLitePowerSaverApplied();
    NSArray *rows = [NSArray arrayWithObjects:
        [self switchForFlag:EXTERIA_LITE_STICKERS_CHAT symbol:ExteriaSymbolSticker tone:ExteriaSettingsToneOrangeDeep key:@"lite.stickers"],
        [self switchForFlag:EXTERIA_LITE_EMOJI_CHAT symbol:ExteriaSymbolSmiley tone:ExteriaSettingsToneOrangeBright key:@"lite.emoji"],
        [self switchForFlag:EXTERIA_LITE_CHAT_BACKGROUND symbol:ExteriaSymbolChats tone:ExteriaSettingsTonePurple key:@"lite.background"],
        [self switchForFlag:EXTERIA_LITE_CHAT_SCALE symbol:ExteriaSymbolMagnifier tone:ExteriaSettingsToneBlue key:@"lite.zoom"],
        [self switchForFlag:EXTERIA_LITE_CHAT_THANOS symbol:ExteriaSymbolTrashCan tone:ExteriaSettingsToneRed key:@"lite.dust"],
        [self switchForFlag:EXTERIA_LITE_CALLS symbol:ExteriaSymbolPhone tone:ExteriaSettingsToneGreen key:@"lite.calls"], nil];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"lite.options", nil) footer:nil rows:rows];
}

- (ExteriaSettingsSection *)transitionsSection {
    ExteriaSettingsRow *smooth = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"lite.smooth", nil) subtitle:nil on:ExteriaLiteSmoothTransitions()
                                                                toggle:^(BOOL on) { ExteriaLiteSetSmoothTransitions(on); }];
    return [ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"lite.smooth.info", nil) rows:[NSArray arrayWithObject:smooth]];
}

- (ExteriaSettingsSection *)classSection {
    ExteriaWeakReference *weak = _weak;
    NSArray *names = [self classNames];
    ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"lite.class", nil) value:[names objectAtIndex:(NSUInteger)ExteriaLiteClassChoice()] tap:^{
        ExteriaLiteModeSettingsController *screen = weak.target;
        ExteriaSettingsChoose(screen, NSLocalizedString(@"lite.class", nil), names, ^(NSUInteger index) {
            if ((int)index == ExteriaLiteClassChoice()) return;
            ExteriaLiteSetClassChoice((int)index);
            ExteriaLiteModeSettingsController *again = weak.target;
            [again replaceSectionAtIndex:SectionClass withSection:[again classSection]];
            /* the class picks the switches of a person who never moved one */
            [again replaceSectionAtIndex:SectionOptions withSection:[again optionsSection]];
        });
    }];
    return [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:row]];
}

- (void)rebuild {
    self.sections = [NSArray arrayWithObjects:[self levelSection], [self optionsSection], [self transitionsSection], [self classSection], nil];
}

/* the saver came or went: the switches are made again, and the slider under the finger is left alone */
- (void)liteModeChanged {
    if (!self.sections.count || ExteriaLitePowerSaverApplied() == _builtUnderSaver) return;
    [self replaceSectionAtIndex:SectionOptions withSection:[self optionsSection]];
}

@end
