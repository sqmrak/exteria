#import <UIKit/UIKit.h>

/* middle of the welcome gradient, for the window behind it during rotation */
UIColor *ExteriaColorBackdrop(void);
/* the signed in screens come in a light and a dark palette; the screens before the login are always light,
   so the app delegate picks the palette each time it builds a root screen and colors are read at build time */
extern NSString *const ExteriaThemeDidChangeNotification;
/* the optional key of its userInfo: an NSValue with the point in window coordinates the change of colors spreads from, which the screens that ask for a change give
   as the spot that was touched */
extern NSString *const ExteriaThemeOriginKey;
BOOL ExteriaThemeStoredClassic(void);
void ExteriaThemeStoreClassic(BOOL classic);
BOOL ExteriaThemeIsClassic(void);
BOOL ExteriaThemeStoredDark(void);
void ExteriaThemeStoreDark(BOOL dark);
BOOL ExteriaThemeIsDark(void);
void ExteriaThemeApply(BOOL dark);
void ExteriaThemeApplyStored(void);

/* the wallpaper of the chat gives the whole modern palette its hue */
BOOL ExteriaThemeStoredTint(float *hue);
void ExteriaThemeStoreTint(BOOL on, float hue);
/* a color of the palette of the app, or any other color built from fixed numbers, turned the same way; other colors than RGB come back as they are */
UIColor *ExteriaThemeTinted(UIColor *color);
/* a color turned by this many degrees of hue, for a palette with a seed hue of its own (the Shiro screens): the
   turn it needs is the hue of the accent now less the hue of its seed */
UIColor *ExteriaThemeRotated(UIColor *color, CGFloat degrees);
BOOL ExteriaThemeAccentHue(CGFloat *degrees);
/* hue in degrees, saturation and value from 0 to 1 */
void ExteriaRGBToHSV(CGFloat red, CGFloat green, CGFloat blue, CGFloat *hue, CGFloat *saturation, CGFloat *value);

/* the screen, the fields and idle chips on it, cards and the tab bar, and the line between rows */
UIColor *ExteriaColorScreen(void);
UIColor *ExteriaColorField(void);
UIColor *ExteriaColorCard(void);
UIColor *ExteriaColorBar(void);
UIColor *ExteriaColorHairline(void);
UIColor *ExteriaColorAccent(void);
/* a color given as 0xRRGGBB, opaque */
UIColor *ExteriaColorOfRGB(uint32_t rgb);
UIColor *ExteriaColorAccentDark(void);
UIColor *ExteriaColorTitle(void);
UIColor *ExteriaColorMessage(void);
UIColor *ExteriaColorDotOff(void);
/* secondary text on the lilac screens, and the quieter shade of it for muted chats and idle tabs */
UIColor *ExteriaColorSecondary(void);
UIColor *ExteriaColorMuted(void);
UIColor *ExteriaColorBadgeRed(void);
/* the pale paper behind a QR code, white turned toward the hue of the chat color; dark modules still read on it */
UIColor *ExteriaColorQrPaper(void);
/* chat bubbles: ours in the accent family, theirs on the card color, and the capsule behind dates and times */
UIColor *ExteriaColorChatBackground(void);
UIColor *ExteriaColorBubbleText(BOOL outgoing);
UIColor *ExteriaColorBubbleLink(BOOL outgoing);
UIColor *ExteriaColorBubbleMeta(BOOL outgoing);
/* the classic bubble as the old Messages drew it: a vertical gradient from top to bottom and an outline, none of them
   transparent so the wallpaper never shows through */
void ExteriaClassicBubbleColors(BOOL outgoing, UIColor **top, UIColor **bottom, UIColor **outline);
/* the colors a theme gives a chat, for the preview of a theme that is not on screen; the style and the tone are
   switched for the moment of the call and put back, so the colors come from the same code that paints the real
   chat */
void ExteriaThemePreviewColors(BOOL classic, BOOL dark, UIColor **incoming, UIColor **outgoing, UIColor **incomingText, UIColor **outgoingText);
UIColor *ExteriaColorBubbleOut(void);
UIColor *ExteriaColorBubbleIn(void);
UIColor *ExteriaColorBubbleCapsule(void);

/* san Francisco on ios 9 and later; before that the bundled Inter, which sets the same way */
UIFont *ExteriaFontRegular(CGFloat size);
UIFont *ExteriaFontMedium(CGFloat size);
UIFont *ExteriaFontSemibold(CGFloat size);
UIFont *ExteriaFontBold(CGFloat size);

/* the ios 5 UITextAlignment values and the ios 6 NSTextAlignment ones are the same numbers on iOS */
#define ExteriaTextAlignmentCenter 1
#define ExteriaTextAlignmentLeft 0
#define ExteriaTextAlignmentRight 2

/* the color that is share (0 to 1) of the way from base to tint, solid whatever the alphas of the two; the plate of a quote is made of the bubble and the
   color of its author this way, so nothing behind the bubble shows through it */
UIColor *ExteriaMixedColor(UIColor *base, UIColor *tint, CGFloat share);
