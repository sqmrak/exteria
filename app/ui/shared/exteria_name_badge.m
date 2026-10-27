#import "exteria_name_badge.h"

#import "exteria_custom_emoji.h"
#import "exteria_developers.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_message.h"

/* a text symbol, not an emoji: the layout replaces it with the badge, and it draws nothing of its own while a status picture loads */
static NSString *const ExteriaBadgePlaceholder = @"★";

long long ExteriaBadgeDocument(long long emojiStatus, BOOL premium) {
    if (emojiStatus > 0) return emojiStatus;
    return premium ? EXTERIA_PREMIUM_STAR_DOCUMENT : 0;
}

NSString *ExteriaNameWithBadge(NSString *name, long long document, NSArray **entities) {
    return ExteriaNameWithBadges(name, document, NO, entities);
}

NSString *ExteriaNameWithBadges(NSString *name, long long document, NSUInteger marks, NSArray **entities) {
    if (entities) *entities = nil;
    if ((!document && !marks) || !name.length) return name;
    NSMutableString *text = [NSMutableString stringWithString:name];
    NSMutableArray *list = [NSMutableArray array];
    long long documents[6] = {document, marks & ExteriaMarkDeveloper ? EXTERIA_DEVELOPER_DOCUMENT : 0, marks & ExteriaMarkLead ? EXTERIA_LEAD_DOCUMENT : 0,
                              marks & ExteriaMarkSenko ? EXTERIA_SENKO_DOCUMENT : 0, marks & ExteriaMarkTester ? EXTERIA_TESTER_DOCUMENT : 0,
                              marks & ExteriaMarkCaution ? EXTERIA_CAUTION_DOCUMENT : 0};
    for (int i = 0; i < 6; ++i) {
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
