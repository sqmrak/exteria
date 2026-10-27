#import "exteria_session_drafts.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

/* worker only: collects what the core walk reports as board entries; a draft that cannot be read is left out, so it neither shows nor erases one */
static exteria_status ExteriaCollectDraft(void *ctx, int32_t kind, int64_t peer, int32_t top, const exteria_tl_value *body) {
    NSMutableArray *entries = ctx;
    id draft = [NSNull null];
    if (body) {
        exteria_draft *row = malloc(sizeof(*row));
        if (!row) return EXTERIA_E_NOMEM;
        exteria_status status = exteria_draft_read(body, top, row);
        if (status == EXTERIA_OK) {
            ExteriaDraft *read = [ExteriaDraft draftWithRow:row];
            if (read) draft = read;
        }
        free(row);
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: a draft of chat %lld was not read: %s", (long long)peer, exteria_status_name(status));
            return EXTERIA_OK;
        }
    }
    [entries addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:kind], [NSNumber numberWithLongLong:peer], [NSNumber numberWithInt:top], draft, nil]];
    return EXTERIA_OK;
}

@implementation ExteriaSession (Drafts)

- (void)saveDraftText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo noWebpage:(BOOL)noWebpage forDialog:(ExteriaDialog *)dialog {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t kind = dialog.peerKind, top = dialog.topicId;
    long long chat = dialog.peerId;
    NSString *body = [text copy];
    ExteriaDraft *draft = [[[ExteriaDraft alloc] initWithText:body entities:entities replyTo:replyTo noWebpage:noWebpage
                                                          date:(int32_t)[[NSDate date] timeIntervalSince1970]] autorelease];
    [self.drafts setLocalDraft:draft kind:kind peer:chat top:top];
    NSMutableData *strings = nil;
    size_t count = 0;
    NSMutableData *packed = ExteriaPackSendEntities(entities, &strings, &count);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        (void)strings;
        return exteria_draft_save_request(arena, &peer, body.UTF8String, packed.bytes, count, replyTo, noWebpage, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            if (delivered) NSLog(@"exteria: saving the draft of chat %lld failed: %@", chat, delivered);
            [self.drafts noteSavedKind:kind peer:chat top:top];
        }];
    }];
    [body release];
}

- (void)noteDraftsOfDialogsAnswer:(const exteria_tl_value *)answer complete:(BOOL)complete {
    NSMutableArray *entries = [NSMutableArray array];
    exteria_status status = exteria_draft_dialogs_visit(answer, ExteriaCollectDraft, entries);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: the drafts of the chat list were not read: %s", exteria_status_name(status));
        return;
    }
    [self deliverMain:^{ [self.drafts noteListed:entries complete:complete]; }];
}

- (void)noteDraftsOfTopicsAnswer:(const exteria_tl_value *)answer forum:(ExteriaDialog *)forum {
    NSMutableArray *entries = [NSMutableArray array];
    exteria_status status = exteria_draft_topics_visit(answer, forum.peerKind, forum.peerId, ExteriaCollectDraft, entries);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: the drafts of the topics were not read: %s", exteria_status_name(status));
        return;
    }
    [self deliverMain:^{ [self.drafts noteListed:entries complete:YES]; }];
}

- (void)noteDraftUpdate:(const exteria_tl_value *)update {
    int32_t kind = 0, top = 0;
    int64_t peer = 0;
    const exteria_tl_value *body = NULL;
    exteria_status status = exteria_draft_update_read(update, &kind, &peer, &top, &body);
    if (status == EXTERIA_E_UNSUPPORTED) return;
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: a draft update was rejected: %s", exteria_status_name(status));
        return;
    }
    exteria_draft *row = malloc(sizeof(*row));
    if (!row) return;
    status = exteria_draft_read(body, top, row);
    ExteriaDraft *draft = status == EXTERIA_OK ? [ExteriaDraft draftWithRow:row] : nil;
    free(row);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: the draft of chat %lld was not read: %s", (long long)peer, exteria_status_name(status));
        return;
    }
    [self deliverMain:^{ [self.drafts noteAccountDraft:draft kind:kind peer:peer top:top]; }];
}

- (void)requestAllDraftsOnce {
    if (_draftsRequested) return;
    _draftsRequested = YES;
    [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "messages.getAllDrafts");
        return *request ? EXTERIA_OK : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        /* the drafts arrive as the updates of the answer, which the client delivers to noteDraftUpdate */
        if (result->status == EXTERIA_OK) return;
        NSString *error = ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        _draftsRequested = NO;
        NSLog(@"exteria: asking for the drafts failed: %@", error);
    }];
}

@end
