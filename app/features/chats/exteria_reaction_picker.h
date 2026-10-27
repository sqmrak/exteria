#import <UIKit/UIKit.h>
#import "exteria_media_cache.h"
#import "exteria_message.h"
#import "exteria_session.h"

/* the whole list of reactions as a card that opens from the message it is for: the reactions the chat allows first, and after them the custom emoji
   sets of the account, chosen by the tabs at the top of the card; the screen behind it is blurred */
@interface ExteriaReactionPicker : UIView {
    void (^_pickHandler)(ExteriaReaction *reaction);
    void (^_customPickHandler)(ExteriaCustomEmojiDocument *emoji);
    void (^_cancelHandler)(void);
    void (^_retryHandler)(void);
}
@property (nonatomic, copy) void (^pickHandler)(ExteriaReaction *reaction);
/* a custom emoji of a set was tapped; the owner decides whether the account may send it as a reaction */
@property (nonatomic, copy) void (^customPickHandler)(ExteriaCustomEmojiDocument *emoji);
@property (nonatomic, copy) void (^cancelHandler)(void);
@property (nonatomic, copy) void (^retryHandler)(void);
/* the part of the message that is on screen, in the coordinates of the picker, and which side it is on: the card opens under it, or over it when
   there is no room, on the side of the bubble; an empty rect centers the card */
@property (nonatomic, assign) CGRect anchorRect;
@property (nonatomic, assign) BOOL anchorOutgoing;
/* the sets come from the session; a free account sees them with a lock */
- (void)attachSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media premium:(BOOL)premium;
- (void)setReactions:(NSArray *)reactions;
- (void)setFailure:(NSString *)error;
- (void)setLoading;
- (void)dismissAnimated:(BOOL)animated;
@end
