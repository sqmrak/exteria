#import "exteria_session.h"
#import "exteria_chat_folder.h"

extern NSString *const ExteriaChatFoldersDidChangeNotification;

@protocol ExteriaFolderDialogRequest <NSObject>
- (void)cancel;
@end

/* a folder the server recommends: the folder as it would be made, and the line that says what it is for */
@interface ExteriaSuggestedFolder : NSObject {
    ExteriaChatFolder *_folder;
    NSString *_info;
}
@property(nonatomic, readonly, retain) ExteriaChatFolder *folder;
@property(nonatomic, readonly, copy) NSString *info;
@end

@interface ExteriaSession (Folders)
@property(nonatomic, readonly) NSArray *chatFolders;
- (void)refreshChangedChatFolders;
- (void)loadChatFoldersWithCompletion:(ExteriaListCompletion)completion;
/* messages.getSuggestedDialogFilters: ExteriaSuggestedFolder items; the folders of the account are not among them */
- (void)loadSuggestedChatFoldersWithCompletion:(ExteriaListCompletion)completion;
- (void)saveChatFolder:(ExteriaChatFolder *)folder completion:(void (^)(NSString *errorName))completion;
- (void)setDialogs:(NSArray *)dialogs pinned:(BOOL)pinned inChatFolder:(ExteriaChatFolder *)folder completion:(void (^)(NSString *errorName))completion;
- (void)deleteChatFolder:(int32_t)folderId completion:(void (^)(NSString *errorName))completion;
- (void)orderChatFolders:(NSArray *)folders completion:(void (^)(NSString *errorName))completion;
/* the main list and archive are both inputs to custom folder rules */
- (id<ExteriaFolderDialogRequest>)loadDialogsForChatFolder:(ExteriaChatFolder *)folder completion:(ExteriaListCompletion)completion;
@end
