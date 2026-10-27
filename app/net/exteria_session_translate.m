#import "exteria_session_translate.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_translate.h"

@implementation ExteriaSession (Translate)

- (void)translateText:(NSString *)text to:(NSString *)language completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    NSString *body = [[text copy] autorelease];
    NSString *code = [[language copy] autorelease];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_translate_request(arena, body.UTF8String, code.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *translated = nil, *error = nil;
        if (result->status == EXTERIA_E_ARG) {
            error = @"ARG";
        } else if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            char *buffer = malloc(EXTERIA_TRANSLATE_TEXT_MAX + 1);
            if (buffer && exteria_translate_parse(result->value, buffer, EXTERIA_TRANSLATE_TEXT_MAX + 1) == EXTERIA_OK) translated = [NSString stringWithUTF8String:buffer];
            if (!translated) error = @"MALFORMED";
            free(buffer);
        }
        [self noteRpcError:error];
        NSString *delivered = [[translated copy] autorelease];
        NSString *failure = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, failure); [done release]; }];
    }];
}

@end
