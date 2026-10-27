#import <Foundation/Foundation.h>

/* the short sounds of the bundle (the tones of the notifications, the sounds of the chat), played through the
   system sound service */
void ExteriaPlayAppSound(NSString *file);

/* the phone shakes once, on the devices that can, and only when the vibration of the in-app notices is on: the check is here, so no caller can shake the phone past the setting */
void ExteriaVibrateOnce(void);

/* the buzz of a call that rings on the screen, unless the vibration of calls is set to off */
void ExteriaVibrateForCall(void);

/* the short sound of the chat on screen: a message that came in, or one that was sent; only when In-Chat Sounds is
   on; two in a moment are one */
void ExteriaPlayInChatSound(BOOL incoming);
