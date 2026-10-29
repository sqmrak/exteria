#import "exteria_group_call_engine.h"

#import "exteria_group_runtime.h"
#import "exteria_person.h"
#import "exteria_rpc.h"
#import "exteria_session.h"
#import "exteria_session_internal.h"

#include "exteria_group_call.h"
#include "exteria_random.h"
#include "exteria_tl_ids.h"

/* the server drops a phone that is silent for long, and a client confirms now and then that it is still in the call */
#define CHECK_SECONDS 20.0
#define PARTICIPANTS_PAGE 200
/* members that came without a name are asked for together, a moment after the first */
#define NAME_REFRESH_SECONDS 1.5
#define SPEAKING_RECENT_SECONDS 3

@interface ExteriaGroupCallEngine () <ExteriaGroupRuntimeDelegate> {
    ExteriaSession *_session;
    BOOL _active;
    NSUInteger _generation;
    ExteriaGroupPhase _phase;
    exteria_peer_ref _chatRef;
    NSString *_chatTitle;
    NSString *_inviteHash;
    exteria_group_call_info _info;
    BOOL _haveCall;
    ExteriaGroupRuntime *_runtime;
    BOOL _joinSent, _selfMuted, _canUnmute, _selfSpeaking, _namesPending;
    int _selfPeerKind;
    long long _selfPeerId;
    NSTimeInterval _startedAt;
    NSMutableDictionary *_members;
    NSSet *_speaking;
    NSString *_wantedTitle;
    ExteriaGroupCall *_current;
}
@end

static NSString *ExteriaMemberKey(int kind, long long peerId) {
    return [NSString stringWithFormat:@"%d:%lld", kind, peerId];
}

@implementation ExteriaGroupCallEngine

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = session;
    _members = [[NSMutableDictionary alloc] init];
    return self;
}

- (void)dealloc {
    [_chatTitle release];
    [_inviteHash release];
    [_members release];
    [_speaking release];
    [_wantedTitle release];
    [_current release];
    [super dealloc];
}

#pragma mark publishing

static NSComparisonResult ExteriaCompareMembers(ExteriaGroupMember *a, ExteriaGroupMember *b, void *context) {
    (void)context;
    if (a.isSelf != b.isSelf) return a.isSelf ? NSOrderedAscending : NSOrderedDescending;
    if (a.speaking != b.speaking) return a.speaking ? NSOrderedAscending : NSOrderedDescending;
    if (a.muted != b.muted) return a.muted ? NSOrderedDescending : NSOrderedAscending;
    if (a.activeDate != b.activeDate) return a.activeDate > b.activeDate ? NSOrderedAscending : NSOrderedDescending;
    return [a.name caseInsensitiveCompare:b.name];
}

/* the members as the screens see them: the ones the audio engine hears now, and the ones the server says spoke in the last seconds, are speaking */
- (NSArray *)memberSnapshot {
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:_members.count];
    int now = (int)[[NSDate date] timeIntervalSince1970];
    for (ExteriaGroupMember *m in [_members allValues]) {
        BOOL speaking = !m.muted && ([_speaking containsObject:[NSNumber numberWithUnsignedInt:m.source]] || (m.activeDate > 0 && now - m.activeDate <= SPEAKING_RECENT_SECONDS));
        if (m.isSelf) speaking = _selfSpeaking && !_selfMuted;
        if (speaking == m.speaking) {
            [list addObject:m];
            continue;
        }
        [list addObject:[[[ExteriaGroupMember alloc] initWithPeerId:m.peerId kind:m.peerKind source:m.source name:m.name photo:m.photo muted:m.muted self:m.isSelf
                                                           speaking:speaking canSelfUnmute:m.canSelfUnmute mutedByYou:m.mutedByYou volume:m.volume activeDate:m.activeDate] autorelease]];
    }
    [list sortUsingFunction:ExteriaCompareMembers context:NULL];
    return list;
}

- (void)publishEnd:(ExteriaGroupEnd)end error:(NSString *)error {
    NSString *title = _info.title[0] ? [NSString stringWithUTF8String:_info.title] : nil;
    ExteriaGroupCall *snapshot = [[[ExteriaGroupCall alloc] initWithCallId:_haveCall ? _info.ref.id : 0 title:title chatTitle:_chatTitle
                                                                      count:_info.participants_count > (int)_members.count ? _info.participants_count : (int)_members.count
                                                                      phase:_phase end:end muted:_selfMuted canUnmute:_canUnmute
                                                                  canManage:(_info.creator || _info.can_change_join_muted) ? YES : NO selfSpeaking:_selfSpeaking
                                                                  startedAt:_startedAt members:[self memberSnapshot] error:error] autorelease];
    ExteriaSession *session = _session;
    ExteriaGroupCallEngine *engine = self;
    [session deliverMain:^{
        [engine->_current release];
        engine->_current = [snapshot retain];
        [session.groupCallDelegate session:session groupCallDidChange:snapshot];
    }];
}

- (void)publish {
    [self publishEnd:ExteriaGroupEndNone error:nil];
}

- (ExteriaGroupCall *)current {
    return _current && _current.phase != ExteriaGroupPhaseEnded ? _current : nil;
}

- (void)setPhase:(ExteriaGroupPhase)phase {
    _phase = phase;
    [self publish];
}

#pragma mark timers

/* a timer is a delay on the main queue that hops back to the worker, and it fires only for the call that set it */
- (void)afterSeconds:(NSTimeInterval)seconds do:(void (^)(void))block {
    NSUInteger generation = _generation;
    void (^action)(void) = [block copy];
    ExteriaSession *session = _session;
    ExteriaGroupCallEngine *engine = [self retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [session post:^{
            if (generation == engine->_generation && engine->_active) action();
            [action release];
            [engine release];
        }];
    });
}

#pragma mark api

- (void)loadVoiceChatOfDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaVoiceChat *, NSString *))completion {
    exteria_peer_ref ref = ExteriaPeerRefOfDialog(dialog);
    void (^done)(ExteriaVoiceChat *, NSString *) = [completion copy];
    ExteriaSession *session = _session;
    void (^finish)(ExteriaVoiceChat *, NSString *) = ^(ExteriaVoiceChat *chat, NSString *error) {
        [chat retain];
        [session deliverMain:^{
            done(chat, error);
            [chat release];
            [done release];
        }];
    };
    void (^finishCopy)(ExteriaVoiceChat *, NSString *) = [finish copy];
    [_session post:^{
        [self lookUpCallOfChat:ref completion:^(const exteria_group_call_info *info, NSString *error) {
            if (!info) {
                finishCopy(nil, error);
            } else {
                BOOL joinable = !info->discarded && !info->conference && !info->rtmp_stream && info->schedule_date == 0;
                finishCopy([[[ExteriaVoiceChat alloc] initWithCallId:info->ref.id title:info->title[0] ? [NSString stringWithUTF8String:info->title] : nil
                                                                count:info->participants_count joinable:joinable] autorelease], nil);
            }
            [finishCopy release];
        }];
    }];
}

/* worker only: the call of a chat, found through its full chat and then read with no participants; error "NOCALL" when none runs */
- (void)lookUpCallOfChat:(exteria_peer_ref)chat completion:(void (^)(const exteria_group_call_info *info, NSString *error))completion {
    void (^done)(const exteria_group_call_info *, NSString *) = [completion copy];
    [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_group_full_chat_request(arena, &chat, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        exteria_group_call_ref ref;
        exteria_status status = result->status == EXTERIA_OK ? exteria_group_full_chat_call(result->value, &ref) : result->status;
        if (status != EXTERIA_OK) {
            done(NULL, status == EXTERIA_E_NOTFOUND ? @"NOCALL" : (result->status == EXTERIA_OK ? @"INTERNAL" : ExteriaRpcErrorName(result)));
            [done release];
            return;
        }
        [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_call_get_request(arena, &ref, 0, request);
        } handler:^(const exteria_mt_rpc_result *answer) {
            exteria_group_call_info info;
            exteria_group_participant none[1];
            size_t count = 0;
            exteria_status parsed = answer->status == EXTERIA_OK ? exteria_group_call_answer_parse(answer->value, &info, none, 1, &count, NULL, 0) : answer->status;
            if (parsed != EXTERIA_OK) done(NULL, answer->status == EXTERIA_OK ? @"INTERNAL" : ExteriaRpcErrorName(answer));
            else done(&info, nil);
            [done release];
        }];
    }];
}

- (void)joinVoiceChatOfDialog:(ExteriaDialog *)dialog inviteHash:(NSString *)inviteHash {
    exteria_peer_ref ref = ExteriaPeerRefOfDialog(dialog);
    NSString *title = [[dialog.title copy] autorelease];
    NSString *hash = [[inviteHash copy] autorelease];
    [_session post:^{ [self beginInChat:ref title:title inviteHash:hash create:NO callTitle:nil]; }];
}

- (void)startVoiceChatInDialog:(ExteriaDialog *)dialog title:(NSString *)callTitle {
    exteria_peer_ref ref = ExteriaPeerRefOfDialog(dialog);
    NSString *title = [[dialog.title copy] autorelease];
    NSString *wanted = [[callTitle copy] autorelease];
    [_session post:^{ [self beginInChat:ref title:title inviteHash:nil create:YES callTitle:wanted]; }];
}

- (void)leave {
    [_session post:^{ if (_active) [self finishWithEnd:ExteriaGroupEndLeft error:nil leaveRequest:YES discard:NO]; }];
}

- (void)endForEveryone {
    [_session post:^{ if (_active) [self finishWithEnd:ExteriaGroupEndFinished error:nil leaveRequest:YES discard:YES]; }];
}

- (void)shutdown {
    if (!_active) return;
    ++_generation;
    [_runtime stop];
    [_runtime release];
    _runtime = nil;
    _active = NO;
}

#pragma mark starting

- (void)resetForChat:(exteria_peer_ref)chat title:(NSString *)title inviteHash:(NSString *)inviteHash {
    ++_generation;
    _active = YES;
    _phase = ExteriaGroupPhaseJoining;
    _chatRef = chat;
    [_chatTitle release];
    _chatTitle = [title copy];
    [_inviteHash release];
    _inviteHash = [inviteHash copy];
    memset(&_info, 0, sizeof(_info));
    _haveCall = NO;
    [_runtime stop];
    [_runtime release];
    _runtime = nil;
    _joinSent = NO;
    _selfMuted = YES;
    _canUnmute = YES;
    _selfSpeaking = NO;
    _namesPending = NO;
    _selfPeerId = 0;
    _selfPeerKind = 1;
    _startedAt = 0;
    [_members removeAllObjects];
    [_speaking release];
    _speaking = nil;
}

- (void)beginInChat:(exteria_peer_ref)chat title:(NSString *)title inviteHash:(NSString *)inviteHash create:(BOOL)create callTitle:(NSString *)callTitle {
    NSUInteger generation;
    if (_active) {
        /* one call at a time: the one that runs is shown again */
        [self publish];
        return;
    }
    if (chat.kind != 2 && chat.kind != 3) return;
    [self resetForChat:chat title:title inviteHash:inviteHash];
    generation = _generation;
    [self publish];
    [self lookUpCallOfChat:chat completion:^(const exteria_group_call_info *info, NSString *error) {
        if (generation != _generation || !_active) return;
        if (info) {
            _info = *info;
            _haveCall = YES;
            [self openCall];
            return;
        }
        if ([error isEqualToString:@"NOCALL"] && create) {
            [self createCallWithTitle:callTitle];
            return;
        }
        [self finishWithEnd:[error isEqualToString:@"NOCALL"] ? ExteriaGroupEndNoCall : ExteriaGroupEndFailed error:[error isEqualToString:@"NOCALL"] ? nil : error
               leaveRequest:NO discard:NO];
    }];
}

- (void)createCallWithTitle:(NSString *)title {
    NSUInteger generation = _generation;
    exteria_peer_ref chat = _chatRef;
    int32_t randomId = 0;
    NSString *wanted = [[title copy] autorelease];
    exteria_random(&randomId, sizeof(randomId));
    [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_group_create_request(arena, &chat, randomId, wanted.length ? wanted.UTF8String : NULL, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (generation != _generation || !_active) return;
        exteria_group_call_info info;
        if (result->status != EXTERIA_OK || exteria_group_updates_find_call(result->value, &info) != EXTERIA_OK) {
            NSString *name = result->status == EXTERIA_OK ? @"INTERNAL" : ExteriaRpcErrorName(result);
            NSLog(@"exteria: phone.createGroupCall failed: %@", name);
            [self finishWithEnd:ExteriaGroupEndFailed error:name leaveRequest:NO discard:NO];
            return;
        }
        _info = info;
        _haveCall = YES;
        [self openCall];
    }];
}

/* the call is known: its participants are read, and the join request goes out with the transport description of the media connection */
- (void)openCall {
    if (_info.discarded) {
        [self finishWithEnd:ExteriaGroupEndFinished error:nil leaveRequest:NO discard:NO];
        return;
    }
    if (_info.conference || _info.rtmp_stream || _info.schedule_date > 0) {
        [self finishWithEnd:ExteriaGroupEndUnsupported error:nil leaveRequest:NO discard:NO];
        return;
    }
    NSUInteger generation = _generation;
    _runtime = [[ExteriaGroupRuntime alloc] initWithDelegate:self];
    if (!_runtime) {
        [self finishWithEnd:ExteriaGroupEndFailed error:@"CRYPTO" leaveRequest:NO discard:NO];
        return;
    }
    exteria_group_call_ref ref = _info.ref;
    NSData *params = _runtime.joinParams;
    NSString *hash = [[_inviteHash copy] autorelease];
    /* the first read of the members shows who is there while the media connects */
    [self refreshMembersThen:nil];
    _joinSent = YES;
    [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_group_join_request(arena, &ref, 1, params.bytes, params.length, hash.length ? hash.UTF8String : NULL, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (generation != _generation || !_active) return;
        if (result->status != EXTERIA_OK) {
            NSString *name = ExteriaRpcErrorName(result);
            NSLog(@"exteria: phone.joinGroupCall failed: %@", name);
            [self finishWithEnd:ExteriaGroupEndFailed error:name leaveRequest:NO discard:NO];
            return;
        }
        if (_phase == ExteriaGroupPhaseJoining) [self setPhase:ExteriaGroupPhaseConnecting];
        [self scheduleCheck];
    }];
}

#pragma mark members

- (ExteriaGroupMember *)memberFromRow:(const exteria_group_participant *)row previous:(ExteriaGroupMember *)previous {
    NSString *name = row->name[0] ? [NSString stringWithUTF8String:row->name] : previous.name;
    ExteriaPhoto *photo = [ExteriaPhoto photoWithRef:&row->photo];
    if (!photo) photo = previous.photo;
    if (!name.length && row->peer_kind == 1) {
        ExteriaPerson *stored = [_session storedPersonWithKey:row->peer_id];
        if (stored) {
            name = stored.name;
            if (!photo) photo = stored.photo;
        }
    }
    if (!name.length) _namesPending = YES;
    return [[[ExteriaGroupMember alloc] initWithPeerId:row->peer_id kind:row->peer_kind source:row->source name:name.length ? name : @"…" photo:photo muted:row->muted != 0
                                                self:row->self != 0 speaking:NO canSelfUnmute:row->can_self_unmute != 0 mutedByYou:row->muted_by_you != 0
                                                volume:row->volume activeDate:row->active_date] autorelease];
}

/* the rows of an answer or an update change the members: a member that left goes, and its source is forgotten by the audio */
- (void)applyRows:(const exteria_group_participant *)rows count:(size_t)count replacing:(BOOL)replacing {
    size_t i;
    NSMutableSet *seen = replacing ? [NSMutableSet set] : nil;
    for (i = 0; i < count; ++i) {
        const exteria_group_participant *row = &rows[i];
        NSString *key = ExteriaMemberKey(row->peer_kind, row->peer_id);
        ExteriaGroupMember *previous = [_members objectForKey:key];
        if (row->left) {
            if (previous) [_runtime forgetSource:previous.source];
            [_members removeObjectForKey:key];
            continue;
        }
        if (previous && previous.source != row->source) [_runtime forgetSource:previous.source];
        [_members setObject:[self memberFromRow:row previous:previous] forKey:key];
        [seen addObject:key];
        /* the server keeps the volume a person set for a member, and the mixing is this phone's own work */
        if (!row->self && row->volume > 0) [_runtime setVolume:(float)row->volume / (float)EXTERIA_GROUP_VOLUME_DEFAULT forSource:row->source];
        if (row->self) {
            _selfPeerId = row->peer_id;
            _selfPeerKind = row->peer_kind;
            _canUnmute = row->can_self_unmute != 0 || !row->muted;
            /* the server's word about this phone's microphone wins over what was asked for: a mute by an admin must show */
            if (row->muted && !_selfMuted && !row->can_self_unmute) {
                _selfMuted = YES;
                [_runtime setMuted:YES];
            }
        }
    }
    if (replacing) {
        for (NSString *key in [_members allKeys]) {
            if (![seen containsObject:key]) {
                [_runtime forgetSource:[(ExteriaGroupMember *)[_members objectForKey:key] source]];
                [_members removeObjectForKey:key];
            }
        }
    }
    if (_namesPending) {
        _namesPending = NO;
        [self afterSeconds:NAME_REFRESH_SECONDS do:^{ [self refreshMembersThen:nil]; }];
    }
}

/* the call with its first page of members, read again; this is also what repairs a gap in the updates */
- (void)refreshMembersThen:(void (^)(void))then {
    NSUInteger generation = _generation;
    exteria_group_call_ref ref = _info.ref;
    void (^after)(void) = [then copy];
    if (!_haveCall) {
        [after release];
        return;
    }
    [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_group_call_get_request(arena, &ref, PARTICIPANTS_PAGE, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (generation == _generation && _active && result->status == EXTERIA_OK) {
            exteria_group_call_info info;
            exteria_group_participant *rows = calloc(PARTICIPANTS_PAGE, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_group_call_answer_parse(result->value, &info, rows, PARTICIPANTS_PAGE, &count, NULL, 0) == EXTERIA_OK) {
                if (info.discarded) {
                    free(rows);
                    [self finishWithEnd:ExteriaGroupEndFinished error:nil leaveRequest:NO discard:NO];
                    [after release];
                    return;
                }
                _info = info;
                [self applyRows:rows count:count replacing:YES];
                [self publish];
            }
            free(rows);
        } else if (result->status != EXTERIA_OK) {
            NSLog(@"exteria: phone.getGroupCall failed: %@", ExteriaRpcErrorName(result));
        }
        if (after) after();
        [after release];
    }];
}

#pragma mark updates

- (void)handleUpdate:(const exteria_tl_value *)update container:(const exteria_tl_value *)container {
    if (!_active || !_haveCall) return;
    if (exteria_tl_is(update, EXTERIA_TL_ID_updateGroupCall)) {
        exteria_group_call_info info;
        if (exteria_group_update_call(update, &info) != EXTERIA_OK || info.ref.id != _info.ref.id) return;
        if (info.discarded) {
            [self finishWithEnd:ExteriaGroupEndFinished error:nil leaveRequest:NO discard:NO];
            return;
        }
        _info = info;
        [self publish];
    } else if (exteria_tl_is(update, EXTERIA_TL_ID_updateGroupCallParticipants)) {
        exteria_group_call_ref ref;
        exteria_group_participant *rows = calloc(EXTERIA_GROUP_PARTICIPANTS_MAX, sizeof(*rows));
        size_t count = 0;
        int32_t version = 0;
        if (rows && exteria_group_update_participants(update, container, &ref, rows, EXTERIA_GROUP_PARTICIPANTS_MAX, &count, &version) == EXTERIA_OK &&
            ref.id == _info.ref.id) {
            [self applyRows:rows count:count replacing:NO];
            if (version > _info.version) _info.version = version;
            [self publish];
        }
        free(rows);
    } else if (exteria_tl_is(update, EXTERIA_TL_ID_updateGroupCallConnection)) {
        const char *json = NULL;
        size_t length = 0;
        int presentation = 0;
        /* the answer of the server may come before the answer to the join request that asked for it, so the join does not have to be confirmed yet */
        if (exteria_group_update_connection(update, &json, &length, &presentation) != EXTERIA_OK || presentation || !_runtime) return;
        if (![_runtime applyTransport:[NSData dataWithBytes:json length:length]]) {
            [self finishWithEnd:ExteriaGroupEndFailed error:@"TRANSPORT" leaveRequest:YES discard:NO];
            return;
        }
        [self setPhase:ExteriaGroupPhaseConnecting];
    }
}

#pragma mark media

- (void)groupRuntime:(ExteriaGroupRuntime *)runtime didChangeState:(exteria_tgc_group_state)state {
    [_session post:^{
        if (!_active || _runtime != runtime) return;
        switch (state) {
        case EXTERIA_TGC_GROUP_CONNECTED:
            if (!_startedAt) _startedAt = [NSDate timeIntervalSinceReferenceDate];
            [self setPhase:ExteriaGroupPhaseActive];
            break;
        case EXTERIA_TGC_GROUP_RECONNECTING:
            [self setPhase:ExteriaGroupPhaseReconnecting];
            break;
        case EXTERIA_TGC_GROUP_FAILED:
            [self finishWithEnd:ExteriaGroupEndFailed error:@"CONNECTION" leaveRequest:YES discard:NO];
            break;
        default:
            break;
        }
    }];
}

- (void)groupRuntime:(ExteriaGroupRuntime *)runtime speaking:(NSArray *)sources selfSpeaking:(BOOL)selfSpeaking {
    NSSet *set = [NSSet setWithArray:sources];
    [_session post:^{
        if (!_active || _runtime != runtime) return;
        if ([set isEqualToSet:_speaking ? _speaking : [NSSet set]] && selfSpeaking == _selfSpeaking) return;
        [_speaking release];
        _speaking = [set retain];
        _selfSpeaking = selfSpeaking;
        [self publish];
    }];
}

#pragma mark microphone and members

- (void)setMuted:(BOOL)muted {
    [_session post:^{
        if (!_active || !_haveCall || !_joinSent || _selfMuted == muted) return;
        if (!muted && !_canUnmute) {
            [self publish];
            return;
        }
        BOOL previous = _selfMuted;
        NSUInteger generation = _generation;
        exteria_group_call_ref ref = _info.ref;
        exteria_peer_ref me;
        memset(&me, 0, sizeof(me));
        me.self = 1;
        me.kind = 1;
        _selfMuted = muted;
        [_runtime setMuted:muted];
        [self publish];
        [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_edit_request(arena, &ref, &me, 1, muted ? 1 : 0, 0, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            if (generation != _generation || !_active || result->status == EXTERIA_OK) return;
            NSLog(@"exteria: the microphone of the group call was refused: %@", ExteriaRpcErrorName(result));
            _selfMuted = previous;
            if (!muted) _canUnmute = NO;
            [_runtime setMuted:previous];
            [self publish];
        }];
    }];
}

- (void)setMember:(ExteriaGroupMember *)member muted:(BOOL)muted {
    long long peerId = member.peerId;
    int kind = member.peerKind;
    [_session post:^{
        if (!_active || !_haveCall || !(_info.creator || _info.can_change_join_muted)) return;
        ExteriaGroupMember *known = [_members objectForKey:ExteriaMemberKey(kind, peerId)];
        ExteriaPerson *person = kind == 1 ? [_session storedPersonWithKey:peerId] : nil;
        if (!known || known.isSelf) return;
        exteria_group_call_ref ref = _info.ref;
        exteria_peer_ref peer;
        memset(&peer, 0, sizeof(peer));
        peer.kind = kind;
        peer.id = peerId;
        peer.access_hash = (int64_t)person.accessHash;
        [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_edit_request(arena, &ref, &peer, 1, muted ? 1 : 0, 0, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            if (result->status != EXTERIA_OK) NSLog(@"exteria: muting a member of the group call failed: %@", ExteriaRpcErrorName(result));
        }];
    }];
}

- (void)setMember:(ExteriaGroupMember *)member volume:(int)volume {
    long long peerId = member.peerId;
    int kind = member.peerKind;
    volume = MAX(1, MIN(EXTERIA_GROUP_VOLUME_MAX, volume));
    [_session post:^{
        if (!_active || !_haveCall) return;
        NSString *key = ExteriaMemberKey(kind, peerId);
        ExteriaGroupMember *known = [_members objectForKey:key];
        ExteriaPerson *person = kind == 1 ? [_session storedPersonWithKey:peerId] : nil;
        if (!known || known.isSelf) return;
        /* heard at once; the answer of the server only keeps it for the next join */
        [_runtime setVolume:(float)volume / (float)EXTERIA_GROUP_VOLUME_DEFAULT forSource:known.source];
        [_members setObject:[[[ExteriaGroupMember alloc] initWithPeerId:known.peerId kind:known.peerKind source:known.source name:known.name photo:known.photo
                                                                 muted:known.muted self:NO speaking:known.speaking canSelfUnmute:known.canSelfUnmute
                                                            mutedByYou:known.mutedByYou volume:volume activeDate:known.activeDate] autorelease] forKey:key];
        [self publish];
        exteria_group_call_ref ref = _info.ref;
        exteria_peer_ref peer;
        memset(&peer, 0, sizeof(peer));
        peer.kind = kind;
        peer.id = peerId;
        peer.access_hash = (int64_t)person.accessHash;
        [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_edit_request(arena, &ref, &peer, 0, 0, volume, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            if (result->status != EXTERIA_OK) NSLog(@"exteria: the volume of a member of the group call was refused: %@", ExteriaRpcErrorName(result));
        }];
    }];
}

- (void)loadInviteLink:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    ExteriaSession *session = _session;
    [_session post:^{
        if (!_active || !_haveCall) {
            [session deliverMain:^{ done(nil, @"NOCALL"); [done release]; }];
            return;
        }
        exteria_group_call_ref ref = _info.ref;
        [session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_invite_link_request(arena, &ref, 1, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            char link[EXTERIA_GROUP_LINK_MAX];
            exteria_status status = result->status == EXTERIA_OK ? exteria_group_invite_link_parse(result->value, link, sizeof(link)) : result->status;
            NSString *text = status == EXTERIA_OK ? [NSString stringWithUTF8String:link] : nil;
            NSString *error = status == EXTERIA_OK ? nil : (result->status == EXTERIA_OK ? @"INTERNAL" : ExteriaRpcErrorName(result));
            [session deliverMain:^{ done(text, error); [done release]; }];
        }];
    }];
}

#pragma mark keeping in

/* every so often the server is asked whether it still has this phone in the call; one that dropped it (a long silence, a kick) ends the call here too */
- (void)scheduleCheck {
    [self afterSeconds:CHECK_SECONDS do:^{
        if (!_runtime || !_haveCall) return;
        NSUInteger generation = _generation;
        exteria_group_call_ref ref = _info.ref;
        int32_t source = (int32_t)_runtime.ssrc;
        [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_check_request(arena, &ref, &source, 1, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            if (generation != _generation || !_active) return;
            int present = 1;
            if (result->status == EXTERIA_OK && exteria_group_check_parse(result->value, source, &present) == EXTERIA_OK && !present) {
                [self finishWithEnd:ExteriaGroupEndRemoved error:nil leaveRequest:NO discard:NO];
                return;
            }
            /* the list of members is read again with it, which also repairs an update that never came */
            [self refreshMembersThen:nil];
            [self scheduleCheck];
        }];
    }];
}

#pragma mark ending

- (void)finishWithEnd:(ExteriaGroupEnd)end error:(NSString *)error leaveRequest:(BOOL)leave discard:(BOOL)discard {
    exteria_group_call_ref ref = _info.ref;
    uint32_t source = _runtime ? _runtime.ssrc : 0;
    BOOL joined = _joinSent && _haveCall;
    ++_generation;
    [_runtime stop];
    [_runtime release];
    _runtime = nil;
    _active = NO;
    _phase = ExteriaGroupPhaseEnded;
    if (_haveCall && discard) {
        [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_discard_request(arena, &ref, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            if (result->status != EXTERIA_OK) NSLog(@"exteria: phone.discardGroupCall failed: %@", ExteriaRpcErrorName(result));
        }];
    } else if (leave && joined) {
        [_session submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_group_leave_request(arena, &ref, source, request);
        } handler:^(const exteria_mt_rpc_result *result) {
            if (result->status != EXTERIA_OK) NSLog(@"exteria: phone.leaveGroupCall failed: %@", ExteriaRpcErrorName(result));
        }];
    }
    [_members removeAllObjects];
    [self publishEnd:end error:error];
}

@end
