#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the contact list as a system table with a search bar; a contact opens into its chat */
@interface ExteriaClassicContactsController : UITableViewController <UISearchBarDelegate>

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers;

@end
