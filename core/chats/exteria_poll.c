#include "exteria_poll.h"

#include <string.h>

#include "exteria_messages.h"

#include "exteria_tl_ids.h"

/* text is cut at a character boundary when it does not fit */
static void copy_text(char *dst, size_t cap, const uint8_t *data, size_t len) {
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

/* the words of a TextWithEntities field, whose entities this reader does not use */
static int read_words(const exteria_tl_value *owner, const char *field, char *dst, size_t cap) {
    const exteria_tl_value *words = exteria_tl_get(owner, field);
    const uint8_t *data;
    size_t len;
    if (!exteria_tl_is(words, EXTERIA_TL_ID_textWithEntities) || exteria_tl_get_bytes(words, "text", &data, &len) != EXTERIA_OK || !len) return 0;
    copy_text(dst, cap, data, len);
    return 1;
}

int exteria_poll_read(const exteria_tl_value *media, exteria_poll *out) {
    const exteria_tl_value *poll, *answers, *results, *voters;
    uint32_t i, j;
    if (!out) return 0;
    memset(out, 0, sizeof(*out));
    if (!exteria_tl_is(media, EXTERIA_TL_ID_messageMediaPoll)) return 0;
    poll = exteria_tl_get(media, "poll");
    if (!exteria_tl_is(poll, EXTERIA_TL_ID_poll) || exteria_tl_get_i64(poll, "id", &out->id) != EXTERIA_OK ||
        !read_words(poll, "question", out->question, sizeof(out->question)) || exteria_tl_get_vec(poll, "answers", &answers) != EXTERIA_OK) {
        memset(out, 0, sizeof(*out));
        return 0;
    }
    out->closed = exteria_tl_has(poll, "closed") ? 1 : 0;
    out->public_voters = exteria_tl_has(poll, "public_voters") ? 1 : 0;
    out->multiple = exteria_tl_has(poll, "multiple_choice") ? 1 : 0;
    out->quiz = exteria_tl_has(poll, "quiz") ? 1 : 0;
    out->revoting_disabled = exteria_tl_has(poll, "revoting_disabled") ? 1 : 0;
    out->hide_results = exteria_tl_has(poll, "hide_results_until_close") ? 1 : 0;
    for (i = 0; i < answers->u.vec.count && out->answer_count < EXTERIA_POLL_ANSWERS_MAX; ++i) {
        const exteria_tl_value *item = answers->u.vec.items[i];
        const uint8_t *token;
        size_t token_len;
        exteria_poll_answer *answer = &out->answers[out->answer_count];
        if (!exteria_tl_is(item, EXTERIA_TL_ID_pollAnswer) || !read_words(item, "text", answer->text, sizeof(answer->text)) ||
            exteria_tl_get_bytes(item, "option", &token, &token_len) != EXTERIA_OK || !token_len || token_len > EXTERIA_POLL_OPTION_MAX) continue;
        memcpy(answer->option, token, token_len);
        answer->option_len = (uint8_t)token_len;
        ++out->answer_count;
    }
    if (!out->answer_count) {
        memset(out, 0, sizeof(*out));
        return 0;
    }
    out->present = 1;
    results = exteria_tl_get(media, "results");
    if (!exteria_tl_is(results, EXTERIA_TL_ID_pollResults)) return 1;
    exteria_tl_get_i32(results, "total_voters", &out->total_voters);
    if (exteria_tl_get_vec(results, "recent_voters", &voters) == EXTERIA_OK) {
        for (i = 0; i < voters->u.vec.count && out->recent_voter_count < EXTERIA_POLL_RECENT_MAX; ++i) {
            const exteria_tl_value *peer = voters->u.vec.items[i];
            int64_t user = 0;
            if (!exteria_tl_is(peer, EXTERIA_TL_ID_peerUser) || exteria_tl_get_i64(peer, "user_id", &user) != EXTERIA_OK || user <= 0) continue;
            out->recent_voters[out->recent_voter_count++] = user;
        }
    }
    if (exteria_tl_get_vec(results, "results", &voters) != EXTERIA_OK) return 1;
    for (i = 0; i < voters->u.vec.count; ++i) {
        const exteria_tl_value *item = voters->u.vec.items[i];
        const uint8_t *token;
        size_t token_len;
        int32_t count = 0;
        if (!exteria_tl_is(item, EXTERIA_TL_ID_pollAnswerVoters) || exteria_tl_get_bytes(item, "option", &token, &token_len) != EXTERIA_OK) continue;
        for (j = 0; j < out->answer_count; ++j) {
            exteria_poll_answer *answer = &out->answers[j];
            if (answer->option_len != token_len || memcmp(answer->option, token, token_len) != 0) continue;
            if (exteria_tl_get_i32(item, "voters", &count) == EXTERIA_OK && count > 0) {
                answer->voters = count;
                out->has_counts = 1;
            }
            answer->chosen = exteria_tl_has(item, "chosen") ? 1 : 0;
            answer->correct = exteria_tl_has(item, "correct") ? 1 : 0;
            break;
        }
    }
    return 1;
}

exteria_status exteria_poll_vote_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t message_id, const exteria_poll_choice *choices,
                                         size_t count, exteria_tl_value **out) {
    exteria_tl_value *request, *input, *list;
    exteria_status status;
    size_t i;
    if (out) *out = NULL;
    if (!arena || !peer || !out || message_id <= 0 || count > EXTERIA_POLL_ANSWERS_MAX || (count && !choices)) return EXTERIA_E_ARG;
    for (i = 0; i < count; ++i) if (!choices[i].option_len || choices[i].option_len > EXTERIA_POLL_OPTION_MAX) return EXTERIA_E_ARG;
    status = exteria_input_peer(arena, peer, &input);
    if (status != EXTERIA_OK) return status;
    list = exteria_tl_new_vec(arena, (uint32_t)count);
    request = exteria_tl_new_obj(arena, "messages.sendVote");
    if (!list || !request) return EXTERIA_E_NOMEM;
    for (i = 0; i < count && status == EXTERIA_OK; ++i) {
        exteria_tl_value *token = exteria_tl_new_bytes(arena, choices[i].option, choices[i].option_len);
        status = token ? exteria_tl_vec_set(list, (uint32_t)i, token) : EXTERIA_E_NOMEM;
    }
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "peer", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == EXTERIA_OK) status = exteria_tl_set(request, "options", list);
    if (status == EXTERIA_OK) *out = request;
    return status;
}
