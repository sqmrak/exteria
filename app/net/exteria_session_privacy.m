#import "exteria_session_privacy.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

static NSString *ExteriaPrivacyText(const char *text) {
    NSString *string = [NSString stringWithUTF8String:text];
    return string ? string : @"";
}

@implementation ExteriaPrivacyEntry
@synthesize identifier = _identifier;
@synthesize chat = _chat;
@synthesize name = _name;
@synthesize photo = _photo;

- (id)initWithIdentifier:(long long)identifier chat:(BOOL)chat name:(NSString *)name ref:(const exteria_photo_ref *)ref {
    self = [super init];
    if (!self) return nil;
    _identifier = identifier;
    _chat = chat;
    _name = [name copy];
    _photo = [[ExteriaPhoto photoWithRef:ref] retain];
    return self;
}

- (void)dealloc {
    [_name release];
    [_photo release];
    [super dealloc];
}
@end

@implementation ExteriaPrivacyRules
@synthesize key = _key;

- (id)initWithKey:(exteria_privacy_key)key rules:(const exteria_privacy_rules *)rules {
    self = [super init];
    if (!self) return nil;
    _key = key;
    _rules = malloc(sizeof(*_rules));
    if (!_rules) {
        [self release];
        return nil;
    }
    *_rules = *rules;
    return self;
}

- (void)dealloc {
    free(_rules);
    [super dealloc];
}

- (exteria_privacy_base)base { return _rules->base; }
- (void)setBase:(exteria_privacy_base)base { _rules->base = base; }
- (const exteria_privacy_rules *)rules { return _rules; }

- (NSUInteger)countAllowed:(BOOL)allowed {
    return allowed ? _rules->allow_users_count + _rules->allow_chats_count : _rules->disallow_users_count + _rules->disallow_chats_count;
}

- (NSArray *)entriesAllowed:(BOOL)allowed {
    NSMutableArray *entries = [NSMutableArray array];
    const exteria_privacy_user *users = allowed ? _rules->allow_users : _rules->disallow_users;
    const exteria_privacy_chat *chats = allowed ? _rules->allow_chats : _rules->disallow_chats;
    size_t userCount = allowed ? _rules->allow_users_count : _rules->disallow_users_count;
    size_t chatCount = allowed ? _rules->allow_chats_count : _rules->disallow_chats_count;
    for (size_t i = 0; i < userCount; ++i) {
        [entries addObject:[[[ExteriaPrivacyEntry alloc] initWithIdentifier:users[i].id chat:NO name:ExteriaPrivacyText(users[i].name) ref:&users[i].photo] autorelease]];
    }
    for (size_t i = 0; i < chatCount; ++i) {
        [entries addObject:[[[ExteriaPrivacyEntry alloc] initWithIdentifier:chats[i].id chat:YES name:ExteriaPrivacyText(chats[i].title) ref:&chats[i].photo] autorelease]];
    }
    return entries;
}

static void ExteriaPrivacyDropUser(exteria_privacy_user *users, size_t *count, long long identifier) {
    for (size_t i = 0; i < *count; ++i) {
        if (users[i].id != identifier) continue;
        memmove(&users[i], &users[i + 1], (*count - i - 1) * sizeof(*users));
        --*count;
        return;
    }
}

- (BOOL)addUser:(long long)userId hash:(long long)hash name:(NSString *)name photo:(ExteriaPhoto *)photo allowed:(BOOL)allowed {
    if (hash == 0) return NO;
    exteria_privacy_user *same = allowed ? _rules->allow_users : _rules->disallow_users;
    size_t *sameCount = allowed ? &_rules->allow_users_count : &_rules->disallow_users_count;
    exteria_privacy_user *other = allowed ? _rules->disallow_users : _rules->allow_users;
    size_t *otherCount = allowed ? &_rules->disallow_users_count : &_rules->allow_users_count;
    ExteriaPrivacyDropUser(other, otherCount, userId);
    for (size_t i = 0; i < *sameCount; ++i) if (same[i].id == userId) return YES;
    if (*sameCount >= EXTERIA_PRIVACY_EXCEPT_MAX) return NO;
    exteria_privacy_user *slot = &same[(*sameCount)++];
    memset(slot, 0, sizeof(*slot));
    slot->id = userId;
    slot->access_hash = hash;
    if (photo) slot->photo = photo.ref;
    const char *text = name.UTF8String ? name.UTF8String : "";
    size_t length = strlen(text);
    if (length >= sizeof(slot->name)) {
        length = sizeof(slot->name) - 1;
        while (length > 0 && ((uint8_t)text[length] & 0xC0u) == 0x80u) --length;
    }
    memcpy(slot->name, text, length);
    return YES;
}

- (BOOL)addChat:(long long)chatId title:(NSString *)title photo:(ExteriaPhoto *)photo allowed:(BOOL)allowed {
    exteria_privacy_chat *same = allowed ? _rules->allow_chats : _rules->disallow_chats;
    size_t *sameCount = allowed ? &_rules->allow_chats_count : &_rules->disallow_chats_count;
    exteria_privacy_chat *other = allowed ? _rules->disallow_chats : _rules->allow_chats;
    size_t *otherCount = allowed ? &_rules->disallow_chats_count : &_rules->allow_chats_count;
    for (size_t i = 0; i < *otherCount; ++i) {
        if (other[i].id != chatId) continue;
        memmove(&other[i], &other[i + 1], (*otherCount - i - 1) * sizeof(*other));
        --*otherCount;
        break;
    }
    for (size_t i = 0; i < *sameCount; ++i) if (same[i].id == chatId) return YES;
    if (*sameCount >= EXTERIA_PRIVACY_EXCEPT_MAX) return NO;
    exteria_privacy_chat *slot = &same[(*sameCount)++];
    memset(slot, 0, sizeof(*slot));
    slot->id = chatId;
    if (photo) slot->photo = photo.ref;
    const char *text = title.UTF8String ? title.UTF8String : "";
    size_t length = strlen(text);
    if (length >= sizeof(slot->title)) {
        length = sizeof(slot->title) - 1;
        while (length > 0 && ((uint8_t)text[length] & 0xC0u) == 0x80u) --length;
    }
    memcpy(slot->title, text, length);
    return YES;
}

- (void)removeEntry:(ExteriaPrivacyEntry *)entry allowed:(BOOL)allowed {
    if (entry.chat) {
        exteria_privacy_chat *chats = allowed ? _rules->allow_chats : _rules->disallow_chats;
        size_t *count = allowed ? &_rules->allow_chats_count : &_rules->disallow_chats_count;
        for (size_t i = 0; i < *count; ++i) {
            if (chats[i].id != entry.identifier) continue;
            memmove(&chats[i], &chats[i + 1], (*count - i - 1) * sizeof(*chats));
            --*count;
            return;
        }
    } else {
        ExteriaPrivacyDropUser(allowed ? _rules->allow_users : _rules->disallow_users, allowed ? &_rules->allow_users_count : &_rules->disallow_users_count, entry.identifier);
    }
}
@end

@implementation ExteriaBlockedPeer
@synthesize name = _name;
@synthesize photo = _photo;

- (id)initWithRow:(const exteria_blocked_row *)row {
    self = [super init];
    if (!self) return nil;
    _row = *row;
    _name = [ExteriaPrivacyText(row->name) copy];
    _photo = [[ExteriaPhoto photoWithRef:&row->photo] retain];
    return self;
}

- (void)dealloc {
    [_photo release];
    [_name release];
    [super dealloc];
}

- (int32_t)kind { return _row.kind; }
- (long long)identifier { return _row.id; }
- (long long)accessHash { return _row.access_hash; }
- (int32_t)date { return _row.date; }
@end

@implementation ExteriaSession (Privacy)

/* an answer of rules, parsed on the worker into a fresh copy for the main thread */
- (ExteriaPrivacyRules *)privacyRulesOfResult:(const exteria_mt_rpc_result *)result key:(exteria_privacy_key)key error:(NSString **)error {
    exteria_privacy_rules *rules = malloc(sizeof(*rules));
    ExteriaPrivacyRules *made = nil;
    if (!rules) {
        *error = @"INTERNAL";
        return nil;
    }
    exteria_status status = exteria_privacy_parse(result->value, rules);
    if (status == EXTERIA_OK) {
        made = [[[ExteriaPrivacyRules alloc] initWithKey:key rules:rules] autorelease];
    } else {
        NSLog(@"exteria: the privacy rules were rejected: %s", exteria_status_name(status));
        /* a list longer than the screen can hold must not be edited, or what is cut would be lost on the server */
        *error = status == EXTERIA_E_LIMIT ? @"PRIVACY_TOO_MANY" : @"INTERNAL";
    }
    free(rules);
    return made;
}

- (void)runPrivacyRequest:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build key:(exteria_privacy_key)key
               completion:(void (^)(ExteriaPrivacyRules *, NSString *))completion {
    void (^done)(ExteriaPrivacyRules *, NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        ExteriaPrivacyRules *rules = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else rules = [self privacyRulesOfResult:result key:key error:&error];
        [self noteRpcError:error];
        ExteriaPrivacyRules *delivered = [rules retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, deliveredError); [delivered release]; [done release]; }];
    }];
}

- (void)loadPrivacy:(exteria_privacy_key)key completion:(void (^)(ExteriaPrivacyRules *, NSString *))completion {
    [self runPrivacyRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_privacy_get_request(arena, key, request);
    } key:key completion:completion];
}

- (void)savePrivacy:(ExteriaPrivacyRules *)rules completion:(void (^)(ExteriaPrivacyRules *, NSString *))completion {
    exteria_privacy_key key = rules.key;
    NSData *copy = [NSData dataWithBytes:rules.rules length:sizeof(exteria_privacy_rules)];
    [self runPrivacyRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_privacy_set_request(arena, key, copy.bytes, request);
    } key:key completion:completion];
}

- (void)loadBlockedFrom:(int32_t)offset completion:(void (^)(NSArray *, int32_t, NSString *))completion {
    void (^done)(NSArray *, int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_blocked_request(arena, offset, EXTERIA_BLOCKED_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *peers = nil;
        int32_t total = 0;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_blocked_row *rows = calloc(EXTERIA_BLOCKED_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_blocked_parse(result->value, rows, EXTERIA_BLOCKED_MAX, &count, &total) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                peers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [peers addObject:[[[ExteriaBlockedPeer alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: the blocked list was rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *delivered = [peers retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, total, deliveredError); [delivered release]; [done release]; }];
    }];
}

/* a call whose answer is only good or not */
- (void)runPrivacyPlain:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)setBlocked:(BOOL)blocked kind:(int32_t)kind identifier:(long long)identifier hash:(long long)hash completion:(void (^)(NSString *))completion {
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = kind;
    peer.id = identifier;
    peer.access_hash = hash;
    [self runPrivacyPlain:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_block_request(arena, &peer, blocked, request);
    } completion:completion];
}

/* a call whose answer is one number */
- (void)runPrivacyNumber:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build parse:(exteria_status (^)(const exteria_tl_value *answer, int32_t *value))parse
              completion:(void (^)(int32_t, NSString *))completion {
    void (^done)(int32_t, NSString *) = [completion copy];
    exteria_status (^reader)(const exteria_tl_value *, int32_t *) = [parse copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        int32_t value = 0;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status status = reader(result->value, &value);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: a privacy setting was rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(value, delivered); [done release]; }];
        [reader release];
    }];
}

- (void)loadAccountTTL:(void (^)(int32_t, NSString *))completion {
    [self runPrivacyNumber:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_account_ttl_request(arena, request);
    } parse:^exteria_status(const exteria_tl_value *answer, int32_t *value) {
        return exteria_account_ttl_parse(answer, value);
    } completion:completion];
}

- (void)setAccountTTL:(int32_t)days completion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_account_ttl_set_request(arena, days, request);
    } completion:completion];
}

- (void)loadHistoryTTL:(void (^)(int32_t, NSString *))completion {
    [self runPrivacyNumber:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_history_ttl_request(arena, request);
    } parse:^exteria_status(const exteria_tl_value *answer, int32_t *value) {
        return exteria_history_ttl_parse(answer, value);
    } completion:completion];
}

- (void)setHistoryTTL:(int32_t)seconds completion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_history_ttl_set_request(arena, seconds, request);
    } completion:completion];
}

- (void)clearPaymentsCredentials:(BOOL)credentials info:(BOOL)info completion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_clear_payments_request(arena, credentials, info, request);
    } completion:completion];
}

- (void)resetSavedContactsWithCompletion:(void (^)(NSString *))completion {
    [self runPrivacyPlain:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_reset_saved_contacts_request(arena, request);
    } completion:completion];
}

@end
