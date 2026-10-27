#import "exteria_notify_store.h"

#import "exteria_platform.h"

NSString *const ExteriaNotifyStoreDidChangeNotification = @"ExteriaNotifyStoreDidChange";

#define KEY_SCOPE @"exteria.notify.scope."
#define KEY_REACTIONS @"exteria.notify.reactions"
#define KEY_IN_APP_SOUNDS @"exteria.notify.inapp.sounds"
#define KEY_IN_APP_VIBRATE @"exteria.notify.inapp.vibrate"
#define KEY_IN_APP_PREVIEW @"exteria.notify.inapp.preview"
#define KEY_IN_CHAT @"exteria.notify.inchat"
#define KEY_CONTACT_JOINED @"exteria.notify.contactjoined"
#define KEY_PINNED @"exteria.notify.pinned"
#define KEY_BADGE @"exteria.notify.badge.shown"
#define KEY_BADGE_MUTED @"exteria.notify.badge.muted"
#define KEY_BADGE_MESSAGES @"exteria.notify.badge.messages"
#define KEY_REPEAT @"exteria.notify.repeat"
#define KEY_CALL_VIBRATE @"exteria.notify.callvibrate"
#define REPEAT_DEFAULT_MINUTES 60

static NSDictionary *ExteriaSoundDictionary(const exteria_notify_sound *sound) {
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:sound->kind], @"k", [NSNumber numberWithLongLong:sound->ringtone_id], @"i",
            [NSString stringWithUTF8String:sound->title], @"t", [NSString stringWithUTF8String:sound->data], @"d", nil];
}

static void ExteriaSoundFromDictionary(NSDictionary *dictionary, exteria_notify_sound *sound, uint8_t *has) {
    memset(sound, 0, sizeof(*sound));
    *has = 0;
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;
    int kind = [[dictionary objectForKey:@"k"] intValue];
    if (kind < EXTERIA_SOUND_DEFAULT || kind > EXTERIA_SOUND_RINGTONE) return;
    sound->kind = kind;
    sound->ringtone_id = [[dictionary objectForKey:@"i"] longLongValue];
    NSString *title = [dictionary objectForKey:@"t"], *data = [dictionary objectForKey:@"d"];
    if ([title isKindOfClass:[NSString class]]) strlcpy(sound->title, title.UTF8String, sizeof(sound->title));
    if ([data isKindOfClass:[NSString class]]) strlcpy(sound->data, data.UTF8String, sizeof(sound->data));
    *has = 1;
}

static NSDictionary *ExteriaPeerNotifyDictionary(const exteria_peer_notify *n) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (n->has_mute) [d setObject:[NSNumber numberWithInt:n->mute_until] forKey:@"mute"];
    if (n->has_previews) [d setObject:[NSNumber numberWithBool:n->previews] forKey:@"previews"];
    if (n->has_silent) [d setObject:[NSNumber numberWithBool:n->silent] forKey:@"silent"];
    if (n->has_sound) [d setObject:ExteriaSoundDictionary(&n->sound) forKey:@"sound"];
    if (n->has_stories_muted) [d setObject:[NSNumber numberWithBool:n->stories_muted] forKey:@"storiesMuted"];
    if (n->has_stories_hide_sender) [d setObject:[NSNumber numberWithBool:n->stories_hide_sender] forKey:@"storiesHide"];
    if (n->has_stories_sound) [d setObject:ExteriaSoundDictionary(&n->stories_sound) forKey:@"storiesSound"];
    return d;
}

static void ExteriaPeerNotifyFromDictionary(NSDictionary *d, exteria_peer_notify *n) {
    memset(n, 0, sizeof(*n));
    if (![d isKindOfClass:[NSDictionary class]]) return;
    NSNumber *value;
    if ((value = [d objectForKey:@"mute"])) { n->has_mute = 1; n->mute_until = (int32_t)[value longLongValue]; }
    if ((value = [d objectForKey:@"previews"])) { n->has_previews = 1; n->previews = [value boolValue]; }
    if ((value = [d objectForKey:@"silent"])) { n->has_silent = 1; n->silent = [value boolValue]; }
    ExteriaSoundFromDictionary([d objectForKey:@"sound"], &n->sound, &n->has_sound);
    if ((value = [d objectForKey:@"storiesMuted"])) { n->has_stories_muted = 1; n->stories_muted = [value boolValue]; }
    if ((value = [d objectForKey:@"storiesHide"])) { n->has_stories_hide_sender = 1; n->stories_hide_sender = [value boolValue]; }
    ExteriaSoundFromDictionary([d objectForKey:@"storiesSound"], &n->stories_sound, &n->has_stories_sound);
}

static void ExteriaNotifyChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaNotifyStoreDidChangeNotification object:nil];
    });
}

static void ExteriaNotifySave(void) {
    ExteriaDefaultsSaveSoon();
    ExteriaNotifyChanged();
}

exteria_peer_notify ExteriaNotifyScopeStored(exteria_notify_scope scope) {
    exteria_peer_notify n;
    memset(&n, 0, sizeof(n));
    if ((int)scope < 0 || scope >= EXTERIA_SCOPE_COUNT) return n;
    ExteriaPeerNotifyFromDictionary([[NSUserDefaults standardUserDefaults] objectForKey:[KEY_SCOPE stringByAppendingFormat:@"%d", (int)scope]], &n);
    return n;
}

void ExteriaNotifyScopeStore(exteria_notify_scope scope, const exteria_peer_notify *value) {
    if ((int)scope < 0 || scope >= EXTERIA_SCOPE_COUNT || !value) return;
    [[NSUserDefaults standardUserDefaults] setObject:ExteriaPeerNotifyDictionary(value) forKey:[KEY_SCOPE stringByAppendingFormat:@"%d", (int)scope]];
    ExteriaNotifySave();
}

exteria_reaction_notify ExteriaNotifyReactionsStored(void) {
    exteria_reaction_notify r;
    memset(&r, 0, sizeof(r));
    r.messages_from = EXTERIA_REACTION_FROM_EVERYONE;
    r.stories_from = EXTERIA_REACTION_FROM_EVERYONE;
    r.previews = 1;
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] objectForKey:KEY_REACTIONS];
    if (![d isKindOfClass:[NSDictionary class]]) return r;
    r.messages_from = (int32_t)[[d objectForKey:@"messages"] intValue];
    r.stories_from = (int32_t)[[d objectForKey:@"stories"] intValue];
    r.previews = [[d objectForKey:@"previews"] boolValue];
    uint8_t has;
    ExteriaSoundFromDictionary([d objectForKey:@"sound"], &r.sound, &has);
    return r;
}

void ExteriaNotifyReactionsStore(const exteria_reaction_notify *value) {
    if (!value) return;
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:value->messages_from], @"messages",
                       [NSNumber numberWithInt:value->stories_from], @"stories", [NSNumber numberWithBool:value->previews], @"previews",
                       ExteriaSoundDictionary(&value->sound), @"sound", nil];
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:KEY_REACTIONS];
    ExteriaNotifySave();
}

static BOOL ExteriaNotifyFlag(NSString *key, BOOL fallback) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return stored ? [stored boolValue] : fallback;
}

static void ExteriaNotifySetFlag(NSString *key, BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
    ExteriaNotifySave();
}

void ExteriaNotifyRulesSnapshot(exteria_notify_rules *out) {
    exteria_notify_rules_init(out);
    for (int i = 0; i < EXTERIA_SCOPE_COUNT; ++i) out->scope[i] = ExteriaNotifyScopeStored((exteria_notify_scope)i);
    out->contact_joined = ExteriaNotifyContactJoined();
    out->pinned_messages = ExteriaNotifyPinnedMessages();
}

BOOL ExteriaNotifyInAppSounds(void) { return ExteriaNotifyFlag(KEY_IN_APP_SOUNDS, YES); }
void ExteriaNotifySetInAppSounds(BOOL on) { ExteriaNotifySetFlag(KEY_IN_APP_SOUNDS, on); }
BOOL ExteriaNotifyInAppVibrate(void) { return ExteriaNotifyFlag(KEY_IN_APP_VIBRATE, YES); }
void ExteriaNotifySetInAppVibrate(BOOL on) { ExteriaNotifySetFlag(KEY_IN_APP_VIBRATE, on); }
BOOL ExteriaNotifyInAppPreview(void) { return ExteriaNotifyFlag(KEY_IN_APP_PREVIEW, YES); }
void ExteriaNotifySetInAppPreview(BOOL on) { ExteriaNotifySetFlag(KEY_IN_APP_PREVIEW, on); }
BOOL ExteriaNotifyInChatSounds(void) { return ExteriaNotifyFlag(KEY_IN_CHAT, NO); }
void ExteriaNotifySetInChatSounds(BOOL on) { ExteriaNotifySetFlag(KEY_IN_CHAT, on); }
BOOL ExteriaNotifyContactJoined(void) { return ExteriaNotifyFlag(KEY_CONTACT_JOINED, YES); }
void ExteriaNotifySetContactJoined(BOOL on) { ExteriaNotifySetFlag(KEY_CONTACT_JOINED, on); }
BOOL ExteriaNotifyPinnedMessages(void) { return ExteriaNotifyFlag(KEY_PINNED, YES); }
void ExteriaNotifySetPinnedMessages(BOOL on) { ExteriaNotifySetFlag(KEY_PINNED, on); }
BOOL ExteriaNotifyBadgeShown(void) { return ExteriaNotifyFlag(KEY_BADGE, YES); }
void ExteriaNotifySetBadgeShown(BOOL on) { ExteriaNotifySetFlag(KEY_BADGE, on); }
BOOL ExteriaNotifyBadgeMuted(void) { return ExteriaNotifyFlag(KEY_BADGE_MUTED, NO); }
void ExteriaNotifySetBadgeMuted(BOOL on) { ExteriaNotifySetFlag(KEY_BADGE_MUTED, on); }
BOOL ExteriaNotifyBadgeMessages(void) { return ExteriaNotifyFlag(KEY_BADGE_MESSAGES, YES); }
void ExteriaNotifySetBadgeMessages(BOOL on) { ExteriaNotifySetFlag(KEY_BADGE_MESSAGES, on); }

NSInteger ExteriaNotifyRepeatMinutes(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:KEY_REPEAT];
    return stored ? MAX(0, [stored integerValue]) : REPEAT_DEFAULT_MINUTES;
}

void ExteriaNotifySetRepeatMinutes(NSInteger minutes) {
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(0, minutes) forKey:KEY_REPEAT];
    ExteriaNotifySave();
}

NSInteger ExteriaNotifyCallVibration(void) {
    NSInteger style = [[NSUserDefaults standardUserDefaults] integerForKey:KEY_CALL_VIBRATE];
    return style >= 0 && style <= 3 ? style : 0;
}

void ExteriaNotifySetCallVibration(NSInteger style) {
    [[NSUserDefaults standardUserDefaults] setInteger:(style >= 0 && style <= 3 ? style : 0) forKey:KEY_CALL_VIBRATE];
    ExteriaNotifySave();
}

void ExteriaNotifyStoreReset(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (int i = 0; i < EXTERIA_SCOPE_COUNT; ++i) [defaults removeObjectForKey:[KEY_SCOPE stringByAppendingFormat:@"%d", i]];
    NSArray *keys = [NSArray arrayWithObjects:KEY_REACTIONS, KEY_IN_APP_SOUNDS, KEY_IN_APP_VIBRATE, KEY_IN_APP_PREVIEW, KEY_IN_CHAT, KEY_CONTACT_JOINED, KEY_PINNED,
                     KEY_BADGE, KEY_BADGE_MUTED, KEY_BADGE_MESSAGES, KEY_REPEAT, KEY_CALL_VIBRATE, nil];
    for (NSString *key in keys) [defaults removeObjectForKey:key];
    ExteriaNotifySave();
}
