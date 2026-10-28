#import "exteria_problem_report.h"

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <sys/sysctl.h>
#include <string.h>

#import "exteria_chat_settings.h"
#import "exteria_crash_prompt.h"
#import "exteria_person.h"
#import "exteria_session_bots.h"

/* the developer the reports go to; an account that is this one tells nobody */
#define REPORT_USERNAME @"sqmrak"
#define REPORT_PAUSE_SECONDS 900
#define REPORT_LIMIT 3500

static NSString *const ExteriaReportedKey = @"exteria.report.last";
static NSString *const ExteriaReportSentKey = @"exteria.report.sent";

/* the identifier of the binary that ran, to look the addresses of a crash up in the symbols of the very build */
static NSString *ExteriaBuildIdentifier(void) {
#if defined(__LP64__)
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
    const uint8_t *command = (const uint8_t *)(header + 1);
    uint32_t count = header->ncmds;
#else
    const struct mach_header *header = _dyld_get_image_header(0);
    const uint8_t *command = (const uint8_t *)(header + 1);
    uint32_t count = header->ncmds;
#endif
    for (uint32_t i = 0; i < count; ++i) {
        const struct load_command *load = (const struct load_command *)command;
        if (load->cmd == LC_UUID) {
            const struct uuid_command *uuid = (const struct uuid_command *)load;
            NSMutableString *text = [NSMutableString string];
            for (int j = 0; j < 16; ++j) [text appendFormat:@"%02x", uuid->uuid[j]];
            return text;
        }
        command += load->cmdsize;
    }
    return @"unknown";
}

static NSString *ExteriaMachine(void) {
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0 || size > 64) return @"?";
    char buffer[64];
    if (sysctlbyname("hw.machine", buffer, &size, NULL, 0) != 0) return @"?";
    return [NSString stringWithUTF8String:buffer];
}

NSString *ExteriaProblemReportHeader(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
#if defined(__arm64__)
    NSString *architecture = @"arm64";
#else
    NSString *architecture = @"armv7";
#endif
    UIDevice *device = [UIDevice currentDevice];
    return [NSString stringWithFormat:@"exteria %@ (%@) %@ build %@\n%@ %@, %@", [info objectForKey:@"CFBundleShortVersionString"],
            [info objectForKey:@"CFBundleVersion"], architecture, ExteriaBuildIdentifier(), device.systemName, device.systemVersion, ExteriaMachine()];
}

static NSString *ExteriaCrashLogText(void) {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    if (!caches) return nil;
    NSData *data = [NSData dataWithContentsOfFile:[caches stringByAppendingPathComponent:@"exteria-crash.log"]];
    if (!data.length || data.length > 256 * 1024) return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

/* the records of crashes the log holds that are newer than the last one told, oldest first: each begins at "fault at", "exception at" or "crash at" and its time */
static NSArray *ExteriaUnreportedCrashes(NSString *text, long long *newest) {
    if (!text.length) return nil;
    long long last = (long long)[[NSUserDefaults standardUserDefaults] doubleForKey:ExteriaReportedKey];
    NSMutableArray *records = [NSMutableArray array];
    NSMutableArray *starts = [NSMutableArray array], *times = [NSMutableArray array];
    static NSString *const markers[] = {@"fault at ", @"exception at ", @"crash at "};
    for (size_t m = 0; m < sizeof(markers) / sizeof(markers[0]); ++m) {
        NSRange from = NSMakeRange(0, text.length);
        for (;;) {
            NSRange found = [text rangeOfString:markers[m] options:0 range:from];
            if (found.location == NSNotFound) break;
            NSScanner *number = [NSScanner scannerWithString:text];
            number.scanLocation = NSMaxRange(found);
            long long when = 0;
            if ([number scanLongLong:&when] && when > 0) {
                [starts addObject:[NSNumber numberWithUnsignedInteger:found.location]];
                [times addObject:[NSNumber numberWithLongLong:when]];
            }
            from = NSMakeRange(NSMaxRange(found), text.length - NSMaxRange(found));
        }
    }
    NSArray *order = [[starts sortedArrayUsingSelector:@selector(compare:)] copy];
    for (NSUInteger i = 0; i < order.count; ++i) {
        NSUInteger begin = [[order objectAtIndex:i] unsignedIntegerValue];
        NSUInteger end = i + 1 < order.count ? [[order objectAtIndex:i + 1] unsignedIntegerValue] : text.length;
        NSUInteger index = [starts indexOfObject:[order objectAtIndex:i]];
        long long when = [[times objectAtIndex:index] longLongValue];
        if (when <= last) continue;
        NSString *record = [text substringWithRange:NSMakeRange(begin, MIN(end - begin, (NSUInteger)900))];
        [records addObject:record];
        if (newest && when > *newest) *newest = when;
    }
    [order release];
    return records;
}

/* the developer's account, asked for once and kept */
static ExteriaDialog *ExteriaReportTarget;

static void ExteriaSendReport(ExteriaSession *session, NSString *body, void (^done)(BOOL sent)) {
    if (!ExteriaChatFlagGet(ExteriaChatFlagCrashReports) || !body.length) {
        if (done) done(NO);
        return;
    }
    NSTimeInterval sentAt = [[NSUserDefaults standardUserDefaults] doubleForKey:ExteriaReportSentKey];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - sentAt < REPORT_PAUSE_SECONDS) {
        NSLog(@"exteria: the problem report was not sent: rate limit");
        if (done) done(NO);
        return;
    }
    NSString *text = [NSString stringWithFormat:@"%@\n\n%@", ExteriaProblemReportHeader(), body];
    if (text.length > REPORT_LIMIT) text = [text substringToIndex:REPORT_LIMIT];
    void (^finish)(BOOL) = [done copy];
    void (^send)(ExteriaDialog *) = ^(ExteriaDialog *target) {
        long long randomId = ((long long)arc4random() << 32) | arc4random();
        [session sendText:text entities:nil toDialog:target randomId:randomId completion:^(int32_t messageId, NSString *errorName) {
            BOOL sent = messageId > 0 && !errorName;
            if (sent) {
                [[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:ExteriaReportSentKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
            } else {
                NSLog(@"exteria: the problem report was not sent: %@", errorName);
            }
            if (finish) finish(sent);
            [finish release];
        }];
    };
    if (ExteriaReportTarget) {
        send(ExteriaReportTarget);
        return;
    }
    [session resolveUsername:REPORT_USERNAME completion:^(ExteriaDialog *dialog, ExteriaPerson *person, NSString *errorName) {
        (void)person;
        if (!dialog) {
            NSLog(@"exteria: the developer for the problem reports was not found: %@", errorName);
            if (finish) finish(NO);
            [finish release];
            return;
        }
        ExteriaReportTarget = [dialog retain];
        send(dialog);
    }];
}

void ExteriaProblemReportsStart(ExteriaSession *session) {
    if (!ExteriaChatFlagGet(ExteriaChatFlagCrashReports)) return;
    long long newest = 0;
    NSArray *records = ExteriaUnreportedCrashes(ExteriaCrashLogText(), &newest);
    if (!records.count) return;
    NSUInteger from = records.count > 3 ? records.count - 3 : 0;
    NSString *body = [NSString stringWithFormat:@"crash log, %lu new:\n%@", (unsigned long)(records.count), [[records subarrayWithRange:NSMakeRange(from, records.count - from)] componentsJoinedByString:@"\n--\n"]];
    /* the same crash is asked about once, even if the app closes before the answer */
    BOOL shown = ExteriaAskCrashReport(^(BOOL send) {
        if (send) ExteriaSendReport(session, body, nil);
    });
    if (shown) {
        [[NSUserDefaults standardUserDefaults] setDouble:(double)newest forKey:ExteriaReportedKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

void ExteriaProblemReportCallFailure(ExteriaSession *session) {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSData *data = documents ? [NSData dataWithContentsOfFile:[documents stringByAppendingPathComponent:@"exteria-call-trace.log"]] : nil;
    NSString *trace = data.length && data.length < 512 * 1024 ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
    if (trace.length > 2800) trace = [trace substringFromIndex:trace.length - 2800];
    ExteriaSendReport(session, [NSString stringWithFormat:@"a call did not connect, trace:\n%@", trace.length ? trace : @"(no trace)"], nil);
}
