#include "exteria_invite.h"

#include <string.h>

#include "exteria_tl_ids.h"

static void copy_text(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK || !data) return;
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static exteria_status admin_self(exteria_arena *arena, exteria_tl_value **out) {
    *out = exteria_tl_new_obj(arena, "inputUserSelf");
    return *out ? EXTERIA_OK : EXTERIA_E_NOMEM;
}

static exteria_status link_valid(const char *link) {
    size_t len = link ? strlen(link) : 0;
    return len > 0 && len < EXTERIA_INVITE_LINK_MAX ? EXTERIA_OK : EXTERIA_E_ARG;
}

static exteria_status spec_valid(const exteria_invite_spec *spec) {
    if (!spec || spec->expire_date < 0 || spec->usage_limit < 0 || spec->usage_limit > EXTERIA_INVITE_LIMIT_MAX) return EXTERIA_E_ARG;
    /* a join that needs approval counts no uses, so the server refuses the two together */
    if (spec->request_needed && spec->usage_limit) return EXTERIA_E_ARG;
    return memchr(spec->title, 0, sizeof(spec->title)) ? EXTERIA_OK : EXTERIA_E_ARG;
}

static exteria_status peer_input(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **input) {
    *input = NULL;
    if (!arena || !peer) return EXTERIA_E_ARG;
    return exteria_input_peer(arena, peer, input);
}

exteria_status exteria_invite_list_request(exteria_arena *arena, const exteria_peer_ref *peer, int revoked, int32_t offset_date, const char *offset_link,
                                          exteria_tl_value **out) {
    exteria_tl_value *request, *input, *admin;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || offset_date < 0 || (offset_link && strlen(offset_link) >= EXTERIA_INVITE_LINK_MAX)) return EXTERIA_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status == EXTERIA_OK) status = admin_self(arena, &admin);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.getExportedChatInvites");
    if (!request) return EXTERIA_E_NOMEM;
    if (revoked) status = exteria_tl_set_flag(request, "revoked");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "admin_id", admin);
    if (status == EXTERIA_OK && offset_link && offset_link[0]) {
        /* the server pages by the date and the link of the last one it sent, and wants both */
        status = exteria_tl_set_i32(arena, request, "offset_date", offset_date);
        if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "offset_link", offset_link);
    }
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", EXTERIA_INVITES_PAGE);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static exteria_status invite_read(const exteria_tl_value *value, exteria_invite *row) {
    memset(row, 0, sizeof(*row));
    /* a chatInvitePublicJoinRequests entry says people wait to join; it is no link */
    if (!value || !exteria_tl_is(value, EXTERIA_TL_ID_chatInviteExported)) return EXTERIA_E_UNSUPPORTED;
    copy_text(row->link, sizeof(row->link), value, "link");
    if (!row->link[0]) return EXTERIA_E_MALFORMED;
    copy_text(row->title, sizeof(row->title), value, "title");
    row->revoked = exteria_tl_has(value, "revoked") ? 1 : 0;
    row->permanent = exteria_tl_has(value, "permanent") ? 1 : 0;
    row->request_needed = exteria_tl_has(value, "request_needed") ? 1 : 0;
    exteria_tl_get_i32(value, "date", &row->date);
    exteria_tl_get_i32(value, "start_date", &row->start_date);
    exteria_tl_get_i32(value, "expire_date", &row->expire_date);
    exteria_tl_get_i32(value, "usage_limit", &row->usage_limit);
    exteria_tl_get_i32(value, "usage", &row->usage);
    exteria_tl_get_i32(value, "requested", &row->requested);
    exteria_tl_get_i64(value, "admin_id", &row->admin_id);
    if (row->usage_limit < 0 || row->usage < 0 || row->requested < 0 || row->expire_date < 0) return EXTERIA_E_MALFORMED;
    return EXTERIA_OK;
}

exteria_status exteria_invite_list_parse(const exteria_tl_value *answer, exteria_invite *rows, size_t cap, size_t *count, int32_t *total) {
    const exteria_tl_value *list = NULL;
    size_t n = 0;
    uint32_t i;
    int32_t all = 0;
    if (count) *count = 0;
    if (total) *total = 0;
    if (!answer || !rows || !cap || !count || !total) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_exportedChatInvites) || exteria_tl_get_i32(answer, "count", &all) != EXTERIA_OK || all < 0 ||
        exteria_tl_get_vec(answer, "invites", &list) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (list->u.vec.count > cap) return EXTERIA_E_LIMIT;
    for (i = 0; i < list->u.vec.count; ++i) {
        exteria_status status = invite_read(list->u.vec.items[i], &rows[n]);
        if (status == EXTERIA_E_UNSUPPORTED) continue;
        if (status != EXTERIA_OK) {
            *count = 0;
            return status;
        }
        ++n;
    }
    *count = n;
    *total = all;
    return EXTERIA_OK;
}

static exteria_status spec_apply(exteria_arena *arena, exteria_tl_value *request, const exteria_invite_spec *spec, int edit) {
    exteria_status status = EXTERIA_OK;
    if (spec->expire_date > 0) status = exteria_tl_set_i32(arena, request, "expire_date", spec->expire_date);
    /* an edit that leaves a limit out would keep the old one, so zero is sent as zero there */
    if (status == EXTERIA_OK && (spec->usage_limit > 0 || edit)) status = exteria_tl_set_i32(arena, request, "usage_limit", spec->usage_limit);
    if (status == EXTERIA_OK && edit && spec->expire_date == 0) status = exteria_tl_set_i32(arena, request, "expire_date", 0);
    if (status == EXTERIA_OK && spec->title[0]) status = exteria_tl_set_str(arena, request, "title", spec->title);
    else if (status == EXTERIA_OK && edit) status = exteria_tl_set_str(arena, request, "title", "");
    return status;
}

exteria_status exteria_invite_create_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_invite_spec *spec, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || spec_valid(spec) != EXTERIA_OK) return EXTERIA_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.exportChatInvite");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK && spec->request_needed) status = exteria_tl_set_flag(request, "request_needed");
    if (status == EXTERIA_OK) status = spec_apply(arena, request, spec, 0);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_invite_edit_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *link, const exteria_invite_spec *spec,
                                          exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || link_valid(link) != EXTERIA_OK || spec_valid(spec) != EXTERIA_OK) return EXTERIA_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.editExportedChatInvite");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "link", link);
    if (status == EXTERIA_OK) {
        exteria_tl_value *needed = exteria_tl_new_obj(arena, spec->request_needed ? "boolTrue" : "boolFalse");
        status = needed ? exteria_tl_set(request, "request_needed", needed) : EXTERIA_E_NOMEM;
    }
    if (status == EXTERIA_OK) status = spec_apply(arena, request, spec, 1);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_invite_revoke_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *link, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || link_valid(link) != EXTERIA_OK) return EXTERIA_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.editExportedChatInvite");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_flag(request, "revoked");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "link", link);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_invite_delete_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *link, exteria_tl_value **out) {
    exteria_tl_value *request, *input;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || link_valid(link) != EXTERIA_OK) return EXTERIA_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.deleteExportedChatInvite");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "link", link);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_invite_delete_revoked_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *admin;
    exteria_status status;
    if (out) *out = NULL;
    if (!out) return EXTERIA_E_ARG;
    status = peer_input(arena, peer, &input);
    if (status == EXTERIA_OK) status = admin_self(arena, &admin);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "messages.deleteRevokedExportedChatInvites");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "admin_id", admin);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_invite_answer_parse(const exteria_tl_value *answer, exteria_invite *invite, exteria_invite *replacement, int *replaced) {
    exteria_status status;
    if (replaced) *replaced = 0;
    if (!answer || !invite) return EXTERIA_E_ARG;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_chatInviteExported)) return invite_read(answer, invite) == EXTERIA_OK ? EXTERIA_OK : EXTERIA_E_MALFORMED;
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_exportedChatInvite)) {
        status = invite_read(exteria_tl_get(answer, "invite"), invite);
        return status == EXTERIA_OK ? EXTERIA_OK : EXTERIA_E_MALFORMED;
    }
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_exportedChatInviteReplaced)) {
        exteria_invite spare;
        status = invite_read(exteria_tl_get(answer, "invite"), invite);
        if (status == EXTERIA_OK) status = invite_read(exteria_tl_get(answer, "new_invite"), replacement ? replacement : &spare);
        if (status != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        if (replaced) *replaced = 1;
        return EXTERIA_OK;
    }
    return EXTERIA_E_MALFORMED;
}
