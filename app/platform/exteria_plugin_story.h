#import <Foundation/Foundation.h>

#import "exteria_status.h"

@class ExteriaStoryAudience;

/* what a plugin can do with the story screen: put a button beside "publish" and take a story before it goes up (the story scheduler holds it and
   publishes it later through the account operation story_post). python/shim/org/telegram/ui/Stories holds the other half.


   audiences that name people live here, by number, while python holds a story: an ExteriaPerson cannot be rebuilt from numbers in python, and a story meant
   for close friends must never go to everyone because its audience was lost */

/* the words of the button a plugin asked for, nil when none did or none is running */
NSString *ExteriaPluginStoryScheduleTitle(void);
/* that button was tapped, or publish was held (longPress) */
void ExteriaPluginStoryScheduleTapped(BOOL longPress);

/* a story about to go up. YES when a plugin took it: the screen must not publish it. *keepFile is YES when the plugin still reads the file, so the screen must
   not delete it; python then owns the file and the audience */
BOOL ExteriaPluginStoryTaken(NSString *path, NSString *caption, ExteriaStoryAudience *audience, BOOL *keepFile);

/* the audience held under a number (retained by the table, nil for zero or an unknown number) */
ExteriaStoryAudience *ExteriaPluginStoryAudience(long long token);
/* whether path, with symlinks resolved, is a file a plugin may publish as a story: one the story screen wrote, or one in the plugins folder */
BOOL ExteriaPluginStoryPathAllowed(NSString *path);

/* the services "story.*": publish (the story screen publishes what it holds, as its button does) and forget (the audience of a number is let go) */
exteria_status ExteriaPluginStoryService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure);
