#include "test_util.h"
#include "exteria_messages.h"
#include "exteria_reaction_layout.h"
#include "exteria_updates.h"
#include "exteria_tl_ids.h"

#include <math.h>
#include <unistd.h>

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set(exteria_tl_value *v, const char *field, exteria_tl_value *x) {
    CHECK_EQ_INT(exteria_tl_set(v, field, x), EXTERIA_OK);
}
static void i32(exteria_tl_value *v, const char *field, int32_t x) {
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, field, x), EXTERIA_OK);
}
static void i64(exteria_tl_value *v, const char *field, int64_t x) {
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, field, x), EXTERIA_OK);
}
static void str(exteria_tl_value *v, const char *field, const char *x) {
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, field, x), EXTERIA_OK);
}
static void flag(exteria_tl_value *v, const char *field) {
    CHECK_EQ_INT(exteria_tl_set_flag(v, field), EXTERIA_OK);
}
static exteria_tl_value *emoji(const char *text) {
    exteria_tl_value *v = obj("reactionEmoji");
    str(v, "emoticon", text);
    return v;
}
static exteria_tl_value *result(exteria_tl_value *reaction, int32_t count, int chosen) {
    exteria_tl_value *v = obj("reactionCount");
    set(v, "reaction", reaction);
    i32(v, "count", count);
    if (chosen) i32(v, "chosen_order", 0);
    return v;
}
static exteria_tl_value *reactions(exteria_tl_value *r, int min) {
    exteria_tl_value *v = obj("messageReactions"), *vec = exteria_tl_new_vec(&arena, r ? 1 : 0);
    if (r) CHECK_EQ_INT(exteria_tl_vec_set(vec, 0, r), EXTERIA_OK);
    set(v, "results", vec);
    if (min) flag(v, "min");
    return v;
}
static exteria_tl_value *peer(const char *type, const char *field, int64_t id) {
    exteria_tl_value *v = obj(type);
    i64(v, field, id);
    return v;
}

static void test_parse(void) {
    exteria_reactions rows;
    exteria_message_row *message_row = calloc(1, sizeof(*message_row));
    exteria_tl_value *v, *r, *vec, *message;
    CHECK(message_row != NULL);
    CHECK_EQ_INT(exteria_reactions_read(NULL, &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.count, 0);
    CHECK_EQ_INT(exteria_reactions_read(obj("boolTrue"), &rows), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_reactions_read(NULL, NULL), EXTERIA_E_ARG);
    r = result(emoji("👍"), 2147483647, 1);
    v = reactions(r, 0);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.count, 1);
    CHECK_EQ_INT(rows.items[0].count, INT32_MAX);
    CHECK_EQ_INT(rows.items[0].chosen, 1);
    CHECK_EQ_INT(rows.items[0].chosen_order, 0);
    CHECK(!strcmp(rows.items[0].emoji, "👍"));
    message = obj("message");
    i32(message, "id", 8);
    i32(message, "date", 10);
    str(message, "message", "text");
    set(message, "reactions", v);
    CHECK_EQ_INT(exteria_message_read(message, message_row), EXTERIA_OK);
    CHECK(message_row->has_reactions && message_row->reactions_possible);
    CHECK_EQ_INT(message_row->reactions.items[0].count, INT32_MAX);
    i32(r, "count", -1);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(rows.count, 0);
    i32(r, "count", 0);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_E_MALFORMED);
    i32(r, "count", 1);
    i32(r, "chosen_order", -1);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_E_MALFORMED);
    i32(r, "chosen_order", 0);
    vec = exteria_tl_new_vec(&arena, 2);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 0, r), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 1, r), EXTERIA_OK);
    set(v, "results", vec);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_E_MALFORMED);
    set(v, "results", exteria_tl_new_vec(&arena, EXTERIA_REACTIONS_MAX + 1));
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_E_LIMIT);
    v = reactions(NULL, 0);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.count, 0);
    r = obj("reactionCustomEmoji");
    i64(r, "document_id", INT64_C(4294967305));
    v = reactions(result(r, 2, 0), 1);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.items[0].kind, EXTERIA_REACTION_CUSTOM);
    CHECK_EQ_INT(rows.items[0].document_id, INT64_C(4294967305));
    CHECK_EQ_INT(rows.min, 1);
    i64(r, "document_id", 0);
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_reactions_read(reactions(result(obj("reactionPaid"), 10, 0), 0), &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.items[0].kind, EXTERIA_REACTION_PAID);
    r = emoji("\xc0\x80");
    CHECK_EQ_INT(exteria_reactions_read(reactions(result(r, 1, 0), 0), &rows), EXTERIA_E_MALFORMED);
    str(r, "emoticon", "\xed\xa0\x80");
    CHECK_EQ_INT(exteria_reactions_read(reactions(result(r, 1, 0), 0), &rows), EXTERIA_E_MALFORMED);
    str(r, "emoticon", "a\n");
    CHECK_EQ_INT(exteria_reactions_read(reactions(result(r, 1, 0), 0), &rows), EXTERIA_E_MALFORMED);
    str(r, "emoticon", "");
    CHECK_EQ_INT(exteria_reactions_read(reactions(result(r, 1, 0), 0), &rows), EXTERIA_E_MALFORMED);
    str(r, "emoticon", "0123456789012345678901234567890123");
    CHECK_EQ_INT(exteria_reactions_read(reactions(result(r, 1, 0), 0), &rows), EXTERIA_E_MALFORMED);
    free(message_row);
}

static void roundtrip(exteria_tl_value *request, uint32_t constructor) {
    exteria_writer writer;
    exteria_tl_value *decoded = NULL;
    exteria_writer_init(&writer, 65536);
    CHECK_EQ_INT(exteria_tl_encode(request, &writer, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_decode_all(&arena, NULL, EXTERIA_TL_REF_ANY, writer.data, writer.len, &decoded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(decoded), constructor);
    exteria_writer_free(&writer);
}

static void test_requests(void) {
    exteria_peer_ref peers[] = {{1, 5, 7, 0, 0}, {2, 6, 0, 0, 0}, {3, 7, 9, 0, 0}, {1, 1, 0, 1, 0}};
    exteria_reaction choices[2];
    exteria_tl_value *request;
    int32_t ids[] = {1, 2, INT32_MAX};
    size_t i;
    memset(choices, 0, sizeof(choices));
    choices[0].kind = EXTERIA_REACTION_EMOJI;
    strcpy(choices[0].emoji, "❤️");
    choices[1].kind = EXTERIA_REACTION_CUSTOM;
    choices[1].document_id = INT64_C(4294967401);
    for (i = 0; i < sizeof(peers) / sizeof(peers[0]); ++i) {
        CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[i], 10, choices, 2, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_messages_sendReaction);
        CHECK_EQ_INT(exteria_tl_get(request, "reaction")->u.vec.count, 2);
        CHECK(exteria_tl_has(request, "add_to_recent"));
        CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[i], 10, NULL, 0, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_messages_sendReaction);
        CHECK_EQ_INT(exteria_tl_get(request, "reaction")->u.vec.count, 0);
        CHECK(!exteria_tl_has(request, "add_to_recent"));
        CHECK_EQ_INT(exteria_get_reactions_request(&arena, &peers[i], ids, 3, &request), EXTERIA_OK);
        roundtrip(request, EXTERIA_TL_ID_messages_getMessagesReactions);
    }
    CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[0], 0, choices, 1, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[0], 1, NULL, 1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[0], 1, choices, EXTERIA_REACTIONS_MAX + 1, &request), EXTERIA_E_ARG);
    choices[1] = choices[0];
    CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[0], 1, choices, 2, &request), EXTERIA_E_ARG);
    memset(choices[0].emoji, 'x', sizeof(choices[0].emoji));
    CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[0], 1, choices, 1, &request), EXTERIA_E_ARG);
    choices[0].kind = EXTERIA_REACTION_PAID;
    CHECK_EQ_INT(exteria_send_reactions_request(&arena, &peers[0], 1, choices, 1, &request), EXTERIA_E_ARG);
    ids[1] = -1;
    CHECK_EQ_INT(exteria_get_reactions_request(&arena, &peers[0], ids, 3, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_get_reactions_request(&arena, &peers[0], ids, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_get_reactions_request(&arena, &peers[0], ids, EXTERIA_MESSAGES_MAX + 1, &request), EXTERIA_E_ARG);
    peers[0].access_hash = 0;
    CHECK_EQ_INT(exteria_get_reactions_request(&arena, &peers[0], ids, 1, &request), EXTERIA_E_ARG);
}

static void test_catalog_policy(void) {
    exteria_tl_value *v = obj("messages.availableReactions"), *vec = exteria_tl_new_vec(&arena, 3), *r;
    exteria_reaction items[4];
    exteria_reactions allowed;
    size_t count = 99;
    int all = 99;
    unsigned i;
    for (i = 0; i < 3; ++i) {
        r = obj("availableReaction");
        str(r, "reaction", i == 0 ? "👍" : "👎");
        if (i == 1) flag(r, "inactive");
        if (i == 2) flag(r, "premium");
        CHECK_EQ_INT(exteria_tl_vec_set(vec, i, r), EXTERIA_OK);
    }
    set(v, "reactions", vec);
    CHECK_EQ_INT(exteria_reaction_catalog_read(v, items, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK(!strcmp(items[0].emoji, "👍"));
    set(v, "reactions", exteria_tl_new_vec(&arena, EXTERIA_REACTION_CATALOG_MAX + 1));
    CHECK_EQ_INT(exteria_reaction_catalog_read(v, items, 4, &count), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_reaction_catalog_read(obj("boolTrue"), items, 4, &count), EXTERIA_E_MALFORMED);
    v = obj("messages.chatFull");
    r = obj("channelFull");
    set(v, "full_chat", r);
    CHECK_EQ_INT(exteria_reaction_policy_read(v, &allowed, &all), EXTERIA_OK);
    CHECK_EQ_INT(all, 0);
    CHECK_EQ_INT(allowed.count, 0);
    set(r, "available_reactions", obj("chatReactionsAll"));
    CHECK_EQ_INT(exteria_reaction_policy_read(v, &allowed, &all), EXTERIA_OK);
    CHECK_EQ_INT(all, 1);
    set(r, "available_reactions", obj("chatReactionsNone"));
    CHECK_EQ_INT(exteria_reaction_policy_read(v, &allowed, &all), EXTERIA_OK);
    CHECK_EQ_INT(all, 0);
    vec = exteria_tl_new_vec(&arena, 1);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 0, emoji("❤️")), EXTERIA_OK);
    r = obj("chatReactionsSome");
    set(r, "reactions", vec);
    set((exteria_tl_value *)exteria_tl_get(v, "full_chat"), "available_reactions", r);
    CHECK_EQ_INT(exteria_reaction_policy_read(v, &allowed, &all), EXTERIA_OK);
    CHECK_EQ_INT(allowed.count, 1);
    CHECK(!strcmp(allowed.items[0].emoji, "❤️"));
}

static void test_custom_reactions(void) {
    exteria_tl_value *request = NULL, *vec, *full, *chat, *custom, *answer;
    exteria_reaction items[4];
    size_t count = 9;
    CHECK_EQ_INT(exteria_reaction_list_request(&arena, 0, 20, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getTopReactions);
    CHECK_EQ_INT(exteria_reaction_list_request(&arena, 1, 20, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_id(request), EXTERIA_TL_ID_messages_getRecentReactions);
    CHECK_EQ_INT(exteria_reaction_list_request(&arena, 1, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_list_request(&arena, 1, 101, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_list_request(&arena, 1, 20, NULL), EXTERIA_E_ARG);

    /* the list keeps the custom emoji only, in order, and skips one without a document */
    vec = exteria_tl_new_vec(&arena, 4);
    custom = obj("reactionCustomEmoji");
    i64(custom, "document_id", 77);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 0, emoji("\xE2\x9D\xA4")), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 1, custom), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 2, obj("reactionCustomEmoji")), EXTERIA_OK);
    custom = obj("reactionCustomEmoji");
    i64(custom, "document_id", 78);
    CHECK_EQ_INT(exteria_tl_vec_set(vec, 3, custom), EXTERIA_OK);
    answer = obj("messages.reactions");
    i64(answer, "hash", 1);
    set(answer, "reactions", vec);
    CHECK_EQ_INT(exteria_reaction_list_read(answer, items, 4, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 2);
    CHECK_EQ_INT(items[0].kind, EXTERIA_REACTION_CUSTOM);
    CHECK_EQ_INT(items[0].document_id, 77);
    CHECK_EQ_INT(items[1].document_id, 78);
    CHECK_EQ_INT(exteria_reaction_list_read(answer, items, 1, &count), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(exteria_reaction_list_read(obj("messages.reactionsNotModified"), items, 4, &count), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_reaction_list_read(obj("boolTrue"), items, 4, &count), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_reaction_list_read(answer, items, 0, &count), EXTERIA_E_ARG);

    /* everyone may use custom emoji only when the chat says so */
    full = obj("messages.chatFull");
    chat = obj("channelFull");
    set(full, "full_chat", chat);
    CHECK_EQ_INT(exteria_reaction_policy_custom(full), 0);
    set(chat, "available_reactions", obj("chatReactionsAll"));
    CHECK_EQ_INT(exteria_reaction_policy_custom(full), 0);
    custom = obj("chatReactionsAll");
    flag(custom, "allow_custom");
    set(chat, "available_reactions", custom);
    CHECK_EQ_INT(exteria_reaction_policy_custom(full), 1);
    set(chat, "available_reactions", obj("chatReactionsNone"));
    CHECK_EQ_INT(exteria_reaction_policy_custom(full), 0);
    CHECK_EQ_INT(exteria_reaction_policy_custom(obj("boolTrue")), 0);
}

static void test_store(void) {
    exteria_store *store = NULL;
    exteria_updates updates;
    exteria_tl_value *m, *update, *wrapper, *got, *r, *state;
    exteria_reactions parsed;
    exteria_arena read;
    exteria_peer channel = {3, INT64_C(4294967309)}, other = {3, 99};
    char path[] = "/tmp/exteria-reactions-XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    exteria_arena_init(&read, 16u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_store_open(&store, path, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_updates_init(&updates, store, 1), EXTERIA_OK);
    state = obj("updates.state");
    i32(state, "pts", 0); i32(state, "qts", 0); i32(state, "seq", 0); i32(state, "date", 10);
    CHECK_EQ_INT(exteria_updates_state(&updates, state), EXTERIA_OK);
    m = obj("message");
    i32(m, "id", 5); i32(m, "date", 10); str(m, "message", "keep this text");
    set(m, "peer_id", peer("peerChannel", "channel_id", channel.id));
    set(m, "reactions", reactions(result(emoji("👍"), 2, 1), 0));
    CHECK_EQ_INT(exteria_updates_cache_message(&updates, m), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_put(store, EXTERIA_RECORD_MESSAGE, other, 5, m), EXTERIA_OK);
    update = obj("updateMessageReactions");
    set(update, "peer", peer("peerChannel", "channel_id", channel.id));
    i32(update, "msg_id", 5);
    r = reactions(result(emoji("👍"), 3, 0), 1);
    set(update, "reactions", r);
    wrapper = obj("updateShort"); set(wrapper, "update", update); i32(wrapper, "date", 11);
    CHECK_EQ_INT(exteria_reaction_update_read(wrapper, channel.kind, channel.id, 5, &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.items[0].count, 3);
    CHECK_EQ_INT(exteria_reaction_update_read(wrapper, other.kind, other.id, 5, &parsed), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(parsed.count, 0);
    CHECK_EQ_INT(exteria_reaction_update_read(wrapper, channel.kind, channel.id, 6, &parsed), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_reaction_update_read(obj("updatesTooLong"), channel.kind, channel.id, 5, &parsed), EXTERIA_E_RETRY);
    CHECK_EQ_INT(exteria_reaction_update_read(obj("boolTrue"), channel.kind, channel.id, 5, &parsed), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_reaction_update_read(wrapper, 0, channel.id, 5, &parsed), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_updates_apply(&updates, wrapper), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_get(store, EXTERIA_RECORD_MESSAGE, channel, 5, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_reactions_read(exteria_tl_get(got, "reactions"), &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.items[0].count, 3);
    CHECK_EQ_INT(parsed.items[0].chosen, 1);
    /* the rpc value must not borrow a chosen_order from the freed storage arena */
    CHECK_EQ_INT(exteria_reactions_read(r, &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.items[0].chosen, 0);
    CHECK_EQ_INT(exteria_store_get(store, EXTERIA_RECORD_MESSAGE, other, 5, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_reactions_read(exteria_tl_get(got, "reactions"), &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.items[0].count, 2);
    set(m, "reactions", reactions(result(emoji("👍"), 4, 0), 1));
    CHECK_EQ_INT(exteria_updates_cache_message(&updates, m), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_get(store, EXTERIA_RECORD_MESSAGE, channel, 5, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_reactions_read(exteria_tl_get(got, "reactions"), &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.items[0].count, 4);
    CHECK_EQ_INT(parsed.items[0].chosen, 1);
    set(update, "reactions", reactions(result(emoji("👍"), 4, 0), 0));
    CHECK_EQ_INT(exteria_updates_apply(&updates, wrapper), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_get(store, EXTERIA_RECORD_MESSAGE, channel, 5, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_reactions_read(exteria_tl_get(got, "reactions"), &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.items[0].chosen, 0);
    set(update, "reactions", reactions(result(emoji("👍"), -1, 0), 0));
    CHECK_EQ_INT(exteria_updates_apply(&updates, wrapper), EXTERIA_E_MALFORMED);
    set(update, "reactions", reactions(NULL, 0));
    CHECK_EQ_INT(exteria_updates_apply(&updates, wrapper), EXTERIA_OK);
    i32(update, "msg_id", 900);
    CHECK_EQ_INT(exteria_updates_apply(&updates, wrapper), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_get(store, EXTERIA_RECORD_MESSAGE, channel, 900, &read, &got), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_store_close(store), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_open(&store, path, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_store_get(store, EXTERIA_RECORD_MESSAGE, channel, 5, &read, &got), EXTERIA_OK);
    CHECK_EQ_INT(exteria_reactions_read(exteria_tl_get(got, "reactions"), &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.count, 0);
    {
        const uint8_t *text; size_t length;
        CHECK_EQ_INT(exteria_tl_get_bytes(got, "message", &text, &length), EXTERIA_OK);
        CHECK_EQ_INT(length, strlen("keep this text"));
        CHECK(!memcmp(text, "keep this text", length));
    }
    CHECK_EQ_INT(exteria_store_close(store), EXTERIA_OK);
    unlink(path);
    exteria_arena_free(&read);
}

static void test_layout(void) {
    double widths[EXTERIA_REACTION_CATALOG_MAX], height;
    exteria_rect frames[EXTERIA_REACTION_CATALOG_MAX];
    size_t i;
    const double hosts[] = {240, 320, 480, 768};
    for (i = 0; i < EXTERIA_REACTION_CATALOG_MAX; ++i) widths[i] = (i % 3 == 0) ? 100 : 44;
    for (i = 0; i < sizeof(hosts) / sizeof(hosts[0]); ++i) {
        size_t j;
        CHECK_EQ_INT(exteria_reaction_layout_compute(hosts[i], 1, widths, EXTERIA_REACTION_CATALOG_MAX,
            frames, EXTERIA_REACTION_CATALOG_MAX, &height), EXTERIA_OK);
        for (j = 0; j < EXTERIA_REACTION_CATALOG_MAX; ++j) {
            CHECK(frames[j].x >= 0 && frames[j].x + frames[j].width <= hosts[i]);
            CHECK(frames[j].y + frames[j].height <= height);
            if (j && frames[j].y == frames[j - 1].y) CHECK(frames[j].x >= frames[j - 1].x + frames[j - 1].width + 4);
        }
    }
    widths[0] = 1000;
    CHECK_EQ_INT(exteria_reaction_layout_compute(44, 1, widths, 1, frames, 1, &height), EXTERIA_OK);
    CHECK_EQ_INT(frames[0].width, 44);
    CHECK_EQ_INT(height, 36);
    CHECK_EQ_INT(exteria_reaction_layout_compute(320, 1, NULL, 0, NULL, 0, &height), EXTERIA_OK);
    CHECK_EQ_INT(height, 0);
    CHECK_EQ_INT(exteria_reaction_layout_compute(320, 1, widths, 2, frames, 1, &height), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_layout_compute(43, 1, widths, 1, frames, 1, &height), EXTERIA_E_ARG);
    widths[0] = NAN;
    CHECK_EQ_INT(exteria_reaction_layout_compute(320, 1, widths, 1, frames, 1, &height), EXTERIA_E_ARG);
    CHECK_EQ_INT(height, 0);
    CHECK_EQ_INT(frames[0].width, 0);
    widths[0] = -1;
    CHECK_EQ_INT(exteria_reaction_layout_compute(320, 1, widths, 1, frames, 1, &height), EXTERIA_E_ARG);
    /* a smaller text size shrinks the chip, its smallest width and the rows together; a size outside the range is refused */
    widths[0] = 10;
    widths[1] = 10;
    CHECK_EQ_INT(exteria_reaction_layout_compute(320, 0.75, widths, 2, frames, 2, &height), EXTERIA_OK);
    CHECK_EQ_INT(frames[0].width, 33);
    CHECK_EQ_INT(frames[0].height, 27);
    CHECK_EQ_INT(frames[1].x, 33 + 3);
    CHECK_EQ_INT(height, 27);
    CHECK_EQ_INT(exteria_reaction_layout_compute(320, 0.4, widths, 1, frames, 1, &height), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reaction_layout_compute(320, 2.5, widths, 1, frames, 1, &height), EXTERIA_E_ARG);
}

static exteria_tl_value *peer_reaction(const char *peer_type, const char *field, int64_t id, exteria_tl_value *reaction) {
    exteria_tl_value *v = obj("messagePeerReaction");
    set(v, "peer_id", peer(peer_type, field, id));
    set(v, "reaction", reaction);
    i32(v, "date", 5);
    return v;
}
static exteria_tl_value *recent_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    return vec;
}

static void test_reactors(void) {
    exteria_reactions rows;
    exteria_tl_value *v = obj("messageReactions"), *results = exteria_tl_new_vec(&arena, 2), *recent[7];
    CHECK(results != NULL);
    CHECK_EQ_INT(exteria_tl_vec_set(results, 0, result(emoji("👍"), 3, 0)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_vec_set(results, 1, result(emoji("🔥"), 1, 1)), EXTERIA_OK);
    set(v, "results", results);
    /* without a list there are no reactors */
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.items[0].reactor_count, 0);
    CHECK_EQ_INT(rows.items[1].reactor_count, 0);

    recent[0] = peer_reaction("peerUser", "user_id", 11, emoji("👍"));
    recent[1] = peer_reaction("peerUser", "user_id", 12, emoji("🔥"));
    recent[2] = peer_reaction("peerUser", "user_id", 13, emoji("👍"));
    recent[3] = peer_reaction("peerUser", "user_id", 11, emoji("👍"));      /* the same person twice counts once */
    recent[4] = peer_reaction("peerChannel", "channel_id", 99, emoji("👍")); /* a channel is not a person */
    recent[5] = peer_reaction("peerUser", "user_id", 14, emoji("😢"));      /* a reaction the message does not count */
    recent[6] = peer_reaction("peerUser", "user_id", 15, emoji("👍"));
    set(v, "recent_reactions", recent_of(recent, 7));
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.count, 2);
    CHECK_EQ_INT(rows.items[0].reactor_count, 3);
    CHECK_EQ_INT(rows.items[0].reactors[0], 11);
    CHECK_EQ_INT(rows.items[0].reactors[1], 13);
    CHECK_EQ_INT(rows.items[0].reactors[2], 15);
    CHECK_EQ_INT(rows.items[1].reactor_count, 1);
    CHECK_EQ_INT(rows.items[1].reactors[0], 12);

    /* a fourth reactor is past the cap, and malformed entries are skipped without failing the read */
    recent[0] = peer_reaction("peerUser", "user_id", 21, emoji("👍"));
    recent[1] = peer_reaction("peerUser", "user_id", 22, emoji("👍"));
    recent[2] = peer_reaction("peerUser", "user_id", 23, emoji("👍"));
    recent[3] = peer_reaction("peerUser", "user_id", 24, emoji("👍"));
    recent[4] = peer_reaction("peerUser", "user_id", -5, emoji("🔥"));
    recent[5] = obj("boolTrue");
    recent[6] = peer_reaction("peerUser", "user_id", 26, obj("reactionEmpty"));
    set(v, "recent_reactions", recent_of(recent, 7));
    CHECK_EQ_INT(exteria_reactions_read(v, &rows), EXTERIA_OK);
    CHECK_EQ_INT(rows.items[0].reactor_count, EXTERIA_REACTORS_MAX);
    CHECK_EQ_INT(rows.items[0].reactors[2], 23);
    CHECK_EQ_INT(rows.items[1].reactor_count, 0);
}

static void test_faces(void) {
    exteria_reactions all;
    memset(&all, 0, sizeof(all));
    all.count = 2;
    all.items[0].kind = EXTERIA_REACTION_EMOJI;
    all.items[1].kind = EXTERIA_REACTION_EMOJI;
    /* a private chat knows who chose from the count and our own flag */
    all.items[0].count = 1;
    all.items[1].count = 2;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 1), EXTERIA_FACES_OTHER);
    all.items[0].chosen = 1;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 1), EXTERIA_FACES_SELF);
    CHECK_EQ_INT(exteria_reaction_faces(&all, 1, 1), EXTERIA_FACES_SELF_AND_OTHER);
    all.items[0].count = 3;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 1), EXTERIA_FACES_NONE);
    /* a group names people only for at most three reactions in all, every one of them known */
    all.items[0].count = 1;
    all.items[0].reactor_count = 1;
    all.items[1].count = 2;
    all.items[1].reactor_count = 2;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 0), EXTERIA_FACES_REACTORS);
    CHECK_EQ_INT(exteria_reaction_faces(&all, 1, 0), EXTERIA_FACES_REACTORS);
    all.items[1].reactor_count = 1;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 1, 0), EXTERIA_FACES_NONE);
    all.items[1].reactor_count = 2;
    all.items[0].count = 2;
    all.items[0].reactor_count = 2;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 0), EXTERIA_FACES_NONE);
    all.count = 1;
    all.items[0].count = 3;
    all.items[0].reactor_count = 3;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 0), EXTERIA_FACES_REACTORS);
    all.items[0].count = 4;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 0), EXTERIA_FACES_NONE);
    all.items[0].count = 1;
    all.items[0].reactor_count = 1;
    all.items[0].kind = EXTERIA_REACTION_PAID;
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 0), EXTERIA_FACES_NONE);
    CHECK_EQ_INT(exteria_reaction_faces(&all, 0, 1), EXTERIA_FACES_NONE);
    CHECK_EQ_INT(exteria_reaction_faces(&all, 1, 0), EXTERIA_FACES_NONE);
    CHECK_EQ_INT(exteria_reaction_faces(NULL, 0, 0), EXTERIA_FACES_NONE);
}

int main(void) {
    exteria_arena_init(&arena, 16u * 1024u * 1024u);
    test_parse();
    test_reactors();
    test_faces();
    test_requests();
    test_catalog_policy();
    test_custom_reactions();
    test_store();
    test_layout();
    exteria_arena_free(&arena);
    return test_finish("test_reactions");
}
