#import "exteria_session_keywords.h"

#import "exteria_emoji_keywords.h"
#import "exteria_rpc.h"
#import "exteria_session_internal.h"

@implementation ExteriaSession (EmojiKeywords)

- (void)updateEmojiKeywords:(ExteriaEmojiKeywords *)keywords completion:(void (^)(NSString *errorName))completion {
    [self updateEmojiKeywords:keywords fromVersion:keywords.version mayRestart:YES completion:completion];
}

- (void)updateEmojiKeywords:(ExteriaEmojiKeywords *)keywords fromVersion:(int32_t)version mayRestart:(BOOL)mayRestart completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    ExteriaEmojiKeywords *held = [keywords retain];
    NSString *language = [keywords.language copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_keywords_request(arena, language.UTF8String, version, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        BOOL again = NO;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status status = [held applyAnswer:result->value];
            if (status == EXTERIA_E_STATE && mayRestart) {
                again = YES;
            } else if (status != EXTERIA_OK) {
                NSLog(@"exteria: the emoji keywords of %@ were refused: %s", language, exteria_status_name(status));
                error = @"INTERNAL";
            }
        }
        if (again) {
            [self updateEmojiKeywords:held fromVersion:0 mayRestart:NO completion:done];
        } else {
            NSString *delivered = [[error copy] autorelease];
            dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(delivered); });
        }
        [done release];
        [held release];
        [language release];
    }];
}

@end
