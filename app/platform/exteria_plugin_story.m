#import "exteria_plugin_story.h"

#import <UIKit/UIKit.h>

#import "exteria_alert.h"
#import "exteria_plugins.h"
#import "exteria_story.h"
#import "exteria_story_camera_controller.h"

/* a story that a plugin holds keeps its audience here; the list of a person who schedules many stories is bounded, and a full table refuses the story
   instead of dropping an audience, which would publish a private story to everyone */
#define AUDIENCES_MAX 64

static NSMutableDictionary *g_audiences;
static long long g_next_token;

static NSMutableDictionary *audiences(void) {
    if (!g_audiences) g_audiences = [[NSMutableDictionary alloc] init];
    return g_audiences;
}

ExteriaStoryAudience *ExteriaPluginStoryAudience(long long token) {
    return token > 0 ? [audiences() objectForKey:[NSNumber numberWithLongLong:token]] : nil;
}

BOOL ExteriaPluginStoryPathAllowed(NSString *path) {
    if (![path isKindOfClass:[NSString class]] || !path.length) return NO;
    NSString *real = [path stringByResolvingSymlinksInPath];
    NSArray *roots = [NSArray arrayWithObjects:NSTemporaryDirectory(), ExteriaPluginsDirectory(), nil];
    for (NSString *root in roots) {
        if ([real hasPrefix:[[root stringByResolvingSymlinksInPath] stringByAppendingString:@"/"]]) return YES;
    }
    return NO;
}

NSString *ExteriaPluginStoryScheduleTitle(void) {
    if (!ExteriaPluginsAreRunning()) return nil;
    id answer = ExteriaPluginsCallHost(@"story_page", [NSArray array]);
    id title = [answer isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)answer objectForKey:@"title"] : nil;
    return [title isKindOfClass:[NSString class]] && [title length] ? title : nil;
}

void ExteriaPluginStoryScheduleTapped(BOOL longPress) {
    if (!ExteriaPluginsAreRunning()) return;
    ExteriaPluginsCallHost(@"story_schedule", [NSArray arrayWithObject:[NSNumber numberWithBool:longPress]]);
}

BOOL ExteriaPluginStoryTaken(NSString *path, NSString *caption, ExteriaStoryAudience *audience, BOOL *keepFile) {
    if (keepFile) *keepFile = NO;
    if (!ExteriaPluginsAreRunning()) return NO;
    NSMutableDictionary *table = audiences();
    long long token = 0;
    if (audience) {
        if (table.count >= AUDIENCES_MAX) {
            ExteriaPluginsLog(@"exteria: a story was refused, %d stories of plugins already hold an audience", AUDIENCES_MAX);
            ExteriaShowNotice(nil, NSLocalizedString(@"story.schedule.full", nil));
            return YES;
        }
        token = ++g_next_token;
        [table setObject:audience forKey:[NSNumber numberWithLongLong:token]];
    }
    NSArray *arguments = [NSArray arrayWithObjects:path, caption ? caption : @"", [NSNumber numberWithLongLong:token], nil];
    id answer = ExteriaPluginsCallHost(@"story_intercept", arguments);
    BOOL taken = [answer isKindOfClass:[NSDictionary class]] && [[(NSDictionary *)answer objectForKey:@"taken"] boolValue];
    if (!taken) {
        /* python frees the number of a story it took when the story is let go; one it did not take is still ours */
        [table removeObjectForKey:[NSNumber numberWithLongLong:token]];
        return NO;
    }
    if (keepFile) *keepFile = [[(NSDictionary *)answer objectForKey:@"keep"] boolValue];
    return YES;
}

exteria_status ExteriaPluginStoryService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure) {
    (void)reply;
    if ([name isEqualToString:@"story.publish"]) {
        /* the plugin chose a time and presses the button the person would press; the screen is still up under the picker */
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![ExteriaStoryCameraController publishHeld]) ExteriaPluginsLog(@"exteria: a plugin pressed publish while no story screen holds a picture");
        });
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"story.forget"]) {
        id token = [request objectForKey:@"token"];
        if (![token isKindOfClass:[NSNumber class]]) {
            if (failure) *failure = @"no token";
            return EXTERIA_E_ARG;
        }
        [audiences() removeObjectForKey:token];
        return EXTERIA_OK;
    }
    return EXTERIA_E_UNSUPPORTED;
}
