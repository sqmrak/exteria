#import "exteria_session_calllog.h"

#import "exteria_person.h"
#import "exteria_rpc.h"
#import "exteria_session_internal.h"

@implementation ExteriaCallLogEntry

@synthesize name = _name;
@synthesize initials = _initials;
@synthesize photo = _photo;

- (id)initWithRow:(const exteria_call_log_row *)row {
    self = [super init];
    if (!self) return nil;
    _row = *row;
    NSString *name = [NSString stringWithUTF8String:row->name];
    _name = [(name ? name : @"") copy];
    _initials = [(row->deleted ? @"" : ExteriaInitialsOfName(_name)) copy];
    _photo = [[ExteriaPhoto photoWithRef:&row->photo] retain];
    return self;
}

- (void)dealloc {
    [_name release];
    [_initials release];
    [_photo release];
    [super dealloc];
}

- (int32_t)messageId { return _row.message_id; }
- (int32_t)date { return _row.date; }
- (int32_t)duration { return _row.duration; }
- (BOOL)outgoing { return _row.outgoing != 0; }
- (BOOL)video { return _row.video != 0; }
- (BOOL)missed { return _row.outcome == EXTERIA_OUTCOME_MISSED; }
- (BOOL)busy { return _row.outcome == EXTERIA_OUTCOME_BUSY; }
- (long long)userId { return _row.user_id; }
- (BOOL)deleted { return _row.deleted != 0; }

- (NSString *)summaryText {
    NSString *kind;
    if (self.missed) kind = NSLocalizedString(self.outgoing ? @"calls.cancelled" : @"calls.missed", nil);
    else if (self.busy) kind = NSLocalizedString(@"calls.busy", nil);
    else kind = NSLocalizedString(self.outgoing ? @"calls.outgoing" : @"calls.incoming", nil);
    if (self.video) kind = [NSString stringWithFormat:NSLocalizedString(@"calls.video", nil), kind];
    if (_row.duration > 0) return [NSString stringWithFormat:@"%@, %d:%02d", kind, (int)(_row.duration / 60), (int)(_row.duration % 60)];
    return kind;
}

- (ExteriaDialog *)dialog {
    if (!_row.access_hash) return nil;
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = 1;
    row.peer_id = _row.user_id;
    row.peer_hash = _row.access_hash;
    row.kind = EXTERIA_DIALOG_USER;
    row.deleted = _row.deleted;
    row.photo = _row.photo;
    snprintf(row.title, sizeof(row.title), "%s", _row.name);
    return [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
}

@end

@implementation ExteriaSession (CallLog)

- (void)loadCallLog:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_call_log_request(arena, EXTERIA_CALL_LOG_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *entries = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_call_log_row *rows = calloc(EXTERIA_CALL_LOG_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_call_log_parse(result->value, rows, EXTERIA_CALL_LOG_MAX, &count) == EXTERIA_OK) {
                entries = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [entries addObject:[[[ExteriaCallLogEntry alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: the call log answer was rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:entries error:error completion:done];
        [done release];
    }];
}

@end
