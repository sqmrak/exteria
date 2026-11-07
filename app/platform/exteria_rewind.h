#import <Foundation/Foundation.h>

/* ios/rewind, the music client of the same author, plays the youtube tracks and opens the playlists that Exteria hands it */

/* whether Rewind is installed on this phone; asked on every call, as it can be installed while Exteria runs */
BOOL ExteriaRewindInstalled(void);

/* sends a youtube track or playlist link to Rewind as rewind://<host>/<path>; NO, with nothing opened, when the address is no such link
   (a channel, the home page, another site) or Rewind is not installed, and the caller opens it in the chosen browser */
BOOL ExteriaRewindOpenLink(NSURL *url);
