#import <Foundation/Foundation.h>

/* the settings of the translator; the numbers of the providers and of the model providers are those, so a stored
   choice means the same there */

typedef enum {
    ExteriaTranslateProviderGoogle = 1,
    ExteriaTranslateProviderYandex = 3,
    ExteriaTranslateProviderLingo = 4,
    ExteriaTranslateProviderBing = 5,
    ExteriaTranslateProviderDeepL = 7,
    ExteriaTranslateProviderTelegram = 8,
    ExteriaTranslateProviderTranSmart = 9,
    ExteriaTranslateProviderLLM = 10
} ExteriaTranslateProviderId;

typedef enum {
    ExteriaLlmPresetCustom = 0,
    ExteriaLlmPresetOpenAI = 1,
    ExteriaLlmPresetGoogleAIStudio = 2,
    ExteriaLlmPresetGroq = 3,
    ExteriaLlmPresetDeepSeek = 4,
    ExteriaLlmPresetXAI = 5,
    ExteriaLlmPresetCerebras = 6,
    ExteriaLlmPresetOllamaCloud = 7,
    ExteriaLlmPresetOpenRouter = 8,
    ExteriaLlmPresetVercelGateway = 9,
    ExteriaLlmPresetVertex = 10
} ExteriaLlmPreset;

/* the providers in the order of the list, as NSNumbers of ExteriaTranslateProviderId */
NSArray *ExteriaTranslateProviderList(void);
NSString *ExteriaTranslateProviderName(int provider);

/* the Translate button in the menu of a message, off until it is switched on */
BOOL ExteriaTranslateButtonEnabled(void);
void ExteriaTranslateSetButtonEnabled(BOOL on);

int ExteriaTranslateProviderChoice(void);
void ExteriaTranslateSetProviderChoice(int provider);

/* whether the original goes with the translation: 0 off, 1 manual only, 2 on */
int ExteriaTranslateOriginalMode(void);
void ExteriaTranslateSetOriginalMode(int mode);

/* the language to translate into: a code, or an empty string for the language of the app */
NSString *ExteriaTranslateTargetChoice(void);
void ExteriaTranslateSetTargetChoice(NSString *code);
/* the code in force: the choice, or else the language of the interface */
NSString *ExteriaTranslateTargetLanguage(void);

/* the codes of the languages that get no Translate button, lowercase; until the person picks some it is the
   language of the interface alone */
NSArray *ExteriaTranslateSkippedLanguages(void);
void ExteriaTranslateSetSkippedLanguages(NSArray *codes);
BOOL ExteriaTranslateSkips(NSString *code);

/* the languages offered first in the list of targets, as the person typed them ("ja, zh_cn") and as codes */
NSString *ExteriaTranslatePreferredText(void);
void ExteriaTranslateSetPreferredText(NSString *text);
NSArray *ExteriaTranslatePreferredLanguages(void);

/* keep the choices above when the language of the app changes; off, the new language of the app replaces the old one among the skipped languages */
BOOL ExteriaTranslateKeepsPreferences(void);
void ExteriaTranslateSetKeepsPreferences(BOOL on);
/* the app language changed from previous to current: moves the language of the interface among the skipped ones unless the preferences are kept */
void ExteriaTranslateInterfaceLanguageChanged(NSString *previous, NSString *current);

/* Google: a Cloud key sends the text to the cloud API, and the experimental switch picks the translate-pa endpoint over the one of the Google app */
NSString *ExteriaTranslateGoogleKey(void);
void ExteriaTranslateSetGoogleKey(NSString *key);
BOOL ExteriaTranslateGoogleNew(void);
void ExteriaTranslateSetGoogleNew(BOOL on);

/* DeepL: an own key, and the tone: 0 as it comes, 1 informal, 2 formal */
NSString *ExteriaTranslateDeepLKey(void);
void ExteriaTranslateSetDeepLKey(NSString *key);
int ExteriaTranslateDeepLFormality(void);
void ExteriaTranslateSetDeepLFormality(int formality);

/* the AI translator */
NSArray *ExteriaLlmPresetList(void);
NSString *ExteriaLlmPresetName(int preset);
int ExteriaLlmPresetChoice(void);
void ExteriaLlmSetPresetChoice(int preset);
/* the keys are kept apart for each provider; several keys may stand in one string, separated by commas */
NSString *ExteriaLlmKey(int preset);
void ExteriaLlmSetKey(int preset, NSString *key);
/* the model the person typed for the provider, empty for the default one */
NSString *ExteriaLlmSavedModel(int preset);
void ExteriaLlmSetModel(int preset, NSString *model);
NSString *ExteriaLlmDefaultModel(int preset);
NSString *ExteriaLlmModel(int preset);
/* the base address of the chat completions API: the one typed for a custom provider (the Gemini one when empty), the fixed one of a named provider */
NSString *ExteriaLlmCustomURL(void);
void ExteriaLlmSetCustomURL(NSString *url);
NSString *ExteriaLlmBaseURL(int preset);
/* "https://host/v1/" with the scheme added, the tail slashes and a trailing /chat/completions cut, or an empty string for text that is no address */
NSString *ExteriaLlmNormalizedURL(NSString *text);
NSString *ExteriaLlmSystemPrompt(void);
void ExteriaLlmSetSystemPrompt(NSString *text);
NSString *ExteriaLlmUserPrompt(void);
void ExteriaLlmSetUserPrompt(NSString *text);
float ExteriaLlmTemperature(void);
void ExteriaLlmSetTemperature(float value);
BOOL ExteriaLlmUsesContext(void);
void ExteriaLlmSetUsesContext(BOOL on);
/* the index in the list 1, 3, 5, 7, 10 of messages sent as context */
int ExteriaLlmContextIndex(void);
void ExteriaLlmSetContextIndex(int index);
int ExteriaLlmContextCount(void);
NSArray *ExteriaLlmContextCounts(void);
/* whether the model takes a temperature: not the GPT-5 family and not the newer Gemini models, which reject the
   field */
BOOL ExteriaLlmSupportsTemperature(int preset, NSString *model);
