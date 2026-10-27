#import <Foundation/Foundation.h>

#include "exteria_bookmarks.h"

#import "exteria_dialog.h"
#import "exteria_session.h"

/* posted on the main thread after a bookmark was added or removed */
extern NSString *const ExteriaBookmarksDidChangeNotification;

/* one bookmarked message, as the list shows it */
@interface ExteriaBookmark : NSObject {
    exteria_bookmark _row;
}
- (id)initWithRow:(const exteria_bookmark *)row;
@property (nonatomic, readonly) int32_t messageId;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) int32_t added;
/* the name of the chat, and the start of the message or the word for its media */
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *text;
/* the chat the message is in, built from what was kept, with no picture */
- (ExteriaDialog *)dialog;
@end

/* the messages the person marked, kept in a file of the account's directory, newest first; a file of another
   account is not read, so signing in as somebody else starts an empty list */
@interface ExteriaBookmarks : NSObject

/* one list per account directory, loaded when first asked for */
+ (ExteriaBookmarks *)bookmarksForSession:(ExteriaSession *)session;

@property (nonatomic, readonly) NSArray *entries;
- (BOOL)containsMessageId:(int32_t)messageId inDialog:(ExteriaDialog *)dialog;
/* text is the line to recognise the message by */
- (BOOL)addMessageId:(int32_t)messageId date:(int32_t)date text:(NSString *)text inDialog:(ExteriaDialog *)dialog;
- (BOOL)removeMessageId:(int32_t)messageId inDialog:(ExteriaDialog *)dialog;
- (BOOL)removeEntry:(ExteriaBookmark *)entry;

@end
