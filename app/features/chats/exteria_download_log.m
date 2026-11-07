#import "exteria_download_log.h"

#import "exteria_chat_item.h"
#import "exteria_session_profile.h"

static NSString *ExteriaDownloadLogPath(ExteriaSession *session) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"];
    return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"downloads-%lld.plist", session.ownPerson.userId]];
}

static NSMutableArray *ExteriaDownloadLogRead(ExteriaSession *session) {
    NSArray *stored = [NSArray arrayWithContentsOfFile:ExteriaDownloadLogPath(session)];
    NSMutableArray *records = [NSMutableArray array];
    for (id record in stored) if ([record isKindOfClass:[NSDictionary class]]) [records addObject:record];
    return records;
}

void ExteriaDownloadLogAdd(ExteriaSession *session, ExteriaDialog *dialog, ExteriaMessage *message) {
    ExteriaMedia *media = message.media;
    if (!dialog || !media || message.messageId <= 0 || !media.file) return;
    exteria_preview_kind kind = media.kind;
    if (kind != EXTERIA_PREVIEW_FILE && kind != EXTERIA_PREVIEW_AUDIO && kind != EXTERIA_PREVIEW_VOICE && kind != EXTERIA_PREVIEW_VIDEO && kind != EXTERIA_PREVIEW_GIF) return;
    NSString *name = media.name.length ? media.name : (media.title.length ? media.title : ExteriaPreviewWord(kind));
    NSMutableArray *records = ExteriaDownloadLogRead(session);
    for (NSUInteger i = records.count; i > 0; --i) {
        NSDictionary *record = [records objectAtIndex:i - 1];
        if ([[record objectForKey:@"kind"] intValue] == dialog.peerKind && [[record objectForKey:@"id"] longLongValue] == dialog.peerId &&
            [[record objectForKey:@"message"] intValue] == message.messageId) [records removeObjectAtIndex:i - 1];
    }
    [records insertObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:dialog.peerKind], @"kind", [NSNumber numberWithLongLong:dialog.peerId], @"id",
                           [NSNumber numberWithLongLong:dialog.peerHash], @"hash", [NSNumber numberWithInt:(int)dialog.kind], @"dialogKind", dialog.title ?: @"", @"chat",
                           [NSNumber numberWithInt:message.messageId], @"message", name, @"name", [NSNumber numberWithLongLong:media.size], @"size",
                           [NSNumber numberWithInt:(int)[[NSDate date] timeIntervalSince1970]], @"date", nil] atIndex:0];
    while (records.count > EXTERIA_DOWNLOAD_LOG_MAX) [records removeLastObject];
    NSString *path = ExteriaDownloadLogPath(session);
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![records writeToFile:path atomically:YES]) NSLog(@"exteria: the list of downloads was not saved");
}

NSArray *ExteriaDownloadLogDialogs(ExteriaSession *session, NSString *query) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *record in ExteriaDownloadLogRead(session)) {
        NSString *name = [record objectForKey:@"name"], *chat = [record objectForKey:@"chat"];
        if (query.length) {
            NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
            if ([name rangeOfString:query options:options].location == NSNotFound && [chat rangeOfString:query options:options].location == NSNotFound) continue;
        }
        NSString *line = [NSString stringWithFormat:@"%@ · %@", chat, ExteriaFileSizeText([[record objectForKey:@"size"] longLongValue])];
        ExteriaDialog *row = [ExteriaDialog dialogWithPeerKind:[[record objectForKey:@"kind"] intValue] peerId:[[record objectForKey:@"id"] longLongValue]
                                                    accessHash:[[record objectForKey:@"hash"] longLongValue] kind:(exteria_dialog_kind)[[record objectForKey:@"dialogKind"] intValue]
                                                         title:name text:line date:[[record objectForKey:@"date"] intValue] messageId:[[record objectForKey:@"message"] intValue]];
        if (row) [rows addObject:row];
    }
    return rows;
}
