#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_story.h"

/* the row of rings above a chat list: whoever has a story, unseen ones first, and a tap opens the viewer; the row
   has no height while nobody has a story, so a list without stories looks as it did before */
@interface ExteriaStoryStrip : NSObject

/* host presents the viewer; changed runs when the height of view changed, so the list can make room */
- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
                 host:(UIViewController *)host changed:(void (^)(void))changed;

@property (nonatomic, readonly) UIView *view;
/* zero while there is nothing to show */
@property (nonatomic, readonly) CGFloat height;

/* runs after the list of posters was replaced, so rows that show a ring can follow it */
@property (nonatomic, copy) void (^peersChanged)(void);

/* the stories of the user a chat is with, nil when there are none or the chat is not with a user; the own stories are not
   a ring on the saved messages row */
- (ExteriaStoryPeer *)peerForDialog:(ExteriaDialog *)dialog;

/* asks the server for the strip; a failure keeps what is shown, because a list with stale rings is better than none */
- (void)reload;
/* the same, unless the strip was fetched a moment ago: a chat list refreshes often and the server needs no hammering */
- (void)refresh;
/* the width the row is laid out in */
- (void)layoutInWidth:(CGFloat)width;

@end
