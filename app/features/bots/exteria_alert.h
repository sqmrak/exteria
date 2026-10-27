#import <Foundation/Foundation.h>

/* the index of the button pressed, counted in the order the titles were given, and the text of the field when the alert has one */
typedef void (^ExteriaAlertHandler)(NSInteger index, NSString *text);

/* an alert with any number of buttons that reports the choice to a block */
void ExteriaShowAlert(NSString *title, NSString *message, NSArray *buttons, NSInteger cancelIndex, BOOL secure, ExteriaAlertHandler handler);

/* a message with one button */
void ExteriaShowNotice(NSString *title, NSString *message);

/* a question with a confirming button and a cancel one; the handler runs only for the confirming one */
void ExteriaConfirm(NSString *title, NSString *message, NSString *confirmTitle, void (^handler)(void));

/* a list of choices on a sheet, with a cancel at the end; the handler gets the index of the choice, not of the
   cancel */
void ExteriaChoose(NSString *title, NSArray *choices, NSInteger destructiveIndex, void (^handler)(NSInteger index));

/* the same, and cancelled runs when the question is turned down instead (Cancel, or the application going to the background) */
void ExteriaPromptTextOrCancel(NSString *title, NSString *message, NSString *initial, NSString *placeholder, void (^handler)(NSString *text), void (^cancelled)(void));

/* a question with one text field filled with initial; the handler runs with the text only when OK is pressed, and with an empty string for an emptied field */
void ExteriaPromptText(NSString *title, NSString *message, NSString *initial, NSString *placeholder, void (^handler)(NSString *text));
