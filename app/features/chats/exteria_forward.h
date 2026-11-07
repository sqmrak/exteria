#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"

/* forwards messages of one chat. when the caller knows the chat forbids forwarding, or a message does, and "copy protected messages" is on, copies without the
   author go out instead. a forward the server refuses with CHAT_FORWARDS_RESTRICTED or MESSAGE_COPYRIGHTED is copied the same way.
   completion gets nil on success, otherwise the text to show, on the main thread */
void ExteriaForwardMessages(ExteriaSession *session, ExteriaMediaCache *media, ExteriaDialog *from, BOOL chatRestricted, NSArray *messages, ExteriaDialog *target, BOOL hideAuthor, void (^completion)(NSString *message));
