#import <UIKit/UIKit.h>

#import "exteria_gift_folders.h"

@class ExteriaGiftFolderBar;

@protocol ExteriaGiftFolderBarDelegate <NSObject>
/* nil is "All gifts" */
- (void)giftFolderBar:(ExteriaGiftFolderBar *)bar didSelectFolder:(ExteriaGiftFolder *)folder;
/* the folders came, or the bar appeared, went or changed its row of chips: the screen lays itself out again and, when selectionChanged, loads the gifts of selectedFolder */
- (void)giftFolderBarDidChange:(ExteriaGiftFolderBar *)bar selectionChanged:(BOOL)selectionChanged;
@end

/* the row of chips over the gifts of a profile: "All gifts" and a chip for each folder of the server show them;
   the bar has no height until the folders have come and there is something to show */
@interface ExteriaGiftFolderBar : UIView {
    id<ExteriaGiftFolderBarDelegate> _delegate;
}

@property (nonatomic, assign) id<ExteriaGiftFolderBarDelegate> delegate;
@property (nonatomic, readonly) ExteriaGiftFolder *selectedFolder;
@property (nonatomic, readonly) NSArray *folders;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog mine:(BOOL)mine;
/* the height the bar wants in a screen, zero while it has nothing to show */
- (CGFloat)height;
/* asks the server for the folders again; the chosen folder stays chosen while it exists */
- (void)reload;
@end
