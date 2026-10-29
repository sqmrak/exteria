#import "exteria_tunnel_protocol.h"

#import "exteria_shiro_network.h"
#include "exteria_https.h"
#include "exteria_article.h"

#define TIMEOUT_MS 25000
#define REDIRECTS_MAX 4

static NSString *const ExteriaTunnelHandledKey = @"exteria.tunnel.handled";
static NSString *const ExteriaTunnelRedirectsKey = @"exteria.tunnel.redirects";

/* what one load shares with the thread that runs it: the cancel flag the HTTPS client polls */
@interface ExteriaTunnelJob : NSObject {
@public
    volatile int cancelled;
}
@end
@implementation ExteriaTunnelJob
@end

static int ExteriaTunnelCancelled(void *context) {
    return ((ExteriaTunnelJob *)context)->cancelled;
}

static BOOL ExteriaTunnelHostAllowed(NSString *host) {
    host = [host lowercaseString];
    return [host isEqualToString:@"telegra.ph"] || [host isEqualToString:@"www.telegra.ph"];
}

/* the trusted roots of the web loads: the roots of the account call and the one the telegra.ph chain ends in */
static NSData *ExteriaTunnelRoots(void) {
    static NSData *roots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *base = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"]];
        NSData *web = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"web-roots" ofType:@"pem"]];
        if (base.length && web.length) {
            NSMutableData *both = [NSMutableData dataWithData:base];
            [both appendData:web];
            roots = [both copy];
        } else {
            NSLog(@"exteria: the roots for telegra.ph are missing");
        }
    });
    return roots;
}

static NSDictionary *ExteriaTunnelHeaders(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@"\r\n"]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [headers setObject:value forKey:name];
    }
    return headers;
}

/* the path and the query of a URL as they go on the request line, or nil when they are not something to send */
static NSString *ExteriaTunnelPath(NSURL *url) {
    NSString *absolute = url.absoluteString;
    NSRange scheme = [absolute rangeOfString:@"://"];
    if (scheme.location == NSNotFound) return nil;
    NSString *rest = [absolute substringFromIndex:scheme.location + 3];
    NSRange fragment = [rest rangeOfString:@"#"];
    if (fragment.location != NSNotFound) rest = [rest substringToIndex:fragment.location];
    NSRange slash = [rest rangeOfString:@"/"];
    NSString *path = slash.location == NSNotFound ? @"/" : [rest substringFromIndex:slash.location];
    if ([path rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) return nil;
    return path;
}

@interface ExteriaArticleLoad ()
- (BOOL)isCancelled;
@end

static int ExteriaArticleCancelled(void *context) {
    return [(ExteriaArticleLoad *)context isCancelled] ? 1 : 0;
}

@implementation ExteriaArticleLoad
- (BOOL)isCancelled { return _cancelled != 0; }
- (void)cancel { _cancelled = 1; }
- (void)startURL:(NSURL *)url completion:(void (^)(NSData *, NSURL *, NSString *))completion {
    void (^done)(NSData *, NSURL *, NSString *) = [completion copy];
    NSURL *first = [url retain];
    [self retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSURL *current = first;
        NSData *html = nil;
        NSString *error = nil;
        NSData *roots = ExteriaTunnelRoots();
        for (int hop = 0; hop <= REDIRECTS_MAX && !_cancelled; ++hop) {
            exteria_https_request request;
            exteria_https_response response;
            const char *headers[] = {"Accept: text/html", "Accept-Encoding: identity", "User-Agent: Exteria", NULL};
            NSString *path = ExteriaTunnelPath(current);
            memset(&request, 0, sizeof(request));
            memset(&response, 0, sizeof(response));
            if (!roots.length || !path || ![[current.scheme lowercaseString] isEqualToString:@"https"] || !ExteriaTunnelHostAllowed(current.host) ||
                (current.port && current.port.integerValue != 443) || current.user.length || current.password.length) {
                error = @"invalid article address or missing trust roots";
                break;
            }
            request.host = current.host.UTF8String;
            request.path = path.UTF8String;
            request.port = 443;
            request.headers = headers;
            request.roots_pem = roots.bytes;
            request.roots_len = roots.length;
            request.timeout_ms = TIMEOUT_MS;
            request.max_response = EXTERIA_HTTPS_MAX_RESPONSE_LIMIT;
            request.connect_socket = ExteriaShiroNetworkConnectSocket;
            request.is_cancelled = ExteriaArticleCancelled;
            request.cancel_ctx = self;
            exteria_status status = exteria_https_get(&request, &response);
            if (status != EXTERIA_OK) {
                error = [NSString stringWithUTF8String:exteria_status_name(status)];
            } else {
                NSDictionary *fields = ExteriaTunnelHeaders(response.headers);
                NSString *type = [[fields objectForKey:@"content-type"] lowercaseString];
                NSString *encoding = [[fields objectForKey:@"content-encoding"] lowercaseString];
                NSString *location = [fields objectForKey:@"location"];
                if ((response.status == 301 || response.status == 302 || response.status == 303 || response.status == 307 || response.status == 308) && location.length) {
                    NSURL *next = [[NSURL URLWithString:location relativeToURL:current] absoluteURL];
                    if (hop == REDIRECTS_MAX || !next) error = @"invalid article redirect";
                    else current = next;
                } else if (response.status != 200) error = [NSString stringWithFormat:@"HTTP %d", response.status];
                else if (![type hasPrefix:@"text/html"] || (encoding.length && ![encoding isEqualToString:@"identity"])) error = @"unsupported article response";
                else {
                    NSMutableData *readable = [NSMutableData dataWithLength:response.body_len];
                    size_t length = 0;
                    status = exteria_article_readonly(response.body, response.body_len, readable.mutableBytes, readable.length, &length);
                    if (status != EXTERIA_OK) error = [NSString stringWithUTF8String:exteria_status_name(status)];
                    else if (!length) error = @"empty article";
                    else { [readable setLength:length]; html = readable; }
                }
            }
            exteria_https_response_free(&response);
            if (html || error) break;
        }
        if (!_cancelled) {
            NSData *result = [html retain];
            NSURL *address = [current retain];
            NSString *failure = [error copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!_cancelled && done) done(result, address, failure);
                [result release]; [address release]; [failure release];
                [done release]; [self release];
            });
        } else {
            [done release];
            [self release];
        }
        [first release];
        [pool drain];
    });
}
@end

@interface ExteriaTunnelURLProtocol () {
    ExteriaTunnelJob *_job;
    NSThread *_thread;
}
@end

@implementation ExteriaTunnelURLProtocol

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ [NSURLProtocol registerClass:self]; });
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (![[url.scheme lowercaseString] isEqualToString:@"https"] || !ExteriaTunnelHostAllowed(url.host)) return NO;
    if (request.HTTPMethod.length && ![request.HTTPMethod isEqualToString:@"GET"]) return NO;
    if ([NSURLProtocol propertyForKey:ExteriaTunnelHandledKey inRequest:request]) return NO;
    /* ios 6 cannot complete the telegra.ph TLS handshake, and UIWebView cannot follow the app's tunnel route */
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)dealloc {
    [_job release];
    [_thread release];
    [super dealloc];
}

- (void)startLoading {
    _job = [[ExteriaTunnelJob alloc] init];
    _thread = [[NSThread currentThread] retain];
    NSURLRequest *original = self.request;
    NSURL *url = [original.URL retain];
    ExteriaTunnelJob *job = [_job retain];
    NSString *agent = [original valueForHTTPHeaderField:@"User-Agent"];
    NSString *accept = [original valueForHTTPHeaderField:@"Accept"];
    NSString *language = [original valueForHTTPHeaderField:@"Accept-Language"];
    NSNumber *redirects = [NSURLProtocol propertyForKey:ExteriaTunnelRedirectsKey inRequest:original];
    [self retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *path = ExteriaTunnelPath(url);
        NSData *roots = ExteriaTunnelRoots();
        exteria_https_response response;
        memset(&response, 0, sizeof(response));
        exteria_status status = EXTERIA_E_ARG;
        if (path && roots.length) {
            NSMutableArray *lines = [NSMutableArray arrayWithObject:@"Accept-Encoding: identity"];
            if (agent.length && ![agent rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].length) [lines addObject:[@"User-Agent: " stringByAppendingString:agent]];
            if (accept.length && ![accept rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].length) [lines addObject:[@"Accept: " stringByAppendingString:accept]];
            if (language.length && ![language rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].length) [lines addObject:[@"Accept-Language: " stringByAppendingString:language]];
            const char *rows[6] = {0};
            for (NSUInteger i = 0; i < lines.count && i < 5; ++i) rows[i] = [[lines objectAtIndex:i] UTF8String];
            exteria_https_request request;
            memset(&request, 0, sizeof(request));
            request.host = url.host.UTF8String;
            request.path = path.UTF8String;
            request.port = 443;
            request.headers = rows;
            request.roots_pem = roots.bytes;
            request.roots_len = roots.length;
            request.timeout_ms = TIMEOUT_MS;
            request.max_response = EXTERIA_HTTPS_MAX_RESPONSE_LIMIT;
            request.is_cancelled = ExteriaTunnelCancelled;
            request.cancel_ctx = job;
            request.connect_socket = ExteriaShiroNetworkConnectSocket;
            status = exteria_https_get(&request, &response);
        }
        NSDictionary *reply = status == EXTERIA_OK ? ExteriaTunnelHeaders(response.headers) : nil;
        NSData *body = nil;
        int code = response.status;
        NSString *contentType = [[reply objectForKey:@"content-type"] lowercaseString];
        NSString *encoding = [[reply objectForKey:@"content-encoding"] lowercaseString];
        if (status == EXTERIA_OK && encoding.length && ![encoding isEqualToString:@"identity"]) {
            status = EXTERIA_E_UNSUPPORTED;
        } else if (status == EXTERIA_OK && code >= 200 && code < 300 && [contentType hasPrefix:@"text/html"]) {
            /* Telegraph's Quill editor empties the article before rebuilding it; old WebKit can stop in between */
            NSMutableData *readable = [NSMutableData dataWithLength:response.body_len];
            size_t length = 0;
            status = exteria_article_readonly(response.body, response.body_len, readable.mutableBytes, readable.length, &length);
            if (status == EXTERIA_OK) {
                [readable setLength:length];
                body = readable;
            }
        } else if (status == EXTERIA_OK) body = [NSData dataWithBytes:response.body length:response.body_len];
        exteria_https_response_free(&response);
        NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:status], @"status", [NSNumber numberWithInt:code], @"code",
                                reply ? reply : [NSDictionary dictionary], @"headers", body ? body : [NSData data], @"body", url, @"url",
                                redirects ? redirects : [NSNumber numberWithInt:0], @"redirects", nil];
        if (!job->cancelled) {
            [self performSelector:@selector(finishWithResult:) onThread:_thread withObject:result waitUntilDone:NO modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
        }
        [job release];
        [url release];
        [self release];
        [pool drain];
    });
}

- (void)stopLoading {
    _job->cancelled = 1;
}

- (void)failWith:(NSInteger)code reason:(NSString *)reason {
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:reason, NSLocalizedDescriptionKey, nil];
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:code userInfo:info]];
}

- (void)finishWithResult:(NSDictionary *)result {
    if (_job->cancelled) return;
    exteria_status status = (exteria_status)[[result objectForKey:@"status"] intValue];
    NSURL *url = [result objectForKey:@"url"];
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: %@ through the tunnel failed: %s", url, exteria_status_name(status));
        [self failWith:status == EXTERIA_E_TIMEOUT ? NSURLErrorTimedOut : NSURLErrorCannotConnectToHost
                reason:[NSString stringWithFormat:@"%s", exteria_status_name(status)]];
        return;
    }
    NSInteger code = [[result objectForKey:@"code"] intValue];
    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:[result objectForKey:@"headers"]];
    NSData *body = [result objectForKey:@"body"];
    /* the reply was decoded by the client, and the page that carries these names was not: the framing headers would be wrong for it */
    [headers removeObjectForKey:@"transfer-encoding"];
    [headers removeObjectForKey:@"content-encoding"];
    [headers setObject:[NSString stringWithFormat:@"%lu", (unsigned long)body.length] forKey:@"content-length"];
    NSHTTPURLResponse *answer = [[[NSHTTPURLResponse alloc] initWithURL:url statusCode:code HTTPVersion:@"HTTP/1.1" headerFields:headers] autorelease];
    NSString *location = [headers objectForKey:@"location"];
    if ((code == 301 || code == 302 || code == 303 || code == 307 || code == 308) && location.length) {
        NSUInteger count = (NSUInteger)[[result objectForKey:@"redirects"] intValue];
        NSURL *target = [NSURL URLWithString:location relativeToURL:url];
        target = [NSURL URLWithString:target.absoluteString];
        if (count >= REDIRECTS_MAX || !target || ![[target.scheme lowercaseString] isEqualToString:@"https"] || !ExteriaTunnelHostAllowed(target.host)) {
            [self failWith:NSURLErrorHTTPTooManyRedirects reason:@"redirect"];
            return;
        }
        NSMutableURLRequest *next = [NSMutableURLRequest requestWithURL:target];
        [NSURLProtocol setProperty:[NSNumber numberWithUnsignedInteger:count + 1] forKey:ExteriaTunnelRedirectsKey inRequest:next];
        [self.client URLProtocol:self wasRedirectedToRequest:next redirectResponse:answer];
        return;
    }
    NSLog(@"exteria: %@ through the tunnel: %ld, %lu bytes", url.lastPathComponent.length ? url.lastPathComponent : url.host, (long)code, (unsigned long)body.length);
    [self.client URLProtocol:self didReceiveResponse:answer cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:body];
    [self.client URLProtocolDidFinishLoading:self];
}

@end
