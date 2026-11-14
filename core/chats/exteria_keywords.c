#include "exteria_keywords.h"

#include <stdlib.h>
#include <string.h>

#include "exteria_tl_ids.h"

/* one keyword and its emoji in one block: keyword, NUL, then each emoji and a NUL. the blocks are sorted by keyword bytes */
typedef struct keyword_block {
    uint16_t keyword_len;
    uint8_t emoji_count;
    uint16_t data_len;
    char data[];
} keyword_block;

struct exteria_keyword_index {
    int32_t version;
    keyword_block **blocks;
    size_t count;
    size_t capacity;
};

#define FILE_MAGIC "EXKW"
#define FILE_FORMAT 1u
#define LANG_MAX 15
/* the emoji one keyword of an answer may name, before the cap of what the index keeps for it */
#define EMOTICONS_PER_ANSWER_MAX 4096u

exteria_keyword_index *exteria_keyword_index_new(void) {
    return calloc(1, sizeof(exteria_keyword_index));
}

static void index_clear(exteria_keyword_index *index) {
    for (size_t i = 0; i < index->count; ++i) free(index->blocks[i]);
    index->count = 0;
    index->version = 0;
}

void exteria_keyword_index_free(exteria_keyword_index *index) {
    if (!index) return;
    index_clear(index);
    free(index->blocks);
    free(index);
}

int32_t exteria_keyword_index_version(const exteria_keyword_index *index) { return index ? index->version : 0; }
size_t exteria_keyword_index_count(const exteria_keyword_index *index) { return index ? index->count : 0; }

static int block_compare(const keyword_block *block, const char *keyword, size_t length) {
    size_t common = block->keyword_len < length ? block->keyword_len : length;
    int order = memcmp(block->data, keyword, common);
    if (order) return order;
    if (block->keyword_len == length) return 0;
    return block->keyword_len < length ? -1 : 1;
}

/* the position of the keyword, or where it would go */
static size_t block_find(const exteria_keyword_index *index, const char *keyword, size_t length, int *found) {
    size_t low = 0, high = index->count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        int order = block_compare(index->blocks[middle], keyword, length);
        if (order == 0) { *found = 1; return middle; }
        if (order < 0) low = middle + 1;
        else high = middle;
    }
    *found = 0;
    return low;
}

static keyword_block *block_make(const char *keyword, size_t keyword_len, const char *emoji_run, size_t emoji_len, unsigned emoji_count) {
    size_t data_len = keyword_len + 1 + emoji_len;
    keyword_block *block = malloc(sizeof(*block) + data_len);
    if (!block) return NULL;
    block->keyword_len = (uint16_t)keyword_len;
    block->emoji_count = (uint8_t)emoji_count;
    block->data_len = (uint16_t)data_len;
    memcpy(block->data, keyword, keyword_len);
    block->data[keyword_len] = 0;
    if (emoji_len) memcpy(block->data + keyword_len + 1, emoji_run, emoji_len);
    return block;
}

static exteria_status index_insert(exteria_keyword_index *index, size_t at, keyword_block *block) {
    if (index->count == index->capacity) {
        size_t capacity = index->capacity ? index->capacity * 2 : 1024;
        keyword_block **grown = realloc(index->blocks, capacity * sizeof(*grown));
        if (!grown) return EXTERIA_E_NOMEM;
        index->blocks = grown;
        index->capacity = capacity;
    }
    memmove(index->blocks + at + 1, index->blocks + at, (index->count - at) * sizeof(*index->blocks));
    index->blocks[at] = block;
    ++index->count;
    return EXTERIA_OK;
}

static int emoji_valid(const uint8_t *data, uint32_t length) {
    return length > 0 && length < EXTERIA_KEYWORD_EMOJI_MAX && !memchr(data, 0, length);
}

/* adds the emoji to the keyword, which is made when it is new; an emoji it already lists is skipped */
static exteria_status add_emoji(exteria_keyword_index *index, const char *keyword, size_t keyword_len, const exteria_tl_value *emoticons) {
    int found;
    size_t at = block_find(index, keyword, keyword_len, &found);
    keyword_block *old = found ? index->blocks[at] : NULL;
    size_t run_cap = (old ? old->data_len - old->keyword_len - 1u : 0u) + (size_t)emoticons->u.vec.count * EXTERIA_KEYWORD_EMOJI_MAX;
    char *run = malloc(run_cap ? run_cap : 1);
    size_t run_len = old ? (size_t)old->data_len - old->keyword_len - 1u : 0u;
    unsigned count = old ? old->emoji_count : 0;
    keyword_block *block;
    if (!run) return EXTERIA_E_NOMEM;
    if (old) memcpy(run, old->data + old->keyword_len + 1, run_len);
    for (uint32_t i = 0; i < emoticons->u.vec.count; ++i) {
        const exteria_tl_value *item = emoticons->u.vec.items[i];
        if (!item || item->kind != EXTERIA_TL_V_BYTES || !emoji_valid(item->u.bytes.data, item->u.bytes.len)) continue;
        char text[EXTERIA_KEYWORD_EMOJI_MAX];
        memcpy(text, item->u.bytes.data, item->u.bytes.len);
        text[item->u.bytes.len] = 0;
        int present = 0;
        for (size_t scan = 0; scan < run_len;) {
            size_t have = strlen(run + scan);
            if (have == item->u.bytes.len && !memcmp(run + scan, text, have)) { present = 1; break; }
            scan += have + 1;
        }
        if (present || count >= EXTERIA_KEYWORD_EMOJI_PER) continue;
        memcpy(run + run_len, text, item->u.bytes.len + 1u);
        run_len += item->u.bytes.len + 1u;
        ++count;
    }
    if (count == 0) { free(run); return EXTERIA_OK; }
    block = block_make(keyword, keyword_len, run, run_len, count);
    free(run);
    if (!block) return EXTERIA_E_NOMEM;
    if (old) {
        free(old);
        index->blocks[at] = block;
        return EXTERIA_OK;
    }
    if (index->count >= EXTERIA_KEYWORDS_MAX) { free(block); return EXTERIA_E_LIMIT; }
    exteria_status status = index_insert(index, at, block);
    if (status != EXTERIA_OK) free(block);
    return status;
}

static exteria_status remove_emoji(exteria_keyword_index *index, const char *keyword, size_t keyword_len, const exteria_tl_value *emoticons) {
    int found;
    size_t at = block_find(index, keyword, keyword_len, &found);
    if (!found) return EXTERIA_OK;
    keyword_block *old = index->blocks[at];
    size_t run_len = (size_t)old->data_len - old->keyword_len - 1u;
    char *run = malloc(run_len ? run_len : 1);
    size_t kept_len = 0;
    unsigned kept = 0;
    if (!run) return EXTERIA_E_NOMEM;
    const char *scan = old->data + old->keyword_len + 1;
    for (unsigned i = 0; i < old->emoji_count; ++i) {
        size_t have = strlen(scan);
        int drop = 0;
        for (uint32_t k = 0; k < emoticons->u.vec.count && !drop; ++k) {
            const exteria_tl_value *item = emoticons->u.vec.items[k];
            drop = item && item->kind == EXTERIA_TL_V_BYTES && item->u.bytes.len == have && !memcmp(item->u.bytes.data, scan, have);
        }
        if (!drop) {
            memcpy(run + kept_len, scan, have + 1);
            kept_len += have + 1;
            ++kept;
        }
        scan += have + 1;
    }
    if (kept == 0) {
        free(old);
        memmove(index->blocks + at, index->blocks + at + 1, (index->count - at - 1) * sizeof(*index->blocks));
        --index->count;
        free(run);
        return EXTERIA_OK;
    }
    keyword_block *block = block_make(old->data, old->keyword_len, run, kept_len, kept);
    free(run);
    if (!block) return EXTERIA_E_NOMEM;
    free(old);
    index->blocks[at] = block;
    return EXTERIA_OK;
}

static int lang_valid(const char *lang) {
    size_t length = lang ? strlen(lang) : 0;
    if (length == 0 || length > LANG_MAX) return 0;
    for (size_t i = 0; i < length; ++i) {
        char c = lang[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_')) return 0;
    }
    return 1;
}

exteria_status exteria_keywords_request(exteria_arena *arena, const char *lang, int32_t from_version, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !lang_valid(lang) || from_version < 0) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, from_version ? "messages.getEmojiKeywordsDifference" : "messages.getEmojiKeywords");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "lang_code", lang);
    if (status == EXTERIA_OK && from_version) status = exteria_tl_set_i32(arena, request, "from_version", from_version);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

/* the keywords of an answer are checked before any is taken in, so an answer that is refused changes nothing */
static exteria_status check_answer(const char *lang, const exteria_tl_value *answer, const exteria_tl_value **keywords, int32_t *from_version, int32_t *version) {
    const uint8_t *code;
    size_t code_len;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_emojiKeywordsDifference)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_bytes(answer, "lang_code", &code, &code_len) != EXTERIA_OK || code_len != strlen(lang) || memcmp(code, lang, code_len)) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_i32(answer, "from_version", from_version) != EXTERIA_OK || exteria_tl_get_i32(answer, "version", version) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (*from_version < 0 || *version < *from_version) return EXTERIA_E_MALFORMED;
    if (exteria_tl_get_vec(answer, "keywords", keywords) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if ((*keywords)->u.vec.count > EXTERIA_KEYWORDS_MAX) return EXTERIA_E_LIMIT;
    for (uint32_t i = 0; i < (*keywords)->u.vec.count; ++i) {
        const exteria_tl_value *item = (*keywords)->u.vec.items[i];
        const uint8_t *word;
        size_t word_len;
        const exteria_tl_value *emoticons;
        if (!item || (!exteria_tl_is(item, EXTERIA_TL_ID_emojiKeyword) && !exteria_tl_is(item, EXTERIA_TL_ID_emojiKeywordDeleted))) return EXTERIA_E_MALFORMED;
        if (exteria_tl_get_bytes(item, "keyword", &word, &word_len) != EXTERIA_OK || word_len == 0 || word_len > EXTERIA_KEYWORD_MAX || memchr(word, 0, word_len)) return EXTERIA_E_MALFORMED;
        if (exteria_tl_get_vec(item, "emoticons", &emoticons) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        if (emoticons->u.vec.count > EMOTICONS_PER_ANSWER_MAX) return EXTERIA_E_LIMIT;
    }
    return EXTERIA_OK;
}

exteria_status exteria_keywords_apply(exteria_keyword_index *index, const char *lang, const exteria_tl_value *answer) {
    const exteria_tl_value *keywords;
    int32_t from_version, version;
    exteria_keyword_index *work;
    exteria_status status;
    if (!index || !lang_valid(lang) || !answer) return EXTERIA_E_ARG;
    status = check_answer(lang, answer, &keywords, &from_version, &version);
    if (status != EXTERIA_OK) return status;
    if (from_version != 0 && from_version != index->version) return EXTERIA_E_STATE;
    /* the changes go to a copy of the blocks, which replaces the index when all of them are in */
    work = exteria_keyword_index_new();
    if (!work) return EXTERIA_E_NOMEM;
    if (from_version != 0) {
        work->blocks = malloc((index->count ? index->count : 1) * sizeof(*work->blocks));
        if (!work->blocks) { exteria_keyword_index_free(work); return EXTERIA_E_NOMEM; }
        work->capacity = index->count ? index->count : 1;
        for (size_t i = 0; i < index->count; ++i) {
            size_t size = sizeof(keyword_block) + index->blocks[i]->data_len;
            work->blocks[i] = malloc(size);
            if (!work->blocks[i]) { exteria_keyword_index_free(work); return EXTERIA_E_NOMEM; }
            memcpy(work->blocks[i], index->blocks[i], size);
            ++work->count;
        }
    }
    for (uint32_t i = 0; i < keywords->u.vec.count && status == EXTERIA_OK; ++i) {
        const exteria_tl_value *item = keywords->u.vec.items[i];
        const uint8_t *word;
        size_t word_len;
        const exteria_tl_value *emoticons;
        char keyword[EXTERIA_KEYWORD_MAX];
        (void)exteria_tl_get_bytes(item, "keyword", &word, &word_len);
        (void)exteria_tl_get_vec(item, "emoticons", &emoticons);
        memcpy(keyword, word, word_len);
        status = exteria_tl_is(item, EXTERIA_TL_ID_emojiKeyword) ? add_emoji(work, keyword, word_len, emoticons) : remove_emoji(work, keyword, word_len, emoticons);
    }
    if (status != EXTERIA_OK) {
        exteria_keyword_index_free(work);
        return status;
    }
    work->version = version;
    {
        exteria_keyword_index swap = *index;
        *index = *work;
        *work = swap;
    }
    exteria_keyword_index_free(work);
    return EXTERIA_OK;
}

/* the letter folded to lower case for the alphabets the server keeps keywords in that have two cases here: ASCII, Latin-1 and Cyrillic. returns the bytes consumed */
static size_t fold_one(const unsigned char *in, size_t left, unsigned char *out, size_t *written) {
    if (in[0] < 0x80) {
        out[0] = (unsigned char)((in[0] >= 'A' && in[0] <= 'Z') ? in[0] + 32 : in[0]);
        *written = 1;
        return 1;
    }
    if (left >= 2 && (in[0] & 0xE0) == 0xC0) {
        uint32_t point = (uint32_t)((in[0] & 0x1F) << 6 | (in[1] & 0x3F));
        if ((point >= 0xC0 && point <= 0xDE && point != 0xD7) || (point >= 0x410 && point <= 0x42F)) point += 0x20;
        else if (point >= 0x400 && point <= 0x40F) point += 0x50;
        out[0] = (unsigned char)(0xC0 | (point >> 6));
        out[1] = (unsigned char)(0x80 | (point & 0x3F));
        *written = 2;
        return 2;
    }
    out[0] = in[0];
    *written = 1;
    return 1;
}

static size_t fold(const char *text, char *out, size_t cap) {
    size_t used = 0;
    const unsigned char *in = (const unsigned char *)text;
    size_t left = strlen(text);
    while (left > 0 && used + 2 < cap) {
        size_t written, consumed = fold_one(in, left, (unsigned char *)out + used, &written);
        used += written;
        in += consumed;
        left -= consumed;
    }
    out[used] = 0;
    return left == 0 ? used : 0;
}

static size_t add_result(char (*out)[EXTERIA_KEYWORD_EMOJI_MAX], size_t cap, size_t count, const keyword_block *block) {
    const char *at = block->data + block->keyword_len + 1;
    for (unsigned i = 0; i < block->emoji_count && count < cap; ++i) {
        size_t have = strlen(at);
        int present = 0;
        for (size_t k = 0; k < count && !present; ++k) present = strlen(out[k]) == have && !memcmp(out[k], at, have);
        if (!present) {
            memcpy(out[count], at, have + 1);
            ++count;
        }
        at += have + 1;
    }
    return count;
}

size_t exteria_keywords_search(const exteria_keyword_index *index, const char *query, char (*out)[EXTERIA_KEYWORD_EMOJI_MAX], size_t cap) {
    char needle[EXTERIA_KEYWORD_MAX * 2 + 1];
    size_t length, start = 0, count = 0;
    if (!index || !query || !out || cap == 0) return 0;
    if (cap > EXTERIA_KEYWORD_RESULTS_MAX) cap = EXTERIA_KEYWORD_RESULTS_MAX;
    while (query[start] == ' ') ++start;
    length = fold(query + start, needle, sizeof(needle));
    while (length > 0 && needle[length - 1] == ' ') needle[--length] = 0;
    if (length == 0 || length > EXTERIA_KEYWORD_MAX) return 0;
    /* three passes in order of how well the keyword fits: the same word, a word that begins with it, a later word of the keyword that begins with it */
    for (int pass = 0; pass < 3 && count < cap; ++pass) {
        for (size_t i = 0; i < index->count && count < cap; ++i) {
            const keyword_block *block = index->blocks[i];
            int match = 0;
            if (pass == 0) match = block->keyword_len == length && !memcmp(block->data, needle, length);
            else if (pass == 1) match = block->keyword_len > length && !memcmp(block->data, needle, length);
            else {
                for (size_t at = 1; at + length <= block->keyword_len && !match; ++at) {
                    match = block->data[at - 1] == ' ' && !memcmp(block->data + at, needle, length);
                }
            }
            if (match) count = add_result(out, cap, count, block);
        }
    }
    return count;
}

static void put_u16(uint8_t *at, uint32_t value) { at[0] = (uint8_t)value; at[1] = (uint8_t)(value >> 8); }
static void put_u32(uint8_t *at, uint32_t value) { put_u16(at, value & 0xFFFFu); put_u16(at + 2, value >> 16); }
static uint32_t get_u16(const uint8_t *at) { return (uint32_t)at[0] | (uint32_t)at[1] << 8; }
static uint32_t get_u32(const uint8_t *at) { return get_u16(at) | get_u16(at + 2) << 16; }

#define FILE_HEADER 16u
#define BLOCK_HEADER 5u

exteria_status exteria_keyword_index_encode(const exteria_keyword_index *index, uint8_t **out, size_t *length) {
    size_t total = FILE_HEADER, used = FILE_HEADER;
    uint8_t *buffer;
    if (out) *out = NULL;
    if (length) *length = 0;
    if (!index || !out || !length) return EXTERIA_E_ARG;
    for (size_t i = 0; i < index->count; ++i) total += BLOCK_HEADER + index->blocks[i]->data_len;
    if (total > EXTERIA_KEYWORDS_FILE_MAX) return EXTERIA_E_LIMIT;
    buffer = malloc(total);
    if (!buffer) return EXTERIA_E_NOMEM;
    memcpy(buffer, FILE_MAGIC, 4);
    put_u32(buffer + 4, FILE_FORMAT);
    put_u32(buffer + 8, (uint32_t)index->version);
    put_u32(buffer + 12, (uint32_t)index->count);
    for (size_t i = 0; i < index->count; ++i) {
        const keyword_block *block = index->blocks[i];
        put_u16(buffer + used, block->keyword_len);
        buffer[used + 2] = block->emoji_count;
        put_u16(buffer + used + 3, block->data_len);
        memcpy(buffer + used + BLOCK_HEADER, block->data, block->data_len);
        used += BLOCK_HEADER + block->data_len;
    }
    *out = buffer;
    *length = used;
    return EXTERIA_OK;
}

exteria_status exteria_keyword_index_decode(const uint8_t *data, size_t length, exteria_keyword_index **out) {
    exteria_keyword_index *index;
    size_t used = FILE_HEADER;
    uint32_t count;
    if (out) *out = NULL;
    if (!data || !out) return EXTERIA_E_ARG;
    if (length > EXTERIA_KEYWORDS_FILE_MAX || length < FILE_HEADER || memcmp(data, FILE_MAGIC, 4) || get_u32(data + 4) != FILE_FORMAT) return EXTERIA_E_MALFORMED;
    count = get_u32(data + 12);
    if (count > EXTERIA_KEYWORDS_MAX || (int32_t)get_u32(data + 8) < 0) return EXTERIA_E_MALFORMED;
    index = exteria_keyword_index_new();
    if (!index) return EXTERIA_E_NOMEM;
    index->version = (int32_t)get_u32(data + 8);
    for (uint32_t i = 0; i < count; ++i) {
        uint32_t keyword_len, data_len, emoji_count;
        keyword_block *block;
        const uint8_t *body;
        const char *scan;
        if (length - used < BLOCK_HEADER) goto malformed;
        keyword_len = get_u16(data + used);
        emoji_count = data[used + 2];
        data_len = get_u16(data + used + 3);
        used += BLOCK_HEADER;
        if (keyword_len == 0 || keyword_len > EXTERIA_KEYWORD_MAX || emoji_count == 0 || emoji_count > EXTERIA_KEYWORD_EMOJI_PER) goto malformed;
        if (data_len <= keyword_len + 1u || length - used < data_len) goto malformed;
        body = data + used;
        used += data_len;
        if (body[keyword_len] != 0 || memchr(body, 0, keyword_len) || body[data_len - 1] != 0) goto malformed;
        scan = (const char *)body + keyword_len + 1;
        for (uint32_t e = 0; e < emoji_count; ++e) {
            const char *end = memchr(scan, 0, (size_t)((const char *)body + data_len - scan));
            if (!end || end == scan || (size_t)(end - scan) >= EXTERIA_KEYWORD_EMOJI_MAX) goto malformed;
            scan = end + 1;
        }
        if (scan != (const char *)body + data_len) goto malformed;
        /* the blocks must come in strictly rising order, or the binary search would miss them */
        if (index->count && block_compare(index->blocks[index->count - 1], (const char *)body, keyword_len) >= 0) goto malformed;
        block = malloc(sizeof(*block) + data_len);
        if (!block) { exteria_keyword_index_free(index); return EXTERIA_E_NOMEM; }
        block->keyword_len = (uint16_t)keyword_len;
        block->emoji_count = (uint8_t)emoji_count;
        block->data_len = (uint16_t)data_len;
        memcpy(block->data, body, data_len);
        if (index_insert(index, index->count, block) != EXTERIA_OK) { free(block); exteria_keyword_index_free(index); return EXTERIA_E_NOMEM; }
    }
    if (used != length) goto malformed;
    *out = index;
    return EXTERIA_OK;
malformed:
    exteria_keyword_index_free(index);
    return EXTERIA_E_MALFORMED;
}
