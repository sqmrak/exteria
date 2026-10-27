#import "exteria_session_data.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_sticker_manage.h"

@implementation ExteriaSession (Data)

- (void)clearAllDraftsWithCompletion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "messages.clearAllDrafts");
        return *request ? EXTERIA_OK : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            /* the Bool the server answers with: true when it did what was asked */
            exteria_status parsed = exteria_sticker_manage_parse(result->value);
            if (parsed == EXTERIA_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            done(delivered);
            [done release];
        }];
    }];
}

- (void)sendOfflineStatus {
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "account.updateStatus");
        return *request ? exteria_tl_set(*request, "offline", exteria_tl_new_obj(arena, "boolTrue")) : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) NSLog(@"exteria: account.updateStatus failed: %@", ExteriaRpcErrorName(result));
    }];
}

- (void)deleteAccountWithReason:(NSString *)reason completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *text = [reason copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "account.deleteAccount");
        return *request ? exteria_tl_set_str(arena, *request, "reason", text.UTF8String ? text.UTF8String : "") : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status parsed = exteria_sticker_manage_parse(result->value);
            if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            done(delivered);
            [done release];
        }];
    }];
    [text release];
}

@end
