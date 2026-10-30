#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_session.h"

/* the shared frame of the signed in list screens: a title bar, a table, and one centered status for the empty and
   failed states; the first load shows an empty screen */
@interface ExteriaListController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    ExteriaSession *_session;
    UITableView *_table;
}

@property (nonatomic, readonly) ExteriaSession *session;
@property (nonatomic, readonly) UITableView *table;
@property (nonatomic, copy) NSString *heading;
/* the height of what covers the bottom edge, such as the tab bar */
@property (nonatomic, assign) CGFloat bottomInset;
/* where the rows get profile photos from */
@property (nonatomic, retain) ExteriaAvatarCache *avatars;
/* a Back button on the left of the bar, for a screen pushed over another */
@property (nonatomic, assign) BOOL showsBack;
/* the title stands at the left margin of the content instead of the middle of the bar */
@property (nonatomic, assign) BOOL titleOnLeft;
@property (nonatomic, assign) BOOL contentUnderBar;
/* the title reads "Connecting..." with moving dots while the session has no working link */
@property (nonatomic, assign) BOOL showsConnection;
/* a button at the right end of the bar, such as the menu; the screen sizes and handles it, the list places it */
@property (nonatomic, retain) UIView *barAccessory;

- (id)initWithSession:(ExteriaSession *)session;

/* ask the session for the items and hand the answer to completion */
- (void)loadItemsWithCompletion:(ExteriaListCompletion)completion;
/* the items an earlier run kept, or nil when there are none; the default keeps nothing */
- (void)loadKeptItemsWithCompletion:(ExteriaListCompletion)completion;
/* store the new items; the table is reloaded right after */
- (void)didReceiveItems:(NSArray *)items;
- (NSInteger)itemCount;
/* shown when the load worked but there is nothing to list */
- (NSString *)emptyText;

/* starts a load unless one is running; the first load has already started by the time the view is up */
- (void)reload;
/* the same, but a load already running is dropped, because what it brings was asked for before something changed */
- (void)reloadDiscardingRunning;
- (void)reloadAfterCurrent;
- (void)reloadTable;
/* called by reloadTable before it reloads the whole table: a list whose rows have names moves, adds and removes
   them with animation and answers YES, in which case the table is not reloaded */
- (BOOL)updateTableAnimated;
/* the list is dragged and rests: a screen that handles these itself calls super first */
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;

@end
