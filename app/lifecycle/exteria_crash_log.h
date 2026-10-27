#import <Foundation/Foundation.h>

/* the crash reports of the system did not reach the phone's CrashReporter folder for a day while the app kept
   dying (general.log counted them), so the app writes a short record of its own */
void ExteriaCrashLogStart(void);

/* notes the memory warnings with the size of the process, and a last run that ended while the app was on screen */
void ExteriaCrashLogWatchMemory(void);
