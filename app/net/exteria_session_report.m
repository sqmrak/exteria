#import "exteria_session_internal.h"

#import "exteria_rpc.h"
#import "exteria_session_report.h"

@implementation ExteriaSession (Report)

- (void)reportDialog:(ExteriaDialog *)dialog reason:(exteria_report_reason)reason comment:(NSString *)comment completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [[comment copy] autorelease];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_report_request(arena, &peer, reason, text.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status parsed = exteria_report_parse(result->value);
            if (parsed == EXTERIA_E_STATE) error = @"NOT_REPORTED";
            else if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

@end

@implementation ExteriaMessageReportStep
@synthesize kind = _kind;
@synthesize title = _title;
@synthesize options = _options;
@synthesize tokens = _tokens;
@synthesize token = _token;
@synthesize commentOptional = _commentOptional;

+ (ExteriaMessageReportStep *)stepWithAnswer:(const exteria_message_report_answer *)answer {
    ExteriaMessageReportStep *step = [[[ExteriaMessageReportStep alloc] init] autorelease];
    step->_kind = (ExteriaMessageReportKind)answer->step;
    step->_title = [[NSString stringWithUTF8String:answer->title] copy];
    NSMutableArray *options = [NSMutableArray array], *tokens = [NSMutableArray array];
    for (size_t i = 0; i < answer->option_count; ++i) {
        NSString *text = [NSString stringWithUTF8String:answer->options[i].text];
        [options addObject:text ? text : @""];
        [tokens addObject:[NSData dataWithBytes:answer->options[i].token length:answer->options[i].token_len]];
    }
    step->_options = [options retain];
    step->_tokens = [tokens retain];
    step->_token = [[NSData dataWithBytes:answer->token length:answer->token_len] retain];
    step->_commentOptional = answer->comment_optional != 0;
    return step;
}

- (void)dealloc {
    [_title release];
    [_options release];
    [_tokens release];
    [_token release];
    [super dealloc];
}
@end

@implementation ExteriaSession (MessageReport)

- (void)reportMessageIds:(NSArray *)ids ofDialog:(ExteriaDialog *)dialog token:(NSData *)token comment:(NSString *)comment
              completion:(void (^)(ExteriaMessageReportStep *, NSString *))completion {
    void (^done)(ExteriaMessageReportStep *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSMutableData *packed = [[NSMutableData alloc] init];
    for (NSNumber *identifier in ids) {
        int32_t value = identifier.intValue;
        [packed appendBytes:&value length:sizeof(value)];
    }
    size_t count = MIN(packed.length / sizeof(int32_t), (size_t)EXTERIA_REPORT_IDS_MAX);
    NSData *chosen = [token copy];
    NSString *text = [comment copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_message_report_request(arena, &peer, packed.bytes, count, chosen.bytes, chosen.length, text.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        ExteriaMessageReportStep *step = nil;
        exteria_message_report_answer *answer = calloc(1, sizeof(*answer));
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else if (!answer || exteria_message_report_parse(result->value, answer) != EXTERIA_OK) {
            error = @"MALFORMED";
        } else {
            step = [ExteriaMessageReportStep stepWithAnswer:answer];
        }
        free(answer);
        [packed release];
        [chosen release];
        [text release];
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(step, deliveredError); [done release]; }];
    }];
}

@end
