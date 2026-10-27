#import "exteria_channel_manage_controller.h"

#include "exteria_channel.h"

#import "exteria_channel_field_controller.h"
#import "exteria_channel_errors.h"
#import "exteria_channel_members_controller.h"
#import "exteria_gift_screen.h"
#import "exteria_weak_reference.h"

@interface ExteriaChannelManageController () {
    ExteriaSession *_session;
    ExteriaFullChannel *_channel;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    BOOL _signaturesBusy;
    void (^_changedHandler)(ExteriaFullChannel *channel);
}
@end

@implementation ExteriaChannelManageController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _channel = [channel retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(channel.megagroup ? @"channel.manage.title.group" : @"channel.manage.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_channel release];
    [_avatars release];
    [_media release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    /* the counts and rights shown on opening came with the profile; the server may have moved on since */
    [self refresh];
}

#pragma mark content

static NSString *ExteriaCount(NSInteger count) {
    return count > 0 ? [NSString stringWithFormat:@"%ld", (long)count] : nil;
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaFullChannel *channel = _channel;
    uint32_t rights = channel.adminRights;
    NSMutableArray *sections = [NSMutableArray array];

    if (rights & EXTERIA_ADMIN_CHANGE_INFO) {
        NSMutableArray *rows = [NSMutableArray array];
        [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolCompose tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"channel.field.title", nil)
                                                 subtitle:nil value:channel.dialog.title tap:^{ [(ExteriaChannelManageController *)weak.target editTitle]; }]];
        NSString *about = channel.about.length ? channel.about : NSLocalizedString(@"channel.about.none", nil);
        [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolInfo tone:ExteriaSettingsToneCyan title:NSLocalizedString(@"channel.field.about", nil)
                                                 subtitle:about value:nil tap:^{ [(ExteriaChannelManageController *)weak.target editAbout]; }]];
        /* only the creator decides whether the channel is public */
        if (channel.creator) {
            NSString *link = channel.username.length ? [@"t.me/" stringByAppendingString:channel.username] : NSLocalizedString(@"channel.kind.private", nil);
            [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolLink tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"channel.field.link", nil)
                                                     subtitle:nil value:link tap:^{ [(ExteriaChannelManageController *)weak.target editUsername]; }]];
        }
        if (!channel.megagroup) {
            [rows addObject:[ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolPerson tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"channel.signatures", nil)
                                                           subtitle:NSLocalizedString(@"channel.signatures.info", nil) on:channel.signatures toggle:^(BOOL on) {
                [(ExteriaChannelManageController *)weak.target setSignatures:on];
            }]];
        }
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"channel.manage.info", nil) footer:nil rows:rows]];
    }

    NSMutableArray *people = [NSMutableArray array];
    [people addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolMember tone:ExteriaSettingsToneBlueDeep
                                                  title:NSLocalizedString(channel.megagroup ? @"channel.members" : @"channel.subscribers", nil) subtitle:nil
                                                  value:ExteriaCount(channel.participants) tap:^{
        [(ExteriaChannelManageController *)weak.target openList:ExteriaChannelListSubscribers];
    }]];
    [people addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolStar tone:ExteriaSettingsToneOrangeBright title:NSLocalizedString(@"channel.admins", nil) subtitle:nil
                                                  value:ExteriaCount(channel.admins) tap:^{
        [(ExteriaChannelManageController *)weak.target openList:ExteriaChannelListAdmins];
    }]];
    if (rights & EXTERIA_ADMIN_BAN_USERS) {
        [people addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolBlock tone:ExteriaSettingsToneRed title:NSLocalizedString(@"channel.banned", nil) subtitle:nil
                                                      value:ExteriaCount(channel.banned) tap:^{
            [(ExteriaChannelManageController *)weak.target openList:ExteriaChannelListBlacklist];
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"channel.manage.people", nil) footer:nil rows:people]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)refresh {
    ExteriaWeakReference *weak = _weak;
    [self retain];
    [_session loadFullChannelOfDialog:_channel.dialog completion:^(ExteriaFullChannel *channel, NSString *errorName) {
        [self autorelease];
        ExteriaChannelManageController *me = weak.target;
        if (!me) return;
        if (!channel) {
            NSLog(@"exteria: the channel %lld did not reload: %@", me->_channel.dialog.peerId, errorName);
            return;
        }
        [me->_channel release];
        me->_channel = [channel retain];
        [me rebuild];
        if (me->_changedHandler) me->_changedHandler(channel);
    }];
}

#pragma mark editing

/* an answer that says the value is already what was asked for is not a failure */
static NSString *ExteriaUnlessUnchanged(NSString *errorName) {
    if ([errorName isEqualToString:@"CHAT_NOT_MODIFIED"] || [errorName isEqualToString:@"CHAT_ABOUT_NOT_MODIFIED"] ||
        [errorName isEqualToString:@"USERNAME_NOT_MODIFIED"] || [errorName isEqualToString:@"NOT_MODIFIED"]) return nil;
    return errorName;
}

- (void)pushField:(ExteriaChannelFieldKind)kind text:(NSString *)text save:(void (^)(NSString *text, void (^done)(NSString *errorName)))save {
    ExteriaChannelFieldController *field = [[[ExteriaChannelFieldController alloc] initWithSession:_session avatars:_avatars media:_media kind:kind text:text
                                                                                            dialog:_channel.dialog save:save] autorelease];
    [self.navigationController pushViewController:field animated:YES];
}

/* the write finished: the profile list shows the new title, and this screen asks the server for the rest */
- (void)writeDone:(NSString *)errorName {
    if (errorName) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
    [self refresh];
}

- (void)editTitle {
    ExteriaWeakReference *weak = _weak;
    [self pushField:ExteriaChannelFieldTitle text:_channel.dialog.title save:^(NSString *text, void (^done)(NSString *)) {
        ExteriaChannelManageController *me = weak.target;
        if (!me) { done(nil); return; }
        [me->_session setTitle:text ofDialog:me->_channel.dialog completion:^(NSString *errorName) {
            NSString *error = ExteriaUnlessUnchanged(errorName);
            [(ExteriaChannelManageController *)weak.target writeDone:error];
            done(error);
        }];
    }];
}

- (void)editAbout {
    ExteriaWeakReference *weak = _weak;
    [self pushField:ExteriaChannelFieldAbout text:_channel.about save:^(NSString *text, void (^done)(NSString *)) {
        ExteriaChannelManageController *me = weak.target;
        if (!me) { done(nil); return; }
        [me->_session setAbout:text ofDialog:me->_channel.dialog completion:^(NSString *errorName) {
            NSString *error = ExteriaUnlessUnchanged(errorName);
            [(ExteriaChannelManageController *)weak.target writeDone:error];
            done(error);
        }];
    }];
}

- (void)editUsername {
    ExteriaWeakReference *weak = _weak;
    [self pushField:ExteriaChannelFieldUsername text:_channel.username save:^(NSString *text, void (^done)(NSString *)) {
        ExteriaChannelManageController *me = weak.target;
        if (!me) { done(nil); return; }
        [me->_session setUsername:text ofDialog:me->_channel.dialog completion:^(NSString *errorName) {
            NSString *error = ExteriaUnlessUnchanged(errorName);
            [(ExteriaChannelManageController *)weak.target writeDone:error];
            done(error);
        }];
    }];
}

- (void)setSignatures:(BOOL)enabled {
    if (_signaturesBusy) return;
    _signaturesBusy = YES;
    ExteriaWeakReference *weak = _weak;
    [self retain];
    [_session setSignatures:enabled ofDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        ExteriaChannelManageController *me = weak.target;
        if (!me) return;
        me->_signaturesBusy = NO;
        NSString *error = ExteriaUnlessUnchanged(errorName);
        if (error) ExteriaGiftAlert(nil, ExteriaChannelErrorText(error));
        /* a failed switch goes back to what the server has, a good one is confirmed by it */
        [me refresh];
    }];
}

#pragma mark lists

- (void)openList:(ExteriaChannelList)list {
    ExteriaChannelMembersController *members = [[[ExteriaChannelMembersController alloc] initWithSession:_session channel:_channel list:list avatars:_avatars
                                                                                                   media:_media] autorelease];
    ExteriaWeakReference *weak = _weak;
    members.changedHandler = ^{ [(ExteriaChannelManageController *)weak.target refresh]; };
    [self.navigationController pushViewController:members animated:YES];
}

@end
