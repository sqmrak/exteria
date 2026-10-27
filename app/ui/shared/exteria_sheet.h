#import <UIKit/UIKit.h>

/* the modern look of a choice that waits for an answer */
@interface ExteriaSheet : UIView

/* handler gets the index of the option that was picked, after the sheet has left. destructive holds the indexes shown in red */
+ (void)presentInView:(UIView *)host title:(NSString *)title message:(NSString *)message options:(NSArray *)options destructive:(NSIndexSet *)destructive
          cancelTitle:(NSString *)cancelTitle handler:(void (^)(NSUInteger index))handler;

@end

/* asks whether to go on with something that cannot be undone (ExteriaConfirm of exteria_alert is the system alert
   alone) */
void ExteriaConfirmAction(UIViewController *host, NSString *message, NSString *actionTitle, void (^confirmed)(void));
