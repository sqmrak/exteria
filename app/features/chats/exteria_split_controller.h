#import <UIKit/UIKit.h>

@class ExteriaMainController;
@class ExteriaDetailNavigationController;

/* the ipad shows the lists on the left and what a tap opens on the right */
@interface ExteriaDetailHost : NSObject {
    ExteriaDetailNavigationController *_detail;
}

@property (nonatomic, assign) ExteriaDetailNavigationController *detail;

/* NO for the screens that are lists of the left pane: the search and an archive folder of the chat list */
- (BOOL)opensInDetail:(UIViewController *)screen;
/* makes the screen the only one of the right pane; a screen already there fades out under it, the first one slides in */
- (void)showInDetail:(UIViewController *)screen animated:(BOOL)animated;
/* back to the empty pane with its hint */
- (void)resetDetail;
/* after a style change, rebuild the restorable pages of the right pane */
- (void)styleDidChange:(BOOL)involvesClassic;
/* whether the right pane has no page open, so a change of colors cannot leave one in the old ones */
- (BOOL)detailIsEmpty;

@end

/* a navigation controller of the left pane (the master one and the tabs of the classic style): a push that is a page for the right pane goes there */
@interface ExteriaSplitNavigationController : UINavigationController {
    ExteriaDetailHost *_detailHost;
}

@property (nonatomic, assign) ExteriaDetailHost *detailHost;

@end

/* the right pane: the last page cannot be popped, it gives way to the empty pane */
@interface ExteriaDetailNavigationController : UINavigationController {
    ExteriaDetailHost *_detailHost;
}

@property (nonatomic, assign) ExteriaDetailHost *detailHost;

@end

/* YES for the page that stands alone in the right pane, which has no left pane to go back to, so its back button stays away */
BOOL ExteriaIsDetailRoot(UIViewController *screen);

@interface ExteriaSplitController : UIViewController {
    ExteriaDetailHost *_host;
}

- (id)initWithMain:(ExteriaMainController *)main;

/* the main screen may build itself again for a night or day change: not while a page of the right pane is open, since that page would keep the old colors */
- (BOOL)canRebuildForTheme;

@end
