#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session_channels.h"
#import "exteria_session_invites.h"
#import "exteria_settings_kit.h"

/* the invite links the account made for a channel or a group: the live ones, the revoked ones, and what to do with each (copy, share, change the term and the
   number of joins, revoke, delete) */
@interface ExteriaChannelInvitesController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;

@end
