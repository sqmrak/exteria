#import <Foundation/Foundation.h>

/* puts the settings of the app back to what a first start has: every stored choice of the app but the list of
   accounts and the count of traffic goes, and the screens read them again; main thread only */
void ExteriaResetSettings(void);
