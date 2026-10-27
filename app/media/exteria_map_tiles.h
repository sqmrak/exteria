#import <UIKit/UIKit.h>
#include "exteria_geo.h"

@interface ExteriaMapTileTicket : NSObject
- (void)cancel;
@end

/* shared by message previews and the full map, so one visible tile has one request */
@interface ExteriaMapTiles : NSObject
+ (ExteriaMapTiles *)sharedTiles;
- (ExteriaMapTileTicket *)loadTile:(exteria_map_tile)tile completion:(void (^)(UIImage *image, NSString *failure))completion;
@end
