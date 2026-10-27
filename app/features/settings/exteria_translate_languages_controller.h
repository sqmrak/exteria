#import "exteria_settings_kit.h"

typedef enum {
    /* one language to translate into, or the language of the app */
    ExteriaTranslateLanguagesTarget,
    /* the languages that get no Translate button */
    ExteriaTranslateLanguagesSkipped
} ExteriaTranslateLanguagesMode;

/* a list of the languages a translator knows, searchable; in the target mode a tap picks the language and leaves */
@interface ExteriaTranslateLanguagesController : ExteriaSettingsPageController

- (id)initWithMode:(ExteriaTranslateLanguagesMode)mode;

@end
