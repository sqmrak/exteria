#import "exteria_list_controller.h"
#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"

@class ExteriaChatsController;

/* the unread messages of the main list, those of muted chats left out: the count a chat shows by its way back; posted on the main thread when it changes */
extern NSString *const ExteriaUnreadTotalDidChangeNotification;
NSInteger ExteriaUnreadTotal(void);
/* the rows of the main chat list as the screen last loaded it, nil before the first load; what the icon badge is counted from when the server cannot be asked */
NSArray *ExteriaMainDialogsSnapshot(void);
void ExteriaSetMainDialogsSnapshot(NSArray *dialogs);

@protocol ExteriaChatsControllerDelegate <NSObject>
/* the unread messages of the chats that are not muted, for the badge on the tab */
- (void)chatsController:(ExteriaChatsController *)controller didChangeUnreadTotal:(NSInteger)total;
@optional
/* YES while a chat in the right pane of a tablet carries the strip of the song, so the list does not show a second one */
- (BOOL)chatsControllerYieldsPlayer:(ExteriaChatsController *)controller;
@end

/* the chat list: search, filter pills, and a row per chat */
@interface ExteriaChatsController : ExteriaListController <UITextFieldDelegate> {
    id<ExteriaChatsControllerDelegate> _chatsDelegate;
}

@property (nonatomic, assign) id<ExteriaChatsControllerDelegate> chatsDelegate;
/* 0 lists the chats, 1 the archive; set before the view loads */
@property (nonatomic, assign) int32_t folderId;
/* whether the strip of the song that plays is up in this list */
@property (nonatomic, readonly) BOOL playerStripShowing;
/* the list goes back to its first row, as the chats tab does when it is pressed while it is shown */
- (void)scrollToTopAnimated;
/* what a chat opened from the list needs for its pictures and its sticker panel; set before the first tap */
@property (nonatomic, retain) ExteriaMediaCache *media;
@property (nonatomic, retain) ExteriaStickerLibrary *stickerLibrary;

@end
