#import <Foundation/Foundation.h>

/* the connection to the server stays alive in the background on ios 5 and 6 only when the system knows it as a
   VoIP socket, and it only knows a socket by a pair of CFStreams that carry the service type */

/* whether this system keeps a VoIP socket alive for the app */
BOOL ExteriaVoipSocketSupported(void);

/* a handle for the streams, nil when the system or the call refuses; the streams run on a copy of the descriptor
   and are opened on the main thread, so the call may come from any thread and returns before they are open */
void *ExteriaVoipSocketAttach(int fd);
/* closes the streams of a handle and the copy of the descriptor they hold; the handle is dead after this */
void ExteriaVoipSocketDetach(void *handle);
