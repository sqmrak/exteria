#import <Foundation/Foundation.h>

@class ExteriaSession;

/* what a plugin may do with the account, and nothing more: read the newest messages of Saved Messages, read and change the saved music of the profile, delete
   messages of Saved Messages, send an audio file there as a song, and publish a story a plugin held back (story_post). these are the requests the plugins that fill a profile with music make (python/shim
   org/telegram/tgnet/requests.py maps the TL request classes onto them). anything else a plugin asks for through send_request is refused in python


   exteria_plugin_ui.m posts ExteriaPluginAccountNotification for the services "account.*"; the main screen owns the session and one of these, which answers by
   calling exteria_host.account_result(token, error, payload) */
extern NSString *const ExteriaPluginAccountNotification;

@interface ExteriaPluginAccount : NSObject
- (id)initWithSession:(ExteriaSession *)session;
/* stops listening; the session may go before this object does */
- (void)invalidate;
@end
