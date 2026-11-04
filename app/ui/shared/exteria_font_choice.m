#import "exteria_font_choice.h"

#import <CoreText/CoreText.h>
#include <pthread.h>
#import "exteria_theme.h"

static NSString *const ExteriaRubikKey = @"ExteriaRubikEverywhere";
static NSString *const ExteriaCustomFontPostScriptKey = @"ExteriaCustomFontPostScript";
static NSString *const ExteriaCustomFontTitleKey = @"ExteriaCustomFontTitle";
static NSString *const ExteriaCustomFontFileKey = @"ExteriaCustomFontFile";
/* a font file is read whole to check it, and a picked file of this size is not a font */
static const unsigned long long ExteriaCustomFontMaxBytes = 20ull * 1024 * 1024;

static pthread_mutex_t ExteriaFontLock = PTHREAD_MUTEX_INITIALIZER;
/* the file registered with the font manager in this process, so a replaced or removed one is unregistered first */
static NSURL *ExteriaRegisteredFont;
static BOOL ExteriaRegistrationTried;

static NSString *ExteriaCustomFontDirectory(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"];
}

/* the lock is held by the caller */
static void ExteriaUnregisterLocked(void) {
    if (!ExteriaRegisteredFont) return;
    CFErrorRef error = NULL;
    if (!CTFontManagerUnregisterFontsForURL((CFURLRef)ExteriaRegisteredFont, kCTFontManagerScopeProcess, &error))
        NSLog(@"exteria: the custom font was not unregistered: %@", error ? [(NSError *)error localizedDescription] : @"unknown");
    if (error) CFRelease(error);
    [ExteriaRegisteredFont release];
    ExteriaRegisteredFont = nil;
}

/* the lock is held by the caller. a font the system already knows by this name counts as registered, since the font manager refuses a duplicate name */
static BOOL ExteriaRegisterLocked(NSURL *url, NSString *postScript) {
    CFErrorRef error = NULL;
    BOOL registered = CTFontManagerRegisterFontsForURL((CFURLRef)url, kCTFontManagerScopeProcess, &error);
    if (registered) {
        ExteriaRegisteredFont = [url retain];
    } else {
        NSLog(@"exteria: the custom font did not register: %@", error ? [(NSError *)error localizedDescription] : @"unknown");
    }
    if (error) CFRelease(error);
    return [UIFont fontWithName:postScript size:12] != nil;
}

/* the file kept by an earlier run is registered on first use, because the font manager forgets it at every launch */
static void ExteriaRestoreLocked(void) {
    if (ExteriaRegistrationTried) return;
    ExteriaRegistrationTried = YES;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *file = [defaults stringForKey:ExteriaCustomFontFileKey];
    NSString *postScript = [defaults stringForKey:ExteriaCustomFontPostScriptKey];
    if (!file.length || !postScript.length) return;
    NSString *path = [ExteriaCustomFontDirectory() stringByAppendingPathComponent:file];
    if (!ExteriaRegisterLocked([NSURL fileURLWithPath:path], postScript))
        NSLog(@"exteria: the custom font %@ is not available, the default face stays", postScript);
}

UIFont *ExteriaFontChoiceFont(int weight, CGFloat size) {
    static NSString *const rubik[] = {@"Rubik-Regular", @"Rubik-Medium", @"Rubik-Bold", @"Rubik-Bold"};
    if (weight < 0 || weight > 3) return nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *custom = [defaults stringForKey:ExteriaCustomFontPostScriptKey];
    if (custom.length) {
        pthread_mutex_lock(&ExteriaFontLock);
        ExteriaRestoreLocked();
        pthread_mutex_unlock(&ExteriaFontLock);
        UIFont *font = [UIFont fontWithName:custom size:size];
        if (font) return font;
    }
    if ([defaults boolForKey:ExteriaRubikKey]) return [UIFont fontWithName:rubik[weight] size:size];
    return nil;
}

BOOL ExteriaFontRubikEverywhere(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaRubikKey];
}

void ExteriaFontStoreRubikEverywhere(BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:ExteriaRubikKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the font choice was not saved");
    ExteriaFontsDidChange();
}

NSString *ExteriaFontCustomName(void) {
    NSString *title = [[NSUserDefaults standardUserDefaults] stringForKey:ExteriaCustomFontTitleKey];
    return title.length ? title : nil;
}

NSString *ExteriaFontImportCustom(NSString *path) {
    NSString *extension = [[path pathExtension] lowercaseString];
    if (![extension isEqualToString:@"ttf"] && ![extension isEqualToString:@"otf"]) return NSLocalizedString(@"font.error.type", nil);
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (!attributes) return NSLocalizedString(@"font.error.read", nil);
    if ([attributes fileSize] == 0 || [attributes fileSize] > ExteriaCustomFontMaxBytes) return NSLocalizedString(@"font.error.size", nil);
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return NSLocalizedString(@"font.error.read", nil);
    /* a file the graphics layer cannot parse would register as nothing and leave every label in the fallback face */
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGFontRef font = provider ? CGFontCreateWithDataProvider(provider) : NULL;
    if (provider) CGDataProviderRelease(provider);
    if (!font) return NSLocalizedString(@"font.error.invalid", nil);
    NSString *postScript = [(NSString *)CGFontCopyPostScriptName(font) autorelease];
    NSString *title = [(NSString *)CGFontCopyFullName(font) autorelease];
    CGFontRelease(font);
    if (!postScript.length) return NSLocalizedString(@"font.error.invalid", nil);

    NSString *directory = ExteriaCustomFontDirectory();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: the font folder was not made: %@", error);
        return NSLocalizedString(@"font.error.save", nil);
    }
    /* a new name per import: a registered file is not replaced in place */
    NSString *file = [NSString stringWithFormat:@"custom-font-%lu.%@", (unsigned long)[[NSDate date] timeIntervalSince1970], extension];
    NSString *target = [directory stringByAppendingPathComponent:file];
    if (![data writeToFile:target options:NSDataWritingAtomic error:&error]) {
        NSLog(@"exteria: the font was not copied: %@", error);
        return NSLocalizedString(@"font.error.save", nil);
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *previousFile = [defaults stringForKey:ExteriaCustomFontFileKey];
    pthread_mutex_lock(&ExteriaFontLock);
    ExteriaRegistrationTried = YES;
    ExteriaUnregisterLocked();
    BOOL usable = ExteriaRegisterLocked([NSURL fileURLWithPath:target], postScript);
    pthread_mutex_unlock(&ExteriaFontLock);
    if (!usable) {
        [[NSFileManager defaultManager] removeItemAtPath:target error:NULL];
        return NSLocalizedString(@"font.error.invalid", nil);
    }
    [defaults setObject:postScript forKey:ExteriaCustomFontPostScriptKey];
    [defaults setObject:title.length ? title : postScript forKey:ExteriaCustomFontTitleKey];
    [defaults setObject:file forKey:ExteriaCustomFontFileKey];
    if (![defaults synchronize]) NSLog(@"exteria: the font choice was not saved");
    if (previousFile.length) [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:previousFile] error:NULL];
    ExteriaFontsDidChange();
    return nil;
}

void ExteriaFontRemoveCustom(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *file = [defaults stringForKey:ExteriaCustomFontFileKey];
    pthread_mutex_lock(&ExteriaFontLock);
    ExteriaRegistrationTried = YES;
    ExteriaUnregisterLocked();
    pthread_mutex_unlock(&ExteriaFontLock);
    [defaults removeObjectForKey:ExteriaCustomFontPostScriptKey];
    [defaults removeObjectForKey:ExteriaCustomFontTitleKey];
    [defaults removeObjectForKey:ExteriaCustomFontFileKey];
    if (![defaults synchronize]) NSLog(@"exteria: the font choice was not saved");
    if (file.length) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtPath:[ExteriaCustomFontDirectory() stringByAppendingPathComponent:file] error:&error])
            NSLog(@"exteria: the font file was not removed: %@", error);
    }
    ExteriaFontsDidChange();
}
