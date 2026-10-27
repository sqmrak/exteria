#import "exteria_session_internal.h"

#import "exteria_chat_settings.h"
#import "exteria_rpc.h"
#import "exteria_story.h"

@implementation ExteriaSession (Stories)

- (void)loadStoryPeers:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_all_request(arena, 0, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *peers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_story_peer *rows = calloc(EXTERIA_STORY_PEERS_MAX, sizeof(*rows));
            size_t count = 0;
            int more = 0;
            exteria_status status = rows ? exteria_story_peers_parse(result->value, [self workerAccount], rows, EXTERIA_STORY_PEERS_MAX,
                                                                      &count, &more) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK || status == EXTERIA_E_NOTFOUND) {
                peers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [peers addObject:[ExteriaStoryPeer peerWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: stories.getAllStories answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:peers error:error completion:done];
        [done release];
    }];
}

/* worker only: replaces the stories the server sent as bare headers with their content */
- (void)completeSkipped:(NSMutableArray *)rows peer:(exteria_peer_ref)peer then:(void (^)(NSString *error))then {
    NSMutableData *ids = [NSMutableData data];
    for (NSValue *value in rows) {
        exteria_story_row row;
        [value getValue:&row];
        if (row.skipped) {
            int32_t id = row.id;
            [ids appendBytes:&id length:sizeof(id)];
        }
    }
    size_t wanted = ids.length / sizeof(int32_t);
    if (!wanted) { then(nil); return; }
    [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_ids_request(arena, &peer, ids.bytes, wanted, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) { then(ExteriaRpcErrorName(result)); return; }
        exteria_story_row *fresh = calloc(EXTERIA_STORIES_MAX, sizeof(*fresh));
        size_t count = 0;
        exteria_status status = fresh ? exteria_stories_parse(result->value, fresh, EXTERIA_STORIES_MAX, &count) : EXTERIA_E_NOMEM;
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: stories.getStoriesByID answer rejected: %s", exteria_status_name(status));
            free(fresh);
            then(@"INTERNAL");
            return;
        }
        for (NSUInteger i = 0; i < rows.count; ++i) {
            exteria_story_row row;
            [[rows objectAtIndex:i] getValue:&row];
            if (!row.skipped) continue;
            BOOL replaced = NO;
            for (size_t j = 0; j < count; ++j) {
                if (fresh[j].id != row.id || fresh[j].skipped) continue;
                [rows replaceObjectAtIndex:i withObject:[NSValue valueWithBytes:&fresh[j] objCType:@encode(exteria_story_row)]];
                replaced = YES;
                break;
            }
            /* a story that stays a header has nothing to show, so it drops out */
            if (!replaced) {
                [rows removeObjectAtIndex:i];
                --i;
            }
        }
        free(fresh);
        then(nil);
    }];
}

- (void)loadStoriesOfDialog:(ExteriaDialog *)dialog completion:(ExteriaStoriesCompletion)completion {
    ExteriaStoriesCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_peer_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        void (^fail)(NSString *) = ^(NSString *error) {
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, nil, delivered); [done release]; }];
        };
        if (result->status != EXTERIA_OK) { fail(ExteriaRpcErrorName(result)); return; }
        exteria_story_row *rows = calloc(EXTERIA_STORIES_MAX, sizeof(*rows));
        exteria_story_peer owner;
        size_t count = 0;
        exteria_status status = rows ? exteria_story_peer_parse(result->value, [self workerAccount], &owner, rows, EXTERIA_STORIES_MAX,
                                                                &count) : EXTERIA_E_NOMEM;
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: stories.getPeerStories answer rejected: %s", exteria_status_name(status));
            free(rows);
            fail(@"INTERNAL");
            return;
        }
        NSMutableArray *packed = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) [packed addObject:[NSValue valueWithBytes:&rows[i] objCType:@encode(exteria_story_row)]];
        free(rows);
        [self completeSkipped:packed peer:peer then:^(NSString *error) {
            if (error) { fail(error); return; }
            NSMutableArray *stories = [NSMutableArray arrayWithCapacity:packed.count];
            for (NSValue *value in packed) {
                exteria_story_row row;
                [value getValue:&row];
                [stories addObject:[ExteriaStory storyWithRow:&row]];
            }
            ExteriaStoryPeer *ring = [ExteriaStoryPeer peerWithRow:&owner];
            [self deliverMain:^{ done(ring, stories, nil); [done release]; }];
        }];
    }];
}

- (void)markStoriesSeenOfDialog:(ExteriaDialog *)dialog upTo:(int32_t)storyId {
    /* ghost mode: the story is looked at and its owner is not told */
    if (ExteriaChatFlagGet(ExteriaChatFlagGhostNoStories)) return;
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_read_request(arena, &peer, storyId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) {
            NSString *error = ExteriaRpcErrorName(result);
            NSLog(@"exteria: stories.readStories failed: %@", error);
            [self noteRpcError:error];
        }
    }];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_views_request(arena, &peer, &storyId, 1, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) {
            NSString *error = ExteriaRpcErrorName(result);
            NSLog(@"exteria: stories.incrementStoryViews failed: %@", error);
            [self noteRpcError:error];
        }
    }];
}

- (void)reactToStory:(int32_t)storyId ofDialog:(ExteriaDialog *)dialog reaction:(ExteriaReaction *)reaction
          completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    BOOL has = reaction != nil;
    exteria_reaction row;
    memset(&row, 0, sizeof(row));
    if (has) row = reaction.row;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_react_request(arena, &peer, storyId, has ? &row : NULL, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        [self deliverMain:^{ done(error); [done release]; }];
    }];
}

- (void)replyToStory:(int32_t)storyId ofDialog:(ExteriaDialog *)dialog text:(NSString *)text randomId:(long long)randomId
          completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_reply_request(arena, &peer, storyId, body.UTF8String, randomId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        [self deliverMain:^{ done(error); [done release]; }];
    }];
    [body release];
}

/* worker only: the stories of a stories.stories answer, as a delivered list */
- (void)deliverStoriesResult:(const exteria_mt_rpc_result *)result completion:(ExteriaListCompletion)done {
    NSMutableArray *stories = nil;
    NSString *error = nil;
    if (result->status != EXTERIA_OK) {
        error = ExteriaRpcErrorName(result);
    } else {
        exteria_story_row *rows = calloc(EXTERIA_STORIES_MAX, sizeof(*rows));
        size_t count = 0;
        exteria_status status = rows ? exteria_stories_parse(result->value, rows, EXTERIA_STORIES_MAX, &count) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) {
            stories = [NSMutableArray arrayWithCapacity:count];
            for (size_t i = 0; i < count; ++i) {
                /* a header without content has nothing to show in a grid */
                if (!rows[i].skipped) [stories addObject:[ExteriaStory storyWithRow:&rows[i]]];
            }
        } else {
            NSLog(@"exteria: stories page rejected: %s", exteria_status_name(status));
            error = @"INTERNAL";
        }
        free(rows);
    }
    [self finishLoad:stories error:error completion:done];
    [done release];
}

- (void)loadPinnedStories:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    exteria_peer_ref self_peer;
    memset(&self_peer, 0, sizeof(self_peer));
    self_peer.kind = 1;
    self_peer.self = 1;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_pinned_request(arena, &self_peer, 0, EXTERIA_STORIES_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self deliverStoriesResult:result completion:done];
    }];
}

- (void)loadStoryArchiveBefore:(int32_t)beforeId completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    exteria_peer_ref self_peer;
    memset(&self_peer, 0, sizeof(self_peer));
    self_peer.kind = 1;
    self_peer.self = 1;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_story_archive_request(arena, &self_peer, beforeId, 30, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self deliverStoriesResult:result completion:done];
    }];
}

@end
