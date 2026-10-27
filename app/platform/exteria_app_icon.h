#import <UIKit/UIKit.h>

/* the icon of the app on the home screen; before that it has no call for it */

typedef enum {
    /* an old system and a bundle the app cannot write: the picker is shown dimmed, with the reason */
    ExteriaAppIconUnavailable = 0,
    /* the call of ios 10.3 */
    ExteriaAppIconNative,
    /* the app rewrites its own Info.plist and runs uicache */
    ExteriaAppIconRewrite
} ExteriaAppIconMode;

ExteriaAppIconMode ExteriaAppIconCurrentMode(void);
/* the name of the alternate icon the home screen shows now, nil for the icon of the app itself */
NSString *ExteriaAlternateIconName(void);
/* name nil goes back to the icon of the app; the completion runs on the main thread with nil, or the error that
   stopped it (ios 10.3 refuses while the app is not in the foreground, for one; the rewrite fails when the plist
   cannot be written or the shell does not start) */
void ExteriaSetAlternateIcon(NSString *name, void (^completion)(NSError *error));
BOOL ExteriaAppIconCanRewrite(void);
void ExteriaRewriteAppIcon(NSString *name, void (^completion)(NSError *error));
/* the names the Info.plist lists, in the order the picker shows them */
NSArray *ExteriaAlternateIconNames(void);

/* the icon the person chose is kept in the user defaults as well, since a new install of the app brings its own
   Info.plist and with it the icon of the app */
void ExteriaAppIconRestore(void);
/* the picture the splash shows: the one of the icon chosen, or the splash picture of the app's own icon */
UIImage *ExteriaSplashIconImage(void);
/* the launch images carry the icon and the color of the screen of the theme, so the system's first picture is the
   splash the app then shows */
void ExteriaAppIconRefreshLaunchImages(void);
