#include "exteria_tgc_negotiate.h"
#include "test_util.h"

#define CALLER_AUDIO 1001u
#define CALLER_VIDEO 1002u
#define CALLEE_AUDIO 2001u
#define CALLEE_VIDEO 2002u

static exteria_tgc_negotiator caller, callee;

static void start(void) {
    CHECK_EQ_INT(exteria_tgc_negotiator_init(&caller, 1, CALLER_AUDIO, CALLER_VIDEO), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_negotiator_init(&callee, 0, CALLEE_AUDIO, CALLEE_VIDEO), EXTERIA_OK);
}

/* a message goes through its wire form, as it does between two phones */
static void through_the_wire(const exteria_tgc_negotiate *in, exteria_tgc_negotiate *out) {
    static exteria_tgc_message message, parsed;
    char text[16384];
    size_t n = 0;
    memset(&message, 0, sizeof(message));
    message.type = EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS;
    message.u.negotiate = *in;
    CHECK_EQ_INT(exteria_tgc_message_write(&message, text, sizeof(text), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_message_parse(text, n, &parsed), EXTERIA_OK);
    CHECK_EQ_INT(parsed.type, EXTERIA_TGC_MESSAGE_NEGOTIATE_CHANNELS);
    *out = parsed.u.negotiate;
}

/* one offer from `from`, answered by `to`, the answer back to `from` */
static void exchange(exteria_tgc_negotiator *from, exteria_tgc_negotiator *to, uint32_t id) {
    exteria_tgc_negotiate offer, wire, answer, answer_wire, none;
    int send = 0, back = 0;
    CHECK_EQ_INT(exteria_tgc_negotiator_wants_offer(from), 1);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(from, id, &offer), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_negotiator_wants_offer(from), 0);
    through_the_wire(&offer, &wire);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(to, &wire, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 1);
    CHECK(answer.exchange_id == id);
    through_the_wire(&answer, &answer_wire);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(from, &answer_wire, &none, &back), EXTERIA_OK);
    CHECK_EQ_INT(back, 0);
    CHECK_EQ_INT(from->pending, 0);
}

static void audio_both_ways(void) {
    start();
    exchange(&caller, &callee, 7001);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK(caller.outgoing[EXTERIA_TGC_STREAM_AUDIO].ssrc == CALLER_AUDIO);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_AUDIO].payload_type, EXTERIA_TGC_OPUS_PAYLOAD);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].ssrc == CALLER_AUDIO);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].payload_type, EXTERIA_TGC_OPUS_PAYLOAD);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    CHECK_EQ_INT(caller.changed, 1);
    CHECK_EQ_INT(callee.changed, 1);

    /* the called side offers its own audio, with its shifted payload number */
    exchange(&callee, &caller, 7002);
    CHECK_EQ_INT(callee.outgoing[EXTERIA_TGC_STREAM_AUDIO].payload_type, EXTERIA_TGC_OPUS_PAYLOAD + EXTERIA_TGC_CALLEE_PAYLOAD_SHIFT);
    CHECK(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].ssrc == CALLEE_AUDIO);
    CHECK_EQ_INT(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].payload_type, EXTERIA_TGC_OPUS_PAYLOAD + EXTERIA_TGC_CALLEE_PAYLOAD_SHIFT);
    /* nothing more is due */
    CHECK_EQ_INT(exteria_tgc_negotiator_wants_offer(&caller), 0);
    CHECK_EQ_INT(exteria_tgc_negotiator_wants_offer(&callee), 0);
    {
        exteria_tgc_negotiate offer;
        CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&caller, 9, &offer), EXTERIA_E_STATE);
    }
}

static void video_on_and_off(void) {
    exteria_tgc_negotiate offer, wire, answer, answer_wire, none;
    int send = 0, back = 0;
    start();
    exchange(&caller, &callee, 1);
    exchange(&callee, &caller, 2);
    caller.changed = callee.changed = 0;

    exteria_tgc_negotiator_set_video(&caller, 1);
    exteria_tgc_negotiator_set_video(&caller, 1);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&caller, 3, &offer), EXTERIA_OK);
    CHECK_EQ_INT(offer.content_count, 2);
    CHECK_EQ_INT(offer.contents[1].group_count, 1);
    CHECK(strcmp(offer.contents[1].groups[0].semantics, "SIM") == 0);
    CHECK_EQ_INT(offer.contents[1].groups[0].count, 1);
    CHECK(offer.contents[1].groups[0].ssrcs[0] == CALLER_VIDEO);
    through_the_wire(&offer, &wire);
    CHECK_EQ_INT(wire.contents[1].group_count, 1);
    CHECK(wire.contents[1].groups[0].ssrcs[0] == wire.contents[1].ssrc);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &wire, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 1);
    through_the_wire(&answer, &answer_wire);
    CHECK_EQ_INT(answer_wire.contents[1].group_count, 1);
    CHECK(answer_wire.contents[1].groups[0].ssrcs[0] == CALLER_VIDEO);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &answer_wire, &none, &back), EXTERIA_OK);
    CHECK_EQ_INT(back, 0);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].active, 1);
    CHECK(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].ssrc == CALLER_VIDEO);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].payload_type, EXTERIA_TGC_VP8_PAYLOAD);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].pli, 1);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].fir, 1);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_VIDEO].active, 1);
    CHECK(callee.incoming[EXTERIA_TGC_STREAM_VIDEO].ssrc == CALLER_VIDEO);
    CHECK_EQ_INT(callee.changed, 1);
    /* the audio stays as it was */
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 1);

    /* the other side turns its camera on after */
    exteria_tgc_negotiator_set_video(&callee, 1);
    exchange(&callee, &caller, 4);
    CHECK_EQ_INT(callee.outgoing[EXTERIA_TGC_STREAM_VIDEO].payload_type, EXTERIA_TGC_VP8_PAYLOAD + EXTERIA_TGC_CALLEE_PAYLOAD_SHIFT);
    CHECK_EQ_INT(caller.incoming[EXTERIA_TGC_STREAM_VIDEO].active, 1);
    CHECK(caller.incoming[EXTERIA_TGC_STREAM_VIDEO].ssrc == CALLEE_VIDEO);

    /* the caller's camera goes off: the offer lists only the audio and the video stream is gone on both ends */
    callee.changed = caller.changed = 0;
    exteria_tgc_negotiator_set_video(&caller, 0);
    exchange(&caller, &callee, 5);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK_EQ_INT(callee.changed, 1);
    CHECK_EQ_INT(caller.incoming[EXTERIA_TGC_STREAM_VIDEO].active, 1);
}

static void refusals(void) {
    exteria_tgc_negotiate offer, answer, none;
    int send = 0;
    start();
    /* a video channel with no VP8 in it, and an audio channel with no Opus, are answered by leaving them out */
    memset(&offer, 0, sizeof(offer));
    offer.exchange_id = 40;
    offer.content_count = 2;
    offer.contents[0].video = 1;
    offer.contents[0].ssrc = 500;
    offer.contents[1].video = 0;
    offer.contents[1].ssrc = 501;
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &offer, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 1);
    CHECK(answer.exchange_id == 40);
    CHECK_EQ_INT(answer.content_count, 0);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 0);

    /* two audio channels in one offer: the first is taken */
    memset(&offer, 0, sizeof(offer));
    offer.exchange_id = 41;
    offer.content_count = 2;
    {
        int i;
        for (i = 0; i < 2; ++i) {
            offer.contents[i].ssrc = 600u + (uint32_t)i;
            offer.contents[i].payload_count = 1;
            offer.contents[i].payloads[0].id = (uint8_t)(96 + i);
            memcpy(offer.contents[i].payloads[0].name, "opus", 5);
            offer.contents[i].payloads[0].clockrate = 48000;
        }
    }
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &offer, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(answer.content_count, 1);
    CHECK(answer.contents[0].ssrc == 600);
    CHECK_EQ_INT(answer.contents[0].payloads[0].id, 96);
    CHECK(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].ssrc == 600);

    /* the offerer's payload number and codec name case are kept, and the feedback in the answer is what both sides can do */
    memset(&offer, 0, sizeof(offer));
    offer.exchange_id = 42;
    offer.content_count = 1;
    offer.contents[0].video = 1;
    offer.contents[0].ssrc = 700;
    offer.contents[0].payload_count = 1;
    offer.contents[0].payloads[0].id = 98;
    memcpy(offer.contents[0].payloads[0].name, "vp8", 4);
    offer.contents[0].payloads[0].clockrate = 90000;
    offer.contents[0].payloads[0].feedback_count = 2;
    memcpy(offer.contents[0].payloads[0].feedback[0].type, "goog-remb", 10);
    memcpy(offer.contents[0].payloads[0].feedback[1].type, "nack", 5);
    memcpy(offer.contents[0].payloads[0].feedback[1].subtype, "pli", 4);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &offer, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(answer.contents[0].payloads[0].id, 98);
    CHECK_EQ_INT(answer.contents[0].payloads[0].feedback_count, 1);
    CHECK(strcmp(answer.contents[0].payloads[0].feedback[0].subtype, "pli") == 0);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_VIDEO].pli, 1);
    CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_VIDEO].fir, 0);

    /* an answer that does not take our video leaves it inactive, and so does one that names a stream we never offered */
    start();
    exteria_tgc_negotiator_set_video(&caller, 1);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&caller, 50, &offer), EXTERIA_OK);
    CHECK_EQ_INT(offer.content_count, 2);
    memset(&answer, 0, sizeof(answer));
    answer.exchange_id = 50;
    answer.content_count = 2;
    answer.contents[0] = offer.contents[0];
    answer.contents[1] = offer.contents[1];
    answer.contents[1].ssrc = 424242;
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &answer, &none, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 0);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].active, 0);
    /* a video content that kept the ssrc but carries an audio codec is no acceptance */
    start();
    exteria_tgc_negotiator_set_video(&caller, 1);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&caller, 51, &offer), EXTERIA_OK);
    answer = offer;
    answer.contents[1].video = 0;
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &answer, &none, &send), EXTERIA_OK);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_VIDEO].active, 0);
}

static void simultaneous_offers(void) {
    exteria_tgc_negotiate from_caller, from_callee, answer, none;
    int send = 0;
    start();
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&caller, 100, &from_caller), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&callee, 200, &from_callee), EXTERIA_OK);

    /* the caller ignores the callee's offer and keeps waiting for the answer to its own */
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &from_callee, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 0);
    CHECK_EQ_INT(caller.pending, 1);
    CHECK_EQ_INT(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 0);

    /* the callee drops its own offer, answers, and owes a new one */
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &from_caller, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 1);
    CHECK(answer.exchange_id == 100);
    CHECK_EQ_INT(callee.pending, 0);
    CHECK_EQ_INT(exteria_tgc_negotiator_wants_offer(&callee), 1);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &answer, &none, &send), EXTERIA_OK);
    CHECK_EQ_INT(caller.pending, 0);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_AUDIO].active, 1);

    /* the answer the caller would have made to the dropped offer is stale on arrival and accepts nothing */
    {
        exteria_tgc_negotiate stale = from_callee;
        CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &stale, &answer, &send), EXTERIA_OK);
        CHECK_EQ_INT(send, 0);
        CHECK_EQ_INT(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 1);
        CHECK(callee.incoming[EXTERIA_TGC_STREAM_AUDIO].ssrc == CALLER_AUDIO);
    }
    exchange(&callee, &caller, 201);
    CHECK_EQ_INT(callee.outgoing[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK_EQ_INT(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].ssrc == CALLEE_AUDIO);
}

/* the callee answers the caller's offer and sends its own new one at once, and the two reach the caller in the other order: the new offer is not lost */
static void offers_out_of_order(void) {
    exteria_tgc_negotiate from_caller, dropped, answer, new_offer, reply, none;
    int send = 0;
    start();
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&caller, 100, &from_caller), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&callee, 200, &dropped), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &from_caller, &answer, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 1);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&callee, 201, &new_offer), EXTERIA_OK);

    /* the new offer first: nothing to say yet, and nothing accepted */
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &new_offer, &reply, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 0);
    CHECK_EQ_INT(caller.pending, 1);
    CHECK_EQ_INT(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 0);

    /* then the answer to ours: taken, and the waiting offer is answered with its own id */
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &answer, &reply, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 1);
    CHECK(reply.exchange_id == 201);
    CHECK_EQ_INT(caller.pending, 0);
    CHECK_EQ_INT(caller.outgoing[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK_EQ_INT(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].active, 1);
    CHECK(caller.incoming[EXTERIA_TGC_STREAM_AUDIO].ssrc == CALLEE_AUDIO);
    CHECK_EQ_INT(caller.has_deferred, 0);

    /* the callee takes that answer as the one to its new offer */
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&callee, &reply, &none, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 0);
    CHECK_EQ_INT(callee.pending, 0);
    CHECK_EQ_INT(callee.outgoing[EXTERIA_TGC_STREAM_AUDIO].active, 1);

    /* an offer that arrived while ours was out and was answered is not answered a second time */
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&caller, &answer, &reply, &send), EXTERIA_OK);
    CHECK_EQ_INT(send, 0);
}

static void arguments(void) {
    exteria_tgc_negotiator n;
    exteria_tgc_negotiate o, a;
    int send = 9;
    CHECK_EQ_INT(exteria_tgc_negotiator_init(NULL, 1, 1, 2), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_init(&n, 1, 0, 2), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_init(&n, 1, 1, 0), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_init(&n, 1, 5, 5), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_init(&n, 1, 1, 2), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&n, 0, &o), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&n, 3, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&n, 3, &o), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_negotiator_make_offer(&n, 4, &o), EXTERIA_E_STATE);
    memset(&o, 0, sizeof(o));
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&n, &o, &a, &send), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(send, 0);
    o.exchange_id = 8;
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(NULL, &o, &a, &send), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&n, NULL, &a, &send), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&n, &o, NULL, &send), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_receive(&n, &o, &a, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_negotiator_wants_offer(NULL), 0);
    exteria_tgc_negotiator_set_video(NULL, 1);
}

int main(void) {
    audio_both_ways();
    video_on_and_off();
    refusals();
    simultaneous_offers();
    offers_out_of_order();
    arguments();
    return test_finish("test_tgc_negotiate");
}
