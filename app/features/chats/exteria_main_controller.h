#import <UIKit/UIKit.h>

#import "exteria_chats_controller.h"
#import "exteria_session.h"
#import "exteria_profile_controller.h"
#import "exteria_tab_bar.h"

@class ExteriaMainController;
@class ExteriaDetailHost;

@protocol ExteriaMainControllerDelegate <NSObject>
- (void)mainController:(ExteriaMainController *)controller requestsSignOut:(void (^)(NSString *errorName))completion;
@end

/* the signed in app: one screen at a time over a tab bar */
@interface ExteriaMainController : UIViewController <ExteriaTabBarDelegate, ExteriaChatsControllerDelegate,
                                                     ExteriaProfileControllerDelegate> {
    id<ExteriaMainControllerDelegate> _delegate;
    ExteriaDetailHost *_detailHost;
}

@property (nonatomic, assign) id<ExteriaMainControllerDelegate> delegate;
/* set on a tablet, where this screen is the left pane and what it opens goes to the right one; nil on a phone */
@property (nonatomic, assign) ExteriaDetailHost *detailHost;

- (id)initWithSession:(ExteriaSession *)session;
/* YES while the chat list of the tab that is up shows the strip of the song */
- (BOOL)showsPlayerStrip;

@end
