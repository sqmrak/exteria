#import "exteria_notifications_kind_controller.h"

#import "exteria_alert.h"
#import "exteria_dialog.h"
#import "exteria_dialog_picker_controller.h"
#import "exteria_notifications_chat_controller.h"
#import "exteria_notifications_sound_controller.h"
#import "exteria_notify_store.h"
#import "exteria_sheet.h"
#import "exteria_weak_reference.h"

@interface ExteriaNotificationsKindController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    ExteriaNotifyKind _kind;
    NSArray *_all;
    BOOL _loadedOnce;
    exteria_reaction_from _lastMessagesFrom;
    exteria_reaction_from _lastStoriesFrom;
}
@end

@implementation ExteriaNotificationsKindController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media kind:(ExteriaNotifyKind)kind exceptions:(NSArray *)exceptions {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _kind = kind;
    _all = [exceptions retain];
    exteria_reaction_notify reactions = ExteriaNotifyReactionsStored();
    _lastMessagesFrom = reactions.messages_from == EXTERIA_REACTION_FROM_CONTACTS ? EXTERIA_REACTION_FROM_CONTACTS : EXTERIA_REACTION_FROM_EVERYONE;
    _lastStoriesFrom = reactions.stories_from == EXTERIA_REACTION_FROM_CONTACTS ? EXTERIA_REACTION_FROM_CONTACTS : EXTERIA_REACTION_FROM_EVERYONE;
    NSString *titles[] = {@"notif.private", @"notif.groups", @"notif.channels", @"notif.stories", @"notif.reactions", @"notif.exceptions.title"};
    self.pageTitle = NSLocalizedString(titles[kind], nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_all release];
    [super dealloc];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeChanged) name:ExteriaNotifyStoreDidChangeNotification object:nil];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadExceptions];
}

- (void)storeChanged {
    [self rebuild];
}

- (void)reloadExceptions {
    if (_kind == ExteriaNotifyKindReactions) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadNotifyExceptionsWithCompletion:^(NSArray *exceptions, NSString *errorName) {
        ExteriaNotificationsKindController *me = weak.target;
        if (!me) return;
        if (!exceptions) {
            NSLog(@"exteria: the notification exceptions did not load: %@", errorName);
            return;
        }
        [me->_all release];
        me->_all = [exceptions retain];
        me->_loadedOnce = YES;
        [me rebuild];
    }];
}

#pragma mark sending

/* stores the new state of a kind and sends it; a refusal puts the old state back */
- (void)changeScope:(void (^)(exteria_peer_notify *settings))change {
    exteria_notify_scope scope = ExteriaNotifyScopeOfKind(_kind);
    exteria_peer_notify before = ExteriaNotifyScopeStored(scope), after = before;
    change(&after);
    ExteriaNotifyScopeStore(scope, &after);
    ExteriaWeakReference *weak = _weak;
    [_session sendNotifyScope:scope completion:^(NSString *errorName) {
        if (!errorName) return;
        NSLog(@"exteria: the notification settings were not kept: %@", errorName);
        ExteriaNotifyScopeStore(scope, &before);
        ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
        [(ExteriaNotificationsKindController *)weak.target rebuild];
    }];
}

- (void)changeReactions:(void (^)(exteria_reaction_notify *settings))change {
    exteria_reaction_notify before = ExteriaNotifyReactionsStored(), after = before;
    change(&after);
    ExteriaNotifyReactionsStore(&after);
    ExteriaWeakReference *weak = _weak;
    [_session sendReactionNotifyWithCompletion:^(NSString *errorName) {
        if (!errorName) return;
        NSLog(@"exteria: the reaction settings were not kept: %@", errorName);
        ExteriaNotifyReactionsStore(&before);
        ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
        [(ExteriaNotificationsKindController *)weak.target rebuild];
    }];
}

#pragma mark rows

- (BOOL)storiesAll {
    exteria_peer_notify s = ExteriaNotifyScopeStored(EXTERIA_SCOPE_USERS);
    return s.has_stories_muted && !s.stories_muted;
}

- (BOOL)storiesAuto {
    return !ExteriaNotifyScopeStored(EXTERIA_SCOPE_USERS).has_stories_muted;
}

static NSString *ExteriaFromText(int32_t from) {
    if (from == EXTERIA_REACTION_FROM_NOBODY) return NSLocalizedString(@"notif.from.nobody", nil);
    return NSLocalizedString(from == EXTERIA_REACTION_FROM_CONTACTS ? @"notif.from.contacts" : @"notif.from.everyone", nil);
}

- (void)chooseReactionsFrom:(BOOL)stories {
    ExteriaWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.from.pick.everyone", nil), NSLocalizedString(@"notif.from.pick.contacts", nil), nil];
    ExteriaSettingsChoose(self, NSLocalizedString(@"notif.from.title", nil), options, ^(NSUInteger index) {
        ExteriaNotificationsKindController *me = weak.target;
        exteria_reaction_from from = index == 0 ? EXTERIA_REACTION_FROM_EVERYONE : EXTERIA_REACTION_FROM_CONTACTS;
        if (stories) me->_lastStoriesFrom = from;
        else me->_lastMessagesFrom = from;
        [me changeReactions:^(exteria_reaction_notify *r) {
            if (stories) r->stories_from = from;
            else r->messages_from = from;
        }];
    });
}

/* the kind is turned off for a while or for good, or on */
- (void)chooseMuteForKind {
    ExteriaWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.mute.on", nil), NSLocalizedString(@"notif.mute.1h", nil), NSLocalizedString(@"notif.mute.2d", nil),
                        NSLocalizedString(@"notif.mute.off", nil), nil];
    ExteriaSettingsChoose(self, nil, options, ^(NSUInteger index) {
        int32_t now = ExteriaNotifyNow();
        int32_t until = index == 0 ? 0 : (index == 1 ? now + 3600 : (index == 2 ? now + 48 * 3600 : EXTERIA_NOTIFY_MUTE_FOREVER));
        [(ExteriaNotificationsKindController *)weak.target changeScope:^(exteria_peer_notify *s) {
            s->has_mute = 1;
            s->mute_until = until;
        }];
    });
}

- (void)openSound {
    ExteriaWeakReference *weak = _weak;
    BOOL stories = _kind == ExteriaNotifyKindStories, reactions = _kind == ExteriaNotifyKindReactions;
    exteria_notify_sound sound;
    BOOL has;
    memset(&sound, 0, sizeof(sound));
    if (reactions) {
        sound = ExteriaNotifyReactionsStored().sound;
        has = YES;
    } else {
        exteria_peer_notify s = ExteriaNotifyScopeStored(ExteriaNotifyScopeOfKind(_kind));
        sound = stories ? s.stories_sound : s.sound;
        has = stories ? s.has_stories_sound : s.has_sound;
    }
    ExteriaNotificationsSoundController *page = [[[ExteriaNotificationsSoundController alloc] initWithSession:_session media:_media title:self.pageTitle
        current:has ? [NSValue valueWithBytes:&sound objCType:@encode(exteria_notify_sound)] : nil apply:^(exteria_notify_sound picked) {
        ExteriaNotificationsKindController *me = weak.target;
        if (!me) return;
        if (reactions) {
            [me changeReactions:^(exteria_reaction_notify *r) { r->sound = picked; }];
        } else {
            [me changeScope:^(exteria_peer_notify *s) {
                if (stories) {
                    s->has_stories_sound = 1;
                    s->stories_sound = picked;
                } else {
                    s->has_sound = 1;
                    s->sound = picked;
                }
            }];
        }
    }] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}

- (NSString *)exceptionLine:(ExteriaNotifyException *)exception {
    exteria_peer_notify n = exception.settings;
    if (_kind == ExteriaNotifyKindStories) {
        return NSLocalizedString(n.has_stories_muted && n.stories_muted ? @"notif.off" : @"notif.on", nil);
    }
    exteria_peer_notify kind = ExteriaNotifyScopeStored(exception.peerKind == 1 ? EXTERIA_SCOPE_USERS : (exception.broadcast ? EXTERIA_SCOPE_BROADCASTS : EXTERIA_SCOPE_CHATS));
    int32_t until = n.has_mute ? n.mute_until : (kind.has_mute ? kind.mute_until : 0);
    return ExteriaNotifyMuteText(until);
}

- (ExteriaSettingsRow *)rowForException:(ExteriaNotifyException *)exception {
    ExteriaWeakReference *weak = _weak;
    NSString *title = exception.deleted || !exception.title.length ? NSLocalizedString(@"notif.chat.new", nil) : exception.title;
    if (exception.deleted && exception.title.length == 0) title = [NSString stringWithFormat:@"%lld", exception.peerId];
    return [ExteriaSettingsRow rowWithTileImage:ExteriaNotifyInitialsTile(exception.title, exception.peerId, 36) title:title subtitle:[self exceptionLine:exception]
                                            tap:^{ [(ExteriaNotificationsKindController *)weak.target actOnException:exception]; }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    BOOL onlyExceptions = _kind == ExteriaNotifyKindAllExceptions;
    exteria_notify_scope scope = ExteriaNotifyScopeOfKind(_kind);
    exteria_peer_notify stored = ExteriaNotifyScopeStored(scope);
    exteria_reaction_notify reactions = ExteriaNotifyReactionsStored();
    int32_t now = ExteriaNotifyNow();
    if (!onlyExceptions) {
        NSMutableArray *about = [NSMutableArray array];
        NSString *footer = nil;
        if (_kind == ExteriaNotifyKindStories) {
            BOOL all = [self storiesAll];
            [about addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.about.stories", nil) subtitle:nil on:all toggle:^(BOOL on) {
                [(ExteriaNotificationsKindController *)weak.target changeScope:^(exteria_peer_notify *s) {
                    s->has_stories_muted = 1;
                    s->stories_muted = !on;
                }];
            }]];
            if (!all) {
                [about addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.about.important", nil) subtitle:nil on:[self storiesAuto] toggle:^(BOOL on) {
                    [(ExteriaNotificationsKindController *)weak.target changeScope:^(exteria_peer_notify *s) {
                        s->has_stories_muted = on ? 0 : 1;
                        s->stories_muted = on ? 0 : 1;
                    }];
                }]];
            }
            footer = NSLocalizedString(@"notif.about.important.info", nil);
        } else if (_kind == ExteriaNotifyKindReactions) {
            ExteriaSettingsRow *messages = [ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolChats tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"notif.about.reactions.messages", nil)
                                                                         subtitle:ExteriaFromText(reactions.messages_from) on:reactions.messages_from != EXTERIA_REACTION_FROM_NOBODY toggle:^(BOOL on) {
                ExteriaNotificationsKindController *me = weak.target;
                [me changeReactions:^(exteria_reaction_notify *r) { r->messages_from = on ? me->_lastMessagesFrom : EXTERIA_REACTION_FROM_NOBODY; }];
            }];
            messages.tap = ^{ [(ExteriaNotificationsKindController *)weak.target chooseReactionsFrom:NO]; };
            ExteriaSettingsRow *stories = [ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolGallery tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"notif.about.reactions.stories", nil)
                                                                         subtitle:ExteriaFromText(reactions.stories_from) on:reactions.stories_from != EXTERIA_REACTION_FROM_NOBODY toggle:^(BOOL on) {
                ExteriaNotificationsKindController *me = weak.target;
                [me changeReactions:^(exteria_reaction_notify *r) { r->stories_from = on ? me->_lastStoriesFrom : EXTERIA_REACTION_FROM_NOBODY; }];
            }];
            stories.tap = ^{ [(ExteriaNotificationsKindController *)weak.target chooseReactionsFrom:YES]; };
            [about addObject:messages];
            [about addObject:stories];
        } else {
            NSString *titles[] = {@"notif.about.private", @"notif.about.groups", @"notif.about.channels"};
            BOOL enabled = exteria_notify_mute_state(stored.has_mute ? stored.mute_until : 0, now) == 0;
            [about addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(titles[_kind], nil) subtitle:nil on:enabled toggle:^(BOOL on) {
                ExteriaNotificationsKindController *me = weak.target;
                if (on) {
                    [me changeScope:^(exteria_peer_notify *s) {
                        s->has_mute = 1;
                        s->mute_until = 0;
                    }];
                } else {
                    [me rebuild];
                    [me chooseMuteForKind];
                }
            }]];
        }
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.notifyme", nil) footer:footer rows:about]];

        NSMutableArray *options = [NSMutableArray array];
        if (_kind == ExteriaNotifyKindStories) {
            [options addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.sendernames", nil) subtitle:nil on:!(stored.has_stories_hide_sender && stored.stories_hide_sender)
                                                               toggle:^(BOOL on) {
                [(ExteriaNotificationsKindController *)weak.target changeScope:^(exteria_peer_notify *s) {
                    s->has_stories_hide_sender = 1;
                    s->stories_hide_sender = !on;
                }];
            }]];
        } else if (_kind == ExteriaNotifyKindReactions) {
            [options addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.sendernames", nil) subtitle:nil on:reactions.previews toggle:^(BOOL on) {
                [(ExteriaNotificationsKindController *)weak.target changeReactions:^(exteria_reaction_notify *r) { r->previews = on; }];
            }]];
        } else {
            [options addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.preview", nil) subtitle:nil on:stored.has_previews ? stored.previews : YES toggle:^(BOOL on) {
                [(ExteriaNotificationsKindController *)weak.target changeScope:^(exteria_peer_notify *s) {
                    s->has_previews = 1;
                    s->previews = on;
                }];
            }]];
        }
        exteria_notify_sound shown;
        BOOL has;
        if (_kind == ExteriaNotifyKindReactions) {
            shown = reactions.sound;
            has = YES;
        } else if (_kind == ExteriaNotifyKindStories) {
            shown = stored.stories_sound;
            has = stored.has_stories_sound;
        } else {
            shown = stored.sound;
            has = stored.has_sound;
        }
        [options addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"notif.sound", nil) value:ExteriaNotifySoundText(has, &shown)
                                                        tap:^{ [(ExteriaNotificationsKindController *)weak.target openSound]; }]];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"notif.settings.header", nil) footer:nil rows:options]];
    }
    if (_kind != ExteriaNotifyKindReactions) {
        NSArray *list = ExteriaNotifyExceptionsForKind(_all, _kind);
        NSMutableArray *rows = [NSMutableArray array];
        if (!onlyExceptions) {
            [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolPlusCircle tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"notif.exceptions.add", nil) subtitle:nil value:nil
                                                          tap:^{ [(ExteriaNotificationsKindController *)weak.target addException]; }]];
        }
        for (ExteriaNotifyException *exception in list) [rows addObject:[self rowForException:exception]];
        NSString *footer = (onlyExceptions && !list.count && _loadedOnce) ? NSLocalizedString(@"notif.exceptions.empty", nil) : nil;
        if (rows.count) [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
        else if (footer) [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:[NSArray array]]];
        if (list.count) {
            ExteriaSettingsRow *deleteAll = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolTrash title:NSLocalizedString(@"notif.exceptions.deleteall", nil) destructive:YES
                                                                                tap:^{ [(ExteriaNotificationsKindController *)weak.target confirmDeleteAll]; }];
            [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:deleteAll]]];
        }
    }
    self.sections = sections;
}

#pragma mark exceptions

- (void)addException {
    ExteriaWeakReference *weak = _weak;
    ExteriaNotifyKind kind = _kind;
    ExteriaDialogPickerController *picker = [[[ExteriaDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.limit = 1;
    picker.filter = ^BOOL(ExteriaDialog *dialog) {
        if (dialog.folder || dialog.saved || dialog.community || dialog.deleted) return NO;
        if (kind == ExteriaNotifyKindPrivate) return dialog.peerKind == 1;
        if (kind == ExteriaNotifyKindGroups) return dialog.kind == EXTERIA_DIALOG_GROUP;
        if (kind == ExteriaNotifyKindChannels) return dialog.kind == EXTERIA_DIALOG_CHANNEL;
        return kind == ExteriaNotifyKindStories ? dialog.peerKind == 1 : YES;
    };
    picker.pickHandler = ^(NSArray *dialogs) {
        ExteriaNotificationsKindController *me = weak.target;
        ExteriaDialog *dialog = dialogs.count ? [dialogs objectAtIndex:0] : nil;
        if (!me || !dialog) return;
        if (kind == ExteriaNotifyKindStories) {
            /* a person is added to the stories exceptions as one that notifies, or not, against the setting of the kind */
            exteria_peer_notify s;
            memset(&s, 0, sizeof(s));
            s.has_stories_muted = 1;
            s.stories_muted = [me storiesAll] ? 1 : 0;
            [me->_session updateNotify:[NSValue valueWithBytes:&s objCType:@encode(exteria_peer_notify)] ofPeerKind:dialog.peerKind id:dialog.peerId hash:dialog.peerHash topic:0
                            completion:^(NSString *errorName) {
                if (errorName) ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                [(ExteriaNotificationsKindController *)weak.target reloadExceptions];
            }];
            return;
        }
        ExteriaNotificationsChatController *page = [[[ExteriaNotificationsChatController alloc] initWithSession:me->_session media:me->_media peerKind:dialog.peerKind
                                                                                                         peerId:dialog.peerId peerHash:dialog.peerHash
                                                                                                        channel:dialog.kind == EXTERIA_DIALOG_CHANNEL topic:0 title:dialog.title] autorelease];
        [me.navigationController pushViewController:page animated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)actOnException:(ExteriaNotifyException *)exception {
    ExteriaWeakReference *weak = _weak;
    BOOL stories = _kind == ExteriaNotifyKindStories;
    NSMutableArray *options = [NSMutableArray array];
    exteria_peer_notify n = exception.settings;
    if (stories) {
        BOOL muted = n.has_stories_muted && n.stories_muted;
        [options addObject:NSLocalizedString(muted ? @"notif.story.unmute" : @"notif.story.mute", nil)];
    } else {
        [options addObject:NSLocalizedString(@"notif.exception.customize", nil)];
    }
    [options addObject:NSLocalizedString(@"notif.exception.delete", nil)];
    ExteriaSettingsChoose(self, exception.title, options, ^(NSUInteger index) {
        ExteriaNotificationsKindController *me = weak.target;
        if (!me) return;
        if (index == 1) {
            [me deleteException:exception];
        } else if (stories) {
            exteria_peer_notify s = exception.settings;
            s.has_stories_muted = 1;
            s.stories_muted = !(n.has_stories_muted && n.stories_muted);
            [me->_session updateNotify:[NSValue valueWithBytes:&s objCType:@encode(exteria_peer_notify)] ofPeerKind:exception.peerKind id:exception.peerId hash:exception.peerHash
                                 topic:0 completion:^(NSString *errorName) {
                if (errorName) ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                [(ExteriaNotificationsKindController *)weak.target reloadExceptions];
            }];
        } else {
            ExteriaNotificationsChatController *page = [[[ExteriaNotificationsChatController alloc] initWithSession:me->_session media:me->_media peerKind:exception.peerKind
                                                                                                             peerId:exception.peerId peerHash:exception.peerHash
                                                                                                            channel:exception.broadcast topic:0 title:exception.title] autorelease];
            [me.navigationController pushViewController:page animated:YES];
        }
    });
}

- (void)deleteException:(ExteriaNotifyException *)exception {
    ExteriaWeakReference *weak = _weak;
    [_session resetNotifyOfPeerKind:exception.peerKind id:exception.peerId hash:exception.peerHash topic:0 completion:^(NSString *errorName) {
        if (errorName) ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
        [(ExteriaNotificationsKindController *)weak.target reloadExceptions];
    }];
}

- (void)confirmDeleteAll {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"notif.exceptions.deleteall.alert", nil), NSLocalizedString(@"notif.exceptions.deleteall", nil), ^{
        ExteriaNotificationsKindController *me = weak.target;
        if (!me) return;
        NSArray *list = ExteriaNotifyExceptionsForKind(me->_all, me->_kind);
        __block NSUInteger pending = list.count;
        for (ExteriaNotifyException *exception in list) {
            [me->_session resetNotifyOfPeerKind:exception.peerKind id:exception.peerId hash:exception.peerHash topic:0 completion:^(NSString *errorName) {
                if (errorName) NSLog(@"exteria: an exception was not removed: %@", errorName);
                if (--pending == 0) [(ExteriaNotificationsKindController *)weak.target reloadExceptions];
            }];
        }
    });
}

@end
