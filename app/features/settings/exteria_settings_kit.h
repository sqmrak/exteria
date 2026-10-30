#import <UIKit/UIKit.h>

#import "exteria_symbol.h"

#include "exteria_sessions.h"

/* the shared frame of the settings screens of the modern theme, ported: a title bar with a back arrow, and under
   it cards of rows on the wave background */

/* the colors of the icon circles, IconBackgroundColors: each is a top and a bottom color, from which the tinted
   circle is made */
typedef enum {
    ExteriaSettingsToneBlue,
    ExteriaSettingsToneBlueDeep,
    ExteriaSettingsToneBlueLight,
    ExteriaSettingsToneOrange,
    ExteriaSettingsToneOrangeBright,
    ExteriaSettingsToneOrangeDeep,
    ExteriaSettingsToneGreen,
    ExteriaSettingsToneRed,
    ExteriaSettingsToneCyan,
    ExteriaSettingsTonePurple,
    ExteriaSettingsToneGray
} ExteriaSettingsTone;

/* the glyph in a circle of the tone, in the tonal style M3 list: a pale disc with a deep glyph, as the dark theme
   and the light theme each want it */
UIImage *ExteriaSettingsTileImage(ExteriaSymbol symbol, ExteriaSettingsTone tone, CGFloat side);
/* the tile of the Exteria row: the mark of the app in white on a dark red disc draw theirs */
UIImage *ExteriaSettingsMarkTile(CGFloat side);

/* the circle that stands for a session: the colors and the glyph SessionCell, white on a gradient */
UIImage *ExteriaDeviceIconImage(exteria_session_kind kind, CGFloat side);
/* the flat color of the same circle session sheet paints it behind its animation */
UIColor *ExteriaDeviceColor(exteria_session_kind kind);
/* the name of the bundled animation of the kind, nil for a kind that has none (it is drawn as the picture) */
NSString *ExteriaDeviceAnimationName(exteria_session_kind kind);

@interface ExteriaSettingsRow : NSObject {
    ExteriaSymbol _symbol;
    BOOL _hasSymbol;
    ExteriaSettingsTone _tone;
    NSString *_title;
    NSString *_subtitle;
    NSString *_value;
    BOOL _valueIsEmoji;
    long long _valueEmojiDocument;
    NSString *_line3;
    UIImage *_picture;
    UIImage *_tileImage;
    UIImage *_trailingImage;
    BOOL _trailingImageUnclipped;
    BOOL _bold;
    BOOL _destructive;
    BOOL _hasSwitch;
    BOOL _on;
    BOOL _accentLine3;
    BOOL _checked;
    BOOL _disabled;
    BOOL _hasLevel;
    NSDictionary *(^_describe)(int percent);
    NSString *_leftCaption;
    NSString *_rightCaption;
    BOOL _hasSlider;
    float _sliderValue;
    float _sliderMinimum;
    float _sliderMaximum;
    NSString *_sliderFormat;
    void (^_tap)(void);
    void (^_toggle)(BOOL on);
    void (^_slide)(float value);
    UIView *_customView;
    CGFloat (^_customHeight)(CGFloat width);
}
/* an icon row that opens something: the title, a line under it, and a value on the right (any may be nil) */
+ (ExteriaSettingsRow *)rowWithSymbol:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone title:(NSString *)title subtitle:(NSString *)subtitle
                                value:(NSString *)value tap:(void (^)(void))tap;
/* an icon row whose tile is a picture of its own, such as the logo of the app, shown round at the size of the tiles */
+ (ExteriaSettingsRow *)rowWithTileImage:(UIImage *)image title:(NSString *)title subtitle:(NSString *)subtitle tap:(void (^)(void))tap;
/* a row with no icon: the title, an optional value in the accent color on the right */
+ (ExteriaSettingsRow *)rowWithTitle:(NSString *)title value:(NSString *)value tap:(void (^)(void))tap;
/* a row with no icon: the title, a line under it and a value in the accent color on the right (any of the last two may be nil) */
+ (ExteriaSettingsRow *)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle value:(NSString *)value tap:(void (^)(void))tap;
/* a row of a list of choices: the title, an optional line under it, and a check mark on the right when it is the chosen one */
+ (ExteriaSettingsRow *)checkRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle checked:(BOOL)checked tap:(void (^)(void))tap;
/* a title with its value on the right and a slider under them */
+ (ExteriaSettingsRow *)sliderRowWithTitle:(NSString *)title format:(NSString *)format value:(float)value minimum:(float)minimum maximum:(float)maximum
                                    change:(void (^)(float value))change;
/* the same with the icon in its tinted circle in front, as the rows that open something have */
+ (ExteriaSettingsRow *)switchRowWithSymbol:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone title:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on
                                     toggle:(void (^)(BOOL on))toggle;
/* a percentage slider with a caption over it, the way the power saver level is set */
+ (ExteriaSettingsRow *)levelRowWithTitle:(NSString *)title leftCaption:(NSString *)left rightCaption:(NSString *)right percent:(int)percent
                                  describe:(NSDictionary *(^)(int percent))describe change:(void (^)(int percent))change;
/* a title and a line under it with a switch on the right */
+ (ExteriaSettingsRow *)switchRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on toggle:(void (^)(BOOL on))toggle;
/* a glyph in the accent color (red when destructive) in front of a text in the same color */
+ (ExteriaSettingsRow *)actionRowWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title destructive:(BOOL)destructive tap:(void (^)(void))tap;
/* a row that is a view of the owner's, such as the preview of a chat under a slider */
+ (ExteriaSettingsRow *)viewRowWithView:(UIView *)view height:(CGFloat (^)(CGFloat width))height;
@property (nonatomic, readonly, retain) UIView *customView;
@property (nonatomic, readonly, copy) CGFloat (^customHeight)(CGFloat width);
/* the row of a session: its picture, the name in bold, then two lines, the last in the accent color when accent is set */
+ (ExteriaSettingsRow *)sessionRowWithPicture:(UIImage *)picture title:(NSString *)title line2:(NSString *)line2 line3:(NSString *)line3 accentLine3:(BOOL)accent
                                          tap:(void (^)(void))tap;

@property (nonatomic, readonly) BOOL hasSymbol;
@property (nonatomic, readonly) ExteriaSymbol symbol;
@property (nonatomic, readonly) ExteriaSettingsTone tone;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *subtitle;
@property (nonatomic, readonly, copy) NSString *value;
@property (nonatomic, assign) BOOL valueIsEmoji;
@property (nonatomic, assign) long long valueEmojiDocument;
@property (nonatomic, readonly, copy) NSString *line3;
@property (nonatomic, readonly, retain) UIImage *picture;
@property (nonatomic, readonly, retain) UIImage *tileImage;
/* a small picture at the right end of the row, such as the icon of an app; set after the row is made */
@property (nonatomic, retain) UIImage *trailingImage;
@property (nonatomic, assign) BOOL trailingImageUnclipped;
@property (nonatomic, readonly) BOOL bold;
@property (nonatomic, readonly) BOOL destructive;
@property (nonatomic, readonly) BOOL hasSwitch;
@property (nonatomic, assign) BOOL on;
@property (nonatomic, readonly) BOOL accentLine3;
@property (nonatomic, readonly) BOOL checked;
/* drawn dimmed, its switch cannot be moved; a tap still reaches tap, which is where the owner says why */
@property (nonatomic, assign) BOOL disabled;
@property (nonatomic, readonly) BOOL hasLevel;
@property (nonatomic, readonly, copy) NSString *leftCaption;
@property (nonatomic, readonly, copy) NSString *rightCaption;
@property (nonatomic, readonly, copy) NSDictionary *(^describe)(int percent);
@property (nonatomic, readonly) BOOL hasSlider;
/* where the slider stands; the cell writes it as the slider moves */
@property (nonatomic, assign) float sliderValue;
@property (nonatomic, readonly) float sliderMinimum;
@property (nonatomic, readonly) float sliderMaximum;
@property (nonatomic, readonly, copy) NSString *sliderFormat;
@property (nonatomic, copy) void (^tap)(void);
@property (nonatomic, readonly, copy) void (^toggle)(BOOL on);
@property (nonatomic, readonly, copy) void (^slide)(float value);
/* the row is a session: its height has room for three lines */
@property (nonatomic, readonly) BOOL isSession;
@end

@interface ExteriaSettingsSection : NSObject {
    NSString *_header;
    NSString *_footer;
    NSArray *_rows;
    BOOL _centerFooter;
}
+ (ExteriaSettingsSection *)sectionWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray *)rows;
@property (nonatomic, readonly, copy) NSString *header;
@property (nonatomic, copy) NSString *footer;
@property (nonatomic, readonly, retain) NSArray *rows;
/* the footer is a line in the middle, such as the version at the end of the list, not a note under the cards */
@property (nonatomic, assign) BOOL centerFooter;
@end

/* the screen: a bar with a back arrow and the title, and the sections in a table */
/* a page that is still worth showing after the theme changed in a way that makes every screen again (the modern
   and the classic style swap the whole structure, and the classic tabs are built anew for every new hue) */
@protocol ExteriaThemeRestorable <NSObject>
- (UIViewController *)controllerAfterThemeChange;
@end

@interface ExteriaSettingsPageController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, retain) NSArray *sections;
/* shown above the first section and scrolling with it; set before the view loads or call reloadSettings after */
@property (nonatomic, retain) UIView *headerView;
@property (nonatomic, readonly) UITableView *table;
/* a root screen has no back arrow, and sits over a tab bar of this height */
@property (nonatomic, assign) BOOL showsBack;
@property (nonatomic, assign) CGFloat bottomInset;
/* 0 to 1: how much of the title in the bar shows */
@property (nonatomic, assign) CGFloat titleAlpha;
/* 0 to 1: how much of the background of the bar shows; a root screen with a big header fades it in as the header scrolls away under the bar */
@property (nonatomic, assign) CGFloat barFill;
/* the table starts under the status bar and scrolls up behind the bar, which then carries a background that fades in with the title; for a root screen whose
   header is taller than the bar */
@property (nonatomic, assign) BOOL contentUnderBar;
/* the page makes its bar and background again when the colors of the theme change, and then calls this */
- (void)themeDidChange;
/* the middle of the row that was tapped last, in window coordinates, for a change that spreads over the screen from where the finger was */
@property (nonatomic, readonly) CGPoint selectPoint;
/* views at the right end of the bar, laid out from the right edge */
@property (nonatomic, retain) NSArray *barViews;

/* a magnifier in the bar, left of barViews, opens a field over the title */
@property (nonatomic, assign) BOOL searchable;
/* puts the cursor in the search of the page: the modern bar opens its field, and the classic table comes to its search bar and the keyboard opens there */
- (void)focusSearch;
@property (nonatomic, readonly) BOOL searching;
/* for a subclass: the sections that answer the query, which is trimmed and never nil; nil means the sections of the screen as they are */
- (NSArray *)sectionsForSearchQuery:(NSString *)query;
/* for a subclass: the search opened or closed; searching tells which */
- (void)searchDidChangeState;

/* asks sectionsForSearchQuery: again for the text in the field, after the rows it made went stale */
- (void)reloadSearchResults;
/* closes the search field and shows the sections again (the modern style; the classic search bar keeps its own text) */
- (void)endSearch;

/* a screen that changes a section while the finger is on a control in another (the power saver slider and the
   switches under it) swaps only that section's rows */
- (void)replaceSectionAtIndex:(NSUInteger)index withSection:(ExteriaSettingsSection *)section;
/* the text under a section, changed in place: a screen that shows it while a slider is dragged cannot have the slider's row made again */
- (void)setFooter:(NSString *)footer forSectionAtIndex:(NSUInteger)index;

- (void)reloadSettings;
/* the heights of the rows are asked again, and the rows stay as they are */
- (void)updateRowHeights;
- (void)goBack;

@end

/* a choice among a few texts: the modern sheet that rises from the bottom, or the system's action sheet in the
   classic style; the handler gets the index of the text that was picked, never of the cancel */
void ExteriaSettingsChoose(UIViewController *host, NSString *title, NSArray *options, void (^handler)(NSUInteger index));
