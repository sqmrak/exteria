#include <stdio.h>
#include <string.h>

#include "exteria_tgc_group_join.h"
#include "exteria_tgc_json.h"
#include "test_util.h"

int main(void) {
    const char *fingerprint = "AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA";
    char out[512];
    size_t len = 0, string_len = 0;
    int64_t ssrc = 0;
    exteria_json_doc *doc = NULL;
    const exteria_json *root, *fp;
    CHECK_EQ_INT(exteria_tgc_group_join_json(UINT32_MAX, "abcd", "abcdefghijklmnopqrstuv", fingerprint, out, sizeof(out), &len), EXTERIA_OK);
    CHECK_EQ_INT(exteria_json_parse(out, len, &doc), EXTERIA_OK);
    root = exteria_json_root(doc);
    CHECK_EQ_INT(exteria_json_int(exteria_json_get(root, "ssrc"), &ssrc), EXTERIA_OK);
    CHECK_EQ_INT(ssrc, -1);
    CHECK(!strcmp(exteria_json_string(exteria_json_get(root, "ufrag"), &string_len), "abcd"));
    fp = exteria_json_first(exteria_json_get(root, "fingerprints"));
    CHECK(!strcmp(exteria_json_string(exteria_json_get(fp, "fingerprint"), &string_len), fingerprint));
    CHECK(!strcmp(exteria_json_string(exteria_json_get(fp, "setup"), &string_len), "passive"));
    exteria_json_free(doc);
    CHECK_EQ_INT(exteria_tgc_group_join_json(0, "abcd", "abcdefghijklmnopqrstuv", fingerprint, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_group_join_json(1, "abc", "abcdefghijklmnopqrstuv", fingerprint, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_group_join_json(1, "abcd", "short", fingerprint, out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_group_join_json(1, "abcd", "abcdefghijklmnopqrstuv", "bad", out, sizeof(out), &len), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_group_join_json(1, "abcd", "abcdefghijklmnopqrstuv", fingerprint, out, 8, &len), EXTERIA_E_LIMIT);
    {
        const char *response = "{\"transport\":{\"ufrag\":\"abcd\",\"pwd\":\"abcdefghijklmnopqrstuv\","
            "\"fingerprints\":[{\"hash\":\"sha-256\",\"setup\":\"active\",\"fingerprint\":\"AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA\"}],"
            "\"candidates\":[{\"ip\":\"192.0.2.1\",\"port\":\"443\",\"priority\":\"4294967295\",\"component\":\"1\",\"protocol\":\"udp\",\"type\":\"host\"}]}}";
        exteria_tgc_group_transport transport;
        CHECK_EQ_INT(exteria_tgc_group_transport_parse(response, strlen(response), &transport), EXTERIA_OK);
        CHECK_EQ_INT(transport.candidate_count, 1);
        CHECK_EQ_INT(transport.candidates[0].port, 443);
        CHECK(transport.candidates[0].priority == UINT32_MAX);
        CHECK(!strcmp(transport.fingerprint, fingerprint));
        CHECK_EQ_INT(transport.audio_payload_type, 111);
        CHECK_EQ_INT(transport.audio_level_ext, 1);
        {
            /* the ids the server names replace the defaults, and a bad one leaves them */
            const char *named = "{\"audio\":{\"payload-types\":[{\"id\":100,\"name\":\"red\"},{\"id\":109,\"name\":\"Opus\"}],"
                "\"rtp-hdrexts\":[{\"id\":2,\"uri\":\"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\"},"
                "{\"id\":5,\"uri\":\"urn:ietf:params:rtp-hdrext:ssrc-audio-level\"}]},";
            char text[2048];
            snprintf(text, sizeof(text), "%s%s", named, strstr(response, "\"transport\""));
            CHECK_EQ_INT(exteria_tgc_group_transport_parse(text, strlen(text), &transport), EXTERIA_OK);
            CHECK_EQ_INT(transport.audio_payload_type, 109);
            CHECK_EQ_INT(transport.audio_level_ext, 5);
            snprintf(text, sizeof(text), "{\"audio\":{\"payload-types\":[{\"id\":900,\"name\":\"opus\"}],\"rtp-hdrexts\":[{\"id\":15,\"uri\":\"urn:ietf:params:rtp-hdrext:ssrc-audio-level\"}]},%s",
                     strstr(response, "\"transport\""));
            CHECK_EQ_INT(exteria_tgc_group_transport_parse(text, strlen(text), &transport), EXTERIA_OK);
            CHECK_EQ_INT(transport.audio_payload_type, 111);
            CHECK_EQ_INT(transport.audio_level_ext, 1);
        }
        CHECK_EQ_INT(exteria_tgc_group_transport_parse("{}", 2, &transport), EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(transport.candidate_count, 0);
        CHECK_EQ_INT(exteria_tgc_group_transport_parse("{", 1, &transport), EXTERIA_E_MALFORMED);
        {
            char bad[1024];
            char *port;
            CHECK(strlen(response) < sizeof(bad));
            strcpy(bad, response);
            port = strstr(bad, "\"port\":\"443\"");
            CHECK(port != NULL);
            memcpy(port + strlen("\"port\":\""), "999", 3);
            CHECK_EQ_INT(exteria_tgc_group_transport_parse(bad, strlen(bad), &transport), EXTERIA_OK);
            memcpy(port + strlen("\"port\":\""), "-43", 3);
            CHECK_EQ_INT(exteria_tgc_group_transport_parse(bad, strlen(bad), &transport), EXTERIA_E_MALFORMED);
            CHECK_EQ_INT(transport.candidate_count, 0);
        }
    }
    return test_finish("test_tgc_group_join");
}
