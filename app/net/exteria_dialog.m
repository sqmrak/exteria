#import "exteria_dialog.h"
#import "exteria_text_filter.h"
#import "exteria_service_line.h"

#import "exteria_person.h"
#import "exteria_photo.h"
#import "exteria_remote_file.h"

@implementation ExteriaDialog

@synthesize showsSender = _showsSender;
@synthesize savedSource = _savedSource;
@synthesize linkedCommunityId = _linkedCommunityId;
@synthesize senderId = _senderId;
@synthesize senderInitials = _senderInitials;
@synthesize senderPhoto = _senderPhoto;
@synthesize peerKind = _peerKind;
@synthesize peerId = _peerId;
@synthesize kind = _kind;
@synthesize saved = _saved;
@synthesize contact = _contact;
@synthesize folder = _folder;
@synthesize forum = _forum;
@synthesize community = _community;
@synthesize communityCollapsed = _communityCollapsed;
@synthesize left = _left;
@synthesize topicId = _topicId;
@synthesize discussion = _discussion;
@synthesize topicIconEmoji = _topicIconEmoji;
@synthesize topicIconColor = _topicIconColor;
@synthesize topicClosed = _topicClosed;
@synthesize folderId = _folderId;
@synthesize peerHash = _peerHash;
@synthesize verified = _verified;
@synthesize premium = _premium;
@synthesize emojiStatus = _emojiStatus;
@synthesize pinned = _pinned;
@synthesize muted = _muted;
@synthesize canPost = _canPost;
@synthesize outgoing = _outgoing;
@synthesize forwarded = _forwarded;
@synthesize read = _read;
@synthesize date = _date;
@synthesize readInboxMaxId = _readInboxMaxId;
@synthesize readOutboxMaxId = _readOutboxMaxId;
@synthesize presence = _presence;
@synthesize seen = _seen;
@synthesize unreadCount = _unreadCount;
@synthesize mentions = _mentions;
@synthesize participantsCount = _participantsCount;
@synthesize title = _title;
@synthesize preview = _preview;
@synthesize previewFile = _previewFile;
@synthesize initials = _initials;
@synthesize photo = _photo;

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *ExteriaUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

static NSString *ExteriaPreviewLabel(exteria_preview_kind kind, NSString *text) {
    switch (kind) {
    case EXTERIA_PREVIEW_NONE: return @"";
    case EXTERIA_PREVIEW_TEXT: return text;
    case EXTERIA_PREVIEW_PHOTO: return NSLocalizedString(@"preview.photo", nil);
    case EXTERIA_PREVIEW_VIDEO: return NSLocalizedString(@"preview.video", nil);
    case EXTERIA_PREVIEW_VIDEO_MESSAGE: return NSLocalizedString(@"preview.videomessage", nil);
    case EXTERIA_PREVIEW_VOICE: return NSLocalizedString(@"preview.voice", nil);
    case EXTERIA_PREVIEW_AUDIO: return NSLocalizedString(@"preview.audio", nil);
    case EXTERIA_PREVIEW_STICKER:
        return text.length ? [text stringByAppendingFormat:@" %@", NSLocalizedString(@"preview.sticker", nil)]
                           : NSLocalizedString(@"preview.sticker", nil);
    case EXTERIA_PREVIEW_GIF: return NSLocalizedString(@"preview.gif", nil);
    case EXTERIA_PREVIEW_FILE: return text.length ? text : NSLocalizedString(@"preview.file", nil);
    case EXTERIA_PREVIEW_LOCATION: return NSLocalizedString(@"preview.location", nil);
    case EXTERIA_PREVIEW_CONTACT: return NSLocalizedString(@"preview.contact", nil);
    case EXTERIA_PREVIEW_POLL: return NSLocalizedString(@"preview.poll", nil);
    case EXTERIA_PREVIEW_SERVICE: return NSLocalizedString(@"preview.service", nil);
    case EXTERIA_PREVIEW_OTHER: break;
    }
    return NSLocalizedString(@"preview.message", nil);
}

- (id)initWithRow:(const exteria_dialog_row *)row {
    self = [super init];
    if (!self) return nil;
    _peerKind = row->peer_kind;
    _peerId = row->peer_id;
    _kind = row->kind;
    _contact = row->contact;
    _saved = row->saved;
    _folder = row->folder;
    _forum = row->forum;
    _community = row->community;
    _communityCollapsed = row->community_collapsed;
    _linkedCommunityId = row->linked_community_id;
    _linkedCommunityHash = row->linked_community_hash;
    _linkedCommunityTitle = [[NSString stringWithUTF8String:row->linked_community_title] copy];
    _left = row->left;
    _topicId = row->topic_id;
    _topicIconEmoji = row->topic_icon_emoji;
    _topicIconColor = row->topic_icon_color;
    _topicClosed = row->topic_closed;
    _folderId = row->folder_id;
    _peerHash = row->peer_hash;
    _verified = row->verified;
    _premium = row->premium;
    _emojiStatus = ExteriaLiveEmojiStatus(row->emoji_status, row->emoji_status_until);
    _pinned = row->pinned;
    _muted = row->muted;
    _canPost = row->can_post;
    _outgoing = row->outgoing;
    _forwarded = row->forwarded;
    _read = row->read;
    _unreadMark = row->unread_mark;
    _photo = [[ExteriaPhoto photoWithRef:&row->photo] retain];
    _date = row->date;
    _readInboxMaxId = row->read_inbox_max_id;
    _readOutboxMaxId = row->read_outbox_max_id;
    _presence = row->presence;
    _seen = row->seen;
    _unreadCount = row->unread_count;
    _mentions = row->mentions;
    _participantsCount = row->participants_count;
    if (row->folder) _title = [NSLocalizedString(@"chats.archive", nil) copy];
    else if (row->saved) _title = [NSLocalizedString(@"chats.saved", nil) copy];
    else if (row->deleted || !row->title[0]) _title = [NSLocalizedString(@"chats.deleted", nil) copy];
    else _title = [ExteriaFilteredText(ExteriaUtf8(row->title)) copy];
    _initials = [(row->saved || row->deleted ? @"" : ExteriaInitialsOfName(_title)) copy];
    NSString *body = ExteriaPreviewLabel(row->preview, ExteriaFilteredText(ExteriaUtf8(row->text)));
    if (row->preview == EXTERIA_PREVIEW_SERVICE && row->service) {
        /* the name of whoever acted: the sender the list carries, "You" for our own line, the other side in a private chat, and the channel for a post */
        NSString *who = nil;
        if (row->sender[0]) who = ExteriaUtf8(row->sender);
        else if (row->sender_is_self) who = NSLocalizedString(@"media.you", nil);
        else if (row->kind == EXTERIA_DIALOG_USER || row->kind == EXTERIA_DIALOG_BOT || row->kind == EXTERIA_DIALOG_CHANNEL) who = ExteriaUtf8(row->title);
        body = ExteriaServiceLine((exteria_service_kind)(row->service - 1), who, nil, ExteriaUtf8(row->text), row->service_value, NO);
    }
    /* our own last message stands without a name before it; the name of another sender is kept in a group */
    if (row->preview != EXTERIA_PREVIEW_NONE && row->preview != EXTERIA_PREVIEW_SERVICE && row->sender[0] &&
        !(row->sender_is_self && row->kind != EXTERIA_DIALOG_CHANNEL && !row->saved)) {
        body = [NSString stringWithFormat:@"%@: %@", ExteriaUtf8(row->sender), body];
        _showsSender = YES;
        _senderId = row->sender_id;
        _senderInitials = [ExteriaInitialsOfName(ExteriaUtf8(row->sender)) copy];
        _senderPhoto = [[ExteriaPhoto photoWithRef:&row->sender_photo] retain];
    }
    _preview = [body copy];
    _previewFile = [[ExteriaRemoteFile fileForMedia:&row->thumb] retain];
    return self;
}

+ (ExteriaDialog *)dialogWithPerson:(ExteriaPerson *)person {
    if (!person.accessHash) return nil;
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = 1;
    row.peer_id = person.userId;
    row.peer_hash = person.accessHash;
    row.kind = person.bot ? EXTERIA_DIALOG_BOT : EXTERIA_DIALOG_USER;
    row.verified = person.verified;
    row.premium = person.premium;
    row.emoji_status = person.emojiStatus;
    row.presence = person.presence;
    row.seen = person.seen;
    row.deleted = person.deleted;
    if (person.photo) row.photo = person.photo.ref;
    snprintf(row.title, sizeof(row.title), "%s", person.name.UTF8String);
    ExteriaDialog *dialog = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
    return dialog;
}

+ (ExteriaDialog *)savedMessagesWithPerson:(ExteriaPerson *)person {
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = 1;
    row.peer_id = person.userId;
    row.peer_hash = person.accessHash;
    row.kind = EXTERIA_DIALOG_USER;
    row.saved = 1;
    ExteriaDialog *dialog = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
    /* the chat with oneself has no photo of its own; the lists draw the bookmark for it and never read the photo */
    [dialog->_photo release];
    dialog->_photo = [person.photo retain];
    [dialog->_initials release];
    dialog->_initials = [ExteriaInitialsOfName(person.name) copy];
    return dialog;
}

+ (ExteriaDialog *)savedMessagesOfUserId:(long long)userId {
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = 1;
    row.peer_id = userId;
    row.kind = EXTERIA_DIALOG_USER;
    row.saved = 1;
    return [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
}

- (ExteriaDialog *)linkedCommunity {
    if (!_linkedCommunityId || !_linkedCommunityHash) return nil;
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = 3;
    row.peer_id = _linkedCommunityId;
    row.peer_hash = _linkedCommunityHash;
    row.kind = EXTERIA_DIALOG_CHANNEL;
    row.community = 1;
    snprintf(row.title, sizeof(row.title), "%s", _linkedCommunityTitle.UTF8String);
    return [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
}

- (ExteriaDialog *)savedDialogFromSource:(ExteriaDialog *)source {
    if (!_saved || !source) return nil;
    ExteriaDialog *narrowed = [ExteriaDialog savedMessagesOfUserId:_peerId];
    narrowed->_peerHash = _peerHash;
    [narrowed->_photo release];
    narrowed->_photo = [_photo retain];
    [narrowed->_initials release];
    narrowed->_initials = [_initials copy];
    narrowed->_savedSource = [source retain];
    if (!source.saved) {
        [narrowed->_title release];
        narrowed->_title = [source.title copy];
    }
    return narrowed;
}

- (BOOL)deleted {
    return _presence == EXTERIA_PRESENCE_DELETED;
}

- (void)dealloc {
    [_linkedCommunityTitle release];
    [_savedSource release];
    [_title release];
    [_senderInitials release];
    [_senderPhoto release];
    [_preview release];
    [_previewFile release];
    [_initials release];
    [_photo release];
    [super dealloc];
}

- (NSUInteger)avatarSeed {
    return (NSUInteger)((_peerId + _topicId) % 1000003);
}

- (BOOL)unread {
    return _unreadCount > 0 || _unreadMark;
}

@end

NSArray *ExteriaDialogsReplacingArchive(NSArray *dialogs, ExteriaDialog *summary) {
    NSMutableArray *updated = [NSMutableArray arrayWithArray:dialogs];
    if (![summary isKindOfClass:[ExteriaDialog class]] || !summary.folder) return updated;
    for (NSUInteger i = 0; i < updated.count; ++i) {
        ExteriaDialog *dialog = [updated objectAtIndex:i];
        if (dialog.folder && dialog.folderId == summary.folderId) [updated replaceObjectAtIndex:i withObject:summary];
    }
    return updated;
}
