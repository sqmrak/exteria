#import <UIKit/UIKit.h>

#import "exteria_country_book.h"
#import "exteria_country_controller.h"

@class ExteriaPhoneController;

@protocol ExteriaPhoneControllerDelegate <NSObject>
/* number is the full international form, a plus and digits only */
- (void)phoneController:(ExteriaPhoneController *)controller didSubmitNumber:(NSString *)number;
/* the link under the card: the person wants to log in with a QR code instead */
- (void)phoneControllerDidRequestQr:(ExteriaPhoneController *)controller;
@end

@interface ExteriaPhoneController : UIViewController <UITextFieldDelegate, ExteriaCountryControllerDelegate>

- (id)initWithCountryBook:(ExteriaCountryBook *)book;

@property (nonatomic, assign) id<ExteriaPhoneControllerDelegate> delegate;
/* the code request is out: Next and the fields stop answering until the result arrives */
@property (nonatomic, assign) BOOL busy;

@end
