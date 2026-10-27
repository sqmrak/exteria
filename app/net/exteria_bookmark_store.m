#import "exteria_bookmark_store.h"

#import "exteria_files.h"

NSString *const ExteriaBookmarksDidChangeNotification = @"ExteriaBookmarksDidChange";

static NSString *ExteriaBookmarkText(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaBookmark

- (id)initWithRow:(const exteria_bookmark *)row {
    self = [super init];
    if (!self) return nil;
    _row = *row;
    return self;
}

- (int32_t)messageId { return _row.message_id; }
- (int32_t)date { return _row.date; }
- (int32_t)added { return _row.added; }
- (NSString *)title { return ExteriaBookmarkText(_row.title); }
- (NSString *)text { return ExteriaBookmarkText(_row.text); }

- (ExteriaDialog *)dialog {
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = _row.peer_kind;
    row.peer_id = _row.peer_id;
    row.peer_hash = _row.peer_hash;
    row.kind = (exteria_dialog_kind)_row.dialog_kind;
    snprintf(row.title, sizeof(row.title), "%s", _row.title);
    return [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
}

- (BOOL)isFor:(const exteria_bookmark *)other {
    return _row.peer_kind == other->peer_kind && _row.peer_id == other->peer_id && _row.message_id == other->message_id;
}

@end

@interface ExteriaBookmarks () {
    NSString *_path;
    long long _account;
    exteria_bookmarks *_list;
    NSArray *_entries;
}
@end

@implementation ExteriaBookmarks

+ (ExteriaBookmarks *)bookmarksForSession:(ExteriaSession *)session {
    static NSMutableDictionary *cache;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    NSString *directory = session.directory;
    long long account = [ExteriaSession accountIdInDirectory:directory];
    NSString *key = [NSString stringWithFormat:@"%@#%lld", directory, account];
    ExteriaBookmarks *bookmarks = [cache objectForKey:key];
    if (!bookmarks) {
        bookmarks = [[[ExteriaBookmarks alloc] initWithDirectory:directory account:account] autorelease];
        [cache setObject:bookmarks forKey:key];
    }
    return bookmarks;
}

- (id)initWithDirectory:(NSString *)directory account:(long long)account {
    self = [super init];
    if (!self) return nil;
    _path = [[directory stringByAppendingPathComponent:@"bookmarks.bin"] copy];
    _account = account;
    _list = calloc(1, sizeof(*_list));
    if (!_list) {
        NSLog(@"exteria: no room for the bookmarks");
        [self release];
        return nil;
    }
    [self load];
    return self;
}

- (void)dealloc {
    free(_list);
    [_path release];
    [_entries release];
    [super dealloc];
}

/* a file of another account, or none, is an empty list; a damaged one is logged, and the next save replaces it */
- (void)load {
    exteria_bookmarks_init(_list);
    if (_account <= 0) return;
    uint8_t *buffer = malloc(EXTERIA_BOOKMARKS_FILE_MAX + 1);
    size_t length = 0;
    if (!buffer) return;
    exteria_status read = ExteriaReadFile(_path, buffer, EXTERIA_BOOKMARKS_FILE_MAX + 1, &length);
    if (read == EXTERIA_OK) {
        exteria_status status = exteria_bookmarks_unpack(buffer, length, _account, _list);
        if (status != EXTERIA_OK && status != EXTERIA_E_NOTFOUND) NSLog(@"exteria: the bookmarks file is damaged: %s", exteria_status_name(status));
    }
    free(buffer);
    [self rebuild];
}

- (void)rebuild {
    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:_list->count];
    for (size_t i = 0; i < _list->count; ++i) [entries addObject:[[[ExteriaBookmark alloc] initWithRow:&_list->items[i]] autorelease]];
    [_entries release];
    _entries = [entries copy];
}

- (NSArray *)entries {
    return _entries;
}

- (BOOL)save {
    if (_account <= 0) return NO;
    uint8_t *buffer = malloc(EXTERIA_BOOKMARKS_FILE_MAX);
    size_t length = 0;
    if (!buffer) return NO;
    exteria_status status = exteria_bookmarks_pack(_list, _account, buffer, EXTERIA_BOOKMARKS_FILE_MAX, &length);
    if (status == EXTERIA_OK) status = ExteriaWriteFile(_path, buffer, length);
    free(buffer);
    if (status != EXTERIA_OK) NSLog(@"exteria: the bookmarks were not saved: %s", exteria_status_name(status));
    return status == EXTERIA_OK;
}

/* the list as it was is kept when the file cannot be written, so what the screen shows is what is on the disk */
- (BOOL)commit:(const exteria_bookmarks *)changed {
    exteria_bookmarks *previous = malloc(sizeof(*previous));
    if (!previous) return NO;
    memcpy(previous, _list, sizeof(*previous));
    memcpy(_list, changed, sizeof(*_list));
    BOOL saved = [self save];
    if (!saved) memcpy(_list, previous, sizeof(*_list));
    free(previous);
    if (!saved) return NO;
    [self rebuild];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaBookmarksDidChangeNotification object:self];
    return YES;
}

- (BOOL)containsMessageId:(int32_t)messageId inDialog:(ExteriaDialog *)dialog {
    return exteria_bookmarks_contains(_list, dialog.peerKind, dialog.peerId, messageId);
}

/* the start of a message as a bookmark's line: one line, cut at a character that fits the entry */
static void ExteriaCopyBookmarkText(char *out, size_t cap, NSString *text) {
    NSString *line = [[text stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    NSUInteger used = 0;
    out[0] = 0;
    if (![line getBytes:out maxLength:cap - 1 usedLength:&used encoding:NSUTF8StringEncoding options:0 range:NSMakeRange(0, line.length)
               remainingRange:NULL]) used = 0;
    out[used] = 0;
}

- (BOOL)addMessageId:(int32_t)messageId date:(int32_t)date text:(NSString *)text inDialog:(ExteriaDialog *)dialog {
    exteria_bookmark entry;
    memset(&entry, 0, sizeof(entry));
    entry.peer_kind = dialog.peerKind;
    entry.peer_id = dialog.peerId;
    entry.peer_hash = dialog.peerHash;
    entry.dialog_kind = (int32_t)dialog.kind;
    entry.message_id = messageId;
    entry.date = date;
    entry.added = (int32_t)[[NSDate date] timeIntervalSince1970];
    ExteriaCopyBookmarkText(entry.title, sizeof(entry.title), dialog.title);
    ExteriaCopyBookmarkText(entry.text, sizeof(entry.text), text);
    exteria_bookmarks *changed = malloc(sizeof(*changed));
    if (!changed) return NO;
    memcpy(changed, _list, sizeof(*changed));
    exteria_status status = exteria_bookmarks_add(changed, &entry);
    BOOL done = NO;
    if (status != EXTERIA_OK) NSLog(@"exteria: message %d was not bookmarked: %s", (int)messageId, exteria_status_name(status));
    else done = [self commit:changed];
    free(changed);
    return done;
}

- (BOOL)removeMessageId:(int32_t)messageId inDialog:(ExteriaDialog *)dialog {
    exteria_bookmarks *changed = malloc(sizeof(*changed));
    if (!changed) return NO;
    memcpy(changed, _list, sizeof(*changed));
    BOOL done = NO;
    if (exteria_bookmarks_remove(changed, dialog.peerKind, dialog.peerId, messageId) == EXTERIA_OK) done = [self commit:changed];
    free(changed);
    return done;
}

- (BOOL)removeEntry:(ExteriaBookmark *)entry {
    return [self removeMessageId:entry.messageId inDialog:[entry dialog]];
}

@end
