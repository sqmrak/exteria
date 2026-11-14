#import "exteria_lyrics.h"

#import "exteria_http_call.h"
#import "exteria_lrc.h"
#import "exteria_weak_reference.h"

#define ANSWER_LIMIT (512 * 1024)
#define CALL_TIMEOUT 8.0
#define PLAIN_LINES_MAX 500
#define CACHE_MAX 32

@interface ExteriaLyrics () {
    NSArray *_lines;
    NSArray *_starts;
}
- (id)initWithLines:(NSArray *)lines starts:(NSArray *)starts;
@end

@implementation ExteriaLyrics
@synthesize lines = _lines, starts = _starts;
- (id)initWithLines:(NSArray *)lines starts:(NSArray *)starts {
    self = [super init];
    if (!self) return nil;
    _lines = [lines copy];
    _starts = [starts copy];
    return self;
}
- (void)dealloc {
    [_lines release];
    [_starts release];
    [super dealloc];
}
- (BOOL)synced { return _starts != nil; }
- (NSInteger)activeLineAt:(NSTimeInterval)seconds {
    if (!_starts.count) return -1;
    NSInteger low = 0, high = (NSInteger)_starts.count;
    NSUInteger ms = seconds <= 0 ? 0 : (NSUInteger)(seconds * 1000.0);
    while (low < high) {
        NSInteger middle = low + (high - low) / 2;
        if ([[_starts objectAtIndex:(NSUInteger)middle] unsignedIntegerValue] <= ms) low = middle + 1;
        else high = middle;
    }
    return low - 1;
}
- (NSTimeInterval)startOfLine:(NSInteger)index {
    if (index < 0 || (NSUInteger)index >= _starts.count) return 0;
    return [[_starts objectAtIndex:(NSUInteger)index] unsignedIntegerValue] / 1000.0;
}
@end

/* the answers of this run, by "performer\ntitle"; a miss is stored as NSNull so the same song is not asked for twice, a network failure is not stored */
static NSMutableDictionary *ExteriaLyricsCache(void) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    return cache;
}

static NSString *ExteriaSearchText(NSString *text) {
    if (!text.length) return @"";
    char out[512];
    if (exteria_lrc_search_text([text UTF8String], out, sizeof out) != EXTERIA_OK) return @"";
    NSString *result = [NSString stringWithUTF8String:out];
    return result ? result : @"";
}

static NSString *ExteriaCompareText(NSString *text) {
    NSArray *words = [[text lowercaseString] componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *word in words) if (word.length) [kept addObject:word];
    return [kept componentsJoinedByString:@" "];
}

/* equal, or one contains the other, after both are lowered and stripped of punctuation */
static BOOL ExteriaTextMatches(NSString *expected, NSString *actual) {
    NSString *a = ExteriaCompareText(expected), *b = ExteriaCompareText(actual);
    if (!a.length || !b.length) return NO;
    return [a isEqualToString:b] || [a rangeOfString:b].location != NSNotFound || [b rangeOfString:a].location != NSNotFound;
}

static NSString *ExteriaStringOf(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

/* the lyrics an LRCLIB item holds: its synced text when that parses, else its plain text; nil for an instrumental or an empty item */
static ExteriaLyrics *ExteriaLyricsFromItem(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    NSString *synced = ExteriaStringOf([item objectForKey:@"syncedLyrics"]);
    if (synced.length) {
        NSData *data = [synced dataUsingEncoding:NSUTF8StringEncoding];
        exteria_lrc lrc;
        if (data && exteria_lrc_parse((const char *)[data bytes], [data length], &lrc) == EXTERIA_OK) {
            NSMutableArray *lines = [NSMutableArray arrayWithCapacity:lrc.count];
            NSMutableArray *starts = [NSMutableArray arrayWithCapacity:lrc.count];
            for (size_t i = 0; i < lrc.count; ++i) {
                NSString *line = [NSString stringWithUTF8String:lrc.lines[i].text];
                if (!line) continue;
                [lines addObject:line];
                [starts addObject:[NSNumber numberWithUnsignedInteger:lrc.lines[i].start_ms]];
            }
            exteria_lrc_free(&lrc);
            if (lines.count) return [[[ExteriaLyrics alloc] initWithLines:lines starts:starts] autorelease];
        }
    }
    NSString *plain = ExteriaStringOf([item objectForKey:@"plainLyrics"]);
    if (!plain.length) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *raw in [plain componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:space];
        if (line.length) [lines addObject:line];
        if (lines.count >= PLAIN_LINES_MAX) break;
    }
    return lines.count ? [[[ExteriaLyrics alloc] initWithLines:lines starts:nil] autorelease] : nil;
}

typedef void (^ExteriaLyricsDone)(ExteriaLyrics *lyrics, BOOL definitive);

@interface ExteriaLyricsRequest () {
    NSString *_key;
    NSString *_artist;
    NSString *_title;
    ExteriaLyricsDone _done;
    ExteriaHttpCall *_call;
    ExteriaWeakReference *_weak;
    BOOL _failed;
}
@end

@implementation ExteriaLyricsRequest

+ (ExteriaLyricsRequest *)fetchForPerformer:(NSString *)performer title:(NSString *)title completion:(void (^)(ExteriaLyrics *, BOOL))completion {
    ExteriaLyricsRequest *request = [[[self alloc] init] autorelease];
    request->_artist = [ExteriaSearchText(performer) retain];
    request->_title = [ExteriaSearchText(title) retain];
    request->_key = [[NSString stringWithFormat:@"%@\n%@", request->_artist, request->_title] retain];
    request->_done = [completion copy];
    request->_weak = [[ExteriaWeakReference referenceTo:request] retain];
    [request start];
    return request;
}

- (void)dealloc {
    [self cancel];
    [_weak clear];
    [_weak release];
    [_key release]; [_artist release]; [_title release];
    [super dealloc];
}

- (void)cancel {
    [_call cancel];
    [_call release]; _call = nil;
    [_done release]; _done = nil;
}

/* the answer goes out on the next turn of the run loop, so a caller that holds the request in a property has it assigned before the block runs */
- (void)finish:(ExteriaLyrics *)lyrics definitive:(BOOL)definitive {
    ExteriaLyricsDone done = _done;
    _done = nil;
    /* the call is inside its own completion here, so it is let go at the end of the turn */
    [_call autorelease]; _call = nil;
    if (!done) return;
    if (lyrics) {
        NSMutableDictionary *cache = ExteriaLyricsCache();
        if (cache.count >= CACHE_MAX) [cache removeAllObjects];
        [cache setObject:lyrics forKey:_key];
    } else if (definitive) {
        [ExteriaLyricsCache() setObject:[NSNull null] forKey:_key];
    }
    done(lyrics, definitive);
    [done release];
}

- (void)start {
    if (!_title.length) {
        [self performSelector:@selector(finishEmpty) withObject:nil afterDelay:0];
        return;
    }
    id cached = [ExteriaLyricsCache() objectForKey:_key];
    if (cached) {
        [self performSelector:@selector(finishCached:) withObject:cached afterDelay:0];
        return;
    }
    if (_artist.length) [self fetchExact];
    else [self fetchSearch];
}

- (void)finishEmpty { [self finish:nil definitive:YES]; }
- (void)finishCached:(id)cached { [self finish:[cached isKindOfClass:[ExteriaLyrics class]] ? cached : nil definitive:YES]; }

- (NSMutableURLRequest *)requestForURL:(NSString *)url {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setValue:@"Exteria/1.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    return request;
}

- (void)runRequest:(NSURLRequest *)request answer:(void (^)(id json, NSInteger status))answer {
    ExteriaWeakReference *weak = _weak;
    [_call autorelease];
    _call = [[ExteriaHttpCall startRequest:request limit:ANSWER_LIMIT timeout:CALL_TIMEOUT completion:^(NSData *body, NSInteger status, NSString *failure) {
        (void)failure;
        ExteriaLyricsRequest *request = weak.target;
        if (!request) return;
        id json = status == 200 && body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
        answer(json, status);
    }] retain];
}

- (void)fetchExact {
    NSString *url = [NSString stringWithFormat:@"https://lrclib.net/api/get?artist_name=%@&track_name=%@", ExteriaURLEscape(_artist), ExteriaURLEscape(_title)];
    ExteriaWeakReference *weak = _weak;
    [self runRequest:[self requestForURL:url] answer:^(id json, NSInteger status) {
        ExteriaLyricsRequest *request = weak.target;
        if (!request) return;
        ExteriaLyrics *lyrics = ExteriaLyricsFromItem(json);
        if (lyrics) { [request finish:lyrics definitive:YES]; return; }
        /* 404 is the plain "no such song"; anything else that is not an answer is the network's */
        if (status != 200 && status != 404) request->_failed = YES;
        [request fetchSearch];
    }];
}

- (void)fetchSearch {
    NSString *query = _artist.length ? [NSString stringWithFormat:@"%@ %@", _artist, _title] : _title;
    NSString *url = [@"https://lrclib.net/api/search?q=" stringByAppendingString:ExteriaURLEscape(query)];
    ExteriaWeakReference *weak = _weak;
    [self runRequest:[self requestForURL:url] answer:^(id json, NSInteger status) {
        ExteriaLyricsRequest *request = weak.target;
        if (!request) return;
        if (status != 200) request->_failed = YES;
        ExteriaLyrics *lyrics = [request bestOf:json];
        [request finish:lyrics definitive:lyrics ? YES : !request->_failed];
    }];
}

/* the hit that carries the title (two points), the performer (one) and stamps (one), as the search of the Android client scores them; a hit below the title is no match */
- (ExteriaLyrics *)bestOf:(id)json {
    if (![json isKindOfClass:[NSArray class]]) return nil;
    ExteriaLyrics *best = nil;
    int bestScore = -1;
    for (id item in (NSArray *)json) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        if ([[item objectForKey:@"instrumental"] boolValue]) continue;
        ExteriaLyrics *lyrics = ExteriaLyricsFromItem(item);
        if (!lyrics) continue;
        int score = 0;
        NSString *name = ExteriaStringOf([item objectForKey:@"trackName"]);
        if (!name.length) name = ExteriaStringOf([item objectForKey:@"name"]);
        if (ExteriaTextMatches(_title, name)) score += 2;
        if (_artist.length && ExteriaTextMatches(_artist, ExteriaStringOf([item objectForKey:@"artistName"]))) score += 1;
        if (lyrics.synced) score += 1;
        if (score > bestScore) { bestScore = score; best = lyrics; }
        if (bestScore >= 4) break;
    }
    return bestScore >= 2 ? best : nil;
}

@end
