#import "exteria_channel_members_controller.h"
#import "exteria_centered_hint_field.h"

#import <QuartzCore/QuartzCore.h>

#include "exteria_channel.h"

#import "exteria_channel_rights_controller.h"
#import "exteria_person_cell.h"
#import "exteria_channel_errors.h"
#import "exteria_settings_kit.h"
#import "exteria_sheet.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define SEARCH_HEIGHT 52.0
#define SEARCH_DELAY 0.35
#define ADD_ROW_HEIGHT 56.0

typedef enum {
    ExteriaMemberActionAdmin,
    ExteriaMemberActionRights,
    ExteriaMemberActionBan,
    ExteriaMemberActionUnban
} ExteriaMemberAction;

@interface ExteriaChannelMembersController () {
    ExteriaFullChannel *_channel;
    ExteriaChannelList _list;
    ExteriaWeakReference *_weak;
    NSMutableArray *_members;
    NSInteger _total;
    NSString *_query;
    BOOL _loading;
    BOOL _done;
    BOOL _failed;
    NSString *_failureName;
    /* an answer to an older query or an older reload is dropped, so rows of a search never land in the plain list */
    NSUInteger _generation;
    UITableView *_table;
    UIView *_searchBar;
    UITextField *_search;
    UIActivityIndicatorView *_spinner;
    UILabel *_status;
    void (^_pickHandler)(ExteriaChannelMember *member);
    void (^_changedHandler)(void);
}
@end

@implementation ExteriaChannelMembersController

@synthesize pickHandler = _pickHandler;
@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel list:(ExteriaChannelList)list avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _channel = [channel retain];
    _list = list;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _members = [[NSMutableArray alloc] init];
    _query = [@"" copy];
    switch (list) {
    case ExteriaChannelListSubscribers: self.screenTitle = NSLocalizedString(channel.megagroup ? @"channel.members" : @"channel.subscribers", nil); break;
    case ExteriaChannelListAdmins: self.screenTitle = NSLocalizedString(@"channel.admins", nil); break;
    case ExteriaChannelListBlacklist: self.screenTitle = NSLocalizedString(@"channel.banned", nil); break;
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    _table.dataSource = nil;
    _table.delegate = nil;
    _search.delegate = nil;
    [_channel release];
    [_members release];
    [_query release];
    [_failureName release];
    [_table release];
    [_searchBar release];
    [_search release];
    [_spinner release];
    [_status release];
    [_pickHandler release];
    [_changedHandler release];
    [super dealloc];
}

- (BOOL)searchable {
    return _list != ExteriaChannelListAdmins;
}

/* the first row of the admins list adds one, for an account that may appoint admins; a screen asked to pick has none */
- (BOOL)hasAddRow {
    return _list == ExteriaChannelListAdmins && !_pickHandler && (_channel.adminRights & EXTERIA_ADMIN_ADD_ADMINS) != 0;
}

- (NSInteger)rowOffset {
    return [self hasAddRow] ? 1 : 0;
}

#pragma mark view

- (void)buildBodyInView:(UIView *)root {
    _table = [[UITableView alloc] init];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = [ExteriaPersonCell rowHeight];
    _table.dataSource = self;
    _table.delegate = self;
    [root addSubview:_table];
    if ([self searchable]) {
        _searchBar = [[UIView alloc] init];
        _search = [[ExteriaCenteredHintField alloc] init];
        _search.delegate = self;
        _search.font = ExteriaFontRegular(16);
        _search.textColor = ExteriaColorTitle();
        _search.placeholder = NSLocalizedString(@"channel.members.search", nil);
        _search.clearButtonMode = UITextFieldViewModeWhileEditing;
        _search.returnKeyType = UIReturnKeySearch;
        _search.autocorrectionType = UITextAutocorrectionTypeNo;
        _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _search.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _search.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
        _search.backgroundColor = ExteriaColorField();
        _search.layer.cornerRadius = 12;
        UIView *pad = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)] autorelease];
        _search.leftView = pad;
        _search.leftViewMode = UITextFieldViewModeAlways;
        [_searchBar addSubview:_search];
        _table.tableHeaderView = _searchBar;
    }
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.font = ExteriaFontRegular(15);
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
}

- (void)layoutBody:(CGRect)body {
    _table.frame = body;
    if (_searchBar) {
        _searchBar.frame = CGRectMake(0, 0, body.size.width, SEARCH_HEIGHT);
        _search.frame = CGRectMake(14, 8, body.size.width - 28, SEARCH_HEIGHT - 16);
        _table.tableHeaderView = _searchBar;
    }
    CGFloat top = body.origin.y + (_searchBar ? SEARCH_HEIGHT : 0);
    _spinner.center = CGPointMake(CGRectGetMidX(body), top + 60);
    _status.frame = CGRectMake(body.origin.x + 24, top + 30, body.size.width - 48, 60);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reload];
}

#pragma mark loading

- (void)reload {
    _generation++;
    [_members removeAllObjects];
    _total = 0;
    _done = NO;
    _failed = NO;
    _loading = NO;
    [_table reloadData];
    [self loadMore];
}

- (void)updateStatus {
    if (_loading && !_members.count) {
        [_spinner startAnimating];
        _status.text = @"";
        return;
    }
    [_spinner stopAnimating];
    if (_failed && !_members.count) {
        _status.text = ExteriaChannelErrorText(_failureName);
    } else if (_done && !_members.count && ![self hasAddRow]) {
        NSString *key = _list == ExteriaChannelListAdmins ? @"channel.admins.empty" : (_list == ExteriaChannelListBlacklist ? @"channel.banned.empty" : @"channel.members.empty");
        _status.text = _query.length ? NSLocalizedString(@"channel.members.nothing", nil) : NSLocalizedString(key, nil);
    } else {
        _status.text = @"";
    }
}

- (void)loadMore {
    if (_loading || _done) return;
    _loading = YES;
    _failed = NO;
    NSUInteger generation = _generation;
    ExteriaWeakReference *weak = _weak;
    [self updateStatus];
    [self retain];
    [self.session loadMembersOfDialog:_channel.dialog list:_list query:_query offset:(NSInteger)_members.count completion:^(NSArray *members, NSInteger total, NSString *errorName) {
        [self autorelease];
        ExteriaChannelMembersController *me = weak.target;
        if (!me || generation != me->_generation) return;
        me->_loading = NO;
        if (!members) {
            NSLog(@"exteria: the %d list of channel %lld did not load: %@", (int)me->_list, me->_channel.dialog.peerId, errorName);
            me->_failed = YES;
            [me->_failureName release];
            me->_failureName = [errorName copy];
            [me updateStatus];
            return;
        }
        [me->_members addObjectsFromArray:members];
        me->_total = total;
        /* a short page, or every row the server counts, is the end; an empty page ends a list whose count was wrong */
        me->_done = members.count < EXTERIA_MEMBERS_PAGE || (NSInteger)me->_members.count >= total;
        [me->_table reloadData];
        [me updateStatus];
    }];
}

#pragma mark search

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [field.text stringByReplacingCharactersInRange:range withString:string];
    if (next.length > EXTERIA_MEMBERS_QUERY_MAX / 4) return NO;
    [self queryChangedTo:next];
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    (void)field;
    [self queryChangedTo:@""];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (void)queryChangedTo:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed isEqualToString:_query]) return;
    [_query release];
    _query = [trimmed copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:SEARCH_DELAY];
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_members.count + [self rowOffset];
}

- (NSString *)subtitleOfMember:(ExteriaChannelMember *)member color:(UIColor **)color {
    ExteriaPerson *person = member.person;
    if (member.role == ExteriaChannelRoleBanned) return NSLocalizedString(@"channel.role.banned", nil);
    if (person.bot) return NSLocalizedString(@"seen.bot", nil);
    BOOL online = person.presence == EXTERIA_PRESENCE_ONLINE;
    if (online && color) *color = ExteriaColorAccent();
    return ExteriaLastSeenText(person.presence, person.seen);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasAddRow] && indexPath.row == 0) {
        static NSString *addIdentifier = @"add";
        ExteriaPersonCell *add = (ExteriaPersonCell *)[tableView dequeueReusableCellWithIdentifier:addIdentifier];
        if (!add) add = [[[ExteriaPersonCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:addIdentifier] autorelease];
        [add configureWithName:NSLocalizedString(@"channel.admin.add", nil) initials:@"+" seed:1 subtitle:nil subtitleColor:nil trailing:nil symbol:ExteriaSymbolPlusCircle
                   showsSymbol:NO nameColor:ExteriaColorAccent() photo:nil avatars:nil];
        return add;
    }
    NSUInteger index = (NSUInteger)(indexPath.row - [self rowOffset]);
    if (index + 4 >= _members.count) [self loadMore];
    ExteriaChannelMember *member = [_members objectAtIndex:index];
    static NSString *identifier = @"member";
    ExteriaPersonCell *cell = (ExteriaPersonCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaPersonCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    UIColor *subtitleColor = nil;
    NSString *subtitle = [self subtitleOfMember:member color:&subtitleColor];
    NSString *trailing = nil;
    if (member.role == ExteriaChannelRoleCreator) {
        trailing = member.rank.length ? member.rank : NSLocalizedString(@"channel.role.creator", nil);
        cell.trailingTint = ExteriaMemberTagColor(YES);
    } else if (member.role == ExteriaChannelRoleAdmin) {
        trailing = member.rank.length ? member.rank : NSLocalizedString(@"channel.role.admin", nil);
        cell.trailingTint = ExteriaMemberTagColor(NO);
    } else if (member.rank.length) {
        trailing = member.rank;
        cell.trailingTint = ExteriaColorAccent();
    }
    ExteriaPerson *person = member.person;
    [cell configureWithName:person.name initials:person.initials seed:(NSUInteger)(person.userId % 1000003) subtitle:subtitle subtitleColor:subtitleColor
                   trailing:trailing symbol:ExteriaSymbolChevronRight showsSymbol:NO nameColor:nil photo:person.photo avatars:self.avatars];
    cell.avatarDeleted = person.deleted;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_search resignFirstResponder];
    if ([self hasAddRow] && indexPath.row == 0) {
        [self addAdmin];
        return;
    }
    NSUInteger index = (NSUInteger)(indexPath.row - [self rowOffset]);
    if (index >= _members.count) return;
    ExteriaChannelMember *member = [_members objectAtIndex:index];
    if (_pickHandler) {
        /* an admin or the creator is already one, so only a plain subscriber is offered */
        if (member.role != ExteriaChannelRolePlain || member.isSelf) return;
        void (^handler)(ExteriaChannelMember *) = [[_pickHandler copy] autorelease];
        [self.navigationController popViewControllerAnimated:YES];
        handler(member);
        return;
    }
    [self showActionsOfMember:member];
}

#pragma mark actions

/* the actions the account may take on this person, as the Android client offers them; appointing needs the right
   to add admins, banning the right to ban (an admin cannot be banned from here, the post has to be taken away
   first) */
- (NSArray *)actionsForMember:(ExteriaChannelMember *)member {
    NSMutableArray *actions = [NSMutableArray array];
    uint32_t mine = _channel.adminRights;
    if (member.isSelf || member.role == ExteriaChannelRoleCreator || member.person.accessHash == 0) return actions;
    if (member.role == ExteriaChannelRoleAdmin) {
        if (member.canEdit && (mine & EXTERIA_ADMIN_ADD_ADMINS)) [actions addObject:[NSNumber numberWithInt:ExteriaMemberActionRights]];
    } else if (member.role == ExteriaChannelRoleBanned) {
        if (mine & EXTERIA_ADMIN_BAN_USERS) [actions addObject:[NSNumber numberWithInt:ExteriaMemberActionUnban]];
    } else {
        if (mine & EXTERIA_ADMIN_ADD_ADMINS) [actions addObject:[NSNumber numberWithInt:ExteriaMemberActionAdmin]];
        if (mine & EXTERIA_ADMIN_BAN_USERS) [actions addObject:[NSNumber numberWithInt:ExteriaMemberActionBan]];
    }
    return actions;
}

static NSString *ExteriaMemberActionTitle(ExteriaMemberAction action, BOOL group) {
    switch (action) {
    case ExteriaMemberActionAdmin: return NSLocalizedString(@"channel.action.makeadmin", nil);
    case ExteriaMemberActionRights: return NSLocalizedString(@"channel.rights.title", nil);
    case ExteriaMemberActionBan: return NSLocalizedString(group ? @"channel.action.ban.group" : @"channel.action.ban", nil);
    case ExteriaMemberActionUnban: return NSLocalizedString(@"channel.action.unban", nil);
    }
    return @"";
}

- (void)showActionsOfMember:(ExteriaChannelMember *)member {
    NSArray *actions = [self actionsForMember:member];
    if (!actions.count) return;
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *action in actions) [titles addObject:ExteriaMemberActionTitle((ExteriaMemberAction)action.intValue, _channel.megagroup)];
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsChoose(self, member.person.name, titles, ^(NSUInteger index) {
        ExteriaChannelMembersController *me = weak.target;
        if (!me || index >= actions.count) return;
        [me perform:(ExteriaMemberAction)[[actions objectAtIndex:index] intValue] onMember:member];
    });
}

- (void)perform:(ExteriaMemberAction)action onMember:(ExteriaChannelMember *)member {
    switch (action) {
    case ExteriaMemberActionAdmin: [self openRightsOfMember:member]; break;
    case ExteriaMemberActionRights: [self openRightsOfMember:member]; break;
    case ExteriaMemberActionBan: [self askBan:member]; break;
    case ExteriaMemberActionUnban: [self setBanned:NO member:member]; break;
    }
}

- (void)notifyChanged {
    if (_changedHandler) _changedHandler();
}

- (void)openRightsOfMember:(ExteriaChannelMember *)member {
    BOOL admin = member.role == ExteriaChannelRoleAdmin;
    ExteriaChannelRightsController *rights = [[[ExteriaChannelRightsController alloc] initWithSession:self.session channel:_channel person:member.person
                                                                                              rights:member.rights rank:member.rank isAdmin:admin
                                                                                             avatars:self.avatars media:self.media] autorelease];
    ExteriaWeakReference *weak = _weak;
    rights.changedHandler = ^{
        ExteriaChannelMembersController *me = weak.target;
        if (!me) return;
        [me reload];
        [me notifyChanged];
    };
    [self.navigationController pushViewController:rights animated:YES];
}

- (void)addAdmin {
    ExteriaChannelMembersController *pick = [[[ExteriaChannelMembersController alloc] initWithSession:self.session channel:_channel list:ExteriaChannelListSubscribers
                                                                                               avatars:self.avatars media:self.media] autorelease];
    ExteriaWeakReference *weak = _weak;
    pick.pickHandler = ^(ExteriaChannelMember *member) {
        /* the picker has gone back by now, and the rights screen goes on top of this list */
        [(ExteriaChannelMembersController *)weak.target openRightsOfMember:member];
    };
    [self.navigationController pushViewController:pick animated:YES];
}

- (void)askBan:(ExteriaChannelMember *)member {
    ExteriaWeakReference *weak = _weak;
    NSString *message = [NSString stringWithFormat:NSLocalizedString(_channel.megagroup ? @"channel.ban.confirm.group" : @"channel.ban.confirm", nil), member.person.name,
                         _channel.dialog.title];
    ExteriaConfirmAction(self, message, NSLocalizedString(@"channel.action.ban.short", nil), ^{
        [(ExteriaChannelMembersController *)weak.target setBanned:YES member:member];
    });
}

- (void)setBanned:(BOOL)banned member:(ExteriaChannelMember *)member {
    ExteriaWeakReference *weak = _weak;
    [self retain];
    [self.session setBanned:banned person:member.person inDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        ExteriaChannelMembersController *me = weak.target;
        if (!me) return;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaChannelErrorText(errorName));
            return;
        }
        /* the person leaves this list either way: banned from the subscribers, or let back off the blacklist */
        NSUInteger at = [me->_members indexOfObjectIdenticalTo:member];
        if (at != NSNotFound) {
            [me->_members removeObjectAtIndex:at];
            if (me->_total > 0) me->_total--;
            [me->_table reloadData];
            [me updateStatus];
        }
        [me notifyChanged];
    }];
}

@end
