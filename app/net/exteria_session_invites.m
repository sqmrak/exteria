#import "exteria_session_invites.h"
#import "exteria_session_internal.h"

#import "exteria_rpc.h"

#include "exteria_tl_ids.h"

static NSString *ExteriaInviteUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaInvite

@synthesize link = _link;
@synthesize title = _title;
@synthesize revoked = _revoked;
@synthesize permanent = _permanent;
@synthesize requestNeeded = _requestNeeded;
@synthesize date = _date;
@synthesize expireDate = _expireDate;
@synthesize usageLimit = _usageLimit;
@synthesize usage = _usage;
@synthesize requested = _requested;

- (id)initWithRow:(const exteria_invite *)row {
    self = [super init];
    if (!self) return nil;
    _link = [ExteriaInviteUtf8(row->link) copy];
    _title = [ExteriaInviteUtf8(row->title) copy];
    _revoked = row->revoked;
    _permanent = row->permanent;
    _requestNeeded = row->request_needed;
    _date = row->date;
    _startDate = row->start_date;
    _expireDate = row->expire_date;
    _usageLimit = row->usage_limit;
    _usage = row->usage;
    _requested = row->requested;
    return self;
}

- (void)dealloc {
    [_link release];
    [_title release];
    [super dealloc];
}

- (BOOL)expired {
    if (_revoked) return NO;
    if (_expireDate > 0 && _expireDate <= (int32_t)time(NULL)) return YES;
    return _usageLimit > 0 && _usage >= _usageLimit;
}

@end

static exteria_invite_spec ExteriaInviteSpec(int32_t expireDate, int32_t usageLimit, BOOL requestNeeded, NSString *title) {
    exteria_invite_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.expire_date = expireDate;
    spec.usage_limit = usageLimit;
    spec.request_needed = requestNeeded ? 1 : 0;
    snprintf(spec.title, sizeof(spec.title), "%s", title.length ? title.UTF8String : "");
    return spec;
}

@implementation ExteriaSession (Invites)

- (void)loadInvitesOfDialog:(ExteriaDialog *)dialog revoked:(BOOL)revoked afterInvite:(ExteriaInvite *)last
                 completion:(void (^)(NSArray *, NSInteger, NSString *))completion {
    void (^done)(NSArray *, NSInteger, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *offsetLink = [[last.link copy] autorelease];
    int32_t offsetDate = last.date;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_list_request(arena, &peer, revoked ? 1 : 0, offsetDate, offsetLink.length ? offsetLink.UTF8String : NULL, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *invites = nil;
        NSInteger total = 0;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_invite *rows = calloc(EXTERIA_INVITES_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t all = 0;
            exteria_status status = rows ? exteria_invite_list_parse(result->value, rows, EXTERIA_INVITES_MAX, &count, &all) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                invites = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [invites addObject:[[[ExteriaInvite alloc] initWithRow:&rows[i]] autorelease]];
                total = all;
            } else {
                NSLog(@"exteria: messages.getExportedChatInvites answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(invites, total, delivered); [done release]; }];
    }];
}

/* the answer of a creation or an edit is the link as the server has it now */
- (void)runInviteRequest:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build completion:(void (^)(ExteriaInvite *, ExteriaInvite *, NSString *))completion {
    void (^done)(ExteriaInvite *, ExteriaInvite *, NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        ExteriaInvite *invite = nil, *replacement = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_invite row, other;
            int replaced = 0;
            exteria_status status = exteria_invite_answer_parse(result->value, &row, &other, &replaced);
            if (status == EXTERIA_OK) {
                invite = [[[ExteriaInvite alloc] initWithRow:&row] autorelease];
                if (replaced) replacement = [[[ExteriaInvite alloc] initWithRow:&other] autorelease];
            } else {
                NSLog(@"exteria: the answer about an invite link was rejected: %s", exteria_status_name(status));
                error = @"MALFORMED";
            }
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(invite, replacement, delivered); [done release]; }];
    }];
}

- (void)createInviteInDialog:(ExteriaDialog *)dialog expireDate:(int32_t)expireDate usageLimit:(int32_t)usageLimit requestNeeded:(BOOL)requestNeeded
                       title:(NSString *)title completion:(void (^)(ExteriaInvite *, NSString *))completion {
    void (^done)(ExteriaInvite *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    exteria_invite_spec spec = ExteriaInviteSpec(expireDate, usageLimit, requestNeeded, title);
    [self runInviteRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_create_request(arena, &peer, &spec, request);
    } completion:^(ExteriaInvite *invite, ExteriaInvite *replacement, NSString *errorName) {
        (void)replacement;
        done(invite, errorName);
        [done release];
    }];
}

- (void)editInvite:(ExteriaInvite *)invite inDialog:(ExteriaDialog *)dialog expireDate:(int32_t)expireDate usageLimit:(int32_t)usageLimit
     requestNeeded:(BOOL)requestNeeded title:(NSString *)title completion:(void (^)(ExteriaInvite *, NSString *))completion {
    void (^done)(ExteriaInvite *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    exteria_invite_spec spec = ExteriaInviteSpec(expireDate, usageLimit, requestNeeded, title);
    NSString *link = [[invite.link copy] autorelease];
    [self runInviteRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_edit_request(arena, &peer, link.UTF8String, &spec, request);
    } completion:^(ExteriaInvite *edited, ExteriaInvite *replacement, NSString *errorName) {
        (void)replacement;
        done(edited, errorName);
        [done release];
    }];
}

- (void)revokeInvite:(ExteriaInvite *)invite inDialog:(ExteriaDialog *)dialog
          completion:(void (^)(ExteriaInvite *, ExteriaInvite *, NSString *))completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *link = [[invite.link copy] autorelease];
    [self runInviteRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_revoke_request(arena, &peer, link.UTF8String, request);
    } completion:completion];
}

/* the two deletes answer with a Bool */
- (void)runInviteDelete:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (!exteria_tl_is(result->value, EXTERIA_TL_ID_boolTrue)) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)deleteInvite:(ExteriaInvite *)invite inDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *link = [[invite.link copy] autorelease];
    [self runInviteDelete:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_delete_request(arena, &peer, link.UTF8String, request);
    } completion:completion];
}

- (void)deleteRevokedInvitesInDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self runInviteDelete:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_delete_revoked_request(arena, &peer, request);
    } completion:completion];
}

@end
