#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_session.h"

/* the files a person asked for in a chat and that came, kept for each account, newest first; the list of downloads of the search shows them, and a tap opens the chat at the
   message. A file the cache has dropped since comes again from that message */
#define EXTERIA_DOWNLOAD_LOG_MAX 300

void ExteriaDownloadLogAdd(ExteriaSession *session, ExteriaDialog *dialog, ExteriaMessage *message);
/* the downloads as rows that stand for their messages: the file name, then the chat and the size; query narrows them by name or chat, case and accents aside */
NSArray *ExteriaDownloadLogDialogs(ExteriaSession *session, NSString *query);
