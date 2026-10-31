#import <Foundation/Foundation.h>

/* what a language pack named by a t.me/setlanguage link means for the app, whose texts live in its own bundle and not on the server */

/* the code of the interface language a pack code stands for ("ru", "pt_BR" in the form the server writes it), nil when the app has no texts in it. the languages
   a person added from a file never match, their codes are not the ones of the server */
NSString *ExteriaInterfaceLanguageForPackCode(NSString *packCode);

/* how many of the English texts of the app a language translates, as a share from 0 to 100 rounded up; 0 for a code the app has no texts for */
int ExteriaInterfaceLanguageCompleteness(NSString *code);
