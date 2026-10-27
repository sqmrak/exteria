#import "exteria_session_folders.h"
#import "exteria_session.h"

#import "exteria_dialog.h"
#import "exteria_files.h"
#import "exteria_media_link.h"
#import "exteria_photo.h"
#import "exteria_person.h"
#import "exteria_remote_file.h"
#import "exteria_notifier.h"
#import "exteria_voip_socket.h"
#import "exteria_session_internal.h"
#import "exteria_session_drafts.h"
#import "exteria_rpc.h"
#import "exteria_call_engine.h"

#import <UIKit/UIKit.h>
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

#include <limits.h>

#include "exteria_client.h"
#include "exteria_credentials.h"
#include "exteria_device.h"
#include "exteria_dialogs.h"
#include "exteria_people.h"
#include "exteria_mt_socket.h"
#include <sys/socket.h>
#include "exteria_session_file.h"
#include "exteria_tl_ids.h"

#define CONNECT_TIMEOUT_MS 10000
#define WRITE_TIMEOUT_MS 15000
/* consecutive failed connections before the worker reports the device offline; a signed in link keeps trying, a login stops */
#define RETRY_LIMIT 4
/* the longest pause between two attempts of a link that keeps trying */
#define RETRY_PAUSE_MAX_MS 30000u
/* the longest sleep between ticks; the client names its own next deadline (ping, pong, request timeouts, login
   waits), commands and a stop come through the wake pipe */
#define POLL_CAP_MS 60000
#define READ_CHUNK 16384
#define READS_PER_WAKE 64
/* the server reports an unknown auth key as a transport error with this code */
#define TRANSPORT_AUTH_KEY_UNKNOWN (-404)
#define RPC_TIMEOUT_MS 30000
#define DIALOGS_PER_REQUEST 100

@interface ExteriaAuthEvent ()
- (id)initWithKind:(ExteriaAuthEventKind)kind;
- (void)setCodeKind:(ExteriaCodeKind)kind length:(NSInteger)length resendAfter:(NSInteger)resendAfter;
- (void)setHint:(NSString *)hint;
- (void)setHasRecovery:(BOOL)has;
- (void)setEmailPattern:(NSString *)pattern;
- (void)setErrorName:(NSString *)name number:(NSInteger)number;
- (void)setUserId:(long long)userId;
- (void)setQrUrl:(NSString *)url expires:(NSTimeInterval)expires;
@end

@implementation ExteriaAuthEvent

@synthesize kind = _kind;
@synthesize codeKind = _codeKind;
@synthesize codeLength = _codeLength;
@synthesize resendAfter = _resendAfter;
@synthesize errorNumber = _errorNumber;
@synthesize hint = _hint;
@synthesize errorName = _errorName;
@synthesize userId = _userId;
@synthesize hasRecovery = _hasRecovery;
@synthesize emailPattern = _emailPattern;
@synthesize qrUrl = _qrUrl;
@synthesize qrExpires = _qrExpires;

- (id)initWithKind:(ExteriaAuthEventKind)kind {
    self = [super init];
    if (!self) return nil;
    _kind = kind;
    _resendAfter = -1;
    return self;
}

- (void)setCodeKind:(ExteriaCodeKind)kind length:(NSInteger)length resendAfter:(NSInteger)resendAfter {
    _codeKind = kind;
    _codeLength = length;
    _resendAfter = resendAfter;
}

- (void)setHint:(NSString *)hint {
    if (hint == _hint) return;
    [_hint release];
    _hint = [hint copy];
}

- (void)setHasRecovery:(BOOL)has {
    _hasRecovery = has;
}

- (void)setEmailPattern:(NSString *)pattern {
    if (pattern == _emailPattern) return;
    [_emailPattern release];
    _emailPattern = [pattern copy];
}

- (void)setErrorName:(NSString *)name number:(NSInteger)number {
    [_errorName release];
    _errorName = [name copy];
    _errorNumber = number;
}

- (void)setUserId:(long long)userId {
    _userId = userId;
}

- (void)setQrUrl:(NSString *)url expires:(NSTimeInterval)expires {
    if (url != _qrUrl) {
        [_qrUrl release];
        _qrUrl = [url copy];
    }
    _qrExpires = expires;
}

- (void)dealloc {
    [_emailPattern release];
    [_hint release];
    [_errorName release];
    [_qrUrl release];
    [super dealloc];
}

@end

@interface ExteriaSession () {
    NSString *_directory;
    ExteriaPerson *_ownPerson;
    BOOL _ownPersonRead;
    NSLock *_lock;
    NSMutableArray *_commands;
    int _wake[2];
    dispatch_semaphore_t _exited;
    BOOL _started;
    BOOL _stopping;
    BOOL _connected;

    /* everything below belongs to the worker thread */
    exteria_client _client;
    BOOL _clientLive;
    BOOL _linkReported;
    exteria_mt_socket _socket;
    exteria_store *_store;
    int32_t _dc;
    unsigned _failures;
    uint32_t _pingInterval;
    uint64_t _retryAt;
    BOOL _wantLink;
    int32_t _migrateDc;
    BOOL _dropKeyPending;
    BOOL _archiveLoading;
    int64_t _authorizedAccount;
    int64_t _account;
    NSMutableDictionary *_handlers;
    NSMutableDictionary *_links;
    NSMutableDictionary *_storeObservers;
    /* who put the observer there, compared by address and never used: a screen that is gone must not remove the observer of the one that took its place */
    void (^_changeHook)(void);
    void *_voip;
    ExteriaShiro *_shiro;
    ExteriaTypingBoard *_typing;
    NSMutableDictionary *_readOutbox;
    ExteriaCallEngine *_calls;
    NSString *_deviceModel;
    NSString *_systemVersion;
    NSString *_appVersion;
    NSString *_langCode;
    /* the client keeps these pointers for its whole life and rebuilds its handshake preamble from them after a
       data center change */
    char *_cDeviceModel;
    char *_cSystemVersion;
    char *_cAppVersion;
    char *_cLangCode;
}
@end

NSString *const ExteriaArchiveSummaryDidChangeNotification = @"ExteriaArchiveSummaryDidChange";

NSString *const ExteriaSessionConnectionDidChangeNotification = @"ExteriaSessionConnectionDidChange";

@implementation ExteriaSession

@synthesize delegate = _delegate;
@synthesize connected = _connected;
@synthesize callDelegate = _callDelegate;
@synthesize directory = _directory;
@synthesize shiro = _shiro;
@synthesize typing = _typing;
@synthesize drafts = _drafts;

NSString *const ExteriaReadOutboxDidChangeNotification = @"ExteriaReadOutboxDidChange";

- (int32_t)readOutboxOfKind:(int32_t)kind peer:(long long)peer {
    return [[_readOutbox objectForKey:[NSString stringWithFormat:@"%d:%lld", (int)kind, peer]] intValue];
}

- (void)noteReadOutbox:(int32_t)maxId ofKind:(int32_t)kind peer:(long long)peer {
    if (!_readOutbox) _readOutbox = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithFormat:@"%d:%lld", (int)kind, peer];
    if ([[_readOutbox objectForKey:key] intValue] >= maxId) return;
    [_readOutbox setObject:[NSNumber numberWithInt:maxId] forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaReadOutboxDidChangeNotification object:self
        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kind], @"kind", [NSNumber numberWithLongLong:peer], @"peer", [NSNumber numberWithInt:maxId], @"maxId", nil]];
}

static uint64_t ExteriaNowMs(void) {
    return exteria_system_clock.monotonic_ms(NULL);
}

+ (BOOL)hasAccountInDirectory:(NSString *)directory {
    uint8_t buf[EXTERIA_ACCOUNT_FILE_LEN + 1];
    size_t len;
    int32_t dc;
    int64_t account;
    if (ExteriaReadFile(ExteriaAccountPath(directory), buf, sizeof(buf), &len) != EXTERIA_OK) return NO;
    return exteria_account_unpack(buf, len, &dc, &account) == EXTERIA_OK;
}

+ (long long)accountIdInDirectory:(NSString *)directory {
    uint8_t buf[EXTERIA_ACCOUNT_FILE_LEN + 1];
    size_t len;
    int32_t dc;
    int64_t account = 0;
    if (ExteriaReadFile(ExteriaAccountPath(directory), buf, sizeof(buf), &len) != EXTERIA_OK) return 0;
    if (exteria_account_unpack(buf, len, &dc, &account) != EXTERIA_OK) return 0;
    return account;
}

static NSString *ExteriaMachineName(void) {
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0 || size > 64) return nil;
    char name[64];
    if (sysctlbyname("hw.machine", name, &size, NULL, 0) != 0) return nil;
    name[sizeof(name) - 1] = '\0';
    return [NSString stringWithUTF8String:name];
}

- (id)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _directory = [directory copy];
    _lock = [[NSLock alloc] init];
    _commands = [[NSMutableArray alloc] init];
    _handlers = [[NSMutableDictionary alloc] init];
    _links = [[NSMutableDictionary alloc] init];
    _typing = [[ExteriaTypingBoard alloc] init];
    _drafts = [[ExteriaDraftBoard alloc] init];
    _calls = [[ExteriaCallEngine alloc] initWithSession:self];
    _wake[0] = _wake[1] = -1;
    exteria_mt_socket_init(&_socket);
    _exited = dispatch_semaphore_create(0);
    UIDevice *device = [UIDevice currentDevice];
    NSString *machine = ExteriaMachineName();
    const char *marketing = exteria_device_name(machine.UTF8String);
    _deviceModel = [(marketing ? [NSString stringWithUTF8String:marketing] : (machine ? machine : device.model)) copy];
    _systemVersion = [[NSString stringWithFormat:@"%@ %@", device.systemName, device.systemVersion] copy];
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    _appVersion = [(version ? version : @"") copy];
    NSString *language = [[NSLocale preferredLanguages] count] ? [[NSLocale preferredLanguages] objectAtIndex:0] : @"en";
    NSRange dash = [language rangeOfString:@"-"];
    _langCode = [(dash.location == NSNotFound ? language : [language substringToIndex:dash.location]) copy];
    _cDeviceModel = strdup(_deviceModel.UTF8String);
    _cSystemVersion = strdup(_systemVersion.UTF8String);
    _cAppVersion = strdup(_appVersion.UTF8String);
    _cLangCode = strdup(_langCode.UTF8String);
    return self;
}

- (void)dealloc {
    for (int i = 0; i < 2; ++i) if (_wake[i] >= 0) close(_wake[i]);
    [_sendAsChoices release];
    [_chatFolders release];
    if (_exited) dispatch_release(_exited);
    [_directory release];
    [_ownPerson release];
    [_lock release];
    [_commands release];
    [_handlers release];
    [_links release];
    [_typing release];
    [_drafts release];
    [_calls release];
    [_storeObservers release];
    [_deviceModel release];
    [_systemVersion release];
    [_appVersion release];
    [_langCode release];
    free(_cDeviceModel);
    free(_cSystemVersion);
    free(_cAppVersion);
    free(_cLangCode);
    [_readOutbox release];
    [super dealloc];
}

#pragma mark calls

/* a bot has no phone: the server refuses the call, and no screen offers one, so a call that gets here from a list that did not know the bot is stopped */
- (void)startCallToDialog:(ExteriaDialog *)dialog {
    if (dialog.kind == EXTERIA_DIALOG_BOT) {
        NSLog(@"exteria: a call to the bot %lld was not started", dialog.peerId);
        return;
    }
    [_calls startCallToDialog:dialog];
}

- (void)startVideoCallToDialog:(ExteriaDialog *)dialog {
    if (dialog.kind == EXTERIA_DIALOG_BOT) {
        NSLog(@"exteria: a video call to the bot %lld was not started", dialog.peerId);
        return;
    }
    [_calls startCallToDialog:dialog video:YES];
}
- (void)acceptCall { [_calls acceptIncoming]; }
- (void)declineCall { [_calls declineIncoming]; }
- (void)hangUpCall { [_calls hangUp]; }
- (void)setCallMuted:(BOOL)muted { [_calls setMuted:muted]; }
- (void)setCallCameraOn:(BOOL)on { [_calls setCameraOn:on]; }
- (ExteriaCallVideo *)activeCallVideo { return [_calls activeVideo]; }

#pragma mark delivery

- (void)deliver:(ExteriaAuthEvent *)event {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate session:self didReceiveAuthEvent:event];
    });
}

- (void)deliverKind:(ExteriaAuthEventKind)kind {
    [self deliver:[[[ExteriaAuthEvent alloc] initWithKind:kind] autorelease]];
}

- (void)deliverFailure:(NSString *)name number:(NSInteger)number {
    ExteriaAuthEvent *event = [[[ExteriaAuthEvent alloc] initWithKind:ExteriaAuthEventFailed] autorelease];
    [event setErrorName:name number:number];
    [self deliver:event];
}

#pragma mark commands

- (void)post:(void (^)(void))block {
    [_lock lock];
    [_commands addObject:[[block copy] autorelease]];
    [_lock unlock];
    char byte = 1;
    /* a full pipe already holds a wake up, so a short write loses nothing */
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"exteria: session wake up failed, errno %d", errno);
}

- (void)afterPendingWork:(void (^)(void))block {
    void (^done)(void) = [block copy];
    [self post:^{
        dispatch_async(dispatch_get_main_queue(), ^{ done(); [done release]; });
    }];
}

- (void)start {
    [_lock lock];
    if (_started) {
        [_lock unlock];
        return;
    }
    _started = YES;
    [_lock unlock];
    if (pipe(_wake) != 0) {
        NSLog(@"exteria: session pipe failed, errno %d", errno);
        _wake[0] = _wake[1] = -1;
        [self deliverFailure:@"INTERNAL" number:0];
        return;
    }
    for (int i = 0; i < 2; ++i) {
        fcntl(_wake[i], F_SETFL, fcntl(_wake[i], F_GETFL, 0) | O_NONBLOCK);
        fcntl(_wake[i], F_SETFD, FD_CLOEXEC);
    }
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
}

- (void)stop {
    [_lock lock];
    BOOL running = _started && !_stopping && _wake[1] >= 0;
    _stopping = YES;
    [_lock unlock];
    if (!running) return;
    char byte = 1;
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"exteria: session stop wake up failed, errno %d", errno);
    dispatch_semaphore_wait(_exited, DISPATCH_TIME_FOREVER);
}

- (BOOL)isStopping {
    [_lock lock];
    BOOL stopping = _stopping;
    [_lock unlock];
    return stopping;
}

- (void)routeChanged {
    [self post:^{
        /* a media link made on the old path would go on using it, so the next download makes a new one */
        for (ExteriaMediaLink *link in [_links allValues]) [link stop];
        [_links removeAllObjects];
        if (_socket.fd >= 0) {
            [self closeSocket];
            if (_clientLive) exteria_client_disconnected(&_client);
        }
        _failures = 0;
        _retryAt = 0;
    }];
}

- (void)setPingInterval:(uint32_t)milliseconds {
    [self post:^{
        _pingInterval = milliseconds;
        if (_clientLive) exteria_mt_client_set_ping_interval(&_client.mt, milliseconds ? milliseconds : EXTERIA_MT_PING_INTERVAL_DEFAULT);
    }];
}

- (void)reconnect {
    [self post:^{
        _failures = 0;
        _retryAt = 0;
        _wantLink = YES;
    }];
}

/* auth calls run on the worker; a session whose client never started answers with a failure instead of crashing */
- (void)authCommand:(const char *)boundary action:(exteria_status (^)(exteria_auth *auth))action {
    [self post:^{
        if (!_clientLive) {
            [self authCallFailed:EXTERIA_E_STATE boundary:boundary];
            return;
        }
        [self linkWanted];
        exteria_status status = action(&_client.auth);
        if (status != EXTERIA_OK) [self authCallFailed:status boundary:boundary];
    }];
}

- (void)requestCodeForNumber:(NSString *)number {
    NSString *copy = [number copy];
    [self authCommand:"phone" action:^exteria_status(exteria_auth *auth) {
        return exteria_auth_phone(auth, copy.UTF8String, NULL);
    }];
    [copy release];
}

- (void)submitCode:(NSString *)code {
    NSString *copy = [code copy];
    [self authCommand:"code" action:^exteria_status(exteria_auth *auth) {
        return exteria_auth_code(auth, copy.UTF8String, NULL);
    }];
    [copy release];
}

- (void)requestQrLogin {
    [self authCommand:"qr" action:^exteria_status(exteria_auth *auth) {
        return exteria_auth_qr(auth, NULL, 0);
    }];
}

- (void)resendCode {
    [self authCommand:"resend" action:^exteria_status(exteria_auth *auth) {
        return exteria_auth_resend(auth, NULL);
    }];
}

- (void)submitPassword:(NSString *)password {
    NSString *copy = [password copy];
    [self authCommand:"password" action:^exteria_status(exteria_auth *auth) {
        const char *bytes = copy.UTF8String;
        return exteria_auth_password(auth, (const uint8_t *)bytes, strlen(bytes));
    }];
    [copy release];
}

- (void)requestPasswordRecovery {
    [self authCommand:"recovery" action:^exteria_status(exteria_auth *auth) {
        return exteria_auth_recovery(auth);
    }];
}

- (void)submitRecoveryCode:(NSString *)code {
    NSString *copy = [code copy];
    [self authCommand:"recover code" action:^exteria_status(exteria_auth *auth) {
        return exteria_auth_recover_code(auth, copy.UTF8String);
    }];
    [copy release];
}

- (void)submitFirstName:(NSString *)first lastName:(NSString *)last {
    NSString *firstCopy = [first copy];
    NSString *lastCopy = [last copy];
    [self authCommand:"signup" action:^exteria_status(exteria_auth *auth) {
        return exteria_auth_signup(auth, firstCopy.UTF8String, lastCopy.UTF8String);
    }];
    [firstCopy release];
    [lastCopy release];
}

- (void)cancelLogin {
    [self post:^{
        if (_clientLive) exteria_auth_cancel(&_client.auth);
    }];
}

/* an argument or state error means the screen sent something the state machine cannot take */
- (void)authCallFailed:(exteria_status)status boundary:(const char *)boundary {
    NSLog(@"exteria: auth %s rejected locally: %s", boundary, exteria_status_name(status));
    [self deliverFailure:@"INTERNAL" number:status];
}

#pragma mark requests

/* runs on the worker: the handler gets the result there, and an arena that is already gone, so it must copy what
   it keeps */
- (void)invoke:(const char *)method configure:(exteria_status (^)(exteria_arena *arena, exteria_tl_value *request))configure
       handler:(void (^)(const exteria_mt_rpc_result *result))handler {
    void (^copy)(const exteria_mt_rpc_result *) = [handler copy];
    exteria_status (^configureCopy)(exteria_arena *, exteria_tl_value *) = [configure copy];
    [self post:^{
        [self submit:method configure:configureCopy handler:copy];
    }];
    [copy release];
    [configureCopy release];
}

/* the same for a request that a builder in the core makes whole, so that it reaches the worker like any other */
- (void)invokeBuilt:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build
            handler:(void (^)(const exteria_mt_rpc_result *result))handler {
    void (^copy)(const exteria_mt_rpc_result *) = [handler copy];
    exteria_status (^buildCopy)(exteria_arena *, exteria_tl_value **) = [build copy];
    [self post:^{
        [self submitBuilt:buildCopy handler:copy];
    }];
    [copy release];
    [buildCopy release];
}

/* worker only: the same, for code that already runs there */
- (void)submit:(const char *)method configure:(exteria_status (^)(exteria_arena *arena, exteria_tl_value *request))configure
       handler:(void (^)(const exteria_mt_rpc_result *result))handler {
    [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **out) {
        *out = exteria_tl_new_obj(arena, method);
        return *out ? configure(arena, *out) : EXTERIA_E_NOMEM;
    } handler:handler];
}

- (void)submitBuilt:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build
            handler:(void (^)(const exteria_mt_rpc_result *result))handler {
    exteria_arena arena;
    exteria_tl_value *request = NULL;
    uint64_t id = 0;
    exteria_status status = EXTERIA_E_STATE;
    /* the limit is a ceiling, nothing is reserved: an upload part of 128 KB and its copy in the request need more than 64 KB */
    exteria_arena_init(&arena, 512u * 1024u);
    if (_clientLive) status = build(&arena, &request);
    if (request && status == EXTERIA_OK) {
        [self linkWanted];
        status = exteria_client_request(&_client, request, RPC_TIMEOUT_MS, &id);
    } else if (status == EXTERIA_OK) {
        status = EXTERIA_E_ARG;
    }
    exteria_arena_free(&arena);
    if (status == EXTERIA_OK) {
        [_handlers setObject:[[handler copy] autorelease] forKey:[NSNumber numberWithUnsignedLongLong:id]];
    } else {
        exteria_mt_rpc_result failed;
        memset(&failed, 0, sizeof(failed));
        failed.status = status;
        handler(&failed);
    }
}

- (void)noteRpcError:(NSString *)error {
    if (ExteriaIsRevokedError(error)) _dropKeyPending = YES;
}

- (exteria_store *)workerStore {
    return _store;
}

- (void)setKeepMask:(uint32_t)mask {
    _client.updates.keep = mask;
}

/* a message that only came in a history page is not in the store, so the server telling that it is gone would
   leave nothing to keep */
- (void)keepMessagesOfAnswer:(const exteria_tl_value *)answer {
    if (!_store || !(_client.updates.keep & EXTERIA_KEEP_DELETED)) return;
    const exteria_tl_value *list = exteria_tl_get(answer, "messages");
    if (!list || list->kind != EXTERIA_TL_V_VEC) return;
    /* the store syncs to disk at every commit, so a page written message by message held this thread, and every answer behind it, for seconds */
    BOOL batched = exteria_store_begin(_store) == EXTERIA_OK;
    for (uint32_t i = 0; i < list->u.vec.count; ++i) {
        const exteria_tl_value *item = list->u.vec.items[i];
        if (!exteria_tl_is(item, EXTERIA_TL_ID_message) && !exteria_tl_is(item, EXTERIA_TL_ID_messageService)) continue;
        exteria_status status = exteria_updates_cache_message(&_client.updates, item);
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: a message of a history page was not kept: %s", exteria_status_name(status));
            break;
        }
    }
    if (batched && exteria_store_commit(_store) != EXTERIA_OK) NSLog(@"exteria: the history page was not committed");
}

- (int64_t)workerAccount {
    return _account;
}

- (int32_t)workerDc {
    return _dc;
}

- (void)setStoreObserver:(void (^)(void))observer {
    [self setStoreObserver:observer owner:NULL];
}

- (void)setStoreObserver:(void (^)(void))observer owner:(void *)owner {
    if (!_storeObservers) _storeObservers = [[NSMutableDictionary alloc] init];
    NSValue *key = [NSValue valueWithPointer:owner];
    if (observer) {
        void (^copied)(void) = [observer copy];
        [_storeObservers setObject:copied forKey:key];
        [copied release];
    } else [_storeObservers removeObjectForKey:key];
}

- (void)clearStoreObserverOwnedBy:(void *)owner {
    if (owner) [_storeObservers removeObjectForKey:[NSValue valueWithPointer:owner]];
}

- (void)setChangeHook:(void (^)(void))hook {
    void (^old)(void) = _changeHook;
    _changeHook = [hook copy];
    [old release];
}

- (NSString *)workerDirectory {
    return _directory;
}

- (void)storeChanged {
    if (_store) {
        NSArray *observers = [[_storeObservers allValues] copy];
        for (void (^observer)(void) in observers) observer();
        [observers release];
    }
    /* presence and typing change nothing a notification could say, and a contact list sends them all day */
    if (_changeHook && _store && !(_clientLive && _client.change_quiet)) _changeHook();
}

/* hands a finished load to the main thread; a dropped key also queues the client restart */
- (void)finishLoad:(NSArray *)items error:(NSString *)error completion:(ExteriaListCompletion)done {
    /* the client is still inside its own callback, so the restart waits for settleClient */
    if (ExteriaIsRevokedError(error)) _dropKeyPending = YES;
    NSArray *delivered = [[items copy] autorelease];
    NSString *deliveredError = [[error copy] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{ done(delivered, deliveredError); });
}

/* parse turns the answer into model objects, or returns nil and sets *error to the name the screen shows */
- (void)load:(const char *)method configure:(exteria_status (^)(exteria_arena *, exteria_tl_value *))configure
       parse:(NSArray * (^)(const exteria_tl_value *answer))parse completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invoke:method configure:configure handler:^(const exteria_mt_rpc_result *result) {
        NSArray *items = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
            if (strcmp(method, "messages.getDialogs") == 0) {
                error = ExteriaDownloadErrorName(result);
                [self rememberFolderFloodError:error];
            }
        } else {
            items = parse(result->value);
            if (!items) {
                NSLog(@"exteria: %s answer rejected", method);
                error = @"INTERNAL";
            }
        }
        [self finishLoad:items error:error completion:done];
    }];
    [done release];
}

- (void)loadDialogs:(ExteriaListCompletion)completion {
    [self loadDialogsInFolder:0 completion:completion];
}

static exteria_status ExteriaConfigureDialogList(exteria_arena *arena, exteria_tl_value *request, int32_t folder) {
    exteria_tl_value *empty = exteria_tl_new_obj(arena, "inputPeerEmpty");
    if (!empty) return EXTERIA_E_NOMEM;
    exteria_status status = exteria_tl_set(request, "offset_peer", empty);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_date", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "offset_id", 0);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", DIALOGS_PER_REQUEST);
    /* folder 0 excludes archived chats, its optional archive shortcut is restored after parsing */
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "folder_id", folder);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "hash", 0);
    return status;
}

- (void)loadDialogsInFolder:(int32_t)folder completion:(ExteriaListCompletion)completion {
    NSString *wait = [self folderFloodError];
    if (wait) {
        if (completion) completion(nil, wait);
        return;
    }
    [self load:"messages.getDialogs" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
        return ExteriaConfigureDialogList(arena, request, folder);
    } parse:^NSArray *(const exteria_tl_value *answer) {
        NSArray *dialogs = [self dialogsFromAnswer:answer folder:folder];
        NSUInteger folders = 0;
        for (ExteriaDialog *entry in dialogs) if (entry.folder) ++folders;
        NSLog(@"exteria: chat list of folder %d: %lu rows, %lu archive entries", (int)folder, (unsigned long)dialogs.count, (unsigned long)folders);
        /* the whole answer is kept so the list opens at once next time, before the network answers */
        if (dialogs) {
            exteria_peer none = {0, 0};
            exteria_status status = exteria_store_put([self workerStore], EXTERIA_RECORD_DIALOG, none, (int64_t)folder + 1, answer);
            if (status != EXTERIA_OK) NSLog(@"exteria: cannot keep the chat list of folder %d: %s", (int)folder, exteria_status_name(status));
        }
        if (dialogs && folder == 0) [self refreshArchiveSummary];
        if (dialogs) {
            [self noteDraftsOfDialogsAnswer:answer complete:YES];
            if (folder == 0) [self requestAllDraftsOnce];
        }
        return dialogs;
    } completion:completion];
}

- (NSArray *)dialogsFromAnswer:(const exteria_tl_value *)answer folder:(int32_t)folder {
    exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX + 1, sizeof(*rows));
    size_t count = 0;
    NSMutableArray *dialogs = nil;
    if (rows && exteria_dialogs_parse(answer, _account, (int32_t)[[NSDate date] timeIntervalSince1970],
                                      rows, EXTERIA_DIALOGS_MAX, &count) == EXTERIA_OK) {
        if (folder == 0 && exteria_dialogs_ensure_archive(rows, EXTERIA_DIALOGS_MAX + 1, &count) != EXTERIA_OK) {
            NSLog(@"exteria: archive shortcut could not be inserted");
            free(rows);
            return nil;
        }
        exteria_dialog_row summary;
        if (folder == 0 && [self readArchiveSummary:&summary]) {
            for (size_t i = 0; i < count; ++i) if (rows[i].folder && rows[i].folder_id == 1) rows[i] = summary;
        }
        dialogs = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) {
            if (!rows[i].folder && rows[i].folder_id != folder) continue;
            if (rows[i].folder && folder != 0) continue;
            [dialogs addObject:[[[ExteriaDialog alloc] initWithRow:&rows[i]] autorelease]];
        }
    }
    free(rows);
    return dialogs;
}

/* negative list keys keep folder metadata separate from the folder's chat list */
#define EXTERIA_ARCHIVE_INFO_KEY (-2)

- (BOOL)readArchiveSummary:(exteria_dialog_row *)summary {
    exteria_arena arena;
    exteria_tl_value *info = NULL, *contents = NULL;
    exteria_peer none = {0, 0};
    exteria_arena_init(&arena, 16u * 1024u * 1024u);
    exteria_status status = exteria_store_get(_store, EXTERIA_RECORD_DIALOG, none, EXTERIA_ARCHIVE_INFO_KEY, &arena, &info);
    if (status == EXTERIA_OK) status = exteria_store_get(_store, EXTERIA_RECORD_DIALOG, none, 2, &arena, &contents);
    if (status == EXTERIA_OK) status = exteria_archive_summary_parse(info, contents, _account,
        (int32_t)[[NSDate date] timeIntervalSince1970], summary);
    if (status != EXTERIA_OK && status != EXTERIA_E_NOTFOUND) NSLog(@"exteria: cannot read archive summary: %s", exteria_status_name(status));
    exteria_arena_free(&arena);
    return status == EXTERIA_OK;
}

- (void)finishArchiveRefreshWithError:(NSString *)error {
    _archiveLoading = NO;
    [self noteRpcError:error];
    NSLog(@"exteria: archive summary refresh failed: %@", error);
}

- (void)refreshArchiveSummary {
    if (_archiveLoading || !_account) return;
    _archiveLoading = YES;
    int64_t account = _account;
    [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **out) {
        exteria_tl_value *request = exteria_tl_new_obj(arena, "messages.getPeerDialogs");
        exteria_tl_value *folder = exteria_tl_new_obj(arena, "inputDialogPeerFolder");
        exteria_tl_value *peers = exteria_tl_new_vec(arena, 1);
        if (!request || !folder || !peers) return EXTERIA_E_NOMEM;
        exteria_status status = exteria_tl_set_i32(arena, folder, "folder_id", 1);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(peers, 0, folder);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "peers", peers);
        if (status == EXTERIA_OK) *out = request;
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        if (account != _account) { _archiveLoading = NO; return; }
        if (result->status != EXTERIA_OK) { [self finishArchiveRefreshWithError:ExteriaRpcErrorName(result)]; return; }
        exteria_peer none = {0, 0};
        exteria_status status = exteria_store_put(_store, EXTERIA_RECORD_DIALOG, none, EXTERIA_ARCHIVE_INFO_KEY, result->value);
        if (status != EXTERIA_OK) { [self finishArchiveRefreshWithError:@"STORAGE"]; return; }
        [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **out) {
            exteria_tl_value *request = exteria_tl_new_obj(arena, "messages.getDialogs");
            if (!request) return EXTERIA_E_NOMEM;
            exteria_status built = ExteriaConfigureDialogList(arena, request, 1);
            if (built == EXTERIA_OK) *out = request;
            return built;
        } handler:^(const exteria_mt_rpc_result *contents) {
            _archiveLoading = NO;
            if (account != _account) return;
            if (contents->status != EXTERIA_OK) {
                NSString *error = ExteriaDownloadErrorName(contents);
                [self rememberFolderFloodError:error];
                [self finishArchiveRefreshWithError:error];
                return;
            }
            exteria_peer key = {0, 0};
            exteria_status kept = exteria_store_put(_store, EXTERIA_RECORD_DIALOG, key, 2, contents->value);
            if (kept != EXTERIA_OK) { [self finishArchiveRefreshWithError:@"STORAGE"]; return; }
            exteria_dialog_row row;
            if (![self readArchiveSummary:&row]) { [self finishArchiveRefreshWithError:@"INTERNAL"]; return; }
            ExteriaDialog *summary = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaArchiveSummaryDidChangeNotification object:self
                    userInfo:[NSDictionary dictionaryWithObject:summary forKey:@"dialog"]];
            });
        }];
    }];
}

- (void)loadCachedDialogsInFolder:(int32_t)folder completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self post:^{
        exteria_arena arena;
        exteria_tl_value *answer = NULL;
        exteria_peer none = {0, 0};
        NSArray *dialogs = nil;
        exteria_arena_init(&arena, 16u * 1024u * 1024u);
        exteria_status status = exteria_store_get([self workerStore], EXTERIA_RECORD_DIALOG, none, (int64_t)folder + 1, &arena, &answer);
        if (status == EXTERIA_OK) {
            dialogs = [self dialogsFromAnswer:answer folder:folder];
            if (dialogs) [self noteDraftsOfDialogsAnswer:answer complete:NO];
        } else if (status != EXTERIA_E_NOTFOUND) NSLog(@"exteria: cannot read the kept chat list: %s", exteria_status_name(status));
        exteria_arena_free(&arena);
        /* nothing kept is not an error, the screen just waits for the network */
        [self finishLoad:dialogs error:nil completion:done];
        [done release];
    }];
}

- (void)moveDialog:(ExteriaDialog *)dialog toFolder:(int32_t)folder completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    int32_t kind = dialog.peerKind;
    long long peerId = dialog.peerId, hash = dialog.peerHash;
    [self invoke:"folders.editPeerFolders" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
        static const char *const ctors[] = {NULL, "inputPeerUser", "inputPeerChat", "inputPeerChannel"};
        static const char *const fields[] = {NULL, "user_id", "chat_id", "channel_id"};
        if (kind < 1 || kind > 3 || (kind != 2 && hash == 0)) return EXTERIA_E_ARG;
        exteria_tl_value *peer = exteria_tl_new_obj(arena, ctors[kind]);
        exteria_tl_value *entry = exteria_tl_new_obj(arena, "inputFolderPeer");
        exteria_tl_value *list = exteria_tl_new_vec(arena, 1);
        if (!peer || !entry || !list) return EXTERIA_E_NOMEM;
        exteria_status status = exteria_tl_set_i64(arena, peer, fields[kind], peerId);
        if (status == EXTERIA_OK && kind != 2) status = exteria_tl_set_i64(arena, peer, "access_hash", hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(entry, "peer", peer);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, entry, "folder_id", folder);
        if (status == EXTERIA_OK) status = exteria_tl_vec_set(list, 0, entry);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "folder_peers", list);
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        NSLog(@"exteria: editPeerFolders of chat %lld to folder %d answered: %@", peerId, (int)folder, error ? error : @"ok");
        if (ExteriaIsRevokedError(error)) _dropKeyPending = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ done(error); });
    }];
    [done release];
}

- (void)createChannelTitled:(NSString *)title megagroup:(BOOL)megagroup completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *name = [title copy];
    [self invoke:"channels.createChannel" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
        exteria_status status = exteria_tl_set_flag(request, megagroup ? "megagroup" : "broadcast");
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "title", name.UTF8String);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "about", "");
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        NSLog(@"exteria: createChannel answered: %@", error ? error : @"ok");
        if (ExteriaIsRevokedError(error)) _dropKeyPending = YES;
        NSString *delivered = [[error copy] autorelease];
        dispatch_async(dispatch_get_main_queue(), ^{ done(delivered); [done release]; });
    }];
    [name release];
}

- (void)searchPeers:(NSString *)query completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    NSString *text = [query copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_found_request(arena, text.UTF8String, 30, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *dialogs = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX + 1, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_found_parse(result->value, _account, rows, EXTERIA_DIALOGS_MAX, &count) == EXTERIA_OK) {
                dialogs = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [dialogs addObject:[[[ExteriaDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: contacts.search answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:dialogs error:error completion:done];
        [done release];
    }];
    [text release];
}

- (void)loadContacts:(ExteriaListCompletion)completion {
    [self load:"contacts.getContacts" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
        return exteria_tl_set_i64(arena, request, "hash", 0);
    } parse:^NSArray *(const exteria_tl_value *answer) {
        exteria_person_row *rows = calloc(EXTERIA_PEOPLE_MAX, sizeof(*rows));
        size_t count = 0;
        NSMutableArray *people = nil;
        if (rows && exteria_contacts_parse(answer, rows, EXTERIA_PEOPLE_MAX, &count) == EXTERIA_OK) {
            people = [NSMutableArray arrayWithCapacity:count];
            for (size_t i = 0; i < count; ++i) [people addObject:[[[ExteriaPerson alloc] initWithRow:&rows[i]] autorelease]];
        }
        free(rows);
        return people;
    } completion:completion];
}

/* the own profile is kept in a small file of the account, a magic and the size of the row before the row itself, so a row of another build is not read */
#define OWN_PERSON_MAGIC 0x45584f50u

- (NSString *)ownPersonPath {
    return [_directory stringByAppendingPathComponent:@"own.person"];
}

- (ExteriaPerson *)ownPerson {
    if (!_ownPersonRead) {
        _ownPersonRead = YES;
        NSData *data = [NSData dataWithContentsOfFile:[self ownPersonPath]];
        uint32_t head[2];
        if (data.length == sizeof(head) + sizeof(exteria_person_row)) {
            memcpy(head, data.bytes, sizeof(head));
            if (head[0] == OWN_PERSON_MAGIC && head[1] == sizeof(exteria_person_row)) {
                exteria_person_row row;
                memcpy(&row, (const uint8_t *)data.bytes + sizeof(head), sizeof(row));
                _ownPerson = [[ExteriaPerson alloc] initWithRow:&row];
            }
        }
    }
    return _ownPerson;
}

- (void)loadSelf:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    NSString *path = [self ownPersonPath];
    [self load:"users.getUsers" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
        exteria_tl_value *ids = exteria_tl_new_vec(arena, 1);
        exteria_tl_value *self_input = exteria_tl_new_obj(arena, "inputUserSelf");
        if (!ids || !self_input) return EXTERIA_E_NOMEM;
        exteria_status status = exteria_tl_vec_set(ids, 0, self_input);
        if (status == EXTERIA_OK) status = exteria_tl_set(request, "id", ids);
        return status;
    } parse:^NSArray *(const exteria_tl_value *answer) {
        exteria_person_row row;
        if (!answer || answer->kind != EXTERIA_TL_V_VEC || answer->u.vec.count < 1 ||
            exteria_person_parse(answer->u.vec.items[0], &row) != EXTERIA_OK) return nil;
        uint8_t packed[2 * sizeof(uint32_t) + sizeof(row)];
        uint32_t head[2] = {OWN_PERSON_MAGIC, (uint32_t)sizeof(row)};
        memcpy(packed, head, sizeof(head));
        memcpy(packed + sizeof(head), &row, sizeof(row));
        if (![[NSData dataWithBytes:packed length:sizeof(packed)] writeToFile:path atomically:YES]) NSLog(@"exteria: the own profile was not kept");
        return [NSArray arrayWithObject:[[[ExteriaPerson alloc] initWithRow:&row] autorelease]];
    } completion:^(NSArray *items, NSString *errorName) {
        if (items.count) {
            [_ownPerson release];
            _ownPerson = [[items objectAtIndex:0] retain];
            _ownPersonRead = YES;
        }
        if (done) done(items, errorName);
        [done release];
    }];
}

/* a file on the account's own data center comes over the main connection; any other data center gets a link of its
   own, signed in through an authorization this connection exports */
- (void)downloadFile:(ExteriaRemoteFile *)file completion:(ExteriaDownloadCompletion)completion {
    [self downloadFile:file offset:0 limit:EXTERIA_REMOTE_FILE_PART ranged:NO completion:completion];
}

- (void)downloadFile:(ExteriaRemoteFile *)file offset:(long long)offset limit:(int32_t)limit completion:(ExteriaDownloadCompletion)completion {
    [self downloadFile:file offset:offset limit:limit ranged:YES completion:completion];
}

- (void)downloadFile:(ExteriaRemoteFile *)file offset:(long long)offset limit:(int32_t)limit ranged:(BOOL)ranged
          completion:(ExteriaDownloadCompletion)completion {
    ExteriaDownloadCompletion done = [completion copy];
    if (!file) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"INTERNAL"); [done release]; });
        return;
    }
    [self post:^{
        if (file.dc == _dc) {
            [self submit:"upload.getFile" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
                exteria_tl_value *location = NULL;
                exteria_status status = [file buildLocation:arena into:&location];
                if (status == EXTERIA_OK) status = exteria_tl_set(request, "location", location);
                if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "offset", offset);
                if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", limit);
                return status;
            } handler:^(const exteria_mt_rpc_result *result) {
                const uint8_t *bytes = NULL;
                size_t len = 0;
                NSData *data = nil;
                NSString *error = nil;
                if (result->status != EXTERIA_OK) error = ExteriaDownloadErrorName(result);
                else if (ranged) {
                    if (exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK && len <= (size_t)limit) data = [NSData dataWithBytes:bytes length:len];
                    else error = @"INTERNAL";
                }
                else if (exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK && len >= EXTERIA_REMOTE_FILE_PART) error = @"FILE_TOO_BIG";
                else if (exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK && len > 0) data = [NSData dataWithBytes:bytes length:len];
                else error = @"INTERNAL";
                if (ExteriaIsRevokedError(error)) _dropKeyPending = YES;
                dispatch_async(dispatch_get_main_queue(), ^{ done(data, error); [done release]; });
            }];
            return;
        }
        NSNumber *key = [NSNumber numberWithInt:file.dc];
        ExteriaMediaLink *link = [_links objectForKey:key];
        if (!link && exteria_dc_host(file.dc)) {
            link = [[[ExteriaMediaLink alloc] initWithDc:file.dc directory:_directory deviceModel:_deviceModel
                                           systemVersion:_systemVersion appVersion:_appVersion langCode:_langCode] autorelease];
            link.shiro = _shiro;
            [_links setObject:link forKey:key];
        }
        if (!link) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"INTERNAL"); [done release]; });
            return;
        }
        int32_t dc = file.dc;
        [link downloadFile:file offset:offset limit:limit ranged:ranged authorizer:^(ExteriaAuthorizationDelivery deliver) {
            ExteriaAuthorizationDelivery deliverCopy = [deliver copy];
            [self post:^{
                [self submit:"auth.exportAuthorization" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
                    return exteria_tl_set_i32(arena, request, "dc_id", dc);
                } handler:^(const exteria_mt_rpc_result *result) {
                    int64_t authId = 0;
                    const uint8_t *bytes = NULL;
                    size_t len = 0;
                    if (result->status == EXTERIA_OK && exteria_tl_get_i64(result->value, "id", &authId) == EXTERIA_OK &&
                        exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK) {
                        deliverCopy(authId, [NSData dataWithBytes:bytes length:len], nil);
                    } else {
                        deliverCopy(0, nil, result->status == EXTERIA_OK ? @"INTERNAL" : ExteriaRpcErrorName(result));
                    }
                    [deliverCopy release];
                }];
            }];
        } completion:^(NSData *data, NSString *error) {
            done(data, error);
            [done release];
        }];
    }];
}

- (void)signOut:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    [self invoke:"auth.logOut" configure:^exteria_status(exteria_arena *arena, exteria_tl_value *request) {
        (void)arena;
        (void)request;
        return EXTERIA_OK;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        /* a key the server already dropped is as good as a finished logout */
        if (!error || ExteriaIsRevokedError(error)) {
            _dropKeyPending = YES;
            error = nil;
        }
        NSString *delivered = [[error copy] autorelease];
        dispatch_async(dispatch_get_main_queue(), ^{ done(delivered); });
    }];
    [done release];
}

#pragma mark client callbacks

static exteria_status ExteriaSend(void *ctx, int32_t dc, const uint8_t *data, size_t len) {
    ExteriaSession *session = ctx;
    (void)dc;
    if (session->_socket.fd < 0) return EXTERIA_E_STATE;
    return exteria_mt_socket_write_all(&session->_socket, data, len, WRITE_TIMEOUT_MS);
}

static exteria_status ExteriaLoadSession(void *ctx, int32_t dc, exteria_mt_session_state *out) {
    ExteriaSession *session = ctx;
    uint8_t buf[EXTERIA_SESSION_FILE_LEN + 1];
    size_t len;
    NSString *path = ExteriaSessionPath(session->_directory, dc);
    exteria_status status = ExteriaReadFile(path, buf, sizeof(buf), &len);
    if (status != EXTERIA_OK) return status;
    status = exteria_session_unpack(buf, len, dc, out);
    exteria_wipe(buf, sizeof(buf));
    if (status != EXTERIA_OK) {
        /* a damaged key cannot be repaired, a new handshake replaces it */
        NSLog(@"exteria: session file for dc %d is unusable, starting a new session", (int)dc);
        unlink(path.fileSystemRepresentation);
        return EXTERIA_E_NOTFOUND;
    }
    return EXTERIA_OK;
}

static exteria_status ExteriaSaveSession(void *ctx, int32_t dc, const exteria_mt_session_state *state) {
    ExteriaSession *session = ctx;
    uint8_t buf[EXTERIA_SESSION_FILE_LEN];
    size_t len;
    exteria_status status = exteria_session_pack(dc, state, buf, sizeof(buf), &len);
    if (status == EXTERIA_OK) status = ExteriaWriteFile(ExteriaSessionPath(session->_directory, dc), buf, len);
    exteria_wipe(buf, sizeof(buf));
    return status;
}

static void ExteriaRpcResult(void *ctx, uint64_t id, const exteria_mt_rpc_result *result) {
    ExteriaSession *session = ctx;
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:id];
    void (^handler)(const exteria_mt_rpc_result *) = [[session->_handlers objectForKey:key] retain];
    if (!handler) return;
    [session->_handlers removeObjectForKey:key];
    handler(result);
    [handler release];
}

/* the client has put something new in the store; whoever watches a chat reads it from there on the worker */
static void ExteriaClientChanged(void *ctx) {
    [(ExteriaSession *)ctx storeChanged];
}

static void ExteriaClientPhoneCall(void *ctx, const exteria_tl_value *value) {
    ExteriaSession *session = (ExteriaSession *)ctx;
    exteria_phone_call call;
    exteria_status status = exteria_phone_call_parse(value, &call);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: a phone call update was rejected: %s", exteria_status_name(status));
        return;
    }
    [session->_calls handlePhoneCall:&call];
}

static void ExteriaClientPhoneSignaling(void *ctx, int64_t callId, const uint8_t *data, size_t len) {
    ExteriaSession *session = (ExteriaSession *)ctx;
    NSData *bytes = [NSData dataWithBytes:data length:len];
    [session->_calls handleSignalingData:bytes callId:callId];
}

static void ExteriaClientFoldersChanged(void *ctx) {
    ExteriaSession *session = ctx;
    [session deliverMain:^{
        [NSObject cancelPreviousPerformRequestsWithTarget:session selector:@selector(refreshChangedChatFolders) object:nil];
        [session performSelector:@selector(refreshChangedChatFolders) withObject:nil afterDelay:0];
    }];
}

static void ExteriaClientReadOutbox(void *ctx, int32_t kind, int64_t peer, int32_t maxId) {
    ExteriaSession *session = (ExteriaSession *)ctx;
    [session deliverMain:^{ [session noteReadOutbox:maxId ofKind:kind peer:peer]; }];
}

static void ExteriaClientTyping(void *ctx, const exteria_typing *typing) {
    ExteriaSession *session = (ExteriaSession *)ctx;
    int32_t kind = typing->peer_kind, top = typing->top_message;
    long long peer = typing->peer_id, user = typing->user_id;
    int action = (int)typing->action;
    /* a group names who writes, by the first name of a person the store knows; this runs on the worker, which is where the store may be read */
    NSString *name = nil;
    if (kind != 1 && user > 0 && action != EXTERIA_TYPING_CANCEL) {
        NSString *full = [[session storedPersonWithKey:user] name];
        NSRange space = [full rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        name = space.location == NSNotFound ? full : [full substringToIndex:space.location];
    }
    [session deliverMain:^{
        /* typing is live only and runs out in seconds, so nobody sees it from the background, where the app is kept awake just for its link */
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) return;
        [session.typing noteKind:kind peer:peer user:user action:action top:top name:name];
    }];
}

static void ExteriaClientDraft(void *ctx, const exteria_tl_value *update) {
    [(ExteriaSession *)ctx noteDraftUpdate:update];
}

static void ExteriaClientError(void *ctx, exteria_status status, const char *boundary) {
    (void)ctx;
    NSLog(@"exteria: client error at %s: %s", boundary, exteria_status_name(status));
}

static NSString *ExteriaTlString(const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return nil;
    return [[[NSString alloc] initWithBytes:data length:len encoding:NSUTF8StringEncoding] autorelease];
}

static ExteriaCodeKind ExteriaCodeKindOf(const exteria_tl_value *type) {
    if (exteria_tl_is(type, EXTERIA_TL_ID_auth_sentCodeTypeApp)) return ExteriaCodeKindApp;
    if (exteria_tl_is(type, EXTERIA_TL_ID_auth_sentCodeTypeSms)) return ExteriaCodeKindSms;
    if (exteria_tl_is(type, EXTERIA_TL_ID_auth_sentCodeTypeCall)) return ExteriaCodeKindCall;
    return ExteriaCodeKindOther;
}

- (void)failureFromStatus:(exteria_status)status text:(const char *)text {
    char name[128];
    int32_t number = 0;
    name[0] = '\0';
    if (status == EXTERIA_E_RPC && text) exteria_mt_rpc_error_split(text, name, sizeof(name), &number);
    else if (status == EXTERIA_E_TIMEOUT) snprintf(name, sizeof(name), "TIMEOUT");
    else {
        NSLog(@"exteria: auth failed: %s", exteria_status_name(status));
        snprintf(name, sizeof(name), "INTERNAL");
    }
    [self deliverFailure:[NSString stringWithUTF8String:name] number:number];
}

static void ExteriaAuthChanged(void *ctx, exteria_auth_state state, exteria_status status,
                               const exteria_tl_value *value, const char *error) {
    ExteriaSession *session = ctx;
    ExteriaAuthEvent *event;
    /* these two arrive with the rpc error that caused them */
    if (state == EXTERIA_AUTH_MIGRATE) {
        session->_migrateDc = session->_client.auth.migrate_dc;
        return;
    }
    if (state == EXTERIA_AUTH_FLOOD_WAIT) {
        [session failureFromStatus:status text:error];
        return;
    }
    if (status != EXTERIA_OK) {
        [session failureFromStatus:status text:error];
        return;
    }
    switch (state) {
    case EXTERIA_AUTH_CODE: {
        const exteria_tl_value *type = exteria_tl_get(value, "type");
        int32_t length = 0, timeout = 0;
        exteria_tl_get_i32(type, "length", &length);
        if (exteria_tl_has(value, "timeout")) exteria_tl_get_i32(value, "timeout", &timeout);
        event = [[[ExteriaAuthEvent alloc] initWithKind:ExteriaAuthEventCode] autorelease];
        [event setCodeKind:ExteriaCodeKindOf(type) length:length
               resendAfter:exteria_tl_has(value, "next_type") ? timeout : -1];
        [session deliver:event];
        break;
    }
    case EXTERIA_AUTH_PASSWORD:
        event = [[[ExteriaAuthEvent alloc] initWithKind:ExteriaAuthEventPassword] autorelease];
        [event setHint:ExteriaTlString(value, "hint")];
        [event setHasRecovery:exteria_tl_has(value, "has_recovery")];
        [session deliver:event];
        break;
    case EXTERIA_AUTH_SIGNUP:
        [session deliverKind:ExteriaAuthEventSignUp];
        break;
    case EXTERIA_AUTH_AUTHORIZED: {
        int64_t account = 0;
        exteria_tl_get_i64(exteria_tl_get(value, "user"), "id", &account);
        session->_authorizedAccount = account;
        break;
    }
    case EXTERIA_AUTH_QR: {
        char url[512];
        int32_t expires = 0;
        if (exteria_auth_qr_url(value, url, sizeof(url)) != EXTERIA_OK || exteria_tl_get_i32(value, "expires", &expires) != EXTERIA_OK) {
            NSLog(@"exteria: the login token cannot be shown");
            [session deliverFailure:@"INTERNAL" number:0];
            break;
        }
        event = [[[ExteriaAuthEvent alloc] initWithKind:ExteriaAuthEventQr] autorelease];
        [event setQrUrl:[NSString stringWithUTF8String:url] expires:(NSTimeInterval)expires];
        [session deliver:event];
        break;
    }
    case EXTERIA_AUTH_EMAIL_SETUP:
    case EXTERIA_AUTH_EMAIL_CODE:
        [session deliverKind:ExteriaAuthEventUnsupported];
        break;
    case EXTERIA_AUTH_RECOVERY:
        event = [[[ExteriaAuthEvent alloc] initWithKind:ExteriaAuthEventRecovery] autorelease];
        [event setEmailPattern:ExteriaTlString(value, "email_pattern")];
        [session deliver:event];
        break;
    case EXTERIA_AUTH_IDLE:
    case EXTERIA_AUTH_WAITING:
    case EXTERIA_AUTH_MIGRATE:
    case EXTERIA_AUTH_FLOOD_WAIT:
        break;
    }
}

#pragma mark worker

- (exteria_status)initClient {
    exteria_mt_client_config config;
    exteria_client_events events;
    memset(&config, 0, sizeof(config));
    memset(&events, 0, sizeof(events));
    config.dc_id = _dc;
    config.transport = EXTERIA_MT_INTERMEDIATE;
    /* the header hides the protocol from providers that block plain telegram traffic */
    config.obfuscation.enabled = 1;
    config.obfuscation.dc_id = (int16_t)_dc;
    config.api_id = EXTERIA_API_ID;
    config.device_model = _cDeviceModel;
    config.system_version = _cSystemVersion;
    config.app_version = _cAppVersion;
    config.system_lang_code = _cLangCode;
    config.lang_pack = "ios";
    config.lang_code = _cLangCode;
    events.ctx = self;
    events.send = ExteriaSend;
    events.load_session = ExteriaLoadSession;
    events.save_session = ExteriaSaveSession;
    events.auth = ExteriaAuthChanged;
    events.error = ExteriaClientError;
    events.changed = ExteriaClientChanged;
    events.phone_call = ExteriaClientPhoneCall;
    events.phone_signaling = ExteriaClientPhoneSignaling;
    events.typing = ExteriaClientTyping;
    events.read_outbox = ExteriaClientReadOutbox;
    events.draft = ExteriaClientDraft;
    events.folders_changed = ExteriaClientFoldersChanged;
    events.result = ExteriaRpcResult;
    exteria_status status = exteria_client_init(&_client, &config, EXTERIA_API_HASH, &events);
    _clientLive = status == EXTERIA_OK;
    if (_clientLive && _pingInterval) exteria_mt_client_set_ping_interval(&_client.mt, _pingInterval);
    return status;
}

- (void)closeSocket {
    if (_voip) {
        /* the streams of a voip socket hold a copy of the descriptor, so closing ours alone would leave the connection up */
        if (_socket.fd >= 0) shutdown(_socket.fd, SHUT_RDWR);
        ExteriaVoipSocketDetach(_voip);
        _voip = NULL;
    }
    exteria_mt_socket_close(&_socket);
}

- (void)closeStore {
    if (!_store) return;
    exteria_status status = exteria_store_close(_store);
    if (status != EXTERIA_OK) NSLog(@"exteria: database close failed: %s", exteria_status_name(status));
    _store = NULL;
}

- (exteria_status)attachStoreForAccount:(int64_t)account {
    NSString *path = ExteriaFilePath(_directory, [NSString stringWithFormat:@"exteria-%lld.db", (long long)account]);
    exteria_status status = exteria_store_open(&_store, path.fileSystemRepresentation, account);
    if (status != EXTERIA_OK) return status;
    status = exteria_client_attach_store(&_client, _store, account);
    if (status != EXTERIA_OK) [self closeStore];
    else _client.updates.keep = ExteriaSavingMask();
    return status;
}

/* a client that is gone cannot answer, so its waiting requests are failed instead of left hanging */
- (void)failPendingRequests {
    NSArray *handlers = [_handlers allValues];
    [_handlers removeAllObjects];
    exteria_mt_rpc_result failed;
    memset(&failed, 0, sizeof(failed));
    failed.status = EXTERIA_E_STATE;
    for (void (^handler)(const exteria_mt_rpc_result *) in handlers) handler(&failed);
}

- (void)linkWanted {
    if (_wantLink) return;
    _failures = 0;
    _retryAt = 0;
    _wantLink = YES;
}

/* a failed link retries with a doubling pause; a login gives up after RETRY_LIMIT in a row and waits for its
   screen to ask again */
- (void)linkLost:(exteria_status)reason {
    int32_t transport = _clientLive ? exteria_mt_client_transport_error(&_client.mt) : 0;
    int64_t securityValue = 0;
    const char *securityNote = _clientLive ? exteria_mt_client_security_note(&_client.mt, &securityValue) : NULL;
    NSLog(@"exteria: link to dc %d lost: %s (transport error %d, last message 0x%08x%s%s %lld)", (int)_dc, exteria_status_name(reason),
          (int)transport, _clientLive ? exteria_mt_client_last_ctor(&_client.mt) : 0u, securityNote ? ", refused: " : "",
          securityNote ? securityNote : "", (long long)securityValue);
    [self closeSocket];
    if (_clientLive) exteria_client_disconnected(&_client);
    if (transport == TRANSPORT_AUTH_KEY_UNKNOWN) {
        [self dropSessionKey];
        return;
    }
    if (_failures < UINT_MAX) ++_failures;
    if (_failures >= RETRY_LIMIT && _account <= 0) {
        _wantLink = NO;
        if (_clientLive) exteria_auth_cancel(&_client.auth);
        [self deliverKind:ExteriaAuthEventOffline];
        return;
    }
    /* the shift is bounded so a long outage cannot overflow it */
    unsigned shift = MIN(_failures - 1, 5u);
    _retryAt = ExteriaNowMs() + MIN(1000u << shift, RETRY_PAUSE_MAX_MS);
}

/* the server forgot the key: a stored account is lost, a login in progress just needs a new handshake */
- (void)dropSessionKey {
    BOOL hadAccount = [ExteriaSession hasAccountInDirectory:_directory];
    unlink(ExteriaSessionPath(_directory, _dc).fileSystemRepresentation);
    if (hadAccount) {
        unlink(ExteriaAccountPath(_directory).fileSystemRepresentation);
        [self closeStore];
        _account = 0;
    }
    exteria_client_free(&_client);
    _clientLive = NO;
    [self failPendingRequests];
    exteria_status status = [self initClient];
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: client restart failed: %s", exteria_status_name(status));
        _wantLink = NO;
        [self deliverFailure:@"INTERNAL" number:status];
        return;
    }
    _failures = 0;
    _retryAt = 0;
    if (hadAccount) [self deliverKind:ExteriaAuthEventLoggedOut];
}

/* worker only: tells the main thread when the link starts or stops working */
- (void)reportLink:(BOOL)works {
    if (works == _linkReported) return;
    _linkReported = works;
    dispatch_async(dispatch_get_main_queue(), ^{
        _connected = works;
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaSessionConnectionDidChangeNotification object:self];
    });
}

- (void)openLink {
    const char *host = exteria_dc_host(_dc);
    BOOL tunneled = NO;
    exteria_status status = ExteriaShiroConnectSocket(_shiro, &_socket, host, exteria_dc_port(), CONNECT_TIMEOUT_MS, &tunneled);
    /* a signed in link that should keep working while the app sleeps is made a voip socket; a stream of the tunnel
       is a local socket pair, which the system cannot keep alive for the network, so it stays an ordinary socket */
    if (status == EXTERIA_OK && !tunneled && _account > 0 && ExteriaBackgroundLinkWanted()) _voip = ExteriaVoipSocketAttach(_socket.fd);
    if (status == EXTERIA_OK) status = exteria_client_connect(&_client);
    if (status != EXTERIA_OK) [self linkLost:status];
}

- (void)readLink {
    uint8_t buf[READ_CHUNK];
    for (int i = 0; i < READS_PER_WAKE && _socket.fd >= 0; ++i) {
        size_t got = 0;
        exteria_status status = exteria_mt_socket_read(&_socket, buf, sizeof(buf), &got, 0);
        if (status == EXTERIA_E_TIMEOUT) return;
        if (status != EXTERIA_OK) {
            [self linkLost:status];
            return;
        }
        status = exteria_client_feed(&_client, buf, got);
        [self settleClient];
        if (status != EXTERIA_OK && status != EXTERIA_E_RETRY) {
            [self linkLost:status];
            return;
        }
        if (_client.mt.state == EXTERIA_MT_CLIENT_DEAD) {
            [self linkLost:EXTERIA_E_STATE];
            return;
        }
    }
}

/* work a callback asked for but could not do from inside the client */
- (void)settleClient {
    if (_dropKeyPending) {
        _dropKeyPending = NO;
        [self closeSocket];
        [self dropSessionKey];
        return;
    }
    if (_migrateDc) {
        int32_t dc = _migrateDc;
        _migrateDc = 0;
        [self closeSocket];
        exteria_status status = exteria_client_migrate(&_client, dc);
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: migration to dc %d failed: %s", (int)dc, exteria_status_name(status));
            [self deliverFailure:@"INTERNAL" number:status];
            return;
        }
        _dc = dc;
        _failures = 0;
        _retryAt = 0;
        _wantLink = YES;
    }
    if (_authorizedAccount) {
        int64_t account = _authorizedAccount;
        _authorizedAccount = 0;
        [self completeAuthorization:account];
    }
}

- (void)completeAuthorization:(int64_t)account {
    uint8_t buf[EXTERIA_ACCOUNT_FILE_LEN];
    size_t len;
    exteria_status status = exteria_account_pack(_dc, account, buf, sizeof(buf), &len);
    if (status == EXTERIA_OK) status = [self attachStoreForAccount:account];
    if (status == EXTERIA_OK) status = ExteriaWriteFile(ExteriaAccountPath(_directory), buf, len);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: account could not be stored: %s", exteria_status_name(status));
        [self deliverFailure:@"STORAGE" number:status];
        return;
    }
    _account = account;
    ExteriaAuthEvent *event = [[[ExteriaAuthEvent alloc] initWithKind:ExteriaAuthEventAuthorized] autorelease];
    [event setUserId:account];
    [self deliver:event];
}

- (void)drainCommands {
    [_lock lock];
    NSArray *batch = [[_commands copy] autorelease];
    [_commands removeAllObjects];
    [_lock unlock];
    for (void (^command)(void) in batch) {
        command();
        [self settleClient];
    }
}

- (void)run {
    NSAutoreleasePool *setup = [[NSAutoreleasePool alloc] init];
    uint8_t buf[EXTERIA_ACCOUNT_FILE_LEN + 1];
    size_t len;
    int64_t account = 0;
    _dc = 2;
    if (ExteriaReadFile(ExteriaAccountPath(_directory), buf, sizeof(buf), &len) == EXTERIA_OK &&
        exteria_account_unpack(buf, len, &_dc, &account) != EXTERIA_OK) {
        NSLog(@"exteria: account file is unusable, starting signed out");
        account = 0;
        _dc = 2;
    }
    exteria_status status = [self initClient];
    if (status == EXTERIA_OK && account > 0) status = [self attachStoreForAccount:account];
    if (status == EXTERIA_OK) _account = account;
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: session start failed: %s", exteria_status_name(status));
        [self deliverFailure:@"INTERNAL" number:status];
    } else {
        _wantLink = YES;
    }
    [setup drain];

    while (_clientLive && ![self isStopping]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [self drainCommands];
        uint64_t now = ExteriaNowMs();
        if (_wantLink && _socket.fd < 0 && now >= _retryAt) [self openLink];

        uint32_t next = POLL_CAP_MS;
        if (_clientLive && exteria_client_tick(&_client, &next) != EXTERIA_OK) next = POLL_CAP_MS;
        [self settleClient];
        /* a restored key is ready the moment it connects, so only a frame the server sent and the client accepted
           counts as a link that works */
        BOOL linkWorks = _clientLive && _socket.fd >= 0 && _client.mt.state == EXTERIA_MT_CLIENT_READY && exteria_mt_client_heard(&_client.mt);
        if (linkWorks) _failures = 0;
        [self reportLink:linkWorks];
        if (next > POLL_CAP_MS) next = POLL_CAP_MS;
        if (_wantLink && _socket.fd < 0) {
            now = ExteriaNowMs();
            uint32_t until = _retryAt > now ? (uint32_t)MIN(_retryAt - now, (uint64_t)POLL_CAP_MS) : 0;
            if (until < next) next = until;
        }

        struct pollfd fds[2];
        nfds_t count = 1;
        fds[0].fd = _wake[0];
        fds[0].events = POLLIN;
        fds[0].revents = 0;
        if (_socket.fd >= 0) {
            fds[1].fd = _socket.fd;
            fds[1].events = POLLIN;
            fds[1].revents = 0;
            count = 2;
        }
        int ready = poll(fds, count, (int)next);
        if (ready < 0 && errno != EINTR) {
            NSLog(@"exteria: poll failed, errno %d", errno);
            [self linkLost:EXTERIA_E_IO];
        } else if (ready > 0) {
            if (fds[0].revents & POLLIN) {
                char drain[64];
                while (read(_wake[0], drain, sizeof(drain)) > 0) {}
            }
            if (count == 2 && (fds[1].revents & (POLLIN | POLLERR | POLLHUP))) [self readLink];
        }
        [pool drain];
    }

    NSAutoreleasePool *teardown = [[NSAutoreleasePool alloc] init];
    [_calls shutdown];
    for (ExteriaMediaLink *link in [_links allValues]) [link stop];
    [self closeSocket];
    if (_clientLive) exteria_client_free(&_client);
    _clientLive = NO;
    [self failPendingRequests];
    [self closeStore];
    [teardown drain];
    dispatch_semaphore_signal(_exited);
}

@end
