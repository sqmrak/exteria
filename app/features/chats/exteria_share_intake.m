#import "exteria_share_intake.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/message.h>

#import "exteria_attach_flow.h"
#import "exteria_image_decoder.h"
#import "exteria_message.h"

NSString *const ExteriaShareFilesNotification = @"ExteriaShareFiles";

/* the longest side a shared picture keeps, as the gallery sheet does for the original quality */
#define SHARE_SIDE_MAX 2560.0
#define SHARE_JPEG_QUALITY 0.9
#define SHARE_FILES_MAX 10

static NSString *ExteriaShareTemporaryJpeg(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-share-%08x%08x.jpg", arc4random(), arc4random()]];
}

static BOOL ExteriaShareConforms(NSString *extension, CFStringRef type) {
    if (!extension.length) return NO;
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL);
    BOOL fits = uti && UTTypeConformsTo(uti, type);
    if (uti) CFRelease(uti);
    return fits;
}

/* off the main thread: the outgoing item of one file, or nil when the file cannot be read */
static ExteriaOutgoing *ExteriaShareOutgoing(NSURL *url, NSString **removable) {
    NSString *path = url.path;
    NSString *extension = path.pathExtension;
    BOOL gif = [extension caseInsensitiveCompare:@"gif"] == NSOrderedSame;
    if (!gif && ExteriaShareConforms(extension, kUTTypeImage)) {
        UIImage *image = ExteriaDecodeImageAtURL(url, SHARE_SIDE_MAX);
        NSData *jpeg = image ? UIImageJPEGRepresentation(image, SHARE_JPEG_QUALITY) : nil;
        NSString *jpegPath = jpeg ? ExteriaShareTemporaryJpeg() : nil;
        if (jpegPath && [jpeg writeToFile:jpegPath atomically:YES]) {
            ExteriaOutgoing *outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
            outgoing->kind = ExteriaOutgoingPhoto;
            outgoing->path = [jpegPath copy];
            outgoing->name = [jpegPath.lastPathComponent copy];
            outgoing->width = (int32_t)image.size.width;
            outgoing->height = (int32_t)image.size.height;
            *removable = jpegPath;
            return outgoing;
        }
        /* a picture the decoder cannot read still goes out as the file it is */
    }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:path]) return nil;
    ExteriaOutgoing *outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
    outgoing->kind = ExteriaOutgoingFile;
    outgoing->path = [path copy];
    outgoing->name = [path.lastPathComponent copy];
    outgoing->mime = [ExteriaMimeOfPath(path) copy];
    outgoing->animated = gif;
    return outgoing;
}

static long long ExteriaShareRandomId(void) {
    long long random;
    do {
        random = (long long)(((uint64_t)arc4random() << 32 | arc4random()) & 0x7fffffffffffffffULL);
    } while (random == 0);
    return random;
}

static void ExteriaShareNext(NSArray *urls, NSUInteger index, ExteriaDialog *dialog, ExteriaSession *session, void (^done)(NSString *), NSString *failure) {
    if (index >= urls.count) {
        done(failure);
        [done release];
        return;
    }
    NSURL *url = [urls objectAtIndex:index];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *removable = nil;
        ExteriaOutgoing *outgoing = [ExteriaShareOutgoing(url, &removable) retain];
        NSString *spare = [removable copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            /* it outlives this block, since the send answers later */
            void (^finish)(NSString *) = [[^(NSString *error) {
                NSFileManager *files = [NSFileManager defaultManager];
                if (spare) [files removeItemAtPath:spare error:NULL];
                [files removeItemAtPath:url.path error:NULL];
                ExteriaShareNext(urls, index + 1, dialog, session, done, failure ? failure : error);
            } copy] autorelease];
            if (!outgoing) {
                NSLog(@"exteria: the shared file %@ cannot be read", url.lastPathComponent);
                finish(@"SHARE_FILE_UNREADABLE");
            } else {
                [session sendOutgoing:outgoing toDialog:dialog randomId:ExteriaShareRandomId() replyTo:0 completion:^(int32_t messageId, NSString *error) {
                    (void)messageId;
                    if (error) NSLog(@"exteria: the shared file %@ was not sent: %@", url.lastPathComponent, error);
                    finish(error);
                }];
            }
            [outgoing release];
            [spare release];
        });
        [pool drain];
    });
}

void ExteriaShareSendFiles(NSArray *urls, NSString *text, ExteriaDialog *dialog, ExteriaSession *session, void (^done)(NSString *errorName)) {
    NSArray *bounded = urls.count > SHARE_FILES_MAX ? [urls subarrayWithRange:NSMakeRange(0, SHARE_FILES_MAX)] : urls;
    void (^files)(NSString *) = [done copy];
    if (!text.length) {
        ExteriaShareNext(bounded, 0, dialog, session, files, nil);
        return;
    }
    [session sendText:text entities:nil toDialog:dialog randomId:ExteriaShareRandomId() completion:^(int32_t messageId, NSString *error) {
        (void)messageId;
        if (error) NSLog(@"exteria: the shared text was not sent: %@", error);
        ExteriaShareNext(bounded, 0, dialog, session, files, error);
    }];
}

#pragma mark extension hand-over

#define SHARE_GROUP @"group.com.sqmrak.exteria"
#define SHARE_FOLDER @"Share"
#define SHARE_MANIFEST @"manifest.plist"
#define SHARE_CLAIMED @"manifest.taken"
#define SHARE_KEEP_SECONDS (24 * 60 * 60)

static NSString *ExteriaShareRoot(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    SEL select = NSSelectorFromString(@"containerURLForSecurityApplicationGroupIdentifier:");
    if (![manager respondsToSelector:select]) return nil;
    NSURL *container = ((id (*)(id, SEL, NSString *))objc_msgSend)(manager, select, SHARE_GROUP);
    return container ? [[container path] stringByAppendingPathComponent:SHARE_FOLDER] : nil;
}

void ExteriaShareDiscard(NSString *directory) {
    if (directory.length) [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

void ExteriaShareCollectPending(void) {
    NSString *root = ExteriaShareRoot();
    if (!root) return;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *newest = nil;
    NSDate *newestDate = nil;
    for (NSString *name in [manager contentsOfDirectoryAtPath:root error:NULL]) {
        NSString *directory = [root stringByAppendingPathComponent:name];
        NSDate *made = [[manager attributesOfItemAtPath:directory error:NULL] fileModificationDate];
        BOOL waiting = [manager fileExistsAtPath:[directory stringByAppendingPathComponent:SHARE_MANIFEST]];
        if (!made || [made timeIntervalSinceNow] < -SHARE_KEEP_SECONDS) {
            ExteriaShareDiscard(directory);
            continue;
        }
        /* a folder with no waiting manifest is being filled by the extension, or is taken and still being sent; it is left alone until it is old */
        if (!waiting) continue;
        if (!newestDate || [made compare:newestDate] == NSOrderedDescending) {
            ExteriaShareDiscard(newest);
            newest = directory;
            newestDate = made;
        } else {
            ExteriaShareDiscard(directory);
        }
    }
    if (!newest) return;
    /* the rename succeeds for one caller only, and the wake url and the return to the front both come here */
    NSString *manifestPath = [newest stringByAppendingPathComponent:SHARE_MANIFEST], *claimed = [newest stringByAppendingPathComponent:SHARE_CLAIMED];
    if (![manager moveItemAtPath:manifestPath toPath:claimed error:NULL]) return;
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:claimed];
    NSMutableArray *urls = [NSMutableArray array];
    for (id name in [manifest objectForKey:@"files"]) {
        /* the names come from another process, so only a plain name inside the folder is taken */
        if ([name isKindOfClass:[NSString class]] && [name length] && [[name lastPathComponent] isEqualToString:name] && ![name hasPrefix:@"."]) {
            [urls addObject:[NSURL fileURLWithPath:[newest stringByAppendingPathComponent:name]]];
        }
    }
    NSString *text = [manifest objectForKey:@"text"];
    if (![text isKindOfClass:[NSString class]]) text = nil;
    if (!urls.count && !text.length) { ExteriaShareDiscard(newest); return; }
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:urls, @"urls", newest, @"directory", nil];
    if (text.length) [info setObject:text forKey:@"text"];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaShareFilesNotification object:nil userInfo:info];
}
