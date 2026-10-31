#import <UIKit/UIKit.h>
#include <stdint.h>

NSString *ExteriaImportedThemeCheck(NSURL *url, BOOL *dark, NSString **name);
NSString *ExteriaImportedThemeInstall(NSURL *url, BOOL dark);
NSString *ExteriaImportedThemeBeginPreview(NSURL *url);
void ExteriaImportedThemeUseBuiltin(BOOL dark);
BOOL ExteriaImportedThemeSelected(BOOL dark);
void ExteriaImportedThemeSuspend(BOOL suspended);
void ExteriaImportedThemeReload(BOOL dark);
UIColor *ExteriaImportedThemeColor(const char *key);
NSString *ExteriaImportedThemeWallpaper(void);
NSString *ExteriaImportedThemeStatusBar(void);
NSUInteger ExteriaImportedThemeWallpaperGradient(uint32_t colors[4], int *angle);
