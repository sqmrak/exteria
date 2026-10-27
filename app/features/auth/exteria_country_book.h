#import <UIKit/UIKit.h>

@interface ExteriaCountry : NSObject
@property (nonatomic, readonly) NSString *iso;
@property (nonatomic, readonly) NSString *code;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *pattern;
@end

/* the dial codes, names and flags the phone screens share */
@interface ExteriaCountryBook : NSObject

/* nil when the bundled list does not parse; the failure is logged */
- (id)init;

/* sorted by the name in the current language */
@property (nonatomic, readonly) NSArray *countries;

- (ExteriaCountry *)countryForISO:(NSString *)iso;

/* the country whose dial code is the longest start of digits, and how many digits that code takes */
- (ExteriaCountry *)countryForDigits:(NSString *)digits codeLength:(NSUInteger *)codeLength;

/* the country of the current locale, or the first entry with that dial code of 1 */
- (ExteriaCountry *)localCountry;

- (UIImage *)flagForCountry:(ExteriaCountry *)country;

@end
