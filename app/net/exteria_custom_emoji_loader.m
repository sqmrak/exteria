#import "exteria_custom_emoji_loader.h"

#import "exteria_custom_emoji.h"

#define DOCUMENTS_PER_CALL 100

/* the server thumbnail stands in when the full document cannot be rendered */
static void ExteriaLoadPreview(ExteriaCustomEmojiDocument *document, ExteriaMediaCache *media, void (^done)(UIImage *image)) {
    if (!document.preview) {
        done(nil);
        return;
    }
    [media loadImageForFile:document.preview maxSide:[ExteriaCustomEmoji pictureSide] completion:done];
}

static void ExteriaLoadPicture(ExteriaCustomEmojiDocument *document, ExteriaMediaCache *media, void (^done)(UIImage *image)) {
    CGFloat side = [ExteriaCustomEmoji pictureSide];
    [media loadImageForFile:document.file maxSide:side completion:^(UIImage *image) {
        if (image) done(image);
        else ExteriaLoadPreview(document, media, done);
    }];
}

@implementation ExteriaCustomEmojiLoader

+ (void)loadPicturesOfDocuments:(NSArray *)documents media:(ExteriaMediaCache *)media picture:(void (^)(void))picture {
    void (^landed)(void) = [picture copy];
    for (ExteriaCustomEmojiDocument *document in documents) {
        long long identifier = document.documentId;
        if (![ExteriaCustomEmoji needsLoad:identifier]) continue;
        [ExteriaCustomEmoji beginLoad:identifier];
        ExteriaLoadPicture(document, media, ^(UIImage *image) {
            [ExteriaCustomEmoji finishLoad:identifier image:image];
            if (image && landed) landed();
        });
    }
    [landed release];
}

+ (void)loadDocuments:(NSArray *)documentIds session:(ExteriaSession *)session media:(ExteriaMediaCache *)media
            documents:(void (^)(NSArray *))documents picture:(void (^)(void))picture {
    void (^knownDocuments)(NSArray *) = [documents copy];
    void (^landed)(void) = [picture copy];
    NSMutableArray *wanted = [NSMutableArray array];
    for (NSNumber *key in documentIds) {
        long long document = key.longLongValue;
        if (![ExteriaCustomEmoji needsLoad:document]) continue;
        [ExteriaCustomEmoji beginLoad:document];
        [wanted addObject:key];
    }
    for (NSUInteger from = 0; from < wanted.count; from += DOCUMENTS_PER_CALL) {
        NSArray *batch = [wanted subarrayWithRange:NSMakeRange(from, MIN((NSUInteger)DOCUMENTS_PER_CALL, wanted.count - from))];
        [session loadCustomEmojiDocuments:batch completion:^(NSArray *answered, NSString *errorName) {
            NSMutableSet *known = [NSMutableSet set];
            for (ExteriaCustomEmojiDocument *document in answered) [known addObject:[NSNumber numberWithLongLong:document.documentId]];
            /* a document the server did not answer for, or a failed call, ends here and is not asked for again in this run */
            for (NSNumber *key in batch) {
                if (![known containsObject:key]) [ExteriaCustomEmoji finishLoad:key.longLongValue image:nil];
            }
            if (!answered) {
                NSLog(@"exteria: custom emoji not loaded: %@", errorName);
                return;
            }
            if (knownDocuments) knownDocuments(answered);
            for (ExteriaCustomEmojiDocument *document in answered) {
                long long identifier = document.documentId;
                ExteriaLoadPicture(document, media, ^(UIImage *image) {
                    [ExteriaCustomEmoji finishLoad:identifier image:image];
                    if (image && landed) landed();
                });
            }
        }];
    }
    [knownDocuments release];
    [landed release];
}

@end
