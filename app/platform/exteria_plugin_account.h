#import <Foundation/Foundation.h>

@class ExteriaSession;
@class ExteriaMedia;

/* what a plugin may do with the account, and nothing more: read the newest messages of Saved Messages, read and change the saved music of the profile, delete
   messages of Saved Messages, list the messages of the open chat (all of them, or the account's own), delete messages by id, find the newest or the oldest song of a chat and read the saved music of a user of the chat list, send an audio file there as a song, and publish a story a plugin held back (story_post). these are the requests the plugins that fill a profile with music make (python/shim
   org/telegram/tgnet/requests.py maps the TL request classes onto them). anything else a plugin asks for through send_request is refused in python


   exteria_plugin_ui.m posts ExteriaPluginAccountNotification for the services "account.*"; the main screen owns the session and one of these, which answers by
   calling exteria_host.account_result(token, error, payload) */
extern NSString *const ExteriaPluginAccountNotification;

/* posted when plugins deleted messages of a chat on the server, so the open screen drops the rows: userInfo has ids (NSNumber) and, for a channel, its dialog (ExteriaDialog); without one the ids are those of the account, see
   account.delete. the app has already removed its kept copies */
extern NSString *const ExteriaPluginMessagesDeletedNotification;

/* the song a document of python names (id, access_hash, dc, file_ref, and the size, name, mime, title, performer and duration when it has them); nil when it cannot name one */
ExteriaMedia *ExteriaPluginSongOfJSON(NSDictionary *doc);

/* whether the chat list the app holds has this chat, by the id the android client uses for it: a user is positive, a group or a channel negative (the plain id after the sign).
   plugins ask before they send a request that names the chat, since the app finds the access hash of a chat in its list only */
BOOL ExteriaPluginKnowsDialog(long long dialogId);

@interface ExteriaPluginAccount : NSObject
- (id)initWithSession:(ExteriaSession *)session;
/* the chats of the list, read at the start and again when plugins start or ask for a chat the list lacks */
- (void)refreshDialogs;
/* stops listening; the session may go before this object does */
- (void)invalidate;
@end
