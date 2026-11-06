#import <UIKit/UIKit.h>

/* the sheet that moves a call between the earpiece, the loudspeaker and a Bluetooth headset; NO, with nothing shown, when no headset is
   connected, so the speaker button only toggles the loudspeaker. done runs after a choice is applied, with the route the person chose */
#import "exteria_audio_session.h"
BOOL ExteriaCallPresentRouteSheet(UIViewController *host, void (^done)(ExteriaAudioRoute route));
