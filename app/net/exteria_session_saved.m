#import "exteria_session_saved.h"

#import "exteria_chat_settings.h"
#import "exteria_session_internal.h"

#include "exteria_messages.h"
#include "exteria_updates.h"

uint32_t ExteriaSavingMask(void) {
    uint32_t mask = 0;
    if (ExteriaChatFlagGet(ExteriaChatFlagAyuSaveDeleted)) {
        mask |= EXTERIA_KEEP_DELETED;
        if (ExteriaChatFlagGet(ExteriaChatFlagAyuDeletedPrivate)) mask |= EXTERIA_KEEP_PRIVATE;
        if (ExteriaChatFlagGet(ExteriaChatFlagAyuDeletedGroups)) mask |= EXTERIA_KEEP_GROUPS;
        if (ExteriaChatFlagGet(ExteriaChatFlagAyuDeletedChannels)) mask |= EXTERIA_KEEP_CHANNELS;
        if (ExteriaChatFlagGet(ExteriaChatFlagAyuDeletedBots)) mask |= EXTERIA_KEEP_BOTS;
    }
    if (ExteriaChatFlagGet(ExteriaChatFlagAyuSaveEdits)) mask |= EXTERIA_KEEP_EDITS;
    return mask;
}

typedef struct {
    NSMutableArray *messages;
    BOOL deleted;
    int32_t low, high;
    int64_t divisor;        /* the id of a version is the id of its message times this plus a number */
    int32_t only;           /* a message whose versions are wanted, or zero */
} ExteriaSavedRead;

static exteria_status ExteriaCollectSaved(void *ctx, int64_t id, const exteria_tl_value *value) {
    ExteriaSavedRead *read = ctx;
    int64_t messageId = id / read->divisor;
    if (read->only ? messageId != read->only : (messageId < read->low || messageId > read->high)) return EXTERIA_OK;
    exteria_message_row *row = calloc(1, sizeof(*row));
    if (!row) return EXTERIA_E_NOMEM;
    if (exteria_message_read(value, row) == EXTERIA_OK) {
        ExteriaMessage *message = [ExteriaMessage messageWithRow:row];
        message.deletedLocally = read->deleted;
        if (message) [read->messages addObject:message];
    }
    free(row);
    return EXTERIA_OK;
}

@implementation ExteriaSession (Saved)

- (void)setSavingSettingsFromDefaults {
    uint32_t mask = ExteriaSavingMask();
    [self post:^{
        if ([self workerStore]) [self setKeepMask:mask];
    }];
}

- (void)countSavedMessages:(void (^)(NSInteger, NSString *))completion {
    void (^done)(NSInteger, NSString *) = [completion copy];
    [self post:^{
        exteria_store *store = [self workerStore];
        int64_t deleted = 0, versions = 0;
        exteria_status status = store ? exteria_store_count(store, EXTERIA_RECORD_DELETED_MESSAGE, &deleted) : EXTERIA_E_STATE;
        if (status == EXTERIA_OK) status = exteria_store_count(store, EXTERIA_RECORD_MESSAGE_EDIT, &versions);
        NSInteger total = (NSInteger)(deleted + versions);
        NSString *error = status == EXTERIA_OK ? nil : @"STORAGE";
        [self deliverMain:^{ done(total, error); [done release]; }];
    }];
}

- (void)deleteSavedMessage:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer peer = {dialog.peerKind, dialog.peerId};
    [self post:^{
        exteria_store *store = [self workerStore];
        exteria_status status = store && messageId > 0 ? exteria_store_delete(store, EXTERIA_RECORD_DELETED_MESSAGE, peer, messageId) : EXTERIA_E_ARG;
        if (status == EXTERIA_OK) [self storeChanged];
        NSString *error = status == EXTERIA_OK ? nil : @"STORAGE";
        [self deliverMain:^{ if (done) done(error); [done release]; }];
    }];
}

- (void)clearSavedMessages:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self post:^{
        exteria_store *store = [self workerStore];
        exteria_status status = store ? exteria_store_clear(store, EXTERIA_RECORD_DELETED_MESSAGE) : EXTERIA_E_STATE;
        if (status == EXTERIA_OK) status = exteria_store_clear(store, EXTERIA_RECORD_MESSAGE_EDIT);
        if (status == EXTERIA_OK) [self storeChanged];
        NSString *error = status == EXTERIA_OK ? nil : @"STORAGE";
        [self deliverMain:^{ done(error); [done release]; }];
    }];
}

NSMutableArray *ExteriaSavedDeletedOfPeer(exteria_store *store, exteria_peer peer, int32_t low, int32_t high) {
    NSMutableArray *found = [NSMutableArray array];
    ExteriaSavedRead read = {found, YES, low, high, 1, 0};
    if (store && exteria_store_page(store, EXTERIA_RECORD_DELETED_MESSAGE, peer, (int64_t)high + 1, 200, ExteriaCollectSaved, &read) != EXTERIA_OK) [found removeAllObjects];
    return found;
}

- (void)loadSavedDeletedOfDialog:(ExteriaDialog *)dialog from:(int32_t)low to:(int32_t)high completion:(void (^)(NSArray *))completion {
    void (^done)(NSArray *) = [completion copy];
    exteria_peer peer = {dialog.peerKind, dialog.peerId};
    [self post:^{
        NSArray *delivered = [[ExteriaSavedDeletedOfPeer([self workerStore], peer, low, high) copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)loadEditVersionsOfMessage:(int32_t)messageId dialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *))completion {
    void (^done)(NSArray *) = [completion copy];
    exteria_peer peer = {dialog.peerKind, dialog.peerId};
    [self post:^{
        exteria_store *store = [self workerStore];
        NSMutableArray *found = [NSMutableArray array];
        ExteriaSavedRead read = {found, NO, 0, 0, EXTERIA_EDIT_VERSIONS, messageId};
        int64_t before = ((int64_t)messageId + 1) * EXTERIA_EDIT_VERSIONS;
        if (store && exteria_store_page(store, EXTERIA_RECORD_MESSAGE_EDIT, peer, before, 100, ExteriaCollectSaved, &read) != EXTERIA_OK) [found removeAllObjects];
        /* the page runs from the newest version to the oldest */
        NSArray *delivered = [[[found reverseObjectEnumerator] allObjects] copy];
        [self deliverMain:^{ done([delivered autorelease]); [done release]; }];
    }];
}

@end
