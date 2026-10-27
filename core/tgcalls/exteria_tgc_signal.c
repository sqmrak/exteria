#include "exteria_tgc_signal.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "exteria_tgc_json.h"

/* copies a JSON string into a fixed field; false when it does not fit, so the caller decides whether that drops the entry or the message */
static int copy_string(char *dst, size_t cap, const exteria_json *node) {
    size_t len;
    const char *s = exteria_json_string(node, &len);
    if (!s || len >= cap) return 0;
    memcpy(dst, s, len + 1);
    return 1;
}

/* a decimal number in a string, or a JSON number, in 1 to 4294967295; zero is no ssrc and no usable exchange id either way */
static int read_u32(const exteria_json *node, uint32_t *out) {
    int64_t value = 0;
    if (exteria_json_kind(node) == EXTERIA_JSON_STRING) {
        size_t len, i;
        const char *s = exteria_json_string(node, &len);
        if (!s || len == 0 || len > 10) return 0;
        for (i = 0; i < len; ++i) {
            if (s[i] < '0' || s[i] > '9') return 0;
            value = value * 10 + (s[i] - '0');
        }
    } else if (exteria_json_int(node, &value) != EXTERIA_OK) {
        return 0;
    }
    if (value < 1 || value > 0xFFFFFFFFLL) return 0;
    *out = (uint32_t)value;
    return 1;
}

static int is_codec_we_use(const char *name) {
    size_t i;
    static const char *known[] = {"opus", "vp8"};
    for (i = 0; i < sizeof(known) / sizeof(known[0]); ++i) {
        const char *a = name, *b = known[i];
        while (*a && *b && tolower((unsigned char)*a) == *b) {
            ++a;
            ++b;
        }
        if (!*a && !*b) return 1;
    }
    return 0;
}

static exteria_status read_payload(const exteria_json *node, exteria_tgc_payload *p, int *keep) {
    const exteria_json *v, *item;
    int64_t i;
    *keep = 0;
    memset(p, 0, sizeof(*p));
    if (exteria_json_kind(node) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
    v = exteria_json_get(node, "id");
    if (exteria_json_int(v, &i) != EXTERIA_OK || i < 0 || i > 127) return EXTERIA_E_MALFORMED;
    p->id = (uint8_t)i;
    v = exteria_json_get(node, "name");
    if (exteria_json_kind(v) != EXTERIA_JSON_STRING) return EXTERIA_E_MALFORMED;
    v = exteria_json_get(node, "clockrate");
    if (exteria_json_int(v, &i) != EXTERIA_OK || i < 0 || i > 0xFFFFFFFFLL) return EXTERIA_E_MALFORMED;
    p->clockrate = (uint32_t)i;
    v = exteria_json_get(node, "channels");
    if (v) {
        if (exteria_json_int(v, &i) != EXTERIA_OK || i < 0 || i > 64) return EXTERIA_E_MALFORMED;
        p->channels = (uint32_t)i;
    }
    v = exteria_json_get(node, "feedbackTypes");
    if (v) {
        if (exteria_json_kind(v) != EXTERIA_JSON_ARRAY) return EXTERIA_E_MALFORMED;
        for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
            exteria_tgc_feedback f;
            memset(&f, 0, sizeof(f));
            if (exteria_json_kind(item) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
            if (exteria_json_kind(exteria_json_get(item, "type")) != EXTERIA_JSON_STRING ||
                exteria_json_kind(exteria_json_get(item, "subtype")) != EXTERIA_JSON_STRING) return EXTERIA_E_MALFORMED;
            if (p->feedback_count >= EXTERIA_TGC_MAX_FEEDBACK) continue;
            /* a name too long for the field is a kind of feedback this app does not know, so it is left out */
            if (!copy_string(f.type, sizeof(f.type), exteria_json_get(item, "type")) ||
                !copy_string(f.subtype, sizeof(f.subtype), exteria_json_get(item, "subtype"))) continue;
            p->feedback[p->feedback_count++] = f;
        }
    }
    v = exteria_json_get(node, "parameters");
    if (v) {
        if (exteria_json_kind(v) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
        for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
            exteria_tgc_param pr;
            const char *key = exteria_json_key(item);
            memset(&pr, 0, sizeof(pr));
            if (exteria_json_kind(item) != EXTERIA_JSON_STRING) return EXTERIA_E_MALFORMED;
            if (p->param_count >= EXTERIA_TGC_MAX_PARAMS || !key || strlen(key) >= sizeof(pr.key)) continue;
            if (!copy_string(pr.value, sizeof(pr.value), item)) continue;
            memcpy(pr.key, key, strlen(key) + 1);
            p->params[p->param_count++] = pr;
        }
    }
    {
        size_t len;
        const char *name = exteria_json_string(exteria_json_get(node, "name"), &len);
        if (len < sizeof(p->name)) {
            memcpy(p->name, name, len + 1);
            *keep = is_codec_we_use(p->name);
        }
    }
    return EXTERIA_OK;
}

static exteria_status read_content(const exteria_json *node, exteria_tgc_content *c) {
    const exteria_json *v, *item;
    size_t len;
    const char *type;
    int64_t i;
    memset(c, 0, sizeof(*c));
    if (exteria_json_kind(node) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
    type = exteria_json_string(exteria_json_get(node, "type"), &len);
    if (!type) return EXTERIA_E_MALFORMED;
    if (strcmp(type, "audio") == 0) c->video = 0;
    else if (strcmp(type, "video") == 0) c->video = 1;
    else return EXTERIA_E_MALFORMED;
    if (!read_u32(exteria_json_get(node, "ssrc"), &c->ssrc)) return EXTERIA_E_MALFORMED;
    v = exteria_json_get(node, "ssrcGroups");
    if (v) {
        if (exteria_json_kind(v) != EXTERIA_JSON_ARRAY) return EXTERIA_E_MALFORMED;
        for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
            exteria_tgc_ssrc_group g;
            const exteria_json *ssrcs, *s;
            memset(&g, 0, sizeof(g));
            if (exteria_json_kind(item) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
            if (exteria_json_kind(exteria_json_get(item, "semantics")) != EXTERIA_JSON_STRING) return EXTERIA_E_MALFORMED;
            ssrcs = exteria_json_get(item, "ssrcs");
            if (exteria_json_kind(ssrcs) != EXTERIA_JSON_ARRAY || exteria_json_count(ssrcs) == 0) return EXTERIA_E_MALFORMED;
            for (s = exteria_json_first(ssrcs); s; s = exteria_json_next(s)) {
                uint32_t value;
                if (!read_u32(s, &value)) return EXTERIA_E_MALFORMED;
                if (g.count < EXTERIA_TGC_MAX_GROUP_SSRCS) g.ssrcs[g.count++] = value;
            }
            if (c->group_count < EXTERIA_TGC_MAX_GROUPS && copy_string(g.semantics, sizeof(g.semantics), exteria_json_get(item, "semantics"))) {
                c->groups[c->group_count++] = g;
            }
        }
    }
    v = exteria_json_get(node, "payloadTypes");
    if (v) {
        if (exteria_json_kind(v) != EXTERIA_JSON_ARRAY) return EXTERIA_E_MALFORMED;
        for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
            exteria_tgc_payload p;
            int keep;
            exteria_status status = read_payload(item, &p, &keep);
            if (status != EXTERIA_OK) return status;
            if (keep && c->payload_count < EXTERIA_TGC_MAX_PAYLOADS) c->payloads[c->payload_count++] = p;
        }
    }
    v = exteria_json_get(node, "rtpExtensions");
    if (v) {
        if (exteria_json_kind(v) != EXTERIA_JSON_ARRAY) return EXTERIA_E_MALFORMED;
        for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
            exteria_tgc_extension e;
            memset(&e, 0, sizeof(e));
            if (exteria_json_kind(item) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
            if (exteria_json_int(exteria_json_get(item, "id"), &i) != EXTERIA_OK || i < 0 || i > 255) return EXTERIA_E_MALFORMED;
            if (exteria_json_kind(exteria_json_get(item, "uri")) != EXTERIA_JSON_STRING) return EXTERIA_E_MALFORMED;
            e.id = (uint8_t)i;
            if (c->extension_count >= EXTERIA_TGC_MAX_EXTENSIONS || !copy_string(e.uri, sizeof(e.uri), exteria_json_get(item, "uri"))) continue;
            c->extensions[c->extension_count++] = e;
        }
    }
    return EXTERIA_OK;
}

static exteria_status read_initial_setup(const exteria_json *root, exteria_tgc_initial_setup *s) {
    const exteria_json *v, *item;
    int flag;
    if (!copy_string(s->ufrag, sizeof(s->ufrag), exteria_json_get(root, "ufrag"))) return EXTERIA_E_MALFORMED;
    if (!copy_string(s->pwd, sizeof(s->pwd), exteria_json_get(root, "pwd"))) return EXTERIA_E_MALFORMED;
    v = exteria_json_get(root, "renomination");
    if (v && exteria_json_bool(v, &flag) == EXTERIA_OK) s->renomination = (uint8_t)flag;
    v = exteria_json_get(root, "fingerprints");
    if (exteria_json_kind(v) != EXTERIA_JSON_ARRAY) return EXTERIA_E_MALFORMED;
    for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
        exteria_tgc_fingerprint f;
        memset(&f, 0, sizeof(f));
        if (exteria_json_kind(item) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
        if (!copy_string(f.hash, sizeof(f.hash), exteria_json_get(item, "hash")) ||
            !copy_string(f.setup, sizeof(f.setup), exteria_json_get(item, "setup")) ||
            !copy_string(f.value, sizeof(f.value), exteria_json_get(item, "fingerprint"))) return EXTERIA_E_MALFORMED;
        if (s->fingerprint_count < EXTERIA_TGC_MAX_FINGERPRINTS) s->fingerprints[s->fingerprint_count++] = f;
    }
    return EXTERIA_OK;
}

static exteria_status read_negotiate(const exteria_json *root, exteria_tgc_negotiate *n) {
    const exteria_json *v, *item;
    if (!read_u32(exteria_json_get(root, "exchangeId"), &n->exchange_id)) return EXTERIA_E_MALFORMED;
    v = exteria_json_get(root, "contents");
    if (!v) return EXTERIA_OK;
    if (exteria_json_kind(v) != EXTERIA_JSON_ARRAY) return EXTERIA_E_MALFORMED;
    for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
        exteria_tgc_content c;
        exteria_status status = read_content(item, &c);
        if (status != EXTERIA_OK) return status;
        if (n->content_count < EXTERIA_TGC_MAX_CONTENTS) n->contents[n->content_count++] = c;
    }
    return EXTERIA_OK;
}

static exteria_status read_candidates(const exteria_json *root, exteria_tgc_candidates *c) {
    const exteria_json *v = exteria_json_get(root, "candidates"), *item;
    if (exteria_json_kind(v) != EXTERIA_JSON_ARRAY) return EXTERIA_E_MALFORMED;
    for (item = exteria_json_first(v); item; item = exteria_json_next(item)) {
        const exteria_json *sdp;
        if (exteria_json_kind(item) != EXTERIA_JSON_OBJECT) return EXTERIA_E_MALFORMED;
        sdp = exteria_json_get(item, "sdpString");
        if (exteria_json_kind(sdp) != EXTERIA_JSON_STRING) return EXTERIA_E_MALFORMED;
        if (c->count >= EXTERIA_TGC_MAX_CANDIDATES) continue;
        if (copy_string(c->sdp[c->count], sizeof(c->sdp[0]), sdp)) ++c->count;
    }
    return EXTERIA_OK;
}

static exteria_status read_video_state(const exteria_json *v, uint8_t *out) {
    size_t len;
    const char *s;
    if (!v) {
        *out = EXTERIA_TGC_VIDEO_INACTIVE;
        return EXTERIA_OK;
    }
    s = exteria_json_string(v, &len);
    if (!s) return EXTERIA_E_MALFORMED;
    /* tgcalls logs a state it does not know and goes on with the default, so an unknown word is not an error */
    if (strcmp(s, "suspended") == 0) *out = EXTERIA_TGC_VIDEO_SUSPENDED;
    else if (strcmp(s, "active") == 0) *out = EXTERIA_TGC_VIDEO_ACTIVE;
    else *out = EXTERIA_TGC_VIDEO_INACTIVE;
    return EXTERIA_OK;
}

static exteria_status read_media_state(const exteria_json *root, exteria_tgc_media_state *m) {
    const exteria_json *v;
    int flag;
    int64_t rotation;
    v = exteria_json_get(root, "muted");
    if (v) {
        if (exteria_json_bool(v, &flag) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        m->muted = (uint8_t)flag;
    }
    v = exteria_json_get(root, "lowBattery");
    if (v) {
        if (exteria_json_bool(v, &flag) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        m->low_battery = (uint8_t)flag;
    }
    if (read_video_state(exteria_json_get(root, "videoState"), &m->video_state) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (read_video_state(exteria_json_get(root, "screencastState"), &m->screencast_state) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    v = exteria_json_get(root, "videoRotation");
    if (v) {
        if (exteria_json_int(v, &rotation) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        m->video_rotation = (rotation == 90 || rotation == 180 || rotation == 270) ? (uint16_t)rotation : 0;
    }
    return EXTERIA_OK;
}

exteria_status exteria_tgc_message_parse(const char *text, size_t len, exteria_tgc_message *out) {
    exteria_json_doc *doc = NULL;
    const exteria_json *root;
    const char *type;
    size_t type_len;
    exteria_status status;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!text) return EXTERIA_E_ARG;
    status = exteria_json_parse(text, len, &doc);
    if (status != EXTERIA_OK) return status == EXTERIA_E_LIMIT ? status : EXTERIA_E_MALFORMED;
    root = exteria_json_root(doc);
    if (exteria_json_kind(root) != EXTERIA_JSON_OBJECT) {
        exteria_json_free(doc);
        return EXTERIA_E_MALFORMED;
    }
    type = exteria_json_string(exteria_json_get(root, "@type"), &type_len);
    if (!type) {
        exteria_json_free(doc);
        return EXTERIA_E_MALFORMED;
    }
    if (strcmp(type, "InitialSetup") == 0) {
        out->type = EXTERIA_TGC_MESSAGE_INITIAL_SETUP;
        status = read_initial_setup(root, &out->u.initial_setup);
    } else if (strcmp(type, "NegotiateChannels") == 0) {
        out->type = EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS;
        status = read_negotiate(root, &out->u.negotiate);
    } else if (strcmp(type, "Candidates") == 0) {
        out->type = EXTERIA_TGC_MESSAGE_CANDIDATES;
        status = read_candidates(root, &out->u.candidates);
    } else if (strcmp(type, "MediaState") == 0) {
        out->type = EXTERIA_TGC_MESSAGE_MEDIA_STATE;
        status = read_media_state(root, &out->u.media_state);
    } else {
        status = EXTERIA_E_UNSUPPORTED;
    }
    exteria_json_free(doc);
    if (status != EXTERIA_OK) memset(out, 0, sizeof(*out));
    return status;
}

/* writing */

static void write_u32_string(exteria_json_out *o, uint32_t value) {
    char text[16];
    snprintf(text, sizeof(text), "%lu", (unsigned long)value);
    exteria_json_out_string(o, text);
}

static void write_content(exteria_json_out *o, const exteria_tgc_content *c) {
    unsigned i, j;
    exteria_json_out_object(o);
    exteria_json_out_key(o, "type");
    exteria_json_out_string(o, c->video ? "video" : "audio");
    exteria_json_out_key(o, "ssrc");
    write_u32_string(o, c->ssrc);
    if (c->group_count) {
        exteria_json_out_key(o, "ssrcGroups");
        exteria_json_out_array(o);
        for (i = 0; i < c->group_count; ++i) {
            exteria_json_out_object(o);
            exteria_json_out_key(o, "semantics");
            exteria_json_out_string(o, c->groups[i].semantics);
            exteria_json_out_key(o, "ssrcs");
            exteria_json_out_array(o);
            for (j = 0; j < c->groups[i].count; ++j) write_u32_string(o, c->groups[i].ssrcs[j]);
            exteria_json_out_end(o);
            exteria_json_out_end(o);
        }
        exteria_json_out_end(o);
    }
    if (c->payload_count) {
        exteria_json_out_key(o, "payloadTypes");
        exteria_json_out_array(o);
        for (i = 0; i < c->payload_count; ++i) {
            const exteria_tgc_payload *p = &c->payloads[i];
            exteria_json_out_object(o);
            exteria_json_out_key(o, "id");
            exteria_json_out_int(o, p->id);
            exteria_json_out_key(o, "name");
            exteria_json_out_string(o, p->name);
            exteria_json_out_key(o, "clockrate");
            exteria_json_out_int(o, p->clockrate);
            exteria_json_out_key(o, "channels");
            exteria_json_out_int(o, p->channels);
            exteria_json_out_key(o, "feedbackTypes");
            exteria_json_out_array(o);
            for (j = 0; j < p->feedback_count; ++j) {
                exteria_json_out_object(o);
                exteria_json_out_key(o, "type");
                exteria_json_out_string(o, p->feedback[j].type);
                exteria_json_out_key(o, "subtype");
                exteria_json_out_string(o, p->feedback[j].subtype);
                exteria_json_out_end(o);
            }
            exteria_json_out_end(o);
            exteria_json_out_key(o, "parameters");
            exteria_json_out_object(o);
            for (j = 0; j < p->param_count; ++j) {
                exteria_json_out_key(o, p->params[j].key);
                exteria_json_out_string(o, p->params[j].value);
            }
            exteria_json_out_end(o);
            exteria_json_out_end(o);
        }
        exteria_json_out_end(o);
    }
    exteria_json_out_key(o, "rtpExtensions");
    exteria_json_out_array(o);
    for (i = 0; i < c->extension_count; ++i) {
        exteria_json_out_object(o);
        exteria_json_out_key(o, "id");
        exteria_json_out_int(o, c->extensions[i].id);
        exteria_json_out_key(o, "uri");
        exteria_json_out_string(o, c->extensions[i].uri);
        exteria_json_out_end(o);
    }
    exteria_json_out_end(o);
    exteria_json_out_end(o);
}

static const char *video_state_word(uint8_t state) {
    return state == EXTERIA_TGC_VIDEO_ACTIVE ? "active" : state == EXTERIA_TGC_VIDEO_SUSPENDED ? "suspended" : "inactive";
}

exteria_status exteria_tgc_message_write(const exteria_tgc_message *m, char *out, size_t capacity, size_t *len) {
    exteria_json_out o;
    unsigned i;
    if (len) *len = 0;
    if (!m || !out || !len) return EXTERIA_E_ARG;
    exteria_json_out_init(&o, out, capacity);
    switch (m->type) {
    case EXTERIA_TGC_MESSAGE_INITIAL_SETUP: {
        const exteria_tgc_initial_setup *s = &m->u.initial_setup;
        if (!s->ufrag[0] || !s->pwd[0] || s->fingerprint_count > EXTERIA_TGC_MAX_FINGERPRINTS) return EXTERIA_E_ARG;
        exteria_json_out_object(&o);
        exteria_json_out_key(&o, "@type");
        exteria_json_out_string(&o, "InitialSetup");
        exteria_json_out_key(&o, "ufrag");
        exteria_json_out_string(&o, s->ufrag);
        exteria_json_out_key(&o, "pwd");
        exteria_json_out_string(&o, s->pwd);
        exteria_json_out_key(&o, "renomination");
        exteria_json_out_bool(&o, s->renomination);
        exteria_json_out_key(&o, "fingerprints");
        exteria_json_out_array(&o);
        for (i = 0; i < s->fingerprint_count; ++i) {
            exteria_json_out_object(&o);
            exteria_json_out_key(&o, "hash");
            exteria_json_out_string(&o, s->fingerprints[i].hash);
            exteria_json_out_key(&o, "setup");
            exteria_json_out_string(&o, s->fingerprints[i].setup);
            exteria_json_out_key(&o, "fingerprint");
            exteria_json_out_string(&o, s->fingerprints[i].value);
            exteria_json_out_end(&o);
        }
        exteria_json_out_end(&o);
        exteria_json_out_end(&o);
        break;
    }
    case EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS: {
        const exteria_tgc_negotiate *n = &m->u.negotiate;
        if (n->exchange_id == 0 || n->content_count > EXTERIA_TGC_MAX_CONTENTS) return EXTERIA_E_ARG;
        for (i = 0; i < n->content_count; ++i) {
            if (n->contents[i].ssrc == 0 || n->contents[i].payload_count > EXTERIA_TGC_MAX_PAYLOADS ||
                n->contents[i].extension_count > EXTERIA_TGC_MAX_EXTENSIONS || n->contents[i].group_count > EXTERIA_TGC_MAX_GROUPS) return EXTERIA_E_ARG;
        }
        exteria_json_out_object(&o);
        exteria_json_out_key(&o, "@type");
        exteria_json_out_string(&o, "NegotiateChannels");
        exteria_json_out_key(&o, "exchangeId");
        write_u32_string(&o, n->exchange_id);
        exteria_json_out_key(&o, "contents");
        exteria_json_out_array(&o);
        for (i = 0; i < n->content_count; ++i) write_content(&o, &n->contents[i]);
        exteria_json_out_end(&o);
        exteria_json_out_end(&o);
        break;
    }
    case EXTERIA_TGC_MESSAGE_CANDIDATES: {
        const exteria_tgc_candidates *c = &m->u.candidates;
        if (c->count > EXTERIA_TGC_MAX_CANDIDATES) return EXTERIA_E_ARG;
        exteria_json_out_object(&o);
        exteria_json_out_key(&o, "@type");
        exteria_json_out_string(&o, "Candidates");
        exteria_json_out_key(&o, "candidates");
        exteria_json_out_array(&o);
        for (i = 0; i < c->count; ++i) {
            exteria_json_out_object(&o);
            exteria_json_out_key(&o, "sdpString");
            exteria_json_out_string(&o, c->sdp[i]);
            exteria_json_out_end(&o);
        }
        exteria_json_out_end(&o);
        exteria_json_out_end(&o);
        break;
    }
    case EXTERIA_TGC_MESSAGE_MEDIA_STATE: {
        const exteria_tgc_media_state *s = &m->u.media_state;
        exteria_json_out_object(&o);
        exteria_json_out_key(&o, "@type");
        exteria_json_out_string(&o, "MediaState");
        exteria_json_out_key(&o, "muted");
        exteria_json_out_bool(&o, s->muted);
        exteria_json_out_key(&o, "lowBattery");
        exteria_json_out_bool(&o, s->low_battery);
        exteria_json_out_key(&o, "videoState");
        exteria_json_out_string(&o, video_state_word(s->video_state));
        exteria_json_out_key(&o, "videoRotation");
        exteria_json_out_int(&o, s->video_rotation);
        exteria_json_out_key(&o, "screencastState");
        exteria_json_out_string(&o, video_state_word(s->screencast_state));
        exteria_json_out_end(&o);
        break;
    }
    default:
        return EXTERIA_E_ARG;
    }
    return exteria_json_out_finish(&o, len);
}
