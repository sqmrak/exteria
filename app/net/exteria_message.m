#import "exteria_message.h"
#import "exteria_text_filter.h"

#import "exteria_person.h"
#import "exteria_remote_file.h"
#import "exteria_star_gift.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *ExteriaUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaMedia

@synthesize name = _name;
@synthesize alt = _alt;
@synthesize title = _title;
@synthesize performer = _performer;
@synthesize waveformBars = _waveformBars;

+ (ExteriaMedia *)mediaWithInfo:(const exteria_media_info *)info {
    ExteriaMedia *media = [[[ExteriaMedia alloc] init] autorelease];
    media->_info = *info;
    media->_name = [ExteriaUtf8(info->name) copy];
    media->_alt = [ExteriaUtf8(info->alt) copy];
    media->_title = [ExteriaUtf8(info->title) copy];
    media->_performer = [ExteriaUtf8(info->performer) copy];
    if (info->waveform_len) {
        uint8_t bars[EXTERIA_MEDIA_WAVEFORM_MAX * 8 / 5 + 1];
        size_t count = 0;
        if (exteria_waveform_unpack(info->waveform, info->waveform_len, bars, sizeof(bars), &count) == EXTERIA_OK && count > 0)
            media->_waveformBars = [[NSData alloc] initWithBytes:bars length:count];
    }
    return media;
}

- (void)dealloc {
    [_name release];
    [_alt release];
    [_title release];
    [_performer release];
    [_waveformBars release];
    [super dealloc];
}

- (exteria_preview_kind)kind { return _info.kind; }
- (exteria_geo_point)location { return _info.location; }
- (exteria_sticker_format)stickerFormat { return _info.sticker; }
- (long long)stickerSetId { return _info.sticker_set_id; }
- (long long)stickerSetHash { return _info.sticker_set_hash; }
- (BOOL)spoiler { return _info.spoiler != 0; }
- (int32_t)ttlSeconds { return _info.ttl_seconds; }
- (BOOL)viewOnce { return _info.ttl_seconds > 0; }
- (int32_t)width { return _info.width; }
- (int32_t)height { return _info.height; }
- (int32_t)duration { return _info.duration; }
- (long long)size { return _info.size; }
- (exteria_media_ref)ref { return _info.ref; }
- (ExteriaRemoteFile *)file { return [ExteriaRemoteFile fileForMedia:&_info.ref]; }
- (ExteriaRemoteFile *)previewFile { return [ExteriaRemoteFile fileForMedia:&_info.preview]; }
- (ExteriaRemoteFile *)fullPhotoFile { return [ExteriaRemoteFile fileForMedia:&_info.full_photo]; }
- (long long)fullPhotoSize { return _info.full_photo_size; }

@end

@implementation ExteriaTextEntity

@synthesize style = _style;
@synthesize range = _range;
@synthesize url = _url;
@synthesize documentId = _documentId;
@synthesize userId = _userId;
@synthesize accessHash = _accessHash;
@synthesize date = _date;
@synthesize flags = _flags;

- (id)initWithStyle:(ExteriaTextStyle)style range:(NSRange)range url:(NSString *)url {
    self = [super init];
    if (!self) return nil;
    _style = style;
    _range = range;
    _url = [url copy];
    return self;
}

- (void)dealloc {
    [_url release];
    [super dealloc];
}

@end

@implementation ExteriaOutgoing

- (void)dealloc {
    [path release];
    [name release];
    [mime release];
    [waveform release];
    [caption release];
    [phone release];
    [preview release];
    [super dealloc];
}

@end

@implementation ExteriaReaction

+ (ExteriaReaction *)reactionWithRow:(const exteria_reaction *)row {
    ExteriaReaction *reaction = [[[ExteriaReaction alloc] init] autorelease];
    reaction->_row = *row;
    return reaction;
}
static NSMutableDictionary *ExteriaCustomTexts(void) {
    static NSMutableDictionary *texts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ texts = [[NSMutableDictionary alloc] init]; });
    return texts;
}

+ (void)rememberCustomTexts:(NSDictionary *)texts {
    [ExteriaCustomTexts() addEntriesFromDictionary:texts];
}

+ (BOOL)knowsCustomDocument:(long long)documentId {
    return [ExteriaCustomTexts() objectForKey:[NSNumber numberWithLongLong:documentId]] != nil;
}

- (void)dealloc {
    [_faces release];
    [super dealloc];
}

@synthesize faces = _faces;

- (NSArray *)reactorIds {
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:_row.reactor_count];
    for (uint8_t i = 0; i < _row.reactor_count; ++i) [ids addObject:[NSNumber numberWithLongLong:_row.reactors[i]]];
    return ids;
}

- (NSString *)faceKey {
    NSMutableString *key = [NSMutableString string];
    for (id person in _faces) [key appendFormat:@"%lld,", [(ExteriaPerson *)person userId]];
    return key;
}

- (exteria_reaction)row { return _row; }
- (NSString *)emoji { return ExteriaUtf8(_row.emoji); }
- (BOOL)chosen { return _row.chosen; }
- (int32_t)count { return _row.count; }
- (NSString *)key {
    return [NSString stringWithFormat:@"%u:%lld:%@", _row.kind, (long long)_row.document_id, self.emoji];
}
- (NSString *)displayText {
    if (_row.kind == EXTERIA_REACTION_PAID) return @"⭐";
    if (_row.kind == EXTERIA_REACTION_CUSTOM) {
        NSString *text = [ExteriaCustomTexts() objectForKey:[NSNumber numberWithLongLong:_row.document_id]];
        return text ? text : NSLocalizedString(@"chat.reaction.custom", nil);
    }
    return self.emoji;
}
- (NSArray *)displayEntities {
    if (_row.kind != EXTERIA_REACTION_CUSTOM || ![ExteriaReaction knowsCustomDocument:_row.document_id]) return nil;
    ExteriaTextEntity *entity = [[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleCustomEmoji
                                                                    range:NSMakeRange(0, self.displayText.length) url:nil] autorelease];
    entity.documentId = _row.document_id;
    return [NSArray arrayWithObject:entity];
}

@end

@implementation ExteriaMessage

@synthesize messageId = _messageId;
@synthesize date = _date;
@synthesize replyTo = _replyTo;
@synthesize replyPeerKind = _replyPeerKind;
@synthesize replyPeerId = _replyPeerId;
@synthesize replyQuote = _replyQuote;
@synthesize topicId = _topicId;
@synthesize threadId = _threadId;
@synthesize fromId = _fromId;
@synthesize fromChannel = _fromChannel;
@synthesize views = _views;
@synthesize hasComments = _hasComments;
@synthesize comments = _comments;
@synthesize discussionId = _discussionId;
@synthesize commenters = _commenters;
@synthesize targetId = _targetId;
@synthesize randomId = _randomId;
@synthesize outgoing = _outgoing;
@synthesize unreadMention = _unreadMention;
@synthesize post = _post;
@synthesize spoilersRevealed = _spoilersRevealed;
@synthesize viewOnceOpened = _viewOnceOpened;
@synthesize forwarded = _forwarded;
@synthesize edited = _edited;
@synthesize deletedLocally = _deletedLocally;
@synthesize uploadProgress = _uploadProgress;
@synthesize service = _service;
@synthesize serviceValue = _serviceValue;
@synthesize state = _state;
@synthesize pendingSend = _pendingSend;
@synthesize text = _text;
@synthesize forwardName = _forwardName;
@synthesize forwardDate = _forwardDate;
@synthesize groupedId = _groupedId;
@synthesize forwardKey = _forwardKey;
@synthesize savedPeerKind = _savedPeerKind;
@synthesize savedPeerId = _savedPeerId;

/* in the favorites a message stands on the right only when the account wrote it: a forward of somebody else is theirs, as exteraGram draws it */
- (void)noteEditedToText:(NSString *)text {
    if (!text) return;
    NSString *copy = [text copy];
    [_text release];
    _text = copy;
    _edited = YES;
}

- (void)placeInSavedMessagesOfUser:(long long)userId {
    if (!_post) _outgoing = !_forwarded || _forwardKey == userId || _savedOut;
}
@synthesize callOutcome = _callOutcome;
@synthesize callVideo = _callVideo;
@synthesize senderRank = _senderRank;
@synthesize entities = _entities;
@synthesize poll = _poll;
@synthesize media = _media;
@synthesize giftTitle = _giftTitle;
@synthesize giftStars = _giftStars;
@synthesize giftNumber = _giftNumber;
@synthesize gift = _gift;
@synthesize reactions = _reactions;
@synthesize reactionsPossible = _reactionsPossible;
@synthesize hasReactions = _hasReactions;

@synthesize viaBotId = _viaBotId;
@synthesize sendReplyTo = _sendReplyTo;
@synthesize markup = _markup;
@synthesize hasMarkup = _hasMarkup;

- (NSString *)markupKey {
    if (!_markup) return @"";
    NSMutableString *key = [NSMutableString stringWithFormat:@"%d:", (int)_markup.kind];
    for (NSArray *row in _markup.rows) {
        for (ExteriaMarkupButton *button in row) [key appendFormat:@"%d,%@,%@;", (int)button.kind, button.text, button.argument];
        [key appendString:@"|"];
    }
    return key;
}

- (NSString *)pollKey {
    return _poll ? [_poll stateKey] : @"";
}

- (NSString *)reactionKey {
    NSMutableString *key = [NSMutableString string];
    for (ExteriaReaction *r in _reactions) [key appendFormat:@"%@=%d:%d:%d:%@;", r.key, r.count, r.chosen, r.row.chosen_order, r.faceKey];
    return key;
}

static ExteriaTextStyle ExteriaStyleOfEntity(uint8_t kind, BOOL *link) {
    *link = NO;
    switch (kind) {
    case EXTERIA_ENTITY_BOLD: return ExteriaTextStyleBold;
    case EXTERIA_ENTITY_ITALIC: return ExteriaTextStyleItalic;
    case EXTERIA_ENTITY_UNDERLINE: return ExteriaTextStyleUnderline;
    case EXTERIA_ENTITY_STRIKE: return ExteriaTextStyleStrike;
    case EXTERIA_ENTITY_CODE: return ExteriaTextStyleCode;
    case EXTERIA_ENTITY_MENTION: return ExteriaTextStyleMention;
    case EXTERIA_ENTITY_HASHTAG: return ExteriaTextStyleHashtag;
    case EXTERIA_ENTITY_CUSTOM_EMOJI: return ExteriaTextStyleCustomEmoji;
    case EXTERIA_ENTITY_BOT_COMMAND: return ExteriaTextStyleBotCommand;
    case EXTERIA_ENTITY_SPOILER: return ExteriaTextStyleSpoiler;
    case EXTERIA_ENTITY_PRE: return ExteriaTextStylePre;
    case EXTERIA_ENTITY_BLOCKQUOTE: return ExteriaTextStyleQuote;
    case EXTERIA_ENTITY_MENTION_NAME: return ExteriaTextStyleMentionName;
    case EXTERIA_ENTITY_FORMATTED_DATE: return ExteriaTextStyleDate;
    default: break;
    }
    *link = YES;
    return ExteriaTextStyleLink;
}

NSArray *ExteriaTextEntities(NSString *text, const exteria_entity *entities, size_t count, const char *urls) {
    NSUInteger length = text.length;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; ++i) {
        const exteria_entity *e = &entities[i];
        if (e->offset < 0 || e->length <= 0 || (NSUInteger)e->offset >= length || (NSUInteger)e->length > length - (NSUInteger)e->offset) continue;
        BOOL link;
        ExteriaTextStyle style = ExteriaStyleOfEntity(e->kind, &link);
        NSString *url = nil;
        if ((e->kind == EXTERIA_ENTITY_TEXT_URL || e->kind == EXTERIA_ENTITY_PRE) && e->url_offset >= 0 && urls) url = ExteriaUtf8(urls + e->url_offset);
        else if (e->kind == EXTERIA_ENTITY_EMAIL) url = [@"mailto:" stringByAppendingString:[text substringWithRange:NSMakeRange((NSUInteger)e->offset, (NSUInteger)e->length)]];
        ExteriaTextEntity *entity = [[[ExteriaTextEntity alloc] initWithStyle:style range:NSMakeRange((NSUInteger)e->offset, (NSUInteger)e->length) url:url] autorelease];
        entity.documentId = e->document_id;
        entity.userId = e->user_id;
        entity.date = e->date;
        entity.flags = e->flags;
        [result addObject:entity];
    }
    return result;
}

- (long long)senderKey {
    return _fromId ? _fromId : -_fromChannel;
}

+ (ExteriaMessage *)messageWithRow:(const exteria_message_row *)row {
    ExteriaMessage *message = [[[ExteriaMessage alloc] init] autorelease];
    message->_messageId = row->id;
    message->_date = row->date;
    message->_replyTo = row->reply_to;
    message->_replyPeerKind = row->reply_peer_kind;
    message->_replyPeerId = row->reply_peer_id;
    message->_replyQuote = [[NSString stringWithUTF8String:row->reply_quote] copy];
    message->_topicId = row->topic_id;
    message->_threadId = row->thread_id;
    message->_fromId = row->from_id;
    message->_fromChannel = row->from_channel;
    message->_views = row->views;
    message->_hasComments = row->has_comments;
    message->_comments = row->comments;
    message->_discussionId = row->discussion_id;
    NSMutableArray *commenters = [NSMutableArray arrayWithCapacity:row->commenter_count];
    for (uint8_t i = 0; i < row->commenter_count; ++i) [commenters addObject:[NSNumber numberWithLongLong:row->commenters[i]]];
    message->_commenters = [commenters copy];
    message->_targetId = row->target_id;
    /* a post is written by the channel, not by the account that typed it, so it stands on the left like the posts of anyone else */
    message->_outgoing = row->out && !row->post;
    message->_unreadMention = row->unread_mention;
    message->_post = row->post;
    message->_forwarded = row->forwarded;
    message->_savedOut = row->forward_saved_out;
    message->_savedPeerKind = row->saved_peer_kind;
    message->_savedPeerId = row->saved_peer_id;
    /* a reaction changes the message on the server and gives it an edit date with the hide flag set; the words were not touched */
    message->_edited = row->edit_date > 0 && !row->edit_hide;
    message->_service = row->service;
    message->_serviceValue = row->service_value;
    message->_viaBotId = row->via_bot_id;
    message->_hasMarkup = row->has_markup;
    message->_reactionsPossible = row->reactions_possible;
    message->_hasReactions = row->has_reactions;
    NSMutableArray *reactions = [NSMutableArray arrayWithCapacity:row->reactions.count];
    for (uint8_t i = 0; i < row->reactions.count; ++i)
        [reactions addObject:[ExteriaReaction reactionWithRow:&row->reactions.items[i]]];
    message->_reactions = [reactions copy];
    /* the entities point into the text, so a text that has some is left whole */
    message->_text = [(row->entity_count ? ExteriaUtf8(row->text) : ExteriaFilteredText(ExteriaUtf8(row->text))) copy];
    message->_forwardName = [ExteriaUtf8(row->forward_name) copy];
    message->_forwardDate = row->forward_date;
    message->_groupedId = row->grouped_id;
    message->_forwardKey = row->forward_from;
    message->_callOutcome = row->call_reason;
    message->_callVideo = row->call_video != 0;
    message->_senderRank = [ExteriaUtf8(row->from_rank) copy];
    message->_media = [[ExteriaMedia mediaWithInfo:&row->media] retain];
    message->_giftTitle = [ExteriaUtf8(row->gift.title) copy];
    message->_giftStars = row->gift.stars;
    message->_giftNumber = row->gift.num;
    if (row->gift.id != 0) message->_gift = [[ExteriaStarGift giftWithRow:&row->gift] retain];
    message->_entities = [ExteriaTextEntities(message->_text, row->entities, row->entity_count, row->urls) retain];
    message->_poll = [[ExteriaPoll pollWithRow:&row->poll] retain];
    return message;
}

+ (ExteriaMessage *)pendingText:(NSString *)text randomId:(long long)randomId date:(int32_t)date {
    return [self pendingText:text entities:nil randomId:randomId date:date];
}

+ (ExteriaMessage *)pendingText:(NSString *)text entities:(NSArray *)entities randomId:(long long)randomId date:(int32_t)date {
    ExteriaMessage *message = [[[ExteriaMessage alloc] init] autorelease];
    message->_date = date;
    message->_randomId = randomId;
    message->_outgoing = YES;
    message->_state = ExteriaMessageStateSending;
    message->_text = [text copy];
    message->_forwardName = [@"" copy];
    message->_senderRank = [@"" copy];
    message->_entities = entities ? [entities copy] : [[NSArray alloc] init];
    exteria_media_info info;
    memset(&info, 0, sizeof(info));
    info.kind = EXTERIA_PREVIEW_TEXT;
    message->_media = [[ExteriaMedia mediaWithInfo:&info] retain];
    return message;
}

- (void)showAsChannelPost {
    _outgoing = NO;
    _post = YES;
}

+ (ExteriaMessage *)pendingSticker:(ExteriaMedia *)sticker randomId:(long long)randomId date:(int32_t)date {
    ExteriaMessage *message = [ExteriaMessage pendingText:@"" randomId:randomId date:date];
    [message->_media release];
    message->_media = [sticker retain];
    return message;
}

+ (ExteriaMessage *)pendingOutgoing:(ExteriaOutgoing *)outgoing randomId:(long long)randomId date:(int32_t)date {
    ExteriaMessage *message = [ExteriaMessage pendingText:outgoing->caption ? outgoing->caption : @"" randomId:randomId date:date];
    exteria_media_info info;
    memset(&info, 0, sizeof(info));
    switch (outgoing->kind) {
    case ExteriaOutgoingVoice: info.kind = EXTERIA_PREVIEW_VOICE; break;
    case ExteriaOutgoingRound: info.kind = EXTERIA_PREVIEW_VIDEO_MESSAGE; break;
    case ExteriaOutgoingPhoto: info.kind = EXTERIA_PREVIEW_PHOTO; break;
    case ExteriaOutgoingVideo: info.kind = EXTERIA_PREVIEW_VIDEO; break;
    case ExteriaOutgoingFile: info.kind = EXTERIA_PREVIEW_FILE; break;
    case ExteriaOutgoingLocation:
        info.kind = EXTERIA_PREVIEW_LOCATION;
        info.location = outgoing->location;
        if (!info.location.valid && exteria_geo_valid(outgoing->latitude, outgoing->longitude)) {
            info.location.valid = 1;
            info.location.latitude = outgoing->latitude;
            info.location.longitude = outgoing->longitude;
        }
        break;
    case ExteriaOutgoingContact: info.kind = EXTERIA_PREVIEW_CONTACT; break;
    }
    if (outgoing->viewOnce && info.kind != EXTERIA_PREVIEW_FILE) info.ttl_seconds = EXTERIA_VIEW_ONCE_TTL;
    info.duration = (outgoing->durationMs + 500) / 1000;
    info.width = outgoing->width;
    info.height = outgoing->height;
    if (info.kind == EXTERIA_PREVIEW_LOCATION) { info.width = 320; info.height = 180; }
    if (outgoing->path) {
        info.size = (int64_t)[[[NSFileManager defaultManager] attributesOfItemAtPath:outgoing->path error:NULL] fileSize];
        snprintf(info.name, sizeof(info.name), "%s", outgoing->name.UTF8String);
    }
    [message->_media release];
    message->_media = [[ExteriaMedia mediaWithInfo:&info] retain];
    message->_pendingSend = [outgoing retain];
    return message;
}

- (void)dealloc {
    [_markup release];
    [_pendingSend release];
    [_replyQuote release];
    [_text release];
    [_forwardName release];
    [_senderRank release];
    [_commenters release];
    [_entities release];
    [_media release];
    [_giftTitle release];
    [_gift release];
    [_reactions release];
    [_poll release];
    [super dealloc];
}

@end

@implementation ExteriaSticker

@synthesize media = _media;

+ (ExteriaSticker *)stickerWithRow:(const exteria_sticker_row *)row {
    ExteriaSticker *sticker = [[[ExteriaSticker alloc] init] autorelease];
    sticker->_media = [[ExteriaMedia mediaWithInfo:&row->media] retain];
    return sticker;
}

- (void)dealloc {
    [_media release];
    [super dealloc];
}

@end

@implementation ExteriaStickerSet

@synthesize row = _row;
@synthesize title = _title;

+ (ExteriaStickerSet *)setWithRow:(const exteria_sticker_set_row *)row {
    ExteriaStickerSet *set = [[[ExteriaStickerSet alloc] init] autorelease];
    set->_row = *row;
    set->_title = [ExteriaUtf8(row->title) copy];
    return set;
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}

- (long long)setId { return _row.id; }
- (ExteriaRemoteFile *)coverFile { return [ExteriaRemoteFile fileForStickerSet:&_row]; }

@end
