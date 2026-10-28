#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_session.h"

/* the mark after the name of a Telegram Premium user: the custom emoji they chose as a status, or the Premium star
   when they chose none */

/* the document to draw after a name: the live status, else the Premium star for a Premium user, else zero */
long long ExteriaBadgeDocument(long long emojiStatus, BOOL premium);
long long ExteriaDialogBadgeDocument(ExteriaDialog *dialog);
long long ExteriaPersonBadgeDocument(ExteriaPerson *person);

/* the name followed by the badge, with the entity list that draws it in entities; the name unchanged and nil entities for document zero */
NSString *ExteriaNameWithBadge(NSString *name, long long document, NSArray **entities);

/* the same with the hammer of the developers after the status badge, for a person who took part in the development of Exteria; developer NO is the call above */
NSString *ExteriaNameWithBadges(NSString *name, long long document, NSUInteger marks, NSArray **entities);

/* fetches the pictures of the statuses among documents (NSNumbers; the star and zero are skipped); redraw runs on
   the main thread each time one lands */
/* draws the rows on screen again, for a picture that landed after they were laid out; it changes no size */
void ExteriaRedrawVisibleRows(UITableView *table);

void ExteriaLoadBadgePictures(NSArray *documents, ExteriaSession *session, ExteriaMediaCache *media, void (^redraw)(void));
