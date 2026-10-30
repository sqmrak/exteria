#import <Foundation/Foundation.h>

#import "exteria_bot.h"
#import "exteria_session.h"

@class ExteriaRemoteFile;

/* the answers of the bot calls; every completion runs on the main thread */
typedef void (^ExteriaResolveCompletion)(ExteriaDialog *dialog, ExteriaPerson *person, NSString *errorName);
typedef void (^ExteriaCallbackCompletion)(ExteriaCallbackAnswer *answer, NSString *errorName);

/* bots: their buttons, commands and inline mode; implemented in exteria_session_bots.m */
@interface ExteriaSession (Bots)

/* the user, bot, group or channel behind @name (without the @) */
- (void)resolveUsername:(NSString *)name completion:(ExteriaResolveCompletion)completion;
/* the person this account already has under the user id, with the photo the chats gave it, nil when it has none; the completion runs on the main thread. the id is
   what stays when a username changes */
- (void)loadStoredPersonOfUserId:(long long)userId completion:(void (^)(ExteriaPerson *person))completion;
/* an invite link to a private group or channel (the hash of t.me/+hash): what it leads to without joining, and the join itself.
   member is set when the account is in the chat already, and then the chat opens as it is */
typedef void (^ExteriaInviteCheckCompletion)(ExteriaDialog *member, NSString *title, NSString *about, ExteriaRemoteFile *photo, NSInteger participants, BOOL broadcast, BOOL requestNeeded, NSString *errorName);
- (void)checkInviteHash:(NSString *)hash completion:(ExteriaInviteCheckCompletion)completion;
- (void)joinInviteHash:(NSString *)hash completion:(void (^)(ExteriaDialog *dialog, NSString *errorName))completion;
/* stores the name the person gives a user (contacts.addContact), which the server shows instead of the user's own;
   the last name may be empty */
/* adds somebody by the number of their phone (contacts.importContacts) with the name the person gives; found says
   whether the number has an account */
- (void)addContactPhone:(NSString *)phone firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(BOOL found, NSString *errorName))completion;
- (void)editContact:(ExteriaPerson *)person firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(NSString *errorName))completion;
/* what the bot says in its empty chat and its menu; a user without bot info answers an empty info */
- (void)loadBotInfoOfPerson:(ExteriaPerson *)bot completion:(void (^)(ExteriaBotInfo *info, NSString *errorName))completion;
/* the first message of a chat with a bot; param is the start parameter, empty for none */
- (void)startBot:(ExteriaPerson *)bot inDialog:(ExteriaDialog *)dialog param:(NSString *)param randomId:(long long)randomId
      completion:(ExteriaSendCompletion)completion;

/* the press of a callback or game button of the message. password is the account password for a button that asks
   for it, nil otherwise */
- (void)pressButton:(ExteriaMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog password:(NSString *)password
         completion:(ExteriaCallbackCompletion)completion;

/* @bot query typed in a chat; offset is empty for the first page and the page's nextOffset for the next */
- (void)searchInline:(NSString *)query bot:(ExteriaPerson *)bot inDialog:(ExteriaDialog *)dialog offset:(NSString *)offset
          completion:(void (^)(ExteriaInlinePage *page, NSString *errorName))completion;
- (void)searchInline:(NSString *)query bot:(ExteriaPerson *)bot inDialog:(ExteriaDialog *)dialog offset:(NSString *)offset
           location:(exteria_geo_point)point completion:(void (^)(ExteriaInlinePage *page, NSString *errorName))completion;
- (void)loadVenueSearchBot:(void (^)(ExteriaPerson *bot, NSString *errorName))completion;
- (void)searchVenues:(NSString *)query latitude:(double)latitude longitude:(double)longitude bot:(ExteriaPerson *)bot
           inDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaInlinePage *page, NSString *errorName))completion;
- (void)sendInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
              completion:(ExteriaSendCompletion)completion;
- (void)sendInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
              replyTo:(int32_t)replyTo completion:(ExteriaSendCompletion)completion;
/* a picture a bot hosts behind the servers; one it hosts itself is fetched by its address */
- (void)loadWebFile:(ExteriaWebFile *)file completion:(void (^)(NSData *data, NSString *errorName))completion;

/* the user a message names, with the access hash their profile needs */
- (void)loadUser:(long long)userId ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaPerson *person, NSString *errorName))completion;

/* signing in on a site: first the question for a button of a message or a bare address, then the answer */
- (void)requestUrlAuthForButton:(ExteriaMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog
                     completion:(void (^)(ExteriaUrlAuth *auth, NSString *errorName))completion;
- (void)requestUrlAuthForUrl:(NSString *)url completion:(void (^)(ExteriaUrlAuth *auth, NSString *errorName))completion;
- (void)acceptUrlAuth:(ExteriaUrlAuth *)auth button:(ExteriaMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog
         writeAllowed:(BOOL)writeAllowed code:(NSString *)code completion:(void (^)(ExteriaUrlAuth *result, NSString *errorName))completion;

/* an invoice in stars: the server's form for the invoice of a message or of a link slug, then the payment */
- (void)loadStarsInvoiceOfMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaStarsInvoice *invoice, NSString *errorName))completion;
- (void)loadStarsInvoiceOfSlug:(NSString *)slug completion:(void (^)(ExteriaStarsInvoice *invoice, NSString *errorName))completion;
- (void)payStarsInvoice:(ExteriaStarsInvoice *)invoice completion:(void (^)(NSString *errorName))completion;

/* the person's own number as a contact, for a keyboard button that asks for it */
- (void)sendContactPhone:(NSString *)phone name:(NSString *)name toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
              completion:(ExteriaSendCompletion)completion;
/* the chats picked for a request peer button of the message */
- (void)sendRequestedDialogs:(NSArray *)dialogs buttonId:(int32_t)buttonId ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog
                  completion:(void (^)(NSString *errorName))completion;

@end
