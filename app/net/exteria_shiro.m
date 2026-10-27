#import "exteria_shiro.h"
#import "exteria_traffic_store.h"
#include "exteria_mt_traffic.h"

#import <UIKit/UIKit.h>

#include <pthread.h>
#include <stdarg.h>
#include <sys/utsname.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "exteria_bytes.h"
#include "exteria_dns.h"
#include "exteria_https.h"
#include "exteria_random.h"
#include "exteria_shiro_engine.h"
#include "exteria_shiro_store.h"
#include "exteria_warp.h"

#import "exteria_files.h"
#import "exteria_shiro_network.h"

NSString *const ExteriaShiroStateDidChangeNotification = @"ExteriaShiroStateDidChange";
static NSString *const ExteriaShiroEnabledKey = @"exteria.shiro.enabled";
static NSString *const ExteriaShiroAccountFile = @"shiro.account";

/* the registration call of the account; the path carries the version of the API and the header the build of the
   official client it was taken from, so they change together */
#define REGISTRATION_HOST "api.cloudflareclient.com"
#define REGISTRATION_PORT 443
#define REGISTRATION_PATH "/v0a4471/reg"
#define REGISTRATION_VERSION "CF-Client-Version: a-6.38-4471"
#define REGISTRATION_TIMEOUT_MS 15000
/* the first servers are the ones of the account, the rest are drawn; a silent network stops here instead of dialing for ever */
#define SERVER_ATTEMPTS 5u
/* the journal keeps the last lines of a run, so a report of a failure carries how it came about */
#define LOG_LINES_MAX 400u
#define LOG_LINES_DROP 100u
#define INSTALL_ID_ALPHABET "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

typedef struct {
    ExteriaShiro *owner;
    uint32_t run;
    uint32_t serial;
} ExteriaShiroContext;

@interface ExteriaShiro () {
    NSString *_directory;
    /* account file, registration, and the start and stop of engines, one after another */
    dispatch_queue_t _queue;
    /* a stream is opened under the read side, so an engine cannot be freed while a caller is inside it; main never takes the write side */
    pthread_rwlock_t _engineLock;
    exteria_shiro_engine *_engine;
    /* queue only */
    ExteriaShiroContext *_context;
    exteria_warp_identity _identity;
    BOOL _identityLoaded;
    /* guards what other threads read: the route and the run that is still wanted */
    NSLock *_stateLock;
    ExteriaShiroRoute _route;
    uint32_t _liveRun;
    /* main thread only */
    ExteriaShiroState _state;
    ExteriaShiroFailure _failure;
    NSString *_failureDetail;
    NSString *_failureText;
    NSLock *_logLock;
    NSMutableArray *_log;
    /* queue only: the status line of the last registration call, for the words of the failure */
    int _registrationHttp;
    BOOL _enabled;
    uint32_t _run;
    /* every engine start gets a number, so a late word from an engine that was replaced is told apart */
    uint32_t _serial;
    unsigned _attempt;
    ExteriaShiroStats _lastStats;
}
@end

@implementation ExteriaShiro

@synthesize state = _state;
@synthesize failure = _failure;
@synthesize enabled = _enabled;

- (id)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _directory = [directory copy];
    _queue = dispatch_queue_create("exteria.shiro", NULL);
    pthread_rwlock_init(&_engineLock, NULL);
    _stateLock = [[NSLock alloc] init];
    _logLock = [[NSLock alloc] init];
    _log = [[NSMutableArray alloc] init];
    _enabled = [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaShiroEnabledKey];
    /* a launch with the VPN wanted starts blocked, so nothing is sent before the tunnel is up */
    _route = _enabled ? ExteriaShiroRouteBlocked : ExteriaShiroRouteDirect;
    return self;
}

- (void)dealloc {
    dispatch_sync(_queue, ^{ [self stopEngine]; });
    dispatch_release(_queue);
    pthread_rwlock_destroy(&_engineLock);
    exteria_wipe(&_identity, sizeof(_identity));
    [_stateLock release];
    [_directory release];
    [_failureDetail release];
    [_failureText release];
    [_log release];
    [_logLock release];
    [super dealloc];
}

#pragma mark journal

static void ExteriaShiroStamp(char out[16]) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    time_t seconds = (time_t)now;
    struct tm parts;
    gmtime_r(&seconds, &parts);
    int millis = (int)((now - (NSTimeInterval)seconds) * 1000.0);
    if (millis < 0 || millis > 999) millis = 0;
    snprintf(out, 16, "%02d:%02d:%02d.%03d", parts.tm_hour, parts.tm_min, parts.tm_sec, millis);
}

/* any thread: the engine reports from its own */
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list arguments;
    va_start(arguments, format);
    NSString *text = [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
    va_end(arguments);
    char stamp[16];
    ExteriaShiroStamp(stamp);
    NSLog(@"exteria: shiro: %@", text);
    [_logLock lock];
    [_log addObject:[NSString stringWithFormat:@"%s %@", stamp, text]];
    if (_log.count > LOG_LINES_MAX) [_log removeObjectsInRange:NSMakeRange(0, LOG_LINES_DROP)];
    [_logLock unlock];
}

- (NSString *)logText {
    struct utsname machine;
    uname(&machine);
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *state[] = {@"off", @"registering", @"connecting", @"up", @"failed"};
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"Exteria %@ (%@)\n", [info objectForKey:@"CFBundleShortVersionString"], [info objectForKey:@"CFBundleVersion"]];
    [text appendFormat:@"%s, iOS %@, %@ network\n", machine.machine, [[UIDevice currentDevice] systemVersion], ExteriaNetworkOnCellular() ? @"cellular" : @"other"];
    ExteriaShiroState now = _state;
    [text appendFormat:@"shiro: %@%@%@\n", state[now], _failureDetail.length ? @", " : @"", _failureDetail ? _failureDetail : @""];
    [_logLock lock];
    for (NSString *line in _log) [text appendFormat:@"%@\n", line];
    [_logLock unlock];
    return text;
}

#pragma mark state

- (ExteriaShiroRoute)route {
    [_stateLock lock];
    ExteriaShiroRoute route = _route;
    [_stateLock unlock];
    return route;
}

- (BOOL)runIsLive:(uint32_t)run {
    [_stateLock lock];
    BOOL live = _liveRun == run;
    [_stateLock unlock];
    return live;
}

/* main thread */
- (uint32_t)newRun {
    ++_run;
    [_stateLock lock];
    _liveRun = _run;
    [_stateLock unlock];
    return _run;
}

- (void)setState:(ExteriaShiroState)state failure:(ExteriaShiroFailure)failure {
    _state = state;
    _failure = failure;
    ExteriaShiroRoute route = !_enabled ? ExteriaShiroRouteDirect : (state == ExteriaShiroStateUp ? ExteriaShiroRouteTunnel : ExteriaShiroRouteBlocked);
    [_stateLock lock];
    _route = route;
    [_stateLock unlock];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaShiroStateDidChangeNotification object:self];
}

- (void)resume {
    if (_enabled) [self begin];
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) return;
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ExteriaShiroEnabledKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the VPN switch was not saved");
    if (enabled) {
        [self begin];
        return;
    }
    [self newRun];
    [self setState:ExteriaShiroStateOff failure:ExteriaShiroFailureNone];
    dispatch_async(_queue, ^{ [self stopEngine]; });
}

- (void)retry {
    if (!_enabled || _state != ExteriaShiroStateFailed) return;
    /* a key the server refused is the account's own, so the try that follows makes a new account */
    [self beginDiscardingAccount:_failure == ExteriaShiroFailureKey];
}

- (void)begin {
    [self beginDiscardingAccount:NO];
}

- (void)beginDiscardingAccount:(BOOL)discard {
    uint32_t run = [self newRun];
    uint32_t serial = ++_serial;
    _attempt = 0;
    [self log:@"start, run %u%@", run, discard ? @", the stored account is dropped" : @""];
    [self setState:ExteriaShiroStateConnecting failure:ExteriaShiroFailureNone];
    dispatch_async(_queue, ^{ [self prepareRun:run serial:serial discardAccount:discard]; });
}

- (NSString *)failureDetail {
    return _failureDetail;
}

- (NSString *)failureText {
    return _failureText;
}

- (void)failRun:(uint32_t)run with:(ExteriaShiroFailure)failure detail:(NSString *)detail text:(NSString *)text {
    if (run != _run || !_enabled) return;
    [self log:@"failed: %@", detail];
    [_failureDetail release];
    _failureDetail = [detail copy];
    [_failureText release];
    _failureText = [text copy];
    [self newRun];
    [self setState:ExteriaShiroStateFailed failure:failure];
    dispatch_async(_queue, ^{ [self stopEngine]; });
}

- (void)registeringRun:(uint32_t)run {
    if (run != _run || !_enabled) return;
    [self setState:ExteriaShiroStateRegistering failure:ExteriaShiroFailureNone];
}

- (void)connectingRun:(uint32_t)run {
    if (run != _run || !_enabled) return;
    [self setState:ExteriaShiroStateConnecting failure:ExteriaShiroFailureNone];
}

/* main thread, from the engine's callback */
- (void)engineState:(exteria_shiro_state)state reason:(exteria_status)reason run:(uint32_t)run serial:(uint32_t)serial {
    if (run != _run || serial != _serial || !_enabled) return;
    if (state == EXTERIA_SHIRO_UP) {
        _attempt = 0;
        [self log:@"the tunnel is up"];
        [self setState:ExteriaShiroStateUp failure:ExteriaShiroFailureNone];
        return;
    }
    if (state != EXTERIA_SHIRO_DOWN) return;
    BOOL wasUp = _state == ExteriaShiroStateUp;
    /* a tunnel that was working starts again from the account's own server; one that never answered goes on to the next server */
    _attempt = wasUp ? 0 : _attempt + 1;
    if (_attempt >= SERVER_ATTEMPTS) {
        BOOL refused = reason == EXTERIA_E_SECURITY;
        [self failRun:run with:refused ? ExteriaShiroFailureKey : ExteriaShiroFailureServer
               detail:[NSString stringWithFormat:@"tunnel: %s", exteria_status_name(reason)]
                 text:NSLocalizedString(refused ? @"shiro.why.key" : @"shiro.why.server", nil)];
        return;
    }
    [self log:@"the tunnel went down (%s), next server is %u", exteria_status_name(reason), _attempt];
    uint32_t next = ++_serial;
    unsigned attempt = _attempt;
    [self setState:ExteriaShiroStateConnecting failure:ExteriaShiroFailureNone];
    dispatch_async(_queue, ^{ [self startEngineForRun:run serial:next attempt:attempt]; });
}

static void ExteriaShiroEngineState(void *context, exteria_shiro_state state, exteria_status reason) {
    ExteriaShiroContext *c = context;
    ExteriaShiro *owner = c->owner;
    uint32_t run = c->run, serial = c->serial;
    dispatch_async(dispatch_get_main_queue(), ^{ [owner engineState:state reason:reason run:run serial:serial]; });
}

static void ExteriaShiroEngineTrace(void *context, const char *line) {
    ExteriaShiroContext *c = context;
    [c->owner log:@"engine: %s", line];
}

#pragma mark queue

- (NSString *)accountPath {
    return ExteriaFilePath(_directory, ExteriaShiroAccountFile);
}

/* EXTERIA_E_NOTFOUND when there is no usable account; an unreadable one is deleted, since only a new registration repairs it */
- (exteria_status)loadIdentity {
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN + 1];
    size_t len = 0;
    exteria_status status = ExteriaReadFile([self accountPath], buf, sizeof(buf), &len);
    if (status != EXTERIA_OK) return status;
    status = exteria_shiro_store_unpack(buf, len, &_identity);
    exteria_wipe(buf, sizeof(buf));
    if (status != EXTERIA_OK) {
        [self log:@"account: the stored one is unusable, registering a new one"];
        unlink([self accountPath].fileSystemRepresentation);
        return EXTERIA_E_NOTFOUND;
    }
    return EXTERIA_OK;
}

- (exteria_status)storeIdentity {
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN];
    size_t len = 0;
    exteria_status status = exteria_shiro_store_pack(&_identity, buf, sizeof(buf), &len);
    if (status == EXTERIA_OK) status = ExteriaWriteFile([self accountPath], buf, len);
    exteria_wipe(buf, sizeof(buf));
    return status;
}

static exteria_status ExteriaShiroInstallId(char id[EXTERIA_WARP_INSTALL_ID_LEN + 1]) {
    size_t filled = 0;
    for (int round = 0; round < 8 && filled < EXTERIA_WARP_INSTALL_ID_LEN; ++round) {
        uint8_t raw[32];
        if (exteria_random(raw, sizeof(raw)) != EXTERIA_OK) return EXTERIA_E_CRYPTO;
        for (size_t i = 0; i < sizeof(raw) && filled < EXTERIA_WARP_INSTALL_ID_LEN; ++i) {
            /* 248 is the largest multiple of 62 in a byte, so the letters come out evenly */
            if (raw[i] < 248) id[filled++] = INSTALL_ID_ALPHABET[raw[i] % 62];
        }
    }
    id[filled] = '\0';
    return filled == EXTERIA_WARP_INSTALL_ID_LEN ? EXTERIA_OK : EXTERIA_E_CRYPTO;
}

static void ExteriaShiroTimestamp(char out[32]) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    time_t seconds = (time_t)now;
    struct tm parts;
    gmtime_r(&seconds, &parts);
    int millis = (int)((now - (NSTimeInterval)seconds) * 1000.0);
    if (millis < 0 || millis > 999) millis = 0;
    snprintf(out, 32, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday, parts.tm_hour, parts.tm_min, parts.tm_sec,
             millis);
}

/* makes the account on the first start */
- (exteria_status)registerIdentity {
    NSString *rootsPath = [[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"];
    NSData *roots = rootsPath ? [NSData dataWithContentsOfFile:rootsPath] : nil;
    _registrationHttp = 0;
    if (![roots length]) {
        [self log:@"registration: the bundled roots are missing"];
        return EXTERIA_E_NOTFOUND;
    }

    uint8_t privateKey[EXTERIA_WG_KEY_LEN], publicKey[EXTERIA_WG_KEY_LEN];
    char installId[EXTERIA_WARP_INSTALL_ID_LEN + 1], tos[32], body[1024];
    size_t bodyLen = 0;
    exteria_status status = exteria_warp_generate_key(privateKey, publicKey);
    if (status == EXTERIA_OK) status = ExteriaShiroInstallId(installId);
    if (status != EXTERIA_OK) goto done;
    ExteriaShiroTimestamp(tos);
    status = exteria_warp_registration_body(publicKey, installId, tos, body, sizeof(body), &bodyLen);
    if (status != EXTERIA_OK) goto done;

    static const char *const headers[] = {"Content-Type: application/json; charset=UTF-8", "User-Agent: okhttp/3.12.1", REGISTRATION_VERSION, NULL};
    exteria_https_request request;
    exteria_https_response response;
    memset(&request, 0, sizeof(request));
    request.host = REGISTRATION_HOST;
    request.port = REGISTRATION_PORT;
    request.path = REGISTRATION_PATH;
    request.headers = headers;
    request.body = (const uint8_t *)body;
    request.body_len = bodyLen;
    request.roots_pem = roots.bytes;
    request.roots_len = roots.length;
    request.timeout_ms = REGISTRATION_TIMEOUT_MS;
    /* a network that reads the SNI of one segment drops the plain hello; only a dead path is worth a second try */
    for (int split = 0; split < 2; ++split) {
        request.split_hello = split;
        status = exteria_https_post(&request, &response);
        [self log:@"registration: call to %s, hello %s: %s", REGISTRATION_HOST, split ? "in pieces" : "whole", exteria_status_name(status)];
        if (status == EXTERIA_OK || (status != EXTERIA_E_IO && status != EXTERIA_E_TIMEOUT)) break;
    }
    if (status != EXTERIA_OK) goto done;
    _registrationHttp = response.status;
    if (response.status < 200 || response.status > 299) {
        [self log:@"registration: the call answered HTTP %d, %zu bytes", response.status, response.body_len];
        status = EXTERIA_E_RPC;
    } else {
        status = exteria_warp_parse_registration((const char *)response.body, response.body_len, privateKey, &_identity);
        [self log:@"registration: the answer was read: %s", exteria_status_name(status)];
    }
    exteria_https_response_free(&response);
    if (status == EXTERIA_OK) {
        status = [self storeIdentity];
        if (status != EXTERIA_OK) exteria_wipe(&_identity, sizeof(_identity));
    }
done:
    exteria_wipe(privateKey, sizeof(privateKey));
    return status;
}

/* what the person is told when the account could not be made, by what stopped it */
- (NSString *)registrationTextForStatus:(exteria_status)status {
    switch (status) {
    case EXTERIA_E_IO:
    case EXTERIA_E_TIMEOUT: return NSLocalizedString(@"shiro.why.account.net", nil);
    case EXTERIA_E_SECURITY: return NSLocalizedString(@"shiro.why.account.tls", nil);
    case EXTERIA_E_RPC: return [NSString stringWithFormat:NSLocalizedString(@"shiro.why.account.refused", nil), _registrationHttp];
    case EXTERIA_E_MALFORMED: return NSLocalizedString(@"shiro.why.account.answer", nil);
    case EXTERIA_E_NOTFOUND: return NSLocalizedString(@"shiro.why.account.roots", nil);
    default: return [NSString stringWithFormat:NSLocalizedString(@"shiro.why.account.other", nil), exteria_status_name(status)];
    }
}

- (void)prepareRun:(uint32_t)run serial:(uint32_t)serial discardAccount:(BOOL)discard {
    if (![self runIsLive:run]) return;
    if (discard) {
        unlink([self accountPath].fileSystemRepresentation);
        exteria_wipe(&_identity, sizeof(_identity));
        _identityLoaded = NO;
    }
    if (!_identityLoaded) {
        exteria_status status = [self loadIdentity];
        if (status == EXTERIA_E_NOTFOUND) {
            [self log:@"account: none stored, registering"];
            dispatch_async(dispatch_get_main_queue(), ^{ [self registeringRun:run]; });
            status = [self registerIdentity];
            if (status != EXTERIA_OK) [self log:@"registration failed: %s", exteria_status_name(status)];
            dispatch_async(dispatch_get_main_queue(), ^{ [self connectingRun:run]; });
        } else if (status == EXTERIA_OK) {
            [self log:@"account: loaded from the file"];
        }
        if (status != EXTERIA_OK) {
            NSString *detail = [NSString stringWithFormat:@"account: %s", exteria_status_name(status)];
            NSString *text = [self registrationTextForStatus:status];
            dispatch_async(dispatch_get_main_queue(), ^{ [self failRun:run with:ExteriaShiroFailureAccount detail:detail text:text]; });
            return;
        }
        _identityLoaded = YES;
    }
    [self startEngineForRun:run serial:serial attempt:0];
}

- (void)startEngineForRun:(uint32_t)run serial:(uint32_t)serial attempt:(unsigned)attempt {
    [self stopEngine];
    /* a run that ended while this block waited its turn must not bring a tunnel up */
    if (![self runIsLive:run]) return;
    uint32_t ip = 0;
    uint16_t port = 0;
    exteria_status status = exteria_warp_endpoint(&_identity, attempt, &ip, &port);
    if (status == EXTERIA_OK) [self log:@"engine: server %u.%u.%u.%u:%u, try %u", ip >> 24, (ip >> 16) & 255u, (ip >> 8) & 255u, ip & 255u, port, attempt + 1u];
    ExteriaShiroContext *context = status == EXTERIA_OK ? calloc(1, sizeof(*context)) : NULL;
    exteria_shiro_engine *engine = NULL;
    if (context) {
        context->owner = self;
        context->run = run;
        context->serial = serial;
        exteria_shiro_events events = {context, ExteriaShiroEngineState, ExteriaShiroEngineTrace};
        status = exteria_shiro_engine_start(&engine, &_identity, ip, port, &events);
    } else if (status == EXTERIA_OK) {
        status = EXTERIA_E_NOMEM;
    }
    if (status != EXTERIA_OK) {
        [self log:@"the engine did not start: %s", exteria_status_name(status)];
        free(context);
        NSString *detail = [NSString stringWithFormat:@"engine: %s", exteria_status_name(status)];
        NSString *text = [NSString stringWithFormat:NSLocalizedString(@"shiro.why.engine", nil), exteria_status_name(status)];
        dispatch_async(dispatch_get_main_queue(), ^{ [self failRun:run with:ExteriaShiroFailureServer detail:detail text:text]; });
        return;
    }
    pthread_rwlock_wrlock(&_engineLock);
    _engine = engine;
    pthread_rwlock_unlock(&_engineLock);
    _context = context;
}

/* queue only; the write side waits for the streams that are being opened, then the engine ends them and joins its
   thread, so no callback comes after it */
- (void)stopEngine {
    pthread_rwlock_wrlock(&_engineLock);
    exteria_shiro_engine *engine = _engine;
    _engine = NULL;
    if (engine) exteria_shiro_engine_stop(engine);
    pthread_rwlock_unlock(&_engineLock);
    free(_context);
    _context = NULL;
}

#pragma mark use

- (BOOL)stats:(ExteriaShiroStats *)stats {
    if (_state != ExteriaShiroStateUp || pthread_rwlock_tryrdlock(&_engineLock) != 0) {
        if (stats) *stats = _lastStats;
        return NO;
    }
    BOOL got = NO;
    if (_engine) {
        exteria_shiro_stats raw;
        memset(&raw, 0, sizeof(raw));
        exteria_shiro_engine_stats(_engine, &raw);
        _lastStats.bytesIn = raw.bytes_in;
        _lastStats.bytesOut = raw.bytes_out;
        _lastStats.ageMs = raw.session_age_ms;
        _lastStats.handshakes = raw.handshakes;
        got = YES;
    }
    pthread_rwlock_unlock(&_engineLock);
    if (stats) *stats = _lastStats;
    return got;
}

/* resolve through the tunnel to avoid leaking DNS, and cache briefly because map tiles share a few hosts */
#define RESOLVER_ADDRESS 0x01010101u
#define NAME_KEEP_MAX 300

static NSMutableDictionary *ExteriaShiroNames;

- (exteria_status)resolveName:(const char *)host timeout:(int)timeoutMs address:(uint32_t *)address {
    NSString *key = [[NSString stringWithUTF8String:host] lowercaseString];
    if (!key.length || !address) return EXTERIA_E_ARG;
    @synchronized([ExteriaShiro class]) {
        NSDictionary *known = [ExteriaShiroNames objectForKey:key];
        if ([[known objectForKey:@"expires"] timeIntervalSinceNow] > 0) {
            *address = [[known objectForKey:@"ip"] unsignedIntValue];
            return EXTERIA_OK;
        }
    }
    uint8_t packet[2 + EXTERIA_DNS_QUERY_MAX], reply[2 + EXTERIA_DNS_ANSWER_MAX];
    size_t length = 0, have = 0, want = 2;
    uint16_t identifier = 0;
    uint32_t ip = 0, life = 0;
    exteria_status status = exteria_random(&identifier, sizeof(identifier));
    if (status == EXTERIA_OK) status = exteria_dns_query_a(host, identifier, packet + 2, sizeof(packet) - 2, &length);
    if (status != EXTERIA_OK) return status;
    packet[0] = (uint8_t)(length >> 8);
    packet[1] = (uint8_t)length;
    int fd = -1;
    status = [self openStreamToAddress:RESOLVER_ADDRESS port:53 timeout:timeoutMs descriptor:&fd];
    if (status != EXTERIA_OK) return status;
    exteria_mt_socket socket;
    exteria_mt_socket_init(&socket);
    status = exteria_mt_socket_adopt(&socket, fd);
    if (status != EXTERIA_OK) {
        close(fd);
        return status;
    }
    status = exteria_mt_socket_write_all(&socket, packet, length + 2, timeoutMs);
    /* a TCP answer is two bytes of length and the message, and may arrive in pieces */
    while (status == EXTERIA_OK && have < want) {
        size_t got = 0;
        status = exteria_mt_socket_read(&socket, reply + have, want - have, &got, timeoutMs);
        if (status != EXTERIA_OK) break;
        have += got;
        if (want == 2 && have == 2) {
            want = 2 + (((size_t)reply[0] << 8) | reply[1]);
            if (want == 2 || want > sizeof(reply)) status = EXTERIA_E_MALFORMED;
        }
    }
    exteria_mt_socket_close(&socket);
    if (status == EXTERIA_E_EOF) status = EXTERIA_E_IO;
    if (status != EXTERIA_OK) return status;
    status = exteria_dns_answer_a(reply + 2, want - 2, identifier, &ip, &life);
    if (status != EXTERIA_OK) return status;
    @synchronized([ExteriaShiro class]) {
        if (!ExteriaShiroNames) ExteriaShiroNames = [[NSMutableDictionary alloc] init];
        if (ExteriaShiroNames.count > 64) [ExteriaShiroNames removeAllObjects];
        [ExteriaShiroNames setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:ip], @"ip",
                                      [NSDate dateWithTimeIntervalSinceNow:MIN(life, (uint32_t)NAME_KEEP_MAX)], @"expires", nil] forKey:key];
    }
    *address = ip;
    return EXTERIA_OK;
}

- (exteria_status)openStreamToHost:(const char *)host port:(uint16_t)port timeout:(int)timeoutMs descriptor:(int *)fd {
    uint32_t ip = 0;
    if (fd) *fd = -1;
    if (!host || !fd) return EXTERIA_E_ARG;
    /* the data centers of Telegram are addresses; a name is asked of the resolver through the tunnel */
    if (exteria_warp_parse_ipv4(host, strlen(host), &ip) != EXTERIA_OK) {
        exteria_status status = [self resolveName:host timeout:timeoutMs address:&ip];
        if (status != EXTERIA_OK) return status;
    }
    return [self openStreamToAddress:ip port:port timeout:timeoutMs descriptor:fd];
}

- (exteria_status)openStreamToAddress:(uint32_t)ip port:(uint16_t)port timeout:(int)timeoutMs descriptor:(int *)fd {
    if (fd) *fd = -1;
    if (!fd) return EXTERIA_E_ARG;
    if (self.route != ExteriaShiroRouteTunnel) return EXTERIA_E_STATE;
    pthread_rwlock_rdlock(&_engineLock);
    exteria_status status = _engine ? exteria_shiro_engine_open(_engine, ip, port, timeoutMs, fd) : EXTERIA_E_STATE;
    pthread_rwlock_unlock(&_engineLock);
    return status;
}

- (BOOL)transferredIn:(unsigned long long *)bytesIn out:(unsigned long long *)bytesOut {
    BOOL got = NO;
    if (bytesIn) *bytesIn = 0;
    if (bytesOut) *bytesOut = 0;
    if (pthread_rwlock_tryrdlock(&_engineLock) != 0) return NO;
    if (_engine) {
        exteria_shiro_stats raw;
        memset(&raw, 0, sizeof(raw));
        exteria_shiro_engine_stats(_engine, &raw);
        if (bytesIn) *bytesIn = raw.bytes_in;
        if (bytesOut) *bytesOut = raw.bytes_out;
        got = YES;
    }
    pthread_rwlock_unlock(&_engineLock);
    return got;
}

- (exteria_status)openDatagramDescriptor:(int *)fd {
    if (fd) *fd = -1;
    if (!fd) return EXTERIA_E_ARG;
    if (self.route != ExteriaShiroRouteTunnel) return EXTERIA_E_STATE;
    pthread_rwlock_rdlock(&_engineLock);
    exteria_status status = _engine ? exteria_shiro_engine_open_udp(_engine, fd) : EXTERIA_E_STATE;
    pthread_rwlock_unlock(&_engineLock);
    return status;
}

@end

exteria_status ExteriaShiroConnectSocket(ExteriaShiro *shiro, exteria_mt_socket *socket, const char *host, uint16_t port, int timeoutMs, BOOL *tunneled) {
    if (tunneled) *tunneled = NO;
    /* what the new connection carries is counted for the network it was opened on */
    exteria_traffic_set_cellular(ExteriaNetworkOnCellular());
    ExteriaShiroRoute route = shiro ? shiro.route : ExteriaShiroRouteDirect;
    if (route == ExteriaShiroRouteDirect) return exteria_mt_socket_connect(socket, host, port, timeoutMs);
    if (route == ExteriaShiroRouteBlocked) return EXTERIA_E_STATE;
    int fd = -1;
    exteria_status status = [shiro openStreamToHost:host port:port timeout:timeoutMs descriptor:&fd];
    if (status != EXTERIA_OK) return status;
    status = exteria_mt_socket_adopt(socket, fd);
    if (status != EXTERIA_OK) {
        close(fd);
        return status;
    }
    if (tunneled) *tunneled = YES;
    return EXTERIA_OK;
}

/* set once at launch and cleared before the object goes; the readers are the call threads, which the app stops first */
static ExteriaShiro *ExteriaShiroActiveInstance;

void ExteriaShiroSetActive(ExteriaShiro *shiro) {
    @synchronized([ExteriaShiro class]) { ExteriaShiroActiveInstance = shiro; }
}

int ExteriaShiroNetworkRoute(void) {
    ExteriaShiro *shiro = ExteriaShiroActiveInstance;
    return shiro ? (int)shiro.route : (int)ExteriaShiroRouteDirect;
}

exteria_status ExteriaShiroNetworkConnectSocket(exteria_mt_socket *socket, const char *host, uint16_t port, int timeout_ms) {
    ExteriaShiro *shiro;
    @synchronized([ExteriaShiro class]) { shiro=[ExteriaShiroActiveInstance retain]; }
    exteria_status status=ExteriaShiroConnectSocket(shiro, socket, host, port, timeout_ms, NULL);
    [shiro release];
    return status;
}

int ExteriaShiroNetworkTransferred(unsigned long long *bytesIn, unsigned long long *bytesOut) {
    ExteriaShiro *shiro = ExteriaShiroActiveInstance;
    if (bytesIn) *bytesIn = 0;
    if (bytesOut) *bytesOut = 0;
    return shiro ? [shiro transferredIn:bytesIn out:bytesOut] : 0;
}

exteria_status ExteriaShiroNetworkOpenDatagram(int *fd) {
    ExteriaShiro *shiro = ExteriaShiroActiveInstance;
    if (fd) *fd = -1;
    return shiro ? [shiro openDatagramDescriptor:fd] : EXTERIA_E_STATE;
}

exteria_status ExteriaShiroNetworkOpenStream(uint32_t ip, uint16_t port, int timeout_ms, int *fd) {
    ExteriaShiro *shiro = ExteriaShiroActiveInstance;
    if (fd) *fd = -1;
    return shiro ? [shiro openStreamToAddress:ip port:port timeout:timeout_ms descriptor:fd] : EXTERIA_E_STATE;
}
