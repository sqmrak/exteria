#import "exteria_settings_kit.h"

@class ExteriaSession;

/* the Change Chat Background screen of the chat settings */
@interface ExteriaWallpaperController : ExteriaSettingsPageController

/* the wallpaper of every chat, from the chat settings */
- (id)init;
/* the wallpaper of one chat alone, from the menu of that chat: what is picked stays in this chat, and the app and its other chats keep theirs */
- (id)initWithPeerKind:(int32_t)peerKind peerId:(long long)peerId;

/* the account the page is opened from; with it the previews of the customization show the picture of the lead developer from the server, without it the one kept from an
   earlier time, or the initials */
@property (nonatomic, retain) ExteriaSession *session;

@end
