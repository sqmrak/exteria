#import "exteria_channel_errors.h"

NSString *ExteriaChannelErrorText(NSString *errorName) {
    static NSString *const names[] = {
        @"CHAT_ADMIN_REQUIRED", @"CHAT_WRITE_FORBIDDEN", @"RIGHT_FORBIDDEN", @"CHANNEL_PRIVATE", @"CHAT_ADMIN_INVITE_REQUIRED",
        @"USER_ADMIN_INVALID", @"USER_CREATOR", @"USER_NOT_PARTICIPANT", @"ADMINS_TOO_MUCH", @"CHAT_ABOUT_TOO_LONG", @"CHAT_TITLE_EMPTY",
        @"USERNAME_OCCUPIED", @"USERNAME_INVALID", @"CHANNELS_ADMIN_PUBLIC_TOO_MUCH", @"ADMIN_RANK_INVALID", @"ADMIN_RANK_EMOJI_NOT_ALLOWED",
        @"USER_PRIVACY_RESTRICTED", @"PEER_ID_INVALID", @"USER_ID_INVALID", @"USER_BANNED_IN_CHANNEL",
    };
    static NSString *const keys[] = {
        @"channel.error.admin", @"channel.error.admin", @"channel.error.admin", @"channel.error.admin", @"channel.error.admin",
        @"channel.error.useradmin", @"channel.error.creator", @"channel.error.notmember", @"channel.error.admins.toomuch", @"channel.error.about", @"channel.error.title",
        @"channel.error.username.occupied", @"channel.error.username.invalid", @"channel.error.public.toomuch", @"channel.error.rank", @"channel.error.rank",
        @"channel.error.privacy", @"channel.error.person", @"channel.error.person", @"channel.error.banned",
    };
    if ([errorName isEqualToString:@"TIMEOUT"]) return NSLocalizedString(@"error.offline", nil);
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        if ([errorName isEqualToString:names[i]]) return NSLocalizedString(keys[i], nil);
    }
    return [NSString stringWithFormat:NSLocalizedString(@"channel.error.unknown", nil), errorName ? errorName : @"?"];
}
