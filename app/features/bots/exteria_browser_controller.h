#import <UIKit/UIKit.h>

/* an address the in-app browser opens: http and https */
BOOL ExteriaIsWebURL(NSURL *url);
void ExteriaPresentBrowser(NSURL *url, UIViewController *host);
