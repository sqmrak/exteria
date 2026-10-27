#import "exteria_list_controller.h"
#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"

/* the contact list, alphabetical, with the last seen line under each name */
@interface ExteriaContactsController : ExteriaListController

/* what a chat opened from a contact needs for its pictures and its sticker panel */
@property (nonatomic, retain) ExteriaMediaCache *media;
@property (nonatomic, retain) ExteriaStickerLibrary *stickerLibrary;

@end
