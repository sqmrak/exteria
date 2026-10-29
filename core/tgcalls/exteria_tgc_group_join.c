#include "exteria_tgc_group_join.h"

#include <string.h>
#include <arpa/inet.h>
#include "exteria_tgc_json.h"

static int read_string(const exteria_json *object, const char *key, char *out, size_t cap) {
    size_t len = 0;
    const char *value = exteria_json_string(exteria_json_get(object, key), &len);
    if (!value || !len || len >= cap || strlen(value) != len) return 0;
    memcpy(out, value, len + 1);
    return 1;
}

static int read_decimal(const exteria_json *object, const char *key, uint32_t max, uint32_t *out) {
    char value[16];
    uint32_t n = 0;
    size_t i;
    if (!read_string(object, key, value, sizeof(value))) return 0;
    for (i = 0; value[i]; ++i) {
        unsigned digit;
        if (value[i] < '0' || value[i] > '9') return 0;
        digit = (unsigned)(value[i] - '0');
        if (n > (max - digit) / 10) return 0;
        n = n * 10 + digit;
    }
    *out = n;
    return 1;
}

static int valid_fingerprint(const char *fingerprint) {
    size_t i;
    if (strlen(fingerprint) != 95) return 0;
    for (i = 0; i < 95; ++i) {
        char c = fingerprint[i];
        if (i % 3 == 2) {
            if (c != ':') return 0;
        } else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return 0;
    }
    return 1;
}

#define DEFAULT_OPUS_PAYLOAD 111
#define DEFAULT_AUDIO_LEVEL_EXT 1
#define AUDIO_LEVEL_URI "urn:ietf:params:rtp-hdrext:ssrc-audio-level"

static int ieq(const char *a, const char *b) {
    for (; *a && *b; ++a, ++b) {
        char x = *a, y = *b;
        if (x >= 'A' && x <= 'Z') x = (char)(x - 'A' + 'a');
        if (y >= 'A' && y <= 'Z') y = (char)(y - 'A' + 'a');
        if (x != y) return 0;
    }
    return *a == *b;
}

/* the ids the server picked for Opus and for the audio level extension; anything missing or out of range keeps the default */
static void read_audio_description(const exteria_json *root, exteria_tgc_group_transport *out) {
    const exteria_json *audio = exteria_json_get(root, "audio"), *list, *item;
    out->audio_payload_type = DEFAULT_OPUS_PAYLOAD;
    out->audio_level_ext = DEFAULT_AUDIO_LEVEL_EXT;
    if (exteria_json_kind(audio) != EXTERIA_JSON_OBJECT) return;
    list = exteria_json_get(audio, "payload-types");
    if (exteria_json_kind(list) == EXTERIA_JSON_ARRAY) {
        for (item = exteria_json_first(list); item; item = exteria_json_next(item)) {
            size_t len = 0;
            const char *name = exteria_json_string(exteria_json_get(item, "name"), &len);
            int64_t id = 0;
            if (name && ieq(name, "opus") && exteria_json_int(exteria_json_get(item, "id"), &id) == EXTERIA_OK && id > 0 && id < 128) {
                out->audio_payload_type = (uint8_t)id;
                break;
            }
        }
    }
    list = exteria_json_get(audio, "rtp-hdrexts");
    if (exteria_json_kind(list) == EXTERIA_JSON_ARRAY) {
        for (item = exteria_json_first(list); item; item = exteria_json_next(item)) {
            size_t len = 0;
            const char *uri = exteria_json_string(exteria_json_get(item, "uri"), &len);
            int64_t id = 0;
            if (uri && !strcmp(uri, AUDIO_LEVEL_URI) && exteria_json_int(exteria_json_get(item, "id"), &id) == EXTERIA_OK && id >= 1 && id <= 14) {
                out->audio_level_ext = (uint8_t)id;
                break;
            }
        }
    }
}

exteria_status exteria_tgc_group_transport_parse(const char *json, size_t len, exteria_tgc_group_transport *out) {
    exteria_tgc_group_transport result;
    exteria_json_doc *doc = NULL;
    const exteria_json *transport, *list, *item;
    exteria_status status;
    char hash[16], component[8];
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!json) return EXTERIA_E_ARG;
    memset(&result, 0, sizeof(result));
    status = exteria_json_parse(json, len, &doc);
    if (status != EXTERIA_OK) return status;
    status = EXTERIA_E_MALFORMED;
    transport = exteria_json_get(exteria_json_root(doc), "transport");
    if (exteria_json_kind(transport) != EXTERIA_JSON_OBJECT ||
        !read_string(transport, "ufrag", result.ufrag, sizeof(result.ufrag)) || strlen(result.ufrag) < 4 ||
        !read_string(transport, "pwd", result.pwd, sizeof(result.pwd)) || strlen(result.pwd) < 22) goto done;
    list = exteria_json_get(transport, "fingerprints");
    if (exteria_json_kind(list) != EXTERIA_JSON_ARRAY || exteria_json_count(list) != 1) goto done;
    item = exteria_json_first(list);
    if (!read_string(item, "hash", hash, sizeof(hash)) || strcmp(hash, "sha-256") ||
        !read_string(item, "fingerprint", result.fingerprint, sizeof(result.fingerprint)) || !valid_fingerprint(result.fingerprint) ||
        !read_string(item, "setup", result.setup, sizeof(result.setup))) goto done;
    list = exteria_json_get(transport, "candidates");
    if (exteria_json_kind(list) != EXTERIA_JSON_ARRAY) goto done;
    if (exteria_json_count(list) > EXTERIA_TGC_GROUP_CANDIDATES_MAX) { status = EXTERIA_E_LIMIT; goto done; }
    for (item = exteria_json_first(list); item; item = exteria_json_next(item)) {
        exteria_tgc_group_candidate *candidate = &result.candidates[result.candidate_count];
        uint32_t port;
        unsigned char address[16];
        if (!read_string(item, "ip", candidate->ip, sizeof(candidate->ip)) ||
            (inet_pton(AF_INET, candidate->ip, address) != 1 && inet_pton(AF_INET6, candidate->ip, address) != 1) ||
            !read_string(item, "protocol", candidate->protocol, sizeof(candidate->protocol)) ||
            !read_string(item, "type", candidate->type, sizeof(candidate->type)) ||
            !read_string(item, "component", component, sizeof(component)) || strcmp(component, "1") ||
            !read_decimal(item, "port", 65535, &port) || !port ||
            !read_decimal(item, "priority", UINT32_MAX, &candidate->priority)) goto done;
        candidate->port = (uint16_t)port;
        ++result.candidate_count;
    }
    read_audio_description(exteria_json_root(doc), &result);
    *out = result;
    status = EXTERIA_OK;
done:
    exteria_json_free(doc);
    return status;
}

exteria_status exteria_tgc_group_join_json(uint32_t audio_ssrc, const char *ufrag, const char *pwd,
                                          const char *fingerprint, char *out, size_t cap, size_t *len) {
    exteria_json_out json;
    int64_t signed_ssrc;
    if (len) *len = 0;
    if (out && cap) out[0] = 0;
    if (!audio_ssrc || !ufrag || !pwd || !fingerprint || !out || !cap || !len) return EXTERIA_E_ARG;
    if (strlen(ufrag) < 4 || strlen(ufrag) >= 64 || strlen(pwd) < 22 || strlen(pwd) >= 128 || !valid_fingerprint(fingerprint))
        return EXTERIA_E_ARG;
    signed_ssrc = audio_ssrc <= INT32_MAX ? (int64_t)audio_ssrc : (int64_t)audio_ssrc - 4294967296LL;
    exteria_json_out_init(&json, out, cap);
    exteria_json_out_object(&json);
    exteria_json_out_key(&json, "ssrc"); exteria_json_out_int(&json, signed_ssrc);
    exteria_json_out_key(&json, "ufrag"); exteria_json_out_string(&json, ufrag);
    exteria_json_out_key(&json, "pwd"); exteria_json_out_string(&json, pwd);
    exteria_json_out_key(&json, "fingerprints"); exteria_json_out_array(&json);
    exteria_json_out_object(&json);
    exteria_json_out_key(&json, "hash"); exteria_json_out_string(&json, "sha-256");
    exteria_json_out_key(&json, "fingerprint"); exteria_json_out_string(&json, fingerprint);
    exteria_json_out_key(&json, "setup"); exteria_json_out_string(&json, "passive");
    exteria_json_out_end(&json);
    exteria_json_out_end(&json);
    exteria_json_out_end(&json);
    return exteria_json_out_finish(&json, len);
}
