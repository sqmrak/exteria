#import "exteria_custom_gift.h"

#import "exteria_developers.h"
#import "exteria_person.h"
#import "exteria_session_bots.h"

#include <string.h>

/* the gifts, in the order of their numbers */
typedef struct {
    int32_t number;
    int64_t giftId;
    const char *title;
    const char *model;
    const char *symbol;
    const char *backdrop;
    uint32_t center, edge, text, pattern;
    int32_t date;
} ExteriaCustomGiftSpec;

static const ExteriaCustomGiftSpec ExteriaCustomGiftSpecs[] = {
    /* #001: a plush Senko from the lead developer, on warm amber */
    {1, -1, "Senko", "Plush Senko", "Soft Shapes", "Amber Glow", 0xFFB74D, 0xE65100, 0xFFE9C7, 0xFFFFFF, 1793222400}
};
#define CUSTOM_GIFT_COUNT (sizeof(ExteriaCustomGiftSpecs) / sizeof(ExteriaCustomGiftSpecs[0]))
static NSString *const ExteriaCustomGiftSenderUsername = @"sqmrak";
static NSString *const ExteriaCustomGiftNote = @"чееее ахахахахах";
static NSString *const ExteriaCustomGiftImage = @"gift_custom_senko";

NSString *ExteriaCustomGiftNumberText(int32_t number) {
    return [NSString stringWithFormat:@"#%03d", (int)number];
}

/* main thread only */
static ExteriaPerson *ExteriaCustomGiftSender;
static NSMutableArray *ExteriaCustomGiftWaiting;
/* a failed ask is not repeated by every page: the gift then names him without a picture */
static BOOL ExteriaCustomGiftAsked;

static BOOL ExteriaCustomGiftApplies(ExteriaDialog *owner) {
    /* the profile of the account itself is asked through its saved messages, which carry its own user id */
    return owner && owner.peerKind == 1 && ExteriaIsDeveloperId(owner.peerId);
}

BOOL ExteriaCustomGiftNeedsSender(ExteriaDialog *owner) {
    return !ExteriaCustomGiftSender && !ExteriaCustomGiftAsked && ExteriaCustomGiftApplies(owner);
}

void ExteriaCustomGiftLoadSender(ExteriaSession *session, void (^done)(void)) {
    if (ExteriaCustomGiftSender || ExteriaCustomGiftAsked || !session) {
        done();
        return;
    }
    if (!ExteriaCustomGiftWaiting) ExteriaCustomGiftWaiting = [[NSMutableArray alloc] init];
    BOOL running = ExteriaCustomGiftWaiting.count > 0;
    [ExteriaCustomGiftWaiting addObject:[[done copy] autorelease]];
    if (running) return;
    [session resolveUsername:ExteriaCustomGiftSenderUsername completion:^(ExteriaDialog *dialog, ExteriaPerson *person, NSString *errorName) {
        (void)dialog;
        ExteriaCustomGiftAsked = YES;
        if (person && person.userId > 0) ExteriaCustomGiftSender = [person retain];
        else NSLog(@"exteria: the sender of the custom gift was not resolved: %@", errorName);
        NSArray *waiting = [[ExteriaCustomGiftWaiting copy] autorelease];
        [ExteriaCustomGiftWaiting removeAllObjects];
        for (void (^waiter)(void) in waiting) waiter();
    }];
}

NSArray *ExteriaCustomGiftsForDialog(ExteriaDialog *owner) {
    if (!ExteriaCustomGiftApplies(owner)) return [NSArray array];
    NSMutableArray *gifts = [NSMutableArray arrayWithCapacity:CUSTOM_GIFT_COUNT];
    for (size_t i = 0; i < CUSTOM_GIFT_COUNT; ++i) {
        const ExteriaCustomGiftSpec *spec = &ExteriaCustomGiftSpecs[i];
        exteria_saved_gift row;
        memset(&row, 0, sizeof(row));
        row.gift.id = spec->giftId;
        row.gift.catalog_id = spec->giftId;
        row.gift.unique = 1;
        row.gift.num = spec->number;
        row.gift.has_backdrop = 1;
        row.gift.backdrop_center = spec->center;
        row.gift.backdrop_edge = spec->edge;
        row.gift.backdrop_text = spec->text;
        row.gift.backdrop_pattern = spec->pattern;
        snprintf(row.gift.title, sizeof(row.gift.title), "%s", spec->title);
        snprintf(row.gift.model, sizeof(row.gift.model), "%s", spec->model);
        snprintf(row.gift.pattern, sizeof(row.gift.pattern), "%s", spec->symbol);
        snprintf(row.gift.backdrop, sizeof(row.gift.backdrop), "%s", spec->backdrop);
        /* until the server has told who he is, the id the credits learned and his username stand for him */
        row.from_id = ExteriaDeveloperIdOfUsername(ExteriaCustomGiftSenderUsername);
        snprintf(row.from_name, sizeof(row.from_name), "%s", ExteriaCustomGiftSenderUsername.UTF8String);
        snprintf(row.note, sizeof(row.note), "%s", ExteriaCustomGiftNote.UTF8String);
        row.date = spec->date;
        /* they stand first on the profile, as pinned gifts do, and wear the pin */
        row.pinned = 1;
        ExteriaSavedGift *gift = [ExteriaSavedGift savedGiftWithRow:&row];
        gift.customImageName = ExteriaCustomGiftImage;
        [gift setSenderPerson:ExteriaCustomGiftSender];
        [gifts addObject:gift];
    }
    return gifts;
}
