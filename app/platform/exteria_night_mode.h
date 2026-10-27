#import <Foundation/Foundation.h>

#include "exteria_night.h"

/* the automatic night theme: at a time of the day, or when the screen is dim, the app puts on its dark theme, and
   takes it off again */

/* posted on the main thread when the person changed the setup */
extern NSString *const ExteriaNightModeDidChangeNotification;

exteria_night_config ExteriaNightConfig(void);
/* a config that is not valid is not stored */
void ExteriaNightSetConfig(exteria_night_config config);

/* the clock, the screen and the system now, as the core takes them: 1 for night, 0 for day, -1 for no opinion */
int ExteriaNightDecision(void);

/* whether the system has an appearance of its own the app can follow (ios 13 and later); the choice is offered only where it has */
BOOL ExteriaNightSystemAvailable(void);

/* where the phone is, for the schedule by the sun */
void ExteriaNightRequestLocation(void (^completion)(BOOL known));
/* whether a place is stored */
BOOL ExteriaNightHasLocation(void);

/* looks at the clock and the screen once and, when the setup says the theme should turn, stores the new theme.
   announce posts the theme change so the screens are built again */
BOOL ExteriaNightCheck(BOOL announce);

/* starts looking: every half minute, when the app comes to the front and when the brightness changes */
void ExteriaNightStart(BOOL (^gate)(void));
void ExteriaNightStop(void);
