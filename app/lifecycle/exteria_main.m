#import <UIKit/UIKit.h>

#include <stdio.h>

#import "exteria_app_delegate.h"

#define LOG_BYTES_MAX (512 * 1024)

/* NSLog reaches the system log only, and the jailbroken phones keep none, so stderr goes to a file that can be pulled
   from Library/Logs; a file past the limit starts over */
static void ExteriaRedirectLog(void) {
    NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *directory = [library stringByAppendingPathComponent:@"Logs"];
    NSString *path = [directory stringByAppendingPathComponent:@"exteria.log"];
    NSFileManager *files = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: no log directory: %@", error);
        return;
    }
    if ([[files attributesOfItemAtPath:path error:NULL] fileSize] > LOG_BYTES_MAX) [files removeItemAtPath:path error:NULL];
    if (!freopen(path.fileSystemRepresentation, "a", stderr)) NSLog(@"exteria: cannot open the log file");
}

/* the interface follows the first language of the system, and bundle lookup would otherwise fall through to the
   second one: a phone set to French first and Russian second would show Russian */
static void ExteriaChooseLanguage(void) {
    NSArray *system = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain] objectForKey:@"AppleLanguages"];
    NSString *first = system.count ? [system objectAtIndex:0] : @"en";
    NSRange dash = [first rangeOfString:@"-"];
    NSString *base = dash.location == NSNotFound ? first : [first substringToIndex:dash.location];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([base isEqualToString:@"en"] || [base isEqualToString:@"ru"]) [defaults removeObjectForKey:@"AppleLanguages"];
    else [defaults setObject:[NSArray arrayWithObject:@"en"] forKey:@"AppleLanguages"];
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    ExteriaRedirectLog();
    ExteriaChooseLanguage();
    int status = UIApplicationMain(argc, argv, nil, NSStringFromClass([ExteriaAppDelegate class]));
    [pool release];
    return status;
}
