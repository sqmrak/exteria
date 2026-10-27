#ifndef EXTERIA_POLL_H
#define EXTERIA_POLL_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_tl.h"

/* the server allows ten answers; a few more are kept in case a newer layer raises that */
#define EXTERIA_POLL_ANSWERS_MAX 12
#define EXTERIA_POLL_QUESTION_MAX 400
#define EXTERIA_POLL_ANSWER_MAX 200
/* the token that names an answer is at most this long (the server keeps to one byte, the schema allows a hundred) */
#define EXTERIA_POLL_OPTION_MAX 100
/* the server names the last few who voted of a public poll, and the clients show three of them */
#define EXTERIA_POLL_RECENT_MAX 3

typedef struct exteria_poll_answer {
    char text[EXTERIA_POLL_ANSWER_MAX];
    uint8_t option[EXTERIA_POLL_OPTION_MAX];
    uint8_t option_len;
    int32_t voters;         /* zero when the server did not count them for this account */
    uint8_t chosen;         /* this account voted for it */
    uint8_t correct;        /* the right answer of a quiz, told once the account answered or the quiz is over */
} exteria_poll_answer;

typedef struct exteria_poll {
    int64_t id;
    uint8_t present;        /* the message carries a poll */
    uint8_t closed;
    uint8_t public_voters;  /* the voters can be seen; otherwise the poll is anonymous */
    uint8_t multiple;       /* several answers can be picked */
    uint8_t quiz;           /* one answer is right */
    uint8_t revoting_disabled;  /* an answer cannot be taken back */
    uint8_t hide_results;   /* the counts stay hidden until the poll is closed */
    uint8_t has_counts;     /* the server told how many voted for the answers (not just that this account did) */
    int32_t total_voters;
    uint8_t answer_count;
    uint8_t recent_voter_count;
    int64_t recent_voters[EXTERIA_POLL_RECENT_MAX];  /* user ids, the newest first; a voter that is not a user is left out */
    char question[EXTERIA_POLL_QUESTION_MAX];
    exteria_poll_answer answers[EXTERIA_POLL_ANSWERS_MAX];
} exteria_poll;

/* reads a messageMediaPoll; returns 1 and fills out; 0 with out cleared for anything else, a poll without a
   question or without a usable answer */
int exteria_poll_read(const exteria_tl_value *media, exteria_poll *out);

struct exteria_peer_ref;

typedef struct exteria_poll_choice {
    uint8_t option[EXTERIA_POLL_OPTION_MAX];
    size_t option_len;
} exteria_poll_choice;

/* messages.sendVote. count is zero to take the vote back, and at most EXTERIA_POLL_ANSWERS_MAX; a token that is empty or too long, or a
   message id that is not positive, is EXTERIA_E_ARG */
exteria_status exteria_poll_vote_request(exteria_arena *arena, const struct exteria_peer_ref *peer, int32_t message_id, const exteria_poll_choice *choices,
                                         size_t count, exteria_tl_value **out);

#endif
