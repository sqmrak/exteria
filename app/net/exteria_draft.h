#import <Foundation/Foundation.h>

#import "exteria_dialog.h"

#include "exteria_drafts.h"

/* posted on the main thread, with the board as the object, when the draft of a chat or topic changed. userInfo has kind, peer and top (numbers) and
   local (a bool): whether the person edited it on this phone, which is NO for a change that came from the account */
extern NSString *const ExteriaDraftDidChangeNotification;

/* a message typed and not sent: what the field holds, and the message it answers; immutable */
@interface ExteriaDraft : NSObject {
    NSString *_text;
    NSArray *_entities;
    int32_t _replyTo;
    BOOL _noWebpage;
    int32_t _date;
}
@property (nonatomic, readonly, copy) NSString *text;
/* ExteriaTextEntity items, offsets counted in the text; the ones the field cannot show are left out */
@property (nonatomic, readonly, retain) NSArray *entities;
@property (nonatomic, readonly) int32_t replyTo;
@property (nonatomic, readonly) BOOL noWebpage;
@property (nonatomic, readonly) int32_t date;

- (id)initWithText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo noWebpage:(BOOL)noWebpage date:(int32_t)date;
/* nil for a row that keeps nothing */
+ (ExteriaDraft *)draftWithRow:(const exteria_draft *)row;
/* nothing in it: no words and no message to answer */
@property (nonatomic, readonly) BOOL empty;
@end

/* the drafts of the account's chats as the screens see them: filled from the chat lists and the live updates, and by what the person types here. A draft
   the person changed on this phone stands over the account's word until the account has it */
@interface ExteriaDraftBoard : NSObject {
    NSMutableDictionary *_drafts;
    NSCountedSet *_unsaved;
}

/* main thread only; topic is the forum topic, zero for the whole chat */
- (ExteriaDraft *)draftForKind:(int32_t)kind peer:(long long)peer top:(int32_t)top;
- (ExteriaDraft *)draftForDialog:(ExteriaDialog *)dialog;
/* the person edited it here; nil or an empty draft removes it. The screen sends it to the account */
- (void)setLocalDraft:(ExteriaDraft *)draft kind:(int32_t)kind peer:(long long)peer top:(int32_t)top;
/* one save of the person's draft came back, whether the account took it or not; its word counts again when every save is back */
- (void)noteSavedKind:(int32_t)kind peer:(long long)peer top:(int32_t)top;
/* the account says what the draft of a chat is, nil for none: a live update, or the answer of a list. Ignored while a draft of the person is on its way to
   the account */
- (void)noteAccountDraft:(ExteriaDraft *)draft kind:(int32_t)kind peer:(long long)peer top:(int32_t)top;
/* a list of chats listed these chats with these drafts (NSNull for none). A list from the account takes the drafts as they are, those it lists without
   one included; a kept list (complete NO) only adds drafts the board does not have. entries are arrays of kind, peer, top and draft */
- (void)noteListed:(NSArray *)entries complete:(BOOL)complete;
/* every draft goes: the account was told to delete them */
- (void)removeAll;

@end

/* whether the change a notification reports is the draft of the chat or topic of this row */
BOOL ExteriaDraftChangeConcerns(NSNotification *note, ExteriaDialog *dialog);
/* the draft a row of the chat list shows, or nil: the words are not empty, the chat is one that can be written in, and the last message is not newer than
   the draft while there is something unread */
ExteriaDraft *ExteriaVisibleDraft(ExteriaDraftBoard *board, ExteriaDialog *dialog);
/* the moment a row is ordered by: the last message, or the draft when that is newer */
int32_t ExteriaDialogSortDate(ExteriaDraftBoard *board, ExteriaDialog *dialog);
/* the list with the chat of the notification moved to where its date puts it; the same array when nothing moves. Pinned chats and the archive entry stay */
NSArray *ExteriaDialogsMovedForDraft(NSArray *dialogs, ExteriaDraftBoard *board, int32_t kind, long long peer, int32_t top);
/* the words a row shows after "Draft:": line breaks are spaces and the length is bounded */
NSString *ExteriaDraftPreviewText(ExteriaDraft *draft);
