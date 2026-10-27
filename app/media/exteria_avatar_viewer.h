#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_media_cache.h"

/* the profile photos of a person, a group or a channel on the whole screen, one page for each, the newest first;
   while the list is on its way the photo the profile already has is shown, so the screen is never empty */
@interface ExteriaAvatarViewer : UIViewController <UIScrollViewDelegate> {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    NSArray *_photos;
    UIScrollView *_pager;
    UILabel *_counter;
    UIButton *_close;
    UIActivityIndicatorView *_spinner;
    NSMutableArray *_pages;
    NSInteger _index;
    BOOL _requested;
    BOOL _statusWasHidden;
}

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@end
