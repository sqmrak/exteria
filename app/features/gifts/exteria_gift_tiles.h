#import "exteria_gift_grid_view.h"
#import "exteria_gift_screen.h"
#import "exteria_star_gift.h"
#import "exteria_story.h"

/* the tile of a gift on a profile; mine marks the gifts hidden from the owner's own profile */
ExteriaGiftTileInfo *ExteriaTileForSavedGift(ExteriaSavedGift *saved, BOOL mine);
/* the tile of a gift for sale */
ExteriaGiftTileInfo *ExteriaTileForCatalogGift(ExteriaStarGift *gift);
/* the tile of a story: its picture or the thumbnail of its video, the day and how many saw it */
ExteriaGiftTileInfo *ExteriaTileForStory(ExteriaStory *story);
