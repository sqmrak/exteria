#import "exteria_session_admin_log.h"

#import "exteria_rpc.h"
#import "exteria_session_internal.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *ExteriaLogUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaAdminEvent

@synthesize eventId = _eventId;
@synthesize date = _date;
@synthesize kind = _kind;
@synthesize flag = _flag;
@synthesize hasMedia = _hasMedia;
@synthesize hasTarget = _hasTarget;
@synthesize messageId = _messageId;
@synthesize number = _number;
@synthesize actorName = _actorName;
@synthesize actorUsername = _actorUsername;
@synthesize targetName = _targetName;
@synthesize beforeText = _beforeText;
@synthesize afterText = _afterText;

- (id)initWithRow:(const exteria_admin_event *)row {
    self = [super init];
    if (!self) return nil;
    _eventId = row->id;
    _date = row->date;
    _kind = (exteria_admin_event_kind)row->kind;
    _flag = row->flag != 0;
    _hasMedia = row->has_media != 0;
    _hasTarget = row->has_target != 0;
    _messageId = row->message_id;
    _number = row->new_number;
    _actorName = [ExteriaLogUtf8(row->actor_name) copy];
    _actorUsername = [ExteriaLogUtf8(row->actor_username) copy];
    _targetName = [ExteriaLogUtf8(row->target_name) copy];
    _beforeText = [ExteriaLogUtf8(row->old_text) copy];
    _afterText = [ExteriaLogUtf8(row->new_text) copy];
    return self;
}

- (void)dealloc {
    [_actorName release];
    [_actorUsername release];
    [_targetName release];
    [_beforeText release];
    [_afterText release];
    [super dealloc];
}

@end

@implementation ExteriaSession (AdminLog)

- (void)loadAdminLogOfDialog:(ExteriaDialog *)dialog query:(NSString *)query beforeId:(long long)maxId
                  completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [[query copy] autorelease];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_admin_log_request(arena, &peer, text.length ? [text UTF8String] : NULL, maxId, EXTERIA_ADMIN_LOG_PAGE, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *events = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_admin_event *rows = calloc(EXTERIA_ADMIN_LOG_PAGE, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_admin_log_parse(result->value, rows, EXTERIA_ADMIN_LOG_PAGE, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                events = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [events addObject:[[[ExteriaAdminEvent alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: channels.getAdminLog answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(events, deliveredError); [done release]; }];
    }];
}

@end
