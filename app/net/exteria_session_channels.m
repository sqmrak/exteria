#import "exteria_session_internal.h"

#include "exteria_channel.h"
#include "exteria_profile.h"

#import "exteria_rpc.h"
#import "exteria_session_channels.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *ExteriaChannelUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

NSString *const ExteriaDialogsChangedNotification = @"ExteriaDialogsChanged";

@implementation ExteriaFullChannel

@synthesize dialog = _dialog;
@synthesize linked = _linked;
@synthesize about = _about;
@synthesize username = _username;
@synthesize inviteLink = _inviteLink;
@synthesize megagroup = _megagroup;
@synthesize membershipKnown = _membershipKnown;
@synthesize verified = _verified;
@synthesize muted = _muted;
@synthesize giftsAvailable = _giftsAvailable;
@synthesize creator = _creator;
@synthesize signatures = _signatures;
@synthesize adminRights = _adminRights;
@synthesize participants = _participants;
@synthesize admins = _admins;
@synthesize banned = _banned;
@synthesize gifts = _gifts;
@synthesize pinnedMessage = _pinnedMessage;
@synthesize sendAsKind = _sendAsKind;
@synthesize sendAsId = _sendAsId;

- (id)initWithRow:(const exteria_full_channel *)row {
    self = [super init];
    if (!self) return nil;
    exteria_dialog_row dialog = row->dialog;
    _dialog = [[ExteriaDialog alloc] initWithRow:&dialog];
    if (row->has_linked) {
        exteria_dialog_row linked = row->linked;
        _linked = [[ExteriaDialog alloc] initWithRow:&linked];
    }
    _about = [ExteriaChannelUtf8(row->about) copy];
    _username = [ExteriaChannelUtf8(row->username) copy];
    _inviteLink = [ExteriaChannelUtf8(row->link) copy];
    _megagroup = row->megagroup;
    _membershipKnown = row->membership_known;
    _verified = row->verified;
    _muted = row->muted;
    _giftsAvailable = row->gifts_available;
    _creator = row->creator;
    _signatures = row->signatures;
    _adminRights = row->admin_rights;
    _participants = row->participants;
    _admins = row->admins;
    _banned = row->banned;
    _gifts = row->gifts;
    _pinnedMessage = row->pinned_message;
    _sendAsKind = row->send_as_kind;
    _sendAsId = row->send_as_id;
    return self;
}

- (void)dealloc {
    [_dialog release];
    [_linked release];
    [_about release];
    [_username release];
    [_inviteLink release];
    [super dealloc];
}

- (BOOL)isAdmin {
    return _creator || _adminRights != 0;
}

- (NSString *)shownLink {
    if (_username.length) return [@"t.me/" stringByAppendingString:_username];
    if (_inviteLink.length) return [_inviteLink hasPrefix:@"https://"] ? [_inviteLink substringFromIndex:8] : _inviteLink;
    return @"";
}

- (NSString *)webLink {
    NSString *shown = self.shownLink;
    return shown.length ? [@"https://" stringByAppendingString:shown] : @"";
}

@end

@implementation ExteriaChannelMember

@synthesize person = _person;
@synthesize role = _role;
@synthesize canEdit = _canEdit;
@synthesize isSelf = _isSelf;
@synthesize rights = _rights;
@synthesize date = _date;
@synthesize rank = _rank;

- (id)initWithRow:(const exteria_channel_member *)row {
    self = [super init];
    if (!self) return nil;
    exteria_person_row person = row->person;
    _person = [[ExteriaPerson alloc] initWithRow:&person];
    _role = (ExteriaChannelRole)row->role;
    _canEdit = row->can_edit;
    _isSelf = row->self;
    _rights = row->rights;
    _date = row->date;
    _rank = [ExteriaChannelUtf8(row->rank) copy];
    return self;
}

- (void)dealloc {
    [_person release];
    [_rank release];
    [super dealloc];
}

@end

/* the reference of a person as a request names it; the access hash is what the server checks */
static exteria_peer_ref ExteriaPeerRefOfPerson(ExteriaPerson *person) {
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = 1;
    peer.id = person.userId;
    peer.access_hash = person.accessHash;
    return peer;
}

/* the shape every write below shares: build the request, run it, hand the rpc error name (nil on success) to the main thread. checkBool reads a Bool answer */
static void ExteriaChannelWrite(ExteriaSession *session, exteria_status (^build)(exteria_arena *arena, exteria_tl_value **request), BOOL checkBool,
                                void (^completion)(NSString *errorName)) {
    void (^done)(NSString *) = [completion copy];
    [session invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else if (checkBool) {
            exteria_status parsed = exteria_channel_bool_parse(result->value);
            if (parsed == EXTERIA_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [session noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [session deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@implementation ExteriaSession (Channels)

- (void)loadDiscussionOfPost:(int32_t)postId dialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaDialog *, NSString *))completion {
    void (^done)(ExteriaDialog *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_discussion_request(arena, &peer, postId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaDialog *discussion = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else {
            exteria_dialog_row row;
            exteria_status status = exteria_discussion_parse(result->value, peer.id, &row);
            if (status == EXTERIA_OK) {
                discussion = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
                discussion.discussion = YES;
                discussion.discussionChannel = (long long)peer.id;
                discussion.discussionChannelHash = (long long)peer.access_hash;
                discussion.discussionPost = postId;
                const exteria_tl_value *list = exteria_tl_get(result->value, "messages");
                NSMutableArray *roots = [NSMutableArray array];
                exteria_message_row *messageRow = calloc(1, sizeof(*messageRow));
                if (messageRow && list && list->kind == EXTERIA_TL_V_VEC) {
                    for (uint32_t i = 0; i < list->u.vec.count && i < EXTERIA_MESSAGES_MAX; ++i) {
                        const exteria_tl_value *value = list->u.vec.items[i];
                        exteria_peer messagePeer;
                        if (exteria_peer_from_tl(exteria_tl_get(value, "peer_id"), &messagePeer) != EXTERIA_OK ||
                            messagePeer.kind != 3 || messagePeer.id != row.peer_id || exteria_message_read(value, messageRow) != EXTERIA_OK) continue;
                        ExteriaMessage *message = [ExteriaMessage messageWithRow:messageRow];
                        if (message) [roots addObject:message];
                    }
                } else if (!messageRow) NSLog(@"exteria: no memory for discussion messages");
                free(messageRow);
                discussion.discussionMessages = roots;
                discussion.discussionPeople = ExteriaPeopleOfAnswer(self, result->value);
                NSLog(@"exteria: the comments of post %d of channel %lld are thread %d of group %lld", postId, (long long)peer.id, (int)row.topic_id, (long long)row.peer_id);
            } else {
                NSLog(@"exteria: discussion of post %d rejected: %s", postId, exteria_status_name(status));
                error = @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(discussion, delivered); [done release]; }];
    }];
}

- (void)loadFullChannelOfDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaFullChannel *, NSString *))completion {
    void (^done)(ExteriaFullChannel *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_full_channel_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) {
            NSString *error = ExteriaRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, delivered); [done release]; }];
            return;
        }
        exteria_full_channel *full = calloc(1, sizeof(*full));
        exteria_status status = full ? exteria_full_channel_parse(result->value, peer.id, (int32_t)time(NULL), full) : EXTERIA_E_NOMEM;
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: channels.getFullChannel answer rejected: %s", exteria_status_name(status));
            free(full);
            [self deliverMain:^{ done(nil, @"INTERNAL"); [done release]; }];
            return;
        }
        ExteriaFullChannel *channel = [[[ExteriaFullChannel alloc] initWithRow:full] autorelease];
        free(full);
        [self deliverMain:^{ done(channel, nil); [done release]; }];
    }];
}

- (void)loadMessage:(int32_t)messageId ofChannelDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaMessage *, NSString *))completion {
    void (^done)(ExteriaMessage *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_message_request(arena, &peer, messageId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaMessage *message = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_message_row *rows = calloc(EXTERIA_MESSAGES_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_messages_parse(result->value, rows, EXTERIA_MESSAGES_MAX, &count) == EXTERIA_OK && count > 0) message = [ExteriaMessage messageWithRow:&rows[0]];
            else error = @"NOT_FOUND";
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(message, deliveredError); [done release]; }];
    }];
}

- (void)joinChannelOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_join_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status parsed = exteria_channel_join_parse(result->value);
            if (parsed == EXTERIA_E_UNSUPPORTED) error = @"JOIN_WEBVIEW";
            else if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)loadChannelDialogWithId:(long long)channelId completion:(void (^)(ExteriaDialog *, NSString *))completion {
    void (^done)(ExteriaDialog *, NSString *) = [completion copy];
    [self post:^{
        /* the hash is the one the chats of this account carry; a channel the account never saw has none, and the link cannot be opened */
        ExteriaPerson *held = [self storedPersonWithKey:-(int64_t)channelId];
        int64_t hash = held ? (int64_t)held.accessHash : 0;
        if (!hash) {
            [self deliverMain:^{ done(nil, @"CHANNEL_PRIVATE"); [done release]; }];
            return;
        }
        [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_channel_by_id_request(arena, (int64_t)channelId, hash, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            ExteriaDialog *dialog = nil;
            NSString *error = nil;
            if (result->status != EXTERIA_OK) {
                error = ExteriaRpcErrorName(result);
            } else {
                exteria_dialog_row row;
                exteria_status parsed = exteria_channel_dialog_parse(result->value, (int64_t)channelId, &row);
                if (parsed == EXTERIA_OK) dialog = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
                else error = parsed == EXTERIA_E_NOTFOUND ? @"CHANNEL_PRIVATE" : @"INTERNAL";
            }
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(dialog, delivered); [done release]; }];
        }];
    }];
}

- (void)loadMembershipOfDialog:(ExteriaDialog *)dialog completion:(void (^)(BOOL, NSString *))completion {
    void (^done)(BOOL, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_member_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        int member = 0;
        if (result->status != EXTERIA_OK) {
            NSString *name = ExteriaRpcErrorName(result);
            /* the server's way of saying the account never joined, which is an answer and no failure */
            if (!exteria_channel_already_left(3, [name UTF8String])) error = name;
        } else if (exteria_channel_member_parse(result->value, &member) != EXTERIA_OK) {
            error = @"MALFORMED";
        }
        if (error) [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        BOOL joined = member != 0;
        [self deliverMain:^{ done(joined, delivered); [done release]; }];
    }];
}

- (void)loadMembersOfDialog:(ExteriaDialog *)dialog list:(ExteriaChannelList)list query:(NSString *)query offset:(NSInteger)offset
                 completion:(void (^)(NSArray *, NSInteger, NSString *))completion {
    void (^done)(NSArray *, NSInteger, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    exteria_member_list kind = list == ExteriaChannelListAdmins ? EXTERIA_MEMBERS_ADMINS : (list == ExteriaChannelListBlacklist ? EXTERIA_MEMBERS_KICKED : EXTERIA_MEMBERS_RECENT);
    NSString *text = [[query copy] autorelease];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_members_request(arena, &peer, kind, text.length ? [text UTF8String] : NULL, (int32_t)offset, EXTERIA_MEMBERS_PAGE, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *members = nil;
        NSInteger total = 0;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_channel_member *rows = calloc(EXTERIA_MEMBERS_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t all = 0;
            exteria_status status = rows ? exteria_channel_members_parse(result->value, rows, EXTERIA_MEMBERS_MAX, &count, &all) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                members = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [members addObject:[[[ExteriaChannelMember alloc] initWithRow:&rows[i]] autorelease]];
                total = all;
            } else {
                NSLog(@"exteria: channels.getParticipants answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(members, total, deliveredError); [done release]; }];
    }];
}

- (void)setAdminRights:(uint32_t)rights rank:(NSString *)rank ofPerson:(ExteriaPerson *)person inDialog:(ExteriaDialog *)dialog
            completion:(void (^)(NSString *))completion {
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    exteria_peer_ref user = ExteriaPeerRefOfPerson(person);
    NSString *title = [[rank copy] autorelease];
    ExteriaChannelWrite(self, ^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_admin_request(arena, &channel, &user, rights, title.length ? [title UTF8String] : NULL, request);
    }, NO, completion);
}

- (void)setBanned:(BOOL)banned person:(ExteriaPerson *)person inDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    exteria_peer_ref user = ExteriaPeerRefOfPerson(person);
    ExteriaChannelWrite(self, ^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_ban_request(arena, &channel, &user, banned ? 1 : 0, request);
    }, NO, completion);
}

- (void)inviteUserDialog:(ExteriaDialog *)user toDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    exteria_peer_ref who = ExteriaPeerRefOfDialog(user);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_invite_request(arena, &channel, &who, 1, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        size_t missing = 0;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_channel_invite_missing(result->value, &missing) != EXTERIA_OK) error = @"MALFORMED";
        /* the server answers with the people it could not add instead of an error, the usual cause being their privacy settings */
        else if (missing > 0) error = @"USER_PRIVACY_RESTRICTED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)setTitle:(NSString *)title ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [[title copy] autorelease];
    ExteriaChannelWrite(self, ^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_title_request(arena, &channel, [text UTF8String], request);
    }, NO, completion);
}

- (void)setAbout:(NSString *)about ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [[about copy] autorelease];
    ExteriaChannelWrite(self, ^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_about_request(arena, &channel, [text UTF8String], request);
    }, YES, completion);
}

- (void)setUsername:(NSString *)username ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [[username copy] autorelease];
    ExteriaChannelWrite(self, ^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_username_request(arena, &channel, [text UTF8String], 0, request);
    }, YES, completion);
}

- (void)checkUsername:(NSString *)username ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [[username copy] autorelease];
    ExteriaChannelWrite(self, ^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_username_request(arena, &channel, [text UTF8String], 1, request);
    }, YES, completion);
}

- (void)setSignatures:(BOOL)enabled ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref channel = ExteriaPeerRefOfDialog(dialog);
    ExteriaChannelWrite(self, ^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_signatures_request(arena, &channel, enabled ? 1 : 0, request);
    }, NO, completion);
}

@end
