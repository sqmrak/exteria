#import "exteria_session_language.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_langpack.h"

@implementation ExteriaLanguagePack
@synthesize name = _name, nativeName = _nativeName, code = _code, baseCode = _baseCode, translationsURL = _translationsURL;
@synthesize stringsCount = _stringsCount, translatedCount = _translatedCount, official = _official, rtl = _rtl;

- (id)initWithInfo:(const exteria_langpack_info *)info {
    self = [super init];
    if (!self) return nil;
    _name = [[NSString stringWithUTF8String:info->name] copy];
    _nativeName = [[NSString stringWithUTF8String:info->native_name] copy];
    _code = [[NSString stringWithUTF8String:info->lang_code] copy];
    _baseCode = [[NSString stringWithUTF8String:info->base_lang_code] copy];
    _translationsURL = [[NSString stringWithUTF8String:info->translations_url] copy];
    _stringsCount = info->strings_count;
    _translatedCount = info->translated_count;
    _official = info->official != 0;
    _rtl = info->rtl != 0;
    /* a name that was not valid utf-8 comes back as nil, and the pack cannot be shown without one */
    if (!_name.length || !_code.length) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc {
    [_name release];
    [_nativeName release];
    [_code release];
    [_baseCode release];
    [_translationsURL release];
    [super dealloc];
}
@end

@implementation ExteriaSession (Language)

- (void)loadLanguagePack:(NSString *)code completion:(void (^)(ExteriaLanguagePack *, NSString *))completion {
    void (^done)(ExteriaLanguagePack *, NSString *) = [completion copy];
    NSString *wanted = [[code copy] autorelease];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_langpack_request(arena, "ios", wanted.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaLanguagePack *pack = nil;
        NSString *error = nil;
        if (result->status == EXTERIA_E_ARG) {
            error = @"ARG";
        } else if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_langpack_info info;
            if (exteria_langpack_parse(result->value, &info) == EXTERIA_OK) pack = [[[ExteriaLanguagePack alloc] initWithInfo:&info] autorelease];
            if (!pack) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *failure = [[error copy] autorelease];
        [self deliverMain:^{ done(pack, failure); [done release]; }];
    }];
}

@end
