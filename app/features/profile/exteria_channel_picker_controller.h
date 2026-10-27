#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

#import "exteria_dialog.h"

/* the channels the person manages, each with its picture, to choose the one for the profile from; the first row takes the channel off */
@interface ExteriaChannelPickerController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
@property (nonatomic, copy) NSString *screenTitle;
/* the channel on the profile now, which is marked */
@property (nonatomic, assign) long long currentChannelId;
/* runs on the main thread with the chosen channel, or nil for none */
@property (nonatomic, copy) void (^pickHandler)(ExteriaDialog *channel);

@end
