#import <UIKit/UIKit.h>

/* clang turns __builtin_available into a call to this compiler-rt function. the toolchain links no compiler-rt, and cpython's
   posixmodule guards the *at() calls that ios 8 added with it, so the arm64 slice (deployment target 7.0) would not link.
   the answer is the version the device reports; the armv7 slice is built on the 6.1 sdk and never emits the call */
#if defined(__arm64__)
int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor) {
    static int32_t version[3];
    static BOOL known;
    if (!known) {
        NSArray *parts = [[[UIDevice currentDevice] systemVersion] componentsSeparatedByString:@"."];
        for (NSUInteger i = 0; i < 3; ++i) version[i] = i < parts.count ? (int32_t)[[parts objectAtIndex:i] intValue] : 0;
        known = YES;
    }
    if (version[0] != major) return version[0] > major;
    if (version[1] != minor) return version[1] > minor;
    return version[2] >= subminor;
}
#endif
