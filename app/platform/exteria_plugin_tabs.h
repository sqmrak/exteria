#import <Foundation/Foundation.h>

#import "exteria_status.h"

/* what a plugin changes on the bottom bar of the main screen (python/shim/org/telegram/ui/_tabs.py stands MainTabsActivity over it). a tab of the bar is a slot;
   a plugin gives a slot another title or icon and takes over its tap and its long press. the changes are kept here, by slot, so a rebuild of the bar (theme,
   layout) shows them again, and they go when the last plugin does. services, main thread only:

   tabs.set (slot, title, icon, click, hold)   title is a string or null, icon the name of a symbol of the app or null, click and hold say that python wants the tap
   tabs.state                                  whether the main screen has its bar up */
exteria_status ExteriaPluginTabsService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure);

/* posted when a slot changed or all were taken back; the main screen applies them to its bar */
extern NSString *const ExteriaPluginTabsNotification;

/* the changes of a slot: title (NSString, may be missing), symbol (NSNumber of an ExteriaSymbol, may be missing), click and hold (NSNumber BOOL). nil when the slot is as the app made it */
NSDictionary *ExteriaPluginTabChange(NSInteger slot);

/* the main screen tells whether it has a bar, which is what a plugin finds when it looks for the screen */
void ExteriaPluginTabsSetBarUp(BOOL up);

/* takes every change back */
void ExteriaPluginTabsReset(void);
