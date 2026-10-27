#import "exteria_session_logins.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_logins.h"

@implementation ExteriaUnconfirmedLogin

@synthesize sessionHash = _hash;
@synthesize date = _date;
@synthesize device = _device;
@synthesize place = _place;

- (id)initWithRow:(const exteria_unconfirmed_login *)row {
    self = [super init];
    if (!self) return nil;
    _hash = row->hash;
    _date = row->date;
    _device = [[NSString stringWithUTF8String:row->device] copy];
    _place = [[NSString stringWithUTF8String:row->place] copy];
    if (!_device) _device = [@"" copy];
    if (!_place) _place = [@"" copy];
    return self;
}

- (void)dealloc {
    [_device release];
    [_place release];
    [super dealloc];
}

@end

@implementation ExteriaSession (Logins)

- (void)loadUnconfirmedLogins:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_logins_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *logins = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_unconfirmed_login *rows = calloc(EXTERIA_LOGINS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_logins_parse(result->value, rows, EXTERIA_LOGINS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                logins = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [logins addObject:[[[ExteriaUnconfirmedLogin alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: account.getAuthorizations answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:logins error:error completion:done];
        [done release];
    }];
}

- (void)answerLogin:(ExteriaUnconfirmedLogin *)login confirm:(BOOL)confirm completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    long long hash = login.sessionHash;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return confirm ? exteria_login_confirm_request(arena, hash, request) : exteria_login_reset_request(arena, hash, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)confirmLogin:(ExteriaUnconfirmedLogin *)login completion:(void (^)(NSString *))completion {
    [self answerLogin:login confirm:YES completion:completion];
}

- (void)terminateLogin:(ExteriaUnconfirmedLogin *)login completion:(void (^)(NSString *))completion {
    [self answerLogin:login confirm:NO completion:completion];
}

@end
