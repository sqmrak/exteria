#import "exteria_text_filter.h"

#import "exteria_chat_settings.h"
#import "exteria_photo.h"

#include "exteria_zalgo.h"

NSString *ExteriaFilteredText(NSString *text) {
    if (!text.length || !ExteriaChatFlagGet(ExteriaChatFlagFilterZalgo)) return text;
    const char *bytes = text.UTF8String;
    if (!bytes) return text;
    size_t size = strlen(bytes) + 1;
    char *buffer = malloc(size);
    if (!buffer) return text;
    NSString *result = text;
    size_t written = exteria_zalgo_filter(bytes, buffer, size);
    if (written != (size_t)-1 && written < size - 1) {
        NSString *filtered = [NSString stringWithUTF8String:buffer];
        if (filtered) result = filtered;
    }
    free(buffer);
    return result;
}

NSString *ExteriaOwnPhoneText(NSString *phone) {
    if (!phone.length) return @"";
    if (!ExteriaChatFlagGet(ExteriaChatFlagHidePhone)) return [@"+" stringByAppendingString:phone];
    return [@"+" stringByAppendingString:[@"" stringByPaddingToLength:phone.length withString:@"\u2022" startingAtIndex:0]];
}

NSArray *ExteriaIdentityRows(long long peerId, ExteriaPhoto *photo) {
    NSMutableArray *rows = [NSMutableArray array];
    if (!ExteriaChatFlagGet(ExteriaChatFlagShowIds) || peerId <= 0) return rows;
    [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.id", nil), [NSString stringWithFormat:@"%lld", peerId], nil]];
    if (photo && photo.ref.dc > 0) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.dc", nil), [NSString stringWithFormat:@"%d", (int)photo.ref.dc], nil]];
    return rows;
}
