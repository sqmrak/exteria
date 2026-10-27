#import "exteria_session_notifysettings.h"

#import "exteria_notify_store.h"
#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#define EXCEPTIONS_MAX 400
#define RINGTONES_MAX 200

@implementation ExteriaNotifyException

- (id)initWithValue:(const exteria_notify_exception *)value {
    self = [super init];
    if (!self) return nil;
    _value = *value;
    NSString *title = [NSString stringWithUTF8String:value->title];
    _title = [(title ? title : @"") copy];
    return self;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

- (int32_t)peerKind { return _value.peer_kind; }
- (long long)peerId { return _value.peer_id; }
- (long long)peerHash { return _value.peer_hash; }
- (NSString *)title { return _title; }
- (BOOL)deleted { return _value.deleted != 0; }
- (BOOL)broadcast { return _value.broadcast != 0; }
- (BOOL)forumTopic { return _value.forum_topic != 0; }
- (exteria_peer_notify)settings { return _value.settings; }

@end

@implementation ExteriaCloudTone

- (id)initWithRow:(const exteria_ringtone_row *)row {
    self = [super init];
    if (!self) return nil;
    _row = *row;
    NSString *title = [NSString stringWithUTF8String:row->title];
    if (!title.length) title = [[NSString stringWithUTF8String:row->file_name] stringByDeletingPathExtension];
    _title = [(title.length ? title : @"") copy];
    return self;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

- (exteria_ringtone_row)row { return _row; }
- (long long)toneId { return _row.id; }
- (NSString *)title { return _title; }
- (int32_t)duration { return _row.duration; }

@end

@implementation ExteriaSession (NotifySettings)

/* every call of these screens ends in an answer that is only good or not */
- (void)runNotifyRequest:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build onSuccess:(void (^)(void))success
              completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    void (^applied)(void) = [success copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_notify_bool_result(result->value) != EXTERIA_OK) error = @"INTERNAL";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            if (!delivered && applied) applied();
            if (done) done(delivered);
            [done release];
            [applied release];
        }];
    }];
}

#pragma mark account settings

- (void)syncNotifySettingsWithCompletion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    __block NSInteger pending = EXTERIA_SCOPE_COUNT + 1;
    __block NSString *firstError = nil;
    void (^finished)(NSString *) = ^(NSString *error) {
        if (error && !firstError) firstError = [error copy];
        if (--pending > 0) return;
        NSString *delivered = [firstError autorelease];
        if (done) done(delivered);
        [done release];
    };
    for (int i = 0; i < EXTERIA_SCOPE_COUNT; ++i) {
        exteria_notify_scope scope = (exteria_notify_scope)i;
        [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_notify_scope_request(arena, scope, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            NSString *error = nil;
            exteria_peer_notify read;
            memset(&read, 0, sizeof(read));
            if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
            else if (exteria_peer_notify_read(result->value, &read) != EXTERIA_OK) error = @"INTERNAL";
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            NSValue *boxed = [NSValue valueWithBytes:&read objCType:@encode(exteria_peer_notify)];
            [self deliverMain:^{
                if (!delivered) {
                    exteria_peer_notify value;
                    [boxed getValue:&value];
                    ExteriaNotifyScopeStore(scope, &value);
                }
                finished(delivered);
            }];
        }];
    }
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_reaction_notify_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        exteria_reaction_notify read;
        memset(&read, 0, sizeof(read));
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_reaction_notify_read(result->value, &read) != EXTERIA_OK) error = @"INTERNAL";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        NSValue *boxed = [NSValue valueWithBytes:&read objCType:@encode(exteria_reaction_notify)];
        [self deliverMain:^{
            if (!delivered) {
                exteria_reaction_notify value;
                [boxed getValue:&value];
                ExteriaNotifyReactionsStore(&value);
            }
            finished(delivered);
        }];
    }];
}

/* what is sent of a kind of chat: the mute, the preview and the sound always, so the server never keeps a half of an older answer; private chats also carry
   the stories fields */
- (void)sendNotifyScope:(exteria_notify_scope)scope completion:(void (^)(NSString *))completion {
    exteria_peer_notify settings = ExteriaNotifyScopeStored(scope);
    settings.has_mute = 1;
    if (!settings.has_previews) settings.previews = 1;
    settings.has_previews = 1;
    settings.has_sound = 1;
    if (scope == EXTERIA_SCOPE_USERS) settings.has_stories_hide_sender = 1;
    else {
        settings.has_stories_muted = settings.has_stories_hide_sender = settings.has_stories_sound = 0;
    }
    [self runNotifyRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_notify_update_request(arena, 1, scope, NULL, &settings, request);
    } onSuccess:nil completion:completion];
}

- (void)sendReactionNotifyWithCompletion:(void (^)(NSString *))completion {
    exteria_reaction_notify settings = ExteriaNotifyReactionsStored();
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_reaction_notify_set_request(arena, &settings, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ if (done) done(delivered); [done release]; }];
    }];
}

#pragma mark chats

- (void)loadNotifyExceptionsWithCompletion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_notify_exceptions_request(arena, 1, 1, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *list = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_notify_exception *rows = calloc(EXCEPTIONS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_notify_exceptions_parse(result->value, [self workerAccount], rows, EXCEPTIONS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                list = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [list addObject:[[[ExteriaNotifyException alloc] initWithValue:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: the notification exceptions were rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *delivered = [list retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, deliveredError); [delivered release]; [done release]; }];
    }];
}

static exteria_peer_ref ExteriaNotifyPeer(int32_t kind, long long peerId, long long hash, int32_t topic) {
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = kind;
    peer.id = peerId;
    peer.access_hash = hash;
    peer.topic_id = topic;
    return peer;
}

- (void)loadNotifyOfPeerKind:(int32_t)kind id:(long long)peerId hash:(long long)hash topic:(int32_t)topic completion:(void (^)(NSValue *, NSString *))completion {
    void (^done)(NSValue *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaNotifyPeer(kind, peerId, hash, topic);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_notify_peer_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        exteria_peer_notify read;
        memset(&read, 0, sizeof(read));
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_peer_notify_read(result->value, &read) != EXTERIA_OK) error = @"INTERNAL";
        [self noteRpcError:error];
        NSValue *boxed = error ? nil : [[NSValue valueWithBytes:&read objCType:@encode(exteria_peer_notify)] retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(boxed, deliveredError); [boxed release]; [done release]; }];
    }];
}

- (void)updateNotify:(NSValue *)settings ofPeerKind:(int32_t)kind id:(long long)peerId hash:(long long)hash topic:(int32_t)topic completion:(void (^)(NSString *))completion {
    exteria_peer_notify value;
    [settings getValue:&value];
    exteria_peer_ref peer = ExteriaNotifyPeer(kind, peerId, hash, topic);
    [self runNotifyRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_notify_update_request(arena, 0, EXTERIA_SCOPE_USERS, &peer, &value, request);
    } onSuccess:nil completion:completion];
}

- (void)resetNotifyOfPeerKind:(int32_t)kind id:(long long)peerId hash:(long long)hash topic:(int32_t)topic completion:(void (^)(NSString *))completion {
    exteria_peer_notify defaults;
    memset(&defaults, 0, sizeof(defaults));
    defaults.has_mute = 1;
    defaults.has_previews = defaults.previews = 1;
    defaults.has_silent = 1;
    defaults.has_sound = 1;
    [self updateNotify:[NSValue valueWithBytes:&defaults objCType:@encode(exteria_peer_notify)] ofPeerKind:kind id:peerId hash:hash topic:topic completion:completion];
}

#pragma mark all

- (void)resetAllNotifySettingsWithCompletion:(void (^)(NSString *))completion {
    [self runNotifyRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_notify_reset_request(arena, request);
    } onSuccess:^{ ExteriaNotifyStoreReset(); } completion:completion];
}

- (void)setContactJoinedNotify:(BOOL)on completion:(void (^)(NSString *))completion {
    [self runNotifyRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_notify_signup_request(arena, on ? 0 : 1, request);
    } onSuccess:nil completion:completion];
}

#pragma mark tones

- (void)loadCloudTonesWithCompletion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_ringtones_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *tones = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_ringtone_row *rows = calloc(RINGTONES_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_ringtones_parse(result->value, rows, RINGTONES_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                tones = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [tones addObject:[[[ExteriaCloudTone alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: the saved tones were rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *delivered = [tones retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, deliveredError); [delivered release]; [done release]; }];
    }];
}

- (void)removeCloudTone:(ExteriaCloudTone *)tone completion:(void (^)(NSString *))completion {
    exteria_ringtone_row row = tone.row;
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_ringtone_unsave_request(arena, &row, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ if (done) done(delivered); [done release]; }];
    }];
}

@end
