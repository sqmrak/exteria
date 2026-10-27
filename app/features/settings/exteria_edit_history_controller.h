#import "exteria_settings_kit.h"

/* what a message said before its edits, after the history of changes of AyuMoments: the text it has now, and under
   it each text it had, the newest first */
@interface ExteriaEditHistoryController : ExteriaSettingsPageController

/* versions are ExteriaMessage items, the oldest first; current is what the message says now, date when it was written */
- (id)initWithVersions:(NSArray *)versions current:(NSString *)current date:(int32_t)date;

@end
