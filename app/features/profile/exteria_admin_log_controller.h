#import "exteria_gift_screen.h"
#import "exteria_session_channels.h"

/* the recent actions of a group or channel: what its admins did lately, newest first, searchable by text; only an admin may open it */
@interface ExteriaAdminLogController : ExteriaGiftScreen <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@end
