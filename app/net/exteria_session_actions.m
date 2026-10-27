#import "exteria_session_internal.h"

#include "exteria_message_actions.h"

#import "exteria_rpc.h"
#import "exteria_session_actions.h"

#include "exteria_poll.h"

/* the ids of an array of numbers, in a buffer the worker block owns */
static NSData *ExteriaPackIds(NSArray *ids) {
    NSMutableData *data = [NSMutableData dataWithLength:(ids.count ? ids.count : 1) * sizeof(int32_t)];
    int32_t *values = data.mutableBytes;
    NSUInteger count = 0;
    for (NSNumber *number in ids) {
        if (count >= EXTERIA_MESSAGES_MAX) break;
        values[count++] = number.intValue;
    }
    return data;
}

@implementation ExteriaSession (Actions)

- (void)finishAction:(const exteria_mt_rpc_result *)result completion:(void (^)(NSString *))done {
    NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
    [self noteRpcError:error];
    NSString *delivered = [[error copy] autorelease];
    [self deliverMain:^{ done(delivered); [done release]; }];
}

- (void)deleteMessageIds:(NSArray *)ids ofDialog:(ExteriaDialog *)dialog revoke:(BOOL)revoke completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSData *packed = [ExteriaPackIds(ids) retain];
    size_t count = MIN(ids.count, (NSUInteger)EXTERIA_MESSAGES_MAX);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_delete_messages_request(arena, &peer, packed.bytes, count, revoke, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else if (exteria_delete_messages_parse(result->value) != EXTERIA_OK) {
            error = @"MALFORMED";
        } else {
            /* the server keeps no message to send back as an update, so the kept copy is cleaned here */
            const int32_t *values = packed.bytes;
            exteria_peer channel = {3, peer.id};
            for (size_t i = 0; i < count; ++i) {
                exteria_status status = peer.kind == 3 ? exteria_store_delete([self workerStore], EXTERIA_RECORD_MESSAGE, channel, values[i])
                                                       : exteria_store_delete_common_message([self workerStore], values[i]);
                if (status != EXTERIA_OK && status != EXTERIA_E_NOTFOUND) NSLog(@"exteria: kept message %d not removed: %s", values[i], exteria_status_name(status));
            }
        }
        [packed release];
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)pinMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog unpin:(BOOL)unpin completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_pin_message_request(arena, &peer, messageId, unpin, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishAction:result completion:done];
    }];
}

- (void)editMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog text:(NSString *)text completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_edit_message_request(arena, &peer, messageId, body.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishAction:result completion:done];
    }];
    [body release];
}

- (void)editCaptionOfMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog text:(NSString *)text completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_edit_caption_request(arena, &peer, messageId, body.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishAction:result completion:done];
    }];
    [body release];
}

- (void)transcribeMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *, BOOL, NSString *))completion {
    void (^done)(NSString *, BOOL, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_transcribe_request(arena, &peer, messageId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil, *text = nil;
        BOOL pending = NO;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_transcript *transcript = calloc(1, sizeof(*transcript));
            if (transcript && exteria_transcribe_parse(result->value, transcript) == EXTERIA_OK) {
                text = [NSString stringWithUTF8String:transcript->text];
                pending = transcript->pending;
            } else {
                NSLog(@"exteria: the transcription answer was rejected");
                error = @"MALFORMED";
            }
            free(transcript);
        }
        [self noteRpcError:error];
        NSString *deliveredText = [[text copy] autorelease];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredText ? deliveredText : @"", pending, delivered); [done release]; }];
    }];
}

- (void)loadReadDateOfMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog completion:(void (^)(int32_t, NSString *))completion {
    void (^done)(int32_t, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_read_date_request(arena, &peer, messageId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        int32_t date = 0;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_read_date_parse(result->value, &date) != EXTERIA_OK) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(date, delivered); [done release]; }];
    }];
}

- (void)loadGroupReadDatesOfMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_group_read_dates_request(arena, &peer, messageId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        exteria_group_read_date rows[256];
        size_t count = 0;
        NSMutableArray *readers = [NSMutableArray array];
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_group_read_dates_parse(result->value, rows, 256, &count) != EXTERIA_OK) error = @"MALFORMED";
        else for (size_t i = 0; i < count; ++i) {
            [readers addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:rows[i].user_id], @"user", [NSNumber numberWithInt:rows[i].date], @"date", nil]];
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(error ? nil : readers, delivered); [done release]; }];
    }];
}

- (void)scheduleText:(NSString *)text atDate:(int32_t)date toDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    int64_t randomId;
    do {
        randomId = (int64_t)((((uint64_t)arc4random() << 32) | arc4random()) & 0x7fffffffffffffffULL);
    } while (randomId == 0);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_status status = exteria_send_text_request(arena, &peer, body.UTF8String, NULL, 0, randomId, request);
        return status == EXTERIA_OK ? exteria_set_schedule(arena, *request, date) : status;
    } handler:^(const exteria_mt_rpc_result *result) {
        [body release];
        [self finishAction:result completion:done];
    }];
}

- (void)exportLinkOfMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_message_link_request(arena, &peer, messageId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *link = nil, *error = nil;
        char buffer[256];
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else if (exteria_message_link_parse(result->value, buffer, sizeof(buffer)) == EXTERIA_OK) {
            link = [NSString stringWithUTF8String:buffer];
        } else {
            error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *deliveredLink = [[link copy] autorelease], *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredLink, deliveredError); [done release]; }];
    }];
}

- (void)sendVoteOptions:(NSArray *)options forMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSMutableData *packed = [[NSMutableData alloc] initWithLength:(options.count ? options.count : 1) * sizeof(exteria_poll_choice)];
    exteria_poll_choice *choices = packed.mutableBytes;
    size_t count = 0;
    for (NSData *token in options) {
        if (count >= EXTERIA_POLL_ANSWERS_MAX || !token.length || token.length > EXTERIA_POLL_OPTION_MAX) continue;
        memcpy(choices[count].option, token.bytes, token.length);
        choices[count].option_len = token.length;
        ++count;
    }
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_poll_vote_request(arena, &peer, messageId, choices, count, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [packed release];
        [self finishAction:result completion:done];
    }];
}

- (void)loadMessagesWithIds:(NSArray *)ids ofDialog:(ExteriaDialog *)dialog completion:(ExteriaListCompletion)completion {
    [self loadMessagesWithIds:ids ofDialog:dialog withPeople:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        if (completion) completion(messages, errorName);
    }];
}

- (void)loadMessagesWithIds:(NSArray *)ids ofDialog:(ExteriaDialog *)dialog withPeople:(ExteriaHistoryCompletion)completion {
    ExteriaHistoryCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t values[EXTERIA_MESSAGES_MAX];
    size_t count = 0;
    for (NSNumber *identifier in ids) if (count < EXTERIA_MESSAGES_MAX) values[count++] = identifier.intValue;
    NSData *packed = [[NSData alloc] initWithBytes:values length:count * sizeof(int32_t)];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_messages_by_id_request(arena, &peer, packed.bytes, packed.length / sizeof(int32_t), request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *messages = nil;
        NSDictionary *people = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_message_row *rows = calloc(EXTERIA_MESSAGES_MAX, sizeof(*rows));
            size_t found = 0;
            if (rows && exteria_messages_parse(result->value, rows, EXTERIA_MESSAGES_MAX, &found) == EXTERIA_OK) {
                people = ExteriaPeopleOfAnswer(result->value);
                messages = [NSMutableArray arrayWithCapacity:found];
                for (size_t i = 0; i < found; ++i) {
                    ExteriaMessage *message = [ExteriaMessage messageWithRow:&rows[i]];
                    if (message) [messages addObject:message];
                }
            } else {
                error = @"MALFORMED";
            }
            free(rows);
        }
        [packed release];
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        NSArray *deliveredMessages = [[messages copy] autorelease];
        NSDictionary *deliveredPeople = [[people copy] autorelease];
        [self deliverMain:^{
            if (done) done(deliveredMessages, deliveredPeople, deliveredError);
            [done release];
        }];
    }];
}

- (void)forwardMessageIds:(NSArray *)ids fromDialog:(ExteriaDialog *)from toDialog:(ExteriaDialog *)to hideAuthor:(BOOL)hideAuthor completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref source = ExteriaPeerRefOfDialog(from);
    exteria_peer_ref target = ExteriaPeerRefOfDialog(to);
    NSData *packed = [ExteriaPackIds(ids) retain];
    size_t count = MIN(ids.count, (NSUInteger)EXTERIA_MESSAGES_MAX);
    NSMutableData *randoms = [[NSMutableData alloc] initWithLength:(count ? count : 1) * sizeof(int64_t)];
    int64_t *random = randoms.mutableBytes;
    for (size_t i = 0; i < count; ++i) {
        do {
            random[i] = (int64_t)((((uint64_t)arc4random() << 32) | arc4random()) & 0x7fffffffffffffffULL);
        } while (random[i] == 0);
    }
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_forward_messages_request(arena, &source, &target, packed.bytes, randoms.bytes, count, hideAuthor ? 1 : 0, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [packed release];
        [randoms release];
        [self finishAction:result completion:done];
    }];
}

@end
