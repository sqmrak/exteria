#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_media_cache.h"
#import "exteria_story.h"

/* what the swipe from the right edge of a row does; None disables the swipe */
typedef enum {
    ExteriaDialogActionNone,
    ExteriaDialogActionArchive,
    ExteriaDialogActionUnarchive,
    ExteriaDialogActionHide,
    /* the archive entry's "pin on top", which brings the hidden archive back to the top of the list */
    ExteriaDialogActionPin,
    /* the swipes the chat settings offer for an ordinary chat, besides the archive */
    ExteriaDialogActionPinChat,
    ExteriaDialogActionUnpinChat,
    ExteriaDialogActionMarkRead,
    ExteriaDialogActionMarkUnread,
    ExteriaDialogActionMute,
    ExteriaDialogActionUnmute,
    ExteriaDialogActionDeleteChat
} ExteriaDialogAction;

@class ExteriaDialogCell;

/* what a swipe to the left does on a chat of the main list or of the archive, by the choice of the chat settings:
   the archive until another is chosen */
ExteriaDialogAction ExteriaDialogSwipeAction(ExteriaDialog *dialog, NSInteger folderId);
/* the word on the button of an action */
NSString *ExteriaDialogActionText(ExteriaDialogAction action);

@protocol ExteriaDialogCellDelegate <NSObject>
/* a swipe started, so the row that was open can close */
- (void)dialogCellDidBeginSwipe:(ExteriaDialogCell *)cell;
/* the swipe went all the way or the opened button was tapped; the cell stays slid out until it is reconfigured */
- (void)dialogCell:(ExteriaDialogCell *)cell didTriggerAction:(ExteriaDialogAction)action;
@end

/* one row of the chat list; the height is fixed so the table never measures */
@class ExteriaDraft;

@interface ExteriaDialogCell : UITableViewCell

@property (nonatomic, assign) id<ExteriaDialogCellDelegate> swipeDelegate;
@property (nonatomic, readonly) BOOL swipeOpen;
/* where the picture of a photo or video preview comes from; without it the row shows the text alone */
@property (nonatomic, assign) ExteriaMediaCache *media;
/* runs when the arrow on the avatar of a chat that belongs to a community is tapped; set after configureWithDialog, cleared by the next configure */
@property (nonatomic, copy) void (^communityHandler)(void);

/* the stories of the user the row is with: a ring round the avatar, coloured while one is unseen; nil takes it away. Set after configureWithDialog, which clears it */
- (void)setStoryPeer:(ExteriaStoryPeer *)peer;

+ (CGFloat)rowHeight;
- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars action:(ExteriaDialogAction)action;
/* replaces the preview with what the chat is doing right now, in the accent color; nil puts the last message back */
- (void)showTypingText:(NSString *)text;
/* the unsent message of the chat stands in the place of the last one, after a red "Draft:" and with the time of the draft. Set after configureWithDialog,
   which puts the last message back; nil leaves it */
- (void)showDraft:(ExteriaDraft *)draft;
- (void)closeSwipeAnimated:(BOOL)animated;
/* changes what the swipe does, for a row that stays on screen after its action ran */
- (void)setSwipeAction:(ExteriaDialogAction)action;
- (void)yieldSwipeToRecognizers:(NSArray *)recognizers;

@end
