#import "exteria_draft.h"

#import "exteria_message.h"

NSString *const ExteriaDraftDidChangeNotification = @"ExteriaDraftDidChange";

/* a row draws two lines of this at most; a longer draft only costs layout time */
#define PREVIEW_CHARACTERS 150

@implementation ExteriaDraft

@synthesize text = _text;
@synthesize entities = _entities;
@synthesize replyTo = _replyTo;
@synthesize noWebpage = _noWebpage;
@synthesize date = _date;

- (id)initWithText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo noWebpage:(BOOL)noWebpage date:(int32_t)date {
    self = [super init];
    if (!self) return nil;
    _text = [text ? text : @"" copy];
    _entities = [entities copy];
    _replyTo = replyTo;
    _noWebpage = noWebpage;
    _date = date;
    return self;
}

- (void)dealloc {
    [_text release];
    [_entities release];
    [super dealloc];
}

+ (ExteriaDraft *)draftWithRow:(const exteria_draft *)row {
    if (!row || !row->present) return nil;
    NSString *text = [NSString stringWithUTF8String:row->text];
    if (!text) text = @"";
    NSArray *entities = ExteriaTextEntities(text, row->entities, row->entity_count, row->urls);
    return [[[ExteriaDraft alloc] initWithText:text entities:entities replyTo:row->reply_to noWebpage:row->no_webpage != 0 date:row->date] autorelease];
}

- (BOOL)empty {
    return !_text.length && !_replyTo;
}

@end

static NSString *ExteriaDraftKey(int32_t kind, long long peer, int32_t top) {
    /* the General topic is the chat itself */
    return [NSString stringWithFormat:@"%d:%lld:%d", (int)kind, peer, top > 1 ? (int)top : 0];
}

@implementation ExteriaDraftBoard

- (id)init {
    self = [super init];
    if (!self) return nil;
    _drafts = [[NSMutableDictionary alloc] init];
    _unsaved = [[NSCountedSet alloc] init];
    return self;
}

- (void)dealloc {
    [_drafts release];
    [_unsaved release];
    [super dealloc];
}

- (ExteriaDraft *)draftForKind:(int32_t)kind peer:(long long)peer top:(int32_t)top {
    return [_drafts objectForKey:ExteriaDraftKey(kind, peer, top)];
}

- (ExteriaDraft *)draftForDialog:(ExteriaDialog *)dialog {
    if (dialog.folder || dialog.community || dialog.savedSource) return nil;
    return [self draftForKind:dialog.peerKind peer:dialog.peerId top:dialog.topicId];
}

- (void)postChangeKind:(int32_t)kind peer:(long long)peer top:(int32_t)top local:(BOOL)local {
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDraftDidChangeNotification object:self
        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kind], @"kind", [NSNumber numberWithLongLong:peer], @"peer",
                  [NSNumber numberWithInt:top > 1 ? top : 0], @"top", [NSNumber numberWithBool:local], @"local", nil]];
}

- (BOOL)storeDraft:(ExteriaDraft *)draft key:(NSString *)key {
    ExteriaDraft *before = [_drafts objectForKey:key];
    if (!draft || draft.empty) {
        if (!before) return NO;
        [_drafts removeObjectForKey:key];
        return YES;
    }
    if (before && [before.text isEqualToString:draft.text] && before.replyTo == draft.replyTo && before.noWebpage == draft.noWebpage &&
        before.date == draft.date) return NO;
    [_drafts setObject:draft forKey:key];
    return YES;
}

- (void)setLocalDraft:(ExteriaDraft *)draft kind:(int32_t)kind peer:(long long)peer top:(int32_t)top {
    NSString *key = ExteriaDraftKey(kind, peer, top);
    [_unsaved addObject:key];
    if ([self storeDraft:draft key:key]) [self postChangeKind:kind peer:peer top:top local:YES];
}

- (void)noteSavedKind:(int32_t)kind peer:(long long)peer top:(int32_t)top {
    [_unsaved removeObject:ExteriaDraftKey(kind, peer, top)];
}

- (void)noteAccountDraft:(ExteriaDraft *)draft kind:(int32_t)kind peer:(long long)peer top:(int32_t)top {
    NSString *key = ExteriaDraftKey(kind, peer, top);
    if ([_unsaved containsObject:key]) return;
    if ([self storeDraft:draft key:key]) [self postChangeKind:kind peer:peer top:top local:NO];
}

- (void)noteListed:(NSArray *)entries complete:(BOOL)complete {
    for (NSArray *entry in entries) {
        int32_t kind = [[entry objectAtIndex:0] intValue], top = [[entry objectAtIndex:2] intValue];
        long long peer = [[entry objectAtIndex:1] longLongValue];
        ExteriaDraft *draft = [entry objectAtIndex:3];
        if ([draft isKindOfClass:[NSNull class]]) {
            /* a kept list is older than what the board heard since, so it cannot say that a draft is gone */
            if (!complete) continue;
            draft = nil;
        } else if (!complete && [self draftForKind:kind peer:peer top:top]) {
            continue;
        }
        [self noteAccountDraft:draft kind:kind peer:peer top:top];
    }
}

- (void)removeAll {
    NSArray *keys = [_drafts allKeys];
    [_drafts removeAllObjects];
    [_unsaved removeAllObjects];
    for (NSString *key in keys) {
        NSArray *parts = [key componentsSeparatedByString:@":"];
        [self postChangeKind:[[parts objectAtIndex:0] intValue] peer:[[parts objectAtIndex:1] longLongValue] top:[[parts objectAtIndex:2] intValue] local:NO];
    }
}

@end

BOOL ExteriaDraftChangeConcerns(NSNotification *note, ExteriaDialog *dialog) {
    NSDictionary *info = note.userInfo;
    return [[info objectForKey:@"kind"] intValue] == dialog.peerKind && [[info objectForKey:@"peer"] longLongValue] == dialog.peerId &&
           [[info objectForKey:@"top"] intValue] == (dialog.topicId > 1 ? dialog.topicId : 0);
}

ExteriaDraft *ExteriaVisibleDraft(ExteriaDraftBoard *board, ExteriaDialog *dialog) {
    if (!board || dialog.folder || dialog.community || dialog.savedSource || dialog.left) return nil;
    /* the row of a forum lists topics; each topic row has the draft of its own thread */
    if (dialog.forum && !dialog.topicId) return nil;
    ExteriaDraft *draft = [board draftForDialog:dialog];
    if (!draft || !draft.text.length) return nil;
    if (dialog.date > draft.date && dialog.unreadCount > 0) return nil;
    return draft;
}

int32_t ExteriaDialogSortDate(ExteriaDraftBoard *board, ExteriaDialog *dialog) {
    ExteriaDraft *draft = ExteriaVisibleDraft(board, dialog);
    return draft && draft.date > dialog.date ? draft.date : dialog.date;
}

NSArray *ExteriaDialogsMovedForDraft(NSArray *dialogs, ExteriaDraftBoard *board, int32_t kind, long long peer, int32_t top) {
    NSUInteger from = NSNotFound;
    for (NSUInteger i = 0; i < dialogs.count; ++i) {
        ExteriaDialog *dialog = [dialogs objectAtIndex:i];
        if (dialog.peerKind == kind && dialog.peerId == peer && (dialog.topicId > 1 ? dialog.topicId : 0) == (top > 1 ? top : 0) && !dialog.folder && !dialog.community) {
            from = i;
            break;
        }
    }
    if (from == NSNotFound) return dialogs;
    ExteriaDialog *moved = [dialogs objectAtIndex:from];
    if (moved.pinned) return dialogs;
    int32_t date = ExteriaDialogSortDate(board, moved);
    NSMutableArray *rest = [NSMutableArray arrayWithArray:dialogs];
    [rest removeObjectAtIndex:from];
    NSUInteger to = rest.count;
    for (NSUInteger i = 0; i < rest.count; ++i) {
        ExteriaDialog *other = [rest objectAtIndex:i];
        if (other.pinned || other.folder) continue;
        if (ExteriaDialogSortDate(board, other) < date) {
            to = i;
            break;
        }
    }
    if (to == from) return dialogs;
    [rest insertObject:moved atIndex:to];
    return rest;
}

NSString *ExteriaDraftPreviewText(ExteriaDraft *draft) {
    NSString *text = draft.text;
    if (text.length > PREVIEW_CHARACTERS) {
        NSRange cut = [text rangeOfComposedCharacterSequenceAtIndex:PREVIEW_CHARACTERS - 1];
        text = [text substringToIndex:NSMaxRange(cut)];
    }
    NSMutableString *flat = [NSMutableString stringWithString:text];
    [flat replaceOccurrencesOfString:@"\r\n" withString:@" " options:0 range:NSMakeRange(0, flat.length)];
    [flat replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, flat.length)];
    [flat replaceOccurrencesOfString:@"\r" withString:@" " options:0 range:NSMakeRange(0, flat.length)];
    return flat;
}
