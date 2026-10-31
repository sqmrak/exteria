#import <UIKit/UIKit.h>

void ExteriaReleaseCheckStart(UIWindow *window);
/* the notice of a new release with made up notes and no files to install, over the host; for the developer settings */
void ExteriaShowReleasePreview(UIView *host);
/* the latest release, or an error; the completion runs on the main thread */
void ExteriaFetchLatestRelease(void (^completion)(NSDictionary *release, NSString *error));
