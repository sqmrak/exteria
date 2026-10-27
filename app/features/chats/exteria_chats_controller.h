#import "exteria_list_controller.h"
#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"

@class ExteriaChatsController;

@protocol ExteriaChatsControllerDelegate <NSObject>
/* the unread messages of the chats that are not muted, for the badge on the tab */
- (void)chatsController:(ExteriaChatsController *)controller didChangeUnreadTotal:(NSInteger)total;
@end

/* the chat list: search, filter pills, and a row per chat */
@interface ExteriaChatsController : ExteriaListController <UITextFieldDelegate> {
    id<ExteriaChatsControllerDelegate> _chatsDelegate;
}

@property (nonatomic, assign) id<ExteriaChatsControllerDelegate> chatsDelegate;
/* 0 lists the chats, 1 the archive; set before the view loads */
@property (nonatomic, assign) int32_t folderId;
/* what a chat opened from the list needs for its pictures and its sticker panel; set before the first tap */
@property (nonatomic, retain) ExteriaMediaCache *media;
@property (nonatomic, retain) ExteriaStickerLibrary *stickerLibrary;

@end
