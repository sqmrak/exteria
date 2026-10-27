#import "exteria_senko.h"

#import <UIKit/UIKit.h>

static NSString *const ExteriaSenkoIdentifier = @"com.senko.app";

static BOOL ExteriaSenkoBundleAt(NSString *path) {
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    return [[bundle bundleIdentifier] isEqualToString:ExteriaSenkoIdentifier];
}

BOOL ExteriaSenkoInstalled(void) {
    static BOOL known = NO;
    static BOOL installed = NO;
    if (known) return installed;
    known = YES;
    /* /var/jb is the rootless prefix of the jailbreaks that keep the system volume sealed */
    static NSString *const paths[] = {@"/Applications/Senko.app", @"/var/jb/Applications/Senko.app"};
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]) && !installed; ++i) installed = ExteriaSenkoBundleAt(paths[i]);
    if (!installed) installed = [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"senko://"]];
    return installed;
}
