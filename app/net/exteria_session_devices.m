#import "exteria_session_devices.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

@implementation ExteriaDeviceSession

@synthesize secretChatsOn = _secretChatsOn;
@synthesize callsOn = _callsOn;

static NSString *ExteriaDeviceText(const char *text) {
    NSString *string = [NSString stringWithUTF8String:text];
    return string ? string : @"";
}

- (id)initWithInfo:(const exteria_session_info *)info {
    self = [super init];
    if (!self) return nil;
    _info = *info;
    char buffer[EXTERIA_SESSION_TEXT_MAX * 2];
    exteria_session_title(info, buffer, sizeof(buffer));
    _title = [ExteriaDeviceText(buffer) copy];
    exteria_session_app_line(info, buffer, sizeof(buffer));
    _appLine = [ExteriaDeviceText(buffer) copy];
    NSString *country = ExteriaDeviceText(info->country), *region = ExteriaDeviceText(info->region);
    /* a region that only repeats the country is left out */
    _place = [(region.length && ![region isEqualToString:country] ? (country.length ? [NSString stringWithFormat:@"%@, %@", region, country] : region) : country) copy];
    _secretChatsOn = !info->secret_chats_off;
    _callsOn = !info->calls_off;
    return self;
}

- (void)dealloc {
    [_title release];
    [_appLine release];
    [_place release];
    [super dealloc];
}

- (long long)sessionHash { return _info.hash; }
- (BOOL)current { return _info.current != 0; }
- (BOOL)passwordPending { return _info.password_pending != 0; }
- (int32_t)dateActive { return _info.date_active; }
- (int32_t)apiId { return _info.api_id; }
/* the ids: the desktop app 2040 and the web app 2496 take no secret chats, and the app 22 takes no calls */
- (BOOL)takesSecretChatsSetting { return _info.api_id != 2040 && _info.api_id != 2496; }
- (BOOL)takesCallsSetting { return _info.api_id != 22; }
- (exteria_session_kind)kind { return exteria_session_kind_of(&_info); }
- (NSString *)title { return _title; }
- (NSString *)appLine { return _appLine; }
- (NSString *)place { return _place; }
- (NSString *)ip { return ExteriaDeviceText(_info.ip); }

@end

@implementation ExteriaSession (Devices)

- (void)loadDevices:(void (^)(NSArray *, int32_t, NSString *))completion {
    void (^done)(NSArray *, int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sessions_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *sessions = nil;
        int32_t ttl = 0;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_session_info *rows = calloc(EXTERIA_SESSIONS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_sessions_parse(result->value, rows, EXTERIA_SESSIONS_MAX, &count, &ttl) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                sessions = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sessions addObject:[[[ExteriaDeviceSession alloc] initWithInfo:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: the session list was rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *delivered = [sessions retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, ttl, deliveredError); [delivered release]; [done release]; }];
    }];
}

/* every call of the screen ends in an answer that is only good or not */
- (void)runDeviceRequest:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)endDevice:(ExteriaDeviceSession *)device completion:(void (^)(NSString *))completion {
    long long hash = device.sessionHash;
    [self runDeviceRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_session_end_request(arena, hash, request);
    } completion:completion];
}

- (void)endOtherDevicesWithCompletion:(void (^)(NSString *))completion {
    [self runDeviceRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sessions_end_others_request(arena, request);
    } completion:completion];
}

- (void)setDevice:(ExteriaDeviceSession *)device secretChats:(int)secretChats calls:(int)calls completion:(void (^)(NSString *))completion {
    long long hash = device.sessionHash;
    [self runDeviceRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_session_settings_request(arena, hash, secretChats, calls, request);
    } completion:completion];
}

- (void)setDevicesTTL:(int32_t)days completion:(void (^)(NSString *))completion {
    [self runDeviceRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sessions_ttl_request(arena, days, request);
    } completion:completion];
}

- (void)acceptLoginLink:(NSString *)link completion:(void (^)(NSString *))completion {
    uint8_t token[EXTERIA_LOGIN_TOKEN_MAX];
    size_t length = 0;
    if (exteria_login_token_from_link(link.UTF8String, token, sizeof(token), &length) != EXTERIA_OK) {
        void (^done)(NSString *) = [completion copy];
        [self deliverMain:^{ done(@"LOGIN_TOKEN_INVALID"); [done release]; }];
        return;
    }
    NSData *bytes = [NSData dataWithBytes:token length:length];
    [self runDeviceRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_login_token_accept_request(arena, bytes.bytes, bytes.length, request);
    } completion:completion];
}

@end
