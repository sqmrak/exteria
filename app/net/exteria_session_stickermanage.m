#import "exteria_session_stickermanage.h"

#import "exteria_session_internal.h"

#include "exteria_sticker_manage.h"
#include "exteria_messages.h"

#import "exteria_rpc.h"

NSString *const ExteriaStickerSetsDidChangeNotification = @"ExteriaStickerSetsDidChange";

@implementation ExteriaSession (StickerManage)

/* the answer of both calls: a Bool, true when the server did what was asked */
- (void)finishManage:(const exteria_mt_rpc_result *)result completion:(void (^)(NSString *))done {
    NSString *error = nil;
    if (result->status != EXTERIA_OK) {
        error = ExteriaRpcErrorName(result);
    } else {
        exteria_status parsed = exteria_sticker_manage_parse(result->value);
        if (parsed == EXTERIA_E_STATE) error = @"NOT_MODIFIED";
        else if (parsed != EXTERIA_OK) error = @"MALFORMED";
    }
    [self noteRpcError:error];
    NSString *delivered = [[error copy] autorelease];
    [self deliverMain:^{
        if (!delivered) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaStickerSetsDidChangeNotification object:nil];
        done(delivered);
        [done release];
    }];
}

- (void)uninstallStickerSet:(ExteriaStickerSet *)set completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    int64_t setId = set.row.id, hash = set.row.access_hash;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_uninstall_request(arena, setId, hash, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishManage:result completion:done];
    }];
}

- (void)installStickerSet:(ExteriaStickerSet *)set completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    int64_t setId = set.row.id, hash = set.row.access_hash;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_install_request(arena, setId, hash, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_sticker_install_parse(result->value) != EXTERIA_OK) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            if (!delivered) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaStickerSetsDidChangeNotification object:nil];
            done(delivered);
            [done release];
        }];
    }];
}

- (void)loadStickerPackWithId:(long long)setId accessHash:(long long)accessHash
                   completion:(void (^)(ExteriaStickerSet *, NSArray *, NSString *))completion {
    void (^done)(ExteriaStickerSet *, NSArray *, NSString *) = [completion copy];
    exteria_sticker_set_row wanted;
    memset(&wanted, 0, sizeof(wanted));
    wanted.id = setId;
    wanted.access_hash = accessHash;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_set_request(arena, &wanted, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaStickerSet *set = nil;
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_row *rows = calloc(EXTERIA_STICKERS_MAX, sizeof(*rows));
            exteria_sticker_set_row header;
            size_t count = 0;
            if (rows && exteria_sticker_set_parse(result->value, &header, rows, EXTERIA_STICKERS_MAX, &count) == EXTERIA_OK) {
                set = [ExteriaStickerSet setWithRow:&header];
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[ExteriaSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getStickerSet answer for a pack was rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        ExteriaStickerSet *deliveredSet = [set retain];
        NSArray *deliveredStickers = [stickers retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            done(deliveredSet, deliveredStickers, deliveredError);
            [deliveredSet release];
            [deliveredStickers release];
            [done release];
        }];
    }];
}

- (void)loadFeaturedStickerSets:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_featured_stickers_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_set_row *rows = calloc(EXTERIA_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_featured_stickers_parse(result->value, rows, EXTERIA_STICKER_SETS_MAX, &count) == EXTERIA_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[ExteriaStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getFeaturedStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:sets error:error completion:done];
        [done release];
    }];
}

- (void)loadArchivedStickerSetsLimit:(int32_t)limit completion:(void (^)(NSArray *, int32_t, NSString *))completion {
    void (^done)(NSArray *, int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_archived_stickers_request(arena, 0, limit, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        int32_t total = 0;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_set_row *rows = calloc(EXTERIA_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_archived_stickers_parse(result->value, rows, EXTERIA_STICKER_SETS_MAX, &count, &total) == EXTERIA_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[ExteriaStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getArchivedStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredSets = [sets retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            done(deliveredSets, total, deliveredError);
            [deliveredSets release];
            [done release];
        }];
    }];
}

- (void)moveStickerSetToTop:(ExteriaStickerSet *)set among:(NSArray *)sets completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSUInteger count = MIN(sets.count, (NSUInteger)EXTERIA_STICKER_ORDER_MAX);
    int64_t *ids = calloc(count ? count : 1, sizeof(*ids));
    size_t used = 0;
    if (ids) {
        ids[used++] = set.row.id;
        for (ExteriaStickerSet *other in sets) {
            if (other.row.id != set.row.id && used < count) ids[used++] = other.row.id;
        }
    }
    NSData *order = ids ? [NSData dataWithBytes:ids length:used * sizeof(*ids)] : nil;
    free(ids);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        if (!order.length) return EXTERIA_E_ARG;
        return exteria_sticker_reorder_request(arena, (const int64_t *)order.bytes, order.length / sizeof(int64_t), request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishManage:result completion:done];
    }];
}

@end
