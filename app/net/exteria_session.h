#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_media_link.h"
#import "exteria_shiro.h"
#import "exteria_typing_board.h"

typedef enum {
    ExteriaAuthEventCode,
    ExteriaAuthEventPassword,
    ExteriaAuthEventSignUp,
    ExteriaAuthEventAuthorized,
    ExteriaAuthEventFailed,
    /* the account asks for a login step Exteria does not implement, such as e-mail verification */
    ExteriaAuthEventUnsupported,
    ExteriaAuthEventOffline,
    /* the server dropped the session key, so the stored account is gone */
    ExteriaAuthEventLoggedOut,
    /* a login token to show as a QR code; a new one follows each time the token runs out or is scanned */
    ExteriaAuthEventQr,
    /* the server sent a recovery code to the e-mail of the cloud password, shown in emailPattern */
    ExteriaAuthEventRecovery
} ExteriaAuthEventKind;

typedef enum {
    ExteriaCodeKindApp,
    ExteriaCodeKindSms,
    ExteriaCodeKindCall,
    ExteriaCodeKindOther
} ExteriaCodeKind;

/* what the login state machine reported, copied out of the transport arena */
@interface ExteriaAuthEvent : NSObject {
    ExteriaAuthEventKind _kind;
    ExteriaCodeKind _codeKind;
    NSInteger _codeLength;
    NSInteger _resendAfter;
    NSInteger _errorNumber;
    NSString *_hint;
    BOOL _hasRecovery;
    NSString *_emailPattern;
    NSString *_errorName;
    long long _userId;
    NSString *_qrUrl;
    NSTimeInterval _qrExpires;
}
@property (nonatomic, readonly) ExteriaAuthEventKind kind;
/* the tg://login address to draw as a QR code, and the unix time it stops working */
@property (nonatomic, readonly, copy) NSString *qrUrl;
@property (nonatomic, readonly) NSTimeInterval qrExpires;
@property (nonatomic, readonly) ExteriaCodeKind codeKind;
/* digits the code has, zero when the server did not say */
@property (nonatomic, readonly) NSInteger codeLength;
/* seconds until the code can be sent another way, negative when it cannot */
@property (nonatomic, readonly) NSInteger resendAfter;
@property (nonatomic, readonly) NSInteger errorNumber;
@property (nonatomic, readonly, copy) NSString *hint;
/* the password has a recovery e-mail, so the code to reset it can be requested */
@property (nonatomic, readonly) BOOL hasRecovery;
/* the masked address the recovery code went to, such as a***@gmail.com */
@property (nonatomic, readonly, copy) NSString *emailPattern;
/* the rpc error name without its number, for example PHONE_CODE_INVALID or FLOOD_WAIT */
@property (nonatomic, readonly, copy) NSString *errorName;
@property (nonatomic, readonly) long long userId;
@end

@class ExteriaSession;

@protocol ExteriaSessionDelegate <NSObject>
/* always on the main thread */
- (void)session:(ExteriaSession *)session didReceiveAuthEvent:(ExteriaAuthEvent *)event;
@end

@class ExteriaStickerDocument;
@class ExteriaCall;
@class ExteriaGroupCall;
@class ExteriaGroupCallEngine;
@class ExteriaCallVideo;
@class ExteriaCommunity;
@class ExteriaDraftBoard;

@protocol ExteriaCallDelegate <NSObject>
/* the call changed, or ended; always on the main thread */
- (void)session:(ExteriaSession *)session callDidChange:(ExteriaCall *)call;
@end

@protocol ExteriaGroupCallDelegate <NSObject>
/* the group call changed, or ended; always on the main thread */
- (void)session:(ExteriaSession *)session groupCallDidChange:(ExteriaGroupCall *)call;
@end

/* owns the mtproto client and one worker thread; every call below only queues work for that thread */
/* one custom emoji: the emoji it stands for, how it is stored, and the files to draw it from */
@interface ExteriaCustomEmojiDocument : NSObject {
    long long _documentId;
    NSString *_alt;
    int _format;
    ExteriaRemoteFile *_file;
    ExteriaRemoteFile *_preview;
}
@property (nonatomic, readonly) long long documentId;
@property (nonatomic, readonly, copy) NSString *alt;
/* an exteria_sticker_format */
@property (nonatomic, readonly) int format;
@property (nonatomic, readonly, retain) ExteriaRemoteFile *file;
@property (nonatomic, readonly, retain) ExteriaRemoteFile *preview;
@end

/* posted on the main thread, by the session, each time connected changes */
/* posted on the main thread with the refreshed archive shortcut under the key "dialog" */
extern NSString *const ExteriaArchiveSummaryDidChangeNotification;
extern NSString *const ExteriaSessionConnectionDidChangeNotification;
extern NSString *const ExteriaSessionDialogsUpdatedNotification;
/* the other side read more of our messages in a chat; userInfo has kind, peer and maxId */
extern NSString *const ExteriaReadOutboxDidChangeNotification;
/* the parts of a file sent in a message that the server has taken, on the main thread; userInfo has "randomId" (the NSNumber of the pending message)
   and "fraction" (an NSNumber float from 0 to 1) */
extern NSString *const ExteriaUploadProgressNotification;

@interface ExteriaSession : NSObject {
    id<ExteriaSessionDelegate> _delegate;
    id<ExteriaCallDelegate> _callDelegate;
    id<ExteriaGroupCallDelegate> _groupCallDelegate;
    /* who the account writes as in each chat that offers a choice, as the exteria_peer_ref data of the identity, keyed by the chat; any thread, under @synchronized */
    NSMutableDictionary *_sendAsChoices;
    NSArray *_chatFolders;
    NSUInteger _chatFolderGeneration;
    uint64_t _folderFloodUntilMs;
    BOOL _chatFolderSaving;
    ExteriaDraftBoard *_drafts;
    /* worker only: every draft of the account was asked for in this run */
    BOOL _draftsRequested;
}

@property (nonatomic, assign) id<ExteriaSessionDelegate> delegate;
/* main thread only: hears every change of the one voice call the session can hold */
@property (nonatomic, assign) id<ExteriaCallDelegate> callDelegate;
/* main thread only: hears every change of the one group call (voice chat) the session can hold */
@property (nonatomic, assign) id<ExteriaGroupCallDelegate> groupCallDelegate;
/* the voice chats of the account: joining, making and leaving them */
@property (nonatomic, readonly) ExteriaGroupCallEngine *groupCalls;
/* main thread only: who is typing in which chat, from the live updates */
@property (nonatomic, readonly) ExteriaTypingBoard *typing;
/* main thread only: the drafts of the account's chats, from the chat lists, the live updates and what the person types */
@property (nonatomic, readonly) ExteriaDraftBoard *drafts;
/* the newest id of ours the other side is known to have read in a chat since the app started, zero when no update said; main thread */
- (int32_t)readOutboxOfKind:(int32_t)kind peer:(long long)peer;
- (void)noteReadOutbox:(int32_t)maxId ofKind:(int32_t)kind peer:(long long)peer;
/* main thread only: whether the link is up and the server has answered on it since it was opened; screens show
   a connecting title while it is NO */
@property (nonatomic, readonly) BOOL connected;

/* directory holds the session keys, the account file and the database; it is created when missing */
- (id)initWithDirectory:(NSString *)directory;
+ (BOOL)hasAccountInDirectory:(NSString *)directory;
/* the id of the stored account, zero when there is none; read from the account file, so any thread may ask */
+ (long long)accountIdInDirectory:(NSString *)directory;
/* where the keys, the account file, the database and the other files of the account are kept */
@property (nonatomic, readonly, copy) NSString *directory;

/* the VPN the connections go through when it is wanted; set before start */
@property (nonatomic, assign) ExteriaShiro *shiro;

- (void)start;
- (void)stop;
/* the network came back or the user retried after an offline event */
- (void)reconnect;
/* how long a quiet link waits before it pings the server, in milliseconds (the client keeps it between 10 and 300
   seconds, 0 is its default of 30) */
- (void)setPingInterval:(uint32_t)milliseconds;
/* runs the block on the main thread once the session thread has finished what it was doing and what was posted
   before this call, which is when its transaction on the database, if one was open */
- (void)afterPendingWork:(void (^)(void))block;
/* the route of the traffic changed (the VPN went up, dropped or was switched): the open links are on the old path, so they are closed and opened
   again on the new one */
- (void)routeChanged;

- (void)requestCodeForNumber:(NSString *)number;
- (void)submitCode:(NSString *)code;
- (void)resendCode;
/* asks for a login token to show as a QR code; the answers are ExteriaAuthEventQr events, then the usual ones once another device
   confirmed (a password, or authorized) */
- (void)requestQrLogin;
- (void)submitPassword:(NSString *)password;
/* asks for a code on the recovery e-mail; the answer is an ExteriaAuthEventRecovery event, or a failure that keeps the password screen */
- (void)requestPasswordRecovery;
/* the code from the recovery e-mail; a right one signs in and drops the cloud password */
- (void)submitRecoveryCode:(NSString *)code;
- (void)submitFirstName:(NSString *)first lastName:(NSString *)last;
- (void)cancelLogin;

/* every load below runs its completion on the main thread, with the items in server order or with nil and the rpc
   error name */
typedef void (^ExteriaListCompletion)(NSArray *items, NSString *errorName);

- (void)loadDialogs:(ExteriaListCompletion)completion;
/* folder 0 is the main list, 1 the archive; the main list carries the archive as its own entry */
- (void)loadDialogsInFolder:(int32_t)folder completion:(ExteriaListCompletion)completion;
- (void)loadDialogPageInFolder:(int32_t)folder after:(ExteriaDialog *)cursor completion:(void (^)(NSArray *items, ExteriaDialog *next, NSString *errorName))completion;
/* the list as the last good load left it, so a screen can show it before the network answers; a nil list means
   nothing is kept yet and is not an error */
- (void)loadCachedDialogsInFolder:(int32_t)folder completion:(ExteriaListCompletion)completion;
/* moves a chat into the archive (folder 1) or back to the main list (0) on the server; the completion
   runs on the main thread with nil on success or the rpc error name */
- (void)moveDialog:(ExteriaDialog *)dialog toFolder:(int32_t)folder completion:(void (^)(NSString *errorName))completion;
/* makes a channel, or a supergroup when megagroup is set, with the title; the completion runs on the main thread with nil on
   success or the rpc error name */
- (void)createChannelTitled:(NSString *)title megagroup:(BOOL)megagroup completion:(void (^)(NSString *errorName))completion;
/* every public user, bot, group and channel whose name or @username starts with the text, as ExteriaDialog items:
   the chats the account has first */
- (void)searchPeers:(NSString *)query completion:(ExteriaListCompletion)completion;
- (void)loadContacts:(ExteriaListCompletion)completion;
/* the signed in user as a one item list */
- (void)loadSelf:(ExteriaListCompletion)completion;
/* the account's own profile as it was last read, in memory or from the file the last run left, nil on a first
   start */
- (ExteriaPerson *)ownPerson;

/* a file, wherever it lives; the completion runs on the main thread with the bytes, or nil and an error name
   (TIMEOUT, FILE_TOO_BIG, an rpc error name) */
- (void)downloadFile:(ExteriaRemoteFile *)file completion:(ExteriaDownloadCompletion)completion;
/* one part of a large file: up to limit bytes from offset, fewer on the last part and none past the end */
- (void)downloadFile:(ExteriaRemoteFile *)file offset:(long long)offset limit:(int32_t)limit completion:(ExteriaDownloadCompletion)completion;

/* voice and video calls: one at a time */
- (void)startCallToDialog:(ExteriaDialog *)dialog;
- (void)startVideoCallToDialog:(ExteriaDialog *)dialog;
- (void)acceptCall;
- (void)declineCall;
- (void)hangUpCall;
- (void)setCallMuted:(BOOL)muted;
/* the camera of a call that runs; a device without one, or a refusal, leaves the call as an audio call and the
   snapshot says so */
- (void)setCallCameraOn:(BOOL)on;
/* main thread: the camera and the pictures of the call that runs, nil when none does; valid while the call lasts */
- (ExteriaCallVideo *)activeCallVideo;

/* ends the session on the server, then drops the key and the stored account; ExteriaAuthEventLoggedOut follows */
- (void)signOut:(void (^)(NSString *errorName))completion;

@end

/* the answers of the chat calls, on the main thread */
typedef void (^ExteriaHistoryCompletion)(NSArray *messages, NSDictionary *people, NSString *errorName);
typedef void (^ExteriaHistoryPageCompletion)(NSArray *messages, NSDictionary *people, exteria_history_page page, NSString *errorName);
typedef void (^ExteriaSendCompletion)(int32_t messageId, NSString *errorName);
typedef void (^ExteriaSearchCompletion)(NSArray *dialogs, int32_t nextRate, NSString *errorName);

/* chats: history, sending, live messages and stickers; implemented in exteria_session_chat.m */
@interface ExteriaSession (Chat)
- (void)uploadStickerAtPath:(NSString *)path completion:(void (^)(ExteriaStickerDocument *document, NSString *errorName))completion;

/* the newest messages of a chat, or the ones before beforeId (zero for the newest), newest first, with the people
   they mention keyed by user id (NSNumber) as ExteriaPerson */
- (void)loadHistoryOfDialog:(ExteriaDialog *)dialog beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(ExteriaHistoryCompletion)completion;
/* a page that may reach toward newer messages: offsetId and a negative addOffset as exteria_history_window_request takes them */
- (void)loadHistoryOfDialog:(ExteriaDialog *)dialog offsetId:(int32_t)offsetId addOffset:(int32_t)addOffset limit:(int32_t)limit completion:(ExteriaHistoryCompletion)completion;
- (void)loadHistoryOfDialog:(ExteriaDialog *)dialog offsetId:(int32_t)offsetId addOffset:(int32_t)addOffset limit:(int32_t)limit pageCompletion:(ExteriaHistoryPageCompletion)completion;

/* the topics of a forum as ExteriaDialog items carrying a topicId, pinned ones first and then by last message; at
   most 200 */
- (void)loadTopicsOfDialog:(ExteriaDialog *)forum completion:(ExteriaListCompletion)completion;
/* the favorites split by the chat each message came from, newest first: ExteriaDialog rows, the one for the account's own notes included (its saved is set) */
- (void)loadSavedDialogs:(ExteriaListCompletion)completion;

/* the chats a community groups, from the server */
- (void)loadCommunity:(ExteriaDialog *)community knownDialogs:(NSArray *)known completion:(void (^)(ExteriaCommunity *community, NSString *errorName))completion;
/* shows the community as one chat in the list, or as its separate chats; the completion runs on the main thread with nil on success or the rpc error name */
- (void)setCommunity:(ExteriaDialog *)community collapsed:(BOOL)collapsed completion:(void (^)(NSString *errorName))completion;

/* the pinned messages of a chat, newest first, up to a hundred, with the people they mention keyed as for the
   history */
- (void)loadPinnedMessagesOfDialog:(ExteriaDialog *)dialog completion:(ExteriaHistoryCompletion)completion;
/* the messages of the person that got a reaction not seen yet, newest first */
- (void)loadUnreadReactionsOfDialog:(ExteriaDialog *)dialog completion:(ExteriaHistoryCompletion)completion;
- (void)markReactionsReadOfDialog:(ExteriaDialog *)dialog;
/* the messages of a chat that contain a text, newest first; the query is not empty and at most EXTERIA_CHAT_SEARCH_QUERY_MAX bytes of UTF-8 */
- (void)searchMessagesOfDialog:(ExteriaDialog *)dialog query:(NSString *)query completion:(ExteriaHistoryCompletion)completion;
/* everything one person wrote in the chat, newest first, as the "history" of the menu of a message in a group */
- (void)searchMessagesOfDialog:(ExteriaDialog *)dialog fromUserId:(long long)userId accessHash:(long long)accessHash completion:(ExteriaHistoryCompletion)completion;
/* everything the account itself wrote in the chat, newest first */
/* the photos and videos, the files or the links of a chat, newest first, a page older than beforeId (zero for the newest) */
- (void)loadSharedOfDialog:(ExteriaDialog *)dialog kind:(exteria_shared_kind)kind beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(ExteriaHistoryCompletion)completion;
/* the oldest messages of the chat, one page, newest of them first */

/* the newest messages of a chat that earlier loads and live updates left on disk, with their senders; nil messages
   when none are kept */
- (void)loadCachedHistoryOfDialog:(ExteriaDialog *)dialog completion:(ExteriaHistoryCompletion)completion;

/* sends a message; randomId names it on the way back and must differ for every message */
/* entities are the ExteriaTextEntity items of the text; only the custom emoji among them travel with it, and nil sends plain text */
- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId completion:(ExteriaSendCompletion)completion;
/* the same as an answer to the message replyTo; zero sends it on its own */
- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(ExteriaSendCompletion)completion;
- (void)sendSticker:(ExteriaMedia *)sticker toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId completion:(ExteriaSendCompletion)completion;
/* sends a recorded file as a voice note or a round video: the file goes up in parts, then the message names it */
- (void)sendVoiceAtPath:(NSString *)path durationMs:(int32_t)durationMs waveform:(NSData *)waveform toDialog:(ExteriaDialog *)dialog
               randomId:(long long)randomId completion:(ExteriaSendCompletion)completion;
- (void)sendRoundVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side toDialog:(ExteriaDialog *)dialog
                    randomId:(long long)randomId completion:(ExteriaSendCompletion)completion;
/* a jpeg as a photo, an mp4 as a video, any file as a document with its name and mime type, a point on the map; the same
   completion and error names as the recordings */
- (void)sendOutgoing:(ExteriaOutgoing *)outgoing toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(ExteriaSendCompletion)completion;
- (void)sendSticker:(ExteriaMedia *)sticker toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(ExteriaSendCompletion)completion;
- (void)sendPhotoAtPath:(NSString *)path caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId completion:(ExteriaSendCompletion)completion;
- (void)sendVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs width:(int32_t)width height:(int32_t)height caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(ExteriaDialog *)dialog
               randomId:(long long)randomId completion:(ExteriaSendCompletion)completion;
- (void)sendDocumentAtPath:(NSString *)path name:(NSString *)name mime:(NSString *)mime caption:(NSString *)caption toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
                completion:(ExteriaSendCompletion)completion;
/* two to ten photos and videos as one album; each is uploaded, then one request sends them together, so the other
   side sees one collage. randomIds are the NSNumber random ids of the pending messages, one for each item in order */
- (void)sendAlbumOfOutgoings:(NSArray *)outgoings toDialog:(ExteriaDialog *)dialog randomIds:(NSArray *)randomIds completion:(void (^)(NSArray *messageIds, NSString *errorName))completion;
/* stops the upload of the pending message with this random id; the completion of its send then reports CANCELLED. A message the server
   already has is not recalled */
- (void)cancelSendWithRandomId:(long long)randomId;
- (void)sendLocationLatitude:(double)latitude longitude:(double)longitude toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
                  completion:(ExteriaSendCompletion)completion;
/* a jpeg becomes the profile photo of the signed in user: the file goes up in parts, then the server is told to
   use it */
- (void)uploadProfilePhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion;
/* a jpeg becomes a story of the signed in user, shown to everyone for a day, no caption; the completion is the same as the profile photo's */
- (void)postStoryPhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion;
/* the custom emoji documents with the ordinary emoji each stands for and the files that draw it, as
   ExteriaCustomEmojiDocument items; a document the server does not know is missing */
- (void)loadCustomEmojiDocuments:(NSArray *)documentIds completion:(void (^)(NSArray *documents, NSString *errorName))completion;
/* ordinary emoji choices permitted by this chat, as ExteriaReaction items */
/* a Premium account is also offered the custom emoji the chat allows: those it lists, and where it allows any, the account's favorites */
- (void)loadAvailableReactionsForDialog:(ExteriaDialog *)dialog premium:(BOOL)premium completion:(ExteriaListCompletion)completion;
/* returns the updated stored messages for these ids, including history outside the watched page */
- (void)refreshReactionsForMessages:(NSArray *)ids dialog:(ExteriaDialog *)dialog completion:(ExteriaListCompletion)completion;
- (void)sendReactions:(NSArray *)reactions messageId:(int32_t)messageId dialog:(ExteriaDialog *)dialog
           completion:(ExteriaListCompletion)completion;
/* tells the server everything up to maxId is read; a failure only shows in the log, the next open says it again */
- (void)markDialogRead:(ExteriaDialog *)dialog upTo:(int32_t)maxId;
- (void)markMentionsRead:(NSArray *)ids dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* messages.readMessageContents: the voice notes, round videos and one-time media of these messages count as played or opened; the ids are NSNumbers */
- (void)markContentsRead:(NSArray *)ids dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;

/* pin, mute or delete one chat on the server; the completion runs on the main thread with nil on success or the
   rpc error name */
typedef enum { ExteriaChatCommandPin, ExteriaChatCommandUnpin, ExteriaChatCommandMute, ExteriaChatCommandUnmute,
               ExteriaChatCommandDelete, ExteriaChatCommandClear,
               /* the swipe of the chat list: everything read (messages.readHistory), the manual "unread" mark put on, and that mark taken off */
               ExteriaChatCommandMarkRead, ExteriaChatCommandMarkUnread, ExteriaChatCommandClearUnreadMark } ExteriaChatCommand;
- (void)performAction:(ExteriaChatCommand)action onDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;

/* a search through every chat for the text: one ExteriaDialog per found message, naming the chat, with the found
   message as its last one, and the offset for the next page (zero when there is none) */
- (void)searchGlobal:(NSString *)query kind:(exteria_search_kind)kind offsetRate:(int32_t)offsetRate completion:(ExteriaSearchCompletion)completion;

/* the handler runs on the main thread with the newest stored messages of the chat, newest first, each time the
   store changed in a way that touches them; nil for dialog stops watching */
- (void)watchDialog:(ExteriaDialog *)dialog handler:(void (^)(NSArray *messages))handler;
/* includes the stored identities of the current page, keyed like ExteriaMessage.senderKey */
- (void)watchDialog:(ExteriaDialog *)dialog peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler;
/* the same for a screen that has to be able to stop only its own watch: the screens of a theme change overlap for a moment, and the one going must not stop the one
   that came */
- (void)watchDialog:(ExteriaDialog *)dialog owner:(id)owner peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler;
- (void)stopWatchingForOwner:(id)owner;
/* group roles and the users named by the answer, delivered on the main thread */
- (void)loadSenderRolesOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSDictionary *roles, NSDictionary *people, NSString *errorName))completion;
/* known users from the local store, indexed by their ids */
- (void)loadCachedPeopleWithIds:(NSArray *)ids completion:(void (^)(NSDictionary *people))completion;
/* a sender channel seen only as a min object, resolved through the message that named it */
- (void)loadChannelSender:(long long)channelId ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog
               completion:(void (^)(ExteriaPerson *person, NSString *errorName))completion;

/* ExteriaStickerSet items of the installed sets, ExteriaSticker items of one set, and of the recently used ones */
- (void)loadStickerSets:(ExteriaListCompletion)completion;
- (void)loadAnimatedEmojiStickers:(ExteriaListCompletion)completion;
- (void)loadStickersOfSet:(ExteriaStickerSet *)set completion:(ExteriaListCompletion)completion;
/* the stickers of a set the server names by its short name, in set order, whether or not the person has installed it */
- (void)loadStickersOfSetNamed:(NSString *)shortName completion:(ExteriaListCompletion)completion;
/* the custom emoji sets the person has installed as ExteriaStickerSet items, and the ExteriaCustomEmojiDocument items of one */
- (void)loadEmojiSets:(ExteriaListCompletion)completion;
- (void)loadEmojiOfSet:(ExteriaStickerSet *)set completion:(ExteriaListCompletion)completion;
- (void)loadRecentStickers:(ExteriaListCompletion)completion;
/* the stickers the person marked as favorites, and the animations they kept (ExteriaSticker items whose media is a GIF), newest first */
- (void)loadFavedStickers:(ExteriaListCompletion)completion;
- (void)loadSavedGifs:(ExteriaListCompletion)completion;
/* puts a sticker among the favorites or takes it out; the completion gets nil once the server took it */
- (void)faveSticker:(ExteriaSticker *)sticker unfave:(BOOL)unfave completion:(void (^)(NSString *errorName))completion;
/* empties the list of the stickers used lately */
- (void)clearRecentStickers:(void (^)(NSString *errorName))completion;
/* ExteriaSticker items the server suggests for a waving hand, the greetings an empty chat offers */
- (void)loadGreetingStickers:(ExteriaListCompletion)completion;

@end
