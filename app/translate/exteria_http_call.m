#import "exteria_http_call.h"

#define REDIRECTS_MAX 3

NSString *ExteriaURLEscape(NSString *text) {
    NSString *escaped = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)text, NULL, CFSTR("!*'();:@&=+$,/?#[]%"), kCFStringEncodingUTF8);
    return [escaped autorelease];
}

@interface ExteriaHttpCall () {
    NSURLConnection *_connection;
    NSMutableData *_data;
    NSString *_host;
    NSUInteger _limit;
    NSInteger _status;
    NSUInteger _redirects;
    BOOL _sameSite;
    NSURL *_responseURL;
    NSDictionary *_responseHeaders;
    ExteriaHttpCompletion _completion;
}
@end

@implementation ExteriaHttpCall

@synthesize responseURL = _responseURL;
@synthesize responseHeaders = _responseHeaders;

+ (ExteriaHttpCall *)startRequest:(NSURLRequest *)request limit:(NSUInteger)limit timeout:(NSTimeInterval)timeout completion:(ExteriaHttpCompletion)completion {
    return [self startRequest:request limit:limit timeout:timeout sameSite:NO completion:completion];
}

/* the last two labels of a host name, which is enough to tell www.bing.com from cn.bing.com and from bing.evil.example */
static NSString *ExteriaSiteOf(NSString *host) {
    NSArray *labels = [[host lowercaseString] componentsSeparatedByString:@"."];
    if (labels.count < 2) return host;
    return [NSString stringWithFormat:@"%@.%@", [labels objectAtIndex:labels.count - 2], [labels lastObject]];
}

+ (ExteriaHttpCall *)startRequest:(NSURLRequest *)request limit:(NSUInteger)limit timeout:(NSTimeInterval)timeout sameSite:(BOOL)sameSite completion:(ExteriaHttpCompletion)completion {
    ExteriaHttpCall *call = [[[ExteriaHttpCall alloc] init] autorelease];
    call->_sameSite = sameSite;
    call->_limit = limit;
    call->_completion = [completion copy];
    call->_data = [[NSMutableData alloc] init];
    call->_host = [[[request URL] host] copy];
    /* the connection holds its delegate until it finishes, which keeps the call alive without the caller holding it */
    call->_connection = [[NSURLConnection alloc] initWithRequest:request delegate:call startImmediately:NO];
    if (!call->_connection) {
        [call finishWithBody:nil failure:@"no connection"];
        return call;
    }
    [call->_connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [call->_connection start];
    [call performSelector:@selector(timedOut) withObject:nil afterDelay:timeout];
    return call;
}

- (void)dealloc {
    [_connection release];
    [_data release];
    [_host release];
    [_responseURL release];
    [_responseHeaders release];
    [_completion release];
    [super dealloc];
}

- (void)stop {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timedOut) object:nil];
    [_connection cancel];
    [_connection release];
    _connection = nil;
}

- (void)cancel {
    [self stop];
    [_completion release];
    _completion = nil;
}

- (void)finishWithBody:(NSData *)body failure:(NSString *)failure {
    ExteriaHttpCompletion done = _completion;
    _completion = nil;
    [self stop];
    if (done) {
        done(body, failure ? 0 : _status, failure);
        [done release];
    }
}

- (void)timedOut {
    [self finishWithBody:nil failure:@"timeout"];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    (void)connection;
    if (!response) return request;
    NSURL *target = [request URL];
    NSString *host = [[target host] lowercaseString];
    BOOL sameHost = [host isEqualToString:[_host lowercaseString]] || (_sameSite && [ExteriaSiteOf(host) isEqualToString:ExteriaSiteOf(_host)]);
    if (++_redirects > REDIRECTS_MAX || ![[target scheme] isEqualToString:@"https"] || !sameHost) {
        [self finishWithBody:nil failure:@"redirect refused"];
        return nil;
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    (void)connection;
    _status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    [_responseURL release];
    _responseURL = [[response URL] retain];
    [_responseHeaders release];
    _responseHeaders = nil;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) _responseHeaders = [[(NSHTTPURLResponse *)response allHeaderFields] retain];
    [_data setLength:0];
    if ([response expectedContentLength] > 0 && (unsigned long long)[response expectedContentLength] > _limit) [self finishWithBody:nil failure:@"answer too large"];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    (void)connection;
    if (_data.length + data.length > _limit) {
        [self finishWithBody:nil failure:@"answer too large"];
        return;
    }
    [_data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    (void)connection;
    [self finishWithBody:[[_data copy] autorelease] failure:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    (void)connection;
    [self finishWithBody:nil failure:[error localizedDescription] ? [error localizedDescription] : @"network error"];
}

/* keys and texts do not belong in the cache of the system */
- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    (void)connection;
    (void)cachedResponse;
    return nil;
}

@end
