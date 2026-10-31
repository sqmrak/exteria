#import "exteria_imported_theme.h"
#import "exteria_theme.h"

#include "exteria_tgios_theme.h"

#include <stdlib.h>
#include <string.h>
#include <pthread.h>

static exteria_tgios_theme *ExteriaImportedActive;
static pthread_mutex_t ExteriaImportedLock = PTHREAD_MUTEX_INITIALIZER;
static NSString *const ExteriaImportedSuspendKey = @"exteria.imported-theme.suspended";

void ExteriaImportedThemeSuspend(BOOL suspended) {
    NSMutableDictionary *values = [[NSThread currentThread] threadDictionary];
    if (suspended) [values setObject:[NSNumber numberWithBool:YES] forKey:ExteriaImportedSuspendKey];
    else [values removeObjectForKey:ExteriaImportedSuspendKey];
}

static BOOL ExteriaImportedThemeIsSuspended(void) {
    return [[[[NSThread currentThread] threadDictionary] objectForKey:ExteriaImportedSuspendKey] boolValue];
}

static NSString *ExteriaImportedKey(BOOL dark) {
    return dark ? @"exteria.imported-theme.dark" : @"exteria.imported-theme.day";
}

static NSString *ExteriaImportedPath(BOOL dark) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"];
    return [directory stringByAppendingPathComponent:dark ? @"imported-night.tgios-theme" : @"imported-day.tgios-theme"];
}

static NSString *ExteriaImportedRead(NSURL *url, exteria_tgios_theme *theme, NSData **validatedData) {
    if (!url || ![url isFileURL] || [[[url path] pathExtension] caseInsensitiveCompare:@"tgios-theme"] != NSOrderedSame)
        return NSLocalizedString(@"theme.import.type", nil);
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL];
    NSNumber *size = [attributes objectForKey:NSFileSize];
    if (!size) return NSLocalizedString(@"theme.import.read", nil);
    if ([size unsignedLongLongValue] > EXTERIA_TGIOS_MAX_BYTES) return NSLocalizedString(@"theme.import.size", nil);
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:[url path]];
    NSData *data = nil;
    @try { data = [handle readDataOfLength:EXTERIA_TGIOS_MAX_BYTES + 1]; }
    @catch (NSException *exception) { NSLog(@"exteria: theme read: %@", exception); }
    @finally { [handle closeFile]; }
    if (!data) return NSLocalizedString(@"theme.import.read", nil);
    exteria_tgios_status status = exteria_tgios_parse([data bytes], [data length], theme);
    if (status != EXTERIA_TGIOS_OK) return NSLocalizedString(status == EXTERIA_TGIOS_TOO_LARGE ? @"theme.import.size" : @"theme.import.format", nil);
    const exteria_tgios_field *badField = NULL;
    status = exteria_tgios_validate_applicable_at(theme, &badField);
    if (status == EXTERIA_TGIOS_INVALID_COLOR) {
        /* the line names the key and its value, since a theme has hundreds of colors and the file is read on a phone */
        return [NSString stringWithFormat:NSLocalizedString(@"theme.import.color", nil), [NSString stringWithUTF8String:badField->key], [NSString stringWithUTF8String:badField->value]];
    }
    if (status != EXTERIA_TGIOS_OK) return NSLocalizedString(status == EXTERIA_TGIOS_INVALID_WALLPAPER ? @"theme.import.wallpaper" : @"theme.import.format", nil);
    if (validatedData) *validatedData = data;
    return nil;
}

NSString *ExteriaImportedThemeCheck(NSURL *url, BOOL *dark, NSString **name) {
    exteria_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) return NSLocalizedString(@"theme.import.memory", nil);
    NSString *error = ExteriaImportedRead(url, theme, NULL);
    if (!error) {
        const char *tone = exteria_tgios_get(theme, "dark");
        const char *title = exteria_tgios_get(theme, "name");
        if (dark) *dark = strcmp(tone, "true") == 0;
        if (name) *name = title ? [NSString stringWithUTF8String:title] : [[url lastPathComponent] stringByDeletingPathExtension];
    }
    free(theme);
    return error;
}

NSString *ExteriaImportedThemeInstall(NSURL *url, BOOL dark) {
    exteria_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) return NSLocalizedString(@"theme.import.memory", nil);
    NSData *data = nil;
    NSString *error = ExteriaImportedRead(url, theme, &data);
    if (!error && (strcmp(exteria_tgios_get(theme, "dark"), "true") == 0) != dark)
        error = NSLocalizedString(@"theme.import.format", nil);
    free(theme);
    if (error) return error;
    NSString *path = ExteriaImportedPath(dark);
    NSError *fileError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&fileError]) {
        NSLog(@"exteria: theme directory: %@", fileError);
        return NSLocalizedString(@"theme.import.save", nil);
    }
    NSData *previous = [NSData dataWithContentsOfFile:path];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&fileError]) {
        NSLog(@"exteria: theme save: %@", fileError);
        return NSLocalizedString(@"theme.import.save", nil);
    }
    BOOL wasSelected = ExteriaImportedThemeSelected(dark);
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:ExteriaImportedKey(dark)];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) {
        [[NSUserDefaults standardUserDefaults] setBool:wasSelected forKey:ExteriaImportedKey(dark)];
        NSError *restoreError = nil;
        BOOL restored = previous ? [previous writeToFile:path options:NSDataWritingAtomic error:&restoreError] : [[NSFileManager defaultManager] removeItemAtPath:path error:&restoreError];
        if (!restored) NSLog(@"exteria: previous theme could not be restored: %@", restoreError);
        NSLog(@"exteria: theme selection was not saved");
        return NSLocalizedString(@"theme.import.save", nil);
    }
    return nil;
}

NSString *ExteriaImportedThemeBeginPreview(NSURL *url) {
    exteria_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) return NSLocalizedString(@"theme.import.memory", nil);
    NSString *error = ExteriaImportedRead(url, theme, NULL);
    if (error) { free(theme); return error; }
    pthread_mutex_lock(&ExteriaImportedLock);
    free(ExteriaImportedActive);
    ExteriaImportedActive = theme;
    pthread_mutex_unlock(&ExteriaImportedLock);
    return nil;
}

void ExteriaImportedThemeUseBuiltin(BOOL dark) {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:ExteriaImportedKey(dark)];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: built-in theme choice was not saved");
}

BOOL ExteriaImportedThemeSelected(BOOL dark) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaImportedKey(dark)];
}

void ExteriaImportedThemeReload(BOOL dark) {
    pthread_mutex_lock(&ExteriaImportedLock);
    free(ExteriaImportedActive);
    ExteriaImportedActive = NULL;
    pthread_mutex_unlock(&ExteriaImportedLock);
    if (!ExteriaImportedThemeSelected(dark)) return;
    exteria_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) { NSLog(@"exteria: imported theme memory unavailable"); return; }
    NSString *error = ExteriaImportedRead([NSURL fileURLWithPath:ExteriaImportedPath(dark)], theme, NULL);
    if (error) { NSLog(@"exteria: imported theme unavailable: %@", error); free(theme); ExteriaImportedThemeUseBuiltin(dark); return; }
    pthread_mutex_lock(&ExteriaImportedLock);
    ExteriaImportedActive = theme;
    pthread_mutex_unlock(&ExteriaImportedLock);
}

UIColor *ExteriaImportedThemeColor(const char *key) {
    if (ExteriaImportedThemeIsSuspended() || ExteriaThemeIsClassic()) return nil;
    pthread_mutex_lock(&ExteriaImportedLock);
    const char *value = exteria_tgios_get(ExteriaImportedActive, key);
    uint32_t argb;
    if (!value || !exteria_tgios_color(value, &argb)) { pthread_mutex_unlock(&ExteriaImportedLock); return nil; }
    pthread_mutex_unlock(&ExteriaImportedLock);
    return [UIColor colorWithRed:((argb >> 16) & 255) / 255.0 green:((argb >> 8) & 255) / 255.0 blue:(argb & 255) / 255.0 alpha:((argb >> 24) & 255) / 255.0];
}

NSString *ExteriaImportedThemeWallpaper(void) {
    if (ExteriaImportedThemeIsSuspended() || ExteriaThemeIsClassic()) return nil;
    pthread_mutex_lock(&ExteriaImportedLock);
    const char *wallpaper = exteria_tgios_get(ExteriaImportedActive, "wallpaper");
    NSString *value = wallpaper ? [NSString stringWithUTF8String:wallpaper] : nil;
    pthread_mutex_unlock(&ExteriaImportedLock);
    return value;
}

NSString *ExteriaImportedThemeStatusBar(void) {
    pthread_mutex_lock(&ExteriaImportedLock);
    const char *value = exteria_tgios_get(ExteriaImportedActive, "root.statusBar");
    NSString *style = value ? [NSString stringWithUTF8String:value] : nil;
    pthread_mutex_unlock(&ExteriaImportedLock);
    return style;
}

NSUInteger ExteriaImportedThemeWallpaperGradient(uint32_t colors[4], int *angle) {
    NSString *wallpaper = ExteriaImportedThemeWallpaper();
    if (!wallpaper || !colors || !angle) return 0;
    exteria_tgios_wallpaper parsed;
    if (!exteria_tgios_parse_wallpaper([wallpaper UTF8String], &parsed)) return 0;
    if (parsed.kind != EXTERIA_TGIOS_WALLPAPER_COLOR && parsed.kind != EXTERIA_TGIOS_WALLPAPER_GRADIENT) return 0;
    for (unsigned i = 0; i < parsed.color_count; ++i) colors[i] = parsed.colors[i];
    *angle = parsed.rotation;
    return parsed.color_count;
}
