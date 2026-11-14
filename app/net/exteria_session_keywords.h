#import <Foundation/Foundation.h>

#import "exteria_session.h"

@class ExteriaEmojiKeywords;

@interface ExteriaSession (EmojiKeywords)

/* asks the server for the keywords of the index's language, the full list when it holds none and the changes since its version otherwise, and takes the answer in. a difference that does not
   follow the version of the index is answered once with a request for the full list. completion runs on the main thread: nil when the index is current, or the name of the error */
- (void)updateEmojiKeywords:(ExteriaEmojiKeywords *)keywords completion:(void (^)(NSString *errorName))completion;

@end
