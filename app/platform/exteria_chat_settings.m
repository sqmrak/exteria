#import "exteria_chat_settings.h"
#import "exteria_person.h"

#import "exteria_platform.h"
#import "exteria_shape.h"
#import "exteria_theme.h"
#include "exteria_reactions.h"

NSString *const ExteriaChatSettingsDidChangeNotification = @"ExteriaChatSettingsDidChange";

static NSString *const ExteriaChatTextSizeKey = @"exteria.chat.textsize";
static NSString *const ExteriaChatBubbleRadiusKey = @"exteria.chat.bubbleradius";
static NSString *const ExteriaChatListStyleKey = @"exteria.chat.liststyle";
static NSString *const ExteriaChatSendByEnterKey = @"exteria.chat.sendbyenter";
static NSString *const ExteriaChatNextMediaTapKey = @"exteria.chat.nextmediatap";
static NSString *const ExteriaChatRaiseToListenKey = @"exteria.chat.raisetolisten";
static NSString *const ExteriaChatRaiseToSpeakKey = @"exteria.chat.raisetospeak";
static NSString *const ExteriaChatPauseOnRecordKey = @"exteria.chat.pauseonrecord";
static NSString *const ExteriaChatPauseOnMediaKey = @"exteria.chat.pauseonmedia";
static NSString *const ExteriaChatBluetoothKey = @"exteria.chat.bluetoothmic";
static NSString *const ExteriaChatSwipeKey = @"exteria.chat.swipe";
static NSString *const ExteriaChatLargeEmojiKey = @"exteria.chat.largeemoji";
static NSString *const ExteriaChatListTitleKey = @"exteria.chatlist.title";
static NSString *const ExteriaChatListCustomTitleKey = @"exteria.chatlist.customtitle";
static NSString *const ExteriaAvatarCornerKey = @"exteria.avatar.corner";
static NSString *const ExteriaAvatarShapeKey = @"exteria.avatar.shape";
static NSString *const ExteriaSendShapeKey = @"exteria.send.shape";
static NSString *const ExteriaListDensityKey = @"exteria.list.density";
static NSString *const ExteriaTabIndicatorKey = @"exteria.tab.indicator";
static NSString *const ExteriaClassicGlossKey = @"exteria.classic.gloss";
static NSString *const ExteriaClassicMaterialKey = @"exteria.classic.material";
static NSString *const ExteriaClassicTextureStyleKey = @"exteria.classic.texture";
static NSString *const ExteriaClassicTextureStrengthKey = @"exteria.classic.texturestrength";
static NSString *const ExteriaClassicTextureHueKey = @"exteria.classic.texturehue";
static NSString *const ExteriaClassicAvatarGlossKey = @"exteria.classic.avatargloss";
static NSString *const ExteriaClassicAvatarShadowKey = @"exteria.classic.avatarshadow";
static NSString *const ExteriaClassicSeparatorsKey = @"exteria.classic.separators";
static NSString *const ExteriaSectionRadiusKey = @"exteria.section.radius";
static NSString *const ExteriaTabLayoutKey = @"exteria.tablayout";
static NSString *const ExteriaTabOrderKey = @"exteria.taborder";
NSString *const ExteriaTabOrderDidChangeNotification = @"ExteriaTabOrderDidChange";
static NSString *const ExteriaCacheKeepDaysKey = @"exteria.cache.keepdays";
static NSString *const ExteriaChatDynamicPackOrderKey = @"exteria.chat.dynamicpackorder";

static NSInteger ExteriaClamped(NSInteger value, NSInteger low, NSInteger high) {
    return value < low ? low : (value > high ? high : value);
}

/* a stored number, or nil when the key was never written (zero is a real radius, so the default cannot stand for "unset") */
static NSNumber *ExteriaStoredNumber(NSString *key) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

/* TRACE: temporary, appends one line per write to a file in the temporary folder of the app */
static void ExteriaTrace(NSString *line) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"chatset-trace.txt"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [handle seekToEndOfFile];
    [handle writeData:[[NSString stringWithFormat:@"%.3f %@\n", CFAbsoluteTimeGetCurrent() - 780000000, line] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

void ExteriaChatTrace(NSString *line) { ExteriaTrace(line); }

static void ExteriaStoreNumber(NSString *key, NSInteger value) {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    ExteriaTrace([NSString stringWithFormat:@"store %@ = %ld, reads %@", key, (long)value, [[NSUserDefaults standardUserDefaults] objectForKey:key]]);
    ExteriaDefaultsSaveSoon();
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
}

NSInteger ExteriaChatDefaultTextSize(void) {
    return ExteriaIsPad() ? 18 : 16;
}

NSInteger ExteriaChatTextSize(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatTextSizeKey);
    return stored ? ExteriaClamped(stored.integerValue, EXTERIA_CHAT_TEXT_SIZE_MIN, EXTERIA_CHAT_TEXT_SIZE_MAX) : ExteriaChatDefaultTextSize();
}

void ExteriaChatSetTextSize(NSInteger size) {
    ExteriaStoreNumber(ExteriaChatTextSizeKey, ExteriaClamped(size, EXTERIA_CHAT_TEXT_SIZE_MIN, EXTERIA_CHAT_TEXT_SIZE_MAX));
}

NSInteger ExteriaChatBubbleRadius(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatBubbleRadiusKey);
    return stored ? ExteriaClamped(stored.integerValue, EXTERIA_CHAT_BUBBLE_RADIUS_MIN, EXTERIA_CHAT_BUBBLE_RADIUS_MAX) : EXTERIA_CHAT_BUBBLE_RADIUS_MAX;
}

void ExteriaChatSetBubbleRadius(NSInteger radius) {
    ExteriaStoreNumber(ExteriaChatBubbleRadiusKey, ExteriaClamped(radius, EXTERIA_CHAT_BUBBLE_RADIUS_MIN, EXTERIA_CHAT_BUBBLE_RADIUS_MAX));
}

NSInteger ExteriaChatClassicBubbleRadius(void) {
    return (ExteriaChatBubbleRadius() * 15 + EXTERIA_CHAT_BUBBLE_RADIUS_MAX / 2) / EXTERIA_CHAT_BUBBLE_RADIUS_MAX;
}

ExteriaChatListStyle ExteriaChatListStyleStored(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatListStyleKey);
    return stored && stored.integerValue == ExteriaChatListTwoLines ? ExteriaChatListTwoLines : ExteriaChatListThreeLines;
}

void ExteriaChatSetListStyle(ExteriaChatListStyle style) {
    ExteriaStoreNumber(ExteriaChatListStyleKey, style == ExteriaChatListTwoLines ? ExteriaChatListTwoLines : ExteriaChatListThreeLines);
}

/* a switch: the stored value, or the default while the key was never written */
static BOOL ExteriaStoredFlag(NSString *key, BOOL fallback) {
    NSNumber *stored = ExteriaStoredNumber(key);
    return stored ? stored.boolValue : fallback;
}

static void ExteriaStoreFlag(NSString *key, BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
    ExteriaDefaultsSaveSoon();
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
}

BOOL ExteriaChatSendByEnter(void) { return ExteriaStoredFlag(ExteriaChatSendByEnterKey, NO); }
void ExteriaChatSetSendByEnter(BOOL on) { ExteriaStoreFlag(ExteriaChatSendByEnterKey, on); }
BOOL ExteriaChatNextMediaTap(void) { return ExteriaStoredFlag(ExteriaChatNextMediaTapKey, NO); }
void ExteriaChatSetNextMediaTap(BOOL on) { ExteriaStoreFlag(ExteriaChatNextMediaTapKey, on); }
BOOL ExteriaChatRaiseToListen(void) { return ExteriaStoredFlag(ExteriaChatRaiseToListenKey, YES); }
void ExteriaChatSetRaiseToListen(BOOL on) { ExteriaStoreFlag(ExteriaChatRaiseToListenKey, on); }
BOOL ExteriaChatRaiseToSpeak(void) { return ExteriaStoredFlag(ExteriaChatRaiseToSpeakKey, NO); }
void ExteriaChatSetRaiseToSpeak(BOOL on) { ExteriaStoreFlag(ExteriaChatRaiseToSpeakKey, on); }
BOOL ExteriaChatPauseMusicOnRecord(void) { return ExteriaStoredFlag(ExteriaChatPauseOnRecordKey, YES); }
void ExteriaChatSetPauseMusicOnRecord(BOOL on) { ExteriaStoreFlag(ExteriaChatPauseOnRecordKey, on); }
BOOL ExteriaChatPauseMusicOnMedia(void) { return ExteriaStoredFlag(ExteriaChatPauseOnMediaKey, YES); }
void ExteriaChatSetPauseMusicOnMedia(BOOL on) { ExteriaStoreFlag(ExteriaChatPauseOnMediaKey, on); }
/* the key is the one the list wrote before the setting had a page of its own */
static NSString *const ExteriaArchiveHiddenKey = @"ExteriaArchiveHidden";
BOOL ExteriaPremiumEffective(BOOL serverPremium) { return serverPremium || ExteriaChatFlagGet(ExteriaChatFlagLocalPremium); }
BOOL ExteriaArchiveHidden(void) { return ExteriaStoredFlag(ExteriaArchiveHiddenKey, NO); }
void ExteriaArchiveSetHidden(BOOL hidden) { ExteriaStoreFlag(ExteriaArchiveHiddenKey, hidden); }
BOOL ExteriaChatLargeEmoji(void) { return ExteriaStoredFlag(ExteriaChatLargeEmojiKey, YES); }
void ExteriaChatSetLargeEmoji(BOOL on) { ExteriaStoreFlag(ExteriaChatLargeEmojiKey, on); }
ExteriaChatListTitle ExteriaChatListTitleStored(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatListTitleKey);
    return stored && stored.integerValue >= 0 && stored.integerValue < ExteriaChatListTitleCount ? (ExteriaChatListTitle)stored.integerValue : ExteriaChatListTitleDefault;
}
void ExteriaChatListTitleStore(ExteriaChatListTitle mode) { ExteriaStoreNumber(ExteriaChatListTitleKey, mode); }
NSString *ExteriaChatListCustomTitle(void) {
    NSString *text = [[NSUserDefaults standardUserDefaults] stringForKey:ExteriaChatListCustomTitleKey];
    return text ? text : @"";
}
NSString *ExteriaChatListTitleText(ExteriaChatListTitle mode, ExteriaPerson *person) {
    switch (mode) {
    case ExteriaChatListTitleUsername:
        if (person.username.length) return [@"@" stringByAppendingString:person.username];
        break;
    case ExteriaChatListTitleName:
        if (person.name.length) return person.name;
        break;
    case ExteriaChatListTitleCustom: {
        NSString *text = [ExteriaChatListCustomTitle() stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length) return text;
        break;
    }
    case ExteriaChatListTitleDefault:
    case ExteriaChatListTitleCount:
        break;
    }
    return NSLocalizedString(@"chats.title", nil);
}
void ExteriaChatListSetCustomTitle(NSString *text) {
    [[NSUserDefaults standardUserDefaults] setObject:text ? text : @"" forKey:ExteriaChatListCustomTitleKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the title of the chat list was not saved");
}

/* the avatar views read this at every draw, so it is kept in memory and changed with the stored value */
static NSInteger ExteriaAvatarCornerCurrent = -1;
NSInteger ExteriaAvatarCornerPercent(void) {
    if (ExteriaAvatarCornerCurrent == -1) {
        NSNumber *stored = ExteriaStoredNumber(ExteriaAvatarCornerKey);
        ExteriaAvatarCornerCurrent = stored && stored.integerValue >= 0 && stored.integerValue <= 100 ? stored.integerValue : -2;
    }
    return ExteriaAvatarCornerCurrent == -2 ? (ExteriaThemeIsClassic() ? EXTERIA_AVATAR_CORNER_DEFAULT : 84) : ExteriaAvatarCornerCurrent;
}
void ExteriaAvatarCornerStore(NSInteger percent) {
    ExteriaAvatarCornerCurrent = MAX(0, MIN(100, percent));
    ExteriaStoreNumber(ExteriaAvatarCornerKey, ExteriaAvatarCornerCurrent);
}
/* the avatar views read the shape at every draw, so it is kept in memory and changed with the stored value */
static NSInteger ExteriaAvatarShapeCurrent = -1;
NSInteger ExteriaAvatarShapeStored(void) {
    if (ExteriaAvatarShapeCurrent == -1) {
        NSNumber *stored = ExteriaStoredNumber(ExteriaAvatarShapeKey);
        ExteriaAvatarShapeCurrent = stored && stored.integerValue >= 0 && stored.integerValue < ExteriaShapeCount ? stored.integerValue : 0;
    }
    return ExteriaAvatarShapeCurrent;
}
void ExteriaAvatarShapeStore(NSInteger shape) {
    ExteriaAvatarShapeCurrent = MAX(0, MIN(ExteriaShapeCount - 1, shape));
    ExteriaStoreNumber(ExteriaAvatarShapeKey, ExteriaAvatarShapeCurrent);
}
NSInteger ExteriaSendShapeStored(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaSendShapeKey);
    return stored ? ExteriaClamped(stored.integerValue, 0, EXTERIA_SEND_SHAPE_COUNT - 1) : 0;
}
void ExteriaSendShapeStore(NSInteger shape) {
    ExteriaStoreNumber(ExteriaSendShapeKey, ExteriaClamped(shape, 0, EXTERIA_SEND_SHAPE_COUNT - 1));
}
NSInteger ExteriaListDensityStored(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaListDensityKey);
    return stored ? ExteriaClamped(stored.integerValue, 0, 1) : 0;
}
void ExteriaListDensityStore(NSInteger density) {
    ExteriaStoreNumber(ExteriaListDensityKey, ExteriaClamped(density, 0, 1));
}
BOOL ExteriaTabIndicatorOn(void) {
    return [ExteriaStoredNumber(ExteriaTabIndicatorKey) boolValue];
}
void ExteriaTabIndicatorStore(BOOL on) {
    ExteriaStoreNumber(ExteriaTabIndicatorKey, on ? 1 : 0);
}
/* the classic pictures read these at every draw and every lookup, so each is kept in memory and changed with the stored value */
static NSInteger ExteriaClassicLook[7] = {-1, -1, -1, -1, -1, -1, -1};
static NSInteger ExteriaClassicRead(int slot, NSString *key, NSInteger low, NSInteger high, NSInteger fallback) {
    if (ExteriaClassicLook[slot] == -1) {
        NSNumber *stored = ExteriaStoredNumber(key);
        ExteriaClassicLook[slot] = stored ? ExteriaClamped(stored.integerValue, low, high) : fallback;
    }
    return ExteriaClassicLook[slot];
}
static void ExteriaClassicWrite(int slot, NSString *key, NSInteger low, NSInteger high, NSInteger value) {
    ExteriaClassicLook[slot] = ExteriaClamped(value, low, high);
    ExteriaStoreNumber(key, ExteriaClassicLook[slot]);
}
NSInteger ExteriaClassicGlossLevel(void) { return ExteriaClassicRead(0, ExteriaClassicGlossKey, 0, 2, 1); }
void ExteriaClassicGlossStore(NSInteger level) { ExteriaClassicWrite(0, ExteriaClassicGlossKey, 0, 2, level); }
NSInteger ExteriaClassicMaterial(void) { return ExteriaClassicRead(1, ExteriaClassicMaterialKey, 0, EXTERIA_CLASSIC_MATERIAL_COUNT - 1, 0); }
void ExteriaClassicMaterialStore(NSInteger material) { ExteriaClassicWrite(1, ExteriaClassicMaterialKey, 0, EXTERIA_CLASSIC_MATERIAL_COUNT - 1, material); }
NSInteger ExteriaClassicTextureStyle(void) { return ExteriaClassicRead(2, ExteriaClassicTextureStyleKey, 0, 1, 0); }
void ExteriaClassicTextureStyleStore(NSInteger style) { ExteriaClassicWrite(2, ExteriaClassicTextureStyleKey, 0, 1, style); }
NSInteger ExteriaClassicTextureStrength(void) { return ExteriaClassicRead(3, ExteriaClassicTextureStrengthKey, 0, 100, 100); }
void ExteriaClassicTextureStrengthStore(NSInteger percent) { ExteriaClassicWrite(3, ExteriaClassicTextureStrengthKey, 0, 100, percent); }
/* stored as the hue plus one so that zero, the unset value, follows the accent */
NSInteger ExteriaClassicTextureHue(void) { return ExteriaClassicRead(6, ExteriaClassicTextureHueKey, 0, 360, 0) - 1; }
void ExteriaClassicTextureHueStore(NSInteger hue) { ExteriaClassicWrite(6, ExteriaClassicTextureHueKey, 0, 360, hue < 0 ? 0 : MIN(hue, 359) + 1); }
BOOL ExteriaClassicAvatarGloss(void) { return ExteriaClassicRead(4, ExteriaClassicAvatarGlossKey, 0, 1, 1) != 0; }
void ExteriaClassicAvatarGlossStore(BOOL on) { ExteriaClassicWrite(4, ExteriaClassicAvatarGlossKey, 0, 1, on ? 1 : 0); }
BOOL ExteriaClassicAvatarShadow(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaClassicAvatarShadowKey);
    return stored && stored.integerValue != 0;
}
void ExteriaClassicAvatarShadowStore(BOOL on) { ExteriaStoreNumber(ExteriaClassicAvatarShadowKey, on ? 1 : 0); }
NSInteger ExteriaClassicSeparators(void) { return ExteriaClassicRead(5, ExteriaClassicSeparatorsKey, 0, 2, 0); }
void ExteriaClassicSeparatorsStore(NSInteger style) { ExteriaClassicWrite(5, ExteriaClassicSeparatorsKey, 0, 2, style); }
NSString *ExteriaClassicLookSignature(void) {
    return [NSString stringWithFormat:@"%ld%ld%d", (long)ExteriaClassicGlossLevel(), (long)ExteriaClassicMaterial(), ExteriaClassicAvatarGloss() ? 1 : 0];
}
static NSInteger ExteriaSectionRadiusCurrent = -1;
CGFloat ExteriaSectionRadius(void) {
    if (ExteriaSectionRadiusCurrent < 0) {
        NSNumber *stored = ExteriaStoredNumber(ExteriaSectionRadiusKey);
        ExteriaSectionRadiusCurrent = stored && stored.integerValue >= 0 && stored.integerValue <= EXTERIA_SECTION_RADIUS_MAX ? stored.integerValue : EXTERIA_SECTION_RADIUS_DEFAULT;
    }
    return (CGFloat)ExteriaSectionRadiusCurrent;
}
void ExteriaSectionRadiusStore(NSInteger points) {
    ExteriaSectionRadiusCurrent = MAX(0, MIN(EXTERIA_SECTION_RADIUS_MAX, points));
    ExteriaStoreNumber(ExteriaSectionRadiusKey, ExteriaSectionRadiusCurrent);
}
ExteriaTabLayout ExteriaTabLayoutStored(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaTabLayoutKey);
    return stored && stored.integerValue >= 0 && stored.integerValue < ExteriaTabLayoutCount ? (ExteriaTabLayout)stored.integerValue : ExteriaTabLayoutMessenger;
}
void ExteriaTabLayoutStore(ExteriaTabLayout layout) {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaTabOrderKey];
    ExteriaStoreNumber(ExteriaTabLayoutKey, layout);
}

void ExteriaTabOrderLoad(int order[EXTERIA_TAB_SLOTS]) {
    static const int messenger[] = {EXTERIA_TAB_CHATS, EXTERIA_TAB_CONTACTS, EXTERIA_TAB_SETTINGS, EXTERIA_TAB_PROFILE};
    static const int calls[] = {EXTERIA_TAB_CONTACTS, EXTERIA_TAB_CALLS, EXTERIA_TAB_CHATS, EXTERIA_TAB_SETTINGS};
    if (!order) return;
    NSArray *stored = [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaTabOrderKey];
    BOOL valid = [stored isKindOfClass:[NSArray class]] && stored.count == EXTERIA_TAB_SLOTS;
    for (NSUInteger i = 0; valid && i < EXTERIA_TAB_SLOTS; ++i) {
        id value = [stored objectAtIndex:i];
        if (![value isKindOfClass:[NSNumber class]]) valid = NO;
        else order[i] = [value intValue];
    }
    if (valid && exteria_tab_order_valid(order, EXTERIA_TAB_SLOTS)) return;
    const int *fallback = ExteriaTabLayoutStored() == ExteriaTabLayoutCalls ? calls : messenger;
    for (NSUInteger i = 0; i < EXTERIA_TAB_SLOTS; ++i) order[i] = fallback[i];
}

BOOL ExteriaTabOrderStore(const int order[EXTERIA_TAB_SLOTS]) {
    if (!exteria_tab_order_valid(order, EXTERIA_TAB_SLOTS)) return NO;
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:EXTERIA_TAB_SLOTS];
    for (NSUInteger i = 0; i < EXTERIA_TAB_SLOTS; ++i) [values addObject:[NSNumber numberWithInt:order[i]]];
    [[NSUserDefaults standardUserDefaults] setObject:values forKey:ExteriaTabOrderKey];
    ExteriaDefaultsSaveSoon();
    return YES;
}

BOOL ExteriaTabOrderIsCustom(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaTabOrderKey];
    int order[EXTERIA_TAB_SLOTS];
    if (![stored isKindOfClass:[NSArray class]] || [stored count] != EXTERIA_TAB_SLOTS) return NO;
    for (NSUInteger i = 0; i < EXTERIA_TAB_SLOTS; ++i) {
        id value = [stored objectAtIndex:i];
        if (![value isKindOfClass:[NSNumber class]]) return NO;
        order[i] = [value intValue];
    }
    return exteria_tab_order_valid(order, EXTERIA_TAB_SLOTS);
}
NSInteger ExteriaCacheKeepDays(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaCacheKeepDaysKey);
    return stored && stored.integerValue > 0 && stored.integerValue <= 365 ? stored.integerValue : 0;
}
void ExteriaCacheSetKeepDays(NSInteger days) { ExteriaStoreNumber(ExteriaCacheKeepDaysKey, days); }
BOOL ExteriaChatDynamicPackOrder(void) { return ExteriaStoredFlag(ExteriaChatDynamicPackOrderKey, YES); }
void ExteriaChatSetDynamicPackOrder(BOOL on) { ExteriaStoreFlag(ExteriaChatDynamicPackOrderKey, on); }
BOOL ExteriaChatRecordViaBluetooth(void) { return ExteriaStoredFlag(ExteriaChatBluetoothKey, NO); }
void ExteriaChatSetRecordViaBluetooth(BOOL on) { ExteriaStoreFlag(ExteriaChatBluetoothKey, on); }

static const struct { NSString *key; BOOL fallback; } ExteriaChatFlagTable[ExteriaChatFlagCount] = {
    [ExteriaChatFlagCommaAfterMention] = {@"exteria.chat.mentioncomma", NO},
    [ExteriaChatFlagRemoveTail] = {@"exteria.chat.notail", NO},
    [ExteriaChatFlagEditedIcon] = {@"exteria.chat.editedicon", NO},
    [ExteriaChatFlagPollResultsFirst] = {@"exteria.chat.pollresultsfirst", NO},
    [ExteriaChatFlagForwardDate] = {@"exteria.chat.forwarddate", NO},
    [ExteriaChatFlagForwardAuthor] = {@"exteria.chat.forwardauthor", NO},
    [ExteriaChatFlagHideShare] = {@"exteria.chat.hideshare", NO},
    [ExteriaChatFlagHideSendAs] = {@"exteria.chat.hidesendas", NO},
    [ExteriaChatFlagHideStickerTime] = {@"exteria.chat.hidestickertime", NO},
    [ExteriaChatFlagHideCameraTile] = {@"exteria.chat.hidecameratile", NO},
    [ExteriaChatFlagAlwaysHD] = {@"exteria.chat.alwayshd", NO},
    [ExteriaChatFlagPauseVoiceOnMinimize] = {@"exteria.chat.pausevoice", NO},
    [ExteriaChatFlagPauseRoundOnMinimize] = {@"exteria.chat.pauseround", NO},
    [ExteriaChatFlagNoAutoNextVoice] = {@"exteria.chat.noautonextvoice", NO},
    [ExteriaChatFlagUnmuteWithVolume] = {@"exteria.chat.unmutevolume", NO},
    [ExteriaChatFlagSeconds] = {@"exteria.chat.seconds", NO},
    [ExteriaChatFlagFilterZalgo] = {@"exteria.chat.zalgo", NO},
    [ExteriaChatFlagExactNumbers] = {@"exteria.chat.exactnumbers", NO},
    [ExteriaChatFlagRelativeSeen] = {@"exteria.chat.relativeseen", NO},
    [ExteriaChatFlagShowIds] = {@"exteria.chat.showids", NO},
    [ExteriaChatFlagHidePhone] = {@"exteria.chat.hidephone", NO},
    [ExteriaChatFlagHideReactionsPrivate] = {@"exteria.chat.noreactionsprivate", NO},
    [ExteriaChatFlagHideReactionsGroups] = {@"exteria.chat.noreactionsgroups", NO},
    [ExteriaChatFlagHideReactionsChannels] = {@"exteria.chat.noreactionschannels", NO},
    [ExteriaChatFlagMenuCopyPhoto] = {@"exteria.chat.menucopyphoto", NO},
    [ExteriaChatFlagMenuHistory] = {@"exteria.chat.menuhistory", NO},
    [ExteriaChatFlagMenuReport] = {@"exteria.chat.menureport", NO},
    [ExteriaChatFlagMenuNoQuote] = {@"exteria.chat.menunoquote", NO},
    [ExteriaChatFlagMenuSave] = {@"exteria.chat.menusave", NO},
    [ExteriaChatFlagMenuRepeat] = {@"exteria.chat.menurepeat", NO},
    [ExteriaChatFlagMenuDetails] = {@"exteria.chat.menudetails", NO},
    [ExteriaChatFlagMenuBookmark] = {@"exteria.chat.menubookmark", NO},
    [ExteriaChatFlagMenuRemind] = {@"exteria.chat.menuremind", NO},
    [ExteriaChatFlagMenuReplyPrivate] = {@"exteria.chat.menureplyprivate", NO},
    [ExteriaChatFlagAskCall] = {@"exteria.chat.askcall", NO},
    [ExteriaChatFlagAskRepeat] = {@"exteria.chat.askrepeat", NO},
    [ExteriaChatFlagAskRecording] = {@"exteria.chat.askrecording", NO},
    [ExteriaChatFlagAskBotCommand] = {@"exteria.chat.askbotcommand", NO},
    [ExteriaChatFlagNoLinkPreview] = {@"exteria.chat.nolinkpreview", NO},
    [ExteriaChatFlagDeleteForMe] = {@"exteria.chat.deleteforme", NO},
    [ExteriaChatFlagReplyColors] = {@"exteria.chat.replycolors", YES},
    [ExteriaChatFlagReplyBackground] = {@"exteria.chat.replybackground", YES},
    [ExteriaChatFlagGhostNoRead] = {@"exteria.ayu.noread", NO},
    [ExteriaChatFlagGhostNoStories] = {@"exteria.ayu.nostories", NO},
    [ExteriaChatFlagGhostOffline] = {@"exteria.ayu.offline", NO},
    [ExteriaChatFlagAyuRegex] = {@"exteria.ayu.regex", NO},
    [ExteriaChatFlagAyuSaveDeleted] = {@"exteria.ayu.savedeleted", NO},
    [ExteriaChatFlagAyuSaveEdits] = {@"exteria.ayu.saveedits", NO},
    [ExteriaChatFlagAyuDeletedPrivate] = {@"exteria.ayu.deletedprivate", YES},
    [ExteriaChatFlagAyuDeletedGroups] = {@"exteria.ayu.deletedgroups", YES},
    [ExteriaChatFlagAyuDeletedChannels] = {@"exteria.ayu.deletedchannels", NO},
    [ExteriaChatFlagAyuDeletedBots] = {@"exteria.ayu.deletedbots", NO},
    [ExteriaChatFlagAyuTranslucent] = {@"exteria.ayu.translucent", YES},
    [ExteriaChatFlagAyuReplyQuote] = {@"exteria.ayu.replyquote", YES},
    [ExteriaChatFlagLocalPremium] = {@"exteria.chat.localpremium", NO},
    [ExteriaChatFlagCrashReports] = {@"exteria.chat.crashreports", YES},
    [ExteriaChatFlagBoykisser] = {@"exteria.chat.boykisser", NO},
    [ExteriaChatFlagSnow] = {@"exteria.chat.snow", NO},
    [ExteriaChatFlagFoxes] = {@"exteria.chat.foxes", NO},
    [ExteriaChatFlagHideWaves] = {@"exteria.chat.hidewaves", NO},
    [ExteriaChatFlagShowMessageEmojiStatus] = {@"exteria.chat.messageemojistatus", YES},
    [ExteriaChatFlagShowReplyCustomEmoji] = {@"exteria.chat.replycustomemoji", YES},
    [ExteriaChatFlagAyuCopyProtected] = {@"exteria.ayu.copyprotected", NO},
    [ExteriaChatFlagSenderAvatars] = {@"exteria.chat.senderavatars", NO},
    [ExteriaChatFlagHideSearchBar] = {@"exteria.chat.hidesearch", NO},
    [ExteriaChatFlagHideStories] = {@"exteria.chat.hidestories", NO},
    [ExteriaChatFlagHideAllChatsTab] = {@"exteria.chat.hidealltab", NO},
    [ExteriaChatFlagNoUnarchiveSwipe] = {@"exteria.chat.nounarchiveswipe", NO},
    [ExteriaChatFlagHideVpnButton] = {@"exteria.chat.hidevpn", NO},
};

BOOL ExteriaChatFlagGet(ExteriaChatFlag flag) {
    if ((NSUInteger)flag >= ExteriaChatFlagCount) return NO;
    return ExteriaStoredFlag(ExteriaChatFlagTable[flag].key, ExteriaChatFlagTable[flag].fallback);
}

void ExteriaChatFlagSet(ExteriaChatFlag flag, BOOL on) {
    if ((NSUInteger)flag >= ExteriaChatFlagCount) return;
    ExteriaStoreFlag(ExteriaChatFlagTable[flag].key, on);
}

static NSString *const ExteriaChatLinkConfirmKey = @"exteria.chat.linkconfirm";

ExteriaLinkConfirm ExteriaChatLinkConfirm(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatLinkConfirmKey);
    NSInteger value = stored ? stored.integerValue : ExteriaLinkConfirmNever;
    return value == ExteriaLinkConfirmHidden || value == ExteriaLinkConfirmAlways ? (ExteriaLinkConfirm)value : ExteriaLinkConfirmNever;
}

void ExteriaChatSetLinkConfirm(ExteriaLinkConfirm mode) {
    ExteriaStoreNumber(ExteriaChatLinkConfirmKey, mode);
}

static NSString *const ExteriaChatDoubleTapInKey = @"exteria.chat.doubletap.in";
static NSString *const ExteriaChatDoubleTapOutKey = @"exteria.chat.doubletap.out";
static NSString *const ExteriaChatSeekKey = @"exteria.chat.seek";
static NSString *const ExteriaChatStickerScaleKey = @"exteria.chat.stickerscale";
static NSString *const ExteriaChatStickerShapeKey = @"exteria.chat.stickershape";

static NSString *const ExteriaChatQuickReactionOffKey = @"exteria.chat.quickreaction.off";

BOOL ExteriaChatQuickReactionEnabled(void) {
    NSNumber *off = ExteriaStoredNumber(ExteriaChatQuickReactionOffKey);
    return !off.integerValue;
}

void ExteriaChatSetQuickReactionEnabled(BOOL enabled) {
    ExteriaStoreNumber(ExteriaChatQuickReactionOffKey, enabled ? 0 : 1);
}

ExteriaDoubleTapAction ExteriaChatDoubleTap(BOOL outgoing) {
    NSNumber *stored = ExteriaStoredNumber(outgoing ? ExteriaChatDoubleTapOutKey : ExteriaChatDoubleTapInKey);
    /* reacts to a double tap out of the box */
    NSInteger value = stored ? stored.integerValue : ExteriaDoubleTapReaction;
    if (value == ExteriaDoubleTapReaction && !ExteriaChatQuickReactionEnabled()) return ExteriaDoubleTapNone;
    return value >= ExteriaDoubleTapNone && value < ExteriaDoubleTapCount ? (ExteriaDoubleTapAction)value : ExteriaDoubleTapNone;
}

static NSString *const ExteriaChatQuickReactionKey = @"exteria.chat.quickreaction";

NSString *ExteriaChatQuickReaction(void) {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:ExteriaChatQuickReactionKey];
    return stored.length ? stored : @"\u2764";
}

void ExteriaChatSetQuickReaction(NSString *emoji) {
    if (emoji.length) [[NSUserDefaults standardUserDefaults] setObject:emoji forKey:ExteriaChatQuickReactionKey];
}

NSString *ExteriaChatQuickReactionDisplay(void) {
    if (!exteria_quick_reaction_document(ExteriaChatQuickReaction().UTF8String)) return ExteriaChatQuickReaction();
    NSString *alt = [[NSUserDefaults standardUserDefaults] stringForKey:@"exteria.chat.quickreaction.alt"];
    return alt.length ? alt : @"✨";
}

void ExteriaChatSetQuickCustomReaction(long long documentId, NSString *alt) {
    if (documentId <= 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:alt.length ? alt : @"✨" forKey:@"exteria.chat.quickreaction.alt"];
    ExteriaChatSetQuickReaction([NSString stringWithFormat:@"animated_%lld", documentId]);
}

void ExteriaChatSetDoubleTap(BOOL outgoing, ExteriaDoubleTapAction action) {
    ExteriaStoreNumber(outgoing ? ExteriaChatDoubleTapOutKey : ExteriaChatDoubleTapInKey, action);
}

NSInteger ExteriaChatSeekSeconds(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatSeekKey);
    NSInteger value = stored ? stored.integerValue : 10;
    return value == 5 || value == 10 || value == 15 || value == 30 ? value : 10;
}

void ExteriaChatSetSeekSeconds(NSInteger seconds) {
    ExteriaStoreNumber(ExteriaChatSeekKey, seconds == 5 || seconds == 15 || seconds == 30 ? seconds : 10);
}

NSInteger ExteriaChatStickerScale(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatStickerScaleKey);
    return stored ? ExteriaClamped(stored.integerValue, EXTERIA_STICKER_SCALE_MIN, EXTERIA_STICKER_SCALE_MAX) : 100;
}

void ExteriaChatSetStickerScale(NSInteger percent) {
    ExteriaStoreNumber(ExteriaChatStickerScaleKey, ExteriaClamped(percent, EXTERIA_STICKER_SCALE_MIN, EXTERIA_STICKER_SCALE_MAX));
}

ExteriaStickerShape ExteriaChatStickerShape(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatStickerShapeKey);
    NSInteger value = stored ? stored.integerValue : ExteriaStickerShapeRounded;
    return value >= ExteriaStickerShapeNone && value <= ExteriaStickerShapeBubble ? (ExteriaStickerShape)value : ExteriaStickerShapeRounded;
}

void ExteriaChatSetStickerShape(ExteriaStickerShape shape) {
    ExteriaStoreNumber(ExteriaChatStickerShapeKey, shape);
}

ExteriaChatSwipe ExteriaChatSwipeStored(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatSwipeKey);
    NSInteger value = stored ? stored.integerValue : ExteriaChatSwipeArchive;
    return value >= ExteriaChatSwipeArchive && value <= ExteriaChatSwipeFolders ? (ExteriaChatSwipe)value : ExteriaChatSwipeArchive;
}

static NSString *const ExteriaChatRecordLockKey = @"exteria.chat.recordlock";

NSInteger ExteriaChatRecordLockSeconds(void) {
    NSNumber *stored = ExteriaStoredNumber(ExteriaChatRecordLockKey);
    if (!stored) return 5;
    NSInteger value = stored.integerValue;
    return value == 0 || value == 3 || value == 5 || value == 10 || value == 15 ? value : 5;
}

void ExteriaChatSetRecordLockSeconds(NSInteger seconds) {
    ExteriaStoreNumber(ExteriaChatRecordLockKey, seconds);
}

void ExteriaChatSetSwipe(ExteriaChatSwipe swipe) {
    ExteriaStoreNumber(ExteriaChatSwipeKey, swipe);
}

void ExteriaChatResetAppearance(void) {
    ExteriaTrace(@"RESET appearance");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaChatTextSizeKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaChatBubbleRadiusKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the chat appearance was not reset on disk");
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
}

BOOL ExteriaChatAppearanceChanged(void) {
    return ExteriaChatTextSize() != ExteriaChatDefaultTextSize() || ExteriaChatBubbleRadius() != EXTERIA_CHAT_BUBBLE_RADIUS_MAX;
}

void ExteriaChatSettingsForgetCached(void) {
    ExteriaAvatarCornerCurrent = -1;
    ExteriaSectionRadiusCurrent = -1;
}
