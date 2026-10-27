#import "exteria_session_namecolor.h"

#import "exteria_session_internal.h"

#include "exteria_name_color.h"

#import "exteria_peer_colors.h"
#import "exteria_rpc.h"

@implementation ExteriaSession (NameColor)

- (void)loadNameColors:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_name_colors_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *colors = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_name_color_option *rows = calloc(EXTERIA_NAME_COLORS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_name_colors_parse(result->value, rows, EXTERIA_NAME_COLORS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                colors = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    [colors addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:rows[i].id], @"id", [NSNumber numberWithUnsignedInt:rows[i].light], @"light",
                                       [NSNumber numberWithUnsignedInt:rows[i].dark], @"dark", [NSNumber numberWithBool:rows[i].hidden != 0], @"hidden", nil]];
                }
            } else {
                NSLog(@"exteria: help.getPeerColors answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            /* a list that has not changed is an empty one, and what is stored stays */
            if (colors.count) ExteriaStoreServerNameColors(colors);
            done(colors.count ? colors : ExteriaServerNameColors(), deliveredError);
            [done release];
        }];
    }];
}

- (void)setNameColorId:(NSInteger)colorId completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_name_color_set_request(arena, (int32_t)colorId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status parsed = exteria_name_color_set_parse(result->value);
            if (parsed == EXTERIA_E_STATE) error = @"NOT_MODIFIED";
            else if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@end
