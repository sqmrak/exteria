#import "exteria_settings_kit.h"
#import "exteria_session.h"

@class ExteriaMediaCache;
@class ExteriaAvatarCache;

/* the picture a list row shows for a reaction: the emoji, or the custom emoji once its document is loaded; nil while it is not */
UIImage *ExteriaReactionRowImage(ExteriaReaction *reaction);
/* asks for the documents of the custom reactions among the items (dictionaries with a @"reaction"), remembers the emoji they stand for, and then runs done */
void ExteriaLoadReactionDocuments(NSArray *items, ExteriaSession *session, ExteriaMediaCache *media, void (^done)(void));

@interface ExteriaReactionPeopleController : ExteriaSettingsPageController
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog messageId:(int32_t)messageId avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
@end
