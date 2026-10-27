#import "exteria_session_notify.h"
#import "exteria_language.h"

#import "exteria_files.h"
#import "exteria_rpc.h"
#import "exteria_session_internal.h"

#include "exteria_notify.h"

@implementation ExteriaNotifyEvent

@synthesize peerKind = _peerKind;
@synthesize peerId = _peerId;
@synthesize messageId = _messageId;
@synthesize title = _title;
@synthesize body = _body;
@synthesize sound = _sound;
@synthesize dialog = _dialog;

- (id)initWithEvent:(const exteria_notify_event *)event {
    self = [super init];
    if (!self) return nil;
    _sound = event->sound;
    _peerKind = event->peer_kind;
    _peerId = event->peer_id;
    _messageId = event->message_id;
    _title = [[NSString stringWithUTF8String:event->title] copy];
    _body = [[NSString stringWithUTF8String:event->body] copy];
    if (!_title) _title = [@"" copy];
    if (!_body) _body = [@"" copy];
    return self;
}

- (void)dealloc {
    [_title release];
    [_body release];
    [_dialog release];
    [super dealloc];
}

@end

#define SCAN_DIALOGS 50

/* the look the session took last; worker thread only, and one session lives at a time */
static exteria_notify_state sNotifyState;
static int64_t sNotifyStateAccount;

static NSString *ExteriaNotifyStatePath(NSString *directory, int64_t account) {
    return ExteriaFilePath(directory, [NSString stringWithFormat:@"notify-state-%lld", (long long)account]);
}

/* the last look of this account from its file, or an empty one that takes the baseline */
static void ExteriaNotifyLoadState(NSString *directory, int64_t account) {
    uint8_t bytes[EXTERIA_NOTIFY_STATE_BYTES + 1];
    size_t len = 0;
    if (sNotifyStateAccount == account) return;
    sNotifyStateAccount = account;
    exteria_notify_state_init(&sNotifyState);
    exteria_status status = ExteriaReadFile(ExteriaNotifyStatePath(directory, account), bytes, sizeof(bytes), &len);
    if (status == EXTERIA_OK && exteria_notify_state_unpack(bytes, len, &sNotifyState) != EXTERIA_OK) {
        NSLog(@"exteria: the notification state file is unusable, taking a new baseline");
        exteria_notify_state_init(&sNotifyState);
    }
}

static void ExteriaNotifySaveState(NSString *directory, int64_t account) {
    uint8_t bytes[EXTERIA_NOTIFY_STATE_BYTES];
    size_t len = 0;
    exteria_status status = exteria_notify_state_pack(&sNotifyState, bytes, sizeof(bytes), &len);
    if (status == EXTERIA_OK) status = ExteriaWriteFile(ExteriaNotifyStatePath(directory, account), bytes, len);
    if (status != EXTERIA_OK) NSLog(@"exteria: cannot keep the notification state: %s", exteria_status_name(status));
}

@implementation ExteriaSession (Notify)

- (void)scanNotificationsAnnouncing:(BOOL)announce options:(ExteriaNotifyScanOptions)options completion:(ExteriaNotifyScanCompletion)completion {
    ExteriaNotifyScanCompletion done = [completion copy];
    BOOL russian = [ExteriaInterfaceLanguage() isEqualToString:@"ru"];
    [self post:^{
        if ([self workerAccount] <= 0) {
            [self deliverMain:^{ done(nil, 0, nil, 0, 0, @"NO_ACCOUNT"); [done release]; }];
            return;
        }
        [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_tl_value *call = exteria_tl_new_obj(arena, "messages.getDialogs");
            exteria_tl_value *empty = exteria_tl_new_obj(arena, "inputPeerEmpty");
            if (!call || !empty) return EXTERIA_E_NOMEM;
            exteria_status status = exteria_tl_set(call, "offset_peer", empty);
            if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, call, "offset_date", 0);
            if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, call, "offset_id", 0);
            if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, call, "limit", SCAN_DIALOGS);
            if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, call, "folder_id", 0);
            if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, call, "hash", 0);
            if (status == EXTERIA_OK) *request = call;
            return status;
        } handler:^(const exteria_mt_rpc_result *result) {
            if (result->status != EXTERIA_OK) {
                NSString *error = ExteriaRpcErrorName(result);
                [self noteRpcError:error];
                /* the wait the server asks for travels with the name, which is how the notifier knows how long to leave the list alone */
                NSString *delivered = error;
                if ([error isEqualToString:@"FLOOD_WAIT"] && result->error_text) {
                    char name[128];
                    int32_t seconds = 0;
                    exteria_mt_rpc_error_split(result->error_text, name, sizeof(name), &seconds);
                    delivered = [NSString stringWithFormat:@"FLOOD_WAIT:%d", (int)seconds];
                }
                delivered = [[delivered copy] autorelease];
                [self deliverMain:^{ done(nil, 0, nil, 0, 0, delivered); [done release]; }];
                return;
            }
            exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t now = (int32_t)[[NSDate date] timeIntervalSince1970];
            exteria_status status = rows ? exteria_dialogs_parse(result->value, [self workerAccount], now, rows, EXTERIA_DIALOGS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: the chat list for notifications was rejected: %s", exteria_status_name(status));
                free(rows);
                [self deliverMain:^{ done(nil, 0, nil, 0, 0, @"INTERNAL"); [done release]; }];
                return;
            }
            exteria_notify_settings settings;
            exteria_notify_event events[EXTERIA_NOTIFY_EVENTS_MAX];
            size_t found = 0, more = 0, i;
            NSInteger badge = 0, unreadChats = 0;
            memset(&settings, 0, sizeof(settings));
            settings.enabled = announce ? 1 : 0;
            settings.rules = options.rules;
            settings.russian = russian ? 1 : 0;
            ExteriaNotifyLoadState([self workerDirectory], [self workerAccount]);
            status = exteria_notify_diff(&sNotifyState, &settings, rows, count, now, options.activeKind, options.activePeer, events, EXTERIA_NOTIFY_EVENTS_MAX, &found, &more);
            for (i = 0; i < count; ++i) {
                exteria_notify_decision decision;
                if (rows[i].folder || rows[i].deleted || rows[i].saved || rows[i].unread_count <= 0) continue;
                exteria_notify_decide(&options.rules, exteria_notify_scope_of(rows[i].peer_kind, rows[i].kind == EXTERIA_DIALOG_CHANNEL), &rows[i].notify, now, &decision);
                if (decision.notify) ++unreadChats;
                if (!decision.notify && !options.badgeMuted) continue;
                badge += options.badgeMessages ? rows[i].unread_count : 1;
            }
            if (!options.badgeShown) badge = 0;
            NSMutableArray *list = [NSMutableArray arrayWithCapacity:found];
            for (i = 0; i < found; ++i) {
                ExteriaNotifyEvent *event = [[[ExteriaNotifyEvent alloc] initWithEvent:&events[i]] autorelease];
                for (size_t j = 0; j < count; ++j) {
                    if (rows[j].peer_kind != events[i].peer_kind || rows[j].peer_id != events[i].peer_id || rows[j].folder) continue;
                    event.dialog = [[[ExteriaDialog alloc] initWithRow:&rows[j]] autorelease];
                    break;
                }
                [list addObject:event];
            }
            free(rows);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: the notification comparison failed: %s", exteria_status_name(status));
                [self deliverMain:^{ done(nil, 0, nil, 0, 0, @"INTERNAL"); [done release]; }];
                return;
            }
            ExteriaNotifySaveState([self workerDirectory], [self workerAccount]);
            char moreText[96];
            exteria_notify_more_text(&settings, more, moreText, sizeof(moreText));
            NSString *moreString = more ? [NSString stringWithUTF8String:moreText] : nil;
            [self deliverMain:^{ done(list, more, moreString, badge, unreadChats, nil); [done release]; }];
        }];
    }];
}

@end
