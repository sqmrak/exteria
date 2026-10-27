#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* who is signed in and the way out, as a grouped system table with the person on top */
@interface ExteriaClassicProfileController : UITableViewController <UIActionSheetDelegate>

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars;

/* the person confirmed; the handler asks the server to end the session and calls back with nil or the rpc error name */
@property (nonatomic, retain) ExteriaMediaCache *media;
@property (nonatomic, retain) ExteriaStickerLibrary *stickerLibrary;
@property (nonatomic, copy) void (^signOutHandler)(void (^completion)(NSString *errorName));

@end
