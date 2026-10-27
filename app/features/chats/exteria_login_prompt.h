#import <UIKit/UIKit.h>

#import "exteria_session.h"

/* the card at the top of the chat list that asks whether a login from another device was the owner's; main thread
   only */
@interface ExteriaLoginPrompt : NSObject

/* changed runs when the card appears or goes, so the list can lay its header out again; it must not keep the list alive */
- (id)initWithSession:(ExteriaSession *)session changed:(void (^)(void))changed;
/* the card's view, to put in the header; it is hidden while there is nothing to ask */
@property (nonatomic, readonly) UIView *view;
/* zero while there is nothing to ask */
- (CGFloat)heightForWidth:(CGFloat)width;
/* puts the card at y in a header of this width */
- (void)layoutInWidth:(CGFloat)width atY:(CGFloat)y;
/* asks the server, at most once in half a minute */
- (void)refresh;

@end
