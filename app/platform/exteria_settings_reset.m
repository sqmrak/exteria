#import "exteria_settings_reset.h"

#import "exteria_chat_settings.h"
#import "exteria_language.h"
#import "exteria_theme.h"

void ExteriaResetSettings(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = [defaults dictionaryRepresentation];
    NSUInteger removed = 0;
    for (NSString *key in [all allKeys]) {
        if ([key rangeOfString:@"exteria" options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == NSNotFound) continue;
        /* the list of the signed in accounts and the traffic counted so far are data of the phone, not choices of the person; a reset that dropped the passcode
           would open the lock to anyone who holds the phone */
        if ([key hasPrefix:@"exteria.account"] || [key hasPrefix:@"exteria.traffic"] || [key hasPrefix:@"exteria.report"] || [key hasPrefix:@"exteria.passcode"]) continue;
        [defaults removeObjectForKey:key];
        ++removed;
    }
    if (![defaults synchronize]) NSLog(@"exteria: the reset of the settings was not saved");
    NSLog(@"exteria: %lu stored settings were reset", (unsigned long)removed);
    /* values the settings keep in memory for the drawing of every avatar and card */
    ExteriaChatSettingsForgetCached();
    ExteriaApplyInterfaceLanguage();
    ExteriaThemeApplyStored();
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaLanguageDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
}
