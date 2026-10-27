#include "test_util.h"
#include "exteria_privacy.h"
#include "exteria_tl_ids.h"

#include <string.h>

static exteria_arena arena;

static exteria_tl_value *obj(const char *name) {
    exteria_tl_value *v = exteria_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
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

static exteria_tl_value *user(int64_t id, int64_t hash, const char *name) {
    exteria_tl_value *v = obj("user");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "access_hash", hash), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, "first_name", name), EXTERIA_OK);
    return v;
}

static exteria_tl_value *chat(int64_t id, const char *title) {
    exteria_tl_value *v = obj("chat");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, v, "id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena, v, "title", title), EXTERIA_OK);
    return v;
}

static exteria_tl_value *vec_of(exteria_tl_value **items, uint32_t n) {
    exteria_tl_value *vec = exteria_tl_new_vec(&arena, n);
    uint32_t i;
    CHECK(vec != NULL);
    for (i = 0; i < n; ++i) CHECK_EQ_INT(exteria_tl_vec_set(vec, i, items[i]), EXTERIA_OK);
    return vec;
}

static exteria_tl_value *ids_rule(const char *ctor, const char *field, const int64_t *ids, uint32_t n) {
    exteria_tl_value *rule = obj(ctor);
    CHECK_EQ_INT(exteria_tl_set_i64_vec(&arena, rule, field, ids, n), EXTERIA_OK);
    return rule;
}

static exteria_tl_value *answer(exteria_tl_value **rules, uint32_t n, exteria_tl_value **chats, uint32_t nc, exteria_tl_value **users, uint32_t nu) {
    exteria_tl_value *a = obj("account.privacyRules");
    CHECK_EQ_INT(exteria_tl_set(a, "rules", vec_of(rules, n)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "chats", vec_of(chats, nc)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "users", vec_of(users, nu)), EXTERIA_OK);
    return a;
}

static void test_parse(void) {
    static exteria_privacy_rules rules;
    const int64_t allowed[2] = {10, 11}, never[1] = {12}, groups[1] = {5};
    exteria_tl_value *items[5], *chats[1], *users[3];
    items[0] = ids_rule("privacyValueAllowUsers", "users", allowed, 2);
    items[1] = ids_rule("privacyValueDisallowUsers", "users", never, 1);
    items[2] = ids_rule("privacyValueDisallowChatParticipants", "chats", groups, 1);
    items[3] = obj("privacyValueAllowPremium");
    items[4] = obj("privacyValueAllowContacts");
    chats[0] = chat(5, "Club");
    users[0] = user(10, 1010, "Ann");
    users[1] = user(11, 1111, "Bob");
    users[2] = user(12, 1212, "Cy");
    CHECK_EQ_INT(exteria_privacy_parse(answer(items, 5, chats, 1, users, 3), &rules), EXTERIA_OK);
    CHECK_EQ_INT(rules.base, EXTERIA_PRIVACY_CONTACTS);
    CHECK_EQ_INT(rules.allow_users_count, 2);
    CHECK_EQ_INT(rules.allow_users[1].id, 11);
    CHECK_EQ_INT(rules.allow_users[1].access_hash, 1111);
    CHECK(!strcmp(rules.allow_users[0].name, "Ann"));
    CHECK_EQ_INT(rules.disallow_users_count, 1);
    CHECK_EQ_INT(rules.disallow_chats_count, 1);
    CHECK(!strcmp(rules.disallow_chats[0].title, "Club"));
    CHECK_EQ_INT(rules.allow_premium, 1);
    CHECK_EQ_INT(rules.allow_chats_count, 0);

    /* the last base stands, and a list with no base is nobody */
    items[0] = obj("privacyValueAllowAll");
    items[1] = obj("privacyValueDisallowAll");
    CHECK_EQ_INT(exteria_privacy_parse(answer(items, 2, chats, 0, users, 0), &rules), EXTERIA_OK);
    CHECK_EQ_INT(rules.base, EXTERIA_PRIVACY_NOBODY);
    CHECK_EQ_INT(exteria_privacy_parse(answer(items, 0, chats, 0, users, 0), &rules), EXTERIA_OK);
    CHECK_EQ_INT(rules.base, EXTERIA_PRIVACY_NOBODY);
    items[0] = obj("privacyValueAllowAll");
    CHECK_EQ_INT(exteria_privacy_parse(answer(items, 1, chats, 0, users, 0), &rules), EXTERIA_OK);
    CHECK_EQ_INT(rules.base, EXTERIA_PRIVACY_EVERYBODY);

    /* a person the answer does not describe keeps the id with no hash and no name */
    {
        const int64_t lone[1] = {77};
        items[0] = ids_rule("privacyValueAllowUsers", "users", lone, 1);
        CHECK_EQ_INT(exteria_privacy_parse(answer(items, 1, chats, 0, users, 0), &rules), EXTERIA_OK);
        CHECK_EQ_INT(rules.allow_users[0].id, 77);
        CHECK_EQ_INT(rules.allow_users[0].access_hash, 0);
        CHECK_EQ_INT(rules.allow_users[0].name[0], 0);
    }
    /* more exceptions than the struct holds are refused whole, and the output stays defined */
    {
        static int64_t many[EXTERIA_PRIVACY_EXCEPT_MAX + 1];
        size_t i;
        for (i = 0; i < EXTERIA_PRIVACY_EXCEPT_MAX + 1; ++i) many[i] = (int64_t)i + 1;
        items[0] = ids_rule("privacyValueAllowUsers", "users", many, EXTERIA_PRIVACY_EXCEPT_MAX + 1);
        rules.allow_users_count = 9;
        CHECK_EQ_INT(exteria_privacy_parse(answer(items, 1, chats, 0, users, 0), &rules), EXTERIA_E_LIMIT);
        CHECK_EQ_INT(rules.allow_users_count, 0);
    }
    CHECK_EQ_INT(exteria_privacy_parse(obj("boolTrue"), &rules), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_privacy_parse(items[0], NULL), EXTERIA_E_ARG);
}

static void test_set(void) {
    static exteria_privacy_rules rules;
    exteria_tl_value *request = NULL;
    const exteria_tl_value *list;
    memset(&rules, 0, sizeof(rules));
    rules.base = EXTERIA_PRIVACY_CONTACTS;
    rules.allow_users_count = 1;
    rules.allow_users[0].id = 10;
    rules.allow_users[0].access_hash = 1010;
    rules.disallow_chats_count = 1;
    rules.disallow_chats[0].id = 5;
    rules.allow_premium = 1;
    CHECK_EQ_INT(exteria_privacy_set_request(&arena, EXTERIA_PRIVACY_LAST_SEEN, &rules, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_setPrivacy);
    CHECK_EQ_INT(exteria_tl_get_vec(request, "rules", &list), EXTERIA_OK);
    /* the exceptions come first, the extras after them and the base last */
    CHECK_EQ_INT(list->u.vec.count, 4);
    CHECK_EQ_INT(exteria_tl_id(list->u.vec.items[0]), EXTERIA_TL_ID_inputPrivacyValueAllowUsers);
    CHECK_EQ_INT(exteria_tl_id(list->u.vec.items[1]), EXTERIA_TL_ID_inputPrivacyValueDisallowChatParticipants);
    CHECK_EQ_INT(exteria_tl_id(list->u.vec.items[2]), EXTERIA_TL_ID_inputPrivacyValueAllowPremium);
    CHECK_EQ_INT(exteria_tl_id(list->u.vec.items[3]), EXTERIA_TL_ID_inputPrivacyValueAllowContacts);
    CHECK(exteria_tl_is(exteria_tl_get(request, "key"), EXTERIA_TL_ID_inputPrivacyKeyStatusTimestamp));
    /* no exceptions: just the base */
    memset(&rules, 0, sizeof(rules));
    rules.base = EXTERIA_PRIVACY_EVERYBODY;
    CHECK_EQ_INT(exteria_privacy_set_request(&arena, EXTERIA_PRIVACY_PHONE, &rules, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_get_vec(request, "rules", &list), EXTERIA_OK);
    CHECK_EQ_INT(list->u.vec.count, 1);
    CHECK_EQ_INT(exteria_tl_id(list->u.vec.items[0]), EXTERIA_TL_ID_inputPrivacyValueAllowAll);
    /* a person with no hash cannot be named, and the whole write is refused */
    rules.disallow_users_count = 1;
    rules.disallow_users[0].id = 3;
    CHECK_EQ_INT(exteria_privacy_set_request(&arena, EXTERIA_PRIVACY_PHONE, &rules, &request), EXTERIA_E_ARG);
    CHECK(request == NULL);
    rules.disallow_users_count = 0;
    CHECK_EQ_INT(exteria_privacy_set_request(&arena, EXTERIA_PRIVACY_KEY_COUNT, &rules, &request), EXTERIA_E_ARG);
    rules.base = (exteria_privacy_base)9;
    CHECK_EQ_INT(exteria_privacy_set_request(&arena, EXTERIA_PRIVACY_PHONE, &rules, &request), EXTERIA_E_ARG);
    rules.base = EXTERIA_PRIVACY_NOBODY;
    rules.allow_users_count = EXTERIA_PRIVACY_EXCEPT_MAX + 1;
    CHECK_EQ_INT(exteria_privacy_set_request(&arena, EXTERIA_PRIVACY_PHONE, &rules, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_privacy_get_request(&arena, EXTERIA_PRIVACY_MUSIC, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_getPrivacy);
    CHECK_EQ_INT(exteria_privacy_get_request(&arena, (exteria_privacy_key)-1, &request), EXTERIA_E_ARG);
}

static exteria_tl_value *blocked_entry(const char *peer, const char *field, int64_t id, int32_t date) {
    exteria_tl_value *entry = obj("peerBlocked"), *p = obj(peer);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena, p, field, id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(entry, "peer_id", p), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, entry, "date", date), EXTERIA_OK);
    return entry;
}

static void test_blocked(void) {
    exteria_blocked_row rows[4];
    exteria_tl_value *entries[3], *users[1], *chats[1], *a;
    size_t count = 99;
    int32_t total = -1;
    exteria_peer_ref peer;
    exteria_tl_value *request = NULL;
    entries[0] = blocked_entry("peerUser", "user_id", 10, 100);
    entries[1] = blocked_entry("peerChat", "chat_id", 5, 200);
    entries[2] = blocked_entry("peerUser", "user_id", 99, 300);
    users[0] = user(10, 1010, "Ann");
    chats[0] = chat(5, "Club");
    a = obj("contacts.blockedSlice");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, a, "count", 40), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "blocked", vec_of(entries, 3)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "chats", vec_of(chats, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "users", vec_of(users, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_blocked_parse(a, rows, 4, &count, &total), EXTERIA_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(total, 40);
    CHECK_EQ_INT(rows[0].kind, 1);
    CHECK_EQ_INT(rows[0].access_hash, 1010);
    CHECK(!strcmp(rows[0].name, "Ann"));
    CHECK_EQ_INT(rows[1].kind, 2);
    CHECK(!strcmp(rows[1].name, "Club"));
    CHECK_EQ_INT(rows[2].id, 99);
    CHECK_EQ_INT(rows[2].access_hash, 0);
    /* cap cuts the page short; a plain contacts.blocked counts its own page */
    CHECK_EQ_INT(exteria_blocked_parse(a, rows, 1, &count, NULL), EXTERIA_OK);
    CHECK_EQ_INT(count, 1);
    a = obj("contacts.blocked");
    CHECK_EQ_INT(exteria_tl_set(a, "blocked", vec_of(entries, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "chats", vec_of(chats, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(a, "users", vec_of(users, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_blocked_parse(a, rows, 4, &count, &total), EXTERIA_OK);
    CHECK_EQ_INT(total, 2);
    CHECK_EQ_INT(exteria_blocked_parse(obj("boolTrue"), rows, 4, &count, &total), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(exteria_blocked_parse(a, NULL, 4, &count, &total), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_blocked_request(&arena, 0, 100, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_contacts_getBlocked);
    CHECK_EQ_INT(exteria_blocked_request(&arena, -1, 100, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blocked_request(&arena, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_blocked_request(&arena, 0, EXTERIA_BLOCKED_MAX + 1, &request), EXTERIA_E_ARG);
    memset(&peer, 0, sizeof(peer));
    peer.kind = 1;
    peer.id = 10;
    peer.access_hash = 1010;
    CHECK_EQ_INT(exteria_block_request(&arena, &peer, 1, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_contacts_block);
    CHECK_EQ_INT(exteria_block_request(&arena, &peer, 0, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_contacts_unblock);
    peer.access_hash = 0;
    CHECK_EQ_INT(exteria_block_request(&arena, &peer, 0, &request), EXTERIA_E_ARG);
}

static void test_settings(void) {
    exteria_tl_value *request = NULL, *a;
    int32_t value = -1;
    CHECK_EQ_INT(exteria_account_ttl_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_getAccountTTL);
    a = obj("accountDaysTTL");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, a, "days", 180), EXTERIA_OK);
    CHECK_EQ_INT(exteria_account_ttl_parse(a, &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 180);
    CHECK_EQ_INT(exteria_account_ttl_parse(obj("boolTrue"), &value), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(value, 0);
    CHECK_EQ_INT(exteria_account_ttl_set_request(&arena, 365, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_account_setAccountTTL);
    CHECK_EQ_INT(exteria_account_ttl_set_request(&arena, 29, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_account_ttl_set_request(&arena, 731, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_history_ttl_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_getDefaultHistoryTTL);
    a = obj("defaultHistoryTTL");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, a, "period", 86400), EXTERIA_OK);
    CHECK_EQ_INT(exteria_history_ttl_parse(a, &value), EXTERIA_OK);
    CHECK_EQ_INT(value, 86400);
    CHECK_EQ_INT(exteria_history_ttl_set_request(&arena, 0, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_messages_setDefaultHistoryTTL);
    CHECK_EQ_INT(exteria_history_ttl_set_request(&arena, -1, &request), EXTERIA_E_ARG);

    CHECK_EQ_INT(exteria_clear_payments_request(&arena, 1, 1, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_payments_clearSavedInfo);
    CHECK_EQ_INT(exteria_tl_has(request, "credentials"), 1);
    CHECK_EQ_INT(exteria_tl_has(request, "info"), 1);
    CHECK_EQ_INT(exteria_clear_payments_request(&arena, 0, 1, &request), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_has(request, "credentials"), 0);
    CHECK_EQ_INT(exteria_clear_payments_request(&arena, 0, 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_reset_saved_contacts_request(&arena, &request), EXTERIA_OK);
    roundtrip(request, EXTERIA_TL_ID_contacts_resetSaved);
}

int main(void) {
    exteria_arena_init(&arena, 8u * 1024u * 1024u);
    test_parse();
    test_set();
    test_blocked();
    test_settings();
    exteria_arena_free(&arena);
    return test_finish("test_privacy");
}
