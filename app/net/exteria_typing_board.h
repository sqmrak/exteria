#import <Foundation/Foundation.h>

#import "exteria_dialog.h"

/* posted on the main thread, with the board as the object, whenever someone starts or stops typing or an action
   runs out */
extern NSString *const ExteriaTypingDidChangeNotification;

/* whether the change that the notification reports shows in the dialog: its chat is the one that changed; a
   notification without a chat concerns every dialog */
BOOL ExteriaTypingChangeConcerns(NSNotification *note, ExteriaDialog *dialog);

/* who is typing where, kept for as long as the server's word holds: an action that is not repeated runs out after
   a few seconds, and a cancel ends it at once */
@interface ExteriaTypingBoard : NSObject {
    NSMutableArray *_entries;
    BOOL _timerSet;
}

/* kind is 1 for a user, 2 for a basic group, 3 for a channel; action is an exteria_typing_action, and EXTERIA_TYPING_CANCEL takes the person out; top is
   the topic or thread, zero for none */
- (void)noteKind:(int32_t)kind peer:(long long)peer user:(long long)user action:(int)action top:(int32_t)top;
/* the same with the name of the person, which a group shows before the words; nil when it is not known */
- (void)noteKind:(int32_t)kind peer:(long long)peer user:(long long)user action:(int)action top:(int32_t)top name:(NSString *)name;
/* the names of the people acting in the chat, in the order they started, as many as are known; those of a person whose name was not given are left out */
- (NSArray *)namesInDialog:(ExteriaDialog *)dialog;
/* how many people are typing something in the chat, or in the topic when the dialog is one */
- (NSUInteger)countInDialog:(ExteriaDialog *)dialog;
/* the action to show for the chat: typing first, then the others in the order they started; EXTERIA_TYPING_CANCEL when no one is acting */
- (int)actionInDialog:(ExteriaDialog *)dialog;

@end
