#import "exteria_notifications_settings_controller.h"

#import "exteria_alert.h"
#import "exteria_notifications_kind_controller.h"
#import "exteria_notifier.h"
#import "exteria_notify_store.h"
#import "exteria_sheet.h"
#import "exteria_weak_reference.h"

@interface ExteriaNotificationsSettingsController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    NSArray *_exceptions;
    BOOL _resetting;
}
@end

@implementation ExteriaNotificationsSettingsController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.notifications", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rebuild) object:nil];
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_exceptions release];
    [super dealloc];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleRebuild) name:ExteriaNotifyStoreDidChangeNotification object:nil];
    [self rebuild];
    [_session syncNotifySettingsWithCompletion:^(NSString *errorName) {
        if (errorName) NSLog(@"exteria: the notification settings did not sync: %@", errorName);
    }];
}

/* a sync writes the store once for every part of the settings it brings, and each write is a full redraw of the table; the changes of one turn of the run loop
   are drawn once */
- (void)scheduleRebuild {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rebuild) object:nil];
    [self performSelector:@selector(rebuild) withObject:nil afterDelay:0];
}

/* the page shows only how many exceptions each kind has, so a list with the same counts changes nothing on it */
static NSString *ExteriaExceptionCounts(NSArray *exceptions) {
    NSMutableString *counts = [NSMutableString string];
    for (ExteriaNotifyKind kind = ExteriaNotifyKindPrivate; kind <= ExteriaNotifyKindStories; ++kind) {
        [counts appendFormat:@"%lu,", (unsigned long)ExteriaNotifyExceptionsForKind(exceptions, kind).count];
    }
    return counts;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ExteriaWeakReference *weak = _weak;
    [_session loadNotifyExceptionsWithCompletion:^(NSArray *exceptions, NSString *errorName) {
        ExteriaNotificationsSettingsController *me = weak.target;
        if (!me) return;
        if (!exceptions) {
            NSLog(@"exteria: the notification exceptions did not load: %@", errorName);
            return;
        }
        BOOL same = me->_exceptions && [ExteriaExceptionCounts(me->_exceptions) isEqualToString:ExteriaExceptionCounts(exceptions)];
        [me->_exceptions release];
        me->_exceptions = [exceptions retain];
        if (!same) [me rebuild];
    }];
}

#pragma mark kinds

static NSString *ExteriaReactionsLine(const exteria_reaction_notify *r) {
    NSMutableArray *parts = [NSMutableArray array];
    if (r->messages_from != EXTERIA_REACTION_FROM_NOBODY) [parts addObject:NSLocalizedString(@"notif.reactions.messages", nil)];
    if (r->stories_from != EXTERIA_REACTION_FROM_NOBODY) [parts addObject:NSLocalizedString(@"notif.reactions.stories", nil)];
    return parts.count ? [parts componentsJoinedByString:@", "] : NSLocalizedString(@"notif.off", nil);
}

- (NSString *)lineForKind:(ExteriaNotifyKind)kind {
    int32_t now = ExteriaNotifyNow();
    if (kind == ExteriaNotifyKindReactions) {
        exteria_reaction_notify r = ExteriaNotifyReactionsStored();
        return ExteriaReactionsLine(&r);
    }
    NSArray *list = ExteriaNotifyExceptionsForKind(_exceptions, kind);
    NSString *state;
    if (kind == ExteriaNotifyKindStories) {
        exteria_peer_notify s = ExteriaNotifyScopeStored(EXTERIA_SCOPE_USERS);
        state = NSLocalizedString(s.has_stories_muted && !s.stories_muted ? @"notif.on" : @"notif.off", nil);
    } else {
        exteria_peer_notify s = ExteriaNotifyScopeStored(ExteriaNotifyScopeOfKind(kind));
        state = ExteriaNotifyMuteText(s.has_mute ? s.mute_until : 0);
        (void)now;
    }
    if (!list.count) return NSLocalizedString(@"notif.tap", nil);
    return [NSString stringWithFormat:@"%@, %@", state, ExteriaNotifyCountText(@"notif.exceptions", list.count)];
}

- (BOOL)kindEnabled:(ExteriaNotifyKind)kind {
    if (kind == ExteriaNotifyKindReactions) {
        exteria_reaction_notify r = ExteriaNotifyReactionsStored();
        return r.messages_from != EXTERIA_REACTION_FROM_NOBODY || r.stories_from != EXTERIA_REACTION_FROM_NOBODY;
    }
    if (kind == ExteriaNotifyKindStories) {
        exteria_peer_notify s = ExteriaNotifyScopeStored(EXTERIA_SCOPE_USERS);
        return s.has_stories_muted && !s.stories_muted;
    }
    exteria_peer_notify s = ExteriaNotifyScopeStored(ExteriaNotifyScopeOfKind(kind));
    return exteria_notify_mute_state(s.has_mute ? s.mute_until : 0, ExteriaNotifyNow()) == 0;
}

- (void)report:(NSString *)errorName {
    if (!errorName) return;
    NSLog(@"exteria: the notification settings were not kept: %@", errorName);
    ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
    [_session syncNotifySettingsWithCompletion:nil];
}

/* the switch of a kind on the main list: on or off at once; the exceptions are told of first tells of them */
- (void)setKind:(ExteriaNotifyKind)kind enabled:(BOOL)on {
    ExteriaWeakReference *weak = _weak;
    void (^apply)(void) = ^{
        ExteriaNotificationsSettingsController *me = weak.target;
        if (!me) return;
        if (kind == ExteriaNotifyKindReactions) {
            exteria_reaction_notify r = ExteriaNotifyReactionsStored();
            r.messages_from = r.stories_from = on ? EXTERIA_REACTION_FROM_EVERYONE : EXTERIA_REACTION_FROM_NOBODY;
            ExteriaNotifyReactionsStore(&r);
            [me->_session sendReactionNotifyWithCompletion:^(NSString *errorName) { [(ExteriaNotificationsSettingsController *)weak.target report:errorName]; }];
            return;
        }
        exteria_notify_scope scope = ExteriaNotifyScopeOfKind(kind);
        exteria_peer_notify s = ExteriaNotifyScopeStored(scope);
        if (kind == ExteriaNotifyKindStories) {
            /* off goes back to the stories of the people the person talks to most */
            s.has_stories_muted = on ? 1 : 0;
            s.stories_muted = 0;
        } else {
            s.has_mute = 1;
            s.mute_until = on ? 0 : EXTERIA_NOTIFY_MUTE_FOREVER;
        }
        ExteriaNotifyScopeStore(scope, &s);
        [me->_session sendNotifyScope:scope completion:^(NSString *errorName) { [(ExteriaNotificationsSettingsController *)weak.target report:errorName]; }];
    };
    NSArray *list = kind == ExteriaNotifyKindReactions ? nil : ExteriaNotifyExceptionsForKind(_exceptions, kind);
    if (!list.count) {
        apply();
        return;
    }
    NSString *about = ExteriaNotifyCountText(kind == ExteriaNotifyKindPrivate || kind == ExteriaNotifyKindStories ? @"notif.exceptions" : @"notif.chats", list.count);
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"notif.exceptions.alert", nil), about];
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.exceptions.view", nil), @"OK", nil];
    ExteriaSettingsChoose(self, message, options, ^(NSUInteger index) {
        ExteriaNotificationsSettingsController *me = weak.target;
        if (!me) return;
        if (index == 0) [me openKind:kind];
        else apply();
    });
    /* a cancelled sheet leaves the switch where the person put it, so the rows are drawn again from what is stored */
    [self rebuild];
}

- (void)openKind:(ExteriaNotifyKind)kind {
    ExteriaNotificationsKindController *page = [[[ExteriaNotificationsKindController alloc] initWithSession:_session avatars:_avatars media:_media kind:kind
                                                                                                  exceptions:_exceptions] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}

- (ExteriaSettingsRow *)rowForKind:(ExteriaNotifyKind)kind symbol:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone title:(NSString *)title {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *row = [ExteriaSettingsRow switchRowWithSymbol:symbol tone:tone title:title subtitle:[self lineForKind:kind] on:[self kindEnabled:kind]
                                                               toggle:^(BOOL on) { [(ExteriaNotificationsSettingsController *)weak.target setKind:kind enabled:on]; }];
    row.tap = ^{ [(ExteriaNotificationsSettingsController *)weak.target openKind:kind]; };
    return row;
}

#pragma mark rows

static ExteriaSettingsRow *ExteriaFlagRow(NSString *key, BOOL on, void (^set)(BOOL)) {
    return [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(key, nil) subtitle:nil on:on toggle:set];
}

- (NSString *)repeatText {
    NSInteger minutes = ExteriaNotifyRepeatMinutes();
    if (minutes == 0) return NSLocalizedString(@"notif.repeat.never", nil);
    if (minutes < 60) return [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.minutes", nil), (int)minutes];
    return [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.hours", nil), (int)(minutes / 60)];
}

- (void)chooseRepeat {
    static const NSInteger values[] = {0, 5, 10, 30, 60, 120, 240};
    NSMutableArray *options = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        NSInteger m = values[i];
        [options addObject:m == 0 ? NSLocalizedString(@"notif.repeat.never", nil)
                                  : (m < 60 ? [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.minutes", nil), (int)m]
                                            : [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.hours", nil), (int)(m / 60)])];
    }
    ExteriaSettingsChoose(self, NSLocalizedString(@"notif.repeat", nil), options, ^(NSUInteger index) { ExteriaNotifySetRepeatMinutes(values[index]); });
}

- (void)chooseCallVibration {
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.vibrate.default", nil), NSLocalizedString(@"notif.vibrate.off", nil), nil];
    ExteriaSettingsChoose(self, NSLocalizedString(@"notif.vibrate", nil), options, ^(NSUInteger index) { ExteriaNotifySetCallVibration(index == 0 ? 0 : 2); });
}

- (void)confirmReset {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"notif.reset.alert", nil), NSLocalizedString(@"notif.reset.confirm", nil), ^{
        ExteriaNotificationsSettingsController *me = weak.target;
        if (!me || me->_resetting) return;
        me->_resetting = YES;
        [me->_session resetAllNotifySettingsWithCompletion:^(NSString *errorName) {
            ExteriaNotificationsSettingsController *again = weak.target;
            if (!again) return;
            again->_resetting = NO;
            if (errorName) {
                ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                return;
            }
            [again->_exceptions release];
            again->_exceptions = nil;
            ExteriaShowNotice(nil, NSLocalizedString(@"notif.reset.done", nil));
            [again rebuild];
        }];
    });
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NSArray *kinds = [NSArray arrayWithObjects:
        [self rowForKind:ExteriaNotifyKindPrivate symbol:ExteriaSymbolPerson tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"notif.private", nil)],
        [self rowForKind:ExteriaNotifyKindGroups symbol:ExteriaSymbolGroupsMenu tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"notif.groups", nil)],
        [self rowForKind:ExteriaNotifyKindChannels symbol:ExteriaSymbolMegaphone tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"notif.channels", nil)],
        [self rowForKind:ExteriaNotifyKindStories symbol:ExteriaSymbolGallery tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"notif.stories", nil)],
        [self rowForKind:ExteriaNotifyKindReactions symbol:ExteriaSymbolHeart tone:ExteriaSettingsToneRed title:NSLocalizedString(@"notif.reactions", nil)], nil];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.chats.header", nil) footer:nil rows:kinds]];

    ExteriaSettingsRow *vibrate = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"notif.vibrate", nil)
                                                             value:NSLocalizedString(ExteriaNotifyCallVibration() == 0 ? @"notif.vibrate.default" : @"notif.vibrate.off", nil)
                                                               tap:^{ [(ExteriaNotificationsSettingsController *)weak.target chooseCallVibration]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.calls.header", nil) footer:nil rows:[NSArray arrayWithObject:vibrate]]];

    NSArray *badge = [NSArray arrayWithObjects:
        ExteriaFlagRow(@"notif.badge.show", ExteriaNotifyBadgeShown(), ^(BOOL on) { ExteriaNotifySetBadgeShown(on); }),
        ExteriaFlagRow(@"notif.badge.muted", ExteriaNotifyBadgeMuted(), ^(BOOL on) { ExteriaNotifySetBadgeMuted(on); }),
        ExteriaFlagRow(@"notif.badge.messages", ExteriaNotifyBadgeMessages(), ^(BOOL on) { ExteriaNotifySetBadgeMessages(on); }), nil];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.badge.header", nil) footer:nil rows:badge]];

    NSArray *inApp = [NSArray arrayWithObjects:
        ExteriaFlagRow(@"notif.inapp.sounds", ExteriaNotifyInAppSounds(), ^(BOOL on) { ExteriaNotifySetInAppSounds(on); }),
        ExteriaFlagRow(@"notif.inapp.vibrate", ExteriaNotifyInAppVibrate(), ^(BOOL on) { ExteriaNotifySetInAppVibrate(on); }),
        ExteriaFlagRow(@"notif.inapp.preview", ExteriaNotifyInAppPreview(), ^(BOOL on) { ExteriaNotifySetInAppPreview(on); }),
        ExteriaFlagRow(@"notif.inchat", ExteriaNotifyInChatSounds(), ^(BOOL on) { ExteriaNotifySetInChatSounds(on); }), nil];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.inapp.header", nil) footer:nil rows:inApp]];

    ExteriaSettingsRow *joined = ExteriaFlagRow(@"notif.contactjoined", ExteriaNotifyContactJoined(), ^(BOOL on) {
        ExteriaNotificationsSettingsController *me = weak.target;
        if (!me) return;
        BOOL before = !on;
        ExteriaNotifySetContactJoined(on);
        [me->_session setContactJoinedNotify:on completion:^(NSString *errorName) {
            if (!errorName) return;
            ExteriaNotifySetContactJoined(before);
            [(ExteriaNotificationsSettingsController *)weak.target report:errorName];
        }];
    });
    NSArray *events = [NSArray arrayWithObjects:joined, ExteriaFlagRow(@"notif.pinned", ExteriaNotifyPinnedMessages(), ^(BOOL on) { ExteriaNotifySetPinnedMessages(on); }), nil];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.events.header", nil) footer:nil rows:events]];

    NSMutableArray *other = [NSMutableArray array];
    [other addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.master", nil) subtitle:NSLocalizedString(@"notif.master.info", nil) on:ExteriaNotifyEnabled()
                                                     toggle:^(BOOL on) { ExteriaNotifySetEnabled(on); }]];
    if (ExteriaNotifySavingAvailable()) {
        [other addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"settings.notify.saving", nil) subtitle:NSLocalizedString(@"settings.notify.saving.subtitle", nil)
                                                             on:ExteriaNotifySaving() toggle:^(BOOL on) { ExteriaNotifySetSaving(on); }]];
    }
    /* the line about banners and the economy mode stands right under the two rows it is about, and the repeat has a card of its own */
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.other.header", nil) footer:NSLocalizedString(@"settings.notify.footer", nil) rows:other]];
    ExteriaSettingsRow *repeat = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"notif.repeat", nil) value:[self repeatText]
                                                              tap:^{ [(ExteriaNotificationsSettingsController *)weak.target chooseRepeat]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:repeat]]];

    ExteriaSettingsRow *reset = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolBroom tone:ExteriaSettingsToneRed title:NSLocalizedString(@"notif.reset", nil)
                                                         subtitle:NSLocalizedString(@"notif.reset.info", nil) value:nil
                                                              tap:^{ [(ExteriaNotificationsSettingsController *)weak.target confirmReset]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:reset]]];
    self.sections = sections;
}

@end
