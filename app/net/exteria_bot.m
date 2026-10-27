#import "exteria_bot.h"

static NSString *ExteriaUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaBotCommand
@synthesize name = _name;
@synthesize text = _text;
- (id)initWithRow:(const exteria_bot_command *)row {
    self = [super init];
    if (!self) return nil;
    _name = [ExteriaUtf8(row->name) copy];
    _text = [ExteriaUtf8(row->text) copy];
    return self;
}
- (void)dealloc {
    [_name release];
    [_text release];
    [super dealloc];
}
@end

@implementation ExteriaBotInfo
@synthesize botDescription = _botDescription;
@synthesize picture = _picture;
@synthesize commands = _commands;
@synthesize menuKind = _menuKind;
@synthesize privacyUrl = _privacyUrl;

+ (ExteriaBotInfo *)infoWithRow:(const exteria_bot_info *)row {
    ExteriaBotInfo *info = [[[ExteriaBotInfo alloc] init] autorelease];
    info->_botDescription = [ExteriaUtf8(row->description) copy];
    if (row->has_picture) info->_picture = [[ExteriaMedia mediaWithInfo:&row->picture] retain];
    NSMutableArray *commands = [NSMutableArray arrayWithCapacity:row->command_count];
    for (uint16_t i = 0; i < row->command_count; ++i) {
        ExteriaBotCommand *command = [[ExteriaBotCommand alloc] initWithRow:&row->commands[i]];
        [commands addObject:command];
        [command release];
    }
    info->_commands = [commands copy];
    info->_menuKind = (exteria_bot_menu_kind)row->menu_kind;
    info->_privacyUrl = [ExteriaUtf8(row->privacy_url) copy];
    return info;
}

- (void)dealloc {
    [_botDescription release];
    [_picture release];
    [_commands release];
    [_privacyUrl release];
    [super dealloc];
}
@end

@implementation ExteriaCallbackAnswer
@synthesize alert = _alert;
@synthesize message = _message;
@synthesize url = _url;

+ (ExteriaCallbackAnswer *)answerWithRow:(const exteria_callback_answer *)row {
    ExteriaCallbackAnswer *answer = [[[ExteriaCallbackAnswer alloc] init] autorelease];
    answer->_alert = row->alert;
    answer->_message = [ExteriaUtf8(row->message) copy];
    if (row->has_url) answer->_url = [ExteriaUtf8(row->url) copy];
    return answer;
}

- (void)dealloc {
    [_message release];
    [_url release];
    [super dealloc];
}
@end

@implementation ExteriaWebFile
@synthesize url = _url;
@synthesize proxied = _proxied;
@synthesize accessHash = _accessHash;

+ (ExteriaWebFile *)fileWithRef:(const exteria_web_ref *)ref {
    if (!ref->present) return nil;
    ExteriaWebFile *file = [[[ExteriaWebFile alloc] init] autorelease];
    file->_url = [ExteriaUtf8(ref->url) copy];
    file->_proxied = ref->proxied;
    file->_accessHash = ref->access_hash;
    return file;
}

- (void)dealloc {
    [_url release];
    [super dealloc];
}
@end

@implementation ExteriaInlineResult
@synthesize kind = _kind;
@synthesize resultId = _resultId;
@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize media = _media;
@synthesize thumb = _thumb;
@synthesize width = _width;
@synthesize height = _height;
@synthesize duration = _duration;

+ (ExteriaInlineResult *)resultWithRow:(const exteria_inline_result *)row {
    ExteriaInlineResult *result = [[[ExteriaInlineResult alloc] init] autorelease];
    result->_kind = (exteria_inline_kind)row->kind;
    result->_resultId = [ExteriaUtf8(row->id) copy];
    result->_title = [ExteriaUtf8(row->title) copy];
    result->_subtitle = [ExteriaUtf8(row->description) copy];
    if (row->media.kind != EXTERIA_PREVIEW_NONE) result->_media = [[ExteriaMedia mediaWithInfo:&row->media] retain];
    result->_thumb = [[ExteriaWebFile fileWithRef:&row->thumb] retain];
    result->_width = row->width;
    result->_height = row->height;
    result->_duration = row->duration;
    return result;
}

- (void)dealloc {
    [_resultId release];
    [_title release];
    [_subtitle release];
    [_media release];
    [_thumb release];
    [super dealloc];
}
@end

@implementation ExteriaInlinePage
@synthesize queryId = _queryId;
@synthesize gallery = _gallery;
@synthesize nextOffset = _nextOffset;
@synthesize switchText = _switchText;
@synthesize switchParam = _switchParam;
@synthesize results = _results;

+ (ExteriaInlinePage *)pageWithRow:(const exteria_inline_page *)row results:(NSArray *)results {
    ExteriaInlinePage *page = [[[ExteriaInlinePage alloc] init] autorelease];
    page->_queryId = row->query_id;
    page->_gallery = row->gallery;
    page->_nextOffset = [ExteriaUtf8(row->next_offset) copy];
    page->_switchText = [ExteriaUtf8(row->switch_text) copy];
    page->_switchParam = [ExteriaUtf8(row->switch_param) copy];
    page->_results = [results copy];
    return page;
}

- (void)dealloc {
    [_nextOffset release];
    [_switchText release];
    [_switchParam release];
    [_results release];
    [super dealloc];
}
@end

@implementation ExteriaUrlAuth
@synthesize kind = _kind;
@synthesize requestWrite = _requestWrite;
@synthesize requestPhone = _requestPhone;
@synthesize botName = _botName;
@synthesize domain = _domain;
@synthesize url = _url;
@synthesize codes = _codes;

+ (ExteriaUrlAuth *)authWithRow:(const exteria_url_auth *)row {
    ExteriaUrlAuth *auth = [[[ExteriaUrlAuth alloc] init] autorelease];
    auth->_kind = (exteria_url_auth_kind)row->kind;
    auth->_requestWrite = row->request_write;
    auth->_requestPhone = row->request_phone;
    auth->_botName = [ExteriaUtf8(row->bot) copy];
    auth->_domain = [ExteriaUtf8(row->domain) copy];
    auth->_url = [ExteriaUtf8(row->url) copy];
    NSMutableArray *codes = [NSMutableArray arrayWithCapacity:row->code_count];
    for (uint8_t i = 0; i < row->code_count; ++i) [codes addObject:ExteriaUtf8(row->codes[i])];
    auth->_codes = [codes copy];
    return auth;
}

- (void)dealloc {
    [_botName release];
    [_domain release];
    [_url release];
    [_codes release];
    [super dealloc];
}
@end

@implementation ExteriaStarsInvoice
- (void)dealloc {
    [slug release];
    [title release];
    [invoiceDescription release];
    [super dealloc];
}
@end
