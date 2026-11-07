#import "exteria_rewind.h"

#import <UIKit/UIKit.h>

static NSString *const ExteriaRewindIdentifier = @"com.sqmrak.rewind";
static NSString *const ExteriaRewindScheme = @"rewind";

static BOOL ExteriaRewindBundleAt(NSString *path) {
    return [[[NSBundle bundleWithPath:path] bundleIdentifier] isEqualToString:ExteriaRewindIdentifier];
}

BOOL ExteriaRewindInstalled(void) {
    /* /var/jb is the rootless prefix of the jailbreaks that keep the system volume sealed */
    static NSString *const paths[] = {@"/Applications/Rewind.app", @"/var/jb/Applications/Rewind.app"};
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); ++i) {
        if (ExteriaRewindBundleAt(paths[i])) return YES;
    }
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"rewind://"]];
}

/* only the addresses Rewind can act on: a watch, playlist, short, live or embed page and a youtu.be id; Rewind reads the id itself and
   says so when it is not valid */
static BOOL ExteriaIsYouTubeMediaLink(NSURL *url) {
    NSString *scheme = [url.scheme lowercaseString];
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) return NO;
    NSString *host = [url.host lowercaseString];
    NSString *path = url.path;
    if ([host isEqualToString:@"youtu.be"] || [host isEqualToString:@"www.youtu.be"]) return path.length > 1;
    if (![host isEqualToString:@"youtube.com"] && ![host isEqualToString:@"www.youtube.com"] && ![host isEqualToString:@"m.youtube.com"] &&
        ![host isEqualToString:@"music.youtube.com"]) return NO;
    if ([path isEqualToString:@"/watch"] || [path isEqualToString:@"/playlist"]) return YES;
    for (NSString *prefix in [NSArray arrayWithObjects:@"/shorts/", @"/live/", @"/embed/", nil]) {
        if ([path hasPrefix:prefix] && path.length > prefix.length) return YES;
    }
    return NO;
}

BOOL ExteriaRewindOpenLink(NSURL *url) {
    if (!url || !ExteriaIsYouTubeMediaLink(url) || !ExteriaRewindInstalled()) return NO;
    NSString *address = url.absoluteString;
    NSRange separator = [address rangeOfString:@"://"];
    if (separator.location == NSNotFound) return NO;
    NSURL *target = [NSURL URLWithString:[[ExteriaRewindScheme stringByAppendingString:@"://"] stringByAppendingString:[address substringFromIndex:NSMaxRange(separator)]]];
    if (!target || ![[UIApplication sharedApplication] openURL:target]) {
        NSLog(@"exteria: rewind did not take the link");
        return NO;
    }
    return YES;
}
