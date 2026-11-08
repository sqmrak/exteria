#import <UIKit/UIKit.h>

/* the alert of the modern style: a card of the application in place of the system alert, with the calls of UIAlertView that the application makes (a title, a message, buttons, one
   field of text and the delegate that hears the answer), so a place that asks for its class through ExteriaAlertClass() takes the card in one style and the system alert in the other */
@interface ExteriaAlertView : UIView <UITextFieldDelegate>

- (id)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate cancelButtonTitle:(NSString *)cancelTitle otherButtonTitles:(NSString *)first, ... NS_REQUIRES_NIL_TERMINATION;

@property (nonatomic, assign) id delegate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
/* the button that is the way out, -1 for none; it reads in the plain weight and the others in the strong one */
@property (nonatomic, assign) NSInteger cancelButtonIndex;
/* 0 no field, 1 a field for a secret, 2 a field of plain text, as UIAlertViewStyle numbers them */
@property (nonatomic, assign) NSInteger alertViewStyle;
@property (nonatomic, readonly) NSInteger numberOfButtons;

- (NSInteger)addButtonWithTitle:(NSString *)title;
- (NSString *)buttonTitleAtIndex:(NSInteger)index;
- (UITextField *)textFieldAtIndex:(NSInteger)index;
- (void)show;
- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated;

@end

/* the class that asks a question for the style on screen: the card of the application in the modern style and UIAlertView in the classic one */
Class ExteriaAlertClass(void);
