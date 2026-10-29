#import "exteria_update_controller.h"
#import "exteria_release_check.h"
#import "exteria_updater.h"
#import "exteria_wave_progress.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"
#include "exteria_release.h"

@interface ExteriaUpdateController () {
    ExteriaWeakReference *_weak;
    NSDictionary *_release;
    NSString *_error;
    ExteriaUpdater *_updater;
    UIView *_progressCard;
    ExteriaWaveProgress *_wave;
    UILabel *_progressText;
    BOOL _checking;
    BOOL _newer;
    NSUInteger _generation;
}
@end

@implementation ExteriaUpdateController
- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"update.page.title", nil);
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    _updater.onChange = nil;
    [_updater cancel];
    [_updater release];
    [_release release];
    [_error release];
    [_progressCard release];
    [_wave release];
    [_progressText release];
    [super dealloc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self check];
}
- (void)themeDidChange { [self rebuild]; }
- (void)check {
    if (_checking || _updater.state == ExteriaUpdaterWorking) return;
    _checking = YES;
    NSUInteger generation = ++_generation;
    [_error release]; _error = nil;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    ExteriaFetchLatestRelease(^(NSDictionary *release, NSString *error) {
        ExteriaUpdateController *controller = weak.target;
        if (!controller || generation != controller->_generation) return;
        controller->_checking = NO;
        [controller->_release release];
        controller->_release = [release retain];
        [controller->_error release];
        controller->_error = [error copy];
        controller->_newer = NO;
        if (release) {
            NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            int newer = 0;
            exteria_status status = exteria_release_compare([[release objectForKey:@"tag"] UTF8String], version.UTF8String, &newer);
            if (status != EXTERIA_OK) controller->_error = [[NSString stringWithUTF8String:exteria_status_name(status)] copy];
            else controller->_newer = newer != 0;
        }
        [controller rebuild];
    });
}
- (void)startUpdate {
    if (!_newer || !_release) return;
    NSString *ipa = [_release objectForKey:@"ipa"], *digest = [_release objectForKey:@"digest"];
    if (!ipa.length || !digest.length || ![ExteriaUpdater canInstallInPlace]) return;
    _updater.onChange = nil;
    [_updater release];
    _updater = [[ExteriaUpdater alloc] initWithIpaURL:ipa digestURL:digest size:[[_release objectForKey:@"size"] unsignedLongLongValue]];
    ExteriaWeakReference *weak = _weak;
    _updater.onChange = ^{ [(ExteriaUpdateController *)weak.target updateChanged]; };
    _wave.value = 0;
    [_updater start];
    [self rebuild];
    [self updateChanged];
}
- (void)updateChanged {
    if (_updater.state == ExteriaUpdaterWorking) {
        _progressText.text = _updater.installing ? NSLocalizedString(@"release.installing", nil) :
            [NSString stringWithFormat:NSLocalizedString(@"release.progress", nil),
             [NSString stringWithFormat:@"%.1f", (double)_updater.downloaded / 1048576.0],
             [NSString stringWithFormat:@"%.1f", (double)_updater.expected / 1048576.0]];
        [_wave setValue:_updater.fraction gliding:YES];
    } else [self rebuild];
}
- (UIView *)progressCard {
    if (_progressCard) return _progressCard;
    _progressCard = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 280, 76)];
    _progressText = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 248, 24)];
    _progressText.backgroundColor = [UIColor clearColor];
    _progressText.textColor = ExteriaColorSecondary();
    _progressText.font = ExteriaFontMedium(14);
    _progressText.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _progressText.text = NSLocalizedString(@"release.preparing", nil);
    [_progressCard addSubview:_progressText];
    _wave = [[ExteriaWaveProgress alloc] initWithFrame:CGRectMake(10, 36, 260, ExteriaWaveProgressHeight)];
    _wave.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _wave.userInteractionEnabled = NO;
    _wave.waving = !ExteriaThemeIsClassic();
    [_progressCard addSubview:_wave];
    return _progressCard;
}
- (void)rebuild {
    NSString *installed = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *latest = [_release objectForKey:@"tag"];
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"update.page.installed", nil) value:installed tap:nil]];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"update.page.latest", nil)
                                             value:latest ? latest : (_checking ? NSLocalizedString(@"update.page.checking", nil) : @"—") tap:nil]];
    NSMutableArray *sections = [NSMutableArray array];
    NSString *message = nil;
    if (_error) message = [NSString stringWithFormat:NSLocalizedString(@"update.page.error", nil), _error];
    else if (_release && !_newer) message = NSLocalizedString(@"update.page.current", nil);
    else if (_newer && (![[_release objectForKey:@"ipa"] length] || ![[_release objectForKey:@"digest"] length])) message = NSLocalizedString(@"release.noasset", nil);
    else if (_newer && ![ExteriaUpdater canInstallInPlace]) message = NSLocalizedString(@"release.readonly", nil);
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:message rows:rows]];
    if (_updater.state == ExteriaUpdaterWorking) {
        ExteriaSettingsRow *progress = [ExteriaSettingsRow viewRowWithView:[self progressCard] height:^CGFloat(CGFloat width) { (void)width; return 76; }];
        ExteriaSettingsRow *cancel = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolClose title:NSLocalizedString(@"release.cancel", nil) destructive:NO tap:^{
            ExteriaUpdateController *controller = weak.target;
            if (controller) [controller->_updater cancel];
        }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:progress, cancel, nil]]];
    } else if (_updater.state == ExteriaUpdaterDone) {
        ExteriaSettingsRow *restart = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolCheck title:NSLocalizedString(@"release.restart", nil) destructive:NO tap:^{ exit(0); }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"release.restart.note", nil) rows:[NSArray arrayWithObject:restart]]];
    } else {
        if (_updater.state == ExteriaUpdaterFailed) {
            NSString *failure = [NSString stringWithFormat:@"%s", exteria_status_name(_updater.failure)];
            [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:failure rows:[NSArray array]]];
        }
        NSMutableArray *actions = [NSMutableArray array];
        if (_newer && [[_release objectForKey:@"ipa"] length] && [[_release objectForKey:@"digest"] length] && [ExteriaUpdater canInstallInPlace])
            [actions addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolArrowDown title:NSLocalizedString(@"release.update", nil) destructive:NO tap:^{ [(ExteriaUpdateController *)weak.target startUpdate]; }]];
        [actions addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolRotate title:NSLocalizedString(@"update.page.check", nil) destructive:NO tap:^{ [(ExteriaUpdateController *)weak.target check]; }]];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:actions]];
    }
    self.sections = sections;
}
@end
