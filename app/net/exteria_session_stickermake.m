#import "exteria_session_stickermake.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_sticker_make.h"

@implementation ExteriaStickerDocument
@synthesize documentId = _documentId;
@synthesize accessHash = _accessHash;
@synthesize fileReference = _fileReference;

- (id)initWithId:(long long)documentId accessHash:(long long)accessHash fileReference:(NSData *)fileReference {
    self = [super init];
    if (!self) return nil;
    _documentId = documentId;
    _accessHash = accessHash;
    _fileReference = [fileReference copy];
    return self;
}

- (void)dealloc {
    [_fileReference release];
    [super dealloc];
}
@end

/* the document as the core wants it; a reference longer than the core keeps cannot have come from the core */
static exteria_input_document ExteriaInputDocument(ExteriaStickerDocument *document) {
    exteria_input_document value;
    memset(&value, 0, sizeof(value));
    value.id = document.documentId;
    value.access_hash = document.accessHash;
    value.file_reference_len = MIN(document.fileReference.length, (NSUInteger)EXTERIA_STICKER_REF_MAX);
    memcpy(value.file_reference, document.fileReference.bytes, value.file_reference_len);
    return value;
}

@implementation ExteriaSession (StickerMake)

- (void)checkStickerShortName:(NSString *)name completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *text = [name copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_check_request(arena, text.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status parsed = exteria_sticker_check_parse(result->value);
            if (parsed == EXTERIA_E_STATE) error = @"NAME_OCCUPIED";
            else if (parsed != EXTERIA_OK) error = @"MALFORMED";
        }
        [text release];
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

/* the set the server answers with: only its public name is kept */
- (void)finishSetResult:(const exteria_mt_rpc_result *)result completion:(void (^)(NSString *, NSString *))done {
    NSString *name = nil, *error = nil;
    char buffer[EXTERIA_STICKER_SHORT_NAME_MAX + 1];
    if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
    else if (exteria_sticker_set_name_parse(result->value, buffer, sizeof(buffer)) == EXTERIA_OK) name = [NSString stringWithUTF8String:buffer];
    else error = @"MALFORMED";
    [self noteRpcError:error];
    NSString *deliveredName = [[name copy] autorelease], *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(deliveredName, deliveredError); [done release]; }];
}

- (void)createStickerSetTitle:(NSString *)title shortName:(NSString *)name document:(ExteriaStickerDocument *)document emoji:(NSString *)emoji
                   completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    NSString *setTitle = [title copy], *setName = [name copy], *setEmoji = [emoji copy];
    exteria_input_document value = ExteriaInputDocument(document);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_create_request(arena, setTitle.UTF8String, setName.UTF8String, &value, setEmoji.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [setTitle release];
        [setName release];
        [setEmoji release];
        [self finishSetResult:result completion:done];
    }];
}

- (void)addStickerDocument:(ExteriaStickerDocument *)document emoji:(NSString *)emoji toSetNamed:(NSString *)name completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    NSString *setName = [name copy], *setEmoji = [emoji copy];
    exteria_input_document value = ExteriaInputDocument(document);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_add_request(arena, setName.UTF8String, &value, setEmoji.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [setName release];
        [setEmoji release];
        [self finishSetResult:result completion:done];
    }];
}

@end
