#import <Foundation/Foundation.h>

/* the language of the interface, and the names of languages */

extern NSString *const ExteriaLanguageDidChangeNotification;

/* a language the person added from a .strings file: the keys are the keys of the English texts of the app, and what a file does not translate stays English. its code is
   "x-" and the name of the file (letters, digits, - and _), which keeps it apart from the codes of real languages; the file may carry "language.name" (its own name),
   "language.english" (the name in English) and "language.base" (the real language it is written in, such as "de", which dates, plurals and the translator follow) */
NSArray *ExteriaCustomLanguageCodes(void);
BOOL ExteriaIsCustomLanguage(NSString *code);
/* reads, checks and stores the file; nil on success and the words for the person when it is refused: unreadable, too large, a name that is taken, no text of the app in it.
   texts whose placeholders differ from the English ones are left out, since a wrong one would crash the screen that shows it */
NSString *ExteriaInstallCustomLanguage(NSString *path, NSUInteger *accepted, NSUInteger *skipped);
/* forgets a custom language; when it was the one in force, the system language comes back */
void ExteriaRemoveCustomLanguage(NSString *code);
/* the English texts as a .strings file the person can translate, copied to a temporary file; nil when the bundle has none */
NSString *ExteriaCustomLanguageTemplatePath(void);

/* the lproj codes the app has texts for, in the order the language screen lists them */
NSArray *ExteriaInterfaceLanguageCodes(void);
/* what the person chose: a code from that list, or an empty string for the system */
NSString *ExteriaInterfaceLanguageChoice(void);
/* the code in force: the choice, or else the first language of the system that the app has, or English. The playful russian answers "ru" here, since it
   behaves as russian everywhere but in its texts */
NSString *ExteriaInterfaceLanguage(void);
/* the row of the language screen in force: the choice as it was made, the playful russian included, or else the same as ExteriaInterfaceLanguage */
NSString *ExteriaInterfaceLanguageVariant(void);
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
