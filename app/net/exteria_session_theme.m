#import "exteria_session_theme.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_theme_link.h"

@implementation ExteriaThemeLink
@synthesize title = _title, file = _file;

- (id)initWithInfo:(const exteria_theme_link_info *)info {
    self = [super init];
    if (!self) return nil;
    _title = [[NSString stringWithUTF8String:info->title] copy];
    if (info->has_file) _file = [[ExteriaMedia mediaWithInfo:&info->file] retain];
    /* a title that was not valid utf-8 comes back as nil, and the theme cannot be shown without one */
    if (!_title.length || (info->has_file && !_file)) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc {
    [_title release];
    [_file release];
    [super dealloc];
}
@end

@implementation ExteriaSession (Theme)

- (void)loadThemeOfSlug:(NSString *)slug completion:(void (^)(ExteriaThemeLink *, NSString *))completion {
    void (^done)(ExteriaThemeLink *, NSString *) = [completion copy];
    NSString *wanted = [[slug copy] autorelease];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_theme_link_request(arena, wanted.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaThemeLink *theme = nil;
        NSString *error = nil;
        if (result->status == EXTERIA_E_ARG) {
            error = @"ARG";
        } else if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_theme_link_info info;
            if (exteria_theme_link_parse(result->value, &info) == EXTERIA_OK) theme = [[[ExteriaThemeLink alloc] initWithInfo:&info] autorelease];
            if (!theme) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *failure = [[error copy] autorelease];
        [self deliverMain:^{ done(theme, failure); [done release]; }];
    }];
}

@end
