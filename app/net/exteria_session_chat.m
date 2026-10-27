#include "exteria_tl_ids.h"
#import "exteria_session_drafts.h"
#import "exteria_session_internal.h"
#import "exteria_session_sendas.h"
#import "exteria_session_stickermake.h"
#import "exteria_chat_settings.h"

#include "exteria_sticker_make.h"
#include "exteria_sticker_manage.h"
#include <fcntl.h>
#include <unistd.h>

#include "exteria_mt_files.h"

#import "exteria_community.h"
#import "exteria_person.h"
#import "exteria_photo.h"
#include "exteria_channel.h"
#include "exteria_profile.h"
#include "exteria_stories.h"
#include "exteria_bots.h"
#import "exteria_rpc.h"

/* the newest page of a chat the store is asked for on every change */
#define WATCH_PAGE 60

exteria_peer_ref ExteriaPeerRefOfDialog(ExteriaDialog *dialog) {
    exteria_peer_ref ref;
    memset(&ref, 0, sizeof(ref));
    ref.kind = dialog.peerKind;
    ref.id = dialog.peerId;
    ref.access_hash = dialog.peerHash;
    ref.self = dialog.saved;
    ref.topic_id = dialog.topicId;
    return ref;
}

/* one file on its way to the server: the transfer state, and what the message that names it needs once it is there */
@interface ExteriaUploadJob : NSObject {
@public
    exteria_file_transfer transfer;
    BOOL open;
    exteria_peer_ref peer;
    /* the file becomes the profile photo of the signed in user instead of a message */
    BOOL profilePhoto;
    /* the file becomes a story of the signed in user */
    BOOL storyPhoto;
    /* the file is a sticker, which becomes a document of the signed in user for a set to take */
    void (^stickerDone)(ExteriaStickerDocument *document, NSString *errorName);
    /* the file is one item of an album: its media, as an NSData of exteria_album_media, or the error */
    void (^albumDone)(NSData *media, NSString *errorName);
    exteria_upload_spec spec;
    uint8_t waveform[EXTERIA_WAVEFORM_BYTES];
    long long randomId;
    ExteriaSendCompletion completion;
}
@end

@implementation ExteriaUploadJob
- (void)dealloc {
    if (open) exteria_file_close(&transfer);
    [completion release];
    [stickerDone release];
    [albumDone release];
    [super dealloc];
}
@end

/* the upload goes in parts of this size; it divides the largest part the server takes */
#define UPLOAD_PART (128 * 1024)
#define UPLOAD_PARTS_MAX 3000

static exteria_upload_spec ExteriaSpec(exteria_upload_kind kind, int32_t durationMs, int32_t width, int32_t height);

static uint64_t ExteriaMonotonicMs(void) {
    return exteria_system_clock.monotonic_ms(exteria_system_clock.ctx);
}

@implementation ExteriaCustomEmojiDocument

@synthesize documentId = _documentId;
@synthesize alt = _alt;
@synthesize format = _format;
@synthesize file = _file;
@synthesize preview = _preview;

- (id)initWithRow:(const exteria_custom_emoji *)row {
    self = [super init];
    if (!self) return nil;
    _documentId = row->id;
    _alt = [[NSString stringWithUTF8String:row->alt] copy];
    _format = row->format;
    _file = [[ExteriaRemoteFile fileForMedia:&row->ref] retain];
    _preview = [[ExteriaRemoteFile fileForMedia:&row->preview] retain];
    return self;
}

- (void)dealloc {
    [_alt release];
    [_file release];
    [_preview release];
    [super dealloc];
}

@end

/* the people a messages answer names: its users by id, and the channels it carries, which messages written as a channel point at, by
   the negative of their id */
NSMutableDictionary *ExteriaPeopleOfAnswer(const exteria_tl_value *answer) {
    NSMutableDictionary *people = [NSMutableDictionary dictionary];
    const exteria_tl_value *users = exteria_tl_get(answer, "users");
    for (uint32_t i = 0; users && users->kind == EXTERIA_TL_V_VEC && i < users->u.vec.count; ++i) {
        exteria_person_row person;
        if (exteria_person_parse(users->u.vec.items[i], &person) != EXTERIA_OK) continue;
        [people setObject:[[[ExteriaPerson alloc] initWithRow:&person] autorelease] forKey:[NSNumber numberWithLongLong:person.id]];
    }
    const exteria_tl_value *chats = exteria_tl_get(answer, "chats");
    for (uint32_t i = 0; chats && chats->kind == EXTERIA_TL_V_VEC && i < chats->u.vec.count; ++i) {
        exteria_person_row channel;
        if (exteria_channel_person_parse(chats->u.vec.items[i], &channel) != EXTERIA_OK) continue;
        [people setObject:[[[ExteriaPerson alloc] initWithRow:&channel] autorelease] forKey:[NSNumber numberWithLongLong:-channel.id]];
    }
    return people;
}

/* the buttons or keyboard of the messages an answer carries; a row only says that markup exists; the buttons are
   read from the message itself, and only for the messages that have some */
static void ExteriaApplyMarkups(NSArray *messages, const exteria_tl_value *answer) {
    const exteria_tl_value *list = exteria_tl_get(answer, "messages");
    if (!list || list->kind != EXTERIA_TL_V_VEC) return;
    for (uint32_t i = 0; i < list->u.vec.count; ++i) {
        const exteria_tl_value *value = list->u.vec.items[i];
        int32_t id = 0;
        if (!exteria_tl_has(value, "reply_markup") || exteria_tl_get_i32(value, "id", &id) != EXTERIA_OK) continue;
        for (ExteriaMessage *message in messages) {
            if (message.messageId == id) {
                message.markup = [ExteriaMarkup markupWithValue:exteria_tl_get(value, "reply_markup")];
                break;
            }
        }
    }
}

/* the items of an album go up one after the other: each becomes media the server knows, and the last step sends them together */
@interface ExteriaAlbumJob : NSObject {
@public
    NSArray *outgoings;
    NSArray *randomIds;
    exteria_peer_ref peer;
    NSUInteger next;
    NSMutableArray *medias;
    void (^completion)(NSArray *messageIds, NSString *errorName);
}
@end

@implementation ExteriaAlbumJob
- (void)dealloc {
    [outgoings release];
    [randomIds release];
    [medias release];
    [completion release];
    [super dealloc];
}
@end

@implementation ExteriaSession (Chat)

- (void)deliverMain:(void (^)(void))block {
    void (^copy)(void) = [block copy];
    dispatch_async(dispatch_get_main_queue(), ^{ copy(); [copy release]; });
}

#pragma mark chat list actions

#define MUTE_FOREVER 2147483647

- (void)performAction:(ExteriaChatCommand)action onDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_tl_value *input = NULL;
        exteria_status status = exteria_input_peer(arena, &peer, &input);
        if (status != EXTERIA_OK) return status;
        switch (action) {
        case ExteriaChatCommandPin:
        case ExteriaChatCommandUnpin: {
            exteria_tl_value *target = exteria_tl_new_obj(arena, "inputDialogPeer");
            *request = exteria_tl_new_obj(arena, "messages.toggleDialogPin");
            if (!target || !*request) return EXTERIA_E_NOMEM;
            status = exteria_tl_set(target, "peer", input);
            if (status == EXTERIA_OK && action == ExteriaChatCommandPin) status = exteria_tl_set_flag(*request, "pinned");
            if (status == EXTERIA_OK) status = exteria_tl_set(*request, "peer", target);
            return status;
        }
        case ExteriaChatCommandMute:
        case ExteriaChatCommandUnmute: {
            exteria_tl_value *target = exteria_tl_new_obj(arena, "inputNotifyPeer");
            exteria_tl_value *settings = exteria_tl_new_obj(arena, "inputPeerNotifySettings");
            *request = exteria_tl_new_obj(arena, "account.updateNotifySettings");
            if (!target || !settings || !*request) return EXTERIA_E_NOMEM;
            status = exteria_tl_set(target, "peer", input);
            if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, settings, "mute_until", action == ExteriaChatCommandMute ? MUTE_FOREVER : 0);
            if (status == EXTERIA_OK) status = exteria_tl_set(*request, "peer", target);
            if (status == EXTERIA_OK) status = exteria_tl_set(*request, "settings", settings);
            return status;
        }
        case ExteriaChatCommandDelete:
            if (peer.kind == 3) {
                exteria_tl_value *channel = exteria_tl_new_obj(arena, "inputChannel");
                *request = exteria_tl_new_obj(arena, "channels.leaveChannel");
                if (!channel || !*request) return EXTERIA_E_NOMEM;
                status = exteria_tl_set_i64(arena, channel, "channel_id", peer.id);
                if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", peer.access_hash);
                if (status == EXTERIA_OK) status = exteria_tl_set(*request, "channel", channel);
                return status;
            }
            *request = exteria_tl_new_obj(arena, "messages.deleteHistory");
            if (!*request) return EXTERIA_E_NOMEM;
            status = exteria_tl_set(*request, "peer", input);
            if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, *request, "max_id", 0);
            return status;
        case ExteriaChatCommandMarkRead:
            /* a max id of INT32_MAX reads everything the chat holds; a positive one is what the call asks for */
            return exteria_read_history_request(arena, &peer, INT32_MAX, request);
        case ExteriaChatCommandMarkUnread:
        case ExteriaChatCommandClearUnreadMark: {
            exteria_tl_value *target = exteria_tl_new_obj(arena, "inputDialogPeer");
            *request = exteria_tl_new_obj(arena, "messages.markDialogUnread");
            if (!target || !*request) return EXTERIA_E_NOMEM;
            status = exteria_tl_set(target, "peer", input);
            if (status == EXTERIA_OK && action == ExteriaChatCommandMarkUnread) status = exteria_tl_set_flag(*request, "unread");
            if (status == EXTERIA_OK) status = exteria_tl_set(*request, "peer", target);
            return status;
        }
        case ExteriaChatCommandClear:
            /* the messages go for this account only, and the chat stays in the list */
            if (peer.kind == 3) return EXTERIA_E_ARG;
            *request = exteria_tl_new_obj(arena, "messages.deleteHistory");
            if (!*request) return EXTERIA_E_NOMEM;
            status = exteria_tl_set_flag(*request, "just_clear");
            if (status == EXTERIA_OK) status = exteria_tl_set(*request, "peer", input);
            if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, *request, "max_id", 0);
            return status;
        }
        return EXTERIA_E_ARG;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        [self deliverMain:^{ done(error); [done release]; }];
    }];
}

#pragma mark uploads

/* worker only: sends the next part, or the message once every part is there */
- (void)pumpUpload:(ExteriaUploadJob *)job {
    exteria_file_state state = job->transfer.state;
    if (state == EXTERIA_FILE_DONE && job->albumDone) {
        [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_tl_value *file = NULL;
            exteria_status status = exteria_file_uploaded(&job->transfer, arena, &file);
            if (status == EXTERIA_OK) status = exteria_album_upload_request(arena, &job->peer, file, &job->spec, request);
            return status;
        } handler:^(const exteria_mt_rpc_result *result) {
            NSData *blob = nil;
            NSString *error = nil;
            exteria_album_media media;
            if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
            else if (exteria_album_media_parse(result->value, &media) == EXTERIA_OK) {
                media.spoiler = job->spec.spoiler;
                blob = [NSData dataWithBytes:&media length:sizeof(media)];
            }
            else error = @"MALFORMED";
            [self noteRpcError:error];
            void (^done)(NSData *, NSString *) = [job->albumDone retain];
            done(blob, error);
            [done release];
            [job release];
        }];
        return;
    }
    if (state == EXTERIA_FILE_DONE && job->stickerDone) {
        [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_tl_value *file = NULL;
            exteria_status status = exteria_file_uploaded(&job->transfer, arena, &file);
            if (status == EXTERIA_OK) status = exteria_sticker_upload_request(arena, file, "sticker.png", request);
            return status;
        } handler:^(const exteria_mt_rpc_result *result) {
            ExteriaStickerDocument *document = nil;
            NSString *error = nil;
            exteria_input_document value;
            if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
            else if (exteria_sticker_upload_parse(result->value, &value) == EXTERIA_OK)
                document = [[[ExteriaStickerDocument alloc] initWithId:value.id accessHash:value.access_hash
                                                         fileReference:[NSData dataWithBytes:value.file_reference length:value.file_reference_len]] autorelease];
            else error = @"MALFORMED";
            [self noteRpcError:error];
            void (^done)(ExteriaStickerDocument *, NSString *) = [job->stickerDone retain];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(document, delivered); [done release]; }];
            [job release];
        }];
        return;
    }
    if (state == EXTERIA_FILE_DONE && (job->profilePhoto || job->storyPhoto)) {
        [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_tl_value *file = NULL;
            exteria_status status = exteria_file_uploaded(&job->transfer, arena, &file);
            if (status == EXTERIA_OK && job->storyPhoto) status = exteria_story_send_photo_request(arena, file, job->randomId, request);
            else if (status == EXTERIA_OK) status = exteria_profile_photo_request(arena, file, request);
            return status;
        } handler:^(const exteria_mt_rpc_result *result) {
            NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
            [self noteRpcError:error];
            ExteriaSendCompletion done = [job->completion retain];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(0, delivered); [done release]; }];
            [job release];
        }];
        return;
    }
    if (state == EXTERIA_FILE_DONE) {
        [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_tl_value *file = NULL;
            exteria_status status = exteria_file_uploaded(&job->transfer, arena, &file);
            if (status == EXTERIA_OK) status = exteria_send_upload_request(arena, &job->peer, file, &job->spec, job->randomId, request);
            if (status == EXTERIA_OK) status = ExteriaApplySendAs(self, &job->peer, arena, *request);
            return status;
        } handler:^(const exteria_mt_rpc_result *result) {
            NSLog(@"exteria: upload of the file is complete, sending the message");
            /* finishSend gives its completion up after delivering, so it gets a reference of its own */
            [self finishSend:result randomId:job->randomId completion:[job->completion retain]];
            [job release];
        }];
        return;
    }
    if (state == EXTERIA_FILE_FAILED || state == EXTERIA_FILE_CANCELLED) {
        [self failUpload:job error:@"UPLOAD_FAILED"];
        return;
    }
    __block uint64_t requestId = 0;
    __block int32_t dc = 0;
    __block int cdn = 0;
    __block exteria_status built = EXTERIA_OK;
    [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        built = exteria_file_next(&job->transfer, ExteriaMonotonicMs(), arena, request, &requestId, &dc, &cdn);
        return built;
    } handler:^(const exteria_mt_rpc_result *result) {
        if (built != EXTERIA_OK) {
            /* a flood wait parks the transfer; the next part goes after the server's pause */
            if (built == EXTERIA_E_RETRY && job->transfer.state == EXTERIA_FILE_WAIT) {
                uint64_t now = ExteriaMonotonicMs();
                uint64_t pause = job->transfer.wait_until > now ? job->transfer.wait_until - now : 0;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                    [self post:^{ [self pumpUpload:job]; }];
                });
                return;
            }
            NSLog(@"exteria: upload part not built: %s", exteria_status_name(built));
            [self failUpload:job error:@"UPLOAD_FAILED"];
            return;
        }
        exteria_status status = exteria_file_result(&job->transfer, requestId, dc, cdn, ExteriaMonotonicMs(), result);
        if (status != EXTERIA_OK && status != EXTERIA_E_RETRY) {
            NSString *error = result->status == EXTERIA_OK ? @"UPLOAD_FAILED" : ExteriaRpcErrorName(result);
            NSLog(@"exteria: upload stopped: %@ (%s)", error, exteria_status_name(status));
            [self noteRpcError:error];
            [self failUpload:job error:error];
            return;
        }
        [self post:^{ [self pumpUpload:job]; }];
    }];
}

- (void)failUpload:(ExteriaUploadJob *)job error:(NSString *)error {
    if (job->albumDone) {
        void (^albumDone)(NSData *, NSString *) = [job->albumDone retain];
        albumDone(nil, error);
        [albumDone release];
        [job release];
        return;
    }
    if (job->stickerDone) {
        void (^stickerDone)(ExteriaStickerDocument *, NSString *) = [job->stickerDone retain];
        NSString *failure = [[error copy] autorelease];
        [self deliverMain:^{ stickerDone(nil, failure); [stickerDone release]; }];
        [job release];
        return;
    }
    ExteriaSendCompletion done = [job->completion retain];
    NSString *delivered = [[error copy] autorelease];
    [self deliverMain:^{ done(0, delivered); [done release]; }];
    [job release];
}

- (void)sendUploadAtPath:(NSString *)path spec:(exteria_upload_spec)spec waveform:(NSData *)waveform toDialog:(ExteriaDialog *)dialog
               randomId:(long long)randomId completion:(ExteriaSendCompletion)completion {
    ExteriaUploadJob *job = [[ExteriaUploadJob alloc] init];
    job->peer = ExteriaPeerRefOfDialog(dialog);
    job->spec = spec;
    job->randomId = randomId;
    job->completion = [completion copy];
    if (waveform) {
        if (waveform.length != EXTERIA_WAVEFORM_BYTES) {
            [self failUpload:job error:@"INTERNAL"];
            return;
        }
        memcpy(job->waveform, waveform.bytes, waveform.length);
        job->spec.waveform = job->waveform;
        job->spec.waveform_len = waveform.length;
    }
    NSString *file = [path copy];
    [self post:^{
        int fd = open(file.fileSystemRepresentation, O_RDONLY);
        exteria_status status = fd < 0 ? EXTERIA_E_IO : exteria_file_upload(&job->transfer, fd, file.lastPathComponent.UTF8String, [self workerDc],
                                                                           UPLOAD_PART, UPLOAD_PARTS_MAX);
        if (fd >= 0) close(fd);
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: cannot start the upload of %@: %s", file.lastPathComponent, exteria_status_name(status));
            [self failUpload:job error:status == EXTERIA_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        } else {
            job->open = YES;
            NSLog(@"exteria: upload of %@ starts, %llu bytes, data center %d", file.lastPathComponent, (unsigned long long)job->transfer.size, (int)[self workerDc]);
            [self pumpUpload:job];
        }
        [file release];
    }];
}

- (void)failAlbum:(ExteriaAlbumJob *)job error:(NSString *)error {
    void (^done)(NSArray *, NSString *) = [job->completion retain];
    NSString *delivered = [[error copy] autorelease];
    [self deliverMain:^{ done(nil, delivered); [done release]; }];
    [job release];
}

- (void)albumUploadNext:(ExteriaAlbumJob *)job {
    if (job->next >= job->outgoings.count) {
        [self albumSend:job];
        return;
    }
    ExteriaOutgoing *item = [job->outgoings objectAtIndex:job->next];
    ExteriaUploadJob *upload = [[ExteriaUploadJob alloc] init];
    upload->peer = job->peer;
    if (item->kind == ExteriaOutgoingVideo) {
        upload->spec = ExteriaSpec(EXTERIA_UPLOAD_VIDEO, item->durationMs, item->width, item->height);
    } else if (item->kind == ExteriaOutgoingFile) {
        /* files sent without compression go out as a group of documents, which the server shows as one album */
        upload->spec = ExteriaSpec(EXTERIA_UPLOAD_FILE, 0, 0, 0);
        snprintf(upload->spec.name, sizeof(upload->spec.name), "%s", item->name.UTF8String);
        snprintf(upload->spec.mime, sizeof(upload->spec.mime), "%s", item->mime.length ? item->mime.UTF8String : "application/octet-stream");
    } else {
        upload->spec = ExteriaSpec(EXTERIA_UPLOAD_PHOTO, 0, 0, 0);
    }
    upload->spec.spoiler = item->spoiler ? 1 : 0;
    upload->albumDone = [^(NSData *media, NSString *errorName) {
        if (!media) {
            [self failAlbum:job error:errorName];
            return;
        }
        [job->medias addObject:media];
        ++job->next;
        [self post:^{ [self albumUploadNext:job]; }];
    } copy];
    NSString *file = [item->path copy];
    int fd = open(file.fileSystemRepresentation, O_RDONLY);
    exteria_status status = fd < 0 ? EXTERIA_E_IO : exteria_file_upload(&upload->transfer, fd, file.lastPathComponent.UTF8String, [self workerDc], UPLOAD_PART, UPLOAD_PARTS_MAX);
    if (fd >= 0) close(fd);
    [file release];
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: cannot start the upload of an album item: %s", exteria_status_name(status));
        [self failUpload:upload error:status == EXTERIA_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        return;
    }
    upload->open = YES;
    [self pumpUpload:upload];
}

- (void)albumSend:(ExteriaAlbumJob *)job {
    NSUInteger count = job->medias.count;
    [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_album_media items[EXTERIA_ALBUM_ITEMS_MAX];
        int64_t ids[EXTERIA_ALBUM_ITEMS_MAX];
        const char *captions[EXTERIA_ALBUM_ITEMS_MAX];
        if (count > EXTERIA_ALBUM_ITEMS_MAX) return EXTERIA_E_ARG;
        for (NSUInteger i = 0; i < count; ++i) {
            NSData *blob = [job->medias objectAtIndex:i];
            if (blob.length != sizeof(items[i])) return EXTERIA_E_ARG;
            memcpy(&items[i], blob.bytes, sizeof(items[i]));
            ids[i] = [[job->randomIds objectAtIndex:i] longLongValue];
            NSString *caption = ((ExteriaOutgoing *)[job->outgoings objectAtIndex:i])->caption;
            captions[i] = caption.length ? caption.UTF8String : NULL;
        }
        exteria_status status = exteria_album_send_request(arena, &job->peer, items, ids, captions, count, request);
        int32_t reply = ((ExteriaOutgoing *)[job->outgoings objectAtIndex:0])->replyTo;
        if (status == EXTERIA_OK) status = exteria_set_reply(arena, *request, &job->peer, reply);
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *messageIds = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            messageIds = [NSMutableArray arrayWithCapacity:count];
            for (NSUInteger i = 0; i < count; ++i) {
                int32_t serverId = 0;
                exteria_status status = exteria_sent_parse(result->value, [[job->randomIds objectAtIndex:i] longLongValue], &serverId);
                /* an answer that names no id still delivered the album, a reload brings the messages back */
                [messageIds addObject:[NSNumber numberWithInt:status == EXTERIA_OK ? serverId : 0]];
            }
        }
        [self noteRpcError:error];
        void (^done)(NSArray *, NSString *) = [job->completion retain];
        NSArray *deliveredIds = [[messageIds copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredIds, deliveredError); [done release]; }];
        [job release];
    }];
}

- (void)sendAlbumOfOutgoings:(NSArray *)outgoings toDialog:(ExteriaDialog *)dialog randomIds:(NSArray *)randomIds completion:(void (^)(NSArray *, NSString *))completion {
    ExteriaAlbumJob *job = [[ExteriaAlbumJob alloc] init];
    job->outgoings = [outgoings copy];
    job->randomIds = [randomIds copy];
    job->peer = ExteriaPeerRefOfDialog(dialog);
    job->medias = [[NSMutableArray alloc] init];
    job->completion = [completion copy];
    if (outgoings.count < 2 || outgoings.count > EXTERIA_ALBUM_ITEMS_MAX || randomIds.count != outgoings.count) {
        [self failAlbum:job error:@"ALBUM_INVALID"];
        return;
    }
    [self post:^{ [self albumUploadNext:job]; }];
}

- (void)uploadStickerAtPath:(NSString *)path completion:(void (^)(ExteriaStickerDocument *, NSString *))completion {
    ExteriaUploadJob *job = [[ExteriaUploadJob alloc] init];
    job->stickerDone = [completion copy];
    NSString *file = [path copy];
    [self post:^{
        int fd = open(file.fileSystemRepresentation, O_RDONLY);
        exteria_status status = fd < 0 ? EXTERIA_E_IO : exteria_file_upload(&job->transfer, fd, file.lastPathComponent.UTF8String, [self workerDc],
                                                                           UPLOAD_PART, UPLOAD_PARTS_MAX);
        if (fd >= 0) close(fd);
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: cannot start the upload of %@: %s", file.lastPathComponent, exteria_status_name(status));
            [self failUpload:job error:status == EXTERIA_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        } else {
            job->open = YES;
            [self pumpUpload:job];
        }
        [file release];
    }];
}

- (void)uploadProfilePhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion {
    [self uploadJobAtPath:path story:NO completion:completion];
}

- (void)postStoryPhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion {
    [self uploadJobAtPath:path story:YES completion:completion];
}

/* both end in a call that takes the file: the profile photo or the story of the signed in user */
- (void)uploadJobAtPath:(NSString *)path story:(BOOL)story completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    ExteriaUploadJob *job = [[ExteriaUploadJob alloc] init];
    job->profilePhoto = !story;
    job->storyPhoto = story;
    job->randomId = story ? (((long long)arc4random() << 32) | arc4random()) | 1 : 0;
    job->completion = [^(int32_t messageId, NSString *errorName) {
        (void)messageId;
        done(errorName);
        [done release];
    } copy];
    NSString *file = [path copy];
    [self post:^{
        int fd = open(file.fileSystemRepresentation, O_RDONLY);
        exteria_status status = fd < 0 ? EXTERIA_E_IO : exteria_file_upload(&job->transfer, fd, file.lastPathComponent.UTF8String, [self workerDc],
                                                                           UPLOAD_PART, UPLOAD_PARTS_MAX);
        if (fd >= 0) close(fd);
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: cannot start the upload of %@: %s", file.lastPathComponent, exteria_status_name(status));
            [self failUpload:job error:status == EXTERIA_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        } else {
            job->open = YES;
            [self pumpUpload:job];
        }
        [file release];
    }];
}

static exteria_upload_spec ExteriaSpec(exteria_upload_kind kind, int32_t durationMs, int32_t width, int32_t height) {
    exteria_upload_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.kind = kind;
    spec.duration_ms = durationMs;
    spec.width = width;
    spec.height = height;
    return spec;
}

- (void)sendVoiceAtPath:(NSString *)path durationMs:(int32_t)durationMs waveform:(NSData *)waveform toDialog:(ExteriaDialog *)dialog
               randomId:(long long)randomId completion:(ExteriaSendCompletion)completion {
    [self sendUploadAtPath:path spec:ExteriaSpec(EXTERIA_UPLOAD_VOICE, durationMs, 0, 0) waveform:waveform toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendRoundVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side toDialog:(ExteriaDialog *)dialog
                    randomId:(long long)randomId completion:(ExteriaSendCompletion)completion {
    [self sendUploadAtPath:path spec:ExteriaSpec(EXTERIA_UPLOAD_ROUND, durationMs, side, side) waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

static BOOL ExteriaUploadCaption(exteria_upload_spec *spec, NSString *caption) {
    NSData *bytes = [caption dataUsingEncoding:NSUTF8StringEncoding];
    if (caption.length > 1024 || bytes.length > EXTERIA_UPLOAD_CAPTION_MAX || (caption.length && !bytes)) return NO;
    if (bytes.length) memcpy(spec->caption, bytes.bytes, bytes.length);
    spec->caption[bytes.length] = 0;
    return YES;
}

- (void)sendOutgoing:(ExteriaOutgoing *)outgoing toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(ExteriaSendCompletion)completion {
    if (replyTo < 0) { completion(0, @"INTERNAL"); return; }
    if (outgoing->kind == ExteriaOutgoingLocation || outgoing->kind == ExteriaOutgoingContact) {
        ExteriaSendCompletion done = [completion copy];
        exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
        [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_status status;
            if (outgoing->kind == ExteriaOutgoingLocation) {
                status = outgoing->location.valid ? exteria_send_location_request(arena, &peer, &outgoing->location, randomId, request) :
                    exteria_send_geo_request(arena, &peer, outgoing->latitude, outgoing->longitude, randomId, request);
            }
            else status = exteria_send_contact_request(arena, &peer, outgoing->phone.UTF8String, outgoing->name.UTF8String, "", randomId, request);
            if (status == EXTERIA_OK) status = exteria_set_reply(arena, *request, &peer, replyTo);
            return status == EXTERIA_OK ? ExteriaApplySendAs(self, &peer, arena, *request) : status;
        } handler:^(const exteria_mt_rpc_result *result) { [self finishSend:result randomId:randomId completion:done]; }];
        return;
    }
    exteria_upload_kind kind;
    switch (outgoing->kind) {
    case ExteriaOutgoingVoice: kind = EXTERIA_UPLOAD_VOICE; break;
    case ExteriaOutgoingRound: kind = EXTERIA_UPLOAD_ROUND; break;
    case ExteriaOutgoingPhoto: kind = EXTERIA_UPLOAD_PHOTO; break;
    case ExteriaOutgoingVideo: kind = EXTERIA_UPLOAD_VIDEO; break;
    case ExteriaOutgoingFile: kind = EXTERIA_UPLOAD_FILE; break;
    default: completion(0, @"INTERNAL"); return;
    }
    exteria_upload_spec spec = ExteriaSpec(kind, outgoing->durationMs, outgoing->width, outgoing->height);
    spec.reply_to = replyTo;
    spec.spoiler = outgoing->spoiler ? 1 : 0;
    if (!ExteriaUploadCaption(&spec, outgoing->caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    if (kind == EXTERIA_UPLOAD_FILE) {
        int nameLength = snprintf(spec.name, sizeof(spec.name), "%s", outgoing->name.UTF8String);
        int mimeLength = snprintf(spec.mime, sizeof(spec.mime), "%s", outgoing->mime.length ? outgoing->mime.UTF8String : "application/octet-stream");
        if (nameLength < 0 || (size_t)nameLength >= sizeof(spec.name) || mimeLength < 0 || (size_t)mimeLength >= sizeof(spec.mime)) { completion(0, @"FILE_NAME_TOO_LONG"); return; }
    }
    [self sendUploadAtPath:outgoing->path spec:spec waveform:outgoing->waveform toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendPhotoAtPath:(NSString *)path caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId completion:(ExteriaSendCompletion)completion {
    exteria_upload_spec spec = ExteriaSpec(EXTERIA_UPLOAD_PHOTO, 0, 0, 0);
    spec.spoiler = spoiler ? 1 : 0;
    if (!ExteriaUploadCaption(&spec, caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    [self sendUploadAtPath:path spec:spec waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs width:(int32_t)width height:(int32_t)height caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(ExteriaDialog *)dialog
               randomId:(long long)randomId completion:(ExteriaSendCompletion)completion {
    exteria_upload_spec spec = ExteriaSpec(EXTERIA_UPLOAD_VIDEO, durationMs, width, height);
    spec.spoiler = spoiler ? 1 : 0;
    if (!ExteriaUploadCaption(&spec, caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    [self sendUploadAtPath:path spec:spec waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendDocumentAtPath:(NSString *)path name:(NSString *)name mime:(NSString *)mime caption:(NSString *)caption toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
                completion:(ExteriaSendCompletion)completion {
    exteria_upload_spec spec = ExteriaSpec(EXTERIA_UPLOAD_FILE, 0, 0, 0);
    if (!ExteriaUploadCaption(&spec, caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    snprintf(spec.name, sizeof(spec.name), "%s", name.UTF8String);
    snprintf(spec.mime, sizeof(spec.mime), "%s", mime.length ? mime.UTF8String : "application/octet-stream");
    [self sendUploadAtPath:path spec:spec waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendLocationLatitude:(double)latitude longitude:(double)longitude toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
                  completion:(ExteriaSendCompletion)completion {
    ExteriaSendCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_status status = exteria_send_geo_request(arena, &peer, latitude, longitude, randomId, request);
        return status == EXTERIA_OK ? ExteriaApplySendAs(self, &peer, arena, *request) : status;
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
}

#pragma mark history

static void ExteriaKeepTopic(NSMutableArray *messages, int32_t topic);

- (void)loadHistoryOfDialog:(ExteriaDialog *)dialog beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(ExteriaHistoryCompletion)completion {
    ExteriaHistoryCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t topic = dialog.topicId;
    ExteriaDialog *source = dialog.savedSource;
    exteria_peer_ref sourcePeer = source ? ExteriaPeerRefOfDialog(source) : peer;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return source ? exteria_saved_history_request(arena, &sourcePeer, beforeId, limit, request) : exteria_history_request(arena, &peer, beforeId, limit, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *messages = nil;
        NSMutableDictionary *people = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_message_row *rows = calloc(EXTERIA_MESSAGES_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_messages_parse(result->value, rows, EXTERIA_MESSAGES_MAX, &count) == EXTERIA_OK) {
                messages = [NSMutableArray arrayWithCapacity:count];
                [self keepMessagesOfAnswer:result->value];
                for (size_t i = 0; i < count; ++i) {
                    if (rows[i].reactions.min) {
                        /* the cached copy preserves our selection when history carries only min counts */
                        exteria_arena storedArena;
                        exteria_tl_value *stored = NULL;
                        exteria_peer storedPeer = {peer.kind, peer.id};
                        exteria_arena_init(&storedArena, 8u * 1024u * 1024u);
                        exteria_status status = exteria_store_get([self workerStore], EXTERIA_RECORD_MESSAGE,
                            storedPeer, rows[i].id, &storedArena, &stored);
                        exteria_reactions preserved;
                        if (status == EXTERIA_OK) status = exteria_reactions_read(exteria_tl_get(stored, "reactions"), &preserved);
                        if (status == EXTERIA_OK) rows[i].reactions = preserved;
                        if (status != EXTERIA_OK) NSLog(@"exteria: cached reaction selection unavailable: %s", exteria_status_name(status));
                        exteria_arena_free(&storedArena);
                    }
                    ExteriaMessage *message = [ExteriaMessage messageWithRow:&rows[i]];
                    if (message) [messages addObject:message];
                }
                ExteriaApplyMarkups(messages, result->value);
                people = ExteriaPeopleOfAnswer(result->value);
            } else {
                NSLog(@"exteria: messages.getHistory answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        if (messages) {
            /* what the person asked to keep joins the page; the kept deleted messages from the oldest of the page
               up to where the page began, which holes in the ids of the page (what was deleted) would otherwise
               leave out for good */
            int32_t lowest = INT32_MAX;
            for (ExteriaMessage *message in messages) lowest = MIN(lowest, message.messageId);
            exteria_peer storedPeer = {peer.kind, peer.id};
            NSMutableArray *kept = ExteriaSavedDeletedOfPeer([self workerStore], storedPeer, messages.count ? lowest : 1, beforeId > 0 ? beforeId - 1 : INT32_MAX);
            ExteriaKeepTopic(kept, topic);
            [messages addObjectsFromArray:kept];
        }
        NSArray *deliveredMessages = [[messages copy] autorelease];
        NSDictionary *deliveredPeople = [[people copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredMessages, deliveredPeople, deliveredError); [done release]; }];
    }];
}

/* a messages.search answer read into messages and the people they name, handed to done on the main thread */
- (void)deliverMessagesOfResult:(const exteria_mt_rpc_result *)result what:(const char *)what completion:(ExteriaHistoryCompletion)done {
    NSMutableArray *messages = nil;
    NSMutableDictionary *people = nil;
    NSString *error = nil;
    if (result->status != EXTERIA_OK) {
        error = ExteriaRpcErrorName(result);
    } else {
        exteria_message_row *rows = calloc(EXTERIA_MESSAGES_MAX, sizeof(*rows));
        size_t count = 0;
        if (rows && exteria_messages_parse(result->value, rows, EXTERIA_MESSAGES_MAX, &count) == EXTERIA_OK) {
            messages = [NSMutableArray arrayWithCapacity:count];
            for (size_t i = 0; i < count; ++i) {
                ExteriaMessage *message = [ExteriaMessage messageWithRow:&rows[i]];
                if (message) [messages addObject:message];
            }
            ExteriaApplyMarkups(messages, result->value);
            people = ExteriaPeopleOfAnswer(result->value);
        } else {
            NSLog(@"exteria: messages.search for %s answer rejected", what);
            error = @"INTERNAL";
        }
        free(rows);
    }
    [self noteRpcError:error];
    NSArray *deliveredMessages = [[messages copy] autorelease];
    NSDictionary *deliveredPeople = [[people copy] autorelease];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(deliveredMessages, deliveredPeople, deliveredError); [done release]; }];
}

- (void)loadPinnedMessagesOfDialog:(ExteriaDialog *)dialog completion:(ExteriaHistoryCompletion)completion {
    ExteriaHistoryCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_pinned_request(arena, &peer, EXTERIA_MESSAGES_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"pinned messages" completion:done];
    }];
}

- (void)searchMessagesOfDialog:(ExteriaDialog *)dialog query:(NSString *)query completion:(ExteriaHistoryCompletion)completion {
    ExteriaHistoryCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [query copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_chat_search_request(arena, &peer, text.UTF8String, EXTERIA_MESSAGES_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"a text" completion:done];
    }];
    [text release];
}

- (void)searchMessagesOfDialog:(ExteriaDialog *)dialog fromUserId:(long long)userId accessHash:(long long)accessHash completion:(ExteriaHistoryCompletion)completion {
    ExteriaHistoryCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    exteria_peer_ref from = {1, userId, accessHash, 0, 0};
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_chat_from_request(arena, &peer, &from, EXTERIA_MESSAGES_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"the messages of a person" completion:done];
    }];
}

- (void)loadSharedOfDialog:(ExteriaDialog *)dialog kind:(exteria_shared_kind)kind beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(ExteriaHistoryCompletion)completion {
    ExteriaHistoryCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_shared_request(arena, &peer, kind, beforeId, limit, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"the shared media" completion:done];
    }];
}

static exteria_status ExteriaCollectMessage(void *ctx, int64_t id, const exteria_tl_value *value);

/* the store keeps a forum as one chat, so a topic takes its own messages out of the newest page of the whole forum */
static void ExteriaKeepTopic(NSMutableArray *messages, int32_t topic) {
    if (topic <= 0) return;
    NSIndexSet *others = [messages indexesOfObjectsPassingTest:^BOOL(id message, NSUInteger index, BOOL *stop) {
        (void)index;
        (void)stop;
        return [(ExteriaMessage *)message topicId] != topic;
    }];
    [messages removeObjectsAtIndexes:others];
}

/* worker only: a stored user, or a stored channel for a negative key, for the sender names of a chat opened offline */
- (ExteriaPerson *)storedPersonWithKey:(int64_t)key {
    exteria_arena arena;
    exteria_tl_value *entity = NULL;
    exteria_person_row row;
    exteria_peer none = {0, 0};
    ExteriaPerson *person = nil;
    exteria_arena_init(&arena, 1024u * 1024u);
    if (key > 0) {
        if (exteria_store_get([self workerStore], EXTERIA_RECORD_USER, none, key, &arena, &entity) == EXTERIA_OK &&
            exteria_person_parse(entity, &row) == EXTERIA_OK) person = [[[ExteriaPerson alloc] initWithRow:&row] autorelease];
    } else {
        exteria_peer channel = {3, -key};
        exteria_status status = exteria_store_get([self workerStore], EXTERIA_RECORD_CHAT, channel, -key, &arena, &entity);
        if (status == EXTERIA_E_NOTFOUND) {
            /* older caches placed community objects under basic-chat keys */
            exteria_peer old = {2, -key};
            status = exteria_store_get([self workerStore], EXTERIA_RECORD_CHAT, old, -key, &arena, &entity);
            if (status == EXTERIA_OK && !exteria_tl_is(entity, EXTERIA_TL_ID_community) &&
                !exteria_tl_is(entity, EXTERIA_TL_ID_communityForbidden)) status = EXTERIA_E_NOTFOUND;
        }
        if (status == EXTERIA_OK && exteria_channel_person_parse(entity, &row) == EXTERIA_OK)
            person = [[[ExteriaPerson alloc] initWithRow:&row] autorelease];
    }
    exteria_arena_free(&arena);
    return person;
}

- (void)loadCachedPeopleWithIds:(NSArray *)ids completion:(void (^)(NSDictionary *))completion {
    NSArray *requested = [ids copy];
    void (^done)(NSDictionary *) = [completion copy];
    [self post:^{
        NSMutableDictionary *people = [NSMutableDictionary dictionary];
        for (NSNumber *key in requested) {
            ExteriaPerson *person = [self storedPersonWithKey:key.longLongValue];
            if (person) [people setObject:person forKey:key];
        }
        [self deliverMain:^{ done(people); [done release]; }];
        [requested release];
    }];
}

- (NSDictionary *)storedPeopleForMessages:(NSArray *)messages {
    NSMutableDictionary *people = [NSMutableDictionary dictionary];
    for (ExteriaMessage *message in messages) {
        NSNumber *key = [NSNumber numberWithLongLong:message.senderKey];
        if (!message.senderKey || [people objectForKey:key]) continue;
        ExteriaPerson *person = [self storedPersonWithKey:message.senderKey];
        if (person) [people setObject:person forKey:key];
    }
    return people;
}

- (void)loadCachedHistoryOfDialog:(ExteriaDialog *)dialog completion:(ExteriaHistoryCompletion)completion {
    ExteriaHistoryCompletion done = [completion copy];
    exteria_peer peer = {dialog.peerKind, dialog.peerId};
    int32_t topic = dialog.topicId;
    [self post:^{
        NSMutableArray *messages = [NSMutableArray array];
        NSMutableDictionary *people = [NSMutableDictionary dictionary];
        exteria_status status = exteria_store_page([self workerStore], EXTERIA_RECORD_MESSAGE, peer, INT64_MAX, WATCH_PAGE,
                                                  ExteriaCollectMessage, messages);
        if (status != EXTERIA_OK) NSLog(@"exteria: cannot read the kept chat %lld: %s", (long long)peer.id, exteria_status_name(status));
        ExteriaKeepTopic(messages, topic);
        if (messages.count) {
            int32_t lowest = INT32_MAX;
            for (ExteriaMessage *message in messages) lowest = MIN(lowest, message.messageId);
            NSMutableArray *kept = ExteriaSavedDeletedOfPeer([self workerStore], peer, lowest, INT32_MAX);
            ExteriaKeepTopic(kept, topic);
            [messages addObjectsFromArray:kept];
        }
        [people addEntriesFromDictionary:[self storedPeopleForMessages:messages]];
        NSArray *deliveredMessages = status == EXTERIA_OK && messages.count ? [[messages copy] autorelease] : nil;
        NSDictionary *deliveredPeople = [[people copy] autorelease];
        [self deliverMain:^{ done(deliveredMessages, deliveredPeople, nil); [done release]; }];
    }];
}

#pragma mark topics

- (void)loadTopicsOfDialog:(ExteriaDialog *)forum completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(forum);
    exteria_dialog_row base;
    memset(&base, 0, sizeof(base));
    base.peer_kind = peer.kind;
    base.peer_id = peer.id;
    base.peer_hash = peer.access_hash;
    base.kind = EXTERIA_DIALOG_GROUP;
    snprintf(base.title, sizeof(base.title), "%s", forum.title.UTF8String);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_topics_request(arena, peer.kind, peer.id, peer.access_hash, 0, 0, 0, EXTERIA_DIALOGS_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *topics = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_topics_parse(result->value, &base, [self workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970],
                                             rows, EXTERIA_DIALOGS_MAX, &count) == EXTERIA_OK) {
                topics = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [topics addObject:[[[ExteriaDialog alloc] initWithRow:&rows[i]] autorelease]];
                [self noteDraftsOfTopicsAnswer:result->value forum:forum];
            } else {
                NSLog(@"exteria: messages.getForumTopics answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredTopics = [[topics copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredTopics, deliveredError); [done release]; }];
    }];
}

- (void)loadSavedDialogs:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_saved_dialogs_request(arena, 0, 0, 0, 0, 0, EXTERIA_DIALOGS_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *dialogs = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_dialogs_parse(result->value, [self workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970],
                                              rows, EXTERIA_DIALOGS_MAX, &count) == EXTERIA_OK) {
                dialogs = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [dialogs addObject:[[[ExteriaDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: messages.getSavedDialogs answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredDialogs = [[dialogs copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredDialogs, deliveredError); [done release]; }];
    }];
}

#pragma mark communities

- (void)loadCommunityPreviews:(NSMutableData *)data info:(ExteriaCommunity *)info known:(NSArray *)known at:(NSUInteger)offset
                    completion:(void (^)(ExteriaCommunity *, NSString *))completion {
    NSUInteger count = data.length / sizeof(exteria_dialog_row);
    if (offset >= count) {
        const exteria_dialog_row *rows = data.bytes;
        NSMutableArray *joined = [NSMutableArray array], *viewable = [NSMutableArray array];
        for (NSUInteger i = 0; i < count; ++i) {
            ExteriaDialog *chat = nil;
            if (!rows[i].date) {
                for (ExteriaDialog *candidate in known) {
                    if (!candidate.folder && candidate.peerKind == rows[i].peer_kind && candidate.peerId == rows[i].peer_id) {
                        chat = candidate;
                        break;
                    }
                }
            }
            if (!chat) chat = [[[ExteriaDialog alloc] initWithRow:&rows[i]] autorelease];
            [(rows[i].left ? viewable : joined) addObject:chat];
        }
        ExteriaCommunity *loaded = [[[ExteriaCommunity alloc] initWithTitle:info.title about:info.about collapsed:info.collapsed
                                                                  joined:joined viewable:viewable] autorelease];
        [self deliverMain:^{ completion(loaded, nil); }];
        return;
    }
    NSUInteger end = MIN(count, offset + 100);
    NSMutableData *peers = [NSMutableData data];
    const exteria_dialog_row *rows = data.bytes;
    for (NSUInteger i = offset; i < end; ++i) {
        exteria_peer_ref peer = {0};
        peer.kind = rows[i].peer_kind;
        peer.id = rows[i].peer_id;
        peer.access_hash = rows[i].peer_hash;
        if (peer.kind != 2 && !peer.access_hash) {
            NSLog(@"exteria: community peer %lld has no access hash", peer.id);
            continue;
        }
        [peers appendBytes:&peer length:sizeof(peer)];
    }
    if (!peers.length) {
        [self loadCommunityPreviews:data info:info known:known at:end completion:completion];
        return;
    }
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_peer_dialogs_request(arena, peers.bytes, peers.length / sizeof(exteria_peer_ref), request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        if (!error && exteria_community_previews_apply(result->value, [self workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970],
                                                       data.mutableBytes, count) != EXTERIA_OK) error = @"MALFORMED";
        if (error) {
            [self noteRpcError:error];
            NSLog(@"exteria: community message previews did not load: %@", error);
        }
        [self loadCommunityPreviews:data info:info known:known at:end completion:completion];
    }];
}

- (void)loadCommunity:(ExteriaDialog *)community knownDialogs:(NSArray *)known completion:(void (^)(ExteriaCommunity *, NSString *))completion {
    void (^done)(ExteriaCommunity *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(community);
    NSArray *kept = [known copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_full_channel_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        if (!error) {
            exteria_community_info info;
            NSMutableData *data = [NSMutableData dataWithLength:EXTERIA_DIALOGS_MAX * sizeof(exteria_dialog_row)];
            size_t count = 0;
            if (exteria_community_parse(result->value, &info, data.mutableBytes, EXTERIA_DIALOGS_MAX, &count) == EXTERIA_OK) {
                data.length = count * sizeof(exteria_dialog_row);
                NSString *title = [NSString stringWithUTF8String:info.title];
                NSString *about = [NSString stringWithUTF8String:info.about];
                ExteriaCommunity *loaded = [[[ExteriaCommunity alloc] initWithTitle:title.length ? title : community.title about:about ? about : @""
                    collapsed:info.collapsed joined:nil viewable:nil] autorelease];
                [self loadCommunityPreviews:data info:loaded known:kept at:0 completion:done];
            } else {
                NSLog(@"exteria: community answer rejected");
                error = @"MALFORMED";
            }
        }
        if (error) {
            [self noteRpcError:error];
            [self deliverMain:^{ done(nil, error); }];
        }
        [done release];
    }];
    [kept release];
}

- (void)setCommunity:(ExteriaDialog *)community collapsed:(BOOL)collapsed completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(community);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_community_collapse_request(arena, peer.id, peer.access_hash, collapsed, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
}

#pragma mark search

- (void)searchGlobal:(NSString *)query kind:(exteria_search_kind)kind offsetRate:(int32_t)offsetRate completion:(ExteriaSearchCompletion)completion {
    ExteriaSearchCompletion done = [completion copy];
    NSString *text = [query copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_search_request(arena, text.UTF8String, kind, offsetRate, 30, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *dialogs = nil;
        NSString *error = nil;
        int32_t next = 0;
        int64_t account = [self workerAccount];
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_dialog_row *rows = calloc(EXTERIA_MESSAGES_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_search_parse(result->value, account, rows, EXTERIA_MESSAGES_MAX, &count, &next) == EXTERIA_OK) {
                dialogs = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [dialogs addObject:[[[ExteriaDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: messages.searchGlobal answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredDialogs = [[dialogs copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredDialogs, next, deliveredError); [done release]; }];
    }];
    [text release];
}

#pragma mark sending

- (void)finishSend:(const exteria_mt_rpc_result *)result randomId:(long long)randomId completion:(ExteriaSendCompletion)done {
    int32_t serverId = 0;
    NSString *error = nil;
    if (result->status != EXTERIA_OK) {
        error = ExteriaRpcErrorName(result);
    } else {
        exteria_status status = exteria_sent_parse(result->value, randomId, &serverId);
        /* an answer that names no id still delivered the message, the store or a reload brings it back */
        if (status != EXTERIA_OK && status != EXTERIA_E_NOTFOUND) {
            NSLog(@"exteria: send answer rejected: %s", exteria_status_name(status));
            serverId = 0;
        }
    }
    [self noteRpcError:error];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(serverId, deliveredError); [done release]; }];
}

/* the kinds a message can carry from here; the rest (addresses, hashtags, commands) the server finds in the text itself */
static uint8_t ExteriaSendKindOfStyle(ExteriaTextStyle style) {
    switch (style) {
    case ExteriaTextStyleBold: return EXTERIA_ENTITY_BOLD;
    case ExteriaTextStyleItalic: return EXTERIA_ENTITY_ITALIC;
    case ExteriaTextStyleUnderline: return EXTERIA_ENTITY_UNDERLINE;
    case ExteriaTextStyleStrike: return EXTERIA_ENTITY_STRIKE;
    case ExteriaTextStyleCode: return EXTERIA_ENTITY_CODE;
    case ExteriaTextStylePre: return EXTERIA_ENTITY_PRE;
    case ExteriaTextStyleSpoiler: return EXTERIA_ENTITY_SPOILER;
    case ExteriaTextStyleQuote: return EXTERIA_ENTITY_BLOCKQUOTE;
    case ExteriaTextStyleLink: return EXTERIA_ENTITY_TEXT_URL;
    case ExteriaTextStyleMentionName: return EXTERIA_ENTITY_MENTION_NAME;
    case ExteriaTextStyleDate: return EXTERIA_ENTITY_FORMATTED_DATE;
    case ExteriaTextStyleCustomEmoji: return EXTERIA_ENTITY_CUSTOM_EMOJI;
    default: return 0;
    }
}

/* pack entities and their strings together so the worker does not depend on Objective-C objects */
NSMutableData *ExteriaPackSendEntities(NSArray *entities, NSMutableData **strings, size_t *count) {
    NSMutableData *packed = [NSMutableData dataWithLength:(entities.count ? entities.count : 1) * sizeof(exteria_send_entity)];
    NSMutableData *pool = [NSMutableData dataWithLength:1];
    exteria_send_entity *rows = packed.mutableBytes;
    size_t used = 0;
    for (ExteriaTextEntity *entity in entities) {
        if (used >= EXTERIA_MESSAGE_ENTITIES_MAX) break;
        uint8_t kind = ExteriaSendKindOfStyle(entity.style);
        if (!kind) continue;
        rows[used].kind = kind;
        rows[used].flags = entity.flags;
        rows[used].offset = (int32_t)entity.range.location;
        rows[used].length = (int32_t)entity.range.length;
        rows[used].id = kind == EXTERIA_ENTITY_MENTION_NAME ? entity.userId : entity.documentId;
        rows[used].access_hash = entity.accessHash;
        rows[used].date = entity.date;
        /* the offset into the buffer is turned into a pointer once the buffer has stopped growing */
        rows[used].text = entity.url.length ? (const char *)(uintptr_t)pool.length : NULL;
        if (entity.url.length) {
            NSData *utf8 = [entity.url dataUsingEncoding:NSUTF8StringEncoding];
            [pool appendData:utf8];
            [pool appendBytes:"\0" length:1];
        }
        ++used;
    }
    for (size_t i = 0; i < used; ++i) {
        if (rows[i].text) rows[i].text = (const char *)pool.bytes + (uintptr_t)rows[i].text;
    }
    *strings = pool;
    *count = used;
    return packed;
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId completion:(ExteriaSendCompletion)completion {
    [self sendText:text entities:entities toDialog:dialog randomId:randomId replyTo:0 completion:completion];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo
      completion:(ExteriaSendCompletion)completion {
    ExteriaSendCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    BOOL noPreview = ExteriaChatFlagGet(ExteriaChatFlagNoLinkPreview);
    NSMutableData *strings = nil;
    size_t count = 0;
    NSMutableData *packed = ExteriaPackSendEntities(entities, &strings, &count);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        /* the block keeps the data object, not only the pointer into it */
        exteria_status status = exteria_send_text_reply_request(arena, &peer, body.UTF8String, packed.bytes, count, randomId, replyTo, request);
        (void)strings;
        if (status == EXTERIA_OK && noPreview) status = exteria_tl_set_flag(*request, "no_webpage");
        return status == EXTERIA_OK ? ExteriaApplySendAs(self, &peer, arena, *request) : status;
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
    [body release];
}

- (void)sendSticker:(ExteriaMedia *)sticker toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId completion:(ExteriaSendCompletion)completion {
    [self sendSticker:sticker toDialog:dialog randomId:randomId replyTo:0 completion:completion];
}

- (void)sendSticker:(ExteriaMedia *)sticker toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(ExteriaSendCompletion)completion {
    ExteriaSendCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    exteria_media_ref ref = sticker.ref;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_status status = exteria_send_sticker_request(arena, &peer, &ref, randomId, request);
        if (status == EXTERIA_OK) status = exteria_set_reply(arena, *request, &peer, replyTo);
        return status == EXTERIA_OK ? ExteriaApplySendAs(self, &peer, arena, *request) : status;
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
}

- (void)markDialogRead:(ExteriaDialog *)dialog upTo:(int32_t)maxId {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    /* ghost mode: the chat is read on the screen and the other side is not told */
    if (maxId <= 0 || ExteriaChatFlagGet(ExteriaChatFlagGhostNoRead)) return;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_read_history_request(arena, &peer, maxId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status == EXTERIA_OK) return;
        NSString *error = ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSLog(@"exteria: marking chat %lld read failed: %@", peer.id, error);
    }];
}

#pragma mark watching

/* worker only: the visit callback of the store page; a message that cannot be shown is skipped */
static exteria_status ExteriaCollectMessage(void *ctx, int64_t id, const exteria_tl_value *value) {
    (void)id;
    NSMutableArray *messages = ctx;
    exteria_message_row *row = calloc(1, sizeof(*row));
    if (!row) return EXTERIA_E_NOMEM;
    if (exteria_message_read(value, row) == EXTERIA_OK) {
        ExteriaMessage *message = [ExteriaMessage messageWithRow:row];
        if (message && row->has_markup) message.markup = [ExteriaMarkup markupWithValue:exteria_tl_get(value, "reply_markup")];
        if (message) [messages addObject:message];
    }
    free(row);
    return EXTERIA_OK;
}

- (void)loadChannelSender:(long long)channelId ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaPerson *, NSString *))completion {
    void (^done)(ExteriaPerson *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_channel_from_message_request(arena, &peer, messageId, channelId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        ExteriaPerson *person = nil;
        if (!error) {
            person = [ExteriaPeopleOfAnswer(result->value) objectForKey:[NSNumber numberWithLongLong:-channelId]];
            if (!person.accessHash) error = @"CHANNEL_INVALID";
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(person, deliveredError); [done release]; }];
    }];
}

- (void)loadSenderRolesOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSDictionary *, NSDictionary *, NSString *))completion {
    void (^done)(NSDictionary *, NSDictionary *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_group_roles_request(arena, peer.kind, peer.id, peer.access_hash, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableDictionary *roles = [NSMutableDictionary dictionary];
        NSDictionary *people = nil;
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        if (!error) {
            exteria_group_role rows[EXTERIA_GROUP_ROLES_MAX];
            size_t count = 0;
            exteria_status status = exteria_group_roles_parse(result->value, peer.id, rows, EXTERIA_GROUP_ROLES_MAX, &count);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: group roles could not be read: %s", exteria_status_name(status));
                error = @"INTERNAL";
            } else {
                people = ExteriaPeopleOfAnswer(result->value);
                for (size_t i = 0; i < count; ++i) {
                    NSString *role = rows[i].rank[0] ? [NSString stringWithUTF8String:rows[i].rank]
                        : NSLocalizedString(rows[i].owner ? @"chat.role.owner" : @"chat.role.admin", nil);
                    [roles setObject:role forKey:[NSNumber numberWithLongLong:rows[i].user_id]];
                }
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(roles, people, deliveredError); [done release]; }];
    }];
}

- (void)watchDialog:(ExteriaDialog *)dialog handler:(void (^)(NSArray *messages))handler {
    if (!handler) { [self watchDialog:dialog peopleHandler:nil]; return; }
    [self watchDialog:dialog peopleHandler:^(NSArray *messages, NSDictionary *people) {
        (void)people;
        handler(messages);
    }];
}

- (void)watchDialog:(ExteriaDialog *)dialog peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler {
    [self watchDialog:dialog owner:nil peopleHandler:handler];
}

- (void)stopWatchingForOwner:(id)owner {
    void *key = owner;
    [self post:^{ [self clearStoreObserverOwnedBy:key]; }];
}

- (void)watchDialog:(ExteriaDialog *)dialog owner:(id)owner peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler {
    if (!dialog || !handler) {
        [self post:^{ [self setStoreObserver:nil]; }];
        return;
    }
    void *key = owner;
    void (^deliver)(NSArray *, NSDictionary *) = [handler copy];
    exteria_peer peer = {dialog.peerKind, dialog.peerId};
    int32_t topic = dialog.topicId;
    /* the same page twice in a row is not worth a trip to the main thread */
    NSMutableString *signature = [[NSMutableString alloc] init];
    /* the store counts the writes that touch this chat, so a change elsewhere (every update of every other chat
       reaches this observer) costs one compare and no page read */
    __block const exteria_store *seenStore = NULL;
    __block uint64_t seenVersion = 0;
    [self post:^{
        [self setStoreObserver:^{
            exteria_store *store = [self workerStore];
            uint64_t version = exteria_store_peer_version(store, peer);
            if (store == seenStore && version == seenVersion) return;
            NSMutableArray *messages = [NSMutableArray array];
            exteria_status status = exteria_store_page(store, EXTERIA_RECORD_MESSAGE, peer, INT64_MAX, WATCH_PAGE,
                                                      ExteriaCollectMessage, messages);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: reading chat %lld from the store failed: %s", (long long)peer.id, exteria_status_name(status));
                return;
            }
            ExteriaKeepTopic(messages, topic);
            /* what the person asked to keep stays in the chat among the live messages: the kept ones that fall inside the page */
            int32_t lowest = INT32_MAX;
            for (ExteriaMessage *message in messages) lowest = MIN(lowest, message.messageId);
            NSMutableArray *deleted = ExteriaSavedDeletedOfPeer(store, peer, messages.count ? lowest : 0, INT32_MAX);
            ExteriaKeepTopic(deleted, topic);
            [messages addObjectsFromArray:deleted];
            NSMutableString *sum = [NSMutableString string];
            NSDictionary *people = [self storedPeopleForMessages:messages];
            for (ExteriaMessage *message in messages) {
                ExteriaPerson *sender = [people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
                [sum appendFormat:@"%d:%d:%d:%lu:%@:%@:%lld:%lu:%@:%@:%@:%d|", message.messageId, message.edited, message.deletedLocally, (unsigned long)message.text.length,
                    message.reactionKey, message.markupKey, message.senderKey, (unsigned long)sender.name.length, sender.name, sender.photo.key,
                    message.senderRank, sender.bot];
            }
            seenStore = store;
            seenVersion = version;
            if ([sum isEqualToString:signature]) return;
            [signature setString:sum];
            NSArray *page = [[messages copy] autorelease];
            [self deliverMain:^{ deliver(page, people); }];
        } owner:key];
        /* what is already stored shows at once */
        [self storeChanged];
    }];
    [deliver release];
    [signature release];
}

#pragma mark reactions

- (void)loadCustomEmojiDocuments:(NSArray *)documentIds completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    NSUInteger count = MIN(documentIds.count, (NSUInteger)EXTERIA_CUSTOM_EMOJI_MAX);
    /* the request is built later on the worker, so the ids travel in an object the block keeps */
    NSMutableData *packed = [NSMutableData dataWithLength:(count ? count : 1) * sizeof(int64_t)];
    int64_t *ids = packed.mutableBytes;
    for (NSUInteger i = 0; i < count; ++i) ids[i] = [[documentIds objectAtIndex:i] longLongValue];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_custom_emoji_request(arena, packed.bytes, count, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *documents = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            /* the rows hold two file references each, so they live on the heap rather than on the worker's stack */
            exteria_custom_emoji *rows = calloc(EXTERIA_CUSTOM_EMOJI_MAX, sizeof(*rows));
            size_t found = 0;
            if (rows && exteria_custom_emoji_parse(result->value, rows, EXTERIA_CUSTOM_EMOJI_MAX, &found) == EXTERIA_OK) {
                documents = [NSMutableArray arrayWithCapacity:found];
                for (size_t i = 0; i < found; ++i) {
                    ExteriaCustomEmojiDocument *document = [[ExteriaCustomEmojiDocument alloc] initWithRow:&rows[i]];
                    if (document.alt.length) [documents addObject:document];
                    [document release];
                }
            } else {
                NSLog(@"exteria: custom emoji answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredDocuments = [[documents copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredDocuments, deliveredError); [done release]; }];
    }];
}

/* the custom emoji a Premium account uses most or lately, from the two lists the server keeps; a list that fails
   is skipped and the other still counts */
- (void)loadFrequentCustomReactions:(void (^)(NSArray *reactions))then {
    void (^finish)(NSArray *) = [then copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_reaction_list_request(arena, 0, 24, request);
    } handler:^(const exteria_mt_rpc_result *top) {
        NSMutableArray *found = [NSMutableArray array];
        exteria_reaction rows[EXTERIA_REACTION_CATALOG_MAX];
        size_t count = 0;
        if (top->status == EXTERIA_OK && exteria_reaction_list_read(top->value, rows, EXTERIA_REACTION_CATALOG_MAX, &count) == EXTERIA_OK) {
            for (size_t i = 0; i < count; ++i) [found addObject:[ExteriaReaction reactionWithRow:&rows[i]]];
        } else {
            NSLog(@"exteria: top reactions not taken: %@", top->status == EXTERIA_OK ? @"rejected" : ExteriaRpcErrorName(top));
        }
        [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_reaction_list_request(arena, 1, 24, request);
        } handler:^(const exteria_mt_rpc_result *recent) {
            exteria_reaction more[EXTERIA_REACTION_CATALOG_MAX];
            size_t added = 0;
            if (recent->status == EXTERIA_OK && exteria_reaction_list_read(recent->value, more, EXTERIA_REACTION_CATALOG_MAX, &added) == EXTERIA_OK) {
                for (size_t i = 0; i < added; ++i) {
                    ExteriaReaction *reaction = [ExteriaReaction reactionWithRow:&more[i]];
                    BOOL seen = NO;
                    for (ExteriaReaction *known in found) seen = seen || [known.key isEqualToString:reaction.key];
                    if (!seen) [found addObject:reaction];
                }
            } else {
                NSLog(@"exteria: recent reactions not taken: %@", recent->status == EXTERIA_OK ? @"rejected" : ExteriaRpcErrorName(recent));
            }
            finish(found);
            [finish release];
        }];
    }];
}

- (void)loadReactionCatalogWithPolicy:(exteria_reactions)allowed all:(BOOL)all custom:(BOOL)allowCustom premium:(BOOL)premium
                           completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "messages.getAvailableReactions");
        return *request ? exteria_tl_set_i32(arena, *request, "hash", 0) : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *items = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else {
            exteria_reaction rows[EXTERIA_REACTION_CATALOG_MAX];
            size_t count = 0;
            exteria_status status = exteria_reaction_catalog_read(result->value, rows, EXTERIA_REACTION_CATALOG_MAX, &count);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: reaction catalog rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            } else {
                items = [NSMutableArray array];
                for (size_t i = 0; i < count; ++i) {
                    BOOL permitted = all;
                    for (uint8_t j = 0; !permitted && j < allowed.count; ++j)
                        permitted = exteria_reaction_equal(&rows[i], &allowed.items[j]);
                    if (permitted) [items addObject:[ExteriaReaction reactionWithRow:&rows[i]]];
                }
                /* only a Premium account may react with a custom emoji, those the chat lists and, where the chat allows any, its own favorites */
                if (premium) {
                    for (uint8_t j = 0; j < allowed.count; ++j) {
                        if (allowed.items[j].kind == EXTERIA_REACTION_CUSTOM) [items addObject:[ExteriaReaction reactionWithRow:&allowed.items[j]]];
                    }
                }
            }
        }
        if (error || !premium || !all || !allowCustom) {
            [self finishLoad:items error:error completion:done];
            [done release];
            return;
        }
        NSMutableArray *standard = items;
        [self loadFrequentCustomReactions:^(NSArray *favorites) {
            for (ExteriaReaction *reaction in favorites) {
                BOOL seen = NO;
                for (ExteriaReaction *known in standard) seen = seen || [known.key isEqualToString:reaction.key];
                if (!seen) [standard addObject:reaction];
            }
            [self finishLoad:standard error:nil completion:done];
            [done release];
        }];
    }];
}

- (void)loadAvailableReactionsForDialog:(ExteriaDialog *)dialog premium:(BOOL)premium completion:(ExteriaListCompletion)completion {
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    if (peer.kind == 1) {
        exteria_reactions allowed;
        memset(&allowed, 0, sizeof(allowed));
        [self loadReactionCatalogWithPolicy:allowed all:YES custom:YES premium:premium completion:completion];
        return;
    }
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        if (peer.kind == 2) {
            *request = exteria_tl_new_obj(arena, "messages.getFullChat");
            return *request ? exteria_tl_set_i64(arena, *request, "chat_id", peer.id) : EXTERIA_E_NOMEM;
        }
        exteria_tl_value *channel = exteria_tl_new_obj(arena, "inputChannel");
        *request = exteria_tl_new_obj(arena, "channels.getFullChannel");
        if (!channel || !*request) return EXTERIA_E_NOMEM;
        exteria_status status = exteria_tl_set_i64(arena, channel, "channel_id", peer.id);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", peer.access_hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(*request, "channel", channel);
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        exteria_reactions allowed;
        int all = 0, custom = 0;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else {
            exteria_status status = exteria_reaction_policy_read(result->value, &allowed, &all);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: chat reaction policy rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            custom = exteria_reaction_policy_custom(result->value);
        }
        if (error) [self finishLoad:nil error:error completion:done];
        else [self loadReactionCatalogWithPolicy:allowed all:all custom:custom premium:premium completion:done];
        [done release];
    }];
}

- (void)refreshReactionsForMessages:(NSArray *)ids dialog:(ExteriaDialog *)dialog completion:(ExteriaListCompletion)completion {
    NSArray *requested = [ids copy];
    ExteriaListCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        int32_t values[EXTERIA_MESSAGES_MAX];
        if (!requested.count || requested.count > EXTERIA_MESSAGES_MAX) return EXTERIA_E_ARG;
        for (NSUInteger i = 0; i < requested.count; ++i) values[i] = [[requested objectAtIndex:i] intValue];
        return exteria_get_reactions_request(arena, &peer, values, requested.count, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *messages = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else {
            messages = [NSMutableArray array];
            exteria_peer storedPeer = {peer.kind, peer.id};
            for (NSNumber *key in requested) {
                exteria_arena arena;
                exteria_tl_value *value = NULL;
                exteria_message_row *row = calloc(1, sizeof(*row));
                exteria_arena_init(&arena, 8u * 1024u * 1024u);
                exteria_status status = row ? exteria_store_get([self workerStore], EXTERIA_RECORD_MESSAGE,
                    storedPeer, key.intValue, &arena, &value) : EXTERIA_E_NOMEM;
                if (status == EXTERIA_OK) status = exteria_message_read(value, row);
                exteria_reactions fresh;
                if (status == EXTERIA_OK) status = exteria_reaction_update_read(result->value, peer.kind, peer.id, key.intValue, &fresh);
                if (status == EXTERIA_OK && !fresh.min) {
                    row->reactions = fresh;
                    row->has_reactions = 1;
                }
                if (status == EXTERIA_OK) {
                    ExteriaMessage *refreshed = [ExteriaMessage messageWithRow:row];
                    if (row->has_markup) refreshed.markup = [ExteriaMarkup markupWithValue:exteria_tl_get(value, "reply_markup")];
                    [messages addObject:refreshed];
                }
                else {
                    NSLog(@"exteria: refreshed reactions for %d unavailable: %s", key.intValue, exteria_status_name(status));
                    error = @"INTERNAL";
                }
                free(row);
                exteria_arena_free(&arena);
            }
        }
        [self finishLoad:error ? nil : messages error:error completion:done];
        [done release];
    }];
    [requested release];
}

- (void)sendReactions:(NSArray *)reactions messageId:(int32_t)messageId dialog:(ExteriaDialog *)dialog
           completion:(ExteriaListCompletion)completion {
    NSArray *choices = [reactions copy];
    ExteriaListCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_reaction rows[EXTERIA_REACTIONS_MAX];
        if (choices.count > EXTERIA_REACTIONS_MAX) return EXTERIA_E_ARG;
        for (NSUInteger i = 0; i < choices.count; ++i) rows[i] = [(ExteriaReaction *)[choices objectAtIndex:i] row];
        return exteria_send_reactions_request(arena, &peer, messageId, rows, choices.count, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) [self finishLoad:nil error:ExteriaRpcErrorName(result) completion:done];
        else [self refreshReactionsForMessages:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] dialog:dialog completion:done];
        [done release];
    }];
    [choices release];
}

#pragma mark stickers

- (void)loadStickerSets:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "messages.getAllStickers");
        return *request ? exteria_tl_set_i64(arena, *request, "hash", 0) : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_set_row *rows = calloc(EXTERIA_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_sticker_sets_parse(result->value, rows, EXTERIA_STICKER_SETS_MAX, &count) == EXTERIA_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[ExteriaStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getAllStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:sets error:error completion:done];
        [done release];
    }];
}

- (void)loadAnimatedEmojiStickers:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_animated_emoji_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_row *rows = calloc(EXTERIA_ANIMATED_EMOJI_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_animated_emoji_parse(result->value, rows, EXTERIA_ANIMATED_EMOJI_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[ExteriaSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: animated emoji pack rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

- (void)loadStickersOfSet:(ExteriaStickerSet *)set completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    exteria_sticker_set_row row = set.row;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_set_request(arena, &row, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_row *rows = calloc(EXTERIA_STICKERS_MAX, sizeof(*rows));
            exteria_sticker_set_row header;
            size_t count = 0;
            if (rows && exteria_sticker_set_parse(result->value, &header, rows, EXTERIA_STICKERS_MAX, &count) == EXTERIA_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[ExteriaSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getStickerSet answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

- (void)loadStickersOfSetNamed:(NSString *)shortName completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    NSString *name = [shortName copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_set_by_name_request(arena, name.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_row *rows = calloc(EXTERIA_STICKERS_MAX, sizeof(*rows));
            exteria_sticker_set_row header;
            size_t count = 0;
            if (rows && exteria_sticker_set_parse(result->value, &header, rows, EXTERIA_STICKERS_MAX, &count) == EXTERIA_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[ExteriaSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getStickerSet answer for %@ rejected", name);
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
    [name release];
}

- (void)loadEmojiSets:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_emoji_sets_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_set_row *rows = calloc(EXTERIA_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_emoji_sets_parse(result->value, rows, EXTERIA_STICKER_SETS_MAX, &count) == EXTERIA_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[ExteriaStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getEmojiStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:sets error:error completion:done];
        [done release];
    }];
}

- (void)loadEmojiOfSet:(ExteriaStickerSet *)set completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    exteria_sticker_set_row row = set.row;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_sticker_set_request(arena, &row, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *emoji = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_custom_emoji *rows = calloc(EXTERIA_STICKERS_MAX, sizeof(*rows));
            exteria_sticker_set_row header;
            size_t count = 0;
            if (rows && exteria_emoji_set_parse(result->value, &header, rows, EXTERIA_STICKERS_MAX, &count) == EXTERIA_OK) {
                emoji = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    ExteriaCustomEmojiDocument *document = [[ExteriaCustomEmojiDocument alloc] initWithRow:&rows[i]];
                    [emoji addObject:document];
                    [document release];
                }
            } else {
                NSLog(@"exteria: messages.getStickerSet answer for emoji rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:emoji error:error completion:done];
        [done release];
    }];
}

- (void)loadRecentStickers:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "messages.getRecentStickers");
        return *request ? exteria_tl_set_i64(arena, *request, "hash", 0) : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_row *rows = calloc(EXTERIA_STICKERS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_recent_stickers_parse(result->value, rows, EXTERIA_STICKERS_MAX, &count) == EXTERIA_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[ExteriaSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getRecentStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

/* the stickers of a list the server answered in full, read with the parser of its kind */
- (void)loadStickerList:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build
                  parse:(exteria_status (*)(const exteria_tl_value *, exteria_sticker_row *, size_t, size_t *))parse
                   what:(const char *)what completion:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_row *rows = calloc(EXTERIA_STICKERS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? parse(result->value, rows, EXTERIA_STICKERS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[ExteriaSticker stickerWithRow:&rows[i]]];
            } else if (status == EXTERIA_E_NOTFOUND) {
                stickers = [NSMutableArray array];
            } else {
                NSLog(@"exteria: the answer for %s was rejected: %s", what, exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

- (void)loadFavedStickers:(ExteriaListCompletion)completion {
    [self loadStickerList:^exteria_status(exteria_arena *arena, exteria_tl_value **request) { return exteria_faved_stickers_request(arena, request); }
                    parse:exteria_faved_stickers_parse what:"the favorite stickers" completion:completion];
}

- (void)loadSavedGifs:(ExteriaListCompletion)completion {
    [self loadStickerList:^exteria_status(exteria_arena *arena, exteria_tl_value **request) { return exteria_saved_gifs_request(arena, request); }
                    parse:exteria_saved_gifs_parse what:"the saved animations" completion:completion];
}

- (void)faveSticker:(ExteriaSticker *)sticker unfave:(BOOL)unfave completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_media_ref ref = sticker.media.ref;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_fave_sticker_request(arena, &ref, unfave ? 1 : 0, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_sticker_manage_parse(result->value) != EXTERIA_OK) error = @"NOT_DONE";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)clearRecentStickers:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_clear_recent_stickers_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_sticker_manage_parse(result->value) != EXTERIA_OK) error = @"NOT_DONE";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)loadGreetingStickers:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_stickers_request(arena, "\xf0\x9f\x91\x8b", request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_sticker_row *rows = calloc(EXTERIA_STICKERS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && exteria_stickers_parse(result->value, rows, EXTERIA_STICKERS_MAX, &count) == EXTERIA_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[ExteriaSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: messages.getStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

@end
