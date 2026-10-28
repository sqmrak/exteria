#import "exteria_media_link.h"
#import "exteria_proxy_settings.h"

#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>

#include "exteria_client.h"
#include "exteria_credentials.h"
#include "exteria_mt_socket.h"
#include "exteria_session_file.h"

#import "exteria_files.h"
#import "exteria_rpc.h"

#define CONNECT_TIMEOUT_MS 10000
#define WRITE_TIMEOUT_MS 15000
#define RETRY_LIMIT 4
#define POLL_CAP_MS 1000
#define READ_CHUNK 16384
#define READS_PER_WAKE 64
#define RPC_TIMEOUT_MS 30000

@interface ExteriaMediaJob : NSObject {
@public
    ExteriaRemoteFile *file;
    ExteriaDownloadCompletion completion;
    BOOL retried;
    /* a part of a large file: the answer may be shorter than the limit, or empty at the end of the file */
    BOOL ranged;
    long long offset;
    int32_t limit;
}
@end

@implementation ExteriaMediaJob
- (void)dealloc {
    [file release];
    [completion release];
    [super dealloc];
}
@end

@interface ExteriaMediaLink () {
    NSString *_directory;
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
    NSLock *_lock;
    NSMutableArray *_commands;
    int _wake[2];
    dispatch_semaphore_t _exited;
    BOOL _started;
    BOOL _stopping;

    /* worker only */
    exteria_client _client;
    BOOL _clientLive;
    exteria_mt_socket _socket;
    unsigned _failures;
    uint64_t _retryAt;
    BOOL _wantLink;
    ExteriaShiro *_shiro;
    NSMutableDictionary *_handlers;
    NSMutableArray *_waiting;
    BOOL _authorizing;
    ExteriaAuthorizer _authorizer;
}
@end

@implementation ExteriaMediaLink

@synthesize dc = _dc;
@synthesize shiro = _shiro;

static uint64_t ExteriaMediaNowMs(void) {
    return exteria_system_clock.monotonic_ms(NULL);
}

- (id)initWithDc:(int32_t)dc directory:(NSString *)directory deviceModel:(NSString *)deviceModel
   systemVersion:(NSString *)systemVersion appVersion:(NSString *)appVersion langCode:(NSString *)langCode {
    self = [super init];
    if (!self) return nil;
    _dc = dc;
    _directory = [directory copy];
    _deviceModel = [deviceModel copy];
    _systemVersion = [systemVersion copy];
    _appVersion = [appVersion copy];
    _langCode = [langCode copy];
    _cDeviceModel = strdup(_deviceModel.UTF8String);
    _cSystemVersion = strdup(_systemVersion.UTF8String);
    _cAppVersion = strdup(_appVersion.UTF8String);
    _cLangCode = strdup(_langCode.UTF8String);
    _lock = [[NSLock alloc] init];
    _commands = [[NSMutableArray alloc] init];
    _handlers = [[NSMutableDictionary alloc] init];
    _waiting = [[NSMutableArray alloc] init];
    _wake[0] = _wake[1] = -1;
    exteria_mt_socket_init(&_socket);
    _exited = dispatch_semaphore_create(0);
    return self;
}

- (void)dealloc {
    for (int i = 0; i < 2; ++i) if (_wake[i] >= 0) close(_wake[i]);
    if (_exited) dispatch_release(_exited);
    [_directory release];
    [_deviceModel release];
    [_systemVersion release];
    [_appVersion release];
    [_langCode release];
    free(_cDeviceModel);
    free(_cSystemVersion);
    free(_cAppVersion);
    free(_cLangCode);
    [_lock release];
    [_commands release];
    [_handlers release];
    [_waiting release];
    [_authorizer release];
    [super dealloc];
}

#pragma mark commands

- (void)post:(void (^)(void))block {
    [_lock lock];
    [_commands addObject:[[block copy] autorelease]];
    [_lock unlock];
    char byte = 1;
    /* a full pipe already holds a wake up, so a short write loses nothing */
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"exteria: media link wake up failed, errno %d", errno);
}

/* the thread starts with the first job, so a data center nobody needs is never dialled */
- (BOOL)ensureStarted {
    [_lock lock];
    if (_started) {
        BOOL usable = _wake[1] >= 0 && !_stopping;
        [_lock unlock];
        return usable;
    }
    _started = YES;
    BOOL piped = pipe(_wake) == 0;
    if (!piped) {
        _wake[0] = _wake[1] = -1;
    } else {
        for (int i = 0; i < 2; ++i) {
            fcntl(_wake[i], F_SETFL, fcntl(_wake[i], F_GETFL, 0) | O_NONBLOCK);
            fcntl(_wake[i], F_SETFD, FD_CLOEXEC);
        }
    }
    [_lock unlock];
    if (!piped) {
        NSLog(@"exteria: media link pipe failed, errno %d", errno);
        return NO;
    }
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
    return YES;
}

- (void)stop {
    [_lock lock];
    BOOL running = _started && !_stopping && _wake[1] >= 0;
    _stopping = YES;
    [_lock unlock];
    if (!running) return;
    char byte = 1;
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"exteria: media link stop wake up failed, errno %d", errno);
    dispatch_semaphore_wait(_exited, DISPATCH_TIME_FOREVER);
}

- (BOOL)isStopping {
    [_lock lock];
    BOOL stopping = _stopping;
    [_lock unlock];
    return stopping;
}

#pragma mark downloads

static void ExteriaFinishJob(ExteriaMediaJob *job, NSData *data, NSString *error) {
    ExteriaDownloadCompletion done = [job->completion retain];
    NSData *delivered = [[data copy] autorelease];
    NSString *deliveredError = [[error copy] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{
        done(delivered, deliveredError);
        [done release];
    });
}

- (void)downloadFile:(ExteriaRemoteFile *)file authorizer:(ExteriaAuthorizer)authorizer completion:(ExteriaDownloadCompletion)completion {
    [self downloadFile:file offset:0 limit:EXTERIA_REMOTE_FILE_PART ranged:NO authorizer:authorizer completion:completion];
}

- (void)downloadFile:(ExteriaRemoteFile *)file offset:(long long)offset limit:(int32_t)limit ranged:(BOOL)ranged
          authorizer:(ExteriaAuthorizer)authorizer completion:(ExteriaDownloadCompletion)completion {
    ExteriaMediaJob *job = [[[ExteriaMediaJob alloc] init] autorelease];
    job->ranged = ranged;
    job->offset = offset;
    job->limit = limit;
    job->file = [file retain];
    job->completion = [completion copy];
    ExteriaAuthorizer authorize = [authorizer copy];
    if (![self ensureStarted]) {
        ExteriaFinishJob(job, nil, @"INTERNAL");
        [authorize release];
        return;
    }
    [self post:^{
        if (!_authorizer) _authorizer = [authorize retain];
        if (!_wantLink) {
            _failures = 0;
            _retryAt = 0;
            _wantLink = YES;
        }
        [self submitJob:job];
    }];
    [authorize release];
}

/* worker only */
- (void)submitJob:(ExteriaMediaJob *)job {
    exteria_arena arena;
    exteria_tl_value *request, *location = NULL;
    uint64_t id = 0;
    exteria_status status = _clientLive ? EXTERIA_OK : EXTERIA_E_STATE;
    exteria_arena_init(&arena, 64u * 1024u);
    request = status == EXTERIA_OK ? exteria_tl_new_obj(&arena, "upload.getFile") : NULL;
    if (status == EXTERIA_OK && !request) status = EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = [job->file buildLocation:&arena into:&location];
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "location", location);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(&arena, request, "offset", job->offset);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(&arena, request, "limit", job->limit);
    if (status == EXTERIA_OK) status = exteria_client_request(&_client, request, RPC_TIMEOUT_MS, &id);
    exteria_arena_free(&arena);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: file request failed: %s", exteria_status_name(status));
        ExteriaFinishJob(job, nil, @"INTERNAL");
        return;
    }
    [_handlers setObject:[[^(const exteria_mt_rpc_result *result) {
        [self fileResult:result forJob:job];
    } copy] autorelease] forKey:[NSNumber numberWithUnsignedLongLong:id]];
}

- (void)fileResult:(const exteria_mt_rpc_result *)result forJob:(ExteriaMediaJob *)job {
    if (result->status == EXTERIA_OK) {
        const uint8_t *bytes;
        size_t len;
        if (job->ranged) {
            if (exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK && len <= (size_t)job->limit) {
                ExteriaFinishJob(job, [NSData dataWithBytes:bytes length:len], nil);
            } else {
                ExteriaFinishJob(job, nil, @"INTERNAL");
            }
            return;
        }
        if (exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK && len >= EXTERIA_REMOTE_FILE_PART) {
            ExteriaFinishJob(job, nil, @"FILE_TOO_BIG");
        } else if (exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK && len > 0) {
            ExteriaFinishJob(job, [NSData dataWithBytes:bytes length:len], nil);
        } else {
            ExteriaFinishJob(job, nil, @"INTERNAL");
        }
        return;
    }
    NSString *error = ExteriaDownloadErrorName(result);
    /* a key that never signed in on this data center is signed in once, then the waiting jobs go again */
    if ([error isEqualToString:@"AUTH_KEY_UNREGISTERED"] && !job->retried && _authorizer) {
        job->retried = YES;
        [_waiting addObject:job];
        if (!_authorizing) [self authorize];
        return;
    }
    ExteriaFinishJob(job, nil, error);
}

- (void)failWaiting:(NSString *)error {
    NSArray *jobs = [[_waiting copy] autorelease];
    [_waiting removeAllObjects];
    for (ExteriaMediaJob *job in jobs) ExteriaFinishJob(job, nil, error);
}

- (void)authorize {
    _authorizing = YES;
    _authorizer(^(long long authId, NSData *bytes, NSString *errorName) {
        NSData *copy = [bytes copy];
        NSString *error = [errorName copy];
        [self post:^{
            if (error || !copy) {
                _authorizing = NO;
                [self failWaiting:error ? error : @"INTERNAL"];
            } else {
                [self importAuthorization:authId bytes:copy];
            }
            [copy release];
            [error release];
        }];
    });
}

- (void)importAuthorization:(long long)authId bytes:(NSData *)bytes {
    exteria_arena arena;
    exteria_tl_value *request;
    uint64_t id = 0;
    exteria_status status = _clientLive ? EXTERIA_OK : EXTERIA_E_STATE;
    exteria_arena_init(&arena, 64u * 1024u);
    request = status == EXTERIA_OK ? exteria_tl_new_obj(&arena, "auth.importAuthorization") : NULL;
    if (status == EXTERIA_OK && !request) status = EXTERIA_E_NOMEM;
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(&arena, request, "id", authId);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(&arena, request, "bytes", bytes.bytes, bytes.length);
    if (status == EXTERIA_OK) status = exteria_client_request(&_client, request, RPC_TIMEOUT_MS, &id);
    exteria_arena_free(&arena);
    if (status != EXTERIA_OK) {
        _authorizing = NO;
        [self failWaiting:@"INTERNAL"];
        return;
    }
    [_handlers setObject:[[^(const exteria_mt_rpc_result *result) {
        _authorizing = NO;
        if (result->status != EXTERIA_OK) {
            [self failWaiting:ExteriaRpcErrorName(result)];
            return;
        }
        NSArray *jobs = [[_waiting copy] autorelease];
        [_waiting removeAllObjects];
        for (ExteriaMediaJob *job in jobs) [self submitJob:job];
    } copy] autorelease] forKey:[NSNumber numberWithUnsignedLongLong:id]];
}

#pragma mark client callbacks

static exteria_status ExteriaMediaSend(void *ctx, int32_t dc, const uint8_t *data, size_t len) {
    ExteriaMediaLink *link = ctx;
    (void)dc;
    if (link->_socket.fd < 0) return EXTERIA_E_STATE;
    return exteria_mt_socket_write_all(&link->_socket, data, len, WRITE_TIMEOUT_MS);
}

static exteria_status ExteriaMediaLoad(void *ctx, int32_t dc, exteria_mt_session_state *out) {
    ExteriaMediaLink *link = ctx;
    uint8_t buf[EXTERIA_SESSION_FILE_LEN + 1];
    size_t len;
    NSString *path = ExteriaSessionPath(link->_directory, dc);
    exteria_status status = ExteriaReadFile(path, buf, sizeof(buf), &len);
    if (status != EXTERIA_OK) return status;
    status = exteria_session_unpack(buf, len, dc, out);
    exteria_wipe(buf, sizeof(buf));
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: session file for dc %d is unusable, starting a new session", (int)dc);
        unlink(path.fileSystemRepresentation);
        return EXTERIA_E_NOTFOUND;
    }
    return EXTERIA_OK;
}

static exteria_status ExteriaMediaSave(void *ctx, int32_t dc, const exteria_mt_session_state *state) {
    ExteriaMediaLink *link = ctx;
    uint8_t buf[EXTERIA_SESSION_FILE_LEN];
    size_t len;
    exteria_status status = exteria_session_pack(dc, state, buf, sizeof(buf), &len);
    if (status == EXTERIA_OK) status = ExteriaWriteFile(ExteriaSessionPath(link->_directory, dc), buf, len);
    exteria_wipe(buf, sizeof(buf));
    return status;
}

static void ExteriaMediaResult(void *ctx, uint64_t id, const exteria_mt_rpc_result *result) {
    ExteriaMediaLink *link = ctx;
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:id];
    void (^handler)(const exteria_mt_rpc_result *) = [[link->_handlers objectForKey:key] retain];
    if (!handler) return;
    [link->_handlers removeObjectForKey:key];
    handler(result);
    [handler release];
}

static void ExteriaMediaError(void *ctx, exteria_status status, const char *boundary) {
    (void)ctx;
    NSLog(@"exteria: media link error at %s: %s", boundary, exteria_status_name(status));
}

#pragma mark worker

- (exteria_status)initClient {
    exteria_mt_client_config config;
    exteria_client_events events;
    memset(&config, 0, sizeof(config));
    memset(&events, 0, sizeof(events));
    config.dc_id = _dc;
    config.transport = EXTERIA_MT_INTERMEDIATE;
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
    events.send = ExteriaMediaSend;
    events.load_session = ExteriaMediaLoad;
    events.save_session = ExteriaMediaSave;
    events.error = ExteriaMediaError;
    events.result = ExteriaMediaResult;
    exteria_status status = exteria_client_init(&_client, &config, EXTERIA_API_HASH, &events);
    _clientLive = status == EXTERIA_OK;
    return status;
}

/* every request still waiting is failed, so no download hangs after the link gave up */
- (void)failEverything:(NSString *)error {
    exteria_mt_rpc_result failed;
    memset(&failed, 0, sizeof(failed));
    failed.status = EXTERIA_E_STATE;
    NSArray *handlers = [_handlers allValues];
    [_handlers removeAllObjects];
    for (void (^handler)(const exteria_mt_rpc_result *) in handlers) handler(&failed);
    [self failWaiting:error];
    _authorizing = NO;
}

- (void)linkLost:(exteria_status)reason {
    int32_t transport = _clientLive ? exteria_mt_client_transport_error(&_client.mt) : 0;
    int64_t securityValue = 0;
    const char *securityNote = _clientLive ? exteria_mt_client_security_note(&_client.mt, &securityValue) : NULL;
    NSLog(@"exteria: media link to dc %d lost: %s (transport error %d%s%s %lld)", (int)_dc, exteria_status_name(reason), (int)transport,
          securityNote ? ", refused: " : "", securityNote ? securityNote : "", (long long)securityValue);
    exteria_mt_socket_close(&_socket);
    if (_clientLive) exteria_client_disconnected(&_client);
    if (transport == -404) {
        /* the server forgot the key: a new handshake replaces it, and the account signs in again on the first job */
        unlink(ExteriaSessionPath(_directory, _dc).fileSystemRepresentation);
        exteria_client_free(&_client);
        _clientLive = NO;
        [self failEverything:@"OFFLINE"];
        if ([self initClient] != EXTERIA_OK) _wantLink = NO;
        _failures = 0;
        return;
    }
    if (++_failures >= RETRY_LIMIT) {
        _wantLink = NO;
        [self failEverything:@"OFFLINE"];
        return;
    }
    _retryAt = ExteriaMediaNowMs() + (1000u << (_failures - 1));
}

- (void)openLink {
    exteria_status status = ExteriaProxyConnect(_shiro, &_socket, exteria_dc_host(_dc), exteria_dc_port(), CONNECT_TIMEOUT_MS, &_client.config, NULL);
    if (status == EXTERIA_OK) {
        _client.mt.config.transport = _client.config.transport;
        _client.mt.config.obfuscation = _client.config.obfuscation;
    }
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
        if ((status != EXTERIA_OK && status != EXTERIA_E_RETRY) || _client.mt.state == EXTERIA_MT_CLIENT_DEAD) {
            [self linkLost:status != EXTERIA_OK ? status : EXTERIA_E_STATE];
            return;
        }
    }
}

- (void)drainCommands {
    [_lock lock];
    NSArray *batch = [[_commands copy] autorelease];
    [_commands removeAllObjects];
    [_lock unlock];
    for (void (^command)(void) in batch) command();
}

- (void)run {
    NSAutoreleasePool *setup = [[NSAutoreleasePool alloc] init];
    exteria_status status = [self initClient];
    if (status != EXTERIA_OK) NSLog(@"exteria: media link start failed: %s", exteria_status_name(status));
    [setup drain];

    while (_clientLive && ![self isStopping]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [self drainCommands];
        if (_wantLink && _socket.fd < 0 && ExteriaMediaNowMs() >= _retryAt) [self openLink];
        uint32_t next = POLL_CAP_MS;
        if (_clientLive && exteria_client_tick(&_client, &next) != EXTERIA_OK) next = POLL_CAP_MS;
        /* only a frame the server sent and the client accepted counts as a link that works, as on the main link */
        if (_socket.fd >= 0 && _client.mt.state == EXTERIA_MT_CLIENT_READY && exteria_mt_client_heard(&_client.mt)) _failures = 0;
        if (next > POLL_CAP_MS) next = POLL_CAP_MS;
        if (_wantLink && _socket.fd < 0) {
            uint64_t now = ExteriaMediaNowMs();
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
            NSLog(@"exteria: media link poll failed, errno %d", errno);
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
    exteria_mt_socket_close(&_socket);
    if (_clientLive) exteria_client_free(&_client);
    _clientLive = NO;
    [self failEverything:@"OFFLINE"];
    [teardown drain];
    dispatch_semaphore_signal(_exited);
}

@end
