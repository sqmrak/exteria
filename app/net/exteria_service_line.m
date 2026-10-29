#import "exteria_service_line.h"

/* 3600 as "1 h", 172800 as "2 d": the largest unit that divides the period, hours and minutes below a day */
static NSString *ExteriaPeriodText(int32_t seconds) {
    if (seconds % 604800 == 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.period.weeks", nil), (int)(seconds / 604800)];
    if (seconds % 86400 == 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.period.days", nil), (int)(seconds / 86400)];
    if (seconds % 3600 == 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.period.hours", nil), (int)(seconds / 3600)];
    return [NSString stringWithFormat:NSLocalizedString(@"chat.period.minutes", nil), (int)MAX(1, seconds / 60)];
}

static NSString *ExteriaDurationText(int32_t seconds) {
    if (seconds >= 3600) return [NSString stringWithFormat:@"%d:%02d:%02d", (int)(seconds / 3600), (int)(seconds / 60 % 60), (int)(seconds % 60)];
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

NSString *ExteriaServiceLine(exteria_service_kind kind, NSString *who, NSString *whom, NSString *text, int32_t value, BOOL actorIsTarget) {
    NSString *actor = who.length ? who : NSLocalizedString(@"chat.someone", nil);
    NSString *target = whom.length ? whom : NSLocalizedString(@"chat.someone", nil);
    switch (kind) {
    case EXTERIA_SERVICE_CHAT_CREATE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.created", nil), actor, text];
    case EXTERIA_SERVICE_CHANNEL_CREATE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.channel", nil), text];
    case EXTERIA_SERVICE_TITLE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.title", nil), actor, text];
    case EXTERIA_SERVICE_PHOTO_CHANGED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.photo", nil), actor];
    case EXTERIA_SERVICE_PHOTO_DELETED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.photo.removed", nil), actor];
    /* the server sends the same action when a member leaves or comes back by a link, with the actor and the target the same person */
    case EXTERIA_SERVICE_USER_ADDED:
        if (actorIsTarget) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.joined", nil), actor];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.added", nil), actor, target];
    case EXTERIA_SERVICE_USER_REMOVED:
        if (actorIsTarget) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.left", nil), actor];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.removed", nil), actor, target];
    case EXTERIA_SERVICE_JOINED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.joined", nil), actor];
    case EXTERIA_SERVICE_PIN: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.pinned", nil), actor];
    case EXTERIA_SERVICE_CALL: return NSLocalizedString(@"chat.service.call", nil);
    case EXTERIA_SERVICE_CONTACT_JOINED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.contact", nil), actor];
    case EXTERIA_SERVICE_SCREENSHOT: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.screenshot", nil), actor];
    case EXTERIA_SERVICE_HISTORY_CLEAR: return NSLocalizedString(@"chat.service.history", nil);
    case EXTERIA_SERVICE_MIGRATED:
        return text.length ? [NSString stringWithFormat:NSLocalizedString(@"chat.service.migrated.from", nil), text]
                           : NSLocalizedString(@"chat.service.migrated.to", nil);
    case EXTERIA_SERVICE_CUSTOM: return text.length ? text : NSLocalizedString(@"chat.service.other", nil);
    case EXTERIA_SERVICE_VIDEO_CHAT:
        if (value > 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.videochat.end", nil), ExteriaDurationText(value)];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.videochat.start", nil), actor];
    case EXTERIA_SERVICE_VIDEO_CHAT_INVITE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.videochat.invite", nil), actor, target];
    case EXTERIA_SERVICE_TOPIC_CREATE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.create", nil), actor, text];
    case EXTERIA_SERVICE_TOPIC_EDIT:
        if (value == 1) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.close", nil), actor];
        if (value == 2) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.reopen", nil), actor];
        if (text.length) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.rename", nil), actor, text];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.edit", nil), actor];
    case EXTERIA_SERVICE_TTL:
        if (value <= 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.ttl.off", nil), actor];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.ttl.on", nil), actor, ExteriaPeriodText(value)];
    case EXTERIA_SERVICE_BOOST: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.boost", nil), actor];
    case EXTERIA_SERVICE_PAYMENT: return NSLocalizedString(@"chat.service.payment", nil);
    case EXTERIA_SERVICE_BOT_ALLOWED: return NSLocalizedString(@"chat.service.botallowed", nil);
    case EXTERIA_SERVICE_PREMIUM_GIFT:
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.premium", nil), actor, [NSString stringWithFormat:NSLocalizedString(@"chat.period.months", nil), (int)MAX(1, value)]];
    case EXTERIA_SERVICE_THEME:
        if (text.length) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.theme", nil), actor, text];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.theme.off", nil), actor];
    case EXTERIA_SERVICE_WALLPAPER: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.wallpaper", nil), actor];
    case EXTERIA_SERVICE_PHOTO_SUGGESTED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.photosuggest", nil), actor];
    case EXTERIA_SERVICE_GAME_SCORE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.score", nil), actor, (int)value];
    case EXTERIA_SERVICE_GIVEAWAY: return NSLocalizedString(@"chat.service.giveaway", nil);
    case EXTERIA_SERVICE_GIVEAWAY_RESULTS: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.giveaway.results", nil), (int)value];
    case EXTERIA_SERVICE_PAYMENT_REFUNDED: return NSLocalizedString(@"chat.service.refunded", nil);
    case EXTERIA_SERVICE_SHARING_REQUEST:
        if (value & 4) return NSLocalizedString(@"chat.service.sharing.expired", nil);
        return [NSString stringWithFormat:NSLocalizedString((value & 2) ? @"chat.service.sharing.request.disable" : @"chat.service.sharing.request.enable", nil), actor];
    case EXTERIA_SERVICE_SHARING_TOGGLE:
        if (!!(value & 1) == !!(value & 2)) return NSLocalizedString((value & 2) ? @"chat.service.sharing.still.disabled" : @"chat.service.sharing.still.enabled", nil);
        return [NSString stringWithFormat:NSLocalizedString((value & 2) ? @"chat.service.sharing.disabled" : @"chat.service.sharing.enabled", nil), actor];
    case EXTERIA_SERVICE_OTHER:
        /* no wording for it: the action's own name, as readable as it gets, beats a line that says nothing */
        if (text.length) return text;
        break;
    case EXTERIA_SERVICE_GIFT:
        break;
    }
    return NSLocalizedString(@"chat.service.other", nil);
}
