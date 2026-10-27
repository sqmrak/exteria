#import "exteria_gift_folders.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_gifts.h"

@implementation ExteriaGiftFolder

@synthesize folderId = _folderId;
@synthesize count = _count;
@synthesize title = _title;

- (id)initWithRow:(const exteria_gift_collection *)row {
    self = [super init];
    if (!self) return nil;
    _folderId = row->id;
    _count = row->count;
    _title = [[NSString stringWithUTF8String:row->title] copy];
    return self;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

@end

/* the ids of the messages of these gifts, at most one batch; the rest of a longer list is the caller's next call */
static NSData *ExteriaGiftMessageIds(NSArray *gifts) {
    NSMutableData *data = [NSMutableData data];
    for (ExteriaSavedGift *gift in gifts) {
        if (gift.messageId <= 0 || data.length / sizeof(int32_t) >= EXTERIA_GIFT_COLLECTION_BATCH_MAX) continue;
        int32_t identifier = gift.messageId;
        [data appendBytes:&identifier length:sizeof(identifier)];
    }
    return data;
}

@implementation ExteriaSession (GiftFolders)

- (void)loadGiftFoldersOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_collections_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *folders = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_gift_collection *rows = calloc(EXTERIA_GIFT_COLLECTIONS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_gift_collections_parse(result->value, rows, EXTERIA_GIFT_COLLECTIONS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                folders = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [folders addObject:[[[ExteriaGiftFolder alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: payments.getStarGiftCollections answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredFolders = [[folders copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredFolders, deliveredError); [done release]; }];
    }];
}

- (void)loadSavedGiftsOfDialog:(ExteriaDialog *)dialog folder:(int32_t)folderId offset:(NSString *)offset completion:(ExteriaSavedGiftsCompletion)completion {
    if (folderId <= 0) {
        [self loadSavedGiftsOfDialog:dialog offset:offset completion:completion];
        return;
    }
    ExteriaSavedGiftsCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *start = offset ? [offset copy] : [@"" copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_saved_gifts_in_collection_request(arena, &peer, folderId, start.UTF8String, 30, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *gifts = nil;
        NSString *next = nil;
        NSString *error = nil;
        NSInteger total = 0;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_saved_gift *rows = calloc(EXTERIA_SAVED_GIFTS_MAX, sizeof(*rows));
            exteria_saved_gift_page page;
            size_t count = 0;
            exteria_status status = rows ? exteria_saved_gifts_parse(result->value, rows, EXTERIA_SAVED_GIFTS_MAX, &count, &page) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                gifts = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [gifts addObject:[ExteriaSavedGift savedGiftWithRow:&rows[i]]];
                total = page.total;
                if (page.next_offset[0]) next = [NSString stringWithUTF8String:page.next_offset];
            } else {
                NSLog(@"exteria: payments.getSavedStarGifts of a folder answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredGifts = [[gifts copy] autorelease];
        NSString *deliveredNext = [[next copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredGifts, total, deliveredNext, deliveredError); [done release]; }];
    }];
    [start release];
}

/* a request whose answer is a folder or true, of which only the error matters */
- (void)runFolderRequest:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ if (done) done(delivered); [done release]; }];
    }];
}

- (void)createGiftFolderTitled:(NSString *)title withGifts:(NSArray *)gifts dialog:(ExteriaDialog *)dialog
                    completion:(void (^)(ExteriaGiftFolder *, NSString *))completion {
    void (^done)(ExteriaGiftFolder *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *name = [title copy];
    NSData *ids = [ExteriaGiftMessageIds(gifts) retain];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_collection_create_request(arena, &peer, name.UTF8String, ids.bytes, ids.length / sizeof(int32_t), request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaGiftFolder *folder = nil;
        NSString *error = nil;
        exteria_gift_collection row;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_gift_collection_read(result->value, &row) != EXTERIA_OK) error = @"INTERNAL";
        else folder = [[[ExteriaGiftFolder alloc] initWithRow:&row] autorelease];
        [self noteRpcError:error];
        ExteriaGiftFolder *deliveredFolder = [folder retain];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredFolder, deliveredError); [deliveredFolder release]; [done release]; }];
    }];
    [name release];
    [ids release];
}

- (void)renameGiftFolder:(ExteriaGiftFolder *)folder to:(NSString *)title dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    NSString *name = [[title copy] autorelease];
    [self runFolderRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_collection_update_request(arena, &peer, identifier, name.UTF8String, NULL, 0, NULL, 0, request);
    } completion:completion];
}

- (void)addGifts:(NSArray *)gifts toFolder:(ExteriaGiftFolder *)folder dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    NSData *ids = [ExteriaGiftMessageIds(gifts) retain];
    [self runFolderRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_collection_update_request(arena, &peer, identifier, NULL, ids.bytes, ids.length / sizeof(int32_t), NULL, 0, request);
    } completion:^(NSString *error) {
        [ids release];
        if (completion) completion(error);
    }];
}

- (void)removeGifts:(NSArray *)gifts fromFolder:(ExteriaGiftFolder *)folder dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    NSData *ids = [ExteriaGiftMessageIds(gifts) retain];
    [self runFolderRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_collection_update_request(arena, &peer, identifier, NULL, NULL, 0, ids.bytes, ids.length / sizeof(int32_t), request);
    } completion:^(NSString *error) {
        [ids release];
        if (completion) completion(error);
    }];
}

- (void)deleteGiftFolder:(ExteriaGiftFolder *)folder dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t identifier = folder.folderId;
    [self runFolderRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_collection_delete_request(arena, &peer, identifier, request);
    } completion:completion];
}

@end
