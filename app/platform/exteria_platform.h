#import <UIKit/UIKit.h>

BOOL ExteriaIsPad(void);
CGFloat ExteriaScreenScale(void);

/* the safe area of a view that is in a window: the notch, the home indicator and the bars; zero before ios 11, and
   zero for a view not yet in a window */
UIEdgeInsets ExteriaSafeInsets(UIView *view);

/* the app keeps the home indicator and the bars in the content inset of its scroll views itself; a no-op before
   ios 11 */
void ExteriaScrollViewOwnsInsets(UIScrollView *scroll);
/* from ios 11 a table guesses the height of rows it has not measured, so the end of a list of rows of every height is not where contentSize says */
void ExteriaTableUsesExactHeights(UITableView *table);

/* zero on ios 5 and 6, where the view already excludes the status bar */
UIEdgeInsets ExteriaLayoutInsets(UIViewController *controller);

/* the widest a column of content gets on a tablet, by kind of screen: cards of settings and profiles, rows of a
   list, the messages of a chat */
#define EXTERIA_COLUMN_PAGE 640.0
#define EXTERIA_COLUMN_LIST 720.0
#define EXTERIA_COLUMN_CHAT 820.0

/* the strip of a view that content stands in, as a rect of the view's height; a phone never gets the limit, its
   landscape screen is the whole row */
CGRect ExteriaContentColumn(CGSize size, UIEdgeInsets insets, CGFloat maxWidth);

/* the user defaults are written to disk once for the steps of a slider that follow each other, half a second after
   the last, and at once when the app goes to the background or ends */
void ExteriaDefaultsSaveSoon(void);

BOOL ExteriaReduceMotionEnabled(void);

/* nil before ios 8: a nil notification name would subscribe to every notification */
NSString *ExteriaReduceMotionChangedNotification(void);

/* every screen rotates the same way: the phone skips upside down, the tablet allows all four */
BOOL ExteriaAllowsOrientation(UIInterfaceOrientation orientation);
NSUInteger ExteriaOrientationMask(void);

/* the view a card or a bar over the whole app is added to; before ios 8 a view added to the window itself keeps
   the orientation of the device, and on an ipad in landscape it would lie on its side */
UIView *ExteriaOverlayHost(void);
/* the height of the status bar in the orientation the app is in, which the frame of the bar gives as its short side */
CGFloat ExteriaStatusBarHeight(void);
