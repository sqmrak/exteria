#import <Foundation/Foundation.h>

#include "exteria_lite_rules.h"

/* the power saving settings: which animations run, the battery level under which none do, smooth transitions and
   the class of the device; main thread only */

extern NSString *const ExteriaLiteModeDidChangeNotification;

/* starts reading the battery and applies the smooth transitions setting; once, at launch */
void ExteriaLiteModeStart(void);

/* whether the animation of flag runs now: chosen, and not under the power saver */
BOOL ExteriaLiteEnabled(uint32_t flag);
void ExteriaLiteSetFlag(uint32_t flag, BOOL on);

/* the battery percent under which the power saver applies: 0 never, 100 always */
int ExteriaLitePowerSaverLevel(void);
void ExteriaLiteSetPowerSaverLevel(int level);
BOOL ExteriaLitePowerSaverApplied(void);
/* 0 to 100, or -1 when the device cannot tell */
int ExteriaLiteBatteryPercent(void);

/* whether the account has Telegram Premium, which picks the bit of the emoji flags; kept for the next launch */
void ExteriaLiteSetPremium(BOOL premium);

/* the animations of the interface that UIKit runs between screens and in its sheets */
BOOL ExteriaLiteSmoothTransitions(void);
void ExteriaLiteSetSmoothTransitions(BOOL on);

/* the class of the device: the person's choice (0 auto, 1 high, 2 average, 3 low) and what it comes to */
int ExteriaLiteClassChoice(void);
void ExteriaLiteSetClassChoice(int choice);
exteria_lite_class ExteriaLiteClass(void);
exteria_lite_class ExteriaLiteMeasuredClass(void);
NSString *ExteriaLiteClassName(exteria_lite_class device_class);
/* how many animated stickers of a chat may run at once: more on a stronger class */
NSUInteger ExteriaLiteStickerLimit(void);
