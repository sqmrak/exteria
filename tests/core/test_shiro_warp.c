#include "exteria_crypto.h"
#include "exteria_tgc_json.h"
#include "exteria_warp.h"
#include "test_util.h"

static void base64_vectors(void) {
    static const struct { const char *plain, *coded; } v[] = {{"", ""}, {"f", "Zg=="}, {"fo", "Zm8="}, {"foo", "Zm9v"}, {"foob", "Zm9vYg=="}, {"fooba", "Zm9vYmE="}, {"foobar", "Zm9vYmFy"}};
    size_t i;
    char text[64];
    uint8_t back[64];
    size_t n = 0;
    for (i = 0; i < sizeof(v) / sizeof(v[0]); ++i) {
        size_t plain_len = strlen(v[i].plain);
        CHECK_EQ_INT(exteria_base64_encode((const uint8_t *)v[i].plain, plain_len, text, sizeof(text), &n), EXTERIA_OK);
        CHECK_EQ_INT(n, strlen(v[i].coded));
        CHECK(strcmp(text, v[i].coded) == 0);
        CHECK_EQ_INT(exteria_base64_decode(v[i].coded, strlen(v[i].coded), back, sizeof(back), &n), EXTERIA_OK);
        CHECK_EQ_INT(n, plain_len);
        CHECK_MEM(back, v[i].plain, plain_len);
    }
    /* a 32 byte key is 44 characters with one padding */
    {
        uint8_t key[32];
        char coded[64];
        size_t k;
        for (k = 0; k < 32; ++k) key[k] = (uint8_t)(k * 9 + 1);
        CHECK_EQ_INT(exteria_base64_encode(key, 32, coded, sizeof(coded), &n), EXTERIA_OK);
        CHECK_EQ_INT(n, 44);
        CHECK_EQ_INT(exteria_base64_decode(coded, n, back, sizeof(back), &n), EXTERIA_OK);
        CHECK_EQ_INT(n, 32);
        CHECK_MEM(back, key, 32);
    }
}

static void base64_rejections(void) {
    uint8_t out[16];
    size_t n = 0;
    CHECK_EQ_INT(exteria_base64_decode("Zg=", 3, out, sizeof(out), &n), EXTERIA_E_MALFORMED);        /* length */
    CHECK_EQ_INT(exteria_base64_decode("Zg", 2, out, sizeof(out), &n), EXTERIA_E_MALFORMED);         /* no padding */
    CHECK_EQ_INT(exteria_base64_decode("Zm9=", 4, out, sizeof(out), &n), EXTERIA_E_MALFORMED);       /* stray bits */
    CHECK_EQ_INT(exteria_base64_decode("Zh==", 4, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_base64_decode("Zg==Zg==", 8, out, sizeof(out), &n), EXTERIA_E_MALFORMED);   /* padding in the middle */
    CHECK_EQ_INT(exteria_base64_decode("Zm9*", 4, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_base64_decode("Zm9v\n", 5, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_base64_decode("Zm-_", 4, out, sizeof(out), &n), EXTERIA_E_MALFORMED);       /* the url alphabet is not this one */
    CHECK_EQ_INT(exteria_base64_decode("Zg=a", 4, out, sizeof(out), &n), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_base64_decode("Zm9vYmFy", 8, out, 5, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_base64_decode("Zm9vYg==", 8, out, 3, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_base64_decode(NULL, 0, out, sizeof(out), &n), EXTERIA_E_ARG);
    {
        char tiny[4];
        CHECK_EQ_INT(exteria_base64_encode((const uint8_t *)"foo", 3, tiny, sizeof(tiny), &n), EXTERIA_E_LIMIT);
    }
}

static void ipv4_parsing(void) {
    uint32_t ip = 1;
    CHECK_EQ_INT(exteria_warp_parse_ipv4("172.16.0.2", 10, &ip), EXTERIA_OK);
    CHECK_EQ_INT(ip, 0xAC100002u);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("0.0.0.0", 7, &ip), EXTERIA_OK);
    CHECK_EQ_INT(ip, 0);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("255.255.255.255", 15, &ip), EXTERIA_OK);
    CHECK_EQ_INT(ip, 0xFFFFFFFFu);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("256.1.1.1", 9, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("1.2.3", 5, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("1.2.3.4.5", 9, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("01.2.3.4", 8, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("1.2.3.4 ", 8, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("1..3.4", 6, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("", 0, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("1.2.3.a", 7, &ip), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_ipv4("1111.2.3.4", 10, &ip), EXTERIA_E_MALFORMED);
}

static void key_generation(void) {
    uint8_t a[32], pa[32], b[32], pb[32], check[32];
    CHECK_EQ_INT(exteria_warp_generate_key(a, pa), EXTERIA_OK);
    CHECK_EQ_INT(exteria_warp_generate_key(b, pb), EXTERIA_OK);
    CHECK_EQ_INT(a[0] & 7, 0);
    CHECK_EQ_INT(a[31] & 0x80, 0);
    CHECK_EQ_INT(a[31] & 0x40, 0x40);
    CHECK(memcmp(a, b, 32) != 0);
    CHECK_EQ_INT(exteria_x25519_public(a, check), EXTERIA_OK);
    CHECK_MEM(check, pa, 32);
    CHECK_EQ_INT(exteria_warp_generate_key(NULL, pa), EXTERIA_E_ARG);
}

static void registration_body(void) {
    uint8_t pub[32];
    char body[512];
    size_t n = 0;
    exteria_json_doc *doc = NULL;
    const exteria_json *root;
    size_t len = 0;
    uint8_t back[32];
    size_t got = 0;
    memset(pub, 0x11, sizeof(pub));
    CHECK_EQ_INT(exteria_warp_registration_body(pub, "abcdefghijklmnopqrstuv", "2026-10-21T12:34:56.789Z", body, sizeof(body), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_json_parse(body, n, &doc), EXTERIA_OK);
    root = exteria_json_root(doc);
    CHECK_EQ_INT(exteria_json_kind(root), EXTERIA_JSON_OBJECT);
    CHECK(strcmp(exteria_json_string(exteria_json_get(root, "install_id"), &len), "abcdefghijklmnopqrstuv") == 0);
    CHECK(strcmp(exteria_json_string(exteria_json_get(root, "tos"), &len), "2026-10-21T12:34:56.789Z") == 0);
    CHECK(strcmp(exteria_json_string(exteria_json_get(root, "type"), &len), "Android") == 0);
    CHECK(strcmp(exteria_json_string(exteria_json_get(root, "fcm_token"), &len), "") == 0);
    {
        const char *key = exteria_json_string(exteria_json_get(root, "key"), &len);
        CHECK_EQ_INT(len, 44);
        CHECK_EQ_INT(exteria_base64_decode(key, len, back, sizeof(back), &got), EXTERIA_OK);
        CHECK_MEM(back, pub, 32);
    }
    exteria_json_free(doc);
    CHECK_EQ_INT(exteria_warp_registration_body(pub, "short", "t", body, sizeof(body), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_warp_registration_body(pub, "abcdefghijklmnopqrst\"v", "t", body, sizeof(body), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_warp_registration_body(pub, "abcdefghijklmnopqrstuv", "t", body, 40, &n), EXTERIA_E_LIMIT);
}

static const char good_answer[] =
    "{\"id\":\"a1b2\",\"type\":\"a\",\"key\":\"x\",\"account\":{\"id\":\"q\",\"account_type\":\"free\"},"
    "\"config\":{\"client_id\":\"AEOY\",\"peers\":[{\"public_key\":\"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=\","
    "\"endpoint\":{\"v4\":\"162.159.192.1:0\",\"v6\":\"[2606:4700:d0::a29f:c001]:0\",\"host\":\"engage.cloudflareclient.com:2408\","
    "\"ports\":[2408,500,1701,4500]}}],\"interface\":{\"addresses\":{\"v4\":\"172.16.0.2\",\"v6\":\"2606:4700:110:8d95:a92:92b6:b54a:d22f\"}},"
    "\"services\":{\"http_proxy\":\"172.16.0.1:2480\"}},\"token\":\"t\",\"warp_enabled\":true}";

/* out = in with the first from replaced by to; 0 when from is not there. in and out may be the same buffer */
static int replace_in(char *out, size_t cap, const char *in, const char *from, const char *to) {
    char copy[2048];
    const char *at = strstr(in, from);
    size_t pre;
    if (!at || strlen(in) + strlen(to) >= cap || strlen(in) >= sizeof(copy)) return 0;
    strcpy(copy, in);
    pre = (size_t)(at - in);
    memcpy(out, copy, pre);
    strcpy(out + pre, to);
    strcat(out, copy + pre + strlen(from));
    return 1;
}

static void registration_parse(void) {
    uint8_t priv[32];
    exteria_warp_identity id;
    size_t i;
    memset(priv, 0x22, sizeof(priv));
    CHECK_EQ_INT(exteria_warp_parse_registration(good_answer, strlen(good_answer), priv, &id), EXTERIA_OK);
    CHECK_MEM(id.private_key, priv, 32);
    CHECK_EQ_INT(id.address, 0xAC100002u);
    CHECK_EQ_INT(id.endpoint_ip, 0xA29FC001u);
    CHECK_EQ_INT(id.port_count, 4);
    CHECK_EQ_INT(id.ports[0], 2408);
    CHECK_EQ_INT(id.ports[3], 4500);
    CHECK_EQ_INT(id.has_reserved, 1);
    CHECK_EQ_INT(id.reserved[0], 0x00);
    CHECK_EQ_INT(id.reserved[1], 0x43);
    CHECK_EQ_INT(id.reserved[2], 0x98);
    CHECK_EQ_INT(id.peer_public[0], 0x6e);
    CHECK_EQ_INT(id.peer_public[31], 0x2a);

    /* each of these damages one thing the parser relies on */
    {
        static const struct { const char *from, *to; } damage[] = {
            {"\"config\"", "\"conf\""},
            {"\"peers\":[", "\"peers\":{"},
            {"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo"},
            {"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyA"},
            {"162.159.192.1:0", "162.159.192.300:0"},
            {"162.159.192.1:0", "engage.cloudflareclient.com:0"},
            {"172.16.0.2", "172.16.0"},
            {"172.16.0.2", "0.0.0.0"},
            {"\"v4\":\"162", "\"v4\":162"},
            {"[2408,500,1701,4500]", "[2408,0,1701,4500]"},
            {"[2408,500,1701,4500]", "[2408,70000,1701,4500]"},
            {"[2408,500,1701,4500]", "[2408,\"500\",1701,4500]"},
            {"\"interface\"", "\"iface\""},
            {"\"addresses\":{", "\"addresses\":[{"}
        };
        for (i = 0; i < sizeof(damage) / sizeof(damage[0]); ++i) {
            char text[2048];
            CHECK(replace_in(text, sizeof(text), good_answer, damage[i].from, damage[i].to));
            CHECK_EQ_INT(exteria_warp_parse_registration(text, strlen(text), priv, &id), EXTERIA_E_MALFORMED);
            CHECK_EQ_INT(id.port_count, 0);
        }
    }
    /* no ports list: the port in the host text is used */
    {
        char text[2048];
        replace_in(text, sizeof(text), good_answer, ",\"ports\":[2408,500,1701,4500]", "");
        replace_in(text, sizeof(text), text, "162.159.192.1:0", "162.159.192.1:2408");
        CHECK_EQ_INT(exteria_warp_parse_registration(text, strlen(text), priv, &id), EXTERIA_OK);
        CHECK_EQ_INT(id.port_count, 1);
        CHECK_EQ_INT(id.ports[0], 2408);
    }
    /* no client id that decodes to three bytes: no reserved bytes */
    {
        char text[2048];
        char *c;
        strcpy(text, good_answer);
        c = strstr(text, "AEOY");
        memcpy(c, "AEO", 3);
        c[3] = '=';   /* decodes to two bytes, not three */
        CHECK_EQ_INT(exteria_warp_parse_registration(text, strlen(text), priv, &id), EXTERIA_OK);
        CHECK_EQ_INT(id.has_reserved, 0);
    }
    CHECK_EQ_INT(exteria_warp_parse_registration("[]", 2, priv, &id), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_registration("not json", 8, priv, &id), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_registration("{}", 2, priv, &id), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_warp_parse_registration(NULL, 0, priv, &id), EXTERIA_E_ARG);
}

static void profile_and_endpoints(void) {
    uint8_t priv[32];
    exteria_warp_identity id;
    exteria_warp_profile profile;
    exteria_wg_config cfg;
    uint8_t blob[1024];
    size_t n = 0, i, different = 0;
    uint32_t first_ip = 0, ip;
    uint16_t port, first_port = 0;
    memset(priv, 0x33, sizeof(priv));
    priv[31] = 0x40;
    CHECK_EQ_INT(exteria_warp_parse_registration(good_answer, strlen(good_answer), priv, &id), EXTERIA_OK);
    CHECK_EQ_INT(exteria_warp_wg_config(&id, &profile, &cfg), EXTERIA_OK);
    CHECK_EQ_INT(cfg.junk_count, 4);
    CHECK_EQ_INT(cfg.junk_min, 40);
    CHECK_EQ_INT(cfg.junk_max, 70);
    CHECK_EQ_INT(cfg.has_reserved, 1);
    CHECK_MEM(cfg.private_key, id.private_key, 32);
    CHECK_MEM(cfg.peer_public, id.peer_public, 32);
    CHECK_EQ_INT(cfg.h1 | cfg.h2 | cfg.h4 | cfg.s1 | cfg.s2, 0);
    CHECK_EQ_INT(exteria_wg_signature_render(cfg.signature[0], 0, blob, sizeof(blob), &n), EXTERIA_OK);
    CHECK(n > 300 && n < 400);
    CHECK_MEM(blob, "INVITE sip:bob@biloxi.com SIP/2.0\r\n", 35);
    CHECK_MEM(blob + n - 4, "\r\n\r\n", 4);
    CHECK_EQ_INT(exteria_wg_signature_render(cfg.signature[1], 0, blob, sizeof(blob), &n), EXTERIA_OK);
    CHECK_MEM(blob, "SIP/2.0 100 Trying\r\n", 20);
    CHECK_MEM(blob + n - 4, "\r\n\r\n", 4);
    CHECK_EQ_INT(exteria_warp_wg_config(NULL, &profile, &cfg), EXTERIA_E_ARG);

    for (i = 0; i < 4; ++i) {
        CHECK_EQ_INT(exteria_warp_endpoint(&id, (unsigned)i, &ip, &port), EXTERIA_OK);
        CHECK_EQ_INT(ip, id.endpoint_ip);
        CHECK_EQ_INT(port, id.ports[i]);
    }
    /* later attempts leave the account's endpoint for other WARP addresses, and differ from one another */
    for (i = 4; i < 40; ++i) {
        size_t k, known = 0;
        CHECK_EQ_INT(exteria_warp_endpoint(&id, (unsigned)i, &ip, &port), EXTERIA_OK);
        CHECK(ip != 0);
        CHECK(port >= 500 && port <= 8886);
        for (k = 0; k < 3; ++k) {
            static const uint32_t first_octets[] = {162, 188, 8};
            if ((ip >> 24) == first_octets[k]) known = 1;
        }
        CHECK(known);
        CHECK((ip & 0xFF) >= 1 && (ip & 0xFF) <= 10);
        if (i == 4) {
            first_ip = ip;
            first_port = port;
        } else if (ip != first_ip || port != first_port) {
            ++different;
        }
    }
    CHECK(different > 20);
    id.endpoint_ip = 0;
    CHECK_EQ_INT(exteria_warp_endpoint(&id, 0, &ip, &port), EXTERIA_E_ARG);
}

int main(void) {
    base64_vectors();
    base64_rejections();
    ipv4_parsing();
    key_generation();
    registration_body();
    registration_parse();
    profile_and_endpoints();
    return test_finish("test_shiro_warp");
}
