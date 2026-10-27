#import "exteria_cleaning.h"
#import "exteria_memory_controller.h"

#import "exteria_chat_settings.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"

static NSString *ExteriaMemorySize(unsigned long long bytes) {
    if (!bytes) return NSLocalizedString(@"settings.cache.empty", nil);
    if (bytes >= 1024ull * 1024ull * 1024ull) return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    if (bytes >= 1024ull * 1024ull) return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
}

/* the days a file stays: zero is as long as the cache has room */
static const NSInteger ExteriaKeepChoices[] = {3, 7, 30, 0};
static NSString *const ExteriaKeepTitles[] = {@"memory.keep.3", @"memory.keep.7", @"memory.keep.30", @"memory.keep.forever"};

@interface ExteriaMemoryController () {
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaMemoryController

- (id)initWithAvatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"memory.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_avatars release];
    [_media release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaMemoryController alloc] initWithAvatars:_avatars media:_media] autorelease];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    unsigned long long avatars = [_avatars diskBytes], media = [_media diskBytes];
    ExteriaSettingsRow *total = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolBroom tone:ExteriaSettingsToneBlueDeep title:NSLocalizedString(@"memory.total", nil) subtitle:nil
                                                            value:ExteriaMemorySize(avatars + media) tap:nil];
    ExteriaSettingsRow *files = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"memory.media", nil) value:ExteriaMemorySize(media) tap:nil];
    ExteriaSettingsRow *photos = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"memory.avatars", nil) value:ExteriaMemorySize(avatars) tap:nil];
    NSMutableArray *keep = [NSMutableArray array];
    NSInteger days = ExteriaCacheKeepDays();
    for (size_t i = 0; i < sizeof(ExteriaKeepChoices) / sizeof(ExteriaKeepChoices[0]); ++i) {
        NSInteger choice = ExteriaKeepChoices[i];
        [keep addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(ExteriaKeepTitles[i], nil) subtitle:nil checked:days == choice tap:^{
            ExteriaMemoryController *me = weak.target;
            if (!me) return;
            ExteriaCacheSetKeepDays(choice);
            /* the files past the new limit go at once, not at the next start */
            [me->_media removeFilesOlderThanDays:choice];
            [me rebuild];
        }]];
    }
    ExteriaSettingsRow *clear = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolBroom title:NSLocalizedString(@"settings.cache.clear.all", nil) destructive:YES tap:^{
        ExteriaMemoryController *me = weak.target;
        if (!me) return;
        ExteriaConfirmAction(me, NSLocalizedString(@"settings.cache.confirm", nil), NSLocalizedString(@"settings.cache.clear", nil), ^{
            ExteriaMemoryController *again = weak.target;
            if (!again) return;
            ExteriaAvatarCache *avatars = again->_avatars;
            ExteriaMediaCache *media = again->_media;
            ExteriaRunCleaning([NSArray arrayWithObjects:
                [ExteriaCleaningStep stepNamed:NSLocalizedString(@"memory.avatars", nil) work:^{ [avatars clear]; }],
                [ExteriaCleaningStep stepNamed:NSLocalizedString(@"memory.media", nil) work:^{ [media clear]; }], nil], ^{
                [(ExteriaMemoryController *)weak.target rebuild];
            });
        });
    }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:total, files, photos, nil]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"memory.keep", nil) footer:NSLocalizedString(@"memory.keep.info", nil) rows:keep]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"memory.clear.info", nil) rows:[NSArray arrayWithObject:clear]]];
    self.sections = sections;
    [self reloadSettings];
}

@end
