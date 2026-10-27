#include "test_util.h"
#include "exteria_proxy.h"

static const uint8_t SECRET[16] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};

static exteria_tg_link link_of(const char *url) {
    exteria_tg_link l;
    CHECK_EQ_INT(exteria_tg_link_parse(url, &l), EXTERIA_OK);
    return l;
}

static void test_secret(void) {
    uint8_t secret[16], padded = 9;
    /* hex, plain and padded */
    CHECK_EQ_INT(exteria_proxy_secret_decode("000102030405060708090a0b0c0d0e0f", secret, &padded), EXTERIA_OK);
    CHECK(memcmp(secret, SECRET, 16) == 0);
    CHECK_EQ_INT(padded, 0);
    CHECK_EQ_INT(exteria_proxy_secret_decode("000102030405060708090A0B0C0D0E0F", secret, &padded), EXTERIA_OK);
    CHECK(memcmp(secret, SECRET, 16) == 0);
    CHECK_EQ_INT(exteria_proxy_secret_decode("dd000102030405060708090a0b0c0d0e0f", secret, &padded), EXTERIA_OK);
    CHECK(memcmp(secret, SECRET, 16) == 0);
    CHECK_EQ_INT(padded, 1);
    /* base64url, with and without padding and in the standard alphabet */
    CHECK_EQ_INT(exteria_proxy_secret_decode("AAECAwQFBgcICQoLDA0ODw", secret, &padded), EXTERIA_OK);
    CHECK(memcmp(secret, SECRET, 16) == 0);
    CHECK_EQ_INT(padded, 0);
    CHECK_EQ_INT(exteria_proxy_secret_decode("AAECAwQFBgcICQoLDA0ODw==", secret, &padded), EXTERIA_OK);
    CHECK_EQ_INT(exteria_proxy_secret_decode("3QABAgMEBQYHCAkKCwwNDg8", secret, &padded), EXTERIA_OK);
    CHECK(memcmp(secret, SECRET, 16) == 0);
    CHECK_EQ_INT(padded, 1);
    /* the fake tls secrets are not spoken here, and are told apart from garbage */
    CHECK_EQ_INT(exteria_proxy_secret_decode("ee000102030405060708090a0b0c0d0e0f6578616d706c652e636f6d", secret, &padded), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(padded, 0);
    CHECK_EQ_INT(exteria_proxy_secret_decode("7gABAgMEBQYHCAkKCwwNDg9leGFtcGxlLmNvbQ", secret, &padded), EXTERIA_E_UNSUPPORTED);
    /* what is no secret */
    CHECK_EQ_INT(exteria_proxy_secret_decode("", secret, &padded), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_proxy_secret_decode("00010203", secret, &padded), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_proxy_secret_decode("000102030405060708090a0b0c0d0e", secret, &padded), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_proxy_secret_decode("ab000102030405060708090a0b0c0d0e0f", secret, &padded), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_proxy_secret_decode("not a secret!", secret, &padded), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_proxy_secret_decode("AAECAwQFBgcICQoLDA0OD", secret, &padded), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_proxy_secret_decode(NULL, secret, &padded), EXTERIA_E_ARG);
    {
        char long_text[400];
        memset(long_text, 'a', sizeof(long_text));
        long_text[399] = 0;
        CHECK_EQ_INT(exteria_proxy_secret_decode(long_text, secret, &padded), EXTERIA_E_MALFORMED);
    }
}

static void test_server(void) {
    CHECK(exteria_proxy_server_valid("127.0.0.1"));
    CHECK(exteria_proxy_server_valid("proxy.example.com"));
    CHECK(exteria_proxy_server_valid("a-b.example"));
    CHECK(!exteria_proxy_server_valid(""));
    CHECK(!exteria_proxy_server_valid("."));
    CHECK(!exteria_proxy_server_valid("a..b"));
    CHECK(!exteria_proxy_server_valid(".a"));
    CHECK(!exteria_proxy_server_valid("a."));
    CHECK(!exteria_proxy_server_valid("-a.example"));
    CHECK(!exteria_proxy_server_valid("a b"));
    CHECK(!exteria_proxy_server_valid("a/b"));
    CHECK(!exteria_proxy_server_valid("a:80"));
    CHECK(!exteria_proxy_server_valid(NULL));
}

static void test_links(void) {
    exteria_tg_link l = link_of("tg://proxy?server=127.0.0.1&port=1082&secret=dd000102030405060708090a0b0c0d0e0f");
    exteria_proxy p;
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PROXY);
    CHECK(!strcmp(l.proxy_server, "127.0.0.1"));
    CHECK_EQ_INT(l.proxy_port, 1082);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &p), EXTERIA_OK);
    CHECK_EQ_INT(p.kind, EXTERIA_PROXY_MTPROTO);
    CHECK_EQ_INT(p.padded, 1);
    CHECK(memcmp(p.secret, SECRET, 16) == 0);
    /* the web forms, and the order of the fields */
    l = link_of("https://t.me/proxy?port=443&secret=000102030405060708090a0b0c0d0e0f&server=proxy.example.com");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PROXY);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &p), EXTERIA_OK);
    CHECK(!strcmp(p.server, "proxy.example.com"));
    CHECK_EQ_INT(p.port, 443);
    CHECK_EQ_INT(p.padded, 0);
    l = link_of("http://telegram.me/proxy?server=a.example&port=1&secret=AAECAwQFBgcICQoLDA0ODw#frag");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PROXY);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &p), EXTERIA_OK);
    /* escapes in the values, and a link of the base64url kind that carries marks a query would mangle */
    l = link_of("tg://proxy?server=p%2Eexample&port=65535&secret=3QABAgMEBQYHCAkKCwwNDg8");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PROXY);
    CHECK(!strcmp(l.proxy_server, "p.example"));
    CHECK_EQ_INT(l.proxy_port, 65535);
    /* socks, with and without credentials */
    l = link_of("tg://socks?server=10.0.0.2&port=1080&user=me%20x&pass=p%40ss");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_SOCKS);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &p), EXTERIA_OK);
    CHECK_EQ_INT(p.kind, EXTERIA_PROXY_SOCKS5);
    CHECK(!strcmp(p.user, "me x"));
    CHECK(!strcmp(p.password, "p@ss"));
    l = link_of("https://t.me/socks?server=10.0.0.2&port=1080");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_SOCKS);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &p), EXTERIA_OK);
    CHECK(p.user[0] == 0);
    /* the fake tls proxy parses as a proxy link and is refused where the secret is read */
    l = link_of("tg://proxy?server=a.example&port=443&secret=ee000102030405060708090a0b0c0d0e0f6578616d706c652e636f6d");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PROXY);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &p), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(p.kind, 0);
    /* not a link this client can use: it stays an ordinary address */
    CHECK_EQ_INT(link_of("tg://proxy?server=a.example&port=443").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://proxy?server=a.example&port=443&secret=").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://proxy?port=443&secret=00").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://proxy?server=a.example&port=0&secret=00").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://proxy?server=a.example&port=65536&secret=00").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://proxy?server=a.example&port=x&secret=00").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://proxy?server=a%20b&port=1&secret=00").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://proxy?server=a/b&port=1&secret=00").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://socks?server=a.example").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/proxy").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/proxy/extra?server=a.example&port=1&secret=00").kind, EXTERIA_LINK_PROXY);
    /* a name that is a user is still a user */
    CHECK_EQ_INT(link_of("https://t.me/proxybot").kind, EXTERIA_LINK_PEER);
    {
        exteria_tg_link other = link_of("https://t.me/durov");
        CHECK_EQ_INT(exteria_proxy_from_link(&other, &p), EXTERIA_E_ARG);
    }
}

static void test_link_out(void) {
    exteria_proxy p, back;
    exteria_tg_link l;
    char out[512], small[20];
    memset(&p, 0, sizeof(p));
    p.kind = EXTERIA_PROXY_MTPROTO;
    strcpy(p.server, "127.0.0.1");
    p.port = 1082;
    memcpy(p.secret, SECRET, 16);
    p.padded = 1;
    CHECK_EQ_INT(exteria_proxy_link(&p, out, sizeof(out)), EXTERIA_OK);
    CHECK(!strcmp(out, "tg://proxy?server=127.0.0.1&port=1082&secret=dd000102030405060708090a0b0c0d0e0f"));
    l = link_of(out);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &back), EXTERIA_OK);
    CHECK(memcmp(&back, &p, sizeof(p)) == 0);
    p.padded = 0;
    CHECK_EQ_INT(exteria_proxy_link(&p, out, sizeof(out)), EXTERIA_OK);
    CHECK(strstr(out, "&secret=0001") != NULL);
    memset(&p, 0, sizeof(p));
    p.kind = EXTERIA_PROXY_SOCKS5;
    strcpy(p.server, "h.example");
    p.port = 1080;
    strcpy(p.user, "me x");
    strcpy(p.password, "p@ss&");
    CHECK_EQ_INT(exteria_proxy_link(&p, out, sizeof(out)), EXTERIA_OK);
    CHECK(!strcmp(out, "tg://socks?server=h.example&port=1080&user=me%20x&pass=p%40ss%26"));
    l = link_of(out);
    CHECK_EQ_INT(exteria_proxy_from_link(&l, &back), EXTERIA_OK);
    CHECK(!strcmp(back.user, "me x") && !strcmp(back.password, "p@ss&"));
    CHECK_EQ_INT(exteria_proxy_link(&p, small, sizeof(small)), EXTERIA_E_LIMIT);
    p.kind = 0;
    CHECK_EQ_INT(exteria_proxy_link(&p, out, sizeof(out)), EXTERIA_E_ARG);
}

int main(void) {
    test_secret();
    test_server();
    test_links();
    test_link_out();
    return test_finish("test_proxy");
}
