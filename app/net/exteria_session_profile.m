#import "exteria_session_internal.h"

#include "exteria_avatars.h"
#include "exteria_profile.h"

#import "exteria_rpc.h"
#import "exteria_session_profile.h"
#import "exteria_message.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *ExteriaProfileUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaPersonalChannel
@synthesize dialog = _dialog;
@synthesize subscribers = _subscribers;
@synthesize lastText = _lastText;
@synthesize lastDate = _lastDate;
- (id)initWithDialog:(ExteriaDialog *)dialog subscribers:(NSInteger)subscribers lastText:(NSString *)text lastDate:(int32_t)date {
    self = [super init];
    if (!self) return nil;
    _dialog = [dialog retain];
    _subscribers = subscribers;
    _lastText = [(text ? text : @"") copy];
    _lastDate = date;
    return self;
}
- (void)dealloc {
    [_dialog release];
    [_lastText release];
    [super dealloc];
}
@end

@implementation ExteriaFullUser
@synthesize about = _about;
@synthesize person = _person;
@synthesize requiresPremium = _requiresPremium;
@synthesize sharingRestricted = _sharingRestricted;
@synthesize hasBirthday = _hasBirthday;
@synthesize birthdayDay = _birthdayDay;
@synthesize birthdayMonth = _birthdayMonth;
@synthesize birthdayYear = _birthdayYear;
@synthesize channel = _channel;
@synthesize music = _music;
@synthesize hasRating = _hasRating, hasPendingRating = _hasPendingRating, pendingRatingDate = _pendingRatingDate;
@synthesize rating = _rating, pendingRating = _pendingRating;
- (id)initWithRow:(const exteria_full_user *)row channel:(ExteriaPersonalChannel *)channel {
    self = [super init];
    if (!self) return nil;
    _about = [ExteriaProfileUtf8(row->about) copy];
    if (row->has_person) _person = [[ExteriaPerson alloc] initWithRow:&row->person];
    _requiresPremium = row->require_premium != 0;
    _sharingRestricted = row->sharing_restricted != 0;
    _hasBirthday = row->has_birthday;
    _birthdayDay = row->birthday_day;
    _birthdayMonth = row->birthday_month;
    _birthdayYear = row->birthday_year;
    _channel = [channel retain];
    if (row->has_music) _music = [[ExteriaMedia mediaWithInfo:&row->music] retain];
    _hasRating = row->has_rating;
    _hasPendingRating = row->has_pending_rating;
    _pendingRatingDate = row->pending_rating_date;
    _rating = row->rating;
    _pendingRating = row->pending_rating;
    return self;
}
- (void)dealloc {
    [_about release];
    [_person release];
    [_channel release];
    [_music release];
    [super dealloc];
}
@end

/* the words that stand for a message that is not text, as the chat list says them */
NSString *ExteriaPreviewWord(exteria_preview_kind kind) {
    switch (kind) {
    case EXTERIA_PREVIEW_PHOTO: return NSLocalizedString(@"preview.photo", nil);
    case EXTERIA_PREVIEW_VIDEO: return NSLocalizedString(@"preview.video", nil);
    case EXTERIA_PREVIEW_VIDEO_MESSAGE: return NSLocalizedString(@"preview.videomessage", nil);
    case EXTERIA_PREVIEW_VOICE: return NSLocalizedString(@"preview.voice", nil);
    case EXTERIA_PREVIEW_AUDIO: return NSLocalizedString(@"preview.audio", nil);
    case EXTERIA_PREVIEW_STICKER: return NSLocalizedString(@"preview.sticker", nil);
    case EXTERIA_PREVIEW_GIF: return NSLocalizedString(@"preview.gif", nil);
    case EXTERIA_PREVIEW_FILE: return NSLocalizedString(@"preview.file", nil);
    case EXTERIA_PREVIEW_LOCATION: return NSLocalizedString(@"preview.location", nil);
    case EXTERIA_PREVIEW_CONTACT: return NSLocalizedString(@"preview.contact", nil);
    case EXTERIA_PREVIEW_POLL: return NSLocalizedString(@"preview.poll", nil);
    default: return @"";
    }
}

@implementation ExteriaSession (Profile)

- (void)loadFullUserOfDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaFullUser *, NSString *))completion {
    void (^done)(ExteriaFullUser *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_full_user_peer_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) {
            NSString *error = ExteriaRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, delivered); [done release]; }];
            return;
        }
        exteria_full_user *full = calloc(1, sizeof(*full));
        exteria_status status = full ? exteria_full_user_parse(result->value, full) : EXTERIA_E_NOMEM;
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: users.getFullUser answer rejected: %s", exteria_status_name(status));
            free(full);
            [self deliverMain:^{ done(nil, @"INTERNAL"); [done release]; }];
            return;
        }
        ExteriaDialog *channelDialog = nil;
        if (full->has_channel) {
            exteria_dialog_row row = full->channel;
            channelDialog = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
        }
        NSInteger subscribers = full->channel_participants;
        int32_t messageId = full->channel_message;
        void (^finish)(NSString *, int32_t) = ^(NSString *text, int32_t date) {
            ExteriaPersonalChannel *channel = channelDialog ? [[[ExteriaPersonalChannel alloc] initWithDialog:channelDialog subscribers:subscribers
                                                                                                    lastText:text lastDate:date] autorelease] : nil;
            ExteriaFullUser *user = [[[ExteriaFullUser alloc] initWithRow:full channel:channel] autorelease];
            free(full);
            [self deliverMain:^{ done(user, nil); [done release]; }];
        };
        if (!channelDialog || messageId <= 0) {
            finish(nil, 0);
            return;
        }
        exteria_peer_ref channelPeer = ExteriaPeerRefOfDialog(channelDialog);
        [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_channel_message_request(arena, &channelPeer, messageId, request);
        } handler:^(const exteria_mt_rpc_result *messageResult) {
            NSString *text = nil;
            int32_t date = 0;
            if (messageResult->status == EXTERIA_OK) {
                exteria_message_row *rows = calloc(2, sizeof(*rows));
                size_t count = 0;
                if (rows && exteria_messages_parse(messageResult->value, rows, 2, &count) == EXTERIA_OK && count > 0) {
                    text = rows[0].text[0] ? ExteriaProfileUtf8(rows[0].text) : ExteriaPreviewWord(rows[0].media.kind);
                    date = rows[0].date;
                }
                free(rows);
            } else {
                /* the profile is still worth showing without the line of text */
                NSLog(@"exteria: personal channel message not loaded: %@", ExteriaRpcErrorName(messageResult));
            }
            finish(text, date);
        }];
    }];
}

/* the Premium state of the signed in person is the same for every chat, so it is asked once */
static NSNumber *ExteriaSelfPremium;

- (void)loadPremiumGateOfDialog:(ExteriaDialog *)dialog completion:(void (^)(BOOL blocked))completion {
    void (^done)(BOOL) = [completion copy];
    if (dialog.kind != EXTERIA_DIALOG_USER || dialog.saved) { done(NO); [done release]; return; }
    [self loadFullUserOfDialog:dialog completion:^(ExteriaFullUser *user, NSString *errorName) {
        if (errorName || !user.requiresPremium) {
            if (errorName) NSLog(@"exteria: premium gate not known, full profile failed: %@", errorName);
            done(NO);
            [done release];
            return;
        }
        if (ExteriaSelfPremium) { done(!ExteriaSelfPremium.boolValue); [done release]; return; }
        [self loadSelf:^(NSArray *items, NSString *selfError) {
            ExteriaPerson *me = items.count ? [items objectAtIndex:0] : nil;
            if (!me) {
                NSLog(@"exteria: premium gate not known, own profile failed: %@", selfError);
                done(NO);
            } else {
                [ExteriaSelfPremium release];
                ExteriaSelfPremium = [[NSNumber numberWithBool:me.premium] retain];
                done(!me.premium);
            }
            [done release];
        }];
    }];
}

- (void)loadSavedMusicOfDialog:(ExteriaDialog *)dialog offset:(NSInteger)offset completion:(void (^)(NSArray *, NSInteger, NSString *))completion {
    void (^done)(NSArray *, NSInteger, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_saved_music_request(arena, &peer, (int32_t)offset, EXTERIA_MUSIC_PAGE, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) {
            NSString *error = ExteriaRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, 0, delivered); [done release]; }];
            return;
        }
        exteria_media_info *rows = calloc(EXTERIA_MUSIC_PAGE, sizeof(*rows));
        size_t count = 0;
        int32_t total = 0;
        exteria_status status = rows ? exteria_saved_music_parse(result->value, rows, EXTERIA_MUSIC_PAGE, &count, &total) : EXTERIA_E_NOMEM;
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: users.getSavedMusic answer rejected: %s", exteria_status_name(status));
            free(rows);
            [self deliverMain:^{ done(nil, 0, @"INTERNAL"); [done release]; }];
            return;
        }
        NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) [tracks addObject:[ExteriaMedia mediaWithInfo:&rows[i]]];
        free(rows);
        [self deliverMain:^{ done(tracks, total, nil); [done release]; }];
    }];
}

- (void)loadAvatarsOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    BOOL user = peer.kind == 1 || peer.self;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return user ? exteria_user_photos_request(arena, &peer, EXTERIA_AVATARS_MAX, request)
                    : exteria_chat_photos_request(arena, &peer, EXTERIA_AVATARS_MAX, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        if (result->status != EXTERIA_OK) {
            NSString *error = ExteriaRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, delivered); [done release]; }];
            return;
        }
        exteria_media_info *rows = calloc(EXTERIA_AVATARS_MAX, sizeof(*rows));
        size_t count = 0;
        int32_t total = 0;
        exteria_status status = EXTERIA_E_NOMEM;
        if (rows) status = user ? exteria_user_avatars_parse(result->value, rows, EXTERIA_AVATARS_MAX, &count, &total)
                                : exteria_chat_avatars_parse(result->value, rows, EXTERIA_AVATARS_MAX, &count);
        if (status != EXTERIA_OK) {
            NSLog(@"exteria: profile photos answer rejected: %s", exteria_status_name(status));
            free(rows);
            [self deliverMain:^{ done(nil, @"INTERNAL"); [done release]; }];
            return;
        }
        NSMutableArray *photos = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) [photos addObject:[ExteriaMedia mediaWithInfo:&rows[i]]];
        free(rows);
        [self deliverMain:^{ done(photos, nil); [done release]; }];
    }];
}

- (void)saveMusic:(ExteriaMedia *)song unsave:(BOOL)unsave completion:(void (^)(NSString *))completion {
    exteria_media_ref ref = song.ref;
    [self runBoolRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_save_music_request(arena, &ref, unsave ? 1 : 0, request);
    } completion:completion];
}

- (void)runBoolRequest:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)setBirthdayDay:(int32_t)day month:(int32_t)month year:(int32_t)year completion:(void (^)(NSString *))completion {
    [self runBoolRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_birthday_request(arena, day, month, year, request);
    } completion:completion];
}

- (void)clearBirthday:(void (^)(NSString *))completion {
    [self runBoolRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_birthday_clear_request(arena, request);
    } completion:completion];
}

- (void)loadChannelsForProfile:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_admined_channels_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *channels = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_dialog_row *rows = calloc(EXTERIA_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            exteria_status status = rows ? exteria_admined_channels_parse(result->value, rows, EXTERIA_DIALOGS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                channels = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [channels addObject:[[[ExteriaDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"exteria: channels.getAdminedPublicChannels answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:channels error:error completion:done];
        [done release];
    }];
}

- (void)setPersonalChannel:(ExteriaDialog *)channel completion:(void (^)(NSString *))completion {
    BOOL has = channel != nil;
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    if (has) peer = ExteriaPeerRefOfDialog(channel);
    [self runBoolRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_personal_channel_request(arena, has ? &peer : NULL, request);
    } completion:completion];
}


- (void)loadAbout:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_full_user_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *about = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_full_user full;
            exteria_status status = exteria_full_user_parse(result->value, &full);
            if (status == EXTERIA_OK) {
                about = [NSString stringWithUTF8String:full.about];
                if (!about) about = @"";
            } else {
                NSLog(@"exteria: users.getFullUser answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *deliveredAbout = [[about copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredAbout, deliveredError); [done release]; }];
    }];
}

/* the answer of a profile change is the user as the server now has them */
- (void)finishPersonResult:(const exteria_mt_rpc_result *)result completion:(void (^)(ExteriaPerson *, NSString *))done {
    ExteriaPerson *person = nil;
    NSString *error = nil;
    if (result->status != EXTERIA_OK) {
        error = ExteriaRpcErrorName(result);
    } else {
        exteria_person_row row;
        exteria_status status = exteria_person_parse(result->value, &row);
        if (status == EXTERIA_OK) {
            person = [[[ExteriaPerson alloc] initWithRow:&row] autorelease];
        } else {
            NSLog(@"exteria: profile change answer rejected: %s", exteria_status_name(status));
            error = @"INTERNAL";
        }
    }
    [self noteRpcError:error];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(person, deliveredError); [done release]; }];
}

- (void)updateFirstName:(NSString *)firstName lastName:(NSString *)lastName about:(NSString *)about
             completion:(void (^)(ExteriaPerson *, NSString *))completion {
    void (^done)(ExteriaPerson *, NSString *) = [completion copy];
    NSString *first = [firstName copy], *last = [lastName copy], *bio = [about copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_profile_update_request(arena, first.UTF8String, last.UTF8String, bio.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishPersonResult:result completion:done];
    }];
    [first release];
    [last release];
    [bio release];
}

- (void)updateUsername:(NSString *)username completion:(void (^)(ExteriaPerson *, NSString *))completion {
    void (^done)(ExteriaPerson *, NSString *) = [completion copy];
    NSString *name = [username copy];
    if (exteria_username_check(name.UTF8String) != EXTERIA_OK) {
        [name release];
        [self deliverMain:^{ done(nil, @"USERNAME_INVALID"); [done release]; }];
        return;
    }
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_username_request(arena, name.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishPersonResult:result completion:done];
    }];
    [name release];
}

@end
