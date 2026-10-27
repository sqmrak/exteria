#include "exteria_warp.h"

#include <stdio.h>
#include <string.h>

#include "exteria_bytes.h"
#include "exteria_crypto.h"
#include "exteria_random.h"
#include "exteria_tgc_json.h"

static const char b64_alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

exteria_status exteria_base64_encode(const uint8_t *data, size_t len, char *out, size_t cap, size_t *out_len) {
    size_t need = (len + 2) / 3 * 4, i, o = 0;
    if (out_len) *out_len = 0;
    if (!out || !out_len || (len && !data)) return EXTERIA_E_ARG;
    if (cap < need + 1) return EXTERIA_E_LIMIT;
    for (i = 0; i + 3 <= len; i += 3) {
        uint32_t v = (uint32_t)data[i] << 16 | (uint32_t)data[i + 1] << 8 | data[i + 2];
        out[o++] = b64_alphabet[v >> 18 & 63];
        out[o++] = b64_alphabet[v >> 12 & 63];
        out[o++] = b64_alphabet[v >> 6 & 63];
        out[o++] = b64_alphabet[v & 63];
    }
    if (len - i == 1) {
        uint32_t v = (uint32_t)data[i] << 16;
        out[o++] = b64_alphabet[v >> 18 & 63];
        out[o++] = b64_alphabet[v >> 12 & 63];
        out[o++] = '=';
        out[o++] = '=';
    } else if (len - i == 2) {
        uint32_t v = (uint32_t)data[i] << 16 | (uint32_t)data[i + 1] << 8;
        out[o++] = b64_alphabet[v >> 18 & 63];
        out[o++] = b64_alphabet[v >> 12 & 63];
        out[o++] = b64_alphabet[v >> 6 & 63];
        out[o++] = '=';
    }
    out[o] = 0;
    *out_len = o;
    return EXTERIA_OK;
}

static int b64_value(char c) {
    const char *p = memchr(b64_alphabet, c, 64);
    return c && p ? (int)(p - b64_alphabet) : -1;
}

exteria_status exteria_base64_decode(const char *text, size_t text_len, uint8_t *out, size_t cap, size_t *out_len) {
    size_t i, o = 0;
    if (out_len) *out_len = 0;
    if (!text || !out_len || (cap && !out)) return EXTERIA_E_ARG;
    if (text_len % 4 != 0) return EXTERIA_E_MALFORMED;
    for (i = 0; i < text_len; i += 4) {
        int a = b64_value(text[i]), b = b64_value(text[i + 1]), c, d;
        int last = i + 4 == text_len;
        uint32_t v;
        if (a < 0 || b < 0) return EXTERIA_E_MALFORMED;
        if (last && text[i + 2] == '=') {
            if (text[i + 3] != '=' || (b & 15) != 0) return EXTERIA_E_MALFORMED;
            if (cap - o < 1) return EXTERIA_E_LIMIT;
            out[o++] = (uint8_t)(a << 2 | b >> 4);
            continue;
        }
        c = b64_value(text[i + 2]);
        if (c < 0) return EXTERIA_E_MALFORMED;
        if (last && text[i + 3] == '=') {
            if ((c & 3) != 0) return EXTERIA_E_MALFORMED;
            if (cap - o < 2) return EXTERIA_E_LIMIT;
            v = (uint32_t)a << 10 | (uint32_t)b << 4 | (uint32_t)c >> 2;
            out[o++] = (uint8_t)(v >> 8);
            out[o++] = (uint8_t)v;
            continue;
        }
        d = b64_value(text[i + 3]);
        if (d < 0) return EXTERIA_E_MALFORMED;
        if (cap - o < 3) return EXTERIA_E_LIMIT;
        v = (uint32_t)a << 18 | (uint32_t)b << 12 | (uint32_t)c << 6 | (uint32_t)d;
        out[o++] = (uint8_t)(v >> 16);
        out[o++] = (uint8_t)(v >> 8);
        out[o++] = (uint8_t)v;
    }
    *out_len = o;
    return EXTERIA_OK;
}

exteria_status exteria_warp_parse_ipv4(const char *text, size_t len, uint32_t *out) {
    uint32_t value = 0;
    size_t i = 0;
    int part;
    if (out) *out = 0;
    if (!text || !out) return EXTERIA_E_ARG;
    for (part = 0; part < 4; ++part) {
        unsigned n = 0;
        size_t start = i;
        while (i < len && text[i] >= '0' && text[i] <= '9') {
            n = n * 10 + (unsigned)(text[i] - '0');
            if (n > 255) return EXTERIA_E_MALFORMED;
            ++i;
        }
        if (i == start || i - start > 3 || (text[start] == '0' && i - start > 1)) return EXTERIA_E_MALFORMED;
        value = value << 8 | n;
        if (part < 3) {
            if (i >= len || text[i] != '.') return EXTERIA_E_MALFORMED;
            ++i;
        }
    }
    if (i != len) return EXTERIA_E_MALFORMED;
    *out = value;
    return EXTERIA_OK;
}

exteria_status exteria_warp_generate_key(uint8_t private_key[EXTERIA_WG_KEY_LEN], uint8_t public_key[EXTERIA_WG_KEY_LEN]) {
    if (!private_key || !public_key) return EXTERIA_E_ARG;
    if (exteria_random(private_key, EXTERIA_WG_KEY_LEN) != EXTERIA_OK) return EXTERIA_E_CRYPTO;
    /* the clamping of RFC 7748, done here as well so the stored key is the one every WireGuard tool would write */
    private_key[0] &= 248;
    private_key[31] &= 127;
    private_key[31] |= 64;
    return exteria_x25519_public(private_key, public_key);
}

exteria_status exteria_warp_registration_body(const uint8_t public_key[EXTERIA_WG_KEY_LEN], const char *install_id, const char *tos, char *out, size_t cap,
                                              size_t *len) {
    char key[64];
    size_t key_len = 0, i;
    exteria_json_out json;
    if (len) *len = 0;
    if (!public_key || !install_id || !tos || !out || !len) return EXTERIA_E_ARG;
    if (strlen(install_id) != EXTERIA_WARP_INSTALL_ID_LEN) return EXTERIA_E_ARG;
    for (i = 0; install_id[i]; ++i) {
        char c = install_id[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) return EXTERIA_E_ARG;
    }
    if (exteria_base64_encode(public_key, EXTERIA_WG_KEY_LEN, key, sizeof(key), &key_len) != EXTERIA_OK) return EXTERIA_E_ARG;
    exteria_json_out_init(&json, out, cap);
    exteria_json_out_object(&json);
    exteria_json_out_key(&json, "key");
    exteria_json_out_string(&json, key);
    exteria_json_out_key(&json, "install_id");
    exteria_json_out_string(&json, install_id);
    exteria_json_out_key(&json, "fcm_token");
    exteria_json_out_string(&json, "");
    exteria_json_out_key(&json, "tos");
    exteria_json_out_string(&json, tos);
    exteria_json_out_key(&json, "model");
    exteria_json_out_string(&json, "iPhone");
    exteria_json_out_key(&json, "serial_number");
    exteria_json_out_string(&json, "");
    exteria_json_out_key(&json, "locale");
    exteria_json_out_string(&json, "en_US");
    exteria_json_out_key(&json, "type");
    exteria_json_out_string(&json, "Android");
    exteria_json_out_end(&json);
    return exteria_json_out_finish(&json, len);
}

static const exteria_json *member(const exteria_json *object, const char *key, exteria_json_type type) {
    const exteria_json *node = exteria_json_get(object, key);
    return node && exteria_json_kind(node) == type ? node : NULL;
}

static exteria_status key_of(const exteria_json *object, const char *key, uint8_t out[EXTERIA_WG_KEY_LEN]) {
    const exteria_json *node = member(object, key, EXTERIA_JSON_STRING);
    size_t text_len = 0, got = 0;
    const char *text;
    if (!node) return EXTERIA_E_MALFORMED;
    text = exteria_json_string(node, &text_len);
    if (!text || exteria_base64_decode(text, text_len, out, EXTERIA_WG_KEY_LEN, &got) != EXTERIA_OK || got != EXTERIA_WG_KEY_LEN) return EXTERIA_E_MALFORMED;
    return EXTERIA_OK;
}

/* "1.2.3.4" or "1.2.3.4:5" */
static exteria_status host_of(const char *text, size_t len, uint32_t *ip) {
    const char *colon = memchr(text, ':', len);
    return exteria_warp_parse_ipv4(text, colon ? (size_t)(colon - text) : len, ip);
}

exteria_status exteria_warp_parse_registration(const char *json, size_t len, const uint8_t private_key[EXTERIA_WG_KEY_LEN], exteria_warp_identity *out) {
    exteria_json_doc *doc = NULL;
    const exteria_json *root, *config, *peers, *peer, *endpoint, *iface, *addresses, *ports, *port, *node;
    exteria_warp_identity id;
    exteria_status status = EXTERIA_E_MALFORMED;
    const char *text;
    size_t text_len = 0, got = 0;
    if (out) memset(out, 0, sizeof(*out));
    if (!json || !private_key || !out) return EXTERIA_E_ARG;
    memset(&id, 0, sizeof(id));
    if (exteria_json_parse(json, len, &doc) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    root = exteria_json_root(doc);
    config = member(root, "config", EXTERIA_JSON_OBJECT);
    peers = config ? member(config, "peers", EXTERIA_JSON_ARRAY) : NULL;
    peer = peers ? exteria_json_first(peers) : NULL;
    if (!peer || exteria_json_kind(peer) != EXTERIA_JSON_OBJECT) goto done;
    if (key_of(peer, "public_key", id.peer_public) != EXTERIA_OK) goto done;
    endpoint = member(peer, "endpoint", EXTERIA_JSON_OBJECT);
    node = endpoint ? member(endpoint, "v4", EXTERIA_JSON_STRING) : NULL;
    text = node ? exteria_json_string(node, &text_len) : NULL;
    if (!text || host_of(text, text_len, &id.endpoint_ip) != EXTERIA_OK || id.endpoint_ip == 0) goto done;
    ports = member(endpoint, "ports", EXTERIA_JSON_ARRAY);
    for (port = ports ? exteria_json_first(ports) : NULL; port; port = exteria_json_next(port)) {
        int64_t value = 0;
        if (exteria_json_int(port, &value) != EXTERIA_OK || value < 1 || value > 65535) goto done;
        if (id.port_count < EXTERIA_WARP_MAX_PORTS) id.ports[id.port_count++] = (uint16_t)value;
    }
    /* an answer without ports is still usable: the port comes from the host text, or from the fallbacks later */
    if (id.port_count == 0 && text) {
        const char *colon = memchr(text, ':', text_len);
        if (colon) {
            unsigned long p = 0;
            const char *c;
            for (c = colon + 1; c < text + text_len; ++c) {
                if (*c < '0' || *c > '9') goto done;
                p = p * 10 + (unsigned long)(*c - '0');
                if (p > 65535) goto done;
            }
            if (p > 0) id.ports[id.port_count++] = (uint16_t)p;
        }
    }
    iface = member(config, "interface", EXTERIA_JSON_OBJECT);
    addresses = iface ? member(iface, "addresses", EXTERIA_JSON_OBJECT) : NULL;
    node = addresses ? member(addresses, "v4", EXTERIA_JSON_STRING) : NULL;
    text = node ? exteria_json_string(node, &text_len) : NULL;
    if (!text || exteria_warp_parse_ipv4(text, text_len, &id.address) != EXTERIA_OK || id.address == 0) goto done;
    /* the client id is the three bytes WARP wants in the reserved places of every header; an account without one still works for a server that does not ask */
    node = member(config, "client_id", EXTERIA_JSON_STRING);
    text = node ? exteria_json_string(node, &text_len) : NULL;
    if (text && exteria_base64_decode(text, text_len, id.reserved, sizeof(id.reserved), &got) == EXTERIA_OK && got == sizeof(id.reserved)) id.has_reserved = 1;
    memcpy(id.private_key, private_key, EXTERIA_WG_KEY_LEN);
    *out = id;
    status = EXTERIA_OK;
done:
    exteria_json_free(doc);
    exteria_wipe(&id, sizeof(id));
    return status;
}

/* the text WARP clients put in the signature datagrams, with the line ends of SIP */
static const char sip_invite[] =
    "INVITE sip:bob@biloxi.com SIP/2.0\r\n"
    "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n"
    "Max-Forwards: 70\r\n"
    "To: Bob <sip:bob@biloxi.com>\r\n"
    "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n"
    "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n"
    "CSeq: 314159 INVITE\r\n"
    "Contact: <sip:alice@pc33.atlanta.com>\r\n"
    "Content-Type: application/sdp\r\n"
    "Content-Length: 0\r\n\r\n";
static const char sip_trying[] =
    "SIP/2.0 100 Trying\r\n"
    "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n"
    "To: Bob <sip:bob@biloxi.com>\r\n"
    "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n"
    "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n"
    "CSeq: 314159 INVITE\r\n"
    "Content-Length: 0\r\n\r\n";

static exteria_status hex_signature(const char *text, size_t len, char *out, size_t cap) {
    static const char hex[] = "0123456789abcdef";
    size_t i, o = 0;
    if (cap < 5 + len * 2 + 2) return EXTERIA_E_LIMIT;
    memcpy(out, "<b 0x", 5);
    o = 5;
    for (i = 0; i < len; ++i) {
        out[o++] = hex[(uint8_t)text[i] >> 4];
        out[o++] = hex[(uint8_t)text[i] & 15];
    }
    out[o++] = '>';
    out[o] = 0;
    return EXTERIA_OK;
}

exteria_status exteria_warp_wg_config(const exteria_warp_identity *identity, exteria_warp_profile *profile, exteria_wg_config *out) {
    exteria_status status;
    if (out) memset(out, 0, sizeof(*out));
    if (!identity || !profile || !out) return EXTERIA_E_ARG;
    status = hex_signature(sip_invite, sizeof(sip_invite) - 1, profile->signature[0], sizeof(profile->signature[0]));
    if (status != EXTERIA_OK) return status;
    status = hex_signature(sip_trying, sizeof(sip_trying) - 1, profile->signature[1], sizeof(profile->signature[1]));
    if (status != EXTERIA_OK) return status;
    memcpy(out->private_key, identity->private_key, EXTERIA_WG_KEY_LEN);
    memcpy(out->peer_public, identity->peer_public, EXTERIA_WG_KEY_LEN);
    memcpy(out->reserved, identity->reserved, sizeof(out->reserved));
    out->has_reserved = identity->has_reserved;
    out->junk_count = 4;
    out->junk_min = 40;
    out->junk_max = 70;
    out->signature[0] = profile->signature[0];
    out->signature[1] = profile->signature[1];
    return exteria_wg_config_check(out);
}

/* the /24 prefixes WARP is served from (162.159.192, 162.159.193, 162.159.195, 188.114.96 to 99, 8.6.112, 8.34.70,
   8.34.146, 8.35.211, 8.39.125, 8.39.204, 8.39.214, 8.47.69) */
static const uint32_t warp_prefixes[] = {
    0xA29FC000u, 0xA29FC100u, 0xA29FC300u, 0xBC726000u, 0xBC726100u, 0xBC726200u, 0xBC726300u, 0x08067000u,
    0x08224600u, 0x08229200u, 0x0823D300u, 0x08277D00u, 0x0827CC00u, 0x0827D600u, 0x082F4500u};
static const uint16_t warp_ports[] = {500,  854,  859,  864,  878,  880,  890,  891,  894,  903,  908,  928,  934,  939,  942,  945,  946,  955,
                                      968,  987,  988,  1002, 1010, 1014, 1018, 1070, 1074, 1180, 1387, 1701, 1843, 2371, 2408, 2506, 3138, 3476,
                                      3581, 3854, 4177, 4198, 4500, 5279, 5956, 7103, 7152, 7156, 7281, 7559, 8319, 8742, 8854, 8886};

exteria_status exteria_warp_endpoint(const exteria_warp_identity *identity, unsigned attempt, uint32_t *ip, uint16_t *port) {
    uint32_t r;
    if (ip) *ip = 0;
    if (port) *port = 0;
    if (!identity || !ip || !port || identity->endpoint_ip == 0) return EXTERIA_E_ARG;
    if (attempt < identity->port_count) {
        *ip = identity->endpoint_ip;
        *port = identity->ports[attempt];
        return EXTERIA_OK;
    }
    if (exteria_random(&r, sizeof(r)) != EXTERIA_OK) return EXTERIA_E_CRYPTO;
    *ip = warp_prefixes[r % (sizeof(warp_prefixes) / sizeof(warp_prefixes[0]))] + 1u + (r >> 8) % 10u;
    *port = warp_ports[(r >> 16) % (sizeof(warp_ports) / sizeof(warp_ports[0]))];
    return EXTERIA_OK;
}
