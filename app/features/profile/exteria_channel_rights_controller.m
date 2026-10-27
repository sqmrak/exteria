#import "exteria_channel_rights_controller.h"

#include "exteria_channel.h"

#import "exteria_channel_field_controller.h"
#import "exteria_channel_errors.h"
#import "exteria_gift_screen.h"
#import "exteria_sheet.h"
#import "exteria_weak_reference.h"

typedef struct {
    uint32_t bit;
    const char *key;
} ExteriaRightEntry;

/* the rights of a broadcast channel, in the order lists them */
static const ExteriaRightEntry ExteriaChannelRights[] = {
    {EXTERIA_ADMIN_CHANGE_INFO, "channel.right.info"},
    {EXTERIA_ADMIN_POST_MESSAGES, "channel.right.post"},
    {EXTERIA_ADMIN_EDIT_MESSAGES, "channel.right.edit"},
    {EXTERIA_ADMIN_DELETE_MESSAGES, "channel.right.delete"},
    {EXTERIA_ADMIN_INVITE_USERS, "channel.right.invite"},
    {EXTERIA_ADMIN_MANAGE_CALL, "channel.right.call"},
    {EXTERIA_ADMIN_ADD_ADMINS, "channel.right.admins"},
};

/* and of a group */
static const ExteriaRightEntry ExteriaGroupRights[] = {
    {EXTERIA_ADMIN_CHANGE_INFO, "group.right.info"},
    {EXTERIA_ADMIN_DELETE_MESSAGES, "channel.right.delete"},
    {EXTERIA_ADMIN_BAN_USERS, "group.right.ban"},
    {EXTERIA_ADMIN_INVITE_USERS, "group.right.invite"},
    {EXTERIA_ADMIN_PIN_MESSAGES, "group.right.pin"},
    {EXTERIA_ADMIN_MANAGE_CALL, "group.right.call"},
    {EXTERIA_ADMIN_ANONYMOUS, "group.right.anonymous"},
    {EXTERIA_ADMIN_ADD_ADMINS, "channel.right.admins"},
};

/* what a new admin starts with: the usual set, without the right to appoint others and to hide behind the group */
#define NEW_ADMIN_BASE (EXTERIA_ADMIN_ALL & ~(EXTERIA_ADMIN_ADD_ADMINS | EXTERIA_ADMIN_ANONYMOUS | EXTERIA_ADMIN_MANAGE_TOPICS))

@interface ExteriaChannelRightsController () {
    ExteriaSession *_session;
    ExteriaFullChannel *_channel;
    ExteriaPerson *_person;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    NSString *_rank;
    uint32_t _rights;
    uint32_t _grantable;
    BOOL _isAdmin;
    BOOL _busy;
    void (^_changedHandler)(void);
}
@end

@implementation ExteriaChannelRightsController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel person:(ExteriaPerson *)person rights:(uint32_t)rights
                 rank:(NSString *)rank isAdmin:(BOOL)isAdmin avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _channel = [channel retain];
    _person = [person retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _isAdmin = isAdmin;
    _rank = [rank copy];
    /* only what the account holds can be handed on; the creator holds everything */
    _grantable = channel.creator ? EXTERIA_ADMIN_ALL : channel.adminRights;
    _rights = isAdmin ? rights : (NEW_ADMIN_BASE & _grantable);
    self.pageTitle = NSLocalizedString(@"channel.rights.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_channel release];
    [_person release];
    [_avatars release];
    [_media release];
    [_rank release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    ExteriaSettingsRow *who = [ExteriaSettingsRow rowWithTitle:_person.name subtitle:_person.username.length ? [@"@" stringByAppendingString:_person.username] : nil
                                                         value:NSLocalizedString(_isAdmin ? @"channel.role.admin" : @"channel.role.member", nil) tap:nil];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:who]]];

    BOOL group = _channel.megagroup;
    const ExteriaRightEntry *table = group ? ExteriaGroupRights : ExteriaChannelRights;
    size_t count = group ? sizeof(ExteriaGroupRights) / sizeof(ExteriaGroupRights[0]) : sizeof(ExteriaChannelRights) / sizeof(ExteriaChannelRights[0]);
    NSMutableArray *rights = [NSMutableArray array];
    for (size_t i = 0; i < count; ++i) {
        uint32_t bit = table[i].bit;
        ExteriaSettingsRow *row = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString([NSString stringWithUTF8String:table[i].key], nil) subtitle:nil
                                                                      on:(_rights & bit) != 0 toggle:^(BOOL on) {
            ExteriaChannelRightsController *me = weak.target;
            if (!me) return;
            if (on) me->_rights |= bit;
            else me->_rights &= ~bit;
        }];
        row.disabled = (_grantable & bit) == 0;
        [rights addObject:row];
    }
    NSString *footer = _grantable == EXTERIA_ADMIN_ALL ? nil : NSLocalizedString(@"channel.rights.footer", nil);
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"channel.rights.header", nil) footer:footer rows:rights]];

    ExteriaSettingsRow *rank = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"channel.rights.rank", nil)
                                                          value:_rank.length ? _rank : NSLocalizedString(@"channel.rights.rank.none", nil) tap:^{
        [(ExteriaChannelRightsController *)weak.target editRank];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"channel.rank.hint", nil) rows:[NSArray arrayWithObject:rank]]];

    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolCheck title:NSLocalizedString(@"channel.save", nil) destructive:NO tap:^{
        [(ExteriaChannelRightsController *)weak.target save];
    }]];
    if (_isAdmin) {
        [actions addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolLogout title:NSLocalizedString(@"channel.rights.dismiss", nil) destructive:YES tap:^{
            [(ExteriaChannelRightsController *)weak.target askDismiss];
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:actions]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)editRank {
    ExteriaWeakReference *weak = _weak;
    ExteriaChannelFieldController *field = [[[ExteriaChannelFieldController alloc] initWithSession:_session avatars:_avatars media:_media
                                                                                               kind:ExteriaChannelFieldRank text:_rank dialog:nil
                                                                                               save:^(NSString *text, void (^done)(NSString *)) {
        ExteriaChannelRightsController *me = weak.target;
        if (me) {
            [me->_rank release];
            me->_rank = [text copy];
            [me rebuild];
        }
        /* the title is sent with the rights, so there is nothing to ask the server yet */
        done(nil);
    }] autorelease];
    [self.navigationController pushViewController:field animated:YES];
}

- (void)finishWithError:(NSString *)errorName {
    _busy = NO;
    if (errorName) {
        ExteriaGiftAlert(nil, ExteriaChannelErrorText(errorName));
        return;
    }
    if (_changedHandler) _changedHandler();
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)save {
    if (_busy) return;
    /* an admin with no right left is a subscriber again, which has its own way out */
    if (!_rights) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"channel.rights.none", nil));
        return;
    }
    _busy = YES;
    [self retain];
    [_session setAdminRights:_rights rank:_rank ofPerson:_person inDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        [self finishWithError:errorName];
    }];
}

- (void)askDismiss {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, [NSString stringWithFormat:NSLocalizedString(@"channel.rights.dismiss.confirm", nil), _person.name],
                         NSLocalizedString(@"channel.rights.dismiss", nil), ^{ [(ExteriaChannelRightsController *)weak.target dismissNow]; });
}

- (void)dismissNow {
    if (_busy) return;
    _busy = YES;
    [self retain];
    [_session setAdminRights:0 rank:nil ofPerson:_person inDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        [self finishWithError:errorName];
    }];
}

@end
