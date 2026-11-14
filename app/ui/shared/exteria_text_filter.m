#import "exteria_text_filter.h"

#import "exteria_chat_settings.h"
#import "exteria_photo.h"

#include "exteria_phone.h"
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

/* the dial code table is read once, from the list the phone screens share; nothing is grouped when the list does not load */
static const exteria_country *ExteriaPhoneCountries(size_t *count) {
    static exteria_country *table = NULL;
    static size_t tableCount = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"countries" ofType:@"txt"];
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        exteria_country *made = calloc(EXTERIA_COUNTRY_MAX, sizeof(exteria_country));
        exteria_status status = data && made ? exteria_country_parse(data.bytes, data.length, made, EXTERIA_COUNTRY_MAX, &tableCount) : EXTERIA_E_NOTFOUND;
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: country list for phone numbers did not load (%s)", exteria_status_name(status));
            free(made);
            tableCount = 0;
            return;
        }
        table = made;
    });
    *count = tableCount;
    return table;
}

NSString *ExteriaPhoneDisplay(NSString *phone) {
    if (!phone.length) return @"";
    char digits[EXTERIA_PHONE_MAX_DIGITS + 1];
    char shown[64];
    size_t count = 0;
    const exteria_country *table = ExteriaPhoneCountries(&count);
    if (!exteria_phone_digits(phone.UTF8String, digits, sizeof(digits)) || !table ||
        exteria_phone_display(table, count, digits, shown, sizeof(shown)) != EXTERIA_OK) {
        return [@"+" stringByAppendingString:phone];
    }
    return [NSString stringWithUTF8String:shown];
}

NSString *ExteriaOwnPhoneText(NSString *phone) {
    if (!phone.length) return @"";
    if (!ExteriaChatFlagGet(ExteriaChatFlagHidePhone)) return ExteriaPhoneDisplay(phone);
    return [@"+" stringByAppendingString:[@"" stringByPaddingToLength:phone.length withString:@"•" startingAtIndex:0]];
}

NSArray *ExteriaIdentityRows(long long peerId, ExteriaPhoto *photo) {
    NSMutableArray *rows = [NSMutableArray array];
    if (!ExteriaChatFlagGet(ExteriaChatFlagShowIds) || peerId <= 0) return rows;
    [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.id", nil), [NSString stringWithFormat:@"%lld", peerId], nil]];
    if (photo && photo.ref.dc > 0) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.dc", nil), [NSString stringWithFormat:@"%d", (int)photo.ref.dc], nil]];
    return rows;
}
