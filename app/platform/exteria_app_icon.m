#import "exteria_app_icon.h"
#import "exteria_theme.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

#include <errno.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

/* the app is an executable, so the environment is a symbol it links against; the headers of the sdk do not declare it */
extern char **environ;

static NSString *const ExteriaIconError = @"ExteriaAppIcon";
/* the name of the chosen icon, kept in the plist beside the files it chose, so the two cannot disagree */
static NSString *const ExteriaIconNameKey = @"ExteriaIconName";
/* the icon entries of the packaged plist, saved before the first rewrite so that the icon of the app can come back */
static NSString *const ExteriaIconOriginalKey = @"ExteriaOriginalIcons";
/* the icon and the screen color the launch images in the bundle were drawn for ("Quack|15121f"), kept in the
   Info.plist so that a new install, which brings its own launch images and plist, drops it */
static NSString *const ExteriaLaunchIconKey = @"ExteriaLaunchIcon";
/* the splash and the launch images draw the icon this wide, in points, on the color of the screen under them (the dark one is also SPLASH_BACKGROUND in tools/make_assets.py) */
#define LAUNCH_ICON_POINTS 96.0

static BOOL ExteriaNativeIconsSupported(void) {
    UIApplication *application = [UIApplication sharedApplication];
    SEL supports = NSSelectorFromString(@"supportsAlternateIcons");
    SEL set = NSSelectorFromString(@"setAlternateIconName:completionHandler:");
    if (![application respondsToSelector:supports] || ![application respondsToSelector:set]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(application, supports);
}

static NSString *ExteriaBundlePlistPath(void) {
    return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Info.plist"];
}

/* the plist is replaced by a new file, which needs the folder; a bundle installed by the system, or by a root install, fails one of the two */
static BOOL ExteriaBundleWritable(void) {
    return access([[[NSBundle mainBundle] bundlePath] fileSystemRepresentation], W_OK) == 0 && access([ExteriaBundlePlistPath() fileSystemRepresentation], W_OK) == 0;
}

BOOL ExteriaAppIconCanRewrite(void) {
    return ExteriaBundleWritable() && access("/usr/bin/uicache", X_OK) == 0 && access("/usr/bin/killall", X_OK) == 0;
}

static dispatch_queue_t ExteriaIconQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("exteria.icon", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

ExteriaAppIconMode ExteriaAppIconCurrentMode(void) {
    if (ExteriaAlternateIconNames().count == 0) return ExteriaAppIconUnavailable;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:ExteriaBundlePlistPath()];
    if ([plist objectForKey:ExteriaIconOriginalKey] && ExteriaAppIconCanRewrite()) return ExteriaAppIconRewrite;
    if (ExteriaNativeIconsSupported()) return ExteriaAppIconNative;
    return ExteriaAppIconCanRewrite() ? ExteriaAppIconRewrite : ExteriaAppIconUnavailable;
}

static NSError *ExteriaIconFailure(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:ExteriaIconError code:code userInfo:[NSDictionary dictionaryWithObject:reason forKey:NSLocalizedDescriptionKey]];
}

/* runs a program with an argument vector and waits for it; nil when it exited with status 0 */
static NSError *ExteriaRunProgram(const char *path, char *const argv[]) {
    pid_t pid = 0;
    int started = posix_spawn(&pid, path, NULL, NULL, argv, environ);
    if (started != 0) return ExteriaIconFailure(started, [NSString stringWithFormat:@"%s did not start (%d)", path, started]);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return ExteriaIconFailure(errno, [NSString stringWithFormat:@"%s was not waited for (%d)", path, errno]);
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return nil;
    return ExteriaIconFailure(status, [NSString stringWithFormat:@"%s ended with status %d", path, status]);
}

/* the home screen reads icons from its own cache of the app, which only uicache fills again, and SpringBoard shows
   the new icon after it starts again. uicache registers the app anew */
static NSError *ExteriaRefreshHomeScreen(void) {
    char *argv[] = {"sh", "-c", "/usr/bin/uicache && /usr/bin/killall SpringBoard", NULL};
    return ExteriaRunProgram("/bin/sh", argv);
}

/* the icon entries a plist keeps: the iphone and ipad dictionaries and the flat list of the oldest systems */
static NSArray *ExteriaIconEntryKeys(void) {
    return [NSArray arrayWithObjects:@"CFBundleIcons", @"CFBundleIcons~ipad", @"CFBundleIconFiles", @"CFBundleIconFiles~ipad", nil];
}

/* the plist with the primary icon of every entry swapped for the files of the named alternate icon, or put back as the package had it for nil */
static NSError *ExteriaRewriteIconPlist(NSString *name) {
    NSString *path = ExteriaBundlePlistPath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSError *error = nil;
    NSMutableDictionary *plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:&error] : nil;
    if (![plist isKindOfClass:[NSMutableDictionary class]]) return error ? error : ExteriaIconFailure(1, @"the Info.plist could not be read");

    if (![plist objectForKey:ExteriaIconOriginalKey]) {
        NSMutableDictionary *original = [NSMutableDictionary dictionary];
        for (NSString *key in ExteriaIconEntryKeys()) {
            id entry = [plist objectForKey:key];
            if (entry) [original setObject:[NSPropertyListSerialization propertyListWithData:[NSPropertyListSerialization dataWithPropertyList:entry format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]
                                                                                   options:NSPropertyListMutableContainers format:NULL error:NULL] forKey:key];
        }
        [plist setObject:original forKey:ExteriaIconOriginalKey];
    }
    NSDictionary *original = [plist objectForKey:ExteriaIconOriginalKey];

    for (NSString *key in ExteriaIconEntryKeys()) {
        id saved = [original objectForKey:key];
        if (!saved) continue;
        if (!name) {
            /* a copy of the saved entry, because the alternate icons of the dictionary entries must stay in the plist whole */
            id copy = [NSPropertyListSerialization propertyListWithData:[NSPropertyListSerialization dataWithPropertyList:saved format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]
                                                               options:NSPropertyListMutableContainers format:NULL error:NULL];
            [plist setObject:copy forKey:key];
            continue;
        }
        BOOL flat = [saved isKindOfClass:[NSArray class]];
        NSDictionary *source = flat ? [original objectForKey:[key hasSuffix:@"~ipad"] ? @"CFBundleIcons~ipad" : @"CFBundleIcons"] : saved;
        NSDictionary *alternates = [source isKindOfClass:[NSDictionary class]] ? [source objectForKey:@"CFBundleAlternateIcons"] : nil;
        NSDictionary *icon = [alternates objectForKey:name];
        NSArray *files = [icon objectForKey:@"CFBundleIconFiles"];
        if (!files.count) {
            /* a device without files for this alternate keeps its primary icon */
            continue;
        }
        if (flat) {
            [plist setObject:files forKey:key];
            continue;
        }
        NSMutableDictionary *entry = [plist objectForKey:key];
        NSMutableDictionary *primary = [entry objectForKey:@"CFBundlePrimaryIcon"];
        [primary setObject:files forKey:@"CFBundleIconFiles"];
        id prerendered = [icon objectForKey:@"UIPrerenderedIcon"];
        if (prerendered) [primary setObject:prerendered forKey:@"UIPrerenderedIcon"];
    }
    if (name) [plist setObject:name forKey:ExteriaIconNameKey];
    else [plist removeObjectForKey:ExteriaIconNameKey];

    NSData *out = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!out) return error ? error : ExteriaIconFailure(2, @"the Info.plist could not be made");
    if (![out writeToFile:path options:NSDataWritingAtomic error:&error]) return error ? error : ExteriaIconFailure(3, @"the Info.plist could not be written");
    return nil;
}

NSString *ExteriaAlternateIconName(void) {
    if (ExteriaAppIconCurrentMode() == ExteriaAppIconNative) {
        SEL current = NSSelectorFromString(@"alternateIconName");
        UIApplication *application = [UIApplication sharedApplication];
        if (![application respondsToSelector:current]) return nil;
        return ((NSString *(*)(id, SEL))objc_msgSend)(application, current);
    }
    /* the file, not the dictionary the bundle loaded at launch, which does not change until the app starts again */
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:ExteriaBundlePlistPath()];
    NSString *name = [plist objectForKey:ExteriaIconNameKey];
    return [name isKindOfClass:[NSString class]] ? name : nil;
}

/* the choice, kept apart from the bundle: the name of the alternate icon, or an empty string for the icon of the app */
static NSString *const ExteriaIconChoiceKey = @"exteria.icon";

static void ExteriaKeepIconChoice(NSString *name) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:name ? name : @"" forKey:ExteriaIconChoiceKey];
    /* the app is closed by the restart of SpringBoard that follows, so the value is written out at once */
    [defaults synchronize];
}

/* the splash picture of an icon, at the scale asked for; the app's own picture where the icon has none */
static NSString *ExteriaSplashPath(NSString *name, int scale) {
    NSString *stem = name.length ? [@"splash_" stringByAppendingString:name.lowercaseString] : @"splash_icon";
    NSString *suffix = scale >= 3 ? @"@3x" : (scale == 2 ? @"@2x" : @"");
    NSString *path = [[NSBundle mainBundle] pathForResource:[stem stringByAppendingString:suffix] ofType:@"png"];
    if (path || !name.length) return path;
    return ExteriaSplashPath(nil, scale);
}

/* the size of a png from its header, without decoding it: a launch image of a big phone is some fourteen megabytes of pixels */
static BOOL ExteriaPNGSize(NSString *path, uint32_t *width, uint32_t *height) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:24];
    [handle closeFile];
    static const uint8_t signature[8] = {0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
    if (head.length < 24 || memcmp(head.bytes, signature, 8) != 0) return NO;
    const uint8_t *b = head.bytes;
    *width = (uint32_t)b[16] << 24 | (uint32_t)b[17] << 16 | (uint32_t)b[18] << 8 | b[19];
    *height = (uint32_t)b[20] << 24 | (uint32_t)b[21] << 16 | (uint32_t)b[22] << 8 | b[23];
    return YES;
}

/* what the launch images carry: the icon and the color of the screen of the theme that is on now, as hex */
static NSString *ExteriaLaunchSignature(NSString *name, UIColor *screen) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [screen getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%@|%02x%02x%02x", name ? name : @"", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}

/* the package's launch images: the app icon on the dark screen color of the modern theme */
static NSString *const ExteriaPackageLaunchSignature = @"|15121f";

static NSString *ExteriaMarkedLaunchSignature(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:ExteriaBundlePlistPath()];
    NSString *marked = [plist objectForKey:ExteriaLaunchIconKey];
    return marked.length ? marked : ExteriaPackageLaunchSignature;
}

/* the system shows the launch image of the bundle until the app has a window */
static NSError *ExteriaWriteLaunchImages(NSString *name, UIColor *screenColor) {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat screenScale = [UIScreen mainScreen].scale;
    uint32_t screenWidth = (uint32_t)lround(screen.width * screenScale), screenHeight = (uint32_t)lround(screen.height * screenScale);
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundle error:&error];
    if (!files) return error;
    for (NSString *file in files) {
        if (![file hasPrefix:@"Default"] || ![file hasSuffix:@".png"]) continue;
        NSString *path = [bundle stringByAppendingPathComponent:file];
        uint32_t width = 0, height = 0;
        if (!ExteriaPNGSize(path, &width, &height)) continue;
        if (!((width == screenWidth && height == screenHeight) || (width == screenHeight && height == screenWidth))) continue;
        int scale = [file rangeOfString:@"@3x"].location != NSNotFound ? 3 : ([file rangeOfString:@"@2x"].location != NSNotFound ? 2 : 1);
        UIImage *icon = [UIImage imageWithContentsOfFile:ExteriaSplashPath(name, scale)];
        if (!icon) return ExteriaIconFailure(5, [NSString stringWithFormat:@"no splash picture for the icon %@", name]);
        CGSize points = CGSizeMake(width / (CGFloat)scale, height / (CGFloat)scale);
        UIGraphicsBeginImageContextWithOptions(points, YES, (CGFloat)scale);
        [screenColor setFill];
        UIRectFill(CGRectMake(0, 0, points.width, points.height));
        [icon drawInRect:CGRectMake(floor((points.width - LAUNCH_ICON_POINTS) / 2), floor((points.height - LAUNCH_ICON_POINTS) / 2), LAUNCH_ICON_POINTS, LAUNCH_ICON_POINTS)];
        UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSData *png = made ? UIImagePNGRepresentation(made) : nil;
        if (!png) return ExteriaIconFailure(6, [NSString stringWithFormat:@"the launch image %@ could not be drawn", file]);
        if (![png writeToFile:path options:NSDataWritingAtomic error:&error]) return error;
    }
    return nil;
}

/* the Info.plist remembers which icon and color the launch images carry: nothing for what the package brings */
static NSError *ExteriaMarkLaunchSignature(NSString *signature) {
    NSString *path = ExteriaBundlePlistPath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSError *error = nil;
    NSMutableDictionary *plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:&error] : nil;
    if (![plist isKindOfClass:[NSMutableDictionary class]]) return error ? error : ExteriaIconFailure(1, @"the Info.plist could not be read");
    if ([signature isEqualToString:ExteriaPackageLaunchSignature]) [plist removeObjectForKey:ExteriaLaunchIconKey];
    else [plist setObject:signature forKey:ExteriaLaunchIconKey];
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!out) return error ? error : ExteriaIconFailure(2, @"the Info.plist could not be made");
    if (![out writeToFile:path options:NSDataWritingAtomic error:&error]) return error ? error : ExteriaIconFailure(3, @"the Info.plist could not be written");
    return nil;
}

/* the launch images for the icon, and the mark that says so; a failure is logged and the next launch tries again */
static void ExteriaSyncLaunchImages(NSString *name, UIColor *screenColor) {
    NSString *signature = ExteriaLaunchSignature(name, screenColor);
    NSError *error = ExteriaWriteLaunchImages(name, screenColor);
    if (!error) error = ExteriaMarkLaunchSignature(signature);
    if (error) NSLog(@"exteria: the launch images were not drawn for the chosen icon: %@", error);
}

/* the launch images carry the icon and the screen color of the theme, so a change of the theme draws them again
   for the next start */
void ExteriaAppIconRefreshLaunchImages(void) {
    if (ExteriaAppIconCurrentMode() != ExteriaAppIconRewrite) return;
    NSString *shown = ExteriaAlternateIconName();
    UIColor *screen = ExteriaColorScreen();
    if ([ExteriaMarkedLaunchSignature() isEqualToString:ExteriaLaunchSignature(shown, screen)]) return;
    NSString *chosen = [[shown copy] autorelease];
    dispatch_async(ExteriaIconQueue(), ^{
        @autoreleasepool { ExteriaSyncLaunchImages(chosen, screen); }
    });
}

void ExteriaAppIconRestore(void) {
    if (ExteriaAppIconCurrentMode() != ExteriaAppIconRewrite) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *shown = ExteriaAlternateIconName();
    id kept = [defaults objectForKey:ExteriaIconChoiceKey];
    NSString *wanted = shown;
    if (![kept isKindOfClass:[NSString class]]) {
        if (shown) ExteriaKeepIconChoice(shown);
    } else {
        wanted = [(NSString *)kept length] ? kept : nil;
        if (wanted && ![ExteriaAlternateIconNames() containsObject:wanted]) {
            /* an icon this version no longer has */
            [defaults removeObjectForKey:ExteriaIconChoiceKey];
            [defaults synchronize];
            wanted = shown;
        }
    }
    BOOL plistWrong = !(wanted == shown || [wanted isEqualToString:shown]);
    UIColor *screen = ExteriaColorScreen();
    BOOL launchWrong = ![ExteriaMarkedLaunchSignature() isEqualToString:ExteriaLaunchSignature(wanted, screen)];
    if (!plistWrong && !launchWrong) return;
    dispatch_async(ExteriaIconQueue(), ^{
        @autoreleasepool {
            if (plistWrong) {
                NSError *error = ExteriaRewriteIconPlist(wanted);
                if (error) {
                    NSLog(@"exteria: the chosen icon was not put back: %@", error);
                    return;
                }
            }
            ExteriaSyncLaunchImages(wanted, screen);
            if (!plistWrong) return;
            NSError *error = ExteriaRefreshHomeScreen();
            if (error) NSLog(@"exteria: the home screen did not read the icon again: %@", error);
        }
    });
}

UIImage *ExteriaSplashIconImage(void) {
    NSString *name = ExteriaAlternateIconName();
    UIImage *image = name.length ? [UIImage imageNamed:[@"splash_" stringByAppendingString:name.lowercaseString]] : nil;
    return image ? image : [UIImage imageNamed:@"splash_icon"];
}

static void ExteriaFinishIcon(void (^done)(NSError *), NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (done) done(error);
        [done release];
    });
}

void ExteriaRewriteAppIcon(NSString *name, void (^completion)(NSError *)) {
    void (^done)(NSError *) = [completion copy];
    if (name && ![ExteriaAlternateIconNames() containsObject:name]) {
        ExteriaFinishIcon(done, ExteriaIconFailure(7, @"the selected icon is absent from this app bundle"));
        return;
    }
    if (!ExteriaAppIconCanRewrite()) {
        ExteriaFinishIcon(done, ExteriaIconFailure(4, @"the app bundle or the home screen cache cannot be updated"));
        return;
    }
    NSString *chosen = [[name copy] autorelease];
    UIColor *screen = ExteriaColorScreen();
    dispatch_async(ExteriaIconQueue(), ^{
        @autoreleasepool {
            NSError *error = ExteriaRewriteIconPlist(chosen);
            if (!error) ExteriaKeepIconChoice(chosen);
            if (!error) ExteriaSyncLaunchImages(chosen, screen);
            if (!error) error = ExteriaRefreshHomeScreen();
            ExteriaFinishIcon(done, error);
        }
    });
}

void ExteriaSetAlternateIcon(NSString *name, void (^completion)(NSError *)) {
    void (^done)(NSError *) = [completion copy];
    ExteriaAppIconMode mode = ExteriaAppIconCurrentMode();
    if (mode == ExteriaAppIconRewrite) {
        [done release];
        ExteriaRewriteAppIcon(name, completion);
        return;
    }
    if (mode != ExteriaAppIconNative) {
        ExteriaFinishIcon(done, ExteriaIconFailure(4, @"this system cannot change the icon"));
        return;
    }
    UIApplication *application = [UIApplication sharedApplication];
    SEL set = NSSelectorFromString(@"setAlternateIconName:completionHandler:");
    ((void (*)(id, SEL, NSString *, void (^)(NSError *)))objc_msgSend)(application, set, name, ^(NSError *error) {
        if (!error) ExteriaKeepIconChoice(name);
        ExteriaFinishIcon(done, error);
    });
}

NSArray *ExteriaAlternateIconNames(void) {
    NSDictionary *icons = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIcons"];
    NSDictionary *alternates = [icons objectForKey:@"CFBundleAlternateIcons"];
    NSArray *names = [[alternates allKeys] sortedArrayUsingSelector:@selector(compare:)];
    /* the plist is a dictionary, so the order is made here: the first icons first, then the others by name */
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSString *first in [NSArray arrayWithObjects:@"Exteraless", @"Blueprint", @"Red", @"Nya", @"Ayu", @"Quack", nil]) {
        if ([names containsObject:first]) [ordered addObject:first];
    }
    for (NSString *name in names) if (![ordered containsObject:name]) [ordered addObject:name];
    return ordered;
}
