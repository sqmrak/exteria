#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_sticker_library.h"
#import "exteria_session.h"
#import "exteria_session_bots.h"

/* what a tap on an address, a @name, a command or a button of a bot leads to: a chat, an invoice or the system's
   browser */
/* posted with userInfo {url: NSString} for an address that came from outside the screens, such as a tg:// link the
   system handed to the app; the main screen routes it through its own router */
extern NSString *const ExteriaOpenLinkNotification;

/* whether the app opens this address itself: the tg scheme and the t.me, telegram.me and telegram.dog hosts over http or https */
BOOL ExteriaIsTelegramLink(NSURL *url);

@interface ExteriaLinkRouter : NSObject {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    UIViewController *_anchor;
    NSUInteger _token;
}

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers;

@property (nonatomic, assign) UIViewController *anchor;
@property (nonatomic, readonly) ExteriaSession *session;

/* any address a person can tap: t.me links and tg:// links open inside the app, everything else goes to the system; the links of a
   bot's web app open the chat with the bot */
- (void)openLink:(NSString *)url;
/* pushes the chat of a dialog; draft fills its field and startParam starts a bot with that parameter */
- (void)openDialog:(ExteriaDialog *)dialog person:(ExteriaPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam;
/* the same, and the chat opens at the message with this number, zero for the usual place */
- (void)openDialog:(ExteriaDialog *)dialog person:(ExteriaPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam messageId:(int32_t)messageId;
/* the profile of a user a message names; asks the server for the hash that opening it needs */
- (void)openProfileOfUser:(long long)userId inMessage:(int32_t)messageId dialog:(ExteriaDialog *)dialog;
/* lets the person pick chats the filter accepts, up to limit of them; the completion gets the ticked ones, not called when they back out */
- (void)pickDialogsWithFilter:(BOOL (^)(ExteriaDialog *dialog))filter limit:(NSUInteger)limit completion:(void (^)(NSArray *dialogs))completion;
/* lets the person pick one of their chats whose kind is in the mask (bit 0 people, 1 bots, 2 groups, 3 channels, zero for any) and tells
   the completion; nil if they backed out */
- (void)pickDialogWithTypes:(uint8_t)types completion:(void (^)(ExteriaDialog *dialog))completion;
/* asks the person to pay an invoice in stars; the completion gets paid, cancelled or failed */
- (void)payInvoiceOfSlug:(NSString *)slug completion:(void (^)(NSString *status))completion;
- (void)payInvoiceOfMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *status))completion;
/* a short text on the screen for something that is not worth an alert */
- (void)showNote:(NSString *)text;
/* the readable form of an error name from the bot calls */
+ (NSString *)textForError:(NSString *)errorName;

@end
