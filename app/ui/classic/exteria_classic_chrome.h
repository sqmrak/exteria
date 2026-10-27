#import <UIKit/UIKit.h>

#import "exteria_symbol.h"

/* the classic style leaves the drawing to UIKit */

/* true when UIKit draws flat bars for this binary (the arm64 slice), where barTintColor colors the bar and tintColor the buttons */
BOOL ExteriaClassicIsFlatSystem(void);

void ExteriaClassicStyleNavigationBar(UINavigationBar *bar);
void ExteriaClassicStyleToolbar(UIToolbar *bar);
/* the system's search bar with its glass outline taken away and its field set into the background: a flat pill a little
   darker than the screen with a light line along its lower edge */
void ExteriaClassicStyleSearchBar(UISearchBar *bar);
/* the search shortcut keeps its glass and text aligned inside the pill on ios 5 and later */
UIView *ExteriaClassicSearchFacade(CGRect frame, NSString *placeholder);

/* the search field of the classic bars with a field of its own: the well of the pill, the glass, and one line of text that is centered on the pill by
   this view's own arithmetic and not by the system bar, whose placement of the word moves between systems */
@interface ExteriaClassicSearchInput : UIView <UITextFieldDelegate> {
    UIImageView *_well;
    UIImageView *_glass;
    UITextField *_field;
    void (^_changeHandler)(NSString *text);
}
/* called with the text after every edit and when it is cleared from outside */
@property (nonatomic, copy) void (^changeHandler)(NSString *text);
@property (nonatomic, copy) NSString *text;
- (id)initWithFrame:(CGRect)frame placeholder:(NSString *)placeholder;
@end
void ExteriaClassicStyleSegmented(UISegmentedControl *control);
void ExteriaClassicStyleTabBar(UITabBar *bar);

/* a plain or grouped table in the colors of the theme; the light theme keeps the system's own background */
void ExteriaClassicStyleTable(UITableView *table);
/* the background and text colors of a cell, for the dark theme; the light theme is left to the system */
void ExteriaClassicStyleCell(UITableViewCell *cell);
UIColor *ExteriaClassicSelectionColor(void);
/* the text inset follows the grouped rows on old iphone and ipad screens */
CGFloat ExteriaClassicGroupedTextInset(CGFloat width);
UIView *ExteriaClassicGroupedHeader(NSString *text, CGFloat width, CGFloat height, UIColor *color);
UIView *ExteriaClassicGroupedFooter(NSString *text, CGFloat width, CGFloat height);

/* a tab bar picture: the system tints only the shape, so it is drawn black on clear */
UIImage *ExteriaClassicTabImage(ExteriaSymbol symbol);
/* titles and glyphs that stay readable on the purple bar; the system draws a resting tab in grey, which vanishes on it */
void ExteriaClassicStyleTabItem(UITabBarItem *item, ExteriaSymbol symbol);

/* the round record or send button of the message bar: a glossy purple dome with its glyph, drawn whole so it needs no layers */
UIImage *ExteriaClassicRoundButtonImage(ExteriaSymbol symbol, CGFloat side, BOOL pressed);

/* the profile photo as a tab bar picture: a 30 point rounded square, drawn in its own colors */
UIImage *ExteriaClassicProfileTabImage(UIImage *photo);

/* a title of two lines for the navigation bar, such as a chat name over its status */
UIView *ExteriaClassicTitleView(NSString *title, NSString *subtitle);
/* the same with a status that colors itself: kind is an ExteriaStatusKind (0 quiet, 1 on line, 2 typing, which
   also runs three dots after the words); the bar is purple, so the colors are light ones */
UIView *ExteriaClassicTitleViewWithStatus(NSString *title, NSString *subtitle, int kind);

/* the small round count on a row, in the system's blue or gray */
UILabel *ExteriaClassicBadge(NSString *text, BOOL muted);

/* the colors of a glossy button of the classic style */
typedef enum {
    ExteriaClassicGlossGreen,
    ExteriaClassicGlossRed,
    /* the violet grey of a button at rest on the purple bar */
    ExteriaClassicGlossSlate,
    ExteriaClassicGlossAmber
} ExteriaClassicGloss;

/* a stretchable glossy button, rounded and lit from above with a pale upper half, in a color; pressed is the
   darker one */
UIImage *ExteriaClassicGlossButtonImage(ExteriaClassicGloss color, BOOL pressed);

/* a plate in the card color of the theme, with a lit rim and a thin outline */
UIImage *ExteriaClassicPlateImage(void);
