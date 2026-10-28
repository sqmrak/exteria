#import <Foundation/Foundation.h>

#include "exteria_passcode.h"

/* the passcode lock of the app: what is kept of the code, how long a leave may last, and how fast wrong tries are
   let through */

typedef enum {
    ExteriaPasscodeResultOK,
    ExteriaPasscodeResultWrong,
    ExteriaPasscodeResultWait
} ExteriaPasscodeResult;

BOOL ExteriaPasscodeEnabled(void);
exteria_passcode_type ExteriaPasscodeType(void);

/* a fresh salt is made for every code; NO when the code does not fit the type or the system has no random bytes */
BOOL ExteriaPasscodeSet(exteria_passcode_type type, NSString *code);
void ExteriaPasscodeClear(void);

/* waitSeconds, when given, is how long the lock still refuses tries (after a wrong code or on Wait) */
ExteriaPasscodeResult ExteriaPasscodeCheck(NSString *code, NSUInteger *waitSeconds);
NSUInteger ExteriaPasscodeWaitRemaining(void);

/* seconds away that the app allows before it asks for the code again: 0 never, 1 on every return */
uint32_t ExteriaPasscodeAutoLock(void);
void ExteriaPasscodeSetAutoLock(uint32_t seconds);

/* the sensor may open the lock in place of the code; it never replaces the code, which stays the way in when the sensor fails, and it goes with the code */
BOOL ExteriaPasscodeBiometricEnabled(void);
void ExteriaPasscodeSetBiometric(BOOL on);
