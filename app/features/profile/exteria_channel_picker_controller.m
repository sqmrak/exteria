#import "exteria_channel_picker_controller.h"

#import "exteria_gift_screen.h"
#import "exteria_people_avatars.h"
#import "exteria_person.h"
#import "exteria_session_profile.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaChannelPickerController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaWeakReference *_weak;
    ExteriaPeopleAvatars *_faces;
    NSArray *_channels;
    NSString *_status;
    long long _currentChannelId;
    void (^_pickHandler)(ExteriaDialog *);
}
@end

@implementation ExteriaChannelPickerController

@synthesize currentChannelId = _currentChannelId;
@synthesize pickHandler = _pickHandler;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    (void)media;
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_faces invalidate];
    [_faces release];
    [_session release];
    [_avatars release];
    [_channels release];
    [_status release];
    [_pickHandler release];
    [super dealloc];
}

- (NSString *)screenTitle {
    return self.pageTitle;
}

- (void)setScreenTitle:(NSString *)title {
    self.pageTitle = title;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadChannelsForProfile:^(NSArray *items, NSString *errorName) {
        ExteriaChannelPickerController *me = weak.target;
        if (!me) return;
        [me->_status release];
        if (!items) {
            me->_status = [ExteriaGiftErrorText(errorName) copy];
        } else {
            [me->_channels release];
            me->_channels = [items retain];
            me->_status = [(items.count ? @"" : NSLocalizedString(@"profile.channel.none", nil)) copy];
        }
        [me rebuild];
    }];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)choose:(ExteriaDialog *)channel {
    if (_pickHandler) _pickHandler(channel);
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    if (!_faces) _faces = [[ExteriaPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(ExteriaChannelPickerController *)weak.target rebuild]; }];
    UIImage *mark = ExteriaSymbolImage(ExteriaSymbolCheck, 22, ExteriaColorAccent());
    ExteriaSettingsRow *none = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolBlock title:NSLocalizedString(@"profile.channel.remove", nil) destructive:YES
                                                                  tap:^{ [(ExteriaChannelPickerController *)weak.target choose:nil]; }];
    if (_currentChannelId == 0) none.trailingImage = mark;
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaDialog *channel in _channels) {
        UIImage *face = [_faces imageForKey:[NSString stringWithFormat:@"%lld", channel.peerId] initials:channel.initials seed:channel.avatarSeed deleted:NO photo:channel.photo];
        ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTileImage:face title:channel.title subtitle:NSLocalizedString(@"profile.channel.kind", nil)
                                                                   tap:^{ [(ExteriaChannelPickerController *)weak.target choose:channel]; }];
        if (channel.peerId == _currentChannelId) row.trailingImage = mark;
        [rows addObject:row];
    }
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:none]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:_status rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

@end
