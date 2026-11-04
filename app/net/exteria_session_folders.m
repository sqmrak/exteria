#import "exteria_session_folders.h"
#import "exteria_session_drafts.h"
#import "exteria_session_internal.h"
#import "exteria_rpc.h"
#include "exteria_tl_ids.h"
#include "exteria_clock.h"
#include "exteria_list_state.h"

NSString *const ExteriaChatFoldersDidChangeNotification = @"ExteriaChatFoldersDidChangeNotification";

@interface ExteriaSession (FolderFloodWait)
- (NSString *)folderFloodError;
- (void)rememberFolderFloodError:(NSString *)error;
@end

@implementation ExteriaSession (FolderFloodWait)
- (NSString *)folderFloodError {
    uint64_t now = exteria_system_clock.monotonic_ms(exteria_system_clock.ctx);
    @synchronized(self) {
        uint32_t seconds = exteria_list_flood_remaining(_folderFloodUntilMs, now);
        if (!seconds) return nil;
        return [NSString stringWithFormat:@"FLOOD_WAIT_%u", (unsigned)seconds];
    }
}
- (void)rememberFolderFloodError:(NSString *)error {
    uint32_t seconds = 0;
    if (!exteria_list_flood_wait(error.UTF8String, &seconds)) return;
    uint64_t now = exteria_system_clock.monotonic_ms(exteria_system_clock.ctx);
    @synchronized(self) {
        _folderFloodUntilMs = exteria_list_flood_deadline(_folderFloodUntilMs, now, seconds);
    }
}
@end

@implementation ExteriaSuggestedFolder
@synthesize folder = _folder;
@synthesize info = _info;
- (id)initWithFolder:(ExteriaChatFolder *)folder info:(NSString *)info {
    self = [super init];
    if (!self) return nil;
    _folder = [folder retain];
    _info = [info copy];
    return self;
}
- (void)dealloc {
    [_folder release];
    [_info release];
    [super dealloc];
}
@end

static NSArray *folders_read(const exteria_tl_value *answer) {
    const exteria_tl_value *list = exteria_tl_get(answer, "filters");
    if (!list || list->kind != EXTERIA_TL_V_VEC || list->u.vec.count > EXTERIA_FOLDERS_MAX)
        return nil;
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (uint32_t i = 0; i < list->u.vec.count; ++i) {
        ExteriaChatFolder *folder = [ExteriaChatFolder folderWithValue:list->u.vec.items[i]];
        NSNumber *key = [NSNumber numberWithInt:folder.folderId];
        if (!folder || [ids containsObject:key])
            return nil;
        [ids addObject:key];
        [folders addObject:folder];
    }
    return folders;
}

#pragma mark kept folders

/* a file per folder: a header, then the rows of the newest chats as the parser made them. the rows hold no pointers, so a file of another build is told by the size of a row */
#define FOLDER_CACHE_MAGIC 0x45464443u
#define FOLDER_CACHE_VERSION 1u
#define FOLDER_CACHE_ROWS_MAX 300u

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t row_size;
    uint32_t count;
    uint64_t signature;
    int64_t saved;
} folder_cache_header;

/* what decides who is in the folder: a change of any of it makes the kept chats wrong */
static uint64_t folder_signature(ExteriaChatFolder *folder) {
    uint64_t hash = 1469598103934665603ull;
    uint32_t head[2] = {(uint32_t)folder.folderId, folder.flags};
    NSData *parts[3] = {folder.included, folder.excluded, folder.pinned};
    const uint8_t *bytes = (const uint8_t *)head;
    for (size_t i = 0; i < sizeof(head); ++i) hash = (hash ^ bytes[i]) * 1099511628211ull;
    for (int k = 0; k < 3; ++k) {
        uint64_t length = parts[k].length;
        const uint8_t *size = (const uint8_t *)&length;
        for (size_t i = 0; i < sizeof(length); ++i) hash = (hash ^ size[i]) * 1099511628211ull;
        const uint8_t *data = parts[k].bytes;
        for (NSUInteger i = 0; i < parts[k].length; ++i) hash = (hash ^ data[i]) * 1099511628211ull;
    }
    return hash;
}

static NSString *folder_cache_path(ExteriaSession *session, int32_t folderId) {
    return [session.directory stringByAppendingPathComponent:[NSString stringWithFormat:@"folder-%d.dialogs", (int)folderId]];
}

static BOOL folder_cache_header_valid(const folder_cache_header *header, ExteriaChatFolder *folder) {
    return header->magic == FOLDER_CACHE_MAGIC && header->version == FOLDER_CACHE_VERSION && header->row_size == sizeof(exteria_dialog_row) &&
           header->count <= FOLDER_CACHE_ROWS_MAX && header->signature == folder_signature(folder);
}

static void folder_cache_store(ExteriaSession *session, ExteriaChatFolder *folder, NSArray *rows) {
    NSString *path = folder_cache_path(session, folder.folderId);
    uint64_t signature = folder_signature(folder);
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(folder_cache_header)];
    NSUInteger count = MIN(rows.count, (NSUInteger)FOLDER_CACHE_ROWS_MAX);
    for (NSUInteger i = 0; i < count; ++i) [data appendData:[rows objectAtIndex:i]];
    folder_cache_header header = {FOLDER_CACHE_MAGIC, FOLDER_CACHE_VERSION, (uint32_t)sizeof(exteria_dialog_row), (uint32_t)count, signature,
                                  (int64_t)[[NSDate date] timeIntervalSince1970]};
    [data replaceBytesInRange:NSMakeRange(0, sizeof(header)) withBytes:&header];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            if (![data writeToFile:path atomically:YES]) {
                NSLog(@"exteria: the chats of folder %d were not kept", (int)folder.folderId);
                return;
            }
            NSError *error = nil;
            if (![[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:0600] forKey:NSFilePosixPermissions]
                                                  ofItemAtPath:path error:&error])
                NSLog(@"exteria: permissions of the kept chats of folder %d were not set: %@", (int)folder.folderId, error);
        }
    });
}

/* custom folders need the older pages too, since a category can have no chats in the newest hundred */
@interface ExteriaFolderDialogsLoad : NSObject <ExteriaFolderDialogRequest> {
    ExteriaSession *_session;
    ExteriaChatFolder *_filter;
    ExteriaListCompletion _completion;
    void (^_progress)(NSArray *);
    NSMutableDictionary *_dialogs;
    /* the parsed row of each chat in _dialogs, for the copy that is kept on disk */
    NSMutableDictionary *_rows;
    exteria_peer_ref _offset;
    int32_t _offsetId;
    int32_t _offsetDate;
    int32_t _archive;
    NSUInteger _pages;
    NSData *_extraPeers;
    NSUInteger _extraAt;
    BOOL _cancelled;
    BOOL _finished;
}
- (id)initWithSession:(ExteriaSession *)session folder:(ExteriaChatFolder *)folder progress:(void (^)(NSArray *))progress completion:(ExteriaListCompletion)completion;
- (void)advance;
@end

@implementation ExteriaFolderDialogsLoad
- (id)initWithSession:(ExteriaSession *)session folder:(ExteriaChatFolder *)folder progress:(void (^)(NSArray *))progress completion:(ExteriaListCompletion)completion {
    self = [super init];
    if (self) {
        _session = [session retain];
        _filter = [folder copy];
        _completion = [completion copy];
        _progress = [progress copy];
        _dialogs = [[NSMutableDictionary alloc] init];
        _rows = [[NSMutableDictionary alloc] init];
        NSMutableData *extra = [NSMutableData dataWithData:folder.included];
        [extra appendData:folder.pinned];
        _extraPeers = [extra copy];
    }
    return self;
}
- (void)dealloc {
    [_session release];
    [_filter release];
    [_completion release];
    [_progress release];
    [_dialogs release];
    [_rows release];
    [_extraPeers release];
    [super dealloc];
}
- (void)cancel {
    @synchronized(self) {
        _cancelled = YES;
    }
}
- (BOOL)cancelled {
    @synchronized(self) {
        return _cancelled;
    }
}
- (NSArray *)sortedDialogs {
    return [[_dialogs allValues] sortedArrayUsingComparator:^NSComparisonResult(ExteriaDialog *a, ExteriaDialog *b) {
        NSUInteger ai = [_filter pinIndexForDialog:a], bi = [_filter pinIndexForDialog:b];
        if (ai != bi) return ai < bi ? NSOrderedAscending : NSOrderedDescending;
        if (a.date != b.date) return a.date > b.date ? NSOrderedAscending : NSOrderedDescending;
        if (a.peerKind != b.peerKind) return a.peerKind < b.peerKind ? NSOrderedAscending : NSOrderedDescending;
        return a.peerId < b.peerId ? NSOrderedAscending : (a.peerId > b.peerId ? NSOrderedDescending : NSOrderedSame);
    }];
}
- (void)reportProgress {
    if (!_progress || !_dialogs.count) return;
    NSArray *items = [self sortedDialogs];
    [_session deliverMain:^{ if (![self cancelled] && _progress) _progress(items); }];
}
- (void)finish:(NSString *)errorName {
    @synchronized(self) {
        if (_finished)
            return;
        _finished = YES;
    }
    NSArray *result = nil;
    if (!errorName) {
        result = [self sortedDialogs];
        /* only a scan that reached the end is kept, so a half list never stands in for the folder */
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:MIN(result.count, (NSUInteger)FOLDER_CACHE_ROWS_MAX)];
        for (ExteriaDialog *dialog in result) {
            NSData *row = [_rows objectForKey:[NSString stringWithFormat:@"%d/%lld", dialog.peerKind, dialog.peerId]];
            if (row) [kept addObject:row];
            if (kept.count == FOLDER_CACHE_ROWS_MAX) break;
        }
        folder_cache_store(_session, _filter, kept);
    }
    ExteriaListCompletion done = [_completion copy];
    [_completion release];
    _completion = nil;
    [_session deliverMain:^{
        if (done)
            done(result, errorName);
        [done release];
    }];
}
/* explicit members can be left chats or have no recent history, so getDialogs alone cannot supply them */
- (void)loadIncludedPeers {
    if ([self cancelled]) {
        [self finish:@"CANCELLED"];
        return;
    }
    NSString *wait = [_session folderFloodError];
    if (wait) { [self finish:wait]; return; }
    const exteria_peer_ref *peers = _extraPeers.bytes;
    NSUInteger count = _extraPeers.length / sizeof(*peers);
    NSMutableData *batch = [NSMutableData data];
    NSMutableSet *keys = [NSMutableSet set];
    while (_extraAt < count && batch.length / sizeof(*peers) < 100) {
        exteria_peer_ref peer = peers[_extraAt++];
        NSString *key = [NSString stringWithFormat:@"%d/%lld", peer.self ? 1 : peer.kind, peer.self ? [_session workerAccount] : peer.id];
        if ([_dialogs objectForKey:key] || [keys containsObject:key])
            continue;
        [keys addObject:key];
        [batch appendBytes:&peer length:sizeof(peer)];
    }
    if (!batch.length) {
        [self finish:nil];
        return;
    }
    [_session
        invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_peer_dialogs_request(arena, batch.bytes, batch.length / sizeof(exteria_peer_ref), request);
        }
        handler:^(const exteria_mt_rpc_result *result) {
            if ([self cancelled]) {
                [self finish:@"CANCELLED"];
                return;
            }
            if (result->status != EXTERIA_OK) {
                [_session noteRpcError:ExteriaRpcErrorName(result)];
                NSString *error = ExteriaDownloadErrorName(result);
                [_session rememberFolderFloodError:error];
                [self finish:error];
                return;
            }
            exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX, sizeof(*rows));
            size_t found = 0;
            exteria_status status = rows ? exteria_dialogs_parse(result->value, [_session workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970], rows,
                                                                 EXTERIA_DIALOGS_MAX, &found)
                                         : EXTERIA_E_NOMEM;
            if (status != EXTERIA_OK) {
                free(rows);
                [self finish:@"MALFORMED"];
                return;
            }
            [_session noteDraftsOfDialogsAnswer:result->value complete:NO];
            for (size_t i = 0; i < found; ++i) {
                ExteriaDialog *dialog = [_filter dialogWithRow:&rows[i]];
                if ([_filter containsDialog:dialog]) {
                    NSString *key = [NSString stringWithFormat:@"%d/%lld", dialog.peerKind, dialog.peerId];
                    [_dialogs setObject:dialog forKey:key];
                    [_rows setObject:[NSData dataWithBytes:&rows[i] length:sizeof(rows[i])] forKey:key];
                }
            }
            free(rows);
            [self reportProgress];
            if (_dialogs.count > 5000) {
                [self finish:@"FOLDER_HISTORY_LIMIT"];
                return;
            }
            [self loadIncludedPeers];
        }];
}

- (void)advance {
    if ([self cancelled]) {
        [self finish:@"CANCELLED"];
        return;
    }
    NSString *wait = [_session folderFloodError];
    if (wait) { [self finish:wait]; return; }
    if (!exteria_folder_scans_dialogs(_filter.flags, _archive)) {
        [self loadIncludedPeers];
        return;
    }
    if (++_pages > 200) {
        [self finish:@"FOLDER_HISTORY_LIMIT"];
        return;
    }
    [_session
        invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_tl_value *call = exteria_tl_new_obj(arena, "messages.getDialogs");
            exteria_tl_value *peer = NULL;
            if (!call)
                return EXTERIA_E_NOMEM;
            exteria_status status = EXTERIA_OK;
            if (_offsetId)
                status = exteria_input_peer(arena, &_offset, &peer);
            else {
                peer = exteria_tl_new_obj(arena, "inputPeerEmpty");
                if (!peer)
                    status = EXTERIA_E_NOMEM;
            }
            if (status == EXTERIA_OK)
                status = exteria_tl_set(call, "offset_peer", peer);
            if (status == EXTERIA_OK)
                status = exteria_tl_set_i32(arena, call, "offset_id", _offsetId);
            if (status == EXTERIA_OK)
                status = exteria_tl_set_i32(arena, call, "offset_date", _offsetDate);
            if (status == EXTERIA_OK)
                status = exteria_tl_set_i32(arena, call, "folder_id", _archive);
            if (status == EXTERIA_OK)
                status = exteria_tl_set_i32(arena, call, "limit", 100);
            if (status == EXTERIA_OK)
                status = exteria_tl_set_i64(arena, call, "hash", 0);
            if (status == EXTERIA_OK && _offsetId)
                status = exteria_tl_set_flag(call, "exclude_pinned");
            *request = status == EXTERIA_OK ? call : NULL;
            return status;
        }
        handler:^(const exteria_mt_rpc_result *result) {
            if ([self cancelled]) {
                [self finish:@"CANCELLED"];
                return;
            }
            if (result->status != EXTERIA_OK) {
                [_session noteRpcError:ExteriaRpcErrorName(result)];
                NSString *error = ExteriaDownloadErrorName(result);
                [_session rememberFolderFloodError:error];
                [self finish:error];
                return;
            }
            exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_dialogs_parse(result->value, [_session workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970], rows,
                                                                 EXTERIA_DIALOGS_MAX, &count)
                                         : EXTERIA_E_NOMEM;
            if (status != EXTERIA_OK) {
                free(rows);
                [self finish:@"MALFORMED"];
                return;
            }
            [_session noteDraftsOfDialogsAnswer:result->value complete:NO];
            exteria_dialog_row last;
            memset(&last, 0, sizeof(last));
            for (size_t i = 0; i < count; ++i) {
                if (rows[i].folder)
                    continue;
                if (rows[i].top_message > 0)
                    last = rows[i];
                ExteriaDialog *dialog = [_filter dialogWithRow:&rows[i]];
                if ([_filter containsDialog:dialog]) {
                    NSString *key = [NSString stringWithFormat:@"%d/%lld", dialog.peerKind, dialog.peerId];
                    [_dialogs setObject:dialog forKey:key];
                    [_rows setObject:[NSData dataWithBytes:&rows[i] length:sizeof(rows[i])] forKey:key];
                }
            }
            free(rows);
            [self reportProgress];
            if (_dialogs.count > 5000) {
                [self finish:@"FOLDER_HISTORY_LIMIT"];
                return;
            }
            const exteria_tl_value *list = exteria_tl_get(result->value, "dialogs");
            /* a slice that is shorter than the hundred asked for can still have older pages behind it (the server cuts a page that holds dialogs it cannot show), so the
               pages go on until one comes back empty or is the one before it; stopping at a short page left the folder without its older chats */
            BOOL more = exteria_tl_is(result->value, EXTERIA_TL_ID_messages_dialogsSlice) && list && list->kind == EXTERIA_TL_V_VEC && list->u.vec.count > 0;
            if (more) {
                if (!last.top_message ||
                    (last.peer_kind == _offset.kind && last.peer_id == _offset.id && last.top_message == _offsetId && last.date == _offsetDate)) {
                    [self finish:@"MALFORMED"];
                    return;
                }
                _offset.kind = last.peer_kind;
                _offset.id = last.peer_id;
                _offset.access_hash = last.peer_hash;
                _offset.self = last.saved;
                _offsetId = last.top_message;
                _offsetDate = last.date;
                [self advance];
            } else if (!_archive && exteria_folder_scans_dialogs(_filter.flags, 1)) {
                _archive = 1;
                memset(&_offset, 0, sizeof(_offset));
                _offsetId = 0;
                _offsetDate = 0;
                [self advance];
            } else
                [self loadIncludedPeers];
        }];
}
@end

@implementation ExteriaSession (Folders)
- (void)refreshChangedChatFolders {
    [self loadChatFoldersWithCompletion:^(NSArray *folders, NSString *errorName) {
        (void)folders;
        if (errorName)
            NSLog(@"exteria: changed chat folders did not load: %@", errorName);
    }];
}

- (NSArray *)chatFolders {
    return _chatFolders ? _chatFolders : [NSArray array];
}

- (void)loadSuggestedChatFoldersWithCompletion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "messages.getSuggestedDialogFilters");
        return *request ? EXTERIA_OK : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *suggested = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else if (result->value && result->value->kind == EXTERIA_TL_V_VEC && result->value->u.vec.count <= EXTERIA_FOLDERS_MAX) {
            suggested = [NSMutableArray array];
            for (uint32_t i = 0; i < result->value->u.vec.count; ++i) {
                const exteria_tl_value *item = result->value->u.vec.items[i];
                ExteriaChatFolder *folder = [ExteriaChatFolder folderWithValue:exteria_tl_get(item, "filter")];
                if (!folder) continue;
                const uint8_t *text = NULL;
                size_t length = 0;
                NSString *info = exteria_tl_get_bytes(item, "description", &text, &length) == EXTERIA_OK && text ? [[[NSString alloc] initWithBytes:text length:length encoding:NSUTF8StringEncoding] autorelease] : @"";
                [suggested addObject:[[[ExteriaSuggestedFolder alloc] initWithFolder:folder info:info ? info : @""] autorelease]];
            }
        } else {
            NSLog(@"exteria: messages.getSuggestedDialogFilters answer rejected");
            error = @"MALFORMED";
        }
        [self finishLoad:suggested error:error completion:done];
        [done release];
    }];
}

- (void)loadChatFoldersWithCompletion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    NSUInteger generation = ++_chatFolderGeneration;
    NSString *path = [self.directory stringByAppendingPathComponent:@"chat-folders.tl"];
    [self
        invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
            if (attributes && [attributes fileSize] <= 2 * 1024 * 1024) {
                NSData *cached = [NSData dataWithContentsOfFile:path];
                exteria_tl_value *answer = NULL;
                if (cached.length && cached.length <= 2 * 1024 * 1024 &&
                    exteria_tl_decode_all(arena, NULL, EXTERIA_TL_REF_ANY, cached.bytes, cached.length, &answer) == EXTERIA_OK) {
                    NSArray *folders = [[folders_read(answer) copy] autorelease];
                    if (folders)
                        [self deliverMain:^{
                            if (!_chatFolders && generation == _chatFolderGeneration) {
                                _chatFolders = [folders retain];
                                [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatFoldersDidChangeNotification object:self];
                            }
                        }];
                }
            }
            *request = exteria_tl_new_obj(arena, "messages.getDialogFilters");
            return *request ? EXTERIA_OK : EXTERIA_E_NOMEM;
        }
        handler:^(const exteria_mt_rpc_result *result) {
            NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
            NSArray *folders = error ? nil : folders_read(result->value);
            if (!error && !folders)
                error = @"MALFORMED";
            NSData *cacheData = nil;
            if (!error) {
                exteria_writer writer;
                exteria_writer_init(&writer, 2 * 1024 * 1024);
                if (exteria_tl_encode(result->value, &writer, NULL) == EXTERIA_OK) {
                    cacheData = [NSData dataWithBytes:writer.data length:writer.len];
                } else
                    NSLog(@"exteria: chat folders could not be encoded");
                exteria_writer_free(&writer);
            }
            [self noteRpcError:error];
            NSArray *delivered = [[folders copy] autorelease];
            NSString *failure = [[error copy] autorelease];
            [self deliverMain:^{
                if (!failure && generation == _chatFolderGeneration) {
                    [_chatFolders release];
                    _chatFolders = [delivered retain];
                    /* the kept chats of a folder that is gone are not wanted any more */
                    NSMutableSet *present = [NSMutableSet set];
                    for (ExteriaChatFolder *folder in delivered) [present addObject:[NSString stringWithFormat:@"folder-%d.dialogs", (int)folder.folderId]];
                    NSString *directory = self.directory;
                    [self post:^{
                        NSFileManager *files = [NSFileManager defaultManager];
                        for (NSString *name in [files contentsOfDirectoryAtPath:directory error:NULL]) {
                            if (![name hasPrefix:@"folder-"] || ![name hasSuffix:@".dialogs"] || [present containsObject:name]) continue;
                            NSError *removeError = nil;
                            if (![files removeItemAtPath:[directory stringByAppendingPathComponent:name] error:&removeError]) NSLog(@"exteria: kept folder %@ was not removed: %@", name, removeError);
                        }
                    }];
                    if (cacheData)
                        [self post:^{
                            if (![cacheData writeToFile:path atomically:YES])
                                NSLog(@"exteria: chat folders were not saved");
                            else if (![[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:0600]
                                                                                                                forKey:NSFilePosixPermissions]
                                                                       ofItemAtPath:path
                                                                              error:NULL])
                                NSLog(@"exteria: chat folder permissions were not saved");
                        }];
                    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatFoldersDidChangeNotification object:self];
                }
                if (done)
                    done(delivered, failure);
                [done release];
            }];
        }];
}

- (void)writeChatFolder:(ExteriaChatFolder *)folder identifier:(int32_t)identifier completion:(void (^)(NSString *))completion {
    if (_chatFolderSaving) {
        if (completion)
            completion(@"FOLDER_BUSY");
        return;
    }
    _chatFolderSaving = YES;
    void (^done)(NSString *) = [completion copy];
    ExteriaChatFolder *snapshot = [folder copy];
    [self
        invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            *request = NULL;
            if (identifier < 2)
                return EXTERIA_E_ARG;
            exteria_tl_value *call = exteria_tl_new_obj(arena, "messages.updateDialogFilter");
            if (!call)
                return EXTERIA_E_NOMEM;
            exteria_status status = exteria_tl_set_i32(arena, call, "id", identifier);
            exteria_tl_value *filter = NULL;
            if (snapshot && status == EXTERIA_OK)
                status = [snapshot buildInArena:arena value:&filter];
            if (filter && status == EXTERIA_OK)
                status = exteria_tl_set(call, "filter", filter);
            if (status == EXTERIA_OK)
                *request = call;
            return status;
        }
        handler:^(const exteria_mt_rpc_result *result) {
            NSString *error =
                result->status == EXTERIA_OK ? (exteria_tl_is(result->value, EXTERIA_TL_ID_boolTrue) ? nil : @"REFUSED") : ExteriaRpcErrorName(result);
            [self noteRpcError:error];
            NSString *failure = [[error copy] autorelease];
            [self deliverMain:^{
                if (failure) {
                    _chatFolderSaving = NO;
                    if (done)
                        done(failure);
                    [done release];
                } else
                    [self loadChatFoldersWithCompletion:^(NSArray *folders, NSString *refreshError) {
                        (void)folders;
                        _chatFolderSaving = NO;
                        if (done)
                            done(refreshError);
                        [done release];
                    }];
            }];
            [snapshot release];
        }];
}
- (void)saveChatFolder:(ExteriaChatFolder *)folder completion:(void (^)(NSString *))completion {
    [self writeChatFolder:folder identifier:folder.folderId completion:completion];
}
- (void)setDialogs:(NSArray *)dialogs pinned:(BOOL)pinned inChatFolder:(ExteriaChatFolder *)folder completion:(void (^)(NSString *))completion {
    ExteriaChatFolder *updated = [[folder copy] autorelease];
    NSMutableData *peers = [NSMutableData data];
    for (ExteriaDialog *dialog in dialogs)
        if (pinned) {
            exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
            [peers appendBytes:&peer length:sizeof(peer)];
        }
    const exteria_peer_ref *old = folder.pinned.bytes;
    for (NSUInteger i = 0; i < folder.pinned.length / sizeof(*old); ++i) {
        BOOL changed = NO;
        for (ExteriaDialog *dialog in dialogs)
            if ((old[i].self && dialog.saved) || (!old[i].self && old[i].kind == dialog.peerKind && old[i].id == dialog.peerId))
                changed = YES;
        if (!changed)
            [peers appendBytes:&old[i] length:sizeof(*old)];
    }
    if (peers.length / sizeof(exteria_peer_ref) > EXTERIA_FOLDER_PEERS_MAX || !folder.folderId) {
        if (completion)
            completion(@"FOLDER_PIN_LIMIT");
        return;
    }
    updated.pinned = peers;
    [self saveChatFolder:updated completion:completion];
}

- (void)deleteChatFolder:(int32_t)folderId completion:(void (^)(NSString *))completion {
    [self writeChatFolder:nil identifier:folderId completion:completion];
}
- (void)orderChatFolders:(NSArray *)folders completion:(void (^)(NSString *))completion {
    if (_chatFolderSaving) {
        if (completion)
            completion(@"FOLDER_BUSY");
        return;
    }
    _chatFolderSaving = YES;
    void (^done)(NSString *) = [completion copy];
    NSMutableArray *ids = [NSMutableArray array];
    for (ExteriaChatFolder *folder in folders)
        [ids addObject:[NSNumber numberWithInt:folder.folderId]];
    [self
        invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            if (!ids.count || ids.count > EXTERIA_FOLDERS_MAX)
                return EXTERIA_E_ARG;
            int32_t values[EXTERIA_FOLDERS_MAX];
            for (NSUInteger i = 0; i < ids.count; ++i)
                values[i] = [[ids objectAtIndex:i] intValue];
            *request = exteria_tl_new_obj(arena, "messages.updateDialogFiltersOrder");
            return *request ? exteria_tl_set_i32_vec(arena, *request, "order", values, (uint32_t)ids.count) : EXTERIA_E_NOMEM;
        }
        handler:^(const exteria_mt_rpc_result *result) {
            NSString *error =
                result->status == EXTERIA_OK ? (exteria_tl_is(result->value, EXTERIA_TL_ID_boolTrue) ? nil : @"REFUSED") : ExteriaRpcErrorName(result);
            [self noteRpcError:error];
            NSString *failure = [[error copy] autorelease];
            [self deliverMain:^{
                if (failure) {
                    _chatFolderSaving = NO;
                    if (done)
                        done(failure);
                    [done release];
                } else
                    [self loadChatFoldersWithCompletion:^(NSArray *updated, NSString *refreshError) {
                        (void)updated;
                        _chatFolderSaving = NO;
                        if (done)
                            done(refreshError);
                        [done release];
                    }];
            }];
        }];
}

- (NSTimeInterval)keptAgeOfChatFolder:(ExteriaChatFolder *)folder {
    if (!folder.folderId) return -1;
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:folder_cache_path(self, folder.folderId)];
    NSData *head = [file readDataOfLength:sizeof(folder_cache_header)];
    [file closeFile];
    if (head.length != sizeof(folder_cache_header)) return -1;
    folder_cache_header header;
    memcpy(&header, head.bytes, sizeof(header));
    if (!folder_cache_header_valid(&header, folder)) return -1;
    NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - (NSTimeInterval)header.saved;
    return age < 0 ? 0 : age;
}

- (void)loadKeptDialogsForChatFolder:(ExteriaChatFolder *)folder completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    ExteriaChatFolder *rules = [folder copy];
    NSString *path = folder_cache_path(self, folder.folderId);
    [self post:^{
        NSArray *dialogs = nil;
        NSData *data = rules.folderId ? [NSData dataWithContentsOfFile:path] : nil;
        folder_cache_header header;
        if (data.length >= sizeof(header)) {
            memcpy(&header, data.bytes, sizeof(header));
            if (folder_cache_header_valid(&header, rules) && data.length == sizeof(header) + (size_t)header.count * header.row_size) {
                NSMutableArray *list = [NSMutableArray arrayWithCapacity:header.count];
                for (uint32_t i = 0; i < header.count; ++i) {
                    exteria_dialog_row row;
                    memcpy(&row, (const uint8_t *)data.bytes + sizeof(header) + (size_t)i * header.row_size, sizeof(row));
                    ExteriaDialog *dialog = [rules dialogWithRow:&row];
                    if ([rules containsDialog:dialog]) [list addObject:dialog];
                }
                /* the same order as a scan gives */
                dialogs = [list sortedArrayUsingComparator:^NSComparisonResult(ExteriaDialog *a, ExteriaDialog *b) {
                    NSUInteger ai = [rules pinIndexForDialog:a], bi = [rules pinIndexForDialog:b];
                    if (ai != bi) return ai < bi ? NSOrderedAscending : NSOrderedDescending;
                    if (a.date != b.date) return a.date > b.date ? NSOrderedAscending : NSOrderedDescending;
                    if (a.peerKind != b.peerKind) return a.peerKind < b.peerKind ? NSOrderedAscending : NSOrderedDescending;
                    return a.peerId < b.peerId ? NSOrderedAscending : (a.peerId > b.peerId ? NSOrderedDescending : NSOrderedSame);
                }];
            } else if (data.length) {
                NSLog(@"exteria: the kept chats of folder %d are of another build or other rules", (int)rules.folderId);
            }
        }
        /* nothing kept is not an error, the screen waits for the scan */
        [self finishLoad:dialogs error:nil completion:done];
        [done release];
    }];
    [rules release];
}

- (id<ExteriaFolderDialogRequest>)loadDialogsForChatFolder:(ExteriaChatFolder *)folder completion:(ExteriaListCompletion)completion {
    return [self loadDialogsForChatFolder:folder progress:nil completion:completion];
}

- (id<ExteriaFolderDialogRequest>)loadDialogsForChatFolder:(ExteriaChatFolder *)folder progress:(void (^)(NSArray *))progress completion:(ExteriaListCompletion)completion {
    if (!folder.folderId) {
        [self loadDialogsInFolder:0 completion:completion];
        return nil;
    }
    NSString *wait = [self folderFloodError];
    if (wait) { if (completion) completion(nil, wait); return nil; }
    ExteriaFolderDialogsLoad *load = [[[ExteriaFolderDialogsLoad alloc] initWithSession:self folder:folder progress:progress completion:completion] autorelease];
    [load advance];
    return load;
}
@end
