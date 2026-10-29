#import "exteria_name_badge.h"

#import "exteria_custom_emoji.h"
#import "exteria_developers.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_message.h"
#import "exteria_person.h"
#include "exteria_people.h"

/* a text symbol, not an emoji: the layout replaces it with the badge, and it draws nothing of its own while a status picture loads */
static NSString *const ExteriaBadgePlaceholder = @"★";

long long ExteriaBadgeDocument(long long emojiStatus, BOOL premium) {
    if (emojiStatus > 0) return emojiStatus;
    return premium ? EXTERIA_PREMIUM_STAR_DOCUMENT : 0;
}

long long ExteriaDialogBadgeDocument(ExteriaDialog *dialog) {
    if (dialog.peerKind == 1 && dialog.peerId == EXTERIA_TELEGRAM_SERVICE_USER_ID) return EXTERIA_TELEGRAM_VERIFIED_DOCUMENT;
    return dialog.saved ? 0 : ExteriaBadgeDocument(dialog.emojiStatus, dialog.premium);
}

long long ExteriaPersonBadgeDocument(ExteriaPerson *person) {
    if (person.userId == EXTERIA_TELEGRAM_SERVICE_USER_ID) return EXTERIA_TELEGRAM_VERIFIED_DOCUMENT;
    return ExteriaBadgeDocument(person.emojiStatus, person.premium);
}

NSString *ExteriaNameWithBadge(NSString *name, long long document, NSArray **entities) {
    return ExteriaNameWithBadges(name, document, NO, entities);
}

NSString *ExteriaNameWithBadges(NSString *name, long long document, NSUInteger marks, NSArray **entities) {
    if (entities) *entities = nil;
    if (marks & ExteriaMarkBugHunter) { document = 0; marks &= ExteriaMarkBugHunter | ExteriaMarkOfficialTester; }
    if ((!document && !marks) || !name.length) return name;
    NSMutableString *text = [NSMutableString stringWithString:name];
    NSMutableArray *list = [NSMutableArray array];
    long long documents[10] = {document, marks & ExteriaMarkDeveloper ? EXTERIA_DEVELOPER_DOCUMENT : 0, marks & ExteriaMarkLead ? EXTERIA_LEAD_DOCUMENT : 0,
                              marks & ExteriaMarkSenko ? EXTERIA_SENKO_DOCUMENT : 0, marks & ExteriaMarkTester ? EXTERIA_TESTER_DOCUMENT : 0,
                              marks & ExteriaMarkCaution ? EXTERIA_CAUTION_DOCUMENT : 0, marks & ExteriaMarkPromotion ? EXTERIA_PROMOTION_DOCUMENT : 0,
                              marks & ExteriaMarkBugHunter ? EXTERIA_BUG_HUNTER_DOCUMENT : 0, marks & ExteriaMarkOfficialTester ? EXTERIA_OFFICIAL_TESTER_DOCUMENT : 0,
                               marks & ExteriaMarkManager ? EXTERIA_MANAGER_DOCUMENT : 0};
    for (int i = 0; i < 10; ++i) {
        if (!documents[i]) continue;
        [text appendString:@" "];
        ExteriaTextEntity *entity = [[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleCustomEmoji
            range:NSMakeRange(text.length, ExteriaBadgePlaceholder.length) url:nil] autorelease];
        entity.documentId = documents[i];
        [list addObject:entity];
        [text appendString:ExteriaBadgePlaceholder];
    }
    if (entities) *entities = list;
    return text;
}

void ExteriaLoadBadgePictures(NSArray *documents, ExteriaSession *session, ExteriaMediaCache *media, void (^redraw)(void)) {
    NSMutableArray *wanted = [NSMutableArray array];
    for (NSNumber *document in documents) {
        if (document.longLongValue > 0 && ![wanted containsObject:document]) [wanted addObject:document];
    }
    if (!wanted.count || !session || !media) return;
    [ExteriaCustomEmojiLoader loadDocuments:wanted session:session media:media documents:nil picture:redraw];
}

static void ExteriaRedrawTreeOfView(UIView *view) {
    [view setNeedsDisplay];
    for (UIView *child in view.subviews) ExteriaRedrawTreeOfView(child);
}

void ExteriaRedrawVisibleRows(UITableView *table) {
    for (UITableViewCell *cell in table.visibleCells) ExteriaRedrawTreeOfView(cell.contentView);
}
