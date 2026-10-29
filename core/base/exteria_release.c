#include "exteria_release.h"
#include "exteria_tgc_json.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct release_version { uint32_t parts[4]; int stable; } release_version;

static exteria_status parse_version(const char *text, release_version *out) {
    size_t count = 0;
    const char *p = text;
    memset(out, 0, sizeof(*out));
    if (!p) return EXTERIA_E_ARG;
    if (*p == 'v' || *p == 'V') ++p;
    do {
        uint32_t number = 0;
        if (count == 4 || *p < '0' || *p > '9') return EXTERIA_E_MALFORMED;
        do {
            unsigned digit = (unsigned)(*p++ - '0');
            if (number > (UINT32_MAX - digit) / 10u) return EXTERIA_E_LIMIT;
            number = number * 10u + digit;
        } while (*p >= '0' && *p <= '9');
        out->parts[count++] = number;
        if (*p != '.') break;
        ++p;
    } while (1);
    if (count < 2) return EXTERIA_E_MALFORMED;
    if (!*p || strcmp(p, "-stable") == 0) out->stable = 1;
    else if (strcmp(p, "-canary") != 0) return EXTERIA_E_UNSUPPORTED;
    return EXTERIA_OK;
}

exteria_status exteria_release_compare(const char *remote, const char *installed, int *newer) {
    release_version a, b;
    exteria_status status;
    size_t i;
    if (newer) *newer = 0;
    if (!remote || !installed || !newer) return EXTERIA_E_ARG;
    status = parse_version(remote, &a);
    if (status == EXTERIA_OK) status = parse_version(installed, &b);
    if (status != EXTERIA_OK) return status;
    for (i = 0; i < 4; ++i) {
        if (a.parts[i] != b.parts[i]) { *newer = a.parts[i] > b.parts[i]; return EXTERIA_OK; }
    }
    *newer = a.stable > b.stable;
    return EXTERIA_OK;
}

static int host_is_github(const char *host) {
    size_t len = strlen(host), suffix = sizeof(".githubusercontent.com") - 1;
    if (!strcmp(host, "github.com")) return 1;
    /* the cdn names change (objects, release-assets), so any single label under githubusercontent.com is taken */
    if (len > suffix && !strcmp(host + len - suffix, ".githubusercontent.com")) {
        size_t i;
        for (i = 0; i < len - suffix; ++i) {
            if (host[i] == '.') return 0;
        }
        return 1;
    }
    return 0;
}

exteria_status exteria_release_url_split(const char *url, char *host, size_t host_cap, char *path, size_t path_cap) {
    static const char scheme[] = "https://";
    const char *start, *slash;
    size_t host_len, path_len, i;
    if (host && host_cap) host[0] = 0;
    if (path && path_cap) path[0] = 0;
    if (!url || !host || !path || host_cap < EXTERIA_RELEASE_HOST_MAX || path_cap < 2) return EXTERIA_E_ARG;
    if (strncmp(url, scheme, sizeof(scheme) - 1)) return EXTERIA_E_SECURITY;
    start = url + sizeof(scheme) - 1;
    slash = strchr(start, '/');
    if (!slash) return EXTERIA_E_SECURITY;
    host_len = (size_t)(slash - start);
    path_len = strlen(slash);
    if (host_len == 0 || host_len >= EXTERIA_RELEASE_HOST_MAX || path_len >= path_cap || path_len >= 2048) return EXTERIA_E_SECURITY;
    for (i = 0; i < host_len; ++i) {
        char c = start[i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.')) return EXTERIA_E_SECURITY;
    }
    for (i = 0; i < path_len; ++i) {
        if ((unsigned char)slash[i] < 0x21 || (unsigned char)slash[i] > 0x7E) return EXTERIA_E_SECURITY;
    }
    memcpy(host, start, host_len);
    host[host_len] = 0;
    if (!host_is_github(host)) {
        host[0] = 0;
        return EXTERIA_E_SECURITY;
    }
    memcpy(path, slash, path_len + 1);
    return EXTERIA_OK;
}

/* the url of the asset with this name, copied only when it is https from the project's own download path */
static void find_asset(const exteria_json *assets, const char *name, char *url, size_t url_cap, uint64_t *size) {
    const exteria_json *asset;
    size_t name_len = strlen(name), prefix_len = strlen(EXTERIA_RELEASE_DOWNLOAD_PREFIX);
    if (exteria_json_kind(assets) != EXTERIA_JSON_ARRAY) return;
    for (asset = exteria_json_first(assets); asset; asset = exteria_json_next(asset)) {
        size_t found_len = 0, link_len = 0, i;
        const char *found = exteria_json_string(exteria_json_get(asset, "name"), &found_len);
        const char *link = exteria_json_string(exteria_json_get(asset, "browser_download_url"), &link_len);
        int64_t bytes = 0;
        if (!found || found_len != name_len || memcmp(found, name, name_len) || !link) continue;
        if (link_len <= prefix_len || link_len >= url_cap || memcmp(link, EXTERIA_RELEASE_DOWNLOAD_PREFIX, prefix_len)) return;
        for (i = 0; i < link_len; ++i) {
            if ((unsigned char)link[i] < 0x21 || (unsigned char)link[i] > 0x7E) return;
        }
        memcpy(url, link, link_len);
        url[link_len] = 0;
        if (size) {
            if (exteria_json_int(exteria_json_get(asset, "size"), &bytes) != EXTERIA_OK || bytes <= 0) url[0] = 0;
            else *size = (uint64_t)bytes;
        }
        return;
    }
}

exteria_status exteria_release_parse_sha256(const char *text, size_t length, uint8_t out[32]) {
    size_t i;
    if (out) memset(out, 0, 32);
    if (!text || !out) return EXTERIA_E_ARG;
    if (length < 64) return EXTERIA_E_MALFORMED;
    for (i = 0; i < 64; ++i) {
        char c = text[i];
        unsigned value;
        if (c >= '0' && c <= '9') value = (unsigned)(c - '0');
        else if (c >= 'a' && c <= 'f') value = (unsigned)(c - 'a') + 10u;
        else if (c >= 'A' && c <= 'F') value = (unsigned)(c - 'A') + 10u;
        else {
            memset(out, 0, 32);
            return EXTERIA_E_MALFORMED;
        }
        if (i % 2 == 0) out[i / 2] = (uint8_t)(value << 4);
        else out[i / 2] = (uint8_t)(out[i / 2] | value);
    }
    /* a digest longer than 64 digits, or one with something glued to it, is some other hash or a damaged file */
    if (length > 64 && text[64] != ' ' && text[64] != '\t' && text[64] != '\n' && text[64] != '\r') {
        memset(out, 0, 32);
        return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

static int header_name_is(const char *line, const char *name) {
    size_t i;
    for (i = 0; name[i]; ++i) {
        char c = line[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c != name[i]) return 0;
    }
    return 1;
}

exteria_status exteria_release_from_redirect(const char *headers, exteria_release *out) {
    static const char tag_path[] = "https://github.com/sqmrak/exteria/releases/tag/";
    const char *line, *value, *end;
    size_t tag_len, i;
    if (out) memset(out, 0, sizeof(*out));
    if (!headers || !out) return EXTERIA_E_ARG;
    for (line = headers; *line; line = strchr(line, '\n') ? strchr(line, '\n') + 1 : line + strlen(line)) {
        if (header_name_is(line, "location:")) break;
    }
    if (!*line) return EXTERIA_E_MALFORMED;
    value = line + strlen("location:");
    while (*value == ' ' || *value == '\t') ++value;
    if (strncmp(value, tag_path, sizeof(tag_path) - 1)) return EXTERIA_E_MALFORMED;
    value += sizeof(tag_path) - 1;
    for (end = value; *end && *end != '\r' && *end != '\n'; ++end);
    tag_len = (size_t)(end - value);
    if (!tag_len || tag_len >= sizeof(out->tag)) return EXTERIA_E_MALFORMED;
    for (i = 0; i < tag_len; ++i) {
        char c = value[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '.' || c == '-' || c == '_' || c == '+')) return EXTERIA_E_MALFORMED;
    }
    memcpy(out->tag, value, tag_len);
    out->tag[tag_len] = 0;
    {
        const char *version = out->tag[0] == 'v' || out->tag[0] == 'V' ? out->tag + 1 : out->tag;
        int n = snprintf(out->ipa_url, sizeof(out->ipa_url), "%s%s/Exteria-v%s.ipa", EXTERIA_RELEASE_DOWNLOAD_PREFIX, out->tag, version);
        if (n < 0 || (size_t)n >= sizeof(out->ipa_url) ||
            snprintf(out->sha_url, sizeof(out->sha_url), "%s.sha256", out->ipa_url) >= (int)sizeof(out->sha_url)) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_LIMIT;
        }
    }
    return EXTERIA_OK;
}

exteria_status exteria_release_parse(const char *json, size_t length, exteria_release *out) {
    exteria_json_doc *doc = NULL;
    const exteria_json *root, *node;
    const char *tag, *body;
    size_t tag_len = 0, body_len = 0;
    int draft = 0, prerelease = 0;
    exteria_status status;
    if (out) memset(out, 0, sizeof(*out));
    if (!json || !out) return EXTERIA_E_ARG;
    status = exteria_json_parse(json, length, &doc);
    if (status != EXTERIA_OK) return status;
    root = exteria_json_root(doc);
    tag = exteria_json_string(exteria_json_get(root, "tag_name"), &tag_len);
    node = exteria_json_get(root, "body");
    body = exteria_json_string(node, &body_len);
    if (!tag || !tag_len || tag_len >= sizeof(out->tag) || memchr(tag, 0, tag_len) ||
        (body && (body_len >= sizeof(out->body) || memchr(body, 0, body_len))) ||
        (!body && exteria_json_kind(node) != EXTERIA_JSON_NULL) ||
        exteria_json_bool(exteria_json_get(root, "draft"), &draft) != EXTERIA_OK ||
        exteria_json_bool(exteria_json_get(root, "prerelease"), &prerelease) != EXTERIA_OK) status = EXTERIA_E_MALFORMED;
    else if (draft || prerelease) status = EXTERIA_E_UNSUPPORTED;
    else {
        char name[EXTERIA_RELEASE_TAG_MAX + 16];
        const exteria_json *assets = exteria_json_get(root, "assets");
        memcpy(out->tag, tag, tag_len);
        if (body) memcpy(out->body, body, body_len);
        snprintf(name, sizeof(name), "Exteria-v%s.ipa", tag[0] == 'v' || tag[0] == 'V' ? tag + 1 : tag);
        find_asset(assets, name, out->ipa_url, sizeof(out->ipa_url), &out->ipa_size);
        if (out->ipa_url[0]) {
            char sha_name[sizeof(name) + 8];
            snprintf(sha_name, sizeof(sha_name), "%s.sha256", name);
            find_asset(assets, sha_name, out->sha_url, sizeof(out->sha_url), NULL);
        }
    }
    exteria_json_free(doc);
    return status;
}
