#import <Foundation/Foundation.h>

/* the language of the interface, and the names of languages */

extern NSString *const ExteriaLanguageDidChangeNotification;

/* the lproj codes the app has texts for, in the order the language screen lists them */
NSArray *ExteriaInterfaceLanguageCodes(void);
/* what the person chose: a code from that list, or an empty string for the system */
NSString *ExteriaInterfaceLanguageChoice(void);
/* the code in force: the choice, or else the first language of the system that the app has, or English */
NSString *ExteriaInterfaceLanguage(void);
/* stores the choice (empty for the system) and makes the main bundle answer in it; posts ExteriaLanguageDidChangeNotification */
void ExteriaSetInterfaceLanguage(NSString *code);
/* puts the stored choice in force; called once at launch, before any text is asked for */
void ExteriaApplyInterfaceLanguage(void);

/* the locale that dates and times are written in; the one of the system, unless the language of the interface is
   another than the system's, in which case it is the locale of that language, so a Russian app on an English phone
   does not name its weekdays in English */
NSLocale *ExteriaFormattingLocale(void);

/* the codes a translator can aim at: the list of Google and Telegram, which the other services take whole or in part */
NSArray *ExteriaTranslationLanguageCodes(void);
/* the name of a language code in the language of the interface ("ru" gives "русский" in Russian and "Russian" in
   English), capitalized; the code itself when the system has no name for it */
NSString *ExteriaLanguageName(NSString *code);
/* the name of a language in its own language, for the list of interface languages */
NSString *ExteriaNativeLanguageName(NSString *code);

/* the name of a language in English, the line under the native name on the language screen */
NSString *ExteriaEnglishLanguageName(NSString *code);

/* a code in the one form the app compares: lowercase, with a dash ("zh_CN" gives "zh-cn") */
NSString *ExteriaNormalizedLanguageCode(NSString *code);
/* the language a text is written in, as a code, guessed from its letters */
NSString *ExteriaGuessLanguageOfText(NSString *text);
