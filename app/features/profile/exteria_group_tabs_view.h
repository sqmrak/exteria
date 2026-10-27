#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_session_channels.h"

@class ExteriaGroupTabsView;

@protocol ExteriaGroupTabsDelegate <NSObject>
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenPerson:(ExteriaPerson *)person;
/* a file or link was tapped: the chat opens at this message */
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMessage:(ExteriaMessage *)message;
/* a photo or video of the media tab was tapped: the viewer opens on it, with the pictures and videos of the tab as its pages, not the chat. messages are in the
   order of the tab and all have a file */
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMedia:(ExteriaMessage *)message among:(NSArray *)messages;
/* the height of the content changed, so the header that holds the view has to grow */
- (void)groupTabsDidResize:(ExteriaGroupTabsView *)tabs;
@optional
/* a tab was chosen; for a user's tabs the gifts tab (selectedTab 0) has no content of its own, the screen shows the gifts */
- (void)groupTabsDidChooseTab:(ExteriaGroupTabsView *)tabs;
@end

/* the lists under a group: its members with their roles at the right, and the photos and videos, files and links
   of its chat; main thread only */
@interface ExteriaGroupTabsView : UIView

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
              forUser:(BOOL)forUser;
/* 0 is Members, or Gifts for a user */
@property (nonatomic, readonly) NSUInteger selectedTab;

@property (nonatomic, assign) id<ExteriaGroupTabsDelegate> delegate;

/* the members list starts again from the first page, after somebody was added */
- (void)reloadMembers;
- (CGFloat)heightForWidth:(CGFloat)width;

@end
