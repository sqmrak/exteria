#import "exteria_chat_folder.h"
#import "exteria_message.h"
#include "exteria_tl_ids.h"

static const char *const rule_names[] = {"contacts", "non_contacts", "groups", "broadcasts", "bots", "exclude_muted", "exclude_read", "exclude_archived"};

static NSString *folder_string(const exteria_tl_value *value, const char *name, NSUInteger maximum) {
    const uint8_t *bytes = NULL;
    size_t length = 0;
    if (exteria_tl_get_bytes(value, name, &bytes, &length) != EXTERIA_OK || length > maximum)
        return nil;
    return [[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding] autorelease];
}

static NSData *folder_peers(const exteria_tl_value *value, const char *name, BOOL optional) {
    const exteria_tl_value *list = exteria_tl_get(value, name);
    if (!list && optional)
        return [NSData data];
    if (!list || list->kind != EXTERIA_TL_V_VEC || list->u.vec.count > EXTERIA_FOLDER_PEERS_MAX)
        return nil;
    NSMutableData *data = [NSMutableData data];
    for (uint32_t i = 0; i < list->u.vec.count; ++i) {
        const exteria_tl_value *input = list->u.vec.items[i];
        exteria_peer_ref peer;
        memset(&peer, 0, sizeof(peer));
        const char *id_name = NULL;
        if (exteria_tl_is(input, EXTERIA_TL_ID_inputPeerSelf))
            peer.self = 1;
        else if (exteria_tl_is(input, EXTERIA_TL_ID_inputPeerUser)) {
            peer.kind = 1;
            id_name = "user_id";
        } else if (exteria_tl_is(input, EXTERIA_TL_ID_inputPeerChat)) {
            peer.kind = 2;
            id_name = "chat_id";
        } else if (exteria_tl_is(input, EXTERIA_TL_ID_inputPeerChannel)) {
            peer.kind = 3;
            id_name = "channel_id";
        } else
            return nil;
        if (id_name && (exteria_tl_get_i64(input, id_name, &peer.id) != EXTERIA_OK || peer.id <= 0))
            return nil;
        if (peer.kind == 1 || peer.kind == 3) {
            if (exteria_tl_get_i64(input, "access_hash", &peer.access_hash) != EXTERIA_OK)
                return nil;
        }
        [data appendBytes:&peer length:sizeof(peer)];
    }
    return data;
}

@implementation ExteriaChatFolder
@synthesize folderId = _folderId, title = _title, flags = _flags, included = _included, excluded = _excluded, pinned = _pinned, shared = _shared,
            original = _original;
@synthesize titleEntities = _titleEntities;

- (void)setTitle:(NSString *)title {
    if (_title == title || [_title isEqualToString:title]) return;
    [_title release];
    _title = [title copy];
    [_titleEntities release];
    _titleEntities = nil;
}

- (id)init {
    self = [super init];
    if (self) {
        _included = [[NSData alloc] init];
        _excluded = [[NSData alloc] init];
        _pinned = [[NSData alloc] init];
    }
    return self;
}
- (void)dealloc {
    [_title release];
    [_titleEntities release];
    [_included release];
    [_excluded release];
    [_pinned release];
    [_original release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone {
    ExteriaChatFolder *copy = [[ExteriaChatFolder allocWithZone:zone] init];
    copy.folderId = _folderId;
    copy.title = _title;
    copy->_titleEntities = [_titleEntities retain];
    copy.flags = _flags;
    copy.included = _included;
    copy.excluded = _excluded;
    copy.pinned = _pinned;
    copy->_shared = _shared;
    copy->_original = [_original retain];
    return copy;
}

+ (ExteriaChatFolder *)folderWithValue:(const exteria_tl_value *)value {
    ExteriaChatFolder *folder = [[[self alloc] init] autorelease];
    if (exteria_tl_is(value, EXTERIA_TL_ID_dialogFilterDefault)) {
        folder.title = NSLocalizedString(@"folders.all", nil);
        return folder;
    }
    BOOL shared = exteria_tl_is(value, EXTERIA_TL_ID_dialogFilterChatlist);
    if (!shared && !exteria_tl_is(value, EXTERIA_TL_ID_dialogFilter))
        return nil;
    int32_t identifier = 0;
    if (exteria_tl_get_i32(value, "id", &identifier) != EXTERIA_OK || identifier < 2)
        return nil;
    NSString *title = folder_string(exteria_tl_get(value, "title"), "text", 512);
    NSData *included = folder_peers(value, "include_peers", NO);
    NSData *excluded = folder_peers(value, "exclude_peers", shared);
    NSData *pinned = folder_peers(value, "pinned_peers", NO);
    if (!title.length || !included || !excluded || !pinned)
        return nil;
    folder.folderId = identifier;
    folder.title = title;
    exteria_entity entities[EXTERIA_MESSAGE_ENTITIES_MAX];
    char urls[1] = {0};
    uint8_t count = 0;
    exteria_entities_read(exteria_tl_get(value, "title"), entities, EXTERIA_MESSAGE_ENTITIES_MAX, urls, sizeof(urls), &count);
    NSArray *runs = ExteriaTextEntities(title, entities, count, urls);
    NSMutableArray *custom = [NSMutableArray array];
    for (ExteriaTextEntity *entity in runs)
        if (entity.style == ExteriaTextStyleCustomEmoji && entity.documentId > 0) [custom addObject:entity];
    folder->_titleEntities = [custom copy];
    folder.included = included;
    folder.excluded = excluded;
    folder.pinned = pinned;
    folder->_shared = shared;
    for (NSUInteger i = 0; i < 8; ++i)
        if (exteria_tl_has(value, rule_names[i]))
            folder->_flags |= 1u << i;
    exteria_writer writer;
    exteria_writer_init(&writer, 256 * 1024);
    if (exteria_tl_encode(value, &writer, NULL) != EXTERIA_OK) {
        exteria_writer_free(&writer);
        return nil;
    }
    folder->_original = [[NSData alloc] initWithBytes:writer.data length:writer.len];
    exteria_writer_free(&writer);
    return folder;
}

static exteria_status build_peers(exteria_arena *arena, exteria_tl_value *filter, const char *name, NSData *data) {
    if (data.length % sizeof(exteria_peer_ref) || data.length / sizeof(exteria_peer_ref) > EXTERIA_FOLDER_PEERS_MAX)
        return EXTERIA_E_ARG;
    uint32_t count = (uint32_t)(data.length / sizeof(exteria_peer_ref));
    exteria_tl_value *list = exteria_tl_new_vec(arena, count);
    if (!list)
        return EXTERIA_E_NOMEM;
    const exteria_peer_ref *peers = data.bytes;
    for (uint32_t i = 0; i < count; ++i) {
        exteria_tl_value *peer = NULL;
        exteria_status status = exteria_input_peer(arena, &peers[i], &peer);
        if (status != EXTERIA_OK)
            return status;
        status = exteria_tl_vec_set(list, i, peer);
        if (status != EXTERIA_OK)
            return status;
    }
    return exteria_tl_set(filter, name, list);
}

- (exteria_status)buildInArena:(exteria_arena *)arena value:(exteria_tl_value **)value {
    *value = NULL;
    if (_folderId < 2 || !_title.length || _title.length > 12 || (_flags & ~255u))
        return EXTERIA_E_ARG;
    exteria_tl_value *filter = exteria_tl_new_obj(arena, _shared ? "dialogFilterChatlist" : "dialogFilter");
    exteria_tl_value *title = exteria_tl_new_obj(arena, "textWithEntities");
    if (!filter || !title)
        return EXTERIA_E_NOMEM;
    exteria_status status = exteria_tl_set_i32(arena, filter, "id", _folderId);
    exteria_tl_value *original = NULL;
    if (_original.length) {
        exteria_tl_limits limits = exteria_tl_default_limits;
        status = exteria_tl_decode_all(arena, &limits, EXTERIA_TL_REF_ANY, _original.bytes, _original.length, &original);
        if (status != EXTERIA_OK)
            return status;
    }
    /* names with custom emoji and the color survive an edit of the rules */
    if (original) {
        const char *fields[] = {"emoticon", "color", "title_noanimate", "has_my_invites"};
        for (NSUInteger i = 0; i < 4; ++i) {
            exteria_tl_value *field = (exteria_tl_value *)exteria_tl_get(original, fields[i]);
            if (field && status == EXTERIA_OK)
                status = exteria_tl_set(filter, fields[i], field);
        }
        if ([_title isEqualToString:folder_string(exteria_tl_get(original, "title"), "text", 512)])
            title = (exteria_tl_value *)exteria_tl_get(original, "title");
    }
    if (!original || title != exteria_tl_get(original, "title")) {
        if (status == EXTERIA_OK)
            status = exteria_tl_set_str(arena, title, "text", _title.UTF8String);
        exteria_tl_value *empty = exteria_tl_new_vec(arena, 0);
        if (status == EXTERIA_OK)
            status = empty ? exteria_tl_set(title, "entities", empty) : EXTERIA_E_NOMEM;
    }
    if (status == EXTERIA_OK)
        status = exteria_tl_set(filter, "title", title);
    if (!_shared)
        for (NSUInteger i = 0; i < 8; ++i)
            if ((_flags & (1u << i)) && status == EXTERIA_OK)
                status = exteria_tl_set_flag(filter, rule_names[i]);
    if (status == EXTERIA_OK)
        status = build_peers(arena, filter, "include_peers", _included);
    if (status == EXTERIA_OK && !_shared)
        status = build_peers(arena, filter, "exclude_peers", _excluded);
    if (status == EXTERIA_OK)
        status = build_peers(arena, filter, "pinned_peers", _pinned);
    if (status == EXTERIA_OK)
        *value = filter;
    return status;
}

- (exteria_folder_rules)rules {
    exteria_folder_rules rules = {_flags,
                                  _included.bytes,
                                  _included.length / sizeof(exteria_peer_ref),
                                  _excluded.bytes,
                                  _excluded.length / sizeof(exteria_peer_ref),
                                  _pinned.bytes,
                                  _pinned.length / sizeof(exteria_peer_ref)};
    return rules;
}
static exteria_dialog_row folder_dialog(ExteriaDialog *dialog) {
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = dialog.peerKind;
    row.peer_id = dialog.peerId;
    row.kind = dialog.kind;
    row.saved = dialog.saved;
    row.contact = dialog.contact;
    row.folder = dialog.folder;
    row.folder_id = dialog.folderId;
    row.muted = dialog.muted;
    row.unread_count = (int32_t)MIN(INT32_MAX, dialog.unreadCount);
    row.unread_mark = dialog.unread;
    row.mentions = (int32_t)MIN(INT32_MAX, dialog.mentions);
    row.reactions = (int32_t)MIN(INT32_MAX, dialog.reactions);
    row.community = dialog.community;
    return row;
}
- (ExteriaDialog *)dialogWithRow:(const exteria_dialog_row *)source {
    exteria_dialog_row row = *source;
    exteria_folder_rules rules = [self rules];
    if (_folderId)
        row.pinned = exteria_folder_pin_index(&rules, &row) != SIZE_MAX;
    return [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
}

- (BOOL)containsDialog:(ExteriaDialog *)dialog {
    if (!_folderId)
        return dialog.folderId == 0;
    exteria_folder_rules rules = [self rules];
    exteria_dialog_row row = folder_dialog(dialog);
    return exteria_folder_contains(&rules, &row) != 0;
}
- (NSUInteger)pinIndexForDialog:(ExteriaDialog *)dialog {
    exteria_folder_rules rules = [self rules];
    exteria_dialog_row row = folder_dialog(dialog);
    return exteria_folder_pin_index(&rules, &row);
}
@end
