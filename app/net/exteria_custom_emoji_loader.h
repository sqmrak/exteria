#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_session.h"

/* fetches custom emoji documents and the pictures that draw them into ExteriaCustomEmoji; a document already in
   memory, on its way or failed before is not asked for again, so a screen can call this on every rebuild */
@interface ExteriaCustomEmojiLoader : NSObject

/* documentIds are NSNumbers. documents runs once on the main thread with the answered documents, for the ordinary
   emoji each stands for */
+ (void)loadDocuments:(NSArray *)documentIds session:(ExteriaSession *)session media:(ExteriaMediaCache *)media
            documents:(void (^)(NSArray *documents))documents picture:(void (^)(void))picture;

/* the pictures of documents already in hand, such as the emoji of a set: the same rules, without asking the server about the documents */
+ (void)loadPicturesOfDocuments:(NSArray *)documents media:(ExteriaMediaCache *)media picture:(void (^)(void))picture;

@end
