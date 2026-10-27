#import "exteria_session_sendas.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_send_as.h"

/* a chat is told apart by its kind and id; the topic of a forum does not change who writes */
static NSString *ExteriaSendAsKey(const exteria_peer_ref *chat) {
    return [NSString stringWithFormat:@"%d:%lld", (int)chat->kind, (long long)chat->id];
}

exteria_status ExteriaApplySendAs(ExteriaSession *session, const exteria_peer_ref *chat, exteria_arena *arena, exteria_tl_value *request) {
    ExteriaDialog *identity = [session storedSendAsForChat:chat];
    if (!identity) return EXTERIA_OK;
    exteria_peer_ref who = ExteriaPeerRefOfDialog(identity);
    return exteria_set_send_as(arena, request, &who);
}

@implementation ExteriaSendAsOption
@synthesize identity = _identity;
@synthesize premiumRequired = _premiumRequired;

- (id)initWithRow:(const exteria_dialog_row *)row premiumRequired:(BOOL)premium {
    self = [super init];
    if (!self) return nil;
    _identity = [[ExteriaDialog alloc] initWithRow:row];
    _premiumRequired = premium;
    return self;
}

- (BOOL)isAccount { return _identity.saved; }

- (void)dealloc {
    [_identity release];
    [super dealloc];
}
@end

@implementation ExteriaSession (SendAs)

- (void)loadSendAsOptionsOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int64_t self_id = [ExteriaSession accountIdInDirectory:self.directory];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_send_as_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *options = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_dialog_row *rows = calloc(EXTERIA_SEND_AS_MAX, sizeof(*rows));
            uint8_t premium[EXTERIA_SEND_AS_MAX];
            size_t count = 0;
            exteria_status status = rows ? exteria_send_as_parse(result->value, self_id, rows, premium, EXTERIA_SEND_AS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                options = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [options addObject:[[[ExteriaSendAsOption alloc] initWithRow:&rows[i] premiumRequired:premium[i] != 0] autorelease]];
            } else {
                NSLog(@"exteria: channels.getSendAs answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(options, deliveredError); [done release]; }];
    }];
}

- (ExteriaDialog *)storedSendAsForChat:(const exteria_peer_ref *)chat {
    ExteriaDialog *identity;
    @synchronized(self) {
        identity = [[[_sendAsChoices objectForKey:ExteriaSendAsKey(chat)] retain] autorelease];
    }
    return identity;
}

- (void)storeSendAs:(ExteriaDialog *)identity forChat:(const exteria_peer_ref *)chat {
    @synchronized(self) {
        if (!_sendAsChoices) _sendAsChoices = [[NSMutableDictionary alloc] init];
        if (identity) [_sendAsChoices setObject:identity forKey:ExteriaSendAsKey(chat)];
        else [_sendAsChoices removeObjectForKey:ExteriaSendAsKey(chat)];
    }
}

- (ExteriaDialog *)sendAsIdentityOfDialog:(ExteriaDialog *)dialog {
    exteria_peer_ref chat = ExteriaPeerRefOfDialog(dialog);
    return [self storedSendAsForChat:&chat];
}

- (void)adoptSendAsIdentity:(ExteriaDialog *)identity ofDialog:(ExteriaDialog *)dialog {
    exteria_peer_ref chat = ExteriaPeerRefOfDialog(dialog);
    [self storeSendAs:identity.saved ? nil : identity forChat:&chat];
}

- (void)chooseSendAsIdentity:(ExteriaDialog *)identity ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref chat = ExteriaPeerRefOfDialog(dialog);
    ExteriaDialog *before = [[self storedSendAsForChat:&chat] retain];
    BOOL account = !identity || identity.saved;
    exteria_peer_ref who;
    memset(&who, 0, sizeof(who));
    if (account) {
        who.kind = 1;
        who.self = 1;
    } else {
        who = ExteriaPeerRefOfDialog(identity);
    }
    /* later messages carry the choice at once; a refusal puts the old one back */
    [self storeSendAs:account ? nil : identity forChat:&chat];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_save_default_send_as_request(arena, &chat, &who, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        if (error) [self storeSendAs:before forChat:&chat];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
        [before release];
    }];
}

@end
