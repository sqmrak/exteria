#import <UIKit/UIKit.h>

/* a sheet a plugin opens over the app, built like the browser's: a card that slides up and is pulled down to close. it shows a native
   surface (see core/pyhost/exteria_surface.h) under a title, and the touch keys the plugin lists. the module of the surface is run
   by the sheet itself, a frame at a time, so python is not in the loop

   spec: title, surface (name), width and height (the proportions of the picture), ended (the text for a surface that stopped),
   buttons: [{label, key, slot}] with slot one of up, down, left, right, a, b, c, t1, t2, t3 */

/* the number of the sheet, or 0 when it could not be shown */
NSInteger ExteriaPluginSheetOpen(NSDictionary *spec, UIViewController *host);
/* the plugin has loaded what the surface needs: the frames start */
void ExteriaPluginSheetReady(NSInteger sheet);
/* the surface will not run: the text takes the place of the picture */
void ExteriaPluginSheetFail(NSInteger sheet, NSString *text);
void ExteriaPluginSheetClose(NSInteger sheet);
/* every sheet is closed at once, for the end of the plugins */
void ExteriaPluginSheetCloseAll(void);
