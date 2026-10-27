#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_settings_kit.h"

typedef enum {
    ExteriaStickerCatalogFeatured,
    ExteriaStickerCatalogArchived,
    ExteriaStickerCatalogEmoji
} ExteriaStickerCatalogKind;

/* a list of sticker sets of the Stickers and Emoji screen */
@interface ExteriaStickerCatalogController : ExteriaSettingsPageController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media kind:(ExteriaStickerCatalogKind)kind;

@end
