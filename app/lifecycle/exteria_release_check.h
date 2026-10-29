#import <UIKit/UIKit.h>

void ExteriaReleaseCheckStart(UIWindow *window);
/* the latest release, or an error; the completion runs on the main thread */
void ExteriaFetchLatestRelease(void (^completion)(NSDictionary *release, NSString *error));
