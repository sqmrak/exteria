#import "exteria_forum_summaries.h"

#import "exteria_dialog.h"

/* the counts of the topics change without the last message of the forum moving, as when another device reads one */
#define SUMMARY_MAX_AGE 60.0

@interface ExteriaForumSummaries () {
    NSMutableDictionary *_kept;
    NSMutableDictionary *_dates;
    NSMutableDictionary *_messages;
    NSMutableSet *_reading;
}
@end

@implementation ExteriaForumSummaries

- (id)init {
    self = [super init];
    if (!self) return nil;
    _kept = [[NSMutableDictionary alloc] init];
    _dates = [[NSMutableDictionary alloc] init];
    _messages = [[NSMutableDictionary alloc] init];
    _reading = [[NSMutableSet alloc] init];
    return self;
}

- (void)dealloc {
    [_kept release];
    [_dates release];
    [_messages release];
    [_reading release];
    [super dealloc];
}

- (void)applyToDialogs:(NSArray *)dialogs {
    @synchronized (self) {
        for (ExteriaDialog *dialog in dialogs) {
            if (!dialog.forum) continue;
            NSData *kept = [_kept objectForKey:[NSNumber numberWithLongLong:dialog.peerId]];
            if (kept.length == sizeof(exteria_forum_summary)) [dialog applyForumSummary:(const exteria_forum_summary *)kept.bytes];
        }
    }
}

- (void)setSummary:(const exteria_forum_summary *)summary forForum:(int64_t)peerId topMessage:(int32_t)topMessage {
    if (!summary) return;
    NSNumber *key = [NSNumber numberWithLongLong:peerId];
    @synchronized (self) {
        [_kept setObject:[NSData dataWithBytes:summary length:sizeof(*summary)] forKey:key];
        [_dates setObject:[NSDate date] forKey:key];
        [_messages setObject:[NSNumber numberWithInt:topMessage] forKey:key];
    }
}

- (BOOL)beginReadingForum:(int64_t)peerId topMessage:(int32_t)topMessage {
    NSNumber *key = [NSNumber numberWithLongLong:peerId];
    @synchronized (self) {
        if ([_reading containsObject:key]) return NO;
        NSDate *date = [_dates objectForKey:key];
        if (date && [[_messages objectForKey:key] intValue] == topMessage && -[date timeIntervalSinceNow] < SUMMARY_MAX_AGE) return NO;
        [_reading addObject:key];
    }
    return YES;
}

- (void)endReadingForum:(int64_t)peerId {
    @synchronized (self) {
        [_reading removeObject:[NSNumber numberWithLongLong:peerId]];
    }
}

@end
