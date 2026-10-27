#include "exteria_tgc_negotiate.h"

#include <ctype.h>
#include <string.h>

static uint8_t shifted(const exteria_tgc_negotiator *n, uint8_t payload) {
    return (uint8_t)(payload + (n->is_outgoing ? 0 : EXTERIA_TGC_CALLEE_PAYLOAD_SHIFT));
}

exteria_status exteria_tgc_negotiator_init(exteria_tgc_negotiator *n, int is_outgoing, uint32_t audio_ssrc, uint32_t video_ssrc) {
    if (!n) return EXTERIA_E_ARG;
    memset(n, 0, sizeof(*n));
    if (audio_ssrc == 0 || video_ssrc == 0 || audio_ssrc == video_ssrc) return EXTERIA_E_ARG;
    n->is_outgoing = is_outgoing ? 1 : 0;
    n->local_ssrc[EXTERIA_TGC_STREAM_AUDIO] = audio_ssrc;
    n->local_ssrc[EXTERIA_TGC_STREAM_VIDEO] = video_ssrc;
    n->need_offer = 1;
    return EXTERIA_OK;
}

void exteria_tgc_negotiator_set_video(exteria_tgc_negotiator *n, int on) {
    if (!n) return;
    on = on ? 1 : 0;
    if (n->want_video == on) return;
    n->want_video = (uint8_t)on;
    n->need_offer = 1;
}

int exteria_tgc_negotiator_wants_offer(const exteria_tgc_negotiator *n) {
    return n && n->need_offer && !n->pending;
}

static void fill_audio(const exteria_tgc_negotiator *n, exteria_tgc_content *c, uint32_t ssrc, uint8_t payload) {
    exteria_tgc_payload *p;
    memset(c, 0, sizeof(*c));
    c->video = 0;
    c->ssrc = ssrc;
    c->payload_count = 1;
    p = &c->payloads[0];
    p->id = payload;
    memcpy(p->name, "opus", 5);
    p->clockrate = 48000;
    p->channels = 2;
    p->param_count = 2;
    memcpy(p->params[0].key, "minptime", 9);
    memcpy(p->params[0].value, "10", 3);
    memcpy(p->params[1].key, "useinbandfec", 13);
    memcpy(p->params[1].value, "1", 2);
    (void)n;
}

/* what this app can use of the feedback a video sender offers: it sends picture loss and full intra requests, nothing else */
static void fill_video(exteria_tgc_content *c, uint32_t ssrc, uint8_t payload, int offer_pli, int offer_fir) {
    exteria_tgc_payload *p;
    memset(c, 0, sizeof(*c));
    c->video = 1;
    c->ssrc = ssrc;
    c->payload_count = 1;
    p = &c->payloads[0];
    p->id = payload;
    memcpy(p->name, "VP8", 4);
    p->clockrate = 90000;
    if (offer_fir) {
        memcpy(p->feedback[p->feedback_count].type, "ccm", 4);
        memcpy(p->feedback[p->feedback_count].subtype, "fir", 4);
        ++p->feedback_count;
    }
    if (offer_pli) {
        memcpy(p->feedback[p->feedback_count].type, "nack", 5);
        memcpy(p->feedback[p->feedback_count].subtype, "pli", 4);
        ++p->feedback_count;
    }
}

exteria_status exteria_tgc_negotiator_make_offer(exteria_tgc_negotiator *n, uint32_t exchange_id, exteria_tgc_negotiate *offer) {
    if (!n || !offer) return EXTERIA_E_ARG;
    memset(offer, 0, sizeof(*offer));
    if (exchange_id == 0) return EXTERIA_E_ARG;
    if (!n->need_offer || n->pending) return EXTERIA_E_STATE;
    offer->exchange_id = exchange_id;
    fill_audio(n, &offer->contents[0], n->local_ssrc[EXTERIA_TGC_STREAM_AUDIO], shifted(n, EXTERIA_TGC_OPUS_PAYLOAD));
    offer->content_count = 1;
    if (n->want_video) {
        fill_video(&offer->contents[1], n->local_ssrc[EXTERIA_TGC_STREAM_VIDEO], shifted(n, EXTERIA_TGC_VP8_PAYLOAD), 1, 1);
        /* tgcalls v2 builds its receive stream from ssrc groups, so an ungrouped video ssrc is never registered */
        offer->contents[1].group_count = 1;
        memcpy(offer->contents[1].groups[0].semantics, "SIM", 4);
        offer->contents[1].groups[0].count = 1;
        offer->contents[1].groups[0].ssrcs[0] = n->local_ssrc[EXTERIA_TGC_STREAM_VIDEO];
        offer->content_count = 2;
    }
    n->need_offer = 0;
    n->pending = 1;
    n->pending_id = exchange_id;
    return EXTERIA_OK;
}

static int has_feedback(const exteria_tgc_payload *p, const char *type, const char *subtype) {
    unsigned i;
    for (i = 0; i < p->feedback_count; ++i) {
        if (strcmp(p->feedback[i].type, type) == 0 && strcmp(p->feedback[i].subtype, subtype) == 0) return 1;
    }
    return 0;
}

static const exteria_tgc_payload *find_payload(const exteria_tgc_content *c, const char *name_lower) {
    unsigned i;
    for (i = 0; i < c->payload_count; ++i) {
        const char *a = c->payloads[i].name, *b = name_lower;
        while (*a && *b && tolower((unsigned char)*a) == *b) {
            ++a;
            ++b;
        }
        if (!*a && !*b) return &c->payloads[i];
    }
    return NULL;
}

static void set_stream(exteria_tgc_negotiator *n, exteria_tgc_stream *slot, const exteria_tgc_stream *value) {
    if (memcmp(slot, value, sizeof(*slot)) != 0) n->changed = 1;
    *slot = *value;
}

/* the answer of the other side to our offer: what they take of each channel we offered, found by ssrc */
static void take_answer(exteria_tgc_negotiator *n, const exteria_tgc_negotiate *answer) {
    int kind;
    n->pending = 0;
    for (kind = 0; kind < EXTERIA_TGC_STREAM_COUNT; ++kind) {
        exteria_tgc_stream stream;
        unsigned i;
        memset(&stream, 0, sizeof(stream));
        for (i = 0; i < answer->content_count; ++i) {
            const exteria_tgc_content *c = &answer->contents[i];
            const exteria_tgc_payload *p;
            if (c->ssrc != n->local_ssrc[kind] || c->video != (kind == EXTERIA_TGC_STREAM_VIDEO)) continue;
            p = find_payload(c, kind == EXTERIA_TGC_STREAM_VIDEO ? "vp8" : "opus");
            if (!p) continue;
            stream.active = 1;
            stream.ssrc = c->ssrc;
            stream.payload_type = p->id;
            if (kind == EXTERIA_TGC_STREAM_VIDEO) {
                stream.pli = (uint8_t)has_feedback(p, "nack", "pli");
                stream.fir = (uint8_t)has_feedback(p, "ccm", "fir");
            }
            break;
        }
        set_stream(n, &n->outgoing[kind], &stream);
    }
}

/* the offer of the other side: accept the Opus and VP8 channels in it, and answer with those only */
static void make_answer(exteria_tgc_negotiator *n, const exteria_tgc_negotiate *offer, exteria_tgc_negotiate *answer) {
    int kind;
    exteria_tgc_stream accepted[EXTERIA_TGC_STREAM_COUNT];
    unsigned i;
    memset(answer, 0, sizeof(*answer));
    memset(accepted, 0, sizeof(accepted));
    answer->exchange_id = offer->exchange_id;
    for (i = 0; i < offer->content_count; ++i) {
        const exteria_tgc_content *c = &offer->contents[i];
        const exteria_tgc_payload *p = find_payload(c, c->video ? "vp8" : "opus");
        exteria_tgc_content *out;
        exteria_tgc_stream *slot = &accepted[c->video ? EXTERIA_TGC_STREAM_VIDEO : EXTERIA_TGC_STREAM_AUDIO];
        if (!p || slot->active) continue;
        out = &answer->contents[answer->content_count++];
        if (c->video) {
            int pli = has_feedback(p, "nack", "pli"), fir = has_feedback(p, "ccm", "fir");
            fill_video(out, c->ssrc, p->id, pli, fir);
            slot->pli = (uint8_t)pli;
            slot->fir = (uint8_t)fir;
        } else {
            fill_audio(n, out, c->ssrc, p->id);
        }
        /* the answer names the offerer's ssrc and keeps its groups, so the offerer can find its own channel */
        out->group_count = c->group_count;
        memcpy(out->groups, c->groups, sizeof(out->groups));
        slot->active = 1;
        slot->ssrc = c->ssrc;
        slot->payload_type = p->id;
    }
    for (kind = 0; kind < EXTERIA_TGC_STREAM_COUNT; ++kind) set_stream(n, &n->incoming[kind], &accepted[kind]);
}

exteria_status exteria_tgc_negotiator_receive(exteria_tgc_negotiator *n, const exteria_tgc_negotiate *remote, exteria_tgc_negotiate *answer,
                                              int *send_answer) {
    if (send_answer) *send_answer = 0;
    if (answer) memset(answer, 0, sizeof(*answer));
    if (!n || !remote || !answer || !send_answer) return EXTERIA_E_ARG;
    if (remote->exchange_id == 0) return EXTERIA_E_MALFORMED;
    /* a message that names one of our own streams is the answer to an offer we have dropped since: there is nothing in it to accept */
    {
        unsigned i;
        for (i = 0; i < remote->content_count; ++i) {
            if (remote->contents[i].ssrc == n->local_ssrc[EXTERIA_TGC_STREAM_AUDIO] || remote->contents[i].ssrc == n->local_ssrc[EXTERIA_TGC_STREAM_VIDEO]) {
                if (n->pending && remote->exchange_id == n->pending_id) break;
                return EXTERIA_OK;
            }
        }
    }
    if (n->pending) {
        if (remote->exchange_id == n->pending_id) {
            take_answer(n, remote);
            if (n->has_deferred) {
                n->has_deferred = 0;
                make_answer(n, &n->deferred, answer);
                *send_answer = 1;
            }
            return EXTERIA_OK;
        }
        /* both sides offered at once: the side that placed the call wins, and answers the other's offer once its
           own is answered */
        if (n->is_outgoing) {
            n->deferred = *remote;
            n->has_deferred = 1;
            return EXTERIA_OK;
        }
        n->pending = 0;
        n->need_offer = 1;
    }
    make_answer(n, remote, answer);
    *send_answer = 1;
    return EXTERIA_OK;
}
