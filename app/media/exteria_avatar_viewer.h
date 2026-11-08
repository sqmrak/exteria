#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_emoji_label.h"
#import "exteria_media_cache.h"

/* the profile photos of a person, a group or a channel on the whole screen, newest first: the name and the day of the shown photo under the arrow that goes
   back to the profile, "n of m" under them, one page for each photo, and a strip of small pictures along the foot to jump by. While the list is on its
   way the photo the profile already has is shown, so the screen is never empty */
@interface ExteriaAvatarViewer : UIViewController <UIScrollViewDelegate> {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    NSArray *_photos;
    ExteriaMedia *_publicPhoto;
    UIScrollView *_pager;
    UILabel *_counter;
    UIButton *_back;
    UIButton *_more;
    ExteriaEmojiLabel *_titleLabel;
    UILabel *_dateLabel;
    UILabel *_toast;
    UIScrollView *_strip;
    NSMutableArray *_thumbs;
    UIActivityIndicatorView *_spinner;
    NSMutableArray *_pages;
    NSInteger _index;
    BOOL _requested;
    BOOL _statusWasHidden;
}

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

/* the photo that those who may not see the main one get, in the profile of the signed in person: the page after the last profile photo, as the wide photo of the profile has it, unless
   the list of photos holds it already; set before the screen is shown */
@property (nonatomic, retain) ExteriaMedia *publicPhoto;

@end
