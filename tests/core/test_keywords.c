#include <stdlib.h>
#include <string.h>

#include "exteria_keywords.h"
#include "exteria_tl_ids.h"
#include "test_util.h"

#define FIRE "\xf0\x9f\x94\xa5"
#define HEART "\xe2\x9d\xa4\xef\xb8\x8f"
#define CAT "\xf0\x9f\x90\xb1"
#define FOOT "\xe2\x9a\xbd"

/* an emojiKeyword (or emojiKeywordDeleted) with the emoji given up to a NULL */
static exteria_tl_value *entry(exteria_arena *arena, const char *ctor, const char *keyword, const char *first, const char *second) {
    exteria_tl_value *item = exteria_tl_new_obj(arena, ctor);
    exteria_tl_value *list = exteria_tl_new_vec(arena, second ? 2u : (first ? 1u : 0u));
    if (first) exteria_tl_vec_set(list, 0, exteria_tl_new_str(arena, first));
    if (second) exteria_tl_vec_set(list, 1, exteria_tl_new_str(arena, second));
    exteria_tl_set_str(arena, item, "keyword", keyword);
    exteria_tl_set(item, "emoticons", list);
    return item;
}

static exteria_tl_value *difference(exteria_arena *arena, const char *lang, int32_t from, int32_t version, exteria_tl_value **items, uint32_t count) {
    exteria_tl_value *answer = exteria_tl_new_obj(arena, "emojiKeywordsDifference");
    exteria_tl_value *list = exteria_tl_new_vec(arena, count);
    for (uint32_t i = 0; i < count; ++i) exteria_tl_vec_set(list, i, items[i]);
    exteria_tl_set_str(arena, answer, "lang_code", lang);
    exteria_tl_set_i32(arena, answer, "from_version", from);
    exteria_tl_set_i32(arena, answer, "version", version);
    exteria_tl_set(answer, "keywords", list);
    return answer;
}

static void test_request(void) {
    exteria_arena arena;
    exteria_tl_value *request;
    const uint8_t *data;
    size_t length;
    int32_t from = -1;
    exteria_arena_init(&arena, 1 << 16);
    CHECK_EQ_INT(exteria_keywords_request(&arena, "ru", 0, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_messages_getEmojiKeywords));
    CHECK_EQ_INT(exteria_tl_get_bytes(request, "lang_code", &data, &length), EXTERIA_OK);
    CHECK_EQ_INT(length, 2);
    CHECK_EQ_INT(exteria_keywords_request(&arena, "en", 7, &request), EXTERIA_OK);
    CHECK(exteria_tl_is(request, EXTERIA_TL_ID_messages_getEmojiKeywordsDifference));
    CHECK_EQ_INT(exteria_tl_get_i32(request, "from_version", &from), EXTERIA_OK);
    CHECK_EQ_INT(from, 7);
    /* a language code is a few letters, digits, - and _ */
    CHECK_EQ_INT(exteria_keywords_request(&arena, "", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_keywords_request(&arena, "en US", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_keywords_request(&arena, "abcdefghijklmnop", 0, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_keywords_request(&arena, "en", -1, &request), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_keywords_request(NULL, "en", 0, &request), EXTERIA_E_ARG);
    exteria_arena_free(&arena);
}

static void test_search(void) {
    exteria_arena arena;
    exteria_keyword_index *index = exteria_keyword_index_new();
    exteria_tl_value *items[5];
    char found[16][EXTERIA_KEYWORD_EMOJI_MAX];
    exteria_arena_init(&arena, 1 << 16);
    items[0] = entry(&arena, "emojiKeyword", "fire", FIRE, NULL);
    items[1] = entry(&arena, "emojiKeyword", "fireplace", HEART, NULL);
    items[2] = entry(&arena, "emojiKeyword", "love fire", HEART, FIRE);
    items[3] = entry(&arena, "emojiKeyword", "\xd0\xba\xd0\xbe\xd1\x82", CAT, NULL);   /* "кот" */
    items[4] = entry(&arena, "emojiKeyword", "soccer", FOOT, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 0, 5, items, 5)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keyword_index_version(index), 5);
    CHECK_EQ_INT(exteria_keyword_index_count(index), 5);
    /* the same word first, then the words that begin with it, then a later word of a keyword; an emoji is listed once */
    CHECK_EQ_INT(exteria_keywords_search(index, "fire", found, 16), 2);
    CHECK_EQ_INT(strcmp(found[0], FIRE), 0);
    CHECK_EQ_INT(strcmp(found[1], HEART), 0);
    CHECK_EQ_INT(exteria_keywords_search(index, "fir", found, 16), 2);
    /* the case and the spaces around a query do not matter */
    CHECK_EQ_INT(exteria_keywords_search(index, "  FIRE ", found, 16), 2);
    CHECK_EQ_INT(strcmp(found[0], FIRE), 0);
    /* a word later in the keyword */
    CHECK_EQ_INT(exteria_keywords_search(index, "love", found, 16), 2);
    CHECK_EQ_INT(exteria_keywords_search(index, "ire", found, 16), 0);
    /* cyrillic capitals fold to the lower case the server sends */
    CHECK_EQ_INT(exteria_keywords_search(index, "\xd0\x9a\xd0\x9e\xd0\xa2", found, 16), 1);
    CHECK_EQ_INT(strcmp(found[0], CAT), 0);
    /* nothing for an empty query, an unknown one, or a result list of no room */
    CHECK_EQ_INT(exteria_keywords_search(index, "", found, 16), 0);
    CHECK_EQ_INT(exteria_keywords_search(index, "   ", found, 16), 0);
    CHECK_EQ_INT(exteria_keywords_search(index, "zzz", found, 16), 0);
    CHECK_EQ_INT(exteria_keywords_search(index, "fire", found, 1), 1);
    CHECK_EQ_INT(exteria_keywords_search(index, "fire", found, 0), 0);
    CHECK_EQ_INT(exteria_keywords_search(NULL, "fire", found, 16), 0);
    /* a query longer than a keyword can be finds nothing and does not run past its buffer */
    {
        char long_query[400];
        memset(long_query, 'a', sizeof(long_query) - 1);
        long_query[sizeof(long_query) - 1] = 0;
        CHECK_EQ_INT(exteria_keywords_search(index, long_query, found, 16), 0);
    }
    exteria_keyword_index_free(index);
    exteria_arena_free(&arena);
}

static void test_difference(void) {
    exteria_arena arena;
    exteria_keyword_index *index = exteria_keyword_index_new();
    exteria_tl_value *items[3];
    char found[8][EXTERIA_KEYWORD_EMOJI_MAX];
    exteria_arena_init(&arena, 1 << 16);
    items[0] = entry(&arena, "emojiKeyword", "ball", FOOT, NULL);
    items[1] = entry(&arena, "emojiKeyword", "red", HEART, FIRE);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 0, 1, items, 2)), EXTERIA_OK);
    /* version 2 adds an emoji to a keyword, removes one from another, and deletes the last of a third */
    items[0] = entry(&arena, "emojiKeyword", "ball", CAT, FOOT);
    items[1] = entry(&arena, "emojiKeywordDeleted", "red", FIRE, NULL);
    items[2] = entry(&arena, "emojiKeywordDeleted", "ball", FOOT, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 1, 2, items, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keywords_search(index, "ball", found, 8), 2);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 2, 3, items + 1, 2)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keyword_index_version(index), 3);
    CHECK_EQ_INT(exteria_keywords_search(index, "red", found, 8), 1);
    CHECK_EQ_INT(strcmp(found[0], HEART), 0);
    CHECK_EQ_INT(exteria_keywords_search(index, "ball", found, 8), 1);
    CHECK_EQ_INT(strcmp(found[0], CAT), 0);
    /* a keyword with no emoji left is gone */
    items[0] = entry(&arena, "emojiKeywordDeleted", "ball", CAT, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 3, 4, items, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keyword_index_count(index), 1);
    /* a difference that does not start at the version of the index asks for the full list */
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 2, 5, items, 1)), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_keyword_index_version(index), 4);
    /* the full list replaces everything */
    items[0] = entry(&arena, "emojiKeyword", "fresh", FIRE, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 0, 9, items, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keyword_index_count(index), 1);
    CHECK_EQ_INT(exteria_keywords_search(index, "red", found, 8), 0);
    CHECK_EQ_INT(exteria_keywords_search(index, "fresh", found, 8), 1);
    exteria_keyword_index_free(index);
    exteria_arena_free(&arena);
}

static void test_refused_answers_change_nothing(void) {
    exteria_arena arena;
    exteria_keyword_index *index = exteria_keyword_index_new();
    exteria_tl_value *items[2];
    exteria_tl_value *not_a_difference;
    char found[8][EXTERIA_KEYWORD_EMOJI_MAX];
    exteria_arena_init(&arena, 1 << 16);
    items[0] = entry(&arena, "emojiKeyword", "keep", FIRE, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 0, 1, items, 1)), EXTERIA_OK);
    /* the language of the answer is not the one asked */
    items[0] = entry(&arena, "emojiKeyword", "other", CAT, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "ru", 1, 2, items, 1)), EXTERIA_E_MALFORMED);
    /* a version that runs backwards, an empty keyword, a keyword over the cap, an answer of another type */
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 1, 0, items, 1)), EXTERIA_E_MALFORMED);
    items[0] = entry(&arena, "emojiKeyword", "", CAT, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 1, 2, items, 1)), EXTERIA_E_MALFORMED);
    {
        char long_word[EXTERIA_KEYWORD_MAX + 2];
        memset(long_word, 'x', sizeof(long_word) - 1);
        long_word[sizeof(long_word) - 1] = 0;
        items[0] = entry(&arena, "emojiKeyword", long_word, CAT, NULL);
        CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 1, 2, items, 1)), EXTERIA_E_MALFORMED);
    }
    not_a_difference = exteria_tl_new_obj(&arena, "messages.getEmojiKeywords");
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", not_a_difference), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_keywords_apply(index, "", NULL), EXTERIA_E_ARG);
    /* none of it reached the index, not even the entry before the bad one */
    items[0] = entry(&arena, "emojiKeyword", "good", CAT, NULL);
    items[1] = entry(&arena, "emojiKeyword", "", CAT, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 1, 2, items, 2)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_keyword_index_version(index), 1);
    CHECK_EQ_INT(exteria_keywords_search(index, "good", found, 8), 0);
    CHECK_EQ_INT(exteria_keywords_search(index, "keep", found, 8), 1);
    exteria_keyword_index_free(index);
    exteria_arena_free(&arena);
}

static void test_emoji_that_do_not_fit_are_skipped(void) {
    exteria_arena arena;
    exteria_keyword_index *index = exteria_keyword_index_new();
    exteria_tl_value *items[1];
    char found[8][EXTERIA_KEYWORD_EMOJI_MAX];
    char big[EXTERIA_KEYWORD_EMOJI_MAX + 4];
    exteria_arena_init(&arena, 1 << 16);
    memset(big, 'e', sizeof(big) - 1);
    big[sizeof(big) - 1] = 0;
    items[0] = entry(&arena, "emojiKeyword", "word", big, FIRE);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 0, 1, items, 1)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keywords_search(index, "word", found, 8), 1);
    CHECK_EQ_INT(strcmp(found[0], FIRE), 0);
    exteria_keyword_index_free(index);
    exteria_arena_free(&arena);
}

static void test_file_round_trip(void) {
    exteria_arena arena;
    exteria_keyword_index *index = exteria_keyword_index_new(), *again = NULL;
    exteria_tl_value *items[3];
    char found[8][EXTERIA_KEYWORD_EMOJI_MAX];
    uint8_t *bytes = NULL;
    size_t length = 0;
    exteria_arena_init(&arena, 1 << 16);
    items[0] = entry(&arena, "emojiKeyword", "fire", FIRE, HEART);
    items[1] = entry(&arena, "emojiKeyword", "\xd0\xba\xd0\xbe\xd1\x82", CAT, NULL);
    items[2] = entry(&arena, "emojiKeyword", "soccer", FOOT, NULL);
    CHECK_EQ_INT(exteria_keywords_apply(index, "en", difference(&arena, "en", 0, 42, items, 3)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keyword_index_encode(index, &bytes, &length), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keyword_index_decode(bytes, length, &again), EXTERIA_OK);
    CHECK_EQ_INT(exteria_keyword_index_version(again), 42);
    CHECK_EQ_INT(exteria_keyword_index_count(again), 3);
    CHECK_EQ_INT(exteria_keywords_search(again, "fire", found, 8), 2);
    CHECK_EQ_INT(strcmp(found[1], HEART), 0);
    exteria_keyword_index_free(again);
    again = NULL;
    /* every shorter file is refused, and so is a file with a byte changed in the header or a keyword out of order */
    for (size_t cut = 0; cut < length; ++cut) {
        CHECK_EQ_INT(exteria_keyword_index_decode(bytes, cut, &again), EXTERIA_E_MALFORMED);
        CHECK(again == NULL);
    }
    CHECK_EQ_INT(exteria_keyword_index_decode(bytes, length + 1, &again), EXTERIA_E_MALFORMED);
    bytes[0] ^= 1;
    CHECK_EQ_INT(exteria_keyword_index_decode(bytes, length, &again), EXTERIA_E_MALFORMED);
    bytes[0] ^= 1;
    bytes[4] = 9;
    CHECK_EQ_INT(exteria_keyword_index_decode(bytes, length, &again), EXTERIA_E_MALFORMED);
    bytes[4] = 1;
    /* the first keyword of the file is "fire"; making its first letter larger than the second keyword's breaks the order */
    bytes[16 + 5] = 'z';
    CHECK_EQ_INT(exteria_keyword_index_decode(bytes, length, &again), EXTERIA_E_MALFORMED);
    free(bytes);
    CHECK_EQ_INT(exteria_keyword_index_decode(NULL, 0, &again), EXTERIA_E_ARG);
    exteria_keyword_index_free(index);
    exteria_arena_free(&arena);
}

int main(void) {
    test_request();
    test_search();
    test_difference();
    test_refused_answers_change_nothing();
    test_emoji_that_do_not_fit_are_skipped();
    test_file_round_trip();
    return test_finish("test_keywords");
}
