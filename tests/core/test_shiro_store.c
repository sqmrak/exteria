#include "exteria_shiro_store.h"
#include "test_util.h"

static exteria_warp_identity sample(void) {
    exteria_warp_identity id;
    size_t i;
    memset(&id, 0, sizeof(id));
    for (i = 0; i < EXTERIA_WG_KEY_LEN; ++i) {
        id.private_key[i] = (uint8_t)(i + 1);
        id.peer_public[i] = (uint8_t)(0xa0 + i);
    }
    id.reserved[0] = 7;
    id.reserved[1] = 250;
    id.reserved[2] = 0;
    id.has_reserved = 1;
    id.address = 0xac100002u;
    id.endpoint_ip = 0xa29fc001u;
    id.ports[0] = 2408;
    id.ports[1] = 500;
    id.ports[2] = 0xfffe;
    id.port_count = 3;
    return id;
}

static void round_trip(void) {
    exteria_warp_identity id = sample(), back;
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN + 8];
    size_t len = 0;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_OK);
    CHECK_EQ_INT(len, EXTERIA_SHIRO_STORE_LEN);
    CHECK_MEM(buf, "EXW1", 4);
    CHECK_EQ_INT(exteria_shiro_store_unpack(buf, len, &back), EXTERIA_OK);
    CHECK_MEM(back.private_key, id.private_key, EXTERIA_WG_KEY_LEN);
    CHECK_MEM(back.peer_public, id.peer_public, EXTERIA_WG_KEY_LEN);
    CHECK_MEM(back.reserved, id.reserved, 3);
    CHECK_EQ_INT(back.has_reserved, 1);
    CHECK_EQ_INT(back.address, id.address);
    CHECK_EQ_INT(back.endpoint_ip, id.endpoint_ip);
    CHECK_EQ_INT(back.port_count, 3);
    CHECK_EQ_INT(back.ports[0], 2408);
    CHECK_EQ_INT(back.ports[1], 500);
    CHECK_EQ_INT(back.ports[2], 0xfffe);
    CHECK_EQ_INT(back.ports[3], 0);
}

static void without_reserved_bytes(void) {
    exteria_warp_identity id = sample(), back;
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN];
    size_t len = 0;
    id.has_reserved = 0;
    memset(id.reserved, 0, sizeof(id.reserved));
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_shiro_store_unpack(buf, len, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.has_reserved, 0);
}

static void full_port_table(void) {
    exteria_warp_identity id = sample(), back;
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN];
    size_t len = 0, i;
    for (i = 0; i < EXTERIA_WARP_MAX_PORTS; ++i) id.ports[i] = (uint16_t)(1000 + i);
    id.port_count = EXTERIA_WARP_MAX_PORTS;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_shiro_store_unpack(buf, len, &back), EXTERIA_OK);
    CHECK_EQ_INT(back.port_count, EXTERIA_WARP_MAX_PORTS);
    CHECK_EQ_INT(back.ports[EXTERIA_WARP_MAX_PORTS - 1], 1000 + EXTERIA_WARP_MAX_PORTS - 1);
}

static void pack_refuses(void) {
    exteria_warp_identity id = sample();
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN];
    size_t len = 99;
    CHECK_EQ_INT(exteria_shiro_store_pack(NULL, buf, sizeof(buf), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(len, 0);
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, NULL, sizeof(buf), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, EXTERIA_SHIRO_STORE_LEN - 1, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(len, 0);

    id = sample();
    id.endpoint_ip = 0;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_E_ARG);
    id = sample();
    id.address = 0;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_E_ARG);
    id = sample();
    id.port_count = 0;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_E_ARG);
    id = sample();
    id.port_count = EXTERIA_WARP_MAX_PORTS + 1;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_E_ARG);
}

static void unpack_refuses(void) {
    exteria_warp_identity id = sample(), out;
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN], bad[EXTERIA_SHIRO_STORE_LEN];
    size_t len = 0, i;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_OK);

    CHECK_EQ_INT(exteria_shiro_store_unpack(NULL, len, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_shiro_store_unpack(buf, 0, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_shiro_store_unpack(buf, len - 1, &out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_shiro_store_unpack(buf, len, NULL), EXTERIA_E_ARG);

    /* every cut of a good file is refused, never read as a shorter identity */
    for (i = 0; i < len; ++i) CHECK_EQ_INT(exteria_shiro_store_unpack(buf, i, &out), EXTERIA_E_MALFORMED);

    memcpy(bad, buf, len);
    bad[3] = '2';
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);

    /* the reserved flag is 0 or 1 */
    memcpy(bad, buf, len);
    bad[4 + 64] = 2;
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);

    /* the port count sits after the two addresses: 4 + 64 + 1 + 3 + 4 + 4 */
    memcpy(bad, buf, len);
    bad[80] = 0;
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);
    memcpy(bad, buf, len);
    bad[80] = EXTERIA_WARP_MAX_PORTS + 1;
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);

    /* a stray port past the count, and a zero port inside it */
    memcpy(bad, buf, len);
    bad[81 + 2 * 5] = 1;
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);
    memcpy(bad, buf, len);
    bad[81] = 0;
    bad[82] = 0;
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);

    /* no address, no endpoint */
    memcpy(bad, buf, len);
    memset(bad + 72, 0, 4);
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);
    memcpy(bad, buf, len);
    memset(bad + 76, 0, 4);
    CHECK_EQ_INT(exteria_shiro_store_unpack(bad, len, &out), EXTERIA_E_MALFORMED);
}

static void failure_leaves_nothing(void) {
    exteria_warp_identity id = sample(), out;
    uint8_t buf[EXTERIA_SHIRO_STORE_LEN];
    uint8_t zero[sizeof(out)];
    size_t len = 0;
    CHECK_EQ_INT(exteria_shiro_store_pack(&id, buf, sizeof(buf), &len), EXTERIA_OK);
    buf[80] = 0;
    memset(&out, 0x5a, sizeof(out));
    memset(zero, 0, sizeof(zero));
    CHECK_EQ_INT(exteria_shiro_store_unpack(buf, len, &out), EXTERIA_E_MALFORMED);
    CHECK_MEM(&out, zero, sizeof(out));
}

int main(void) {
    round_trip();
    without_reserved_bytes();
    full_port_table();
    pack_refuses();
    unpack_refuses();
    failure_leaves_nothing();
    return test_finish("test_shiro_store");
}
