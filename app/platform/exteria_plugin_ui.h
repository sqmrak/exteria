#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "exteria_status.h"

/* the uikit side of the android view shim of python/shim/android. a plugin builds a tree of views in python; the operations
   arrive here as json lists (see python/shim/android/_ui.py) and become views in one overlay above the key window. the
   overlay passes every touch that is not on a view the plugin asked touches for */

/* answers the services "ui.*", "sensor.*", "theme.*", "app.*", "chat.*", "sheet.*", "audio.*", "bitmap.*" and "page.*". EXTERIA_E_UNSUPPORTED when the name is not one of
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

/* the page ids python addresses a page of the app by: the root of the views a plugin puts on it is registered under the id, see PageView in python/shim/android/view */
#define EXTERIA_PLUGIN_PAGE_SETTINGS (-1LL)

/* the transparent layer a page gives to the views a plugin adds under its rows, registered under pageId. the page puts it between its background and its
   table and keeps it as long as the page lives; calling this again for the same id replaces the layer, and what python added to the old one is sent again
   by the next page event (create). when the layer gains or loses a view the page is asked to lay out again, so it can hide what the views now cover */
UIView *ExteriaPluginPageLayer(long long pageId);

/* how opaque a plugin wants the cards of the settings page: 1 is as the app draws them. posted when it changes, and the page reads the value when it is made */
extern NSString *const ExteriaPluginCardsNotification;
CGFloat ExteriaPluginCardAlpha(void);

/* the person the app is signed in as, for the plugins that ask who "me" is (app.me). the main screen sets it when it has a session, zero when there is none */
void ExteriaPluginUISetOwnUser(long long userId, NSString *firstName);
