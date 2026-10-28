#import "exteria_profile_colors.h"

#import "exteria_session_internal.h"

#include "exteria_people.h"

#import "exteria_rpc.h"

static NSMutableDictionary *ExteriaProfileColorTable;
static BOOL ExteriaProfileColorsAsking;

@implementation ExteriaProfileColors

+ (void)loadWithSession:(ExteriaSession *)session completion:(void (^)(void))done {
    if (ExteriaProfileColorTable || !session) {
        if (done) done();
        return;
    }
    void (^finished)(void) = [done copy];
    /* a second screen that asks while the first one waits is not given a second request: it is told when the list is there, by the same answer */
    static NSMutableArray *waiting;
    if (!waiting) waiting = [[NSMutableArray alloc] init];
    if (finished) [waiting addObject:[[finished copy] autorelease]];
    [finished release];
    if (ExteriaProfileColorsAsking) return;
    ExteriaProfileColorsAsking = YES;
    [session invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_profile_colors_request(arena, 0, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableDictionary *table = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_profile_color *rows = calloc(EXTERIA_PROFILE_COLORS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_profile_colors_parse(result->value, rows, EXTERIA_PROFILE_COLORS_MAX, &count, NULL) == EXTERIA_OK) {
                table = [NSMutableDictionary dictionary];
                for (size_t i = 0; i < count; ++i) {
                    [table setObject:[NSData dataWithBytes:&rows[i] length:sizeof(rows[i])] forKey:[NSNumber numberWithInt:rows[i].id]];
                }
            } else {
                error = @"MALFORMED";
            }
            free(rows);
        }
        if (error) NSLog(@"exteria: the profile colors were not loaded: %@", error);
        [session deliverMain:^{
            ExteriaProfileColorsAsking = NO;
            if (table) ExteriaProfileColorTable = [table retain];
            NSArray *callbacks = [[waiting copy] autorelease];
            [waiting removeAllObjects];
            for (void (^callback)(void) in callbacks) callback();
        }];
    }];
}

+ (BOOL)blendForColorId:(int32_t)colorId dark:(BOOL)dark center:(uint32_t *)center edge:(uint32_t *)edge {
    NSData *packed = [ExteriaProfileColorTable objectForKey:[NSNumber numberWithInt:colorId]];
    if (packed.length != sizeof(exteria_profile_color)) return NO;
    exteria_profile_color row;
    memcpy(&row, packed.bytes, sizeof(row));
    const uint32_t *bg = dark && row.has_dark ? row.dark_bg : row.bg;
    if (center) *center = bg[0];
    if (edge) *edge = bg[1];
    return YES;
}

@end
