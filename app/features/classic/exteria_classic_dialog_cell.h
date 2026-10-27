#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_media_cache.h"
#import "exteria_person.h"
#import "exteria_session_calllog.h"
#import "exteria_story.h"

/* a chat row in the classic style: the system cell with its own highlight, separators and swipe, and the system
   fonts; the avatar and the texts are views */
@class ExteriaDraft;

@interface ExteriaClassicDialogCell : UITableViewCell

/* where the picture of a photo or video preview comes from; without it the row shows the text alone */
@property (nonatomic, assign) ExteriaMediaCache *media;
/* runs when the arrow on the avatar of a chat that belongs to a community is tapped; set after configureWithDialog */
@property (nonatomic, copy) void (^communityHandler)(void);

/* the stories of the user the row is with: a ring round the avatar, coloured while one is unseen; nil takes it away. Set after configureWithDialog, which clears it */
- (void)setStoryPeer:(ExteriaStoryPeer *)peer;

+ (CGFloat)rowHeight;
- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars;
/* replaces the preview with what the chat is doing right now, in the accent color; nil leaves the last message */
- (void)showTypingText:(NSString *)text;
/* the unsent message of the chat stands in the place of the last one, after a red "Draft:" and with the time of the draft. Set after configureWithDialog; nil leaves
   the last message */
- (void)showDraft:(ExteriaDraft *)draft;
/* a contact: the name and when they were last seen, with no time or count on the right */
- (void)configureWithPerson:(ExteriaPerson *)person avatars:(ExteriaAvatarCache *)avatars;

/* a call of the log: the name, how it went in the line under it (red for a missed one) and when */
- (void)configureWithCall:(ExteriaCallLogEntry *)call avatars:(ExteriaAvatarCache *)avatars;

@end
