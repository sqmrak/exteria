#import "exteria_forward.h"

#include "exteria_message_actions.h"

#import "exteria_chat_settings.h"
#import "exteria_gift_screen.h"
#import "exteria_message.h"
#import "exteria_person.h"
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

static void ExteriaCopyMessagesWithLines(ExteriaSession *session, ExteriaMediaCache *cache, NSArray *messages, NSUInteger index, ExteriaDialog *target, NSDictionary *lines, void (^completion)(NSUInteger, NSString *));
static void ExteriaCopyMessages(ExteriaSession *session, ExteriaMediaCache *cache, NSArray *messages, NSUInteger index, ExteriaDialog *target, void (^completion)(NSUInteger, NSString *)) {
    ExteriaCopyMessagesWithLines(session, cache, messages, index, target, nil, completion);
}

static void ExteriaCopyMessagesWithLines(ExteriaSession *session, ExteriaMediaCache *cache, NSArray *messages, NSUInteger index, ExteriaDialog *target, NSDictionary *lines, void (^completion)(NSUInteger, NSString *)) {
    if (index >= messages.count) { completion(index, nil); return; }
    ExteriaMessage *message = [messages objectAtIndex:index];
    ExteriaMedia *media = message.media;
    long long randomId = ExteriaCopyRandomId();
    ExteriaSendCompletion done = ^(int32_t messageId, NSString *error) {
        (void)messageId;
        if (error) { completion(index, error); return; }
        ExteriaCopyMessagesWithLines(session, cache, messages, index + 1, target, lines, completion);
    };
    /* the author's line: the name in bold and the @username after it, then the words of the message under it */
    NSString *line = [lines objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    NSString *words = message.text ? message.text : @"";
    NSArray *entities = message.entities;
    if (line.length) {
        NSUInteger shift = line.length + 1;
        NSMutableArray *shifted = [NSMutableArray array];
        NSRange boldRange = [line rangeOfString:@" @" options:NSBackwardsSearch];
        NSUInteger nameLength = boldRange.location == NSNotFound ? line.length : boldRange.location;
        [shifted addObject:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleBold range:NSMakeRange(0, nameLength) url:nil] autorelease]];
        for (ExteriaTextEntity *entity in message.entities) {
            ExteriaTextEntity *moved = [[[ExteriaTextEntity alloc] initWithStyle:entity.style range:NSMakeRange(entity.range.location + shift, entity.range.length) url:entity.url] autorelease];
            moved.documentId = entity.documentId; moved.userId = entity.userId; moved.date = entity.date; moved.flags = entity.flags;
            [shifted addObject:moved];
        }
        entities = shifted;
        words = [NSString stringWithFormat:@"%@\n%@", line, words];
    }
    if (media.kind == EXTERIA_PREVIEW_NONE || media.kind == EXTERIA_PREVIEW_TEXT) {
        [session sendText:words entities:entities toDialog:target randomId:randomId completion:done];
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
            [session sendPhotoAtPath:named caption:words spoiler:media.spoiler toDialog:target randomId:randomId completion:^(int32_t messageId, NSString *error) {
                [[NSFileManager defaultManager] removeItemAtPath:named error:NULL];
                done(messageId, error);
            }];
            break;
        }
        case EXTERIA_PREVIEW_VIDEO:
            [session sendVideoAtPath:path durationMs:duration width:media.width height:media.height caption:words spoiler:media.spoiler toDialog:target randomId:randomId completion:done]; break;
        case EXTERIA_PREVIEW_VIDEO_MESSAGE:
            [session sendRoundVideoAtPath:path durationMs:duration side:media.width toDialog:target randomId:randomId completion:done]; break;
        case EXTERIA_PREVIEW_VOICE:
            [session sendVoiceAtPath:path durationMs:duration waveform:media.waveformBars toDialog:target randomId:randomId completion:done]; break;
        default:
            [session sendDocumentAtPath:path name:media.name mime:media.mime caption:words toDialog:target randomId:randomId completion:done]; break;
        }
    }];
}

static void ExteriaForwardMessagesNow(ExteriaSession *session, ExteriaMediaCache *cache, ExteriaDialog *from, BOOL chatRestricted, NSArray *messages, ExteriaDialog *target, BOOL hideAuthor, void (^completion)(NSString *message));

/* the target of the cancel button of the topic list: it closes the list and answers with nothing */
@interface ExteriaForwardCancel : NSObject {
    void (^_block)(void);
}
- (id)initWithBlock:(void (^)(void))block;
- (void)fire;
@end

@implementation ExteriaForwardCancel
- (id)initWithBlock:(void (^)(void))block {
    self = [super init];
    if (self) _block = [block copy];
    return self;
}
- (void)fire { if (_block) _block(); }
- (void)dealloc { [_block release]; [super dealloc]; }
@end

static UIViewController *ExteriaForwardFrontController(void) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

/* a forum asks for the topic the messages go to, as the other clients do: the topics of the group in a list over the screen, and the one that is tapped is the target; a forum whose
   topics do not load keeps the answer of the group itself, which the server reads as its General topic */
static void ExteriaChooseForwardTopic(ExteriaSession *session, ExteriaDialog *target, void (^done)(ExteriaDialog *chosen)) {
    if (!target.forum || target.topicId > 0) { done(target); return; }
    void (^answer)(ExteriaDialog *) = [done copy];
    [session loadTopicsOfDialog:target completion:^(NSArray *topics, NSString *errorName) {
        UIViewController *front = ExteriaForwardFrontController();
        if (errorName || !topics.count || !front) {
            if (errorName) NSLog(@"exteria: the topics for a forward did not load: %@", errorName);
            answer(target);
            [answer release];
            return;
        }
        ExteriaSettingsPageController *page = [[[ExteriaSettingsPageController alloc] init] autorelease];
        page.pageTitle = NSLocalizedString(@"chat.forward.topic", nil);
        UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:page] autorelease];
        navigation.modalPresentationStyle = UIModalPresentationFormSheet;
        NSMutableArray *rows = [NSMutableArray array];
        __block BOOL chosen = NO;
        for (ExteriaDialog *topic in topics) {
            if (topic.topicClosed) continue;
            [rows addObject:[ExteriaSettingsRow rowWithTitle:topic.title value:nil tap:^{
                if (chosen) return;
                chosen = YES;
                [navigation dismissViewControllerAnimated:YES completion:^{ answer(topic); [answer release]; }];
            }]];
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
    __block NSDictionary *authorLines = nil;
    void (^copy)(void) = ^{
        /* a poll, a place or a contact in the pick cannot be sent again; the rest of a pick must still go, and the person is told how many stayed behind */
        NSMutableArray *copyable = [NSMutableArray arrayWithCapacity:messages.count];
        for (ExteriaMessage *message in messages) if (ExteriaCanCopyForward(message)) [copyable addObject:message];
        long skipped = (long)(messages.count - copyable.count);
        if (!copyable.count) { completion(NSLocalizedString(@"ayu.copyprotected.failed", nil)); return; }
        ExteriaCopyMessagesWithLines(session, cache, copyable, 0, target, authorLines, ^(NSUInteger sent, NSString *error) {
            if (error && sent) completion([NSString stringWithFormat:NSLocalizedString(@"ayu.copyprotected.partial", nil), (long)sent, ExteriaGiftErrorText(error)]);
            else if (error) completion(ExteriaGiftErrorText(error));
            else completion(skipped ? [NSString stringWithFormat:NSLocalizedString(@"ayu.copyprotected.skipped", nil), (long)copyable.count, skipped] : nil);
        });
    };
    /* without the author, and the person asked for his name: the messages go as copies that open with the name and the @username of whoever wrote them */
    if (hideAuthor && ExteriaChatFlagGet(ExteriaChatFlagForwardAuthor)) {
        NSMutableArray *keys = [NSMutableArray array];
        for (ExteriaMessage *message in messages) {
            NSNumber *key = [NSNumber numberWithLongLong:message.senderKey];
            if (message.senderKey && ![keys containsObject:key]) [keys addObject:key];
        }
        [session loadCachedPeopleWithIds:keys completion:^(NSDictionary *people) {
            NSMutableDictionary *lines = [NSMutableDictionary dictionary];
            for (NSNumber *key in people) {
                ExteriaPerson *person = [people objectForKey:key];
                if (!person.name.length) continue;
                [lines setObject:person.username.length ? [NSString stringWithFormat:@"%@ @%@", person.name, person.username] : person.name forKey:key];
            }
            authorLines = [lines retain];
            copy();
        }];
        return;
    }
    if (allowCopy && restricted) { copy(); return; }
    [session forwardMessageIds:ids fromDialog:from toDialog:target hideAuthor:hideAuthor completion:^(NSString *error) {
        if (allowCopy && ([error isEqualToString:@"CHAT_FORWARDS_RESTRICTED"] || [error isEqualToString:@"MESSAGE_COPYRIGHTED"])) copy();
        else completion(error ? ExteriaGiftErrorText(error) : nil);
    }];
}
