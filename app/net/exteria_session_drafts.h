#import <Foundation/Foundation.h>

#import "exteria_draft.h"
#import "exteria_session.h"

/* the drafts: what the person types and has not sent is kept by the account, so it follows them to every phone */
@interface ExteriaSession (Drafts)

/* the draft of a chat or topic is now this (an empty text and no reply clear it). The board has it at once, and the account within a moment; main thread */
- (void)saveDraftText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo noWebpage:(BOOL)noWebpage forDialog:(ExteriaDialog *)dialog;

/* worker only: the drafts a chat list answer carries go to the board; complete is NO for the answer the last run kept */
- (void)noteDraftsOfDialogsAnswer:(const exteria_tl_value *)answer complete:(BOOL)complete;
/* worker only: the same for the topics of a forum */
- (void)noteDraftsOfTopicsAnswer:(const exteria_tl_value *)answer forum:(ExteriaDialog *)forum;
/* worker only: an updateDraftMessage of the account */
- (void)noteDraftUpdate:(const exteria_tl_value *)update;
/* worker only: asks for every draft of the account once per run; they come back as updates */
- (void)requestAllDraftsOnce;

@end
