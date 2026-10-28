#import "exteria_session.h"

#include "exteria_mt_client.h"
#include "exteria_store.h"

@class ExteriaPerson;

/* the mask of what the settings of the person keep of deleted and edited messages */
uint32_t ExteriaSavingMask(void);

/* worker only: the kept deleted messages of a chat with ids from low to high */
NSMutableArray *ExteriaSavedDeletedOfPeer(exteria_store *store, exteria_peer peer, int32_t low, int32_t high);

/* how a request names a chat */
exteria_peer_ref ExteriaPeerRefOfDialog(ExteriaDialog *dialog);

/* users and channel senders keyed as in chat history, on the worker thread */
/* a person or channel seen in part (min) has no photo that can be fetched, so the one the store holds whole stands in for it; worker only, since it reads the store */
NSMutableDictionary *ExteriaPeopleOfAnswer(ExteriaSession *session, const exteria_tl_value *answer);

/* the entities of a message in the rows exteria_send_text_request reads, and the pool their link strings point into, which has to live as long as the rows */
NSMutableData *ExteriaPackSendEntities(NSArray *entities, NSMutableData **strings, size_t *count);

/* a send request built for chat: sets who it is sent as when the person chose another identity there */
exteria_status ExteriaApplySendAs(ExteriaSession *session, const exteria_peer_ref *chat, exteria_arena *arena, exteria_tl_value *request);

/* what the session's own files and its chat code share; nothing here is for screens */
@interface ExteriaSession (Internal)

/* runs the block on the worker thread */
- (void)post:(void (^)(void))block;
/* queues a request that the core built whole; the handler runs on the worker and must copy what it keeps */
- (void)invokeBuilt:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build
            handler:(void (^)(const exteria_mt_rpc_result *result))handler;
/* hands a finished load to the main thread, and queues the client restart when the key was revoked */
- (void)finishLoad:(NSArray *)items error:(NSString *)error completion:(ExteriaListCompletion)done;
/* a revoked key in an error name queues the client restart; worker only */
- (void)noteRpcError:(NSString *)error;
- (NSString *)folderFloodError;
- (void)rememberFolderFloodError:(NSString *)error;
/* worker only */
- (exteria_store *)workerStore;
/* worker only: what AyuMoments keeps of deleted and edited messages, a mask of EXTERIA_KEEP_ bits that the part handling the updates reads */
- (void)setKeepMask:(uint32_t)mask;
/* worker only: stores the messages of a history answer when deleted messages are kept */
- (void)keepMessagesOfAnswer:(const exteria_tl_value *)answer;
/* worker only: the upload of a pending message was stopped by the person; the next step of the upload reads it and forgets it at the end */
- (void)workerCancelSend:(long long)randomId;
- (BOOL)workerSendIsCancelled:(long long)randomId;
- (void)workerForgetSend:(long long)randomId;
- (int64_t)workerAccount;
- (int32_t)workerDc;
/* the next step of an upload runs on the worker; the declarations the chat code shares */
- (void)finishSend:(const exteria_mt_rpc_result *)result randomId:(long long)randomId completion:(ExteriaSendCompletion)done;
/* the observer runs on the worker each time the client changed the store; nil removes it; worker only */
- (void)setStoreObserver:(void (^)(void))observer;
/* the same, remembering whose it is, so that only the owner can take it away again; worker only */
- (void)setStoreObserver:(void (^)(void))observer owner:(void *)owner;
- (void)clearStoreObserverOwnedBy:(void *)owner;
- (void)storeChanged;
/* runs on the worker after every change the client made to the store, beside the observer above; nil removes it;
   worker only */
- (void)setChangeHook:(void (^)(void))hook;
/* where the session keeps its files; worker only */
- (NSString *)workerDirectory;

/* queues a request from code that already runs on the worker; the handler runs there too */
- (void)submitBuilt:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build
            handler:(void (^)(const exteria_mt_rpc_result *result))handler;
/* runs the block on the main thread */
- (void)deliverMain:(void (^)(void))block;
/* worker only: a stored user, or a stored channel for a negative key; nil when none is kept */
- (ExteriaPerson *)storedPersonWithKey:(int64_t)key;

@end
