#import "exteria_table_update.h"

#import "exteria_lite_mode.h"
#import "exteria_platform.h"

#include "exteria_list_moves.h"

/* a longer list of changes is a different list, not a few chats that moved */
#define MAX_CHANGED_ROWS 40

BOOL ExteriaTableUpdateRows(UITableView *table, NSArray *oldKeys, NSArray *newKeys, void (^refresh)(UITableViewCell *cell, NSUInteger newIndex)) {
    NSUInteger oldCount = oldKeys.count, newCount = newKeys.count;
    if (!table.window || !ExteriaLiteSmoothTransitions() || ExteriaReduceMotionEnabled() || ![UIView areAnimationsEnabled]) return NO;
    if (oldCount == 0 || oldCount > EXTERIA_LIST_MOVES_MAX || newCount > EXTERIA_LIST_MOVES_MAX) return NO;
    /* the table counts the rows of its last load, and a caller whose keys went stale would otherwise make UIKit raise on endUpdates */
    if ((NSUInteger)[table numberOfRowsInSection:0] != oldCount) return NO;
    NSMutableDictionary *newIndex = [NSMutableDictionary dictionaryWithCapacity:newCount];
    for (NSUInteger i = 0; i < newCount; ++i) {
        id key = [newKeys objectAtIndex:i];
        if ([newIndex objectForKey:key]) return NO;
        [newIndex setObject:[NSNumber numberWithUnsignedInteger:i] forKey:key];
    }
    int32_t target[EXTERIA_LIST_MOVES_MAX];
    uint8_t keep[EXTERIA_LIST_MOVES_MAX];
    BOOL claimed[EXTERIA_LIST_MOVES_MAX];
    NSMutableSet *seen = [NSMutableSet setWithCapacity:oldCount];
    NSUInteger removed = 0, surviving = 0;
    memset(claimed, 0, sizeof(claimed));
    for (NSUInteger i = 0; i < oldCount; ++i) {
        id key = [oldKeys objectAtIndex:i];
        NSNumber *found = [newIndex objectForKey:key];
        if ([seen containsObject:key]) return NO;
        [seen addObject:key];
        if (!found) {
            target[i] = -1;
            ++removed;
            continue;
        }
        target[i] = (int32_t)found.unsignedIntegerValue;
        claimed[found.unsignedIntegerValue] = YES;
        ++surviving;
    }
    NSUInteger inserted = newCount - surviving;
    if (removed + inserted > MAX_CHANGED_ROWS) return NO;
    if (oldCount - removed + inserted != newCount) return NO;
    if (exteria_list_keep(target, oldCount, keep, sizeof(keep)) != EXTERIA_OK) return NO;

    /* a survivor takes its new content where it stands, so the move carries a finished row */
    if (refresh) {
        for (NSUInteger i = 0; i < oldCount; ++i) {
            if (target[i] < 0) continue;
            UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
            if (cell) refresh(cell, (NSUInteger)target[i]);
        }
    }
    NSMutableArray *deletes = [NSMutableArray arrayWithCapacity:removed], *inserts = [NSMutableArray arrayWithCapacity:inserted];
    for (NSUInteger i = 0; i < oldCount; ++i) {
        if (target[i] < 0) [deletes addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    }
    for (NSUInteger i = 0; i < newCount; ++i) {
        if (!claimed[i]) [inserts addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    }
    [table beginUpdates];
    if (deletes.count) [table deleteRowsAtIndexPaths:deletes withRowAnimation:UITableViewRowAnimationFade];
    if (inserts.count) [table insertRowsAtIndexPaths:inserts withRowAnimation:UITableViewRowAnimationFade];
    for (NSUInteger i = 0; i < oldCount; ++i) {
        if (target[i] < 0 || keep[i]) continue;
        [table moveRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0] toIndexPath:[NSIndexPath indexPathForRow:target[i] inSection:0]];
    }
    [table endUpdates];
    return YES;
}
