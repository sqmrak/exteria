#import "exteria_group_call_state.h"

@implementation ExteriaGroupMember

@synthesize peerId = _peerId;
@synthesize peerKind = _peerKind;
@synthesize source = _source;
@synthesize name = _name;
@synthesize photo = _photo;
@synthesize muted = _muted;
@synthesize isSelf = _self;
@synthesize speaking = _speaking;
@synthesize canSelfUnmute = _canSelfUnmute;
@synthesize mutedByYou = _mutedByYou;
@synthesize volume = _volume;
@synthesize activeDate = _activeDate;

- (id)initWithPeerId:(long long)peerId kind:(int)kind source:(uint32_t)source name:(NSString *)name photo:(ExteriaPhoto *)photo muted:(BOOL)muted self:(BOOL)isSelf
            speaking:(BOOL)speaking canSelfUnmute:(BOOL)canSelfUnmute mutedByYou:(BOOL)mutedByYou volume:(int)volume activeDate:(int)activeDate {
    self = [super init];
    if (!self) return nil;
    _peerId = peerId;
    _peerKind = kind;
    _source = source;
    _name = [name copy];
    _photo = [photo retain];
    _muted = muted;
    _self = isSelf;
    _speaking = speaking;
    _canSelfUnmute = canSelfUnmute;
    _mutedByYou = mutedByYou;
    _volume = volume;
    _activeDate = activeDate;
    return self;
}

- (void)dealloc {
    [_name release];
    [_photo release];
    [super dealloc];
}

@end

@implementation ExteriaGroupCall

@synthesize callId = _callId;
@synthesize title = _title;
@synthesize chatTitle = _chatTitle;
@synthesize participantsCount = _participantsCount;
@synthesize phase = _phase;
@synthesize end = _end;
@synthesize muted = _muted;
@synthesize canUnmute = _canUnmute;
@synthesize canManage = _canManage;
@synthesize selfSpeaking = _selfSpeaking;
@synthesize startedAt = _startedAt;
@synthesize members = _members;
@synthesize error = _error;

- (id)initWithCallId:(long long)callId title:(NSString *)title chatTitle:(NSString *)chatTitle count:(int)count phase:(ExteriaGroupPhase)phase end:(ExteriaGroupEnd)end
               muted:(BOOL)muted canUnmute:(BOOL)canUnmute canManage:(BOOL)canManage selfSpeaking:(BOOL)selfSpeaking startedAt:(NSTimeInterval)startedAt
             members:(NSArray *)members error:(NSString *)error {
    self = [super init];
    if (!self) return nil;
    _callId = callId;
    _title = [title copy];
    _chatTitle = [chatTitle copy];
    _participantsCount = count;
    _phase = phase;
    _end = end;
    _muted = muted;
    _canUnmute = canUnmute;
    _canManage = canManage;
    _selfSpeaking = selfSpeaking;
    _startedAt = startedAt;
    _members = [members retain];
    _error = [error copy];
    return self;
}

- (void)dealloc {
    [_title release];
    [_chatTitle release];
    [_members release];
    [_error release];
    [super dealloc];
}

@end

@implementation ExteriaVoiceChat

@synthesize callId = _callId;
@synthesize title = _title;
@synthesize participantsCount = _participantsCount;
@synthesize joinable = _joinable;

- (id)initWithCallId:(long long)callId title:(NSString *)title count:(int)count joinable:(BOOL)joinable {
    self = [super init];
    if (!self) return nil;
    _callId = callId;
    _title = [title copy];
    _participantsCount = count;
    _joinable = joinable;
    return self;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

@end
