#include "exteria_tgc_call.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_random.h"
#include "exteria_rtp.h"

#define RTCP_TYPE_FIRST 64
#define RTCP_TYPE_LAST 95
#define RTCP_PSFB 206
/* without receiver reports the remote encoder stays at its low starting rate */
#define REPORT_INTERVAL_MS 1000
#define RTCP_FMT_PLI 1
#define RTCP_FMT_FIR 4
#define CREDENTIAL_ALPHABET "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/"
#define UFRAG_LEN 4
#define PWD_LEN 24
#define VIDEO_PAYLOAD_ROOM 1100

struct exteria_tgc_call {
    exteria_tgc_call_events events;
    uint8_t is_outgoing;
    uint8_t started;
    uint8_t sent_setup;
    uint8_t got_setup;
    uint8_t seen_remote_negotiation;
    uint8_t dtls_started;
    uint8_t srtp_ready;
    uint8_t failed;
    uint8_t muted;
    uint8_t local_video_state;
    uint16_t local_video_rotation;
    exteria_tgc_call_state state;
    char remote_setup[EXTERIA_TGC_NAME_LEN];
    char local_ufrag[UFRAG_LEN + 1];
    char local_pwd[PWD_LEN + 1];
    uint64_t now_ms;
    uint64_t first_tick_ms;
    exteria_tgc_cipher cipher;
    exteria_tgc_ice ice;
    exteria_dtls *dtls;
    exteria_tgc_sctp *sctp;
    exteria_tgc_negotiator negotiator;
    exteria_tgc_srtp send_srtp;
    exteria_tgc_srtp recv_srtp;
    uint16_t audio_seq;
    uint32_t audio_ts;
    uint16_t video_seq;
    exteria_vp8_depacketizer depack;
    uint8_t *video_storage;
    uint16_t video_picture_id;
    uint32_t video_ssrc_seen;
    uint64_t last_pli_ms;
    uint64_t last_report_ms;
    unsigned reports_sent;
    exteria_rtp_receive_stats audio_stats;
    exteria_rtp_receive_stats video_stats;
    unsigned rtcp_reports_traced;
    unsigned video_reports_traced;
    unsigned signals_in;
    unsigned signals_out;
    unsigned audio_rx;
    unsigned video_rx;
    unsigned video_tx_frames;
    unsigned rtcp_rx;
    unsigned key_frame_requests;
    unsigned audio_tx;
    uint8_t sctp_state_seen;
    /* scratch for the signaling, kept here and not on the stack: the messages and their JSON are large */
    exteria_tgc_message out_message;
    exteria_tgc_message in_message;
    exteria_tgc_negotiate answer;
    char json[EXTERIA_TGC_SIGNAL_MAX + 1];
    uint8_t sealed[EXTERIA_TGC_PACKET_MAX];
    uint8_t plain[EXTERIA_TGC_SIGNAL_MAX];
};

static void ctrace(const exteria_tgc_call *c, const char *format, ...) {
    char line[220];
    va_list args;
    if (!c->events.trace) return;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    c->events.trace(c->events.context, line);
}

/* the text of a channel negotiation in pieces of a line, for a call that does not show the video one side sends: what was offered and what was accepted is in it */
static void trace_text(const exteria_tgc_call *c, const char *label, const char *text, size_t len) {
    size_t at = 0;
    unsigned part = 0;
    while (at < len && part < 8) {
        size_t take = len - at < 150 ? len - at : 150;
        ctrace(c, "%s [%u] %.*s", label, part++, (int)take, text + at);
        at += take;
    }
}

static const char *message_name(exteria_tgc_message_type t) {
    switch (t) {
    case EXTERIA_TGC_MESSAGE_INITIAL_SETUP: return "InitialSetup";
    case EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS: return "NegotiateChannels";
    case EXTERIA_TGC_MESSAGE_CANDIDATES: return "Candidates";
    case EXTERIA_TGC_MESSAGE_MEDIA_STATE: return "MediaState";
    default: return "?";
    }
}

static uint32_t random_u32(void) {
    uint32_t v = 0;
    while (v == 0) {
        if (exteria_random(&v, sizeof(v)) != EXTERIA_OK) return 1;
    }
    return v;
}

static void random_text(char *out, size_t n) {
    uint8_t bytes[PWD_LEN];
    size_t i;
    if (exteria_random(bytes, n) != EXTERIA_OK) memset(bytes, 0x41, n);
    for (i = 0; i < n; ++i) out[i] = CREDENTIAL_ALPHABET[bytes[i] & 63];
    out[n] = '\0';
}

static void set_state(exteria_tgc_call *c, exteria_tgc_call_state state) {
    if (c->state == state || c->failed) return;
    ctrace(c, "call state %d -> %d", (int)c->state, (int)state);
    c->state = state;
    if (state == EXTERIA_TGC_CALL_FAILED) c->failed = 1;
    if (c->events.state) c->events.state(c->events.context, state);
}

static void fail(exteria_tgc_call *c) {
    set_state(c, EXTERIA_TGC_CALL_FAILED);
}

/* signaling out: the message to JSON, sealed with the call key */
static void send_message(exteria_tgc_call *c, const exteria_tgc_message *m) {
    size_t json_len = 0, sealed_len = 0;
    if (exteria_tgc_message_write(m, c->json, sizeof(c->json), &json_len) != EXTERIA_OK) return;
    if (exteria_tgc_cipher_seal(&c->cipher, (const uint8_t *)c->json, json_len, c->sealed, sizeof(c->sealed), &sealed_len) != EXTERIA_OK) return;
    ++c->signals_out;
    ctrace(c, "signal out %s (%u bytes)", message_name(m->type), (unsigned)sealed_len);
    if (m->type == EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS && c->negotiator.want_video) trace_text(c, "out negotiate", c->json, json_len);
    if (c->events.send_signaling) c->events.send_signaling(c->events.context, c->sealed, sealed_len);
}

static void send_initial_setup(exteria_tgc_call *c) {
    exteria_tgc_initial_setup *s;
    if (c->sent_setup) return;
    memset(&c->out_message, 0, sizeof(c->out_message));
    c->out_message.type = EXTERIA_TGC_MESSAGE_INITIAL_SETUP;
    s = &c->out_message.u.initial_setup;
    memcpy(s->ufrag, c->local_ufrag, sizeof(c->local_ufrag));
    memcpy(s->pwd, c->local_pwd, sizeof(c->local_pwd));
    /* renomination would make the other side nominate with an attribute this agent does not read */
    s->renomination = 0;
    s->fingerprint_count = 1;
    memcpy(s->fingerprints[0].hash, "sha-256", 8);
    snprintf(s->fingerprints[0].setup, sizeof(s->fingerprints[0].setup), "%s", c->is_outgoing ? "actpass" : "passive");
    snprintf(s->fingerprints[0].value, sizeof(s->fingerprints[0].value), "%s", exteria_dtls_local_fingerprint(c->dtls));
    c->sent_setup = 1;
    send_message(c, &c->out_message);
}

static void send_media_state(exteria_tgc_call *c, uint64_t now_ms) {
    exteria_tgc_media_state *m;
    char json[256];
    size_t n = 0;
    if (!c->sctp) {
        ctrace(c, "media state not sent: no data channel yet");
        return;
    }
    memset(&c->out_message, 0, sizeof(c->out_message));
    c->out_message.type = EXTERIA_TGC_MESSAGE_MEDIA_STATE;
    m = &c->out_message.u.media_state;
    m->muted = c->muted;
    m->video_state = c->local_video_state;
    m->video_rotation = c->local_video_rotation;
    if (exteria_tgc_message_write(&c->out_message, json, sizeof(json), &n) != EXTERIA_OK) {
        ctrace(c, "media state not written");
        return;
    }
    /* the other phone shows our picture only after this message says the video is active, so what went out and whether the channel took it is told */
    ctrace(c, "media state out: %.*s (%s)", (int)n, json, exteria_status_name(exteria_tgc_sctp_send_text(c->sctp, json, n, now_ms)));
}

static void send_offer_if_due(exteria_tgc_call *c) {
    uint32_t id;
    /* the called side offers its channels once it has seen the first message of the caller, as tgcalls does */
    if (!exteria_tgc_negotiator_wants_offer(&c->negotiator) || (!c->is_outgoing && !c->seen_remote_negotiation)) return;
    id = random_u32();
    memset(&c->out_message, 0, sizeof(c->out_message));
    c->out_message.type = EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS;
    if (exteria_tgc_negotiator_make_offer(&c->negotiator, id, &c->out_message.u.negotiate) != EXTERIA_OK) return;
    send_message(c, &c->out_message);
}

static void update_state(exteria_tgc_call *c) {
    if (c->failed) return;
    if (c->srtp_ready && c->negotiator.outgoing[EXTERIA_TGC_STREAM_AUDIO].active && c->negotiator.incoming[EXTERIA_TGC_STREAM_AUDIO].active) {
        set_state(c, c->ice.state == EXTERIA_TGC_ICE_DISCONNECTED ? EXTERIA_TGC_CALL_RECONNECTING : EXTERIA_TGC_CALL_CONNECTED);
    } else if (c->state == EXTERIA_TGC_CALL_CONNECTED && c->ice.state == EXTERIA_TGC_ICE_DISCONNECTED) {
        set_state(c, EXTERIA_TGC_CALL_RECONNECTING);
    }
}

static void streams_changed(exteria_tgc_call *c) {
    if (!c->negotiator.changed) return;
    c->negotiator.changed = 0;
    ctrace(c, "channels: out audio %d (pt %u) video %d, in audio %d (pt %u) video %d", (int)c->negotiator.outgoing[0].active, (unsigned)c->negotiator.outgoing[0].payload_type,
           (int)c->negotiator.outgoing[1].active, (int)c->negotiator.incoming[0].active, (unsigned)c->negotiator.incoming[0].payload_type, (int)c->negotiator.incoming[1].active);
    if (c->events.streams) c->events.streams(c->events.context);
    update_state(c);
}

/* DTLS: what the session wants sent goes out over the ICE path; what it decrypted for the data channel goes to SCTP */
static void pump_dtls_out(exteria_tgc_call *c) {
    uint8_t buf[EXTERIA_DTLS_MAX_DATAGRAM];
    size_t n = 0;
    while (exteria_dtls_poll(c->dtls, buf, sizeof(buf), &n) == EXTERIA_OK) {
        /* before the path is nominated there is nothing to send over, and the handshake resends what it needs */
        exteria_tgc_ice_send(&c->ice, buf, n);
    }
}

static void sctp_send(void *context, const uint8_t *packet, size_t len) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    if (exteria_dtls_write(c->dtls, packet, len) == EXTERIA_OK) pump_dtls_out(c);
}

static void sctp_channel(void *context, int open) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    ctrace(c, "data channel %s", open ? "open" : "closed");
    if (open) send_media_state(c, c->now_ms);
}

static void sctp_message(void *context, const char *text, size_t len) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    exteria_tgc_message m;
    if (exteria_tgc_message_parse(text, len, &m) != EXTERIA_OK || m.type != EXTERIA_TGC_MESSAGE_MEDIA_STATE) return;
    ctrace(c, "media state in: muted %d, video %d, rotation %d", (int)m.u.media_state.muted, (int)m.u.media_state.video_state, (int)m.u.media_state.video_rotation);
    if (c->events.remote_media) c->events.remote_media(c->events.context, m.u.media_state.muted, m.u.media_state.video_state, m.u.media_state.video_rotation);
}

static void handshake_done(exteria_tgc_call *c) {
    uint8_t send_key[EXTERIA_DTLS_SRTP_KEY_LEN], send_salt[EXTERIA_DTLS_SRTP_SALT_LEN], recv_key[EXTERIA_DTLS_SRTP_KEY_LEN], recv_salt[EXTERIA_DTLS_SRTP_SALT_LEN];
    exteria_tgc_sctp_events ev;
    uint8_t cookie[32];
    if (c->srtp_ready) return;
    if (exteria_dtls_srtp_keys(c->dtls, send_key, send_salt, recv_key, recv_salt) != EXTERIA_OK) {
        fail(c);
        return;
    }
    if (exteria_tgc_srtp_init(&c->send_srtp, send_key, send_salt) != EXTERIA_OK || exteria_tgc_srtp_init(&c->recv_srtp, recv_key, recv_salt) != EXTERIA_OK) {
        fail(c);
        return;
    }
    memset(send_key, 0, sizeof(send_key));
    memset(recv_key, 0, sizeof(recv_key));
    c->srtp_ready = 1;
    ctrace(c, "dtls connected, srtp keys derived");
    c->sctp = (exteria_tgc_sctp *)calloc(1, sizeof(*c->sctp));
    if (c->sctp && exteria_random(cookie, sizeof(cookie)) == EXTERIA_OK) {
        memset(&ev, 0, sizeof(ev));
        ev.context = c;
        ev.send = sctp_send;
        ev.channel = sctp_channel;
        ev.message = sctp_message;
        if (exteria_tgc_sctp_init(c->sctp, c->is_outgoing, random_u32(), random_u32() & 0x7FFFFFFFu, cookie, &ev) == EXTERIA_OK) exteria_tgc_sctp_start(c->sctp, c->now_ms);
        else {
            free(c->sctp);
            c->sctp = NULL;
        }
    }
    update_state(c);
}

static void pump_dtls_in(exteria_tgc_call *c) {
    uint8_t buf[EXTERIA_DTLS_MAX_DATAGRAM];
    size_t n = 0;
    exteria_dtls_state st = exteria_dtls_get_state(c->dtls);
    if (st == EXTERIA_DTLS_FAILED) {
        ctrace(c, "dtls failed");
        fail(c);
        return;
    }
    if (st == EXTERIA_DTLS_CONNECTED) handshake_done(c);
    while (c->sctp && exteria_dtls_read(c->dtls, buf, sizeof(buf), &n) == EXTERIA_OK) exteria_tgc_sctp_input(c->sctp, buf, n, c->now_ms);
}

static void dtls_changed(exteria_tgc_call *c) {
    pump_dtls_out(c);
    pump_dtls_in(c);
    pump_dtls_out(c);
}

static void maybe_start_dtls(exteria_tgc_call *c) {
    int client;
    if (c->dtls_started || !c->got_setup || c->ice.state != EXTERIA_TGC_ICE_CONNECTED) return;
    /* the role follows the setup attribute of the other side (RFC 5763): it says passive, we connect; it says active, we wait; it offers either, the side that placed the call connects */
    if (strcmp(c->remote_setup, "passive") == 0) client = 1;
    else if (strcmp(c->remote_setup, "active") == 0) client = 0;
    else client = c->is_outgoing;
    c->dtls_started = 1;
    ctrace(c, "dtls starts as %s (remote setup %s)", client ? "client" : "server", c->remote_setup);
    if (exteria_dtls_start(c->dtls, client) != EXTERIA_OK) {
        fail(c);
        return;
    }
    dtls_changed(c);
}

static int is_sha256(const char *s) {
    static const char want[] = "sha-256";
    size_t i;
    for (i = 0; i < sizeof(want); ++i) {
        if (tolower((unsigned char)s[i]) != want[i]) return 0;
        if (!want[i]) break;
    }
    return 1;
}

static void handle_initial_setup(exteria_tgc_call *c, const exteria_tgc_initial_setup *s) {
    if (c->got_setup) return;
    if (s->fingerprint_count == 0 || !is_sha256(s->fingerprints[0].hash)) {
        ctrace(c, "setup refused: no sha-256 fingerprint");
        return;
    }
    if (exteria_dtls_set_peer_fingerprint(c->dtls, s->fingerprints[0].hash, s->fingerprints[0].value) != EXTERIA_OK) {
        ctrace(c, "setup refused: the fingerprint does not read");
        return;
    }
    if (exteria_tgc_ice_set_remote(&c->ice, s->ufrag, s->pwd) != EXTERIA_OK) {
        ctrace(c, "setup refused: the ice credentials are not usable (ufrag %u chars)", (unsigned)strlen(s->ufrag));
        return;
    }
    ctrace(c, "setup taken: remote setup %s, renomination %d", s->fingerprints[0].setup, (int)s->renomination);
    snprintf(c->remote_setup, sizeof(c->remote_setup), "%s", s->fingerprints[0].setup);
    c->got_setup = 1;
    if (!c->is_outgoing) send_initial_setup(c);
    maybe_start_dtls(c);
}

static void handle_negotiate(exteria_tgc_call *c, const exteria_tgc_negotiate *n) {
    int send_answer = 0;
    exteria_tgc_negotiate *answer = &c->answer;
    c->seen_remote_negotiation = 1;
    if (exteria_tgc_negotiator_receive(&c->negotiator, n, answer, &send_answer) != EXTERIA_OK) return;
    if (send_answer) {
        memset(&c->out_message, 0, sizeof(c->out_message));
        c->out_message.type = EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS;
        c->out_message.u.negotiate = *answer;
        if (answer->exchange_id) send_message(c, &c->out_message);
    }
    send_offer_if_due(c);
    streams_changed(c);
}

exteria_status exteria_tgc_call_signaling(exteria_tgc_call *c, const uint8_t *data, size_t len, uint64_t now_ms) {
    size_t plain_len = 0;
    exteria_status status;
    if (!c || !data) return EXTERIA_E_ARG;
    c->now_ms = now_ms;
    status = exteria_tgc_cipher_open(&c->cipher, data, len, c->plain, sizeof(c->plain), &plain_len);
    if (status != EXTERIA_OK) {
        if (status != EXTERIA_E_RETRY) ctrace(c, "signal in refused: %s (%u bytes)", exteria_status_name(status), (unsigned)len);
        return status;
    }
    ++c->signals_in;
    status = exteria_tgc_message_parse((const char *)c->plain, plain_len, &c->in_message);
    if (status != EXTERIA_OK) {
        ctrace(c, "signal in unreadable: %s, starts %.60s", exteria_status_name(status), (const char *)c->plain);
        return status;
    }
    ctrace(c, "signal in %s (%u bytes)", message_name(c->in_message.type), (unsigned)len);
    if (c->in_message.type == EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS && c->negotiator.want_video) trace_text(c, "in negotiate", (const char *)c->plain, plain_len);
    switch (c->in_message.type) {
    case EXTERIA_TGC_MESSAGE_INITIAL_SETUP:
        handle_initial_setup(c, &c->in_message.u.initial_setup);
        break;
    case EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS:
        handle_negotiate(c, &c->in_message.u.negotiate);
        break;
    case EXTERIA_TGC_MESSAGE_CANDIDATES: {
        unsigned i;
        for (i = 0; i < c->in_message.u.candidates.count; ++i) exteria_tgc_ice_add_remote_candidate(&c->ice, c->in_message.u.candidates.sdp[i], now_ms);
        break;
    }
    case EXTERIA_TGC_MESSAGE_MEDIA_STATE: {
        const exteria_tgc_media_state *m = &c->in_message.u.media_state;
        ctrace(c, "media state in: muted %d, video %d, rotation %d", (int)m->muted, (int)m->video_state, (int)m->video_rotation);
        if (c->events.remote_media) c->events.remote_media(c->events.context, m->muted, m->video_state, m->video_rotation);
        break;
    }
    default:
        break;
    }
    return EXTERIA_OK;
}

/* RTCP of the other side: a request for a key frame of the video we send is the one message acted on */
static void handle_rtcp(exteria_tgc_call *c, uint8_t *packet, size_t len) {
    size_t out = 0, pos = 0;
    if (exteria_tgc_srtcp_unprotect(&c->recv_srtp, packet, len, &out) != EXTERIA_OK) {
        ctrace(c, "rtcp of the other side did not open (%u bytes)", (unsigned)len);
        return;
    }
    if (++c->rtcp_rx == 1) ctrace(c, "first rtcp received (%u bytes, type %u)", (unsigned)out, out >= 2 ? (unsigned)packet[1] : 0u);
    while (pos + 8 <= out) {
        size_t words = ((size_t)packet[pos + 2] << 8 | packet[pos + 3]) + 1, bytes = words * 4;
        uint8_t type = packet[pos + 1], fmt = packet[pos] & 0x1F;
        if ((packet[pos] >> 6) != 2 || pos + bytes > out) return;
        if (type == 200 && bytes >= 16) {
            uint32_t sender = (uint32_t)packet[pos + 4] << 24 | (uint32_t)packet[pos + 5] << 16 | (uint32_t)packet[pos + 6] << 8 | packet[pos + 7];
            uint32_t middle = (uint32_t)packet[pos + 10] << 24 | (uint32_t)packet[pos + 11] << 16 | (uint32_t)packet[pos + 12] << 8 | packet[pos + 13];
            if (c->audio_stats.started && sender == c->audio_stats.ssrc) exteria_rtp_stats_sender_report(&c->audio_stats, middle, c->now_ms);
            if (c->video_stats.started && sender == c->video_stats.ssrc) exteria_rtp_stats_sender_report(&c->video_stats, middle, c->now_ms);
        }
        /* the reports of the other side say whether it receives our streams: a block for our video ssrc with a moving sequence number is a picture that arrives */
        if ((type == 200 || type == 201) && (c->rtcp_reports_traced < 12 || c->video_reports_traced < 12)) {
            size_t first = pos + (type == 200 ? 28 : 8), block;
            unsigned count = fmt;
            for (block = 0; block < count && first + 24 <= pos + bytes; ++block, first += 24) {
                const uint8_t *b = packet + first;
                uint32_t reported = (uint32_t)b[0] << 24 | (uint32_t)b[1] << 16 | (uint32_t)b[2] << 8 | b[3];
                /* the block of our video ssrc has a count of its own, so the first twelve reports of the audio do not hide whether the picture arrives */
                if (reported == c->negotiator.local_ssrc[EXTERIA_TGC_STREAM_VIDEO]) {
                    if (++c->video_reports_traced > 12) continue;
                } else if (c->rtcp_reports_traced >= 12) {
                    continue;
                } else {
                    ++c->rtcp_reports_traced;
                }
                ctrace(c, "rtcp report block for ssrc %02x%02x%02x%02x: lost %u of 256, highest sequence %u, jitter %u", b[0], b[1], b[2], b[3], (unsigned)b[4],
                       (unsigned)((b[8] << 24) | (b[9] << 16) | (b[10] << 8) | b[11]), (unsigned)((b[12] << 24) | (b[13] << 16) | (b[14] << 8) | b[15]));
            }
            if (count == 0 && c->rtcp_reports_traced < 12) {
                ++c->rtcp_reports_traced;
                ctrace(c, "rtcp report of type %u without a block: the other side has received nothing of ours yet", (unsigned)type);
            }
        }
        if (type == RTCP_PSFB && (fmt == RTCP_FMT_PLI || fmt == RTCP_FMT_FIR) && bytes >= 12) {
            uint32_t media = (uint32_t)packet[pos + 8] << 24 | (uint32_t)packet[pos + 9] << 16 | (uint32_t)packet[pos + 10] << 8 | packet[pos + 11];
            if ((media == c->negotiator.local_ssrc[EXTERIA_TGC_STREAM_VIDEO] || media == 0) && c->events.key_frame_requested) {
                if (++c->key_frame_requests <= 5) ctrace(c, "the other side asks for a key frame of our video (request %u)", c->key_frame_requests);
                c->events.key_frame_requested(c->events.context);
            }
        }
        pos += bytes;
    }
}

static void request_key_frame(exteria_tgc_call *c, uint64_t now_ms) {
    uint8_t buf[EXTERIA_RTCP_PLI_LEN + EXTERIA_TGC_SRTCP_TRAILER_LEN];
    size_t n = 0;
    uint32_t media = c->negotiator.incoming[EXTERIA_TGC_STREAM_VIDEO].ssrc;
    if (!c->srtp_ready || media == 0 || (c->last_pli_ms && now_ms - c->last_pli_ms < EXTERIA_TGC_CALL_PLI_INTERVAL_MS)) return;
    if (exteria_rtcp_write_pli(buf, sizeof(buf), c->negotiator.local_ssrc[EXTERIA_TGC_STREAM_AUDIO], media) != EXTERIA_OK) return;
    if (exteria_tgc_srtcp_protect(&c->send_srtp, buf, EXTERIA_RTCP_PLI_LEN, sizeof(buf), &n) != EXTERIA_OK) return;
    c->last_pli_ms = now_ms;
    exteria_tgc_ice_send(&c->ice, buf, n);
}

/* a receiver report for the streams that come in, so the other side's encoder can follow loss and delay on this side */
static void send_receiver_report(exteria_tgc_call *c, uint64_t now_ms) {
    uint8_t blocks[2 * EXTERIA_RTCP_BLOCK_LEN];
    uint8_t buf[8 + 2 * EXTERIA_RTCP_BLOCK_LEN + EXTERIA_TGC_SRTCP_TRAILER_LEN];
    size_t count = 0, len = 0, n = 0;
    if (!c->srtp_ready || c->ice.selected < 0) return;
    if (c->last_report_ms && now_ms - c->last_report_ms < REPORT_INTERVAL_MS) return;
    if (exteria_rtp_stats_block(&c->audio_stats, now_ms, blocks + count * EXTERIA_RTCP_BLOCK_LEN) == EXTERIA_OK) ++count;
    if (exteria_rtp_stats_block(&c->video_stats, now_ms, blocks + count * EXTERIA_RTCP_BLOCK_LEN) == EXTERIA_OK) ++count;
    c->last_report_ms = now_ms ? now_ms : 1;
    if (count == 0) return;
    if (exteria_rtcp_write_receiver_report(buf, sizeof(buf), c->negotiator.local_ssrc[EXTERIA_TGC_STREAM_AUDIO], blocks, count, &len) != EXTERIA_OK) return;
    if (exteria_tgc_srtcp_protect(&c->send_srtp, buf, len, sizeof(buf), &n) != EXTERIA_OK) return;
    if (++c->reports_sent <= 3 || c->reports_sent % 20 == 0) {
        ctrace(c, "receiver report %u sent (%u blocks, video: %u packets, highest sequence %u)", c->reports_sent, (unsigned)count, c->video_stats.received,
               (unsigned)c->video_stats.max_sequence);
    }
    exteria_tgc_ice_send(&c->ice, buf, n);
}

exteria_status exteria_tgc_call_request_key_frame(exteria_tgc_call *c, uint64_t now_ms) {
    if (!c) return EXTERIA_E_ARG;
    if (!c->srtp_ready || !c->negotiator.incoming[EXTERIA_TGC_STREAM_VIDEO].active || c->ice.selected < 0) return EXTERIA_E_STATE;
    request_key_frame(c, now_ms);
    return EXTERIA_OK;
}

static void handle_video_packet(exteria_tgc_call *c, const uint8_t *payload, size_t len, const exteria_rtp_header *h) {
    exteria_vp8_frame_info info;
    exteria_status status;
    if (!c->video_storage) {
        c->video_storage = (uint8_t *)malloc(EXTERIA_TGC_CALL_VIDEO_FRAME_MAX);
        if (!c->video_storage || exteria_vp8_depacketizer_init(&c->depack, c->video_storage, EXTERIA_TGC_CALL_VIDEO_FRAME_MAX) != EXTERIA_OK) return;
    }
    /* a new ssrc (the other side restarted its camera) begins a new stream */
    if (c->video_ssrc_seen != h->ssrc) {
        exteria_vp8_depacketizer_init(&c->depack, c->video_storage, EXTERIA_TGC_CALL_VIDEO_FRAME_MAX);
        c->video_ssrc_seen = h->ssrc;
    }
    status = exteria_vp8_depacketizer_push(&c->depack, h->sequence, h->timestamp, h->marker, payload, len, &info);
    if (status == EXTERIA_OK && info.ready && c->events.video) c->events.video(c->events.context, c->video_storage, info.length, info.key_frame, info.timestamp);
    if (c->depack.need_key_frame) request_key_frame(c, c->now_ms);
}

static void handle_rtp(exteria_tgc_call *c, const uint8_t *data, size_t len) {
    uint8_t buf[EXTERIA_DTLS_MAX_DATAGRAM];
    size_t n = 0;
    exteria_rtp_header h;
    const exteria_tgc_stream *audio = &c->negotiator.incoming[EXTERIA_TGC_STREAM_AUDIO], *video = &c->negotiator.incoming[EXTERIA_TGC_STREAM_VIDEO];
    if (len > sizeof(buf)) return;
    memcpy(buf, data, len);
    if (exteria_tgc_srtp_unprotect(&c->recv_srtp, buf, len, &n) != EXTERIA_OK) return;
    if (exteria_rtp_parse(buf, n, &h) != EXTERIA_OK || h.payload_len == 0) return;
    if (audio->active && h.ssrc == audio->ssrc && h.payload_type == audio->payload_type) {
        if (++c->audio_rx == 1) ctrace(c, "first audio packet received (%u bytes)", (unsigned)h.payload_len);
        if (c->audio_stats.ssrc != h.ssrc) exteria_rtp_stats_reset(&c->audio_stats, h.ssrc);
        exteria_rtp_stats_update(&c->audio_stats, h.sequence);
        if (c->events.audio) c->events.audio(c->events.context, buf + h.payload_offset, h.payload_len, h.sequence, h.timestamp);
    } else if (video->active && h.ssrc == video->ssrc && h.payload_type == video->payload_type) {
        if (++c->video_rx == 1) ctrace(c, "first video packet received (%u bytes)", (unsigned)h.payload_len);
        if (c->video_stats.ssrc != h.ssrc) exteria_rtp_stats_reset(&c->video_stats, h.ssrc);
        exteria_rtp_stats_update(&c->video_stats, h.sequence);
        handle_video_packet(c, buf + h.payload_offset, h.payload_len, &h);
    }
}

static void ice_payload(void *context, const uint8_t *data, size_t len) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    uint8_t first;
    if (len == 0) return;
    first = data[0];
    if (first >= 20 && first <= 63) {
        exteria_dtls_input(c->dtls, data, len);
        dtls_changed(c);
    } else if (first >= 128 && first <= 191 && c->srtp_ready && len >= 8) {
        uint8_t kind = data[1] & 0x7F;
        if (kind >= RTCP_TYPE_FIRST && kind <= RTCP_TYPE_LAST) {
            uint8_t copy[EXTERIA_DTLS_MAX_DATAGRAM];
            if (len <= sizeof(copy)) {
                memcpy(copy, data, len);
                handle_rtcp(c, copy, len);
            }
        } else {
            handle_rtp(c, data, len);
        }
    }
}

static void ice_send(void *context, unsigned index, const uint8_t *data, size_t len) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    if (c->events.send_datagram) c->events.send_datagram(c->events.context, index, data, len);
}

static void ice_candidate(void *context, const char *sdp) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    memset(&c->out_message, 0, sizeof(c->out_message));
    c->out_message.type = EXTERIA_TGC_MESSAGE_CANDIDATES;
    c->out_message.u.candidates.count = 1;
    snprintf(c->out_message.u.candidates.sdp[0], sizeof(c->out_message.u.candidates.sdp[0]), "%s", sdp);
    send_message(c, &c->out_message);
}

static void ice_trace(void *context, const char *line) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    if (c->events.trace) c->events.trace(c->events.context, line);
}

static void ice_state(void *context, exteria_tgc_ice_state state) {
    exteria_tgc_call *c = (exteria_tgc_call *)context;
    if (state == EXTERIA_TGC_ICE_CONNECTED) maybe_start_dtls(c);
    update_state(c);
}

exteria_status exteria_tgc_call_new(exteria_tgc_call **out, const exteria_tgc_call_config *config, const exteria_tgc_call_events *events) {
    exteria_tgc_call *c;
    exteria_tgc_ice_reflector_config reflectors[EXTERIA_TGC_ICE_MAX_REFLECTORS];
    exteria_tgc_ice_events ice_events;
    uint64_t tie = 0;
    uint32_t audio_ssrc, video_ssrc;
    size_t i;
    exteria_status status;
    if (out) *out = NULL;
    if (!out || !config || !events || config->reflector_count == 0 || config->reflector_count > EXTERIA_TGC_ICE_MAX_REFLECTORS) return EXTERIA_E_ARG;
    c = (exteria_tgc_call *)calloc(1, sizeof(*c));
    if (!c) return EXTERIA_E_NOMEM;
    c->events = *events;
    c->is_outgoing = config->is_outgoing ? 1 : 0;
    c->state = EXTERIA_TGC_CALL_CONNECTING;
    status = exteria_tgc_cipher_init(&c->cipher, config->key, config->is_outgoing);
    if (status != EXTERIA_OK) goto fail;
    random_text(c->local_ufrag, UFRAG_LEN);
    random_text(c->local_pwd, PWD_LEN);
    if (exteria_random(&tie, sizeof(tie)) != EXTERIA_OK) goto fail_crypto;
    for (i = 0; i < config->reflector_count; ++i) {
        reflectors[i] = config->reflectors[i];
        reflectors[i].local_tag = random_u32();
    }
    memset(&ice_events, 0, sizeof(ice_events));
    ice_events.context = c;
    ice_events.send = ice_send;
    ice_events.local_candidate = ice_candidate;
    ice_events.state = ice_state;
    ice_events.payload = ice_payload;
    ice_events.trace = ice_trace;
    status = exteria_tgc_ice_init(&c->ice, c->is_outgoing, tie, c->local_ufrag, c->local_pwd, reflectors, config->reflector_count, &ice_events);
    if (status != EXTERIA_OK) goto fail;
    /* a TURN server that does not take its credentials is left out: the reflectors still serve the call */
    for (i = 0; i < config->turn_count && i < EXTERIA_TGC_ICE_MAX_TURNS; ++i) {
        const exteria_tgc_call_turn *turn = &config->turns[i];
        (void)exteria_tgc_ice_add_turn(&c->ice, turn->ip, turn->port, turn->username, turn->password);
    }
    status = exteria_dtls_new(&c->dtls);
    if (status != EXTERIA_OK) goto fail;
    do {
        audio_ssrc = random_u32();
        video_ssrc = random_u32();
    } while (audio_ssrc == video_ssrc);
    status = exteria_tgc_negotiator_init(&c->negotiator, c->is_outgoing, audio_ssrc, video_ssrc);
    if (status != EXTERIA_OK) goto fail;
    c->audio_seq = (uint16_t)random_u32();
    c->audio_ts = random_u32();
    c->video_seq = (uint16_t)random_u32();
    if (config->with_video) {
        exteria_tgc_negotiator_set_video(&c->negotiator, 1);
        c->local_video_state = EXTERIA_TGC_VIDEO_ACTIVE;
    }
    *out = c;
    return EXTERIA_OK;
fail_crypto:
    status = EXTERIA_E_CRYPTO;
fail:
    exteria_tgc_call_free(c);
    return status;
}

void exteria_tgc_call_free(exteria_tgc_call *c) {
    if (!c) return;
    exteria_dtls_free(c->dtls);
    free(c->sctp);
    free(c->video_storage);
    exteria_tgc_cipher_wipe(&c->cipher);
    exteria_tgc_srtp_wipe(&c->send_srtp);
    exteria_tgc_srtp_wipe(&c->recv_srtp);
    memset(c->plain, 0, sizeof(c->plain));
    free(c);
}

exteria_status exteria_tgc_call_start(exteria_tgc_call *c, uint64_t now_ms) {
    if (!c) return EXTERIA_E_ARG;
    if (c->started) return EXTERIA_E_STATE;
    c->started = 1;
    c->now_ms = now_ms;
    if (c->is_outgoing) {
        send_initial_setup(c);
        send_offer_if_due(c);
    }
    exteria_tgc_ice_tick(&c->ice, now_ms);
    return EXTERIA_OK;
}

exteria_status exteria_tgc_call_datagram(exteria_tgc_call *c, unsigned index, const uint8_t *data, size_t len, uint64_t now_ms) {
    if (!c || !data) return EXTERIA_E_ARG;
    c->now_ms = now_ms;
    return exteria_tgc_ice_input(&c->ice, index, data, len, now_ms);
}

void exteria_tgc_call_tick(exteria_tgc_call *c, uint64_t now_ms) {
    if (!c || !c->started || c->failed) return;
    c->now_ms = now_ms;
    if (c->first_tick_ms == 0) c->first_tick_ms = now_ms ? now_ms : 1;
    if (c->state == EXTERIA_TGC_CALL_CONNECTING && now_ms - c->first_tick_ms > EXTERIA_TGC_CALL_CONNECT_TIMEOUT_MS) {
        ctrace(c, "no media path after %u ms: ice state %d, dtls started %d, srtp %d", (unsigned)(now_ms - c->first_tick_ms), (int)c->ice.state, (int)c->dtls_started, (int)c->srtp_ready);
        fail(c);
        return;
    }
    exteria_tgc_ice_tick(&c->ice, now_ms);
    if (c->dtls_started && exteria_dtls_get_state(c->dtls) == EXTERIA_DTLS_HANDSHAKING) {
        exteria_dtls_on_timeout(c->dtls);
        dtls_changed(c);
    }
    if (c->sctp) {
        exteria_tgc_sctp_tick(c->sctp, now_ms);
        if ((uint8_t)c->sctp->state != c->sctp_state_seen) {
            c->sctp_state_seen = (uint8_t)c->sctp->state;
            ctrace(c, "sctp state %d", (int)c->sctp->state);
        }
    }
    if (c->srtp_ready && c->depack.need_key_frame && c->video_storage) request_key_frame(c, now_ms);
    send_receiver_report(c, now_ms);
    update_state(c);
}

exteria_status exteria_tgc_call_send_audio(exteria_tgc_call *c, const uint8_t *opus, size_t len, uint32_t samples, uint64_t now_ms) {
    uint8_t buf[EXTERIA_TGC_CALL_RTP_PAYLOAD_MAX + EXTERIA_RTP_FIXED_LEN + EXTERIA_TGC_SRTP_TAG_LEN];
    size_t n = 0;
    const exteria_tgc_stream *out;
    (void)now_ms;
    if (!c || !opus) return EXTERIA_E_ARG;
    out = &c->negotiator.outgoing[EXTERIA_TGC_STREAM_AUDIO];
    if (!c->srtp_ready || !out->active || c->ice.selected < 0) return EXTERIA_E_STATE;
    if (len == 0 || len > EXTERIA_TGC_CALL_RTP_PAYLOAD_MAX) return EXTERIA_E_LIMIT;
    if (exteria_rtp_write_header(buf, sizeof(buf), out->payload_type, 0, c->audio_seq, c->audio_ts, out->ssrc) != EXTERIA_OK) return EXTERIA_E_STATE;
    memcpy(buf + EXTERIA_RTP_FIXED_LEN, opus, len);
    if (exteria_tgc_srtp_protect(&c->send_srtp, buf, EXTERIA_RTP_FIXED_LEN + len, sizeof(buf), &n) != EXTERIA_OK) return EXTERIA_E_CRYPTO;
    if (++c->audio_tx == 1) ctrace(c, "first audio packet sent (%u bytes)", (unsigned)len);
    ++c->audio_seq;
    c->audio_ts += samples;
    return exteria_tgc_ice_send(&c->ice, buf, n);
}

exteria_status exteria_tgc_call_send_video(exteria_tgc_call *c, const uint8_t *frame, size_t len, uint32_t timestamp, uint64_t now_ms) {
    exteria_vp8_packetizer p;
    uint8_t buf[EXTERIA_RTP_FIXED_LEN + EXTERIA_VP8_MAX_PAYLOAD + EXTERIA_TGC_SRTP_TAG_LEN];
    uint8_t payload[EXTERIA_VP8_MAX_PAYLOAD];
    size_t payload_len = 0, n = 0;
    int marker = 0;
    const exteria_tgc_stream *out;
    exteria_status status;
    (void)now_ms;
    if (!c || !frame) return EXTERIA_E_ARG;
    out = &c->negotiator.outgoing[EXTERIA_TGC_STREAM_VIDEO];
    if (!c->srtp_ready || !out->active || c->ice.selected < 0) return EXTERIA_E_STATE;
    /* no frame is marked non-reference: the encoder keeps its deltas as references, and a receiver that is told a delta may be dropped does not chain the
       pictures after it to that one */
    status = exteria_vp8_packetizer_init(&p, frame, len, VIDEO_PAYLOAD_ROOM, c->video_picture_id++, 0);
    if (status != EXTERIA_OK) return status;
    while (exteria_vp8_packetizer_next(&p, payload, sizeof(payload), &payload_len, &marker) == EXTERIA_OK) {
        if (exteria_rtp_write_header(buf, sizeof(buf), out->payload_type, marker, c->video_seq, timestamp, out->ssrc) != EXTERIA_OK) return EXTERIA_E_STATE;
        memcpy(buf + EXTERIA_RTP_FIXED_LEN, payload, payload_len);
        if (exteria_tgc_srtp_protect(&c->send_srtp, buf, EXTERIA_RTP_FIXED_LEN + payload_len, sizeof(buf), &n) != EXTERIA_OK) return EXTERIA_E_CRYPTO;
        ++c->video_seq;
        exteria_tgc_ice_send(&c->ice, buf, n);
    }
    if (++c->video_tx_frames <= 3) {
        ctrace(c, "video frame %u sent (%u bytes, %s, pt %u, ssrc %08x)", c->video_tx_frames, (unsigned)len, len > 0 && !(frame[0] & 1) ? "key" : "delta",
               (unsigned)out->payload_type, (unsigned)out->ssrc);
    }
    return EXTERIA_OK;
}

void exteria_tgc_call_set_video(exteria_tgc_call *c, int on, int rotation, uint64_t now_ms) {
    if (!c) return;
    c->now_ms = now_ms;
    c->local_video_state = on ? EXTERIA_TGC_VIDEO_ACTIVE : EXTERIA_TGC_VIDEO_INACTIVE;
    c->local_video_rotation = (rotation == 90 || rotation == 180 || rotation == 270) ? (uint16_t)rotation : 0;
    exteria_tgc_negotiator_set_video(&c->negotiator, on);
    if (c->started) send_offer_if_due(c);
    send_media_state(c, now_ms);
}

void exteria_tgc_call_set_muted(exteria_tgc_call *c, int muted, uint64_t now_ms) {
    if (!c) return;
    c->now_ms = now_ms;
    c->muted = muted ? 1 : 0;
    send_media_state(c, now_ms);
}

void exteria_tgc_call_streams(const exteria_tgc_call *c, exteria_tgc_stream outgoing[EXTERIA_TGC_STREAM_COUNT], exteria_tgc_stream incoming[EXTERIA_TGC_STREAM_COUNT]) {
    if (!c || !outgoing || !incoming) return;
    memcpy(outgoing, c->negotiator.outgoing, sizeof(c->negotiator.outgoing));
    memcpy(incoming, c->negotiator.incoming, sizeof(c->negotiator.incoming));
}

exteria_tgc_call_state exteria_tgc_call_get_state(const exteria_tgc_call *c) {
    return c ? c->state : EXTERIA_TGC_CALL_FAILED;
}

void exteria_tgc_call_diagnostics(const exteria_tgc_call *c, int *ice, int *dtls, int *sctp, unsigned *signals_in, unsigned *signals_out) {
    if (!c) return;
    if (ice) *ice = (int)c->ice.state;
    if (dtls) *dtls = (int)exteria_dtls_get_state(c->dtls);
    if (sctp) *sctp = c->sctp ? (int)c->sctp->state : -1;
    if (signals_in) *signals_in = c->signals_in;
    if (signals_out) *signals_out = c->signals_out;
}
