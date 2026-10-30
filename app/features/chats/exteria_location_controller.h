#import <UIKit/UIKit.h>
#include "exteria_geo.h"
@class ExteriaSession, ExteriaDialog;

@interface ExteriaLocationController : UIViewController
@property (nonatomic, copy) void (^closeHandler)(void);
/* a bot query only needs the chosen point, not a search for nearby venues */
@property (nonatomic, assign) BOOL locationOnly;
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog location:(exteria_geo_point)location
             selection:(void (^)(exteria_geo_point point))selection;
- (void)cancel;
@end
