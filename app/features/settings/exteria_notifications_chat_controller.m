#import "exteria_notifications_chat_controller.h"

#import "exteria_alert.h"
#import "exteria_notifications_sound_controller.h"
#import "exteria_notify_store.h"
#import "exteria_sheet.h"
#import "exteria_weak_reference.h"

@interface ExteriaNotificationsChatController () {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    int32_t _peerKind;
    long long _peerId;
    long long _peerHash;
    BOOL _broadcast;
    int32_t _topic;
    exteria_peer_notify _settings;
    BOOL _loaded;
    BOOL _sending;
}
@end

@implementation ExteriaNotificationsChatController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media peerKind:(int32_t)peerKind peerId:(long long)peerId peerHash:(long long)peerHash
              channel:(BOOL)broadcast topic:(int32_t)topic title:(NSString *)title {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _peerKind = peerKind;
    _peerId = peerId;
    _peerHash = peerHash;
    _broadcast = broadcast;
    _topic = topic;
    memset(&_settings, 0, sizeof(_settings));
    self.pageTitle = title.length ? title : NSLocalizedString(@"notif.chat.header", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [super dealloc];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadNotifyOfPeerKind:_peerKind id:_peerId hash:_peerHash topic:_topic completion:^(NSValue *boxed, NSString *errorName) {
        ExteriaNotificationsChatController *me = weak.target;
        if (!me) return;
        if (!boxed) {
            NSLog(@"exteria: the notification settings of the chat did not load: %@", errorName);
            return;
        }
        [boxed getValue:&me->_settings];
        me->_loaded = YES;
        [me rebuild];
    }];
}

- (exteria_notify_scope)scope {
    return exteria_notify_scope_of(_peerKind, _broadcast);
}

/* what the chat does now: its own setting over the one of its kind */
- (void)effective:(exteria_notify_decision *)decision {
    exteria_notify_rules rules;
    ExteriaNotifyRulesSnapshot(&rules);
    exteria_notify_decide(&rules, [self scope], &_settings, ExteriaNotifyNow(), decision);
}

- (int32_t)effectiveMute {
    exteria_peer_notify kind = ExteriaNotifyScopeStored([self scope]);
    if (_settings.has_mute) return _settings.mute_until;
    return kind.has_mute ? kind.mute_until : 0;
}

- (BOOL)hasOwnSettings {
    return _settings.has_mute || _settings.has_previews || _settings.has_silent || _settings.has_sound || _settings.has_stories_muted;
}

/* the change is made on the copy and the whole copy is sent, since the server takes the settings of a chat as one thing */
- (void)edit:(void (^)(exteria_peer_notify *settings))change {
    exteria_peer_notify before = _settings;
    change(&_settings);
    ExteriaWeakReference *weak = _weak;
    [_session updateNotify:[NSValue valueWithBytes:&_settings objCType:@encode(exteria_peer_notify)] ofPeerKind:_peerKind id:_peerId hash:_peerHash topic:_topic
                completion:^(NSString *errorName) {
        ExteriaNotificationsChatController *me = weak.target;
        if (!me || !errorName) return;
        NSLog(@"exteria: the notification settings of the chat were not kept: %@", errorName);
        me->_settings = before;
        [me rebuild];
        ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
    }];
    [self rebuild];
}

- (void)chooseMute {
    ExteriaWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.mute.on", nil), NSLocalizedString(@"notif.mute.1h", nil), NSLocalizedString(@"notif.mute.8h", nil),
                        NSLocalizedString(@"notif.mute.2d", nil), NSLocalizedString(@"notif.mute.off", nil), nil];
    ExteriaSettingsChoose(self, NSLocalizedString(@"notif.chat.mute", nil), options, ^(NSUInteger index) {
        int32_t now = ExteriaNotifyNow();
        int32_t until = index == 0 ? 0 : (index == 1 ? now + 3600 : (index == 2 ? now + 8 * 3600 : (index == 3 ? now + 2 * 86400 : EXTERIA_NOTIFY_MUTE_FOREVER)));
        [(ExteriaNotificationsChatController *)weak.target edit:^(exteria_peer_notify *s) {
            s->has_mute = 1;
            s->mute_until = until;
        }];
    });
}

- (void)openSound {
    ExteriaWeakReference *weak = _weak;
    NSValue *current = _settings.has_sound ? [NSValue valueWithBytes:&_settings.sound objCType:@encode(exteria_notify_sound)] : nil;
    ExteriaNotificationsSoundController *page = [[[ExteriaNotificationsSoundController alloc] initWithSession:_session media:_media title:NSLocalizedString(@"notif.sound", nil)
                                                                                                    current:current apply:^(exteria_notify_sound sound) {
        [(ExteriaNotificationsChatController *)weak.target edit:^(exteria_peer_notify *s) {
            s->has_sound = 1;
            s->sound = sound;
        }];
    }] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}

- (void)confirmReset {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"notif.chat.reset.alert", nil), NSLocalizedString(@"notif.reset.confirm", nil), ^{
        ExteriaNotificationsChatController *me = weak.target;
        if (!me) return;
        [me->_session resetNotifyOfPeerKind:me->_peerKind id:me->_peerId hash:me->_peerHash topic:me->_topic completion:^(NSString *errorName) {
            ExteriaNotificationsChatController *again = weak.target;
            if (!again) return;
            if (errorName) {
                ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                return;
            }
            memset(&again->_settings, 0, sizeof(again->_settings));
            [again rebuild];
        }];
    });
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    exteria_notify_decision decision;
    [self effective:&decision];
    int32_t mute = [self effectiveMute];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolBell tone:ExteriaSettingsToneRed title:NSLocalizedString(@"notif.chat.mute", nil) subtitle:nil
                                                value:ExteriaNotifyMuteText(mute) tap:^{ [(ExteriaNotificationsChatController *)weak.target chooseMute]; }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolEye tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"notif.preview", nil) subtitle:nil
                                                         on:decision.previews toggle:^(BOOL on) {
        [(ExteriaNotificationsChatController *)weak.target edit:^(exteria_peer_notify *s) {
            s->has_previews = 1;
            s->previews = on;
        }];
    }]];
    if (_peerKind == 1) {
        BOOL stories = !(_settings.has_stories_muted && _settings.stories_muted);
        [rows addObject:[ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolGallery tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"notif.chat.stories", nil)
                                                       subtitle:nil on:stories toggle:^(BOOL on) {
            [(ExteriaNotificationsChatController *)weak.target edit:^(exteria_peer_notify *s) {
                s->has_stories_muted = 1;
                s->stories_muted = !on;
            }];
        }]];
    }
    exteria_notify_sound shown = decision.sound;
    [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsSounds tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"notif.sound", nil) subtitle:nil
                                                value:ExteriaNotifySoundText(_settings.has_sound || decision.sound.kind != EXTERIA_SOUND_DEFAULT, &shown)
                                                  tap:^{ [(ExteriaNotificationsChatController *)weak.target openSound]; }]];
    NSMutableArray *sections = [NSMutableArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.chat.header", nil) footer:nil rows:rows]];
    if ([self hasOwnSettings]) {
        ExteriaSettingsRow *reset = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolBroom title:NSLocalizedString(@"notif.chat.reset", nil) destructive:YES
                                                                        tap:^{ [(ExteriaNotificationsChatController *)weak.target confirmReset]; }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:reset]]];
    }
    self.sections = sections;
}

@end
