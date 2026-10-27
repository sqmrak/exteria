#include "exteria_tgc_signal.h"
#include "test_util.h"

static exteria_tgc_message msg;

static exteria_status parse(const char *text) {
    return exteria_tgc_message_parse(text, strlen(text), &msg);
}

/* shaped like the offers of the official clients: opus with transport-cc, then video with VP8, VP9, H264 and rtx */
#define AUDIO "{\"type\":\"audio\",\"ssrc\":\"2851830345\",\"payloadTypes\":[{\"id\":111,\"name\":\"opus\",\"clockrate\":48000,\"channels\":2," \
    "\"feedbackTypes\":[{\"type\":\"transport-cc\",\"subtype\":\"\"}],\"parameters\":{\"minptime\":\"10\",\"useinbandfec\":\"1\"}}]," \
    "\"rtpExtensions\":[{\"id\":2,\"uri\":\"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\"}," \
    "{\"id\":3,\"uri\":\"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\"}]}"

#define VIDEO "{\"type\":\"video\",\"ssrc\":\"4100\",\"ssrcGroups\":[{\"semantics\":\"FID\",\"ssrcs\":[\"4100\",\"4101\"]}]," \
    "\"payloadTypes\":[" \
    "{\"id\":100,\"name\":\"VP8\",\"clockrate\":90000,\"channels\":0,\"feedbackTypes\":[{\"type\":\"goog-remb\",\"subtype\":\"\"}," \
    "{\"type\":\"transport-cc\",\"subtype\":\"\"},{\"type\":\"ccm\",\"subtype\":\"fir\"},{\"type\":\"nack\",\"subtype\":\"\"}," \
    "{\"type\":\"nack\",\"subtype\":\"pli\"}],\"parameters\":{}}," \
    "{\"id\":101,\"name\":\"rtx\",\"clockrate\":90000,\"parameters\":{\"apt\":\"100\"}}," \
    "{\"id\":102,\"name\":\"VP9\",\"clockrate\":90000,\"parameters\":{\"profile-id\":\"0\"}}," \
    "{\"id\":104,\"name\":\"H264\",\"clockrate\":90000,\"parameters\":{\"level-asymmetry-allowed\":\"1\",\"packetization-mode\":\"1\"," \
    "\"profile-level-id\":\"42e01f\"}}]," \
    "\"rtpExtensions\":[{\"id\":13,\"uri\":\"urn:3gpp:video-orientation\"}]}"

static void initial_setup(void) {
    exteria_tgc_initial_setup *s;
    char out[1024];
    size_t n = 0;
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":\"abcd\",\"pwd\":\"0123456789012345678901\",\"renomination\":true,"
                       "\"fingerprints\":[{\"hash\":\"sha-256\",\"setup\":\"actpass\",\"fingerprint\":\"AA:BB:CC\"}]}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.type, EXTERIA_TGC_MESSAGE_INITIAL_SETUP);
    s = &msg.u.initial_setup;
    CHECK(strcmp(s->ufrag, "abcd") == 0 && strcmp(s->pwd, "0123456789012345678901") == 0);
    CHECK_EQ_INT(s->renomination, 1);
    CHECK_EQ_INT(s->fingerprint_count, 1);
    CHECK(strcmp(s->fingerprints[0].hash, "sha-256") == 0 && strcmp(s->fingerprints[0].setup, "actpass") == 0);
    CHECK(strcmp(s->fingerprints[0].value, "AA:BB:CC") == 0);
    /* renomination may be missing, or of the wrong kind, as in tgcalls; the fingerprint list may be empty */
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":\"u\",\"pwd\":\"p\",\"renomination\":\"yes\",\"fingerprints\":[]}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.initial_setup.renomination, 0);
    CHECK_EQ_INT(msg.u.initial_setup.fingerprint_count, 0);
    /* written as tgcalls writes it, and read back */
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":\"abcd\",\"pwd\":\"pw\",\"renomination\":true,"
                       "\"fingerprints\":[{\"hash\":\"sha-256\",\"setup\":\"passive\",\"fingerprint\":\"01:02\"}]}"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_message_write(&msg, out, sizeof(out), &n), EXTERIA_OK);
    CHECK(strcmp(out, "{\"@type\":\"InitialSetup\",\"ufrag\":\"abcd\",\"pwd\":\"pw\",\"renomination\":true,\"fingerprints\":"
                      "[{\"hash\":\"sha-256\",\"setup\":\"passive\",\"fingerprint\":\"01:02\"}]}") == 0);
    CHECK_EQ_INT(n, strlen(out));
    /* required members */
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"pwd\":\"p\",\"fingerprints\":[]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":\"u\",\"fingerprints\":[]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":\"u\",\"pwd\":\"p\"}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":\"u\",\"pwd\":\"p\",\"fingerprints\":[{\"hash\":\"h\",\"setup\":\"s\"}]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":\"u\",\"pwd\":\"p\",\"fingerprints\":[5]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"InitialSetup\",\"ufrag\":7,\"pwd\":\"p\",\"fingerprints\":[]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(msg.type, EXTERIA_TGC_MESSAGE_NONE);
    /* a field too long for its storage refuses the message */
    {
        char text[600], longpw[200];
        memset(longpw, 'p', sizeof(longpw) - 1);
        longpw[sizeof(longpw) - 1] = '\0';
        snprintf(text, sizeof(text), "{\"@type\":\"InitialSetup\",\"ufrag\":\"u\",\"pwd\":\"%s\",\"fingerprints\":[]}", longpw);
        CHECK_EQ_INT(parse(text), EXTERIA_E_MALFORMED);
    }
}

static void negotiate_channels(void) {
    char text[4096], out[4096];
    const exteria_tgc_content *a, *v;
    size_t n = 0;
    snprintf(text, sizeof(text), "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"3735928559\",\"contents\":[%s,%s]}", AUDIO, VIDEO);
    CHECK_EQ_INT(parse(text), EXTERIA_OK);
    CHECK_EQ_INT(msg.type, EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS);
    CHECK(msg.u.negotiate.exchange_id == 3735928559u);
    CHECK_EQ_INT(msg.u.negotiate.content_count, 2);
    a = &msg.u.negotiate.contents[0];
    CHECK_EQ_INT(a->video, 0);
    CHECK(a->ssrc == 2851830345u);
    CHECK_EQ_INT(a->payload_count, 1);
    CHECK_EQ_INT(a->payloads[0].id, 111);
    CHECK(strcmp(a->payloads[0].name, "opus") == 0);
    CHECK_EQ_INT(a->payloads[0].clockrate, 48000);
    CHECK_EQ_INT(a->payloads[0].channels, 2);
    CHECK_EQ_INT(a->payloads[0].feedback_count, 1);
    CHECK(strcmp(a->payloads[0].feedback[0].type, "transport-cc") == 0 && a->payloads[0].feedback[0].subtype[0] == '\0');
    CHECK_EQ_INT(a->payloads[0].param_count, 2);
    CHECK(strcmp(a->payloads[0].params[0].key, "minptime") == 0 && strcmp(a->payloads[0].params[0].value, "10") == 0);
    CHECK(strcmp(a->payloads[0].params[1].key, "useinbandfec") == 0);
    CHECK_EQ_INT(a->extension_count, 2);
    CHECK_EQ_INT(a->extensions[0].id, 2);
    CHECK(strstr(a->extensions[1].uri, "transport-wide-cc") != NULL);
    v = &msg.u.negotiate.contents[1];
    CHECK_EQ_INT(v->video, 1);
    CHECK(v->ssrc == 4100);
    CHECK_EQ_INT(v->group_count, 1);
    CHECK(strcmp(v->groups[0].semantics, "FID") == 0);
    CHECK_EQ_INT(v->groups[0].count, 2);
    CHECK(v->groups[0].ssrcs[0] == 4100 && v->groups[0].ssrcs[1] == 4101);
    /* only VP8 is kept of the four codecs; rtx, VP9 and H264 are for decoders this app does not have */
    CHECK_EQ_INT(v->payload_count, 1);
    CHECK_EQ_INT(v->payloads[0].id, 100);
    CHECK(strcmp(v->payloads[0].name, "VP8") == 0);
    CHECK_EQ_INT(v->payloads[0].feedback_count, 5);
    CHECK(strcmp(v->payloads[0].feedback[4].type, "nack") == 0 && strcmp(v->payloads[0].feedback[4].subtype, "pli") == 0);
    CHECK_EQ_INT(v->payloads[0].param_count, 0);
    CHECK_EQ_INT(v->extension_count, 1);

    /* what is written is what tgcalls reads: parse it again and compare field by field */
    CHECK_EQ_INT(exteria_tgc_message_write(&msg, out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, strlen(out));
    {
        exteria_tgc_message again;
        CHECK_EQ_INT(exteria_tgc_message_parse(out, n, &again), EXTERIA_OK);
        CHECK(again.u.negotiate.exchange_id == msg.u.negotiate.exchange_id);
        CHECK_EQ_INT(again.u.negotiate.content_count, 2);
        CHECK(memcmp(&again.u.negotiate.contents[0], &msg.u.negotiate.contents[0], sizeof(exteria_tgc_content)) == 0);
        CHECK(memcmp(&again.u.negotiate.contents[1], &msg.u.negotiate.contents[1], sizeof(exteria_tgc_content)) == 0);
    }
    CHECK(strstr(out, "\"exchangeId\":\"3735928559\"") != NULL);
    CHECK(strstr(out, "\"ssrc\":\"2851830345\"") != NULL);
    CHECK(strstr(out, "\"ssrcs\":[\"4100\",\"4101\"]") != NULL);
    /* ssrc and exchange id as plain numbers are read too */
    CHECK_EQ_INT(parse("{\"@type\":\"NegotiateChannels\",\"exchangeId\":77,\"contents\":[{\"type\":\"audio\",\"ssrc\":88}]}"), EXTERIA_OK);
    CHECK(msg.u.negotiate.exchange_id == 77 && msg.u.negotiate.contents[0].ssrc == 88);
    CHECK_EQ_INT(msg.u.negotiate.contents[0].payload_count, 0);
    /* an answer that accepts nothing has no contents at all */
    CHECK_EQ_INT(parse("{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"5\"}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.negotiate.content_count, 0);
    CHECK_EQ_INT(parse("{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"5\",\"contents\":[]}"), EXTERIA_OK);
    /* the codec name is matched without case */
    CHECK_EQ_INT(parse("{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"5\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"9\","
                       "\"payloadTypes\":[{\"id\":96,\"name\":\"OPUS\",\"clockrate\":48000},{\"id\":97,\"name\":\"vp8\",\"clockrate\":90000}]}]}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.negotiate.contents[0].payload_count, 2);
    CHECK_EQ_INT(msg.u.negotiate.contents[0].payloads[0].channels, 0);
}

static void negotiate_rejections(void) {
    static const char *bad[] = {
        "{\"@type\":\"NegotiateChannels\"}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"abc\"}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"0\"}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"4294967296\"}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"-1\"}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"12345678901\"}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":1.5}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":{}}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[3]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"ssrc\":\"5\"}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"screen\",\"ssrc\":\"5\"}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\"}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"0\"}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":true}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"ssrcGroups\":{}}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"ssrcGroups\":[{\"semantics\":\"FID\",\"ssrcs\":[]}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"ssrcGroups\":[{\"semantics\":\"FID\",\"ssrcs\":[\"0\"]}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"ssrcGroups\":[{\"ssrcs\":[\"7\"]}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":{}}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"name\":\"opus\",\"clockrate\":48000}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":128,\"name\":\"opus\",\"clockrate\":48000}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":-1,\"name\":\"opus\",\"clockrate\":48000}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":1,\"clockrate\":48000}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":1,\"name\":\"opus\"}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":1,\"name\":\"opus\",\"clockrate\":48000,\"channels\":\"2\"}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":1,\"name\":\"opus\",\"clockrate\":48000,\"feedbackTypes\":[{\"type\":\"nack\"}]}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":1,\"name\":\"opus\",\"clockrate\":48000,\"parameters\":{\"a\":1}}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"payloadTypes\":[{\"id\":1,\"name\":\"opus\",\"clockrate\":48000,\"parameters\":[]}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"rtpExtensions\":{}}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"rtpExtensions\":[{\"id\":2}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"rtpExtensions\":[{\"uri\":\"u\"}]}]}",
        "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"5\",\"rtpExtensions\":[{\"id\":256,\"uri\":\"u\"}]}]}"
    };
    size_t i;
    for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        exteria_status s = parse(bad[i]);
        if (s != EXTERIA_E_MALFORMED) fprintf(stderr, "  input: %s\n", bad[i]);
        CHECK_EQ_INT(s, EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(msg.type, EXTERIA_TGC_MESSAGE_NONE);
    }
}

static void caps(void) {
    char text[8192];
    size_t n, i;
    /* five contents: the first four are kept */
    n = (size_t)snprintf(text, sizeof(text), "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[");
    for (i = 0; i < 5; ++i) n += (size_t)snprintf(text + n, sizeof(text) - n, "%s{\"type\":\"audio\",\"ssrc\":\"%u\"}", i ? "," : "", (unsigned)(10 + i));
    snprintf(text + n, sizeof(text) - n, "]}");
    CHECK_EQ_INT(parse(text), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.negotiate.content_count, EXTERIA_TGC_MAX_CONTENTS);
    CHECK(msg.u.negotiate.contents[3].ssrc == 13);
    /* more payloads, feedback entries, params, extensions and groups than the caps */
    n = (size_t)snprintf(text, sizeof(text), "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"1\",\"contents\":[{\"type\":\"video\",\"ssrc\":\"5\",\"payloadTypes\":[");
    for (i = 0; i < 6; ++i) {
        size_t j;
        n += (size_t)snprintf(text + n, sizeof(text) - n, "%s{\"id\":%u,\"name\":\"VP8\",\"clockrate\":90000,\"feedbackTypes\":[", i ? "," : "", (unsigned)(96 + i));
        for (j = 0; j < 9; ++j) n += (size_t)snprintf(text + n, sizeof(text) - n, "%s{\"type\":\"t%u\",\"subtype\":\"\"}", j ? "," : "", (unsigned)j);
        n += (size_t)snprintf(text + n, sizeof(text) - n, "],\"parameters\":{");
        for (j = 0; j < 9; ++j) n += (size_t)snprintf(text + n, sizeof(text) - n, "%s\"k%u\":\"v%u\"", j ? "," : "", (unsigned)j, (unsigned)j);
        n += (size_t)snprintf(text + n, sizeof(text) - n, "}}");
    }
    n += (size_t)snprintf(text + n, sizeof(text) - n, "],\"rtpExtensions\":[");
    for (i = 0; i < 11; ++i) n += (size_t)snprintf(text + n, sizeof(text) - n, "%s{\"id\":%u,\"uri\":\"u%u\"}", i ? "," : "", (unsigned)(i + 1), (unsigned)i);
    n += (size_t)snprintf(text + n, sizeof(text) - n, "],\"ssrcGroups\":[");
    for (i = 0; i < 5; ++i) n += (size_t)snprintf(text + n, sizeof(text) - n, "%s{\"semantics\":\"G%u\",\"ssrcs\":[\"1\",\"2\",\"3\",\"4\",\"5\",\"6\"]}", i ? "," : "", (unsigned)i);
    snprintf(text + n, sizeof(text) - n, "]}]}");
    CHECK_EQ_INT(parse(text), EXTERIA_OK);
    {
        const exteria_tgc_content *c = &msg.u.negotiate.contents[0];
        CHECK_EQ_INT(c->payload_count, EXTERIA_TGC_MAX_PAYLOADS);
        CHECK_EQ_INT(c->payloads[0].feedback_count, EXTERIA_TGC_MAX_FEEDBACK);
        CHECK_EQ_INT(c->payloads[0].param_count, EXTERIA_TGC_MAX_PARAMS);
        CHECK_EQ_INT(c->extension_count, EXTERIA_TGC_MAX_EXTENSIONS);
        CHECK_EQ_INT(c->group_count, EXTERIA_TGC_MAX_GROUPS);
        CHECK_EQ_INT(c->groups[0].count, EXTERIA_TGC_MAX_GROUP_SSRCS);
    }
}

static void candidates(void) {
    char text[8192], out[8192];
    size_t n = 0, i;
    CHECK_EQ_INT(parse("{\"@type\":\"Candidates\",\"candidates\":[{\"sdpString\":\"candidate:1 1 udp 2122260223 192.168.0.5 53333 typ host generation 0\"},"
                       "{\"sdpString\":\"candidate:2 1 udp 1686052607 5.6.7.8 61000 typ srflx raddr 192.168.0.5 rport 53333 generation 0\"}]}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.type, EXTERIA_TGC_MESSAGE_CANDIDATES);
    CHECK_EQ_INT(msg.u.candidates.count, 2);
    CHECK(strstr(msg.u.candidates.sdp[1], "typ srflx") != NULL);
    CHECK_EQ_INT(exteria_tgc_message_write(&msg, out, sizeof(out), &n), EXTERIA_OK);
    CHECK(strcmp(out, "{\"@type\":\"Candidates\",\"candidates\":[{\"sdpString\":\"candidate:1 1 udp 2122260223 192.168.0.5 53333 typ host generation 0\"},"
                      "{\"sdpString\":\"candidate:2 1 udp 1686052607 5.6.7.8 61000 typ srflx raddr 192.168.0.5 rport 53333 generation 0\"}]}") == 0);
    CHECK_EQ_INT(parse("{\"@type\":\"Candidates\",\"candidates\":[]}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.candidates.count, 0);
    CHECK_EQ_INT(parse("{\"@type\":\"Candidates\"}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"Candidates\",\"candidates\":[1]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"Candidates\",\"candidates\":[{\"sdp\":\"x\"}]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"Candidates\",\"candidates\":[{\"sdpString\":5}]}"), EXTERIA_E_MALFORMED);
    /* an overlong candidate is skipped, the ones around it stay; the cap keeps the first 24 */
    {
        char longone[500];
        memset(longone, 'x', sizeof(longone) - 1);
        longone[sizeof(longone) - 1] = '\0';
        snprintf(text, sizeof(text), "{\"@type\":\"Candidates\",\"candidates\":[{\"sdpString\":\"a\"},{\"sdpString\":\"%s\"},{\"sdpString\":\"b\"}]}", longone);
        CHECK_EQ_INT(parse(text), EXTERIA_OK);
        CHECK_EQ_INT(msg.u.candidates.count, 2);
        CHECK(strcmp(msg.u.candidates.sdp[1], "b") == 0);
    }
    n = (size_t)snprintf(text, sizeof(text), "{\"@type\":\"Candidates\",\"candidates\":[");
    for (i = 0; i < 30; ++i) n += (size_t)snprintf(text + n, sizeof(text) - n, "%s{\"sdpString\":\"c%u\"}", i ? "," : "", (unsigned)i);
    snprintf(text + n, sizeof(text) - n, "]}");
    CHECK_EQ_INT(parse(text), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.candidates.count, EXTERIA_TGC_MAX_CANDIDATES);
    CHECK(strcmp(msg.u.candidates.sdp[23], "c23") == 0);
}

static void media_state(void) {
    char out[512];
    size_t n = 0;
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\",\"muted\":true,\"lowBattery\":true,\"videoState\":\"active\",\"videoRotation\":90,\"screencastState\":\"suspended\"}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.type, EXTERIA_TGC_MESSAGE_MEDIA_STATE);
    CHECK_EQ_INT(msg.u.media_state.muted, 1);
    CHECK_EQ_INT(msg.u.media_state.low_battery, 1);
    CHECK_EQ_INT(msg.u.media_state.video_state, EXTERIA_TGC_VIDEO_ACTIVE);
    CHECK_EQ_INT(msg.u.media_state.video_rotation, 90);
    CHECK_EQ_INT(msg.u.media_state.screencast_state, EXTERIA_TGC_VIDEO_SUSPENDED);
    CHECK_EQ_INT(exteria_tgc_message_write(&msg, out, sizeof(out), &n), EXTERIA_OK);
    CHECK(strcmp(out, "{\"@type\":\"MediaState\",\"muted\":true,\"lowBattery\":true,\"videoState\":\"active\",\"videoRotation\":90,"
                      "\"screencastState\":\"suspended\"}") == 0);
    /* everything is optional */
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\"}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.media_state.muted, 0);
    CHECK_EQ_INT(msg.u.media_state.video_state, EXTERIA_TGC_VIDEO_INACTIVE);
    CHECK_EQ_INT(msg.u.media_state.video_rotation, 0);
    /* an unknown state word or rotation falls back, as in tgcalls; a wrong kind refuses the message */
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\",\"videoState\":\"paused\",\"videoRotation\":45}"), EXTERIA_OK);
    CHECK_EQ_INT(msg.u.media_state.video_state, EXTERIA_TGC_VIDEO_INACTIVE);
    CHECK_EQ_INT(msg.u.media_state.video_rotation, 0);
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\",\"muted\":\"no\"}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\",\"lowBattery\":1}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\",\"videoState\":1}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\",\"screencastState\":[]}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":\"MediaState\",\"videoRotation\":\"90\"}"), EXTERIA_E_MALFORMED);
}

static void envelope(void) {
    CHECK_EQ_INT(parse("{\"@type\":\"Ping\"}"), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(msg.type, EXTERIA_TGC_MESSAGE_NONE);
    CHECK_EQ_INT(parse("{\"type\":\"InitialSetup\"}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"@type\":5}"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("[]"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("\"InitialSetup\""), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("not json"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse(""), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_message_parse(NULL, 5, &msg), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_message_parse("{}", 2, NULL), EXTERIA_E_ARG);
    {
        static char big[70000];
        memset(big, ' ', sizeof(big));
        CHECK_EQ_INT(exteria_tgc_message_parse(big, sizeof(big), &msg), EXTERIA_E_LIMIT);
    }
}

static void write_errors(void) {
    exteria_tgc_message m;
    char out[64], big[4096];
    size_t n = 5;
    memset(&m, 0, sizeof(m));
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(n, 0);
    m.type = EXTERIA_TGC_MESSAGE_INITIAL_SETUP;
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_E_ARG);
    snprintf(m.u.initial_setup.ufrag, sizeof(m.u.initial_setup.ufrag), "u");
    snprintf(m.u.initial_setup.pwd, sizeof(m.u.initial_setup.pwd), "p");
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_message_write(&m, out, 20, &n), EXTERIA_E_LIMIT);
    m.u.initial_setup.fingerprint_count = EXTERIA_TGC_MAX_FINGERPRINTS + 1;
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_E_ARG);
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS;
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_E_ARG);
    m.u.negotiate.exchange_id = 4;
    m.u.negotiate.content_count = 1;
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_E_ARG);
    m.u.negotiate.contents[0].ssrc = 6;
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_OK);
    CHECK(strcmp(big, "{\"@type\":\"NegotiateChannels\",\"exchangeId\":\"4\",\"contents\":[{\"type\":\"audio\",\"ssrc\":\"6\",\"rtpExtensions\":[]}]}") == 0);
    m.u.negotiate.content_count = EXTERIA_TGC_MAX_CONTENTS + 1;
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_E_ARG);
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_TGC_MESSAGE_CANDIDATES;
    m.u.candidates.count = EXTERIA_TGC_MAX_CANDIDATES + 1;
    CHECK_EQ_INT(exteria_tgc_message_write(&m, big, sizeof(big), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_message_write(NULL, big, sizeof(big), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_message_write(&m, NULL, sizeof(big), &n), EXTERIA_E_ARG);
}

int main(void) {
    initial_setup();
    negotiate_channels();
    negotiate_rejections();
    caps();
    candidates();
    media_state();
    envelope();
    write_errors();
    return test_finish("test_tgc_signal");
}
