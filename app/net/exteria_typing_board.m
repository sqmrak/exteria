#import "exteria_typing_board.h"

#include "exteria_typing.h"

NSString *const ExteriaTypingDidChangeNotification = @"ExteriaTypingDidChange";

/* the server repeats an action every few seconds while it goes on, and the clients let it run out after six */
#define TYPING_LIFETIME_SECONDS 6.0

@interface ExteriaTypingEntry : NSObject {
@public
    int32_t kind;
    long long peer;
    long long user;
    int32_t top;
    int action;
    NSString *name;
    NSTimeInterval expires;
}
@end

@implementation ExteriaTypingEntry
- (void)dealloc {
    [name release];
    [super dealloc];
}
@end

@implementation ExteriaTypingBoard

- (id)init {
    self = [super init];
    if (!self) return nil;
    _entries = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_entries release];
    [super dealloc];
}

static NSTimeInterval ExteriaTypingNow(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

static BOOL ExteriaTypingSamePerson(ExteriaTypingEntry *entry, int32_t kind, long long peer, long long user, int32_t top) {
    return entry->kind == kind && entry->peer == peer && entry->user == user && entry->top == top;
}

static NSString *const ExteriaTypingKindKey = @"kind";
static NSString *const ExteriaTypingPeerKey = @"peer";

BOOL ExteriaTypingChangeConcerns(NSNotification *note, ExteriaDialog *dialog) {
    NSNumber *kind = [note.userInfo objectForKey:ExteriaTypingKindKey], *peer = [note.userInfo objectForKey:ExteriaTypingPeerKey];
    if (![kind isKindOfClass:[NSNumber class]] || ![peer isKindOfClass:[NSNumber class]]) return YES;
    return kind.intValue == dialog.peerKind && peer.longLongValue == dialog.peerId;
}

- (void)changedKind:(int32_t)kind peer:(long long)peer {
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kind], ExteriaTypingKindKey,
                          [NSNumber numberWithLongLong:peer], ExteriaTypingPeerKey, nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaTypingDidChangeNotification object:self userInfo:info];
}

/* one pass that drops what has run out and sets the next one for the soonest of the rest */
- (void)expire {
    _timerSet = NO;
    NSTimeInterval now = ExteriaTypingNow();
    NSMutableArray *gone = [NSMutableArray array];
    for (NSInteger i = (NSInteger)_entries.count - 1; i >= 0; --i) {
        ExteriaTypingEntry *entry = [_entries objectAtIndex:(NSUInteger)i];
        if (entry->expires <= now) {
            [gone addObject:entry];
            [_entries removeObjectAtIndex:(NSUInteger)i];
        }
    }
    [self scheduleExpiry];
    /* one report for each chat that lost someone, however many people ran out in it */
    for (NSUInteger i = 0; i < gone.count; ++i) {
        ExteriaTypingEntry *entry = [gone objectAtIndex:i];
        BOOL reported = NO;
        for (NSUInteger earlier = 0; earlier < i && !reported; ++earlier) {
            ExteriaTypingEntry *other = [gone objectAtIndex:earlier];
            reported = other->kind == entry->kind && other->peer == entry->peer;
        }
        if (!reported) [self changedKind:entry->kind peer:entry->peer];
    }
}

- (void)scheduleExpiry {
    if (_timerSet || !_entries.count) return;
    NSTimeInterval soonest = 0, now = ExteriaTypingNow();
    for (ExteriaTypingEntry *entry in _entries) {
        if (!soonest || entry->expires < soonest) soonest = entry->expires;
    }
    _timerSet = YES;
    [self performSelector:@selector(expire) withObject:nil afterDelay:MAX(0.05, soonest - now)];
}

- (void)noteKind:(int32_t)kind peer:(long long)peer user:(long long)user action:(int)action top:(int32_t)top {
    [self noteKind:kind peer:peer user:user action:action top:top name:nil];
}

- (NSArray *)namesInDialog:(ExteriaDialog *)dialog {
    NSMutableArray *names = [NSMutableArray array];
    for (ExteriaTypingEntry *entry in _entries) {
        if ([self entry:entry belongsToDialog:dialog] && entry->name.length) [names addObject:entry->name];
    }
    return names;
}

- (void)noteKind:(int32_t)kind peer:(long long)peer user:(long long)user action:(int)action top:(int32_t)top name:(NSString *)name {
    ExteriaTypingEntry *found = nil;
    for (ExteriaTypingEntry *entry in _entries) {
        if (ExteriaTypingSamePerson(entry, kind, peer, user, top)) {
            found = entry;
            break;
        }
    }
    if (action == EXTERIA_TYPING_CANCEL) {
        if (!found) return;
        [_entries removeObject:found];
        [self changedKind:kind peer:peer];
        return;
    }
    BOOL fresh = found == nil || found->action != action;
    if (!found) {
        found = [[[ExteriaTypingEntry alloc] init] autorelease];
        found->kind = kind;
        found->peer = peer;
        found->user = user;
        found->top = top;
        [_entries addObject:found];
    }
    found->action = action;
    if (name.length && ![name isEqualToString:found->name]) {
        [found->name release];
        found->name = [name copy];
        fresh = YES;
    }
    found->expires = ExteriaTypingNow() + TYPING_LIFETIME_SECONDS;
    [self scheduleExpiry];
    /* a repeat of the same action only moves its end, which no screen shows */
    if (fresh) [self changedKind:kind peer:peer];
}

- (BOOL)entry:(ExteriaTypingEntry *)entry belongsToDialog:(ExteriaDialog *)dialog {
    if (entry->kind != dialog.peerKind || entry->peer != dialog.peerId) return NO;
    /* a topic shows its own thread and a whole chat shows every thread of it */
    return dialog.topicId <= 0 || entry->top == dialog.topicId;
}

- (NSUInteger)countInDialog:(ExteriaDialog *)dialog {
    NSUInteger count = 0;
    for (ExteriaTypingEntry *entry in _entries) {
        if ([self entry:entry belongsToDialog:dialog]) ++count;
    }
    return count;
}

- (int)actionInDialog:(ExteriaDialog *)dialog {
    int best = EXTERIA_TYPING_CANCEL;
    for (ExteriaTypingEntry *entry in _entries) {
        if (![self entry:entry belongsToDialog:dialog]) continue;
        if (entry->action == EXTERIA_TYPING_TEXT) return EXTERIA_TYPING_TEXT;
        if (best == EXTERIA_TYPING_CANCEL) best = entry->action;
    }
    return best;
}

@end
