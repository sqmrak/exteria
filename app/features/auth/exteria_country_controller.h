#import <UIKit/UIKit.h>

#import "exteria_country_book.h"

@class ExteriaCountryController;

@protocol ExteriaCountryControllerDelegate <NSObject>
- (void)countryController:(ExteriaCountryController *)controller didPickCountry:(ExteriaCountry *)country;
- (void)countryControllerDidCancel:(ExteriaCountryController *)controller;
@end

/* the country list with search, shown over the phone screen */
@interface ExteriaCountryController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (id)initWithCountryBook:(ExteriaCountryBook *)book;

@property (nonatomic, assign) id<ExteriaCountryControllerDelegate> delegate;

@end
