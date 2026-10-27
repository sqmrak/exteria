#import "exteria_notifications_sound_controller.h"

#import <AVFoundation/AVFoundation.h>

#import "exteria_alert.h"
#import "exteria_app_sounds.h"
#import "exteria_remote_file.h"
#import "exteria_sheet.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaNotificationsSoundController () {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    exteria_notify_sound _current;
    BOOL _hasCurrent;
    void (^_apply)(exteria_notify_sound sound);
    NSArray *_cloud;
    /* an AVAudioPlayer, found by name, so the arm64 slice does not link a framework that older systems lack */
    id _player;
    NSUInteger _request;
}
@end

@implementation ExteriaNotificationsSoundController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media title:(NSString *)title current:(NSValue *)current
                apply:(void (^)(exteria_notify_sound))apply {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _apply = [apply copy];
    memset(&_current, 0, sizeof(_current));
    if (current) {
        [current getValue:&_current];
        _hasCurrent = YES;
    }
    self.pageTitle = title.length ? title : NSLocalizedString(@"notif.sound", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_media cancelPathRequest:_request];
    [_player stop];
    [_player release];
    [_session release];
    [_media release];
    [_apply release];
    [_cloud release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadCloudTonesWithCompletion:^(NSArray *tones, NSString *errorName) {
        ExteriaNotificationsSoundController *me = weak.target;
        if (!me) return;
        if (!tones) {
            NSLog(@"exteria: the saved tones did not load: %@", errorName);
            return;
        }
        [me->_cloud release];
        me->_cloud = [tones retain];
        [me rebuild];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_player stop];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)choose:(exteria_notify_sound)sound {
    _current = sound;
    _hasCurrent = YES;
    if (_apply) _apply(sound);
    [self rebuild];
}

/* a tone of the cloud is fetched and played from the file; the file is kept by the cache, so the next tap is at once */
- (void)playCloudTone:(ExteriaCloudTone *)tone {
    exteria_ringtone_row row = tone.row;
    exteria_media_ref ref;
    memset(&ref, 0, sizeof(ref));
    ref.source = EXTERIA_MEDIA_SOURCE_DOCUMENT;
    ref.dc = row.dc;
    ref.id = row.id;
    ref.access_hash = row.access_hash;
    ref.ref_len = row.file_reference_len;
    memcpy(ref.file_ref, row.file_reference, row.file_reference_len);
    ExteriaRemoteFile *file = [ExteriaRemoteFile fileForMedia:&ref];
    if (!file) return;
    [_media cancelPathRequest:_request];
    ExteriaWeakReference *weak = _weak;
    _request = [_media loadPathForFile:file size:row.size progress:nil completion:^(NSString *path) {
        ExteriaNotificationsSoundController *me = weak.target;
        if (!me) return;
        NSError *error = nil;
        Class playerClass = NSClassFromString(@"AVAudioPlayer");
        id player = path && playerClass ? [[playerClass alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error] : nil;
        if (!player) {
            NSLog(@"exteria: the tone could not be played: %@", error);
            ExteriaShowNotice(nil, NSLocalizedString(@"notif.sound.failed", nil));
            return;
        }
        [me->_player stop];
        [me->_player release];
        me->_player = player;
        [player play];
    }];
}

- (BOOL)isCurrentKind:(int32_t)kind data:(const char *)data id:(int64_t)tone {
    if (!_hasCurrent) return kind == EXTERIA_SOUND_DEFAULT;
    if (_current.kind != kind) return NO;
    if (kind == EXTERIA_SOUND_LOCAL) return !strcmp(_current.data, data);
    if (kind == EXTERIA_SOUND_RINGTONE) return _current.ringtone_id == tone;
    return YES;
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    if (_cloud.count) {
        NSMutableArray *rows = [NSMutableArray array];
        for (ExteriaCloudTone *tone in _cloud) {
            BOOL chosen = [self isCurrentKind:EXTERIA_SOUND_RINGTONE data:"" id:tone.toneId];
            NSString *length = tone.duration > 0 ? [NSString stringWithFormat:@"%d:%02d", tone.duration / 60, tone.duration % 60] : nil;
            [rows addObject:[ExteriaSettingsRow checkRowWithTitle:tone.title subtitle:length checked:chosen tap:^{
                ExteriaNotificationsSoundController *me = weak.target;
                if (!me) return;
                if (chosen) {
                    [me askDeleteTone:tone];
                    return;
                }
                exteria_notify_sound sound;
                memset(&sound, 0, sizeof(sound));
                sound.kind = EXTERIA_SOUND_RINGTONE;
                sound.ringtone_id = tone.toneId;
                strlcpy(sound.title, tone.title.UTF8String, sizeof(sound.title));
                [me playCloudTone:tone];
                [me choose:sound];
            }]];
        }
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.sound.cloud", nil) footer:NSLocalizedString(@"notif.sound.cloud.info", nil) rows:rows]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"notif.sound.none", nil) subtitle:nil checked:[self isCurrentKind:EXTERIA_SOUND_NONE data:"" id:0] tap:^{
        exteria_notify_sound sound;
        memset(&sound, 0, sizeof(sound));
        sound.kind = EXTERIA_SOUND_NONE;
        [(ExteriaNotificationsSoundController *)weak.target choose:sound];
    }]];
    [rows addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"notif.sound.default", nil) subtitle:nil checked:[self isCurrentKind:EXTERIA_SOUND_DEFAULT data:"" id:0] tap:^{
        exteria_notify_sound sound;
        memset(&sound, 0, sizeof(sound));
        [(ExteriaNotificationsSoundController *)weak.target choose:sound];
    }]];
    for (NSArray *tone in ExteriaNotifyTones()) {
        NSString *file = [tone objectAtIndex:0], *title = [tone objectAtIndex:1];
        [rows addObject:[ExteriaSettingsRow checkRowWithTitle:title subtitle:nil checked:[self isCurrentKind:EXTERIA_SOUND_LOCAL data:file.UTF8String id:0] tap:^{
            exteria_notify_sound sound;
            memset(&sound, 0, sizeof(sound));
            sound.kind = EXTERIA_SOUND_LOCAL;
            strlcpy(sound.data, file.UTF8String, sizeof(sound.data));
            strlcpy(sound.title, title.UTF8String, sizeof(sound.title));
            ExteriaPlayAppSound(file);
            [(ExteriaNotificationsSoundController *)weak.target choose:sound];
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.sound.app", nil) footer:nil rows:rows]];
    self.sections = sections;
}

- (void)askDeleteTone:(ExteriaCloudTone *)tone {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, tone.title, NSLocalizedString(@"notif.sound.delete", nil), ^{
        ExteriaNotificationsSoundController *me = weak.target;
        if (!me) return;
        [me->_session removeCloudTone:tone completion:^(NSString *errorName) {
            ExteriaNotificationsSoundController *again = weak.target;
            if (!again) return;
            if (errorName) {
                ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                return;
            }
            NSMutableArray *rest = [NSMutableArray arrayWithArray:again->_cloud];
            [rest removeObject:tone];
            [again->_cloud release];
            again->_cloud = [rest copy];
            /* the tone that was in use falls back to the default one */
            if (again->_hasCurrent && again->_current.kind == EXTERIA_SOUND_RINGTONE && again->_current.ringtone_id == tone.toneId) {
                exteria_notify_sound sound;
                memset(&sound, 0, sizeof(sound));
                [again choose:sound];
            } else {
                [again rebuild];
            }
        }];
    });
}

@end
