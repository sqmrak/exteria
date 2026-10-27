#import "exteria_gift_screen.h"
#import "exteria_session_channels.h"

/* one of the three lists an admin keeps: the subscribers, the administrators and the blacklist */
@interface ExteriaChannelMembersController : ExteriaGiftScreen <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel list:(ExteriaChannelList)list avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media;

/* set before the screen is shown: the person tapped is passed here and the screen goes back */
@property (nonatomic, copy) void (^pickHandler)(ExteriaChannelMember *member);
/* runs on the main thread after a change that moves the counts of the channel (an admin appointed or taken away, a person banned or let back) */
@property (nonatomic, copy) void (^changedHandler)(void);

@end
