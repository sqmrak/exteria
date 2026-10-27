#import <UIKit/UIKit.h>
#import "exteria_avatar_cache.h"
#import "exteria_message.h"

/* the same bounded chip layout supplies row heights and the touch controls */
CGFloat ExteriaReactionsHeight(NSArray *reactions, CGFloat width, BOOL counts);
/* the same layout for a row that shares its bubble with the time: the height, the width the widest row takes, and the width of the last row, which is
   what the time has to fit beside */
CGFloat ExteriaReactionsMetrics(NSArray *reactions, CGFloat width, BOOL counts, CGFloat *used, CGFloat *lastRow);

@interface ExteriaReactionsView : UIView {
    NSArray *_reactions;
    NSArray *_buttons;
    BOOL _counts;
    BOOL _alignRight;
    BOOL _inBubble;
    BOOL _outgoing;
    void (^_pickHandler)(ExteriaReaction *reaction);
    ExteriaAvatarCache *_avatars;
}
@property (nonatomic, assign) BOOL alignRight;
/* the chips sit in the bubble of a message; translucent over the bubble color, since the card color of the free
   standing chips would vanish on the bubble of our own messages. outgoing tells which bubble it is */
@property (nonatomic, assign) BOOL inBubble;
@property (nonatomic, assign) BOOL outgoing;
/* where the pictures of the faces on the chips come from; without it a chip with faces shows the colors and initials */
@property (nonatomic, assign) ExteriaAvatarCache *avatars;
@property (nonatomic, copy) void (^pickHandler)(ExteriaReaction *reaction);
- (void)setReactions:(NSArray *)reactions counts:(BOOL)counts;
/* animated: a chip that is new, or whose count changed since the last call, pops in with an overshoot */
- (void)setReactions:(NSArray *)reactions counts:(BOOL)counts animated:(BOOL)animated;
/* a chip of a reaction that was taken away is still shrinking out of view */
- (BOOL)animatingOut;

@end
