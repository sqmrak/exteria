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
/* the height the system gives a tab bar on this os, so a bar standing beside it can match: the one of the tab controller on screen once it has laid out, else a bar measured
   alone */
CGFloat ExteriaClassicTabBarHeight(void);
/* the height of the real tab bar, which the one measured alone can miss by a point or two on a tablet, leaving the input bar of the chat beside it a step off */
void ExteriaClassicNoteTabBarHeight(CGFloat height);

/* a plain or grouped table in the colors of the theme; the light theme keeps the system's own background */
void ExteriaClassicStyleTable(UITableView *table);
/* the separator style the lists of the classic style use, by the choice of the customization: a thin line, an etched double line or none; a list with no rows has none */
UITableViewCellSeparatorStyle ExteriaClassicListSeparatorStyle(BOOL hasRows);
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
UIImage *ExteriaClassicRedRoundButtonImage(ExteriaSymbol symbol, CGFloat side, BOOL pressed);

/* the face in a chrome rim, as the logo of the QR code wears it: a brushed metal gradient outside, a darker bevel before the face, an inner shadow and a gloss over the
   upper half; side is in points, the face is cropped round and may be nil */
UIImage *ExteriaClassicMetalDisc(UIImage *face, CGFloat side);

/* the profile photo as a tab bar picture: a 30 point rounded square, drawn in its own colors */
UIImage *ExteriaClassicProfileTabImage(UIImage *photo);

/* a title of two lines for the navigation bar, such as a chat name over its status */
UIView *ExteriaClassicTitleView(NSString *title, NSString *subtitle);
/* the same with a status that colors itself: kind is an ExteriaStatusKind (0 quiet, 1 on line, 2 typing, which
   also runs three dots after the words); the bar is purple, so the colors are light ones */
UIView *ExteriaClassicTitleViewWithStatus(NSString *title, NSString *subtitle, int kind);
/* the same with the width of the view given, for a bar whose buttons take more of a phone's width than the 190 points the default leaves them */
UIView *ExteriaClassicTitleViewWithStatusWidth(NSString *title, NSString *subtitle, int kind, CGFloat width);
/* a count in the glossy badge of the old home screen: a white ring, the accent lit from above, a gloss on the upper half and a shadow under it */
UIView *ExteriaClassicCounterBadge(NSString *text);

/* the small round count on a row, in the accent color or gray */
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
UIImage *ExteriaClassicBarButtonImage(BOOL pressed);

/* a plate in the card color of the theme, with a lit rim and a thin outline */
UIImage *ExteriaClassicPlateImage(void);

/* the menu plate of the classic style: a charcoal plate in the dark tone and a pale glossy one in the white tone, each with a lit edge
   and a soft shadow; the layer is named "plate" and sized to the bounds of the view */
void ExteriaClassicApplyMenuPlate(UIView *view, CGFloat radius);
/* sizes the plate of a view that got one from ExteriaClassicApplyMenuPlate to the view's bounds, bleed points taller at the bottom, and gives the shadow a path: without one the shadow of a
   card is worked out from its content at every frame of a scroll */
void ExteriaClassicFitPlate(UIView *view, CGFloat bleed);
/* the colors of the rows on that plate */
UIColor *ExteriaClassicMenuTextColor(void);
UIColor *ExteriaClassicMenuRedColor(void);
UIColor *ExteriaClassicMenuPressColor(void);
/* a bold row title with the stamped shadow of the old menus */
void ExteriaClassicStyleMenuLabel(UILabel *label, CGFloat size);

/* the glossy purple of the navigation bar, stretched to fill a strip such as the mini player or the selection bar */
UIImageView *ExteriaClassicStripBackdrop(void);
/* the fill of the text boxes of the classic bars: the white or dark grey of the screen with a fifth of the accent mixed in, opaque since emoji are drawn over it */
UIColor *ExteriaClassicInputFill(void);
/* the plain ground of the strips that stand over a chat, the pinned message and the player: dark grey with a little of the accent on the dark theme and white with a trace of it on the light one, so the wallpaper never shows
   through them; the ink is for their text and glyphs and the edge for the line under them */
UIColor *ExteriaClassicStripGround(void);
/* a key in the color of the ground it stands on, for a profile that has a color of its own: a soft gradient, a thin darker outline, and no gloss, streak or lit line over it */
UIImage *ExteriaClassicGroundKeyImage(UIColor *ground, BOOL pressed);
/* a glossy key or pill in any color, as the blue microphone key of the old messaging apps: the color lit from above and darker below, a hard-edged gloss over the upper half, a streak,
   a lit line under the top edge and a dark outline; it stretches from its middle, and radius is the corner */
UIImage *ExteriaClassicTintedGlossImage(UIColor *base, CGFloat radius, BOOL pressed);
UIColor *ExteriaClassicStripInk(void);
UIColor *ExteriaClassicStripEdge(void);
