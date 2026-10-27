#import "exteria_translate_config.h"

#import "exteria_language.h"

#include "exteria_translate_llm.h"

static NSString *const ExteriaTrPrefix = @"exteria.tr.";

static NSUserDefaults *ExteriaTrDefaults(void) {
    return [NSUserDefaults standardUserDefaults];
}

static NSString *ExteriaTrKey(NSString *name) {
    return [ExteriaTrPrefix stringByAppendingString:name];
}

static NSString *ExteriaTrString(NSString *name) {
    NSString *value = [ExteriaTrDefaults() stringForKey:ExteriaTrKey(name)];
    return value ? value : @"";
}

static void ExteriaTrSetString(NSString *name, NSString *value) {
    NSString *kept = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (kept.length) [ExteriaTrDefaults() setObject:kept forKey:ExteriaTrKey(name)];
    else [ExteriaTrDefaults() removeObjectForKey:ExteriaTrKey(name)];
}

static BOOL ExteriaTrBool(NSString *name, BOOL fallback) {
    id value = [ExteriaTrDefaults() objectForKey:ExteriaTrKey(name)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static void ExteriaTrSetBool(NSString *name, BOOL value) {
    [ExteriaTrDefaults() setBool:value forKey:ExteriaTrKey(name)];
}

static int ExteriaTrInt(NSString *name, int fallback) {
    id value = [ExteriaTrDefaults() objectForKey:ExteriaTrKey(name)];
    return [value isKindOfClass:[NSNumber class]] ? [value intValue] : fallback;
}

static void ExteriaTrSetInt(NSString *name, int value) {
    [ExteriaTrDefaults() setInteger:value forKey:ExteriaTrKey(name)];
}

#pragma mark providers

NSArray *ExteriaTranslateProviderList(void) {
    return [NSArray arrayWithObjects:[NSNumber numberWithInt:ExteriaTranslateProviderGoogle], [NSNumber numberWithInt:ExteriaTranslateProviderYandex],
            [NSNumber numberWithInt:ExteriaTranslateProviderLingo], [NSNumber numberWithInt:ExteriaTranslateProviderBing],
            [NSNumber numberWithInt:ExteriaTranslateProviderDeepL],
            [NSNumber numberWithInt:ExteriaTranslateProviderTelegram], [NSNumber numberWithInt:ExteriaTranslateProviderTranSmart],
            [NSNumber numberWithInt:ExteriaTranslateProviderLLM], nil];
}

NSString *ExteriaTranslateProviderName(int provider) {
    switch (provider) {
    case ExteriaTranslateProviderYandex: return NSLocalizedString(@"tr.provider.yandex", nil);
    case ExteriaTranslateProviderLingo: return NSLocalizedString(@"tr.provider.lingo", nil);
    case ExteriaTranslateProviderBing: return NSLocalizedString(@"tr.provider.bing", nil);
    case ExteriaTranslateProviderDeepL: return NSLocalizedString(@"tr.provider.deepl", nil);
    case ExteriaTranslateProviderTelegram: return NSLocalizedString(@"tr.provider.telegram", nil);
    case ExteriaTranslateProviderTranSmart: return NSLocalizedString(@"tr.provider.transmart", nil);
    case ExteriaTranslateProviderLLM: return NSLocalizedString(@"tr.provider.llm", nil);
    default: return NSLocalizedString(@"tr.provider.google", nil);
    }
}

BOOL ExteriaTranslateButtonEnabled(void) { return ExteriaTrBool(@"show", NO); }
void ExteriaTranslateSetButtonEnabled(BOOL on) { ExteriaTrSetBool(@"show", on); }

int ExteriaTranslateProviderChoice(void) {
    int stored = ExteriaTrInt(@"provider", ExteriaTranslateProviderGoogle);
    return [ExteriaTranslateProviderList() containsObject:[NSNumber numberWithInt:stored]] ? stored : ExteriaTranslateProviderGoogle;
}

void ExteriaTranslateSetProviderChoice(int provider) { ExteriaTrSetInt(@"provider", provider); }

int ExteriaTranslateOriginalMode(void) {
    int mode = ExteriaTrInt(@"original", 0);
    return mode >= 0 && mode <= 2 ? mode : 0;
}

void ExteriaTranslateSetOriginalMode(int mode) { ExteriaTrSetInt(@"original", mode); }

#pragma mark languages

NSString *ExteriaTranslateTargetChoice(void) { return ExteriaTrString(@"target"); }
void ExteriaTranslateSetTargetChoice(NSString *code) { ExteriaTrSetString(@"target", code); }

NSString *ExteriaTranslateTargetLanguage(void) {
    NSString *choice = ExteriaTranslateTargetChoice();
    return choice.length ? choice : ExteriaInterfaceLanguage();
}

NSArray *ExteriaTranslateSkippedLanguages(void) {
    NSArray *stored = [ExteriaTrDefaults() arrayForKey:ExteriaTrKey(@"skipped")];
    if (!stored) return [NSArray arrayWithObject:ExteriaInterfaceLanguage()];
    NSMutableArray *codes = [NSMutableArray array];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]] && [item length]) [codes addObject:[item lowercaseString]];
    }
    return codes;
}

void ExteriaTranslateSetSkippedLanguages(NSArray *codes) {
    /* the language of the interface alone is what no choice at all means, so it is not stored */
    if (codes.count == 1 && [[codes objectAtIndex:0] isEqualToString:ExteriaInterfaceLanguage()]) {
        [ExteriaTrDefaults() removeObjectForKey:ExteriaTrKey(@"skipped")];
        return;
    }
    [ExteriaTrDefaults() setObject:codes forKey:ExteriaTrKey(@"skipped")];
}

BOOL ExteriaTranslateSkips(NSString *code) {
    if (!code.length) return NO;
    NSString *wanted = ExteriaNormalizedLanguageCode(code);
    for (NSString *skipped in ExteriaTranslateSkippedLanguages()) {
        if ([ExteriaNormalizedLanguageCode(skipped) isEqualToString:wanted]) return YES;
    }
    return NO;
}

NSString *ExteriaTranslatePreferredText(void) { return ExteriaTrString(@"preferred"); }
void ExteriaTranslateSetPreferredText(NSString *text) { ExteriaTrSetString(@"preferred", text); }

NSArray *ExteriaTranslatePreferredLanguages(void) {
    NSMutableArray *codes = [NSMutableArray array];
    for (NSString *part in [ExteriaTranslatePreferredText() componentsSeparatedByString:@","]) {
        NSString *code = ExteriaNormalizedLanguageCode([part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
        if (code.length && ![codes containsObject:code]) [codes addObject:code];
    }
    return codes;
}

BOOL ExteriaTranslateKeepsPreferences(void) { return ExteriaTrBool(@"keep", NO); }
void ExteriaTranslateSetKeepsPreferences(BOOL on) { ExteriaTrSetBool(@"keep", on); }

void ExteriaTranslateInterfaceLanguageChanged(NSString *previous, NSString *current) {
    if (ExteriaTranslateKeepsPreferences() || [previous isEqualToString:current]) return;
    /* the list is read with the old language of the interface as its default before the new one is stored */
    NSMutableArray *codes = [NSMutableArray array];
    BOOL stored = [ExteriaTrDefaults() arrayForKey:ExteriaTrKey(@"skipped")] != nil;
    if (stored) [codes addObjectsFromArray:ExteriaTranslateSkippedLanguages()];
    else if (previous.length) [codes addObject:previous];
    if (previous.length && current.length && [codes containsObject:previous] && ![codes containsObject:current]) [codes removeObject:previous];
    if (current.length && ![codes containsObject:current]) [codes addObject:current];
    ExteriaTranslateSetSkippedLanguages(codes);
}

#pragma mark google and deepl

NSString *ExteriaTranslateGoogleKey(void) { return ExteriaTrString(@"google.key"); }
void ExteriaTranslateSetGoogleKey(NSString *key) { ExteriaTrSetString(@"google.key", key); }
BOOL ExteriaTranslateGoogleNew(void) { return ExteriaTrBool(@"google.new", YES); }
void ExteriaTranslateSetGoogleNew(BOOL on) { ExteriaTrSetBool(@"google.new", on); }

NSString *ExteriaTranslateDeepLKey(void) { return ExteriaTrString(@"deepl.key"); }
void ExteriaTranslateSetDeepLKey(NSString *key) { ExteriaTrSetString(@"deepl.key", key); }

int ExteriaTranslateDeepLFormality(void) {
    int value = ExteriaTrInt(@"deepl.formality", 0);
    return value >= 0 && value <= 2 ? value : 0;
}

void ExteriaTranslateSetDeepLFormality(int formality) { ExteriaTrSetInt(@"deepl.formality", formality); }

#pragma mark ai translator

NSArray *ExteriaLlmPresetList(void) {
    int order[] = {ExteriaLlmPresetCustom, ExteriaLlmPresetOpenAI, ExteriaLlmPresetGoogleAIStudio, ExteriaLlmPresetVertex, ExteriaLlmPresetGroq,
                   ExteriaLlmPresetDeepSeek, ExteriaLlmPresetXAI, ExteriaLlmPresetCerebras, ExteriaLlmPresetOllamaCloud, ExteriaLlmPresetOpenRouter,
                   ExteriaLlmPresetVercelGateway};
    NSMutableArray *list = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(order) / sizeof(order[0]); ++i) [list addObject:[NSNumber numberWithInt:order[i]]];
    return list;
}

NSString *ExteriaLlmPresetName(int preset) {
    switch (preset) {
    case ExteriaLlmPresetOpenAI: return @"OpenAI";
    case ExteriaLlmPresetGoogleAIStudio: return @"Google AI Studio";
    case ExteriaLlmPresetVertex: return @"Google Vertex";
    case ExteriaLlmPresetGroq: return @"Groq";
    case ExteriaLlmPresetDeepSeek: return @"DeepSeek";
    case ExteriaLlmPresetXAI: return @"SpaceXAI";
    case ExteriaLlmPresetCerebras: return @"Cerebras";
    case ExteriaLlmPresetOllamaCloud: return @"Ollama";
    case ExteriaLlmPresetOpenRouter: return @"OpenRouter";
    case ExteriaLlmPresetVercelGateway: return @"Vercel AI Gateway";
    default: return NSLocalizedString(@"tr.llm.custom", nil);
    }
}

int ExteriaLlmPresetChoice(void) {
    int stored = ExteriaTrInt(@"llm.preset", ExteriaLlmPresetCustom);
    return [ExteriaLlmPresetList() containsObject:[NSNumber numberWithInt:stored]] ? stored : ExteriaLlmPresetCustom;
}

void ExteriaLlmSetPresetChoice(int preset) { ExteriaTrSetInt(@"llm.preset", preset); }

NSString *ExteriaLlmKey(int preset) { return ExteriaTrString([NSString stringWithFormat:@"llm.key.%d", preset]); }
void ExteriaLlmSetKey(int preset, NSString *key) { ExteriaTrSetString([NSString stringWithFormat:@"llm.key.%d", preset], key); }

NSString *ExteriaLlmSavedModel(int preset) { return ExteriaTrString([NSString stringWithFormat:@"llm.model.%d", preset]); }
void ExteriaLlmSetModel(int preset, NSString *model) { ExteriaTrSetString([NSString stringWithFormat:@"llm.model.%d", preset], model); }

NSString *ExteriaLlmDefaultModel(int preset) {
    switch (preset) {
    case ExteriaLlmPresetOpenAI: return @"gpt-5.6-luna";
    case ExteriaLlmPresetGoogleAIStudio: return @"gemini-flash-lite-latest";
    case ExteriaLlmPresetVertex: return @"gemini-3.5-flash-lite";
    case ExteriaLlmPresetGroq: return @"openai/gpt-oss-120b";
    case ExteriaLlmPresetDeepSeek: return @"deepseek-v4-flash";
    case ExteriaLlmPresetXAI: return @"";
    case ExteriaLlmPresetCerebras: return @"gpt-oss-120b";
    case ExteriaLlmPresetOllamaCloud: return @"gemma4:31b";
    case ExteriaLlmPresetOpenRouter: return @"openrouter/free";
    case ExteriaLlmPresetVercelGateway: return @"google/gemma-4-31b-it";
    default: return NSLocalizedString(@"tr.llm.model.default", nil);
    }
}

NSString *ExteriaLlmModel(int preset) {
    NSString *saved = ExteriaLlmSavedModel(preset);
    return saved.length ? saved : ExteriaLlmDefaultModel(preset);
}

NSString *ExteriaLlmCustomURL(void) { return ExteriaTrString(@"llm.url"); }
void ExteriaLlmSetCustomURL(NSString *url) { ExteriaTrSetString(@"llm.url", ExteriaLlmNormalizedURL(url)); }

NSString *ExteriaLlmNormalizedURL(NSString *text) {
    NSString *url = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!url.length) return @"";
    NSString *lower = [url lowercaseString];
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) url = [@"https://" stringByAppendingString:url];
    while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    NSString *tail = @"/chat/completions";
    if ([[url lowercaseString] hasSuffix:tail]) {
        url = [url substringToIndex:url.length - tail.length];
        while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    }
    /* a host is required; a text with spaces or no name after the scheme is no address */
    NSURL *parsed = [NSURL URLWithString:url];
    if (!parsed || !parsed.host.length) return @"";
    return url;
}

NSString *ExteriaLlmBaseURL(int preset) {
    switch (preset) {
    case ExteriaLlmPresetOpenAI: return @"https://api.openai.com/v1";
    case ExteriaLlmPresetGoogleAIStudio: return @"https://generativelanguage.googleapis.com/v1beta/openai";
    case ExteriaLlmPresetGroq: return @"https://api.groq.com/openai/v1";
    case ExteriaLlmPresetDeepSeek: return @"https://api.deepseek.com/v1";
    case ExteriaLlmPresetXAI: return @"https://api.x.ai/v1";
    case ExteriaLlmPresetCerebras: return @"https://api.cerebras.ai/v1";
    case ExteriaLlmPresetOllamaCloud: return @"https://ollama.com/v1";
    case ExteriaLlmPresetOpenRouter: return @"https://openrouter.ai/api/v1";
    case ExteriaLlmPresetVercelGateway: return @"https://ai-gateway.vercel.sh/v1";
    case ExteriaLlmPresetVertex: return @"https://aiplatform.googleapis.com/v1";
    default: {
        NSString *typed = ExteriaLlmCustomURL();
        return typed.length ? typed : @"https://generativelanguage.googleapis.com/v1beta/openai";
    }
    }
}

NSString *ExteriaLlmSystemPrompt(void) { return ExteriaTrString(@"llm.system"); }
void ExteriaLlmSetSystemPrompt(NSString *text) { ExteriaTrSetString(@"llm.system", text); }
NSString *ExteriaLlmUserPrompt(void) { return ExteriaTrString(@"llm.user"); }
void ExteriaLlmSetUserPrompt(NSString *text) { ExteriaTrSetString(@"llm.user", text); }

float ExteriaLlmTemperature(void) {
    id value = [ExteriaTrDefaults() objectForKey:ExteriaTrKey(@"llm.temperature")];
    float temperature = [value isKindOfClass:[NSNumber class]] ? [value floatValue] : 0.7f;
    return temperature < 0 ? 0 : (temperature > 2 ? 2 : temperature);
}

void ExteriaLlmSetTemperature(float value) {
    [ExteriaTrDefaults() setFloat:value forKey:ExteriaTrKey(@"llm.temperature")];
}

BOOL ExteriaLlmUsesContext(void) { return ExteriaTrBool(@"llm.context", NO); }
void ExteriaLlmSetUsesContext(BOOL on) { ExteriaTrSetBool(@"llm.context", on); }

NSArray *ExteriaLlmContextCounts(void) {
    return [NSArray arrayWithObjects:[NSNumber numberWithInt:1], [NSNumber numberWithInt:3], [NSNumber numberWithInt:5], [NSNumber numberWithInt:7],
            [NSNumber numberWithInt:10], nil];
}

int ExteriaLlmContextIndex(void) {
    int index = ExteriaTrInt(@"llm.context.size", 2);
    return index >= 0 && index < (int)ExteriaLlmContextCounts().count ? index : 2;
}

void ExteriaLlmSetContextIndex(int index) { ExteriaTrSetInt(@"llm.context.size", index); }

int ExteriaLlmContextCount(void) {
    return [[ExteriaLlmContextCounts() objectAtIndex:(NSUInteger)ExteriaLlmContextIndex()] intValue];
}

BOOL ExteriaLlmSupportsTemperature(int preset, NSString *model) {
    if (preset == ExteriaLlmPresetVertex) return NO;
    return exteria_llm_supports_temperature(model.UTF8String) != 0;
}
