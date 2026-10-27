#include "exteria_release.h"
#include "test_util.h"

static void versions(void) {
    static const struct { const char *remote, *installed; int newer; } cases[] = {
        {"v1.1.0", "1.0.0-stable", 1},
        {"v1.0.0-stable", "1.0.0-stable", 0},
        {"1.0.0-stable", "1.0.0-canary", 1},
        {"1.0.0", "1.0.1-canary", 0},
        {"v2.0", "1.99.0", 1},
        {"1.0.0", "1.0", 0},
        {"1.0.0-canary", "1.0.0-stable", 0}
    };
    size_t i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        int newer = -1;
        CHECK_EQ_INT(exteria_release_compare(cases[i].remote, cases[i].installed, &newer), EXTERIA_OK);
        CHECK_EQ_INT(newer, cases[i].newer);
    }
    {
        int newer = 5;
        CHECK_EQ_INT(exteria_release_compare("v1.0.0-rc1", "1.0.0", &newer), EXTERIA_E_UNSUPPORTED);
        CHECK_EQ_INT(newer, 0);
        CHECK_EQ_INT(exteria_release_compare("1..0", "1.0", &newer), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(exteria_release_compare("999999999999.0", "1.0", &newer), EXTERIA_E_LIMIT);
    }
}

static void releases(void) {
    static const char valid[] = "{\"tag_name\":\"v1.2.3\",\"body\":\"fixes\\nnew\",\"draft\":false,\"prerelease\":false}";
    static const char prerelease[] = "{\"tag_name\":\"v1.2.3\",\"body\":null,\"draft\":false,\"prerelease\":true}";
    static const char nullbody[] = "{\"tag_name\":\"v1.2.3\",\"body\":null,\"draft\":false,\"prerelease\":false}";
    static const char malformed[] = "{\"tag_name\":\"v1.2.3\",\"body\":42,\"draft\":false,\"prerelease\":false}";
    exteria_release release;
    CHECK_EQ_INT(exteria_release_parse(valid, sizeof(valid) - 1, &release), EXTERIA_OK);
    CHECK(!strcmp(release.tag, "v1.2.3"));
    CHECK(!strcmp(release.body, "fixes\nnew"));
    CHECK_EQ_INT(exteria_release_parse(prerelease, sizeof(prerelease) - 1, &release), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(exteria_release_parse(nullbody, sizeof(nullbody) - 1, &release), EXTERIA_OK);
    CHECK(!release.body[0]);
    CHECK_EQ_INT(exteria_release_parse(malformed, sizeof(malformed) - 1, &release), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_release_parse(valid, sizeof(valid) - 2, &release), EXTERIA_E_MALFORMED);
}

static void assets(void) {
    static const char P[] = "https://github.com/sqmrak/exteria/releases/download/v1.2.3/";
    char json[2048];
    exteria_release release;
    int n;
    n = snprintf(json, sizeof(json),
        "{\"tag_name\":\"v1.2.3\",\"body\":\"x\",\"draft\":false,\"prerelease\":false,\"assets\":["
        "{\"name\":\"notes.txt\",\"size\":3,\"browser_download_url\":\"%snotes.txt\"},"
        "{\"name\":\"Exteria-v1.2.3.ipa.sha256\",\"size\":90,\"browser_download_url\":\"%sExteria-v1.2.3.ipa.sha256\"},"
        "{\"name\":\"Exteria-v1.2.3.ipa\",\"size\":33086265,\"uploader\":{\"login\":\"x\"},\"browser_download_url\":\"%sExteria-v1.2.3.ipa\"}]}", P, P, P);
    CHECK(n > 0 && (size_t)n < sizeof(json));
    CHECK_EQ_INT(exteria_release_parse(json, (size_t)n, &release), EXTERIA_OK);
    CHECK(!strcmp(release.ipa_url, "https://github.com/sqmrak/exteria/releases/download/v1.2.3/Exteria-v1.2.3.ipa"));
    CHECK(!strcmp(release.sha_url, "https://github.com/sqmrak/exteria/releases/download/v1.2.3/Exteria-v1.2.3.ipa.sha256"));
    CHECK_EQ_INT(release.ipa_size, 33086265);

    /* a tag without the v still names the asset with one */
    n = snprintf(json, sizeof(json),
        "{\"tag_name\":\"1.2.3\",\"body\":null,\"draft\":false,\"prerelease\":false,\"assets\":["
        "{\"name\":\"Exteria-v1.2.3.ipa\",\"size\":10,\"browser_download_url\":\"%sExteria-v1.2.3.ipa\"}]}", P);
    CHECK_EQ_INT(exteria_release_parse(json, (size_t)n, &release), EXTERIA_OK);
    CHECK(release.ipa_url[0] != 0);
    CHECK(release.sha_url[0] == 0);

    /* a foreign host, plain http, a wrong name, a missing size and no assets at all leave nothing to install */
    {
        static const char *const bad[] = {
            "\"name\":\"Exteria-v1.2.3.ipa\",\"size\":10,\"browser_download_url\":\"https://evil.example/releases/download/v1.2.3/Exteria-v1.2.3.ipa\"",
            "\"name\":\"Exteria-v1.2.3.ipa\",\"size\":10,\"browser_download_url\":\"http://github.com/sqmrak/exteria/releases/download/v1.2.3/Exteria-v1.2.3.ipa\"",
            "\"name\":\"Exteria-v1.2.4.ipa\",\"size\":10,\"browser_download_url\":\"https://github.com/sqmrak/exteria/releases/download/v1.2.3/Exteria-v1.2.4.ipa\"",
            "\"name\":\"Exteria-v1.2.3.ipa\",\"browser_download_url\":\"https://github.com/sqmrak/exteria/releases/download/v1.2.3/Exteria-v1.2.3.ipa\"",
            "\"name\":\"Exteria-v1.2.3.ipa\",\"size\":0,\"browser_download_url\":\"https://github.com/sqmrak/exteria/releases/download/v1.2.3/Exteria-v1.2.3.ipa\"",
            "\"name\":\"Exteria-v1.2.3.ipa\",\"size\":10,\"browser_download_url\":\"https://github.com/sqmrak/exteria/releases/download/v1.2.3/a b\"",
            "\"name\":\"Exteria-v1.2.3.ipa\",\"size\":10,\"browser_download_url\":42"
        };
        size_t i;
        for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
            n = snprintf(json, sizeof(json), "{\"tag_name\":\"v1.2.3\",\"body\":null,\"draft\":false,\"prerelease\":false,\"assets\":[{%s}]}", bad[i]);
            CHECK_EQ_INT(exteria_release_parse(json, (size_t)n, &release), EXTERIA_OK);
            CHECK(release.ipa_url[0] == 0);
        }
        static const char none[] = "{\"tag_name\":\"v1.2.3\",\"body\":null,\"draft\":false,\"prerelease\":false}";
        CHECK_EQ_INT(exteria_release_parse(none, sizeof(none) - 1, &release), EXTERIA_OK);
        CHECK(release.ipa_url[0] == 0 && release.sha_url[0] == 0 && release.ipa_size == 0);
    }
}

static void urls(void) {
    char host[EXTERIA_RELEASE_HOST_MAX], path[2048];
    static const struct { const char *url; exteria_status status; const char *host, *path; } cases[] = {
        {"https://github.com/sqmrak/exteria/releases/download/v1/x.ipa", EXTERIA_OK, "github.com", "/sqmrak/exteria/releases/download/v1/x.ipa"},
        {"https://release-assets.githubusercontent.com/a/b?sig=AbC%3D&se=2026", EXTERIA_OK, "release-assets.githubusercontent.com", "/a/b?sig=AbC%3D&se=2026"},
        {"https://objects.githubusercontent.com/x", EXTERIA_OK, "objects.githubusercontent.com", "/x"},
        {"http://github.com/x", EXTERIA_E_SECURITY, "", ""},
        {"/relative/path", EXTERIA_E_SECURITY, "", ""},
        {"https://github.com", EXTERIA_E_SECURITY, "", ""},
        {"https://evil.example/x", EXTERIA_E_SECURITY, "", ""},
        {"https://github.com.evil.example/x", EXTERIA_E_SECURITY, "", ""},
        {"https://evilgithub.com/x", EXTERIA_E_SECURITY, "", ""},
        {"https://a.b.githubusercontent.com/x", EXTERIA_E_SECURITY, "", ""},
        {"https://githubusercontent.com/x", EXTERIA_E_SECURITY, "", ""},
        {"https://.githubusercontent.com/x", EXTERIA_E_SECURITY, "", ""},
        {"https://user@github.com/x", EXTERIA_E_SECURITY, "", ""},
        {"https://github.com:8443/x", EXTERIA_E_SECURITY, "", ""},
        {"https://GitHub.com/x", EXTERIA_E_SECURITY, "", ""},
        {"https://github.com/a b", EXTERIA_E_SECURITY, "", ""},
        {"https://github.com/a\r\nHost: x", EXTERIA_E_SECURITY, "", ""},
        {"", EXTERIA_E_SECURITY, "", ""}
    };
    size_t i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        CHECK_EQ_INT(exteria_release_url_split(cases[i].url, host, sizeof(host), path, sizeof(path)), cases[i].status);
        if (cases[i].status == EXTERIA_OK) {
            CHECK(!strcmp(host, cases[i].host));
            CHECK(!strcmp(path, cases[i].path));
        } else {
            CHECK(host[0] == 0);
        }
    }
    {
        char longurl[4200], small[8];
        memcpy(longurl, "https://github.com/", 19);
        memset(longurl + 19, 'a', 3000);
        longurl[3019] = 0;
        CHECK_EQ_INT(exteria_release_url_split(longurl, host, sizeof(host), path, sizeof(path)), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(exteria_release_url_split("https://github.com/x", host, sizeof(host), small, 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_release_url_split("https://github.com/long-path", host, sizeof(host), small, sizeof(small)), EXTERIA_E_SECURITY);
        CHECK_EQ_INT(exteria_release_url_split(NULL, host, sizeof(host), path, sizeof(path)), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_release_url_split("https://github.com/x", host, 4, path, sizeof(path)), EXTERIA_E_ARG);
    }
}

static void digests(void) {
    static const char hex[] = "00112233445566778899aabbccddeeff0123456789ABCDEFfedcba9876543210";
    static const uint8_t want[32] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
                                     0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10};
    uint8_t out[32];
    char text[160];
    size_t n;
    CHECK_EQ_INT(exteria_release_parse_sha256(hex, 64, out), EXTERIA_OK);
    CHECK_MEM(out, want, 32);
    n = (size_t)snprintf(text, sizeof(text), "%s  Exteria-v1.2.3.ipa\n", hex);
    CHECK_EQ_INT(exteria_release_parse_sha256(text, n, out), EXTERIA_OK);
    CHECK_MEM(out, want, 32);
    n = (size_t)snprintf(text, sizeof(text), "%s\r\n", hex);
    CHECK_EQ_INT(exteria_release_parse_sha256(text, n, out), EXTERIA_OK);
    CHECK_EQ_INT(exteria_release_parse_sha256(hex, 63, out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_release_parse_sha256("", 0, out), EXTERIA_E_MALFORMED);
    n = (size_t)snprintf(text, sizeof(text), "%s0", hex);
    CHECK_EQ_INT(exteria_release_parse_sha256(text, n, out), EXTERIA_E_MALFORMED);
    n = (size_t)snprintf(text, sizeof(text), "g%s", hex + 1);
    CHECK_EQ_INT(exteria_release_parse_sha256(text, n, out), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_release_parse_sha256(NULL, 64, out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_release_parse_sha256(hex, 64, NULL), EXTERIA_E_ARG);
}

int main(void) {
    digests();
    urls();
    versions();
    releases();
    assets();
    return test_finish("test_release");
}
