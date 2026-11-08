#import <UIKit/UIKit.h>

#import "exteria_audio_session.h"

/* the sheet that moves a call between the earpiece, the loudspeaker, headphones with a cable and a Bluetooth headset; NO, with nothing shown, when neither kind of headset is
   there, so the speaker button only toggles the loudspeaker. done runs after a choice is applied, with the route the person chose */
BOOL ExteriaCallPresentRouteSheet(UIViewController *host, void (^done)(ExteriaAudioRoute route));
/* the same sheet shown whatever is connected, for the menu of the call: the phone and the loudspeaker are offered with any headset that is there; NO only when there is no host */
BOOL ExteriaCallPresentRouteChoices(UIViewController *host, void (^done)(ExteriaAudioRoute route));
