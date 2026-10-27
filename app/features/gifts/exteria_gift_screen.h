#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_symbol.h"

/* "1 234 stars" in the language of the device, with the plural form its grammar wants; for text that cannot carry a picture */
NSString *ExteriaStarsText(long long stars);
/* the prefix, then the star picture and the count, drawn in one image for the labels and buttons that show a price */
UIImage *ExteriaStarsImage(NSString *prefix, long long stars, UIFont *font, UIColor *color);

/* what to tell the person about a failed gift call: the server's own names where they are known, the plain name otherwise */
NSString *ExteriaGiftErrorText(NSString *errorName);

/* an alert with one button; UIAlertView is looked up by name so the screens build on every sdk */
void ExteriaGiftAlert(NSString *title, NSString *message);

/* the frame of the gift screens: in the modern style a bar of the app's own with a back button, a title and one
   optional action, in the classic style the navigation bar the system already draws */
@interface ExteriaGiftScreen : UIViewController {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
}

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@property (nonatomic, readonly) ExteriaSession *session;
@property (nonatomic, readonly) ExteriaAvatarCache *avatars;
@property (nonatomic, readonly) ExteriaMediaCache *media;
@property (nonatomic, copy) NSString *screenTitle;
/* in the modern style the bar is see-through, with no title and no line, and the back button sits on a dark disc,
   for a screen whose picture runs to the top edge; set it before the view loads */
@property (nonatomic, assign) BOOL clearBar;

/* the action at the right end of the bar; a nil title removes it */
- (void)setActionTitle:(NSString *)title handler:(void (^)(void))handler;
/* the action as a symbol button at the right end of the bar, for a menu such as the three dots; nil handler
   removes it */
- (void)setActionSymbol:(ExteriaSymbol)symbol label:(NSString *)label handler:(void (^)(void))handler;
/* where a menu hangs from: the bottom right corner of the symbol button, in the coordinates of the view */
- (CGPoint)actionSymbolAnchor;
/* the area below the bar, in the bounds of the view */
- (CGRect)bodyFrame;
/* for subclasses: build the body into root once, and lay it out in body each time the view is laid out */
- (void)buildBodyInView:(UIView *)root;
- (void)layoutBody:(CGRect)body;
- (void)goBack;

@end
