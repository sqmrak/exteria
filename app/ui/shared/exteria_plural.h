#import <Foundation/Foundation.h>

/* which plural form of a word a count takes in the language of the interface; Russian has "one" after a last digit
   of 1, "few" after 2 to 4, and "other" otherwise, except 11 to 14 */
NSString *ExteriaPluralForm(NSInteger count);
