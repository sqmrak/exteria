#include "exteria_call.h"

#include <string.h>

#include "exteria_crypto.h"
#include "exteria_mt_handshake.h"
#include "exteria_random.h"
#include "exteria_tl_ids.h"

#define KEY EXTERIA_CALL_KEY_LEN

exteria_status exteria_call_dh_request(exteria_arena *arena, int32_t version, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || version < 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "messages.getDhConfig");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i32(arena, request, "version", version);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "random_length", KEY);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_call_dh_parse(const exteria_tl_value *answer, const exteria_call_dh *known, exteria_call_dh *out, uint8_t random[KEY]) {
    const uint8_t *bytes;
    size_t len;
    int32_t g = 0, version = 0;
    if (!out || !random) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    memset(random, 0, KEY);
    if (exteria_tl_is(answer, EXTERIA_TL_ID_messages_dhConfigNotModified)) {
        if (!known || known->version <= 0 || known->g <= 0) return EXTERIA_E_STATE;
        if (exteria_tl_get_bytes(answer, "random", &bytes, &len) != EXTERIA_OK || len != KEY) return EXTERIA_E_MALFORMED;
        *out = *known;
        memcpy(random, bytes, KEY);
        return EXTERIA_OK;
    }
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_dhConfig)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_i32(answer, "g", &g) != EXTERIA_OK || exteria_tl_get_i32(answer, "version", &version) != EXTERIA_OK || version <= 0)
        return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_bytes(answer, "p", &bytes, &len) != EXTERIA_OK || len != KEY) return EXTERIA_E_SECURITY;
    /* the prime may come from the cache of an earlier call of the same version, which was checked then */
    if (!(known && known->version == version && known->g == g && memcmp(known->p, bytes, KEY) == 0) &&
        exteria_mt_check_dh_prime(bytes, len, (uint32_t)g) != EXTERIA_OK) return EXTERIA_E_SECURITY;
    memcpy(out->p, bytes, KEY);
    out->g = g;
    out->version = version;
    if (exteria_tl_get_bytes(answer, "random", &bytes, &len) != EXTERIA_OK || len != KEY) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    memcpy(random, bytes, KEY);
    return EXTERIA_OK;
}

exteria_status exteria_call_make_secret_from(const exteria_call_dh *dh, const uint8_t seed[KEY], const uint8_t server_random[KEY],
                                            uint8_t secret[KEY], uint8_t pub[KEY]) {
    exteria_bn *p = NULL, *g = NULL, *a = NULL, *value = NULL;
    exteria_status status = EXTERIA_E_NOMEM;
    size_t i;
    if (!dh || !seed || !server_random || !secret || !pub || dh->g <= 0) return EXTERIA_E_ARG;
    memset(pub, 0, KEY);
    for (i = 0; i < KEY; ++i) secret[i] = (uint8_t)(seed[i] ^ server_random[i]);
    p = exteria_bn_from_bin(dh->p, KEY);
    g = exteria_bn_from_u64((uint64_t)dh->g);
    a = exteria_bn_from_bin(secret, KEY);
    if (p && g && a) value = exteria_bn_mod_exp_secret(g, a, p);
    if (value) status = exteria_bn_to_bin_padded(value, pub, KEY);
    if (status == EXTERIA_OK) status = exteria_mt_check_dh_value(dh->p, KEY, pub, KEY) == EXTERIA_OK ? EXTERIA_OK : EXTERIA_E_SECURITY;
    exteria_bn_free(p);
    exteria_bn_free(g);
    exteria_bn_free(a);
    exteria_bn_free(value);
    if (status != EXTERIA_OK) {
        memset(secret, 0, KEY);
        memset(pub, 0, KEY);
    }
    return status;
}

exteria_status exteria_call_make_secret(const exteria_call_dh *dh, const uint8_t server_random[KEY], uint8_t secret[KEY], uint8_t pub[KEY]) {
    uint8_t seed[KEY];
    exteria_status status = exteria_random(seed, sizeof(seed));
    if (status != EXTERIA_OK) return status;
    status = exteria_call_make_secret_from(dh, seed, server_random, secret, pub);
    memset(seed, 0, sizeof(seed));
    return status;
}

exteria_status exteria_call_make_key(const exteria_call_dh *dh, const uint8_t other_pub[KEY], const uint8_t secret[KEY], uint8_t key[KEY],
                                    int64_t *fingerprint) {
    exteria_bn *p = NULL, *other = NULL, *a = NULL, *value = NULL;
    uint8_t digest[EXTERIA_SHA1_LEN];
    exteria_status status = EXTERIA_E_NOMEM;
    int i;
    uint64_t id = 0;
    if (!dh || !other_pub || !secret || !key || !fingerprint) return EXTERIA_E_ARG;
    memset(key, 0, KEY);
    *fingerprint = 0;
    if (exteria_mt_check_dh_value(dh->p, KEY, other_pub, KEY) != EXTERIA_OK) return EXTERIA_E_SECURITY;
    p = exteria_bn_from_bin(dh->p, KEY);
    other = exteria_bn_from_bin(other_pub, KEY);
    a = exteria_bn_from_bin(secret, KEY);
    if (p && other && a) value = exteria_bn_mod_exp_secret(other, a, p);
    if (value) status = exteria_bn_to_bin_padded(value, key, KEY);
    exteria_bn_free(p);
    exteria_bn_free(other);
    exteria_bn_free(a);
    exteria_bn_free(value);
    if (status == EXTERIA_OK) status = exteria_sha1_one(key, KEY, digest);
    if (status != EXTERIA_OK) {
        memset(key, 0, KEY);
        return status;
    }
    for (i = 7; i >= 0; --i) id = (id << 8) | digest[EXTERIA_SHA1_LEN - 8 + i];
    *fingerprint = (int64_t)id;
    return EXTERIA_OK;
}

exteria_status exteria_call_commit(const uint8_t pub[KEY], uint8_t hash[32]) {
    if (!pub || !hash) return EXTERIA_E_ARG;
    return exteria_sha256_one(pub, KEY, hash);
}

exteria_status exteria_call_emoji_indexes(const uint8_t key[KEY], const uint8_t caller_pub[KEY], uint16_t indexes[EXTERIA_CALL_EMOJI_SHOWN]) {
    uint8_t joined[2 * KEY], digest[32];
    exteria_status status;
    int i, j;
    if (!key || !caller_pub || !indexes) return EXTERIA_E_ARG;
    memcpy(joined, key, KEY);
    memcpy(joined + KEY, caller_pub, KEY);
    status = exteria_sha256_one(joined, sizeof(joined), digest);
    memset(joined, 0, sizeof(joined));
    if (status != EXTERIA_OK) return status;
    for (i = 0; i < EXTERIA_CALL_EMOJI_SHOWN; ++i) {
        /* eight bytes, big endian, with the top bit dropped so the number stays positive, as every other client reads them */
        uint64_t value = (uint64_t)(digest[8 * i] & 0x7F);
        for (j = 1; j < 8; ++j) value = (value << 8) | digest[8 * i + j];
        indexes[i] = (uint16_t)(value % EXTERIA_CALL_EMOJI_COUNT);
    }
    return EXTERIA_OK;
}

static exteria_status protocol(exteria_arena *arena, int p2p, exteria_tl_value **out) {
    static const char *const names[] = {EXTERIA_CALL_TGCALLS_VERSION, EXTERIA_CALL_LIBRARY_VERSION};
    exteria_tl_value *p = exteria_tl_new_obj(arena, "phoneCallProtocol"), *versions = exteria_tl_new_vec(arena, 2);
    exteria_status status = EXTERIA_OK;
    uint32_t i;
    if (!p || !versions) return EXTERIA_E_NOMEM;
    for (i = 0; i < 2 && status == EXTERIA_OK; ++i) {
        exteria_tl_value *version = exteria_tl_new_str(arena, names[i]);
        if (!version) return EXTERIA_E_NOMEM;
        status = exteria_tl_vec_set(versions, i, version);
    }
    if (status == EXTERIA_OK && p2p) status = exteria_tl_set_flag(p, "udp_p2p");
    if (status == EXTERIA_OK) status = exteria_tl_set_flag(p, "udp_reflector");
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, p, "min_layer", EXTERIA_CALL_MIN_LAYER);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, p, "max_layer", EXTERIA_CALL_MAX_LAYER);
    if (status == EXTERIA_OK) status = exteria_tl_set(p, "library_versions", versions);
    if (status == EXTERIA_OK) *out = p;
    return status;
}

static exteria_status input_call(exteria_arena *arena, int64_t id, int64_t access_hash, exteria_tl_value **out) {
    exteria_tl_value *input = exteria_tl_new_obj(arena, "inputPhoneCall");
    exteria_status status;
    if (!input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "id", id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", access_hash);
    if (status == EXTERIA_OK) *out = input;
    return status;
}

exteria_status exteria_call_request_request(exteria_arena *arena, const exteria_peer_ref *user, int32_t random_id, const uint8_t hash[32], int video, int p2p,
                                           exteria_tl_value **out) {
    exteria_tl_value *request, *input, *proto = NULL;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !user || !hash || user->kind != 1 || user->id <= 0 || user->access_hash == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "phone.requestCall");
    input = exteria_tl_new_obj(arena, "inputUser");
    if (!request || !input) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, input, "user_id", user->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, input, "access_hash", user->access_hash);
    if (status == EXTERIA_OK) status = protocol(arena, p2p, &proto);
    if (status == EXTERIA_OK && video) status = exteria_tl_set_flag(request, "video");
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "user_id", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "random_id", random_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, request, "g_a_hash", hash, 32);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "protocol", proto);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_call_accept_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t pub[KEY], int p2p, exteria_tl_value **out) {
    exteria_tl_value *request, *peer = NULL, *proto = NULL;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !pub || call_id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "phone.acceptCall");
    if (!request) return EXTERIA_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == EXTERIA_OK) status = protocol(arena, p2p, &proto);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, request, "g_b", pub, KEY);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "protocol", proto);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_call_confirm_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t pub[KEY], int64_t fingerprint, int p2p,
                                           exteria_tl_value **out) {
    exteria_tl_value *request, *peer = NULL, *proto = NULL;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !pub || call_id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "phone.confirmCall");
    if (!request) return EXTERIA_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == EXTERIA_OK) status = protocol(arena, p2p, &proto);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, request, "g_a", pub, KEY);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "key_fingerprint", fingerprint);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "protocol", proto);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_call_signaling_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, const uint8_t *data, size_t len, exteria_tl_value **out) {
    exteria_tl_value *request, *peer = NULL;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || !data || call_id == 0) return EXTERIA_E_ARG;
    if (len == 0 || len > 16384) return EXTERIA_E_LIMIT;
    request = exteria_tl_new_obj(arena, "phone.sendSignalingData");
    if (!request) return EXTERIA_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_bytes(arena, request, "data", data, len);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_call_received_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, exteria_tl_value **out) {
    exteria_tl_value *request, *peer = NULL;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || call_id == 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "phone.receivedCall");
    if (!request) return EXTERIA_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_call_discard_request(exteria_arena *arena, int64_t call_id, int64_t access_hash, int32_t duration, exteria_call_reason reason,
                                           int64_t connection_id, exteria_tl_value **out) {
    static const char *const names[] = {NULL, "phoneCallDiscardReasonMissed", "phoneCallDiscardReasonDisconnect", "phoneCallDiscardReasonHangup",
                                        "phoneCallDiscardReasonBusy"};
    exteria_tl_value *request, *peer = NULL, *why;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!arena || call_id == 0 || duration < 0 || reason <= EXTERIA_CALL_REASON_NONE || reason > EXTERIA_CALL_REASON_BUSY) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "phone.discardCall");
    why = exteria_tl_new_obj(arena, names[reason]);
    if (!request || !why) return EXTERIA_E_NOMEM;
    status = input_call(arena, call_id, access_hash, &peer);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", peer);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "duration", duration);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "reason", why);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, request, "connection_id", connection_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

static void copy_string(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK || !data || len >= cap) return;
    memcpy(dst, data, len);
    dst[len] = 0;
}

static void read_protocol(const exteria_tl_value *call, exteria_phone_call *out) {
    const exteria_tl_value *proto = exteria_tl_get(call, "protocol"), *versions;
    if (!exteria_tl_is(proto, EXTERIA_TL_ID_phoneCallProtocol)) return;
    exteria_tl_get_i32(proto, "min_layer", &out->min_layer);
    exteria_tl_get_i32(proto, "max_layer", &out->max_layer);
    versions = exteria_tl_get(proto, "library_versions");
    if (versions && versions->kind == EXTERIA_TL_V_VEC && versions->u.vec.count > 0) {
        const exteria_tl_value *first = versions->u.vec.items[0];
        if (first && first->kind == EXTERIA_TL_V_BYTES && first->u.bytes.len < sizeof(out->version)) {
            memcpy(out->version, first->u.bytes.data, first->u.bytes.len);
            out->version[first->u.bytes.len] = 0;
        }
    }
}

static void read_connections(const exteria_tl_value *call, exteria_phone_call *out) {
    const exteria_tl_value *list = exteria_tl_get(call, "connections");
    uint32_t i;
    for (i = 0; list && list->kind == EXTERIA_TL_V_VEC && i < list->u.vec.count && out->connection_count < EXTERIA_CALL_CONNECTIONS_MAX; ++i) {
        const exteria_tl_value *item = list->u.vec.items[i];
        exteria_call_connection *c = &out->connections[out->connection_count];
        const uint8_t *tag;
        size_t tag_len;
        int32_t port = 0;
        if (!exteria_tl_is(item, EXTERIA_TL_ID_phoneConnection)) continue;
        memset(c, 0, sizeof(*c));
        if (exteria_tl_get_bytes(item, "peer_tag", &tag, &tag_len) != EXTERIA_OK || tag_len != EXTERIA_CALL_TAG_LEN) continue;
        if (exteria_tl_get_i32(item, "port", &port) != EXTERIA_OK || port <= 0 || port > 65535) continue;
        exteria_tl_get_i64(item, "id", &c->id);
        c->tcp = exteria_tl_has(item, "tcp") ? 1 : 0;
        c->port = (uint16_t)port;
        copy_string(c->ip, sizeof(c->ip), item, "ip");
        copy_string(c->ipv6, sizeof(c->ipv6), item, "ipv6");
        if (!c->ip[0] && !c->ipv6[0]) continue;
        memcpy(c->peer_tag, tag, EXTERIA_CALL_TAG_LEN);
        ++out->connection_count;
    }
}

static void read_turns(const exteria_tl_value *call, exteria_phone_call *out) {
    const exteria_tl_value *list = exteria_tl_get(call, "connections");
    uint32_t i;
    for (i = 0; list && list->kind == EXTERIA_TL_V_VEC && i < list->u.vec.count && out->turn_count < EXTERIA_CALL_TURNS_MAX; ++i) {
        const exteria_tl_value *item = list->u.vec.items[i];
        exteria_call_turn *t = &out->turns[out->turn_count];
        int32_t port = 0;
        if (!exteria_tl_is(item, EXTERIA_TL_ID_phoneConnectionWebrtc) || !exteria_tl_has(item, "turn")) continue;
        memset(t, 0, sizeof(*t));
        if (exteria_tl_get_i32(item, "port", &port) != EXTERIA_OK || port <= 0 || port > 65535) continue;
        exteria_tl_get_i64(item, "id", &t->id);
        t->port = (uint16_t)port;
        copy_string(t->ip, sizeof(t->ip), item, "ip");
        copy_string(t->username, sizeof(t->username), item, "username");
        copy_string(t->password, sizeof(t->password), item, "password");
        if (!t->ip[0] || !t->username[0]) continue;
        ++out->turn_count;
    }
}

static void read_g(const exteria_tl_value *call, const char *field, exteria_phone_call *out) {
    const uint8_t *data;
    size_t len;
    if (exteria_tl_get_bytes(call, field, &data, &len) != EXTERIA_OK || len != KEY) return;
    memcpy(out->g, data, KEY);
    out->has_g = 1;
}

exteria_status exteria_phone_call_parse(const exteria_tl_value *call, exteria_phone_call *out) {
    const exteria_tl_value *reason;
    const uint8_t *data;
    size_t len;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!call) return EXTERIA_E_MALFORMED;
    if (exteria_tl_is(call, EXTERIA_TL_ID_phoneCallEmpty)) {
        out->kind = EXTERIA_CALL_EMPTY;
        return exteria_tl_get_i64(call, "id", &out->id) == EXTERIA_OK ? EXTERIA_OK : EXTERIA_E_MALFORMED;
    }
    if (exteria_tl_is(call, EXTERIA_TL_ID_phoneCallDiscarded)) {
        out->kind = EXTERIA_CALL_DISCARDED;
        if (exteria_tl_get_i64(call, "id", &out->id) != EXTERIA_OK) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        exteria_tl_get_i32(call, "duration", &out->duration);
        out->need_rating = exteria_tl_has(call, "need_rating") ? 1 : 0;
        out->video = exteria_tl_has(call, "video") ? 1 : 0;
        reason = exteria_tl_get(call, "reason");
        if (exteria_tl_is(reason, EXTERIA_TL_ID_phoneCallDiscardReasonMissed)) out->reason = EXTERIA_CALL_REASON_MISSED;
        else if (exteria_tl_is(reason, EXTERIA_TL_ID_phoneCallDiscardReasonDisconnect)) out->reason = EXTERIA_CALL_REASON_DISCONNECT;
        else if (exteria_tl_is(reason, EXTERIA_TL_ID_phoneCallDiscardReasonHangup)) out->reason = EXTERIA_CALL_REASON_HANGUP;
        else if (exteria_tl_is(reason, EXTERIA_TL_ID_phoneCallDiscardReasonBusy)) out->reason = EXTERIA_CALL_REASON_BUSY;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(call, EXTERIA_TL_ID_phoneCallWaiting)) out->kind = EXTERIA_CALL_WAITING;
    else if (exteria_tl_is(call, EXTERIA_TL_ID_phoneCallRequested)) out->kind = EXTERIA_CALL_REQUESTED;
    else if (exteria_tl_is(call, EXTERIA_TL_ID_phoneCallAccepted)) out->kind = EXTERIA_CALL_ACCEPTED;
    else if (exteria_tl_is(call, EXTERIA_TL_ID_phoneCall)) out->kind = EXTERIA_CALL_ACTIVE;
    else return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_i64(call, "id", &out->id) != EXTERIA_OK || out->id == 0 || exteria_tl_get_i64(call, "access_hash", &out->access_hash) != EXTERIA_OK ||
        exteria_tl_get_i32(call, "date", &out->date) != EXTERIA_OK || exteria_tl_get_i64(call, "admin_id", &out->admin_id) != EXTERIA_OK ||
        exteria_tl_get_i64(call, "participant_id", &out->participant_id) != EXTERIA_OK) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    out->video = exteria_tl_has(call, "video") ? 1 : 0;
    out->p2p_allowed = exteria_tl_has(call, "p2p_allowed") ? 1 : 0;
    read_protocol(call, out);
    if (out->kind == EXTERIA_CALL_WAITING) {
        exteria_tl_get_i32(call, "receive_date", &out->receive_date);
    } else if (out->kind == EXTERIA_CALL_REQUESTED) {
        if (exteria_tl_get_bytes(call, "g_a_hash", &data, &len) != EXTERIA_OK || len != 32) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        memcpy(out->g_hash, data, 32);
        out->has_hash = 1;
    } else if (out->kind == EXTERIA_CALL_ACCEPTED) {
        read_g(call, "g_b", out);
    } else {
        read_g(call, "g_a_or_b", out);
        exteria_tl_get_i64(call, "key_fingerprint", &out->key_fingerprint);
        read_connections(call, out);
        read_turns(call, out);
    }
    return EXTERIA_OK;
}

exteria_status exteria_phone_call_from_answer(const exteria_tl_value *answer, exteria_phone_call *out) {
    if (!out) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_phone_phoneCall)) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    return exteria_phone_call_parse(exteria_tl_get(answer, "phone_call"), out);
}
