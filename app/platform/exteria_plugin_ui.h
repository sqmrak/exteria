#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include "exteria_status.h"

/* the uikit side of the android view shim of python/shim/android. a plugin builds a tree of views in python; the operations
   arrive here as json lists (see python/shim/android/_ui.py) and become views in one overlay above the key window. the
   overlay passes every touch that is not on a view the plugin asked touches for */

/* answers the services "ui.*", "sensor.*", "theme.*", "app.*" and "chat.*". EXTERIA_E_UNSUPPORTED when the name is not one of
   them. *reply is a json object, *failure the text of a failed request. main thread only */
exteria_status ExteriaPluginUIService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure);

/* posted by the service "app.pick" for the main screen, which owns the chat picker of the app. userInfo: token (NSNumber),
   types (bit 1 users, 2 bots, 4 groups, 8 channels), limit (how many chats at most). the answer goes back to python as
   pick_result(token, [{id, kind}]) once the person has chosen; nothing comes back when they go back instead */
extern NSString *const ExteriaPluginPickNotification;

/* removes every view a plugin made and stops the sensor; used when the last plugin goes */
void ExteriaPluginUIReset(void);

/* the newest frame of a native surface as an image, +1 retained; NULL when the surface has none. the pixels are copied */
CGImageRef ExteriaPluginSurfaceImage(NSString *name);
