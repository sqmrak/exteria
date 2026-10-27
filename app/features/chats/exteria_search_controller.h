#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

/* the search screen of the chat list: a field with the keyboard up, ten kinds of results to pick from */
@interface ExteriaSearchController : UIViewController

/* dialogs is the loaded chat list, newest first, which the local kinds search and the people on top come from */
- (id)initWithSession:(ExteriaSession *)session dialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers;

@end
