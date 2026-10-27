#include "test_util.h"
#include "exteria_secret.h"
#include "exteria_tl_ids.h"
#include "srp_vectors.h"

static exteria_tl_value *message(exteria_arena *arena, int64_t id) {
    exteria_tl_value *v = exteria_tl_new_obj(arena, "decryptedMessage");
    CHECK_EQ_INT(exteria_tl_set_i64(arena, v, "random_id", id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(arena, v, "ttl", 10), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(arena, v, "message", "secret text"), EXTERIA_OK);
    return v;
}
static exteria_tl_value *service(exteria_arena *a, const exteria_tl_value *action, int64_t random_id) {
    exteria_tl_value *v = exteria_tl_new_obj(a, "decryptedMessageService");
    CHECK_EQ_INT(exteria_tl_set_i64(a, v, "random_id", random_id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(v, "action", (exteria_tl_value *)action), EXTERIA_OK);
    return v;
}
static void exchange(exteria_secret_state *sender, exteria_secret_state *receiver, const exteria_tl_value *v,
                     exteria_arena *arena, exteria_tl_value **received) {
    exteria_writer packet;
    exteria_secret_state next;
    exteria_writer_init(&packet, 2u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_secret_seal(sender, v, &packet, &next), EXTERIA_OK);
    *sender = next;
    CHECK_EQ_INT(exteria_secret_open(receiver, packet.data, packet.len, arena, received, &next), EXTERIA_OK);
    *receiver = next;
    exteria_writer_free(&packet);
    exteria_secret_free(&next);
}

int main(void) {
    exteria_secret_dh da, db;
    exteria_mt_auth_key ka, kb;
    exteria_secret_state a, b, next;
    exteria_arena arena, received;
    exteria_tl_value *v, *got, *request, *accept, *commit, *noop;
    exteria_writer packet, packet2, short_output;
    uint8_t invalid[256] = {0};
    uint64_t old_key;
    exteria_arena_init(&arena, 4u * 1024u * 1024u);
    exteria_arena_init(&received, 4u * 1024u * 1024u);
    CHECK_EQ_INT(exteria_secret_dh_begin(&da, srp_prime, 3, NULL, 0), EXTERIA_OK);
    CHECK_EQ_INT(exteria_secret_dh_begin(&db, srp_prime, 3, srp_b, 256), EXTERIA_OK);
    CHECK_EQ_INT(exteria_secret_dh_finish(&da, db.public_value, 256, &ka), EXTERIA_OK);
    CHECK_EQ_INT(exteria_secret_dh_finish(&db, da.public_value, 256, &kb), EXTERIA_OK);
    CHECK_MEM(ka.key, kb.key, 256);
    CHECK_EQ_INT(ka.id, kb.id);
    CHECK_EQ_INT(exteria_secret_init(&a, 1, &da, &ka, 1000), EXTERIA_OK);
    CHECK_EQ_INT(exteria_secret_init(&b, 0, &db, &kb, 1000), EXTERIA_OK);
    v = exteria_tl_new_obj(&arena, "decryptedMessageActionNotifyLayer");
    CHECK_EQ_INT(exteria_tl_set_i32(&arena, v, "layer", EXTERIA_SECRET_LAYER), EXTERIA_OK);
    exchange(&a, &b, service(&arena, v, 10), &received, &got);
    CHECK_EQ_INT(exteria_secret_action(&b, exteria_tl_get(got, "action"), 1000, &arena, &noop, &next), EXTERIA_OK);
    b = next;
    exchange(&b, &a, service(&arena, v, 11), &received, &got);
    CHECK_EQ_INT(exteria_secret_action(&a, exteria_tl_get(got, "action"), 1000, &arena, &noop, &next), EXTERIA_OK);
    a = next;
    CHECK_EQ_INT(a.remote_layer, EXTERIA_SECRET_LAYER);
    CHECK_EQ_INT(b.remote_layer, EXTERIA_SECRET_LAYER);
    exteria_writer_init(&packet, 2u * 1024u * 1024u);
    exteria_writer_init(&packet2, 2u * 1024u * 1024u);
    exteria_writer_init(&short_output, 10);
    v = message(&arena, 12);
    CHECK_EQ_INT(exteria_secret_seal(&a, v, &short_output, &next), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(next.out_count, a.out_count);
    CHECK_EQ_INT(short_output.len, 0);
    CHECK_EQ_INT(exteria_secret_seal(&a, v, &packet, &next), EXTERIA_OK);
    a = next;
    CHECK_EQ_INT(exteria_secret_seal(&a, message(&arena, 13), &packet2, &next), EXTERIA_OK);
    a = next;
    CHECK_EQ_INT(exteria_secret_open(&b, packet2.data, packet2.len, &received, &got, &next), EXTERIA_E_RETRY);
    CHECK_EQ_INT(next.in_count, b.in_count);
    CHECK_EQ_INT(exteria_secret_open(&b, packet.data, packet.len, &received, &got, &next), EXTERIA_OK);
    b = next;
    CHECK_EQ_INT(exteria_secret_open(&b, packet.data, packet.len, &received, &got, &next), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(exteria_secret_open(&b, packet2.data, packet2.len, &received, &got, &next), EXTERIA_OK);
    b = next;
    CHECK_EQ_INT(exteria_secret_open(&a, packet.data, packet.len, &received, &got, &next), EXTERIA_E_SECURITY);
    packet.data[packet.len - 1] ^= 1;
    CHECK_EQ_INT(exteria_secret_open(&b, packet.data, packet.len, &received, &got, &next), EXTERIA_E_SECURITY);
    CHECK(next.discarded);
    packet.data[packet.len - 1] ^= 1;
    CHECK(exteria_secret_rekey_due(&a, 1000 + 604800));
    CHECK_EQ_INT(exteria_secret_rekey_start(&a, &arena, &request, &next), EXTERIA_OK);
    a = next;
    CHECK(!exteria_secret_rekey_due(&a, 1000 + 604800));
    exchange(&a, &b, service(&arena, request, 14), &received, &got);
    CHECK_EQ_INT(exteria_secret_action(&b, exteria_tl_get(got, "action"), 2000, &arena, &accept, &next), EXTERIA_OK);
    b = next;
    CHECK(accept != NULL);
    exchange(&b, &a, service(&arena, accept, 15), &received, &got);
    CHECK_EQ_INT(exteria_secret_action(&a, exteria_tl_get(got, "action"), 2000, &arena, &commit, &next), EXTERIA_OK);
    a = next;
    old_key = a.key.id;
    exchange(&a, &b, service(&arena, commit, 16), &received, &got);
    CHECK(a.key.id != old_key);
    CHECK_EQ_INT(exteria_secret_action(&b, exteria_tl_get(got, "action"), 2000, &arena, &noop, &next), EXTERIA_OK);
    b = next;
    CHECK_EQ_INT(a.key.id, b.key.id);
    CHECK_EQ_INT(b.previous.id, 0);
    exchange(&b, &a, service(&arena, noop, 17), &received, &got);
    CHECK_EQ_INT(a.previous.id, 0);
    CHECK_EQ_INT(a.rekey_state, 0);
    CHECK_MEM(a.visualization, b.visualization, sizeof(a.visualization));
    CHECK_EQ_INT(exteria_secret_dh_finish(&da, invalid, 256, &ka), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(ka.id, 0);
    CHECK_EQ_INT(exteria_secret_expiry(10, 100, 30), 131);
    CHECK_EQ_INT(exteria_secret_expiry(0, 100, 30), 0);
    CHECK_EQ_INT(exteria_secret_expiry(10, UINT64_MAX - 2, 0), UINT64_MAX);
    exteria_secret_free(&a); exteria_secret_free(&b); exteria_secret_free(&next);
    exteria_wipe(&da, sizeof(da)); exteria_wipe(&db, sizeof(db)); exteria_wipe(&ka, sizeof(ka)); exteria_wipe(&kb, sizeof(kb));
    exteria_writer_free(&packet); exteria_writer_free(&packet2); exteria_writer_free(&short_output);
    exteria_arena_free(&arena); exteria_arena_free(&received);
    return test_finish("test_secret");
}
