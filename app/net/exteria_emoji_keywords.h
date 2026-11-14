#import <Foundation/Foundation.h>

#import "exteria_keywords.h"

/* the words that find an emoji for one language, kept in memory and in a file of the caches folder; the server's list is asked for once a launch and brings only what changed.
   the index is touched by the worker that applies an answer and by the screen that searches, so every call takes the lock */
@interface ExteriaEmojiKeywords : NSObject

/* the index of a language, made on the first ask and loaded from its file; the same object every time */
+ (ExteriaEmojiKeywords *)keywordsForLanguage:(NSString *)language;
/* the languages a typed word is looked up in: the interface language, then English when that is another */
+ (NSArray *)searchLanguages;

@property (nonatomic, readonly) NSString *language;
/* the version of the server's list the index holds; 0 for none */
@property (nonatomic, readonly) int32_t version;
/* whether an update of this launch has been asked for already */
@property (nonatomic, assign) BOOL updateRequested;

/* the emoji of a query, best first, as strings that go into a message */
- (NSArray *)emojiForQuery:(NSString *)query;
/* worker or main: takes an emojiKeywordsDifference in and writes the file; EXTERIA_E_STATE means the caller asks for the full list */
- (exteria_status)applyAnswer:(const exteria_tl_value *)answer;

@end
