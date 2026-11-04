#import <UIKit/UIKit.h>

/* the home screen menu of the icon (3d touch, ios 9 and later) lists the first chats of the main list; nil or an empty list takes the menu away */
void ExteriaQuickActionsUpdate(NSArray *dialogs);

/* the "kind" and "peer" numbers of the chat a chosen menu item names, or nil for an item that is not a chat */
NSDictionary *ExteriaQuickActionChatInfo(id item);
