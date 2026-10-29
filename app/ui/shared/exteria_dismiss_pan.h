#import <UIKit/UIKit.h>

@protocol ExteriaDismissPanGuard <NSObject>
- (BOOL)exteriaCanDismissByPan;
@end

/* a downward pull closes a card; scrolling content may start a pull only at its top */
void ExteriaAddDismissPan(UIView *card, id target, SEL action);
