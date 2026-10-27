#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* the reports of the app's own failures, which go to the developer in a private message from the account of the
   person; a crash the app recorded in its log before it died, and a call that could not connect, with the trace it
   wrote */

/* looks for crashes the log holds that were not told yet, a little after the screens start, and sends them */
void ExteriaProblemReportsStart(ExteriaSession *session);
/* a call ended without a path for the audio; the trace of the call is added */
void ExteriaProblemReportCallFailure(ExteriaSession *session);
/* what a report is headed with: the version and the build, the processor, the system and the model of the phone; also shown in the settings */
NSString *ExteriaProblemReportHeader(void);
