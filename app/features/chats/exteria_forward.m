#import "exteria_forward.h"

#include "exteria_message_actions.h"

#import "exteria_chat_settings.h"
#import "exteria_gift_screen.h"
#import "exteria_message.h"
#import "exteria_session_actions.h"

static BOOL ExteriaCanCopyForward(ExteriaMessage *message) {
    ExteriaMedia *media = message.media;
    BOOL fullPhoto = media.kind == EXTERIA_PREVIEW_PHOTO && media.fullPhotoFile != nil;
    return !message.service && exteria_copy_forward_allowed(media.kind, message.text.length > 0,
        fullPhoto || media.file != nil, media.viewOnce, fullPhoto ? media.fullPhotoSize : media.size, media.duration);
}

static long long ExteriaCopyRandomId(void) {
    long long random;
    do {
        random = (long long)(((uint64_t)arc4random() << 32 | arc4random()) & 0x7fffffffffffffffULL);
    } while (random == 0);
    return random;
}

static void ExteriaCopyMessages(ExteriaSession *session, ExteriaMediaCache *cache, NSArray *messages, NSUInteger index, ExteriaDialog *target, void (^completion)(NSUInteger, NSString *)) {
    if (index >= messages.count) { completion(index, nil); return; }
    ExteriaMessage *message = [messages objectAtIndex:index];
    ExteriaMedia *media = message.media;
    long long randomId = ExteriaCopyRandomId();
    ExteriaSendCompletion done = ^(int32_t messageId, NSString *error) {
        (void)messageId;
        if (error) { completion(index, error); return; }
        ExteriaCopyMessages(session, cache, messages, index + 1, target, completion);
    };
    if (media.kind == EXTERIA_PREVIEW_NONE || media.kind == EXTERIA_PREVIEW_TEXT) {
        [session sendText:message.text entities:message.entities toDialog:target randomId:randomId completion:done];
        return;
    }
    if (media.kind == EXTERIA_PREVIEW_STICKER) {
        [session sendSticker:media toDialog:target randomId:randomId completion:done];
        return;
    }
    ExteriaRemoteFile *file = media.kind == EXTERIA_PREVIEW_PHOTO && media.fullPhotoFile ? media.fullPhotoFile : media.file;
    long long size = media.kind == EXTERIA_PREVIEW_PHOTO && media.fullPhotoFile ? media.fullPhotoSize : media.size;
    [cache loadPathForFile:file size:size progress:nil completion:^(NSString *path) {
        if (!path) { completion(index, @"DOWNLOAD_FAILED"); return; }
        int32_t duration = media.duration * 1000;
        switch (media.kind) {
        case EXTERIA_PREVIEW_PHOTO: {
            /* the cache names a file by its key with no extension, and the upload sends that name: the server answers PHOTO_EXT_INVALID to a photo without .jpg */
            NSString *named = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"copy-%08x%08x.jpg", arc4random(), arc4random()]];
            NSError *copyError = nil;
            if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:named error:&copyError]) {
                NSLog(@"exteria: the photo to copy could not be staged: %@", copyError);
                completion(index, @"INTERNAL");
                return;
            }
            [session sendPhotoAtPath:named caption:message.text spoiler:media.spoiler toDialog:target randomId:randomId completion:^(int32_t messageId, NSString *error) {
                [[NSFileManager defaultManager] removeItemAtPath:named error:NULL];
                done(messageId, error);
            }];
            break;
        }
        case EXTERIA_PREVIEW_VIDEO:
            [session sendVideoAtPath:path durationMs:duration width:media.width height:media.height caption:message.text spoiler:media.spoiler toDialog:target randomId:randomId completion:done]; break;
        case EXTERIA_PREVIEW_VIDEO_MESSAGE:
            [session sendRoundVideoAtPath:path durationMs:duration side:media.width toDialog:target randomId:randomId completion:done]; break;
        case EXTERIA_PREVIEW_VOICE:
            [session sendVoiceAtPath:path durationMs:duration waveform:media.waveformBars toDialog:target randomId:randomId completion:done]; break;
        default:
            [session sendDocumentAtPath:path name:media.name mime:media.mime caption:message.text toDialog:target randomId:randomId completion:done]; break;
        }
    }];
}

void ExteriaForwardMessages(ExteriaSession *session, ExteriaMediaCache *cache, ExteriaDialog *from, BOOL chatRestricted, NSArray *messages, ExteriaDialog *target, BOOL hideAuthor, void (^completion)(NSString *message)) {
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:messages.count];
    BOOL restricted = chatRestricted;
    for (ExteriaMessage *message in messages) {
        [ids addObject:[NSNumber numberWithInt:message.messageId]];
        restricted = restricted || message.noForwards;
    }
    BOOL allowCopy = ExteriaChatFlagGet(ExteriaChatFlagAyuCopyProtected);
    void (^copy)(void) = ^{
        /* a poll, a place or a contact in the pick cannot be sent again; the rest of a pick must still go, and the person is told how many stayed behind */
        NSMutableArray *copyable = [NSMutableArray arrayWithCapacity:messages.count];
        for (ExteriaMessage *message in messages) if (ExteriaCanCopyForward(message)) [copyable addObject:message];
        long skipped = (long)(messages.count - copyable.count);
        if (!copyable.count) { completion(NSLocalizedString(@"ayu.copyprotected.failed", nil)); return; }
        ExteriaCopyMessages(session, cache, copyable, 0, target, ^(NSUInteger sent, NSString *error) {
            if (error && sent) completion([NSString stringWithFormat:NSLocalizedString(@"ayu.copyprotected.partial", nil), (long)sent, ExteriaGiftErrorText(error)]);
            else if (error) completion(ExteriaGiftErrorText(error));
            else completion(skipped ? [NSString stringWithFormat:NSLocalizedString(@"ayu.copyprotected.skipped", nil), (long)copyable.count, skipped] : nil);
        });
    };
    if (allowCopy && restricted) { copy(); return; }
    [session forwardMessageIds:ids fromDialog:from toDialog:target hideAuthor:hideAuthor completion:^(NSString *error) {
        if (allowCopy && ([error isEqualToString:@"CHAT_FORWARDS_RESTRICTED"] || [error isEqualToString:@"MESSAGE_COPYRIGHTED"])) copy();
        else completion(error ? ExteriaGiftErrorText(error) : nil);
    }];
}
