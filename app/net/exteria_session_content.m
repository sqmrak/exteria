#import "exteria_session_content.h"

#import "exteria_session_internal.h"

#include "exteria_content.h"

#import "exteria_rpc.h"

@implementation ExteriaSession (Content)

- (void)loadContentSettings:(void (^)(BOOL, BOOL, NSString *))completion {
    void (^done)(BOOL, BOOL, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_content_settings_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        exteria_content_settings settings;
        NSString *error = nil;
        memset(&settings, 0, sizeof(settings));
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_content_settings_parse(result->value, &settings) != EXTERIA_OK) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        BOOL enabled = settings.sensitive_enabled != 0, canChange = settings.sensitive_can_change != 0;
        [self deliverMain:^{ done(enabled, canChange, delivered); [done release]; }];
    }];
}

- (void)setSensitiveContent:(BOOL)enabled completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_content_set_request(arena, enabled ? 1 : 0, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status parsed = exteria_content_set_parse(result->value);
            if (parsed == EXTERIA_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@end
