#import "exteria_list_controller.h"
#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"

/* the Calls tab: the calls of the account, newest first, each with the person, how it went and when */
@interface ExteriaCallsController : ExteriaListController

@property (nonatomic, retain) ExteriaMediaCache *media;
@property (nonatomic, retain) ExteriaStickerLibrary *stickerLibrary;

@end
