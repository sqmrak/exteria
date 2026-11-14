#import "exteria_plugin_account.h"

#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_person.h"
#import "exteria_plugin_story.h"
#import "exteria_plugins.h"
#import "exteria_story.h"
#import "exteria_session.h"
#import "exteria_session_actions.h"
#import "exteria_session_profile.h"
#import "exteria_messages.h"

NSString *const ExteriaPluginAccountNotification = @"ExteriaPluginAccount";
NSString *const ExteriaPluginMessagesDeletedNotification = @"ExteriaPluginMessagesDeleted";

#define HISTORY_LIMIT_MAX 100
#define DELETE_IDS_MAX 100
#define TAG_MAX 128

static NSString *hex_of(const uint8_t *bytes, size_t length) {
    NSMutableString *text = [NSMutableString stringWithCapacity:length * 2];
    for (size_t i = 0; i < length; ++i) [text appendFormat:@"%02x", bytes[i]];
    return text;
}

static int hex_digit(unichar c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* the file reference of a document as python holds it, hex; NO for text that is not bytes or does not fit */
static BOOL bytes_of_hex(NSString *text, uint8_t *out, size_t capacity, size_t *length) {
    if (![text isKindOfClass:[NSString class]] || text.length % 2 || text.length / 2 > capacity) return NO;
    for (NSUInteger i = 0; i < text.length; i += 2) {
        int high = hex_digit([text characterAtIndex:i]), low = hex_digit([text characterAtIndex:i + 1]);
        if (high < 0 || low < 0) return NO;
        out[i / 2] = (uint8_t)(high << 4 | low);
    }
    *length = text.length / 2;
    return YES;
}

/* a song or file of the server as the plain values the TL document of the android client has: python builds its record from them */
static NSDictionary *document_json(ExteriaMedia *media) {
    exteria_media_ref ref = media.ref;
    if (ref.source != EXTERIA_MEDIA_SOURCE_DOCUMENT) return nil;
    return [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithLongLong:ref.id], @"id", [NSNumber numberWithLongLong:ref.access_hash], @"access_hash", [NSNumber numberWithInt:ref.dc], @"dc",
        hex_of(ref.file_ref, ref.ref_len), @"file_ref", [NSNumber numberWithLongLong:media.size], @"size", media.name ? media.name : @"", @"name",
        media.mime ? media.mime : @"", @"mime", media.title ? media.title : @"", @"title", media.performer ? media.performer : @"", @"performer",
        [NSNumber numberWithInt:media.duration], @"duration", [NSNumber numberWithBool:media.previewFile != nil], @"thumb", nil];
}

static void copy_text(char *to, size_t capacity, id text) {
    if ([text isKindOfClass:[NSString class]]) strlcpy(to, [text UTF8String], capacity);
}

/* the song a request names: the identity of a document, which is all saveMusic sends, and the size and tags when python has them (a song that is played needs
   them to show). nil for values that cannot name one */
ExteriaMedia *ExteriaPluginSongOfJSON(NSDictionary *doc) {
    if (![doc isKindOfClass:[NSDictionary class]]) return nil;
    id identity = [doc objectForKey:@"id"], hash = [doc objectForKey:@"access_hash"], dc = [doc objectForKey:@"dc"];
    if (![identity isKindOfClass:[NSNumber class]] || ![hash isKindOfClass:[NSNumber class]] || [identity longLongValue] == 0) return nil;
    exteria_media_info info;
    memset(&info, 0, sizeof(info));
    info.kind = EXTERIA_PREVIEW_AUDIO;
    info.ref.source = EXTERIA_MEDIA_SOURCE_DOCUMENT;
    info.ref.id = [identity longLongValue];
    info.ref.access_hash = [hash longLongValue];
    info.ref.dc = [dc isKindOfClass:[NSNumber class]] ? [dc intValue] : 0;
    size_t length = 0;
    if (!bytes_of_hex([doc objectForKey:@"file_ref"], info.ref.file_ref, sizeof(info.ref.file_ref), &length)) return nil;
    info.ref.ref_len = (uint8_t)length;
    copy_text(info.name, sizeof(info.name), [doc objectForKey:@"name"]);
    copy_text(info.mime, sizeof(info.mime), [doc objectForKey:@"mime"]);
    copy_text(info.title, sizeof(info.title), [doc objectForKey:@"title"]);
    copy_text(info.performer, sizeof(info.performer), [doc objectForKey:@"performer"]);
    id size = [doc objectForKey:@"size"], duration = [doc objectForKey:@"duration"];
    if ([size isKindOfClass:[NSNumber class]] && [size longLongValue] > 0) info.size = [size longLongValue];
    if ([duration isKindOfClass:[NSNumber class]] && [duration intValue] > 0) info.duration = [duration intValue];
    return [ExteriaMedia mediaWithInfo:&info];
}

/* the chats of the list by the id the android client has for them, shared with the synchronous service peer.known */
static NSMutableDictionary *g_dialogs;

static NSNumber *dialog_key(long long dialogId) {
    return [NSNumber numberWithLongLong:dialogId];
}

BOOL ExteriaPluginKnowsDialog(long long dialogId) {
    return [g_dialogs objectForKey:dialog_key(dialogId)] != nil;
}

@implementation ExteriaPluginAccount {
    ExteriaSession *_session;
    BOOL _valid;
    NSTimeInterval _refreshed;
}

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _valid = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(requested:) name:ExteriaPluginAccountNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pluginsChanged) name:ExteriaPluginsDidChangeNotification object:nil];
    if (!g_dialogs) g_dialogs = [[NSMutableDictionary alloc] init];
    [g_dialogs removeAllObjects];
    [_session loadCachedDialogsInFolder:0 completion:^(NSArray *items, NSString *errorName) {
        (void)errorName;
        if (_valid) [self remember:items];
    }];
    return self;
}

/* the list of the person's chats is what a plugin can name: a chat that is not in it has no access hash the app could send a request with */
- (void)remember:(NSArray *)items {
    for (ExteriaDialog *dialog in items) {
        if (dialog.folder || dialog.community || dialog.topicId > 0 || dialog.peerId <= 0) continue;
        long long key = dialog.peerKind == 1 ? dialog.peerId : -dialog.peerId;
        if (![g_dialogs objectForKey:dialog_key(key)]) [g_dialogs setObject:dialog forKey:dialog_key(key)];
    }
}

- (void)refreshDialogs {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!_valid || now - _refreshed < 20) return;
    _refreshed = now;
    [_session loadDialogs:^(NSArray *items, NSString *errorName) {
        if (!_valid) return;
        if (!items) {
            ExteriaPluginsLog(@"exteria: the chat list for plugins did not load: %@", errorName);
            return;
        }
        [self remember:items];
    }];
}

- (void)pluginsChanged {
    if (ExteriaPluginsAreRunning()) [self refreshDialogs];
}

- (void)invalidate {
    _valid = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc {
    [self invalidate];
    [_session release];
    [super dealloc];
}

/* the id of the signed in person, from the profile the session keeps of them; zero before it has one */
- (long long)ownUserId {
    return [[_session ownPerson] userId];
}

- (ExteriaDialog *)savedMessages {
    return [ExteriaDialog savedMessagesOfUserId:[self ownUserId]];
}

/* the chat of an id of the android client: the person's own id is Saved Messages, any other must be in the chat list */
- (ExteriaDialog *)dialogOfId:(long long)dialogId {
    if (dialogId == [self ownUserId]) return [self savedMessages];
    return [g_dialogs objectForKey:dialog_key(dialogId)];
}

/* python is told once, on the main thread, with the name of the error or nil, and the values of the answer */
- (void)answer:(NSNumber *)token error:(NSString *)error payload:(id)payload {
    ExteriaPluginsCallHost(@"account_result", [NSArray arrayWithObjects:token, error ? (id)error : (id)[NSNull null], payload ? payload : [NSDictionary dictionary], nil]);
}

- (void)requested:(NSNotification *)note {
    NSDictionary *request = note.userInfo;
    NSNumber *token = [request objectForKey:@"token"];
    NSString *operation = [request objectForKey:@"op"];
    if (!_valid || ![token isKindOfClass:[NSNumber class]] || ![operation isKindOfClass:[NSString class]]) return;
    if (![self ownUserId]) {
        [self answer:token error:@"AUTH_KEY_UNREGISTERED" payload:nil];
        return;
    }
    if ([operation isEqualToString:@"history"]) [self loadHistory:request token:token];
    else if ([operation isEqualToString:@"saved_music"]) [self loadSavedMusic:request token:token];
    else if ([operation isEqualToString:@"chat_music"]) [self loadChatMusic:request token:token];
    else if ([operation isEqualToString:@"chat_page"]) [self loadChatPage:request token:token];
    else if ([operation isEqualToString:@"save_music"]) [self saveMusic:request token:token];
    else if ([operation isEqualToString:@"delete"]) [self deleteMessages:request token:token];
    else if ([operation isEqualToString:@"send_audio"]) [self sendAudio:request token:token];
    else if ([operation isEqualToString:@"story_post"]) [self postStory:request token:token];
    else if ([operation isEqualToString:@"device_profile"]) [self setDeviceProfile:request token:token];
    else [self answer:token error:@"METHOD_INVALID" payload:nil];
}

- (void)loadHistory:(NSDictionary *)request token:(NSNumber *)token {
    int32_t limit = [[request objectForKey:@"limit"] intValue];
    if (limit < 1 || limit > HISTORY_LIMIT_MAX) { [self answer:token error:@"LIMIT_INVALID" payload:nil]; return; }
    [_session loadHistoryOfDialog:[self savedMessages] offsetId:0 addOffset:0 limit:limit completion:^(NSArray *messages, NSDictionary *people, NSString *error) {
        (void)people;
        if (error) { [self answer:token error:error payload:nil]; return; }
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:messages.count];
        for (ExteriaMessage *message in messages) {
            NSMutableDictionary *row = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:message.messageId], @"id",
                message.text ? message.text : @"", @"text", [NSNumber numberWithInt:message.date], @"date", nil];
            NSDictionary *doc = message.media ? document_json(message.media) : nil;
            if (doc) [row setObject:doc forKey:@"doc"];
            [rows addObject:row];
        }
        [self answer:token error:nil payload:[NSDictionary dictionaryWithObject:rows forKey:@"messages"]];
    }];
}

- (void)loadSavedMusic:(NSDictionary *)request token:(NSNumber *)token {
    NSInteger offset = [[request objectForKey:@"offset"] integerValue];
    if (offset < 0) { [self answer:token error:@"OFFSET_INVALID" payload:nil]; return; }
    /* the music of the profile of a user of the chat list, or of the person when no one is named */
    NSNumber *user = [request objectForKey:@"user"];
    ExteriaDialog *dialog = [user isKindOfClass:[NSNumber class]] ? [self dialogOfId:[user longLongValue]] : [self savedMessages];
    if (!dialog || (dialog.peerKind != 1 && !dialog.saved)) { [self answer:token error:@"USER_ID_INVALID" payload:nil]; return; }
    [_session loadSavedMusicOfDialog:dialog offset:offset completion:^(NSArray *tracks, NSInteger total, NSString *error) {
        if (error) { [self answer:token error:error payload:nil]; return; }
        NSMutableArray *docs = [NSMutableArray arrayWithCapacity:tracks.count];
        for (ExteriaMedia *track in tracks) {
            NSDictionary *doc = document_json(track);
            if (doc) [docs addObject:doc];
        }
        [self answer:token error:nil payload:[NSDictionary dictionaryWithObjectsAndKeys:docs, @"documents", [NSNumber numberWithInteger:total], @"count", nil]];
    }];
}

/* the newest song of a chat, or the oldest when first is set (what the music button of a plugin plays), as a page of one message */
- (void)loadChatMusic:(NSDictionary *)request token:(NSNumber *)token {
    NSNumber *dialogId = [request objectForKey:@"dialog"];
    ExteriaDialog *dialog = [dialogId isKindOfClass:[NSNumber class]] ? [self dialogOfId:[dialogId longLongValue]] : nil;
    if (!dialog) {
        [self refreshDialogs];
        [self answer:token error:@"PEER_ID_INVALID" payload:nil];
        return;
    }
    ExteriaHistoryCompletion done = ^(NSArray *messages, NSDictionary *people, NSString *error) {
        (void)people;
        if (error) { [self answer:token error:error payload:nil]; return; }
        NSMutableArray *rows = [NSMutableArray array];
        for (ExteriaMessage *message in messages) {
            NSDictionary *doc = message.media ? document_json(message.media) : nil;
            if (!doc) continue;
            [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:message.messageId], @"id", message.text ? message.text : @"", @"text",
                             [NSNumber numberWithInt:message.date], @"date", doc, @"doc", nil]];
            break;
        }
        [self answer:token error:nil payload:[NSDictionary dictionaryWithObject:rows forKey:@"messages"]];
    };
    if ([[request objectForKey:@"first"] boolValue]) [_session loadOldestSharedOfDialog:dialog kind:EXTERIA_SHARED_AUDIO completion:done];
    else [_session loadSharedOfDialog:dialog kind:EXTERIA_SHARED_AUDIO beforeId:0 limit:1 completion:done];
}

/* a page of the messages of the open chat for a plugin that cleans it: all of them, or the ones the account wrote ("mine"), older than offset_id, newest first. the rows
   carry what the cleaner decides on: id, date, whether it is ours, whether it is a channel post and whether it is a service message */
- (void)loadChatPage:(NSDictionary *)request token:(NSNumber *)token {
    ExteriaDialog *dialog = [request objectForKey:@"openDialog"];
    NSNumber *offset = [request objectForKey:@"offset_id"], *limit = [request objectForKey:@"limit"];
    NSString *mode = [request objectForKey:@"mode"];
    if (![dialog isKindOfClass:[ExteriaDialog class]] || ![offset isKindOfClass:[NSNumber class]] || [offset intValue] < 0 || ![limit isKindOfClass:[NSNumber class]] ||
        [limit intValue] < 1 || [limit intValue] > HISTORY_LIMIT_MAX || !([mode isEqualToString:@"all"] || [mode isEqualToString:@"mine"])) {
        [self answer:token error:@"LIMIT_INVALID" payload:nil];
        return;
    }
    ExteriaHistoryCompletion done = ^(NSArray *messages, NSDictionary *people, NSString *error) {
        (void)people;
        if (error) { [self answer:token error:error payload:nil]; return; }
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:messages.count];
        for (ExteriaMessage *message in messages) {
            if (message.messageId <= 0) continue;
            [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:message.messageId], @"id", [NSNumber numberWithInt:message.date], @"date",
                             [NSNumber numberWithBool:message.outgoing], @"out", [NSNumber numberWithBool:message.post], @"post", [NSNumber numberWithBool:message.service != 0], @"service", nil]];
        }
        [self answer:token error:nil payload:[NSDictionary dictionaryWithObject:rows forKey:@"messages"]];
    };
    if ([mode isEqualToString:@"mine"]) [_session loadOwnMessagesOfDialog:dialog beforeId:[offset intValue] limit:[limit intValue] completion:done];
    else [_session loadHistoryOfDialog:dialog offsetId:[offset intValue] addOffset:0 limit:[limit intValue] completion:done];
}

- (void)saveMusic:(NSDictionary *)request token:(NSNumber *)token {
    ExteriaMedia *song = ExteriaPluginSongOfJSON([request objectForKey:@"doc"]);
    if (!song) { [self answer:token error:@"DOCUMENT_INVALID" payload:nil]; return; }
    [_session saveMusic:song unsave:[[request objectForKey:@"unsave"] boolValue] completion:^(NSString *error) { [self answer:token error:error payload:nil]; }];
}

/* messages deleted on the server by id. a message of a user or a group has an id of the account, so any non-channel chat takes it (Saved Messages carries the request);
   a channel message has the id of its channel, so a request that names a channel runs on the open chat, which the main screen checked is that channel. the kept
   copies go with the messages and the open screen is told */
- (void)deleteMessages:(NSDictionary *)request token:(NSNumber *)token {
    NSArray *ids = [request objectForKey:@"ids"];
    if (![ids isKindOfClass:[NSArray class]] || !ids.count || ids.count > DELETE_IDS_MAX) { [self answer:token error:@"MESSAGE_ID_INVALID" payload:nil]; return; }
    for (id one in ids) if (![one isKindOfClass:[NSNumber class]] || [one intValue] <= 0) { [self answer:token error:@"MESSAGE_ID_INVALID" payload:nil]; return; }
    ExteriaDialog *channel = [request objectForKey:@"openDialog"];
    ExteriaDialog *target = [channel isKindOfClass:[ExteriaDialog class]] ? channel : [self savedMessages];
    NSArray *kept = [[ids copy] autorelease];
    [_session deleteMessageIds:kept ofDialog:target revoke:[[request objectForKey:@"revoke"] boolValue] completion:^(NSString *error) {
        if (!error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:kept forKey:@"ids"];
            if (channel) [info setObject:channel forKey:@"dialog"];
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginMessagesDeletedNotification object:nil userInfo:info];
        }
        [self answer:token error:error payload:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:kept.count] forKey:@"count"]];
    }];
}

/* the three texts the server lists for this device, or the real ones again when restore is set. the length is the one the core refuses beyond, checked in
   bytes there; an empty model or system version is refused too, so a plugin cannot blank the entry in the devices screen */
- (void)setDeviceProfile:(NSDictionary *)request token:(NSNumber *)token {
    if ([[request objectForKey:@"restore"] boolValue]) {
        [_session setDeviceModel:nil systemVersion:nil appVersion:nil completion:^(NSString *error) { [self answer:token error:error payload:nil]; }];
        return;
    }
    NSString *model = [request objectForKey:@"model"], *system = [request objectForKey:@"system"], *app = [request objectForKey:@"app"];
    if (![model isKindOfClass:[NSString class]] || ![system isKindOfClass:[NSString class]] || ![app isKindOfClass:[NSString class]]) {
        [self answer:token error:@"DEVICE_INVALID" payload:nil];
        return;
    }
    [_session setDeviceModel:model systemVersion:system appVersion:app completion:^(NSString *error) { [self answer:token error:error payload:nil]; }];
}

/* a story a plugin held for later goes up as the story screen would send it. the file is one the story screen wrote or one in the plugins folder, and the
   audience is the one held under the number the plugin was given when it took the story (none: everyone) */
- (void)postStory:(NSDictionary *)request token:(NSNumber *)token {
    NSString *path = [request objectForKey:@"path"];
    NSString *caption = [request objectForKey:@"caption"];
    NSNumber *audienceToken = [request objectForKey:@"audience"];
    if (!ExteriaPluginStoryPathAllowed(path) || ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        [self answer:token error:@"FILE_INVALID" payload:nil];
        return;
    }
    ExteriaStoryAudience *audience = [audienceToken isKindOfClass:[NSNumber class]] ? ExteriaPluginStoryAudience([audienceToken longLongValue]) : nil;
    if ([audienceToken longLongValue] > 0 && !audience) {
        /* a story meant for some people must not go to everyone because its list is gone */
        [self answer:token error:@"AUDIENCE_LOST" payload:nil];
        return;
    }
    if (!audience) audience = [ExteriaStoryAudience audienceWithBase:EXTERIA_STORY_EVERYONE];
    [_session postStoryPhotoAtPath:path caption:[caption isKindOfClass:[NSString class]] && [caption length] ? caption : nil audience:audience
                        completion:^(NSString *error) { [self answer:token error:error payload:nil]; }];
}

- (void)sendAudio:(NSDictionary *)request token:(NSNumber *)token {
    NSString *path = [request objectForKey:@"path"];
    NSString *mime = [request objectForKey:@"mime"];
    NSString *caption = [request objectForKey:@"caption"];
    NSString *title = [request objectForKey:@"title"];
    NSString *performer = [request objectForKey:@"performer"];
    int32_t durationMs = [[request objectForKey:@"duration_ms"] intValue];
    /* only a file the plugin wrote to its own folder is read: a plugin cannot send what it finds elsewhere on the phone */
    if (![path isKindOfClass:[NSString class]] || !ExteriaPluginsPathInCache(path) || ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        [self answer:token error:@"FILE_INVALID" payload:nil];
        return;
    }
    if (![mime isKindOfClass:[NSString class]] || ![mime hasPrefix:@"audio/"] || durationMs < 0 || [title length] > TAG_MAX || [performer length] > TAG_MAX) {
        [self answer:token error:@"AUDIO_INVALID" payload:nil];
        return;
    }
    ExteriaOutgoing *outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
    outgoing->kind = ExteriaOutgoingFile;
    outgoing->path = [path copy];
    outgoing->name = [[path lastPathComponent] copy];
    outgoing->mime = [mime copy];
    outgoing->caption = [([caption isKindOfClass:[NSString class]] ? caption : @"") copy];
    outgoing->music = YES;
    outgoing->title = [([title isKindOfClass:[NSString class]] ? title : @"") copy];
    outgoing->performer = [([performer isKindOfClass:[NSString class]] ? performer : @"") copy];
    outgoing->durationMs = durationMs;
    long long randomId = 0;
    while (!randomId) randomId = (long long)(((unsigned long long)arc4random() << 31) ^ arc4random()) & 0x7FFFFFFFFFFFFFFFLL;
    [_session sendOutgoing:outgoing toDialog:[self savedMessages] randomId:randomId replyTo:0 completion:^(int32_t messageId, NSString *error) {
        [self answer:token error:error payload:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:messageId] forKey:@"id"]];
    }];
}

@end
