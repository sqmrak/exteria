#import <UIKit/UIKit.h>

typedef enum {
    ExteriaFormKindCode,
    ExteriaFormKindPassword,
    ExteriaFormKindName
} ExteriaFormKind;

@class ExteriaFormController;

@protocol ExteriaFormControllerDelegate <NSObject>
/* one string per field; the name form sends the first and the last name */
- (void)formController:(ExteriaFormController *)controller didSubmitValues:(NSArray *)values;
- (void)formControllerDidTapAction:(ExteriaFormController *)controller;
- (void)formControllerDidGoBack:(ExteriaFormController *)controller;
@end

/* the code, password and name screens of the login: a title, a message, a card of fields,
   an error line and one action under it */
@interface ExteriaFormController : UIViewController <UITextFieldDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, assign) id<ExteriaFormControllerDelegate> delegate;
@property (nonatomic, copy) NSString *heading;
@property (nonatomic, copy) NSString *message;
/* the password form's placeholder: the hint the person left for the password, or nil for the plain word */
@property (nonatomic, copy) NSString *fieldHint;
/* the code form submits by itself when this many digits are typed; zero leaves it to the Next button */
@property (nonatomic, assign) NSInteger codeLength;
/* the request is out: fields and buttons stop answering until the result arrives */
@property (nonatomic, assign) BOOL busy;

- (id)initWithKind:(ExteriaFormKind)kind;
/* an empty or nil text clears the line */
- (void)showError:(NSString *)text;
- (void)clearFields;
/* a nil title hides the action; seconds above zero show a countdown and keep the action off until it ends */
- (void)setActionTitle:(NSString *)title waitSeconds:(NSInteger)seconds;

@end
