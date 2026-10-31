#import "exteria_session_sendas.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_send_as.h"
#include "exteria_tl_ids.h"

/* a chat is told apart by its kind and id; the topic of a forum does not change who writes */
static NSString *ExteriaSendAsKey(const exteria_peer_ref *chat) {
    return [NSString stringWithFormat:@"%d:%lld", (int)chat->kind, (long long)chat->id];
}

/* the stars the person agreed to pay for each message to a chat that charges for them; the server refuses a message without the amount (ALLOW_PAYMENT_REQUIRED_n) and
   takes a smaller one than its price just as badly, so the amount it named is what is sent. the sends run on a worker, hence the lock */
static NSMutableDictionary *sPaidApprovals;

static NSString *ExteriaPaidKey(ExteriaSession *session, const exteria_peer_ref *chat) {
    return [NSString stringWithFormat:@"%p:%d:%lld", session, (int)chat->kind, (long long)chat->id];
}

void ExteriaApprovePaidMessages(ExteriaSession *session, const exteria_peer_ref *chat, long long stars) {
    @synchronized([ExteriaSession class]) {
        if (!sPaidApprovals) sPaidApprovals = [[NSMutableDictionary alloc] init];
        if (stars > 0) [sPaidApprovals setObject:[NSNumber numberWithLongLong:stars] forKey:ExteriaPaidKey(session, chat)];
        else [sPaidApprovals removeObjectForKey:ExteriaPaidKey(session, chat)];
    }
}

static long long ExteriaApprovedPaidStars(ExteriaSession *session, const exteria_peer_ref *chat) {
    @synchronized([ExteriaSession class]) {
        return [[sPaidApprovals objectForKey:ExteriaPaidKey(session, chat)] longLongValue];
    }
}

exteria_status ExteriaApplySendAs(ExteriaSession *session, const exteria_peer_ref *chat, exteria_arena *arena, exteria_tl_value *request) {
    ExteriaDialog *identity = [session storedSendAsForChat:chat];
    if (identity) {
        exteria_peer_ref who = ExteriaPeerRefOfDialog(identity);
        exteria_status status = exteria_set_send_as(arena, request, &who);
        if (status != EXTERIA_OK) return status;
    }
    long long paid = ExteriaApprovedPaidStars(session, chat);
    if (paid > 0 && (exteria_tl_is(request, EXTERIA_TL_ID_messages_sendMessage) || exteria_tl_is(request, EXTERIA_TL_ID_messages_sendMedia) ||
                     exteria_tl_is(request, EXTERIA_TL_ID_messages_sendMultiMedia) || exteria_tl_is(request, EXTERIA_TL_ID_messages_forwardMessages)))
        return exteria_tl_set_i64(arena, request, "allow_paid_stars", paid);
    return EXTERIA_OK;
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

- (void)approvePaidMessages:(long long)stars ofDialog:(ExteriaDialog *)dialog {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    ExteriaApprovePaidMessages(self, &peer, stars);
}

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
