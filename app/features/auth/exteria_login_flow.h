#import <UIKit/UIKit.h>

#import "exteria_country_book.h"
#import "exteria_form_controller.h"
#import "exteria_phone_controller.h"
#import "exteria_qr_controller.h"
#import "exteria_session.h"

@class ExteriaLoginFlow;

@protocol ExteriaLoginFlowDelegate <NSObject>
- (void)loginFlow:(ExteriaLoginFlow *)flow didAuthorizeUser:(long long)userId;
@end

/* walks the navigation stack through the phone, code, password and name screens as the login state
   machine asks for them; the welcome screen below the phone screen is not its business */
@interface ExteriaLoginFlow : NSObject <ExteriaPhoneControllerDelegate, ExteriaQrControllerDelegate, ExteriaFormControllerDelegate, ExteriaSessionDelegate> {
    id<ExteriaLoginFlowDelegate> _delegate;
}

@property (nonatomic, assign) id<ExteriaLoginFlowDelegate> delegate;

- (id)initWithNavigation:(UINavigationController *)navigation session:(ExteriaSession *)session
            countryBook:(ExteriaCountryBook *)book;
/* pushes the phone screen and takes over as the session delegate */
- (void)begin;
/* the same, but the first screen is the QR code, with the phone screen kept for the way to the number */
- (void)beginWithQr;

@end
