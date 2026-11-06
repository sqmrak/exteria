#include "exteria_text_split.h"

#define SPLIT_LOOKBACK 300u

static int is_space(uint16_t unit) {
    return unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0x85 || unit == 0xA0 || unit == 0x1680 || (unit >= 0x2000 && unit <= 0x200A) ||
           unit == 0x2028 || unit == 0x2029 || unit == 0x202F || unit == 0x205F || unit == 0x3000;
}

static int is_high_surrogate(uint16_t unit) {
    return unit >= 0xD800 && unit <= 0xDBFF;
}

/* the index of the unit the piece ends at (exclusive) and the index the next one starts at */
static void find_cut(const uint16_t *units, size_t len, size_t start, size_t limit, size_t *end, size_t *next) {
    size_t blank = 0, line = 0, stop = 0, space = 0;
    int has_blank = 0, has_line = 0, has_stop = 0, has_space = 0;
    if (len - start <= limit) {
        *end = len;
        *next = len;
        return;
    }
    {
        size_t i = start + limit - 1;
        size_t steps = 0;
        while (i > start && steps < SPLIT_LOOKBACK) {
            uint16_t c = units[i];
            uint16_t before = units[i - 1];
            if (c == '\n' && before == '\n') {
                blank = i;
                has_blank = 1;
                break;
            }
            /* the nearest line break to the limit wins, so the piece stays as long as it can */
            if (c == '\n') {
                if (!has_line) {
                    line = i;
                    has_line = 1;
                }
            } else if (!has_stop && is_space(c) && before == '.') {
                stop = i;
                has_stop = 1;
            } else if (!has_space && is_space(c)) {
                space = i;
                has_space = 1;
            }
            --i;
            ++steps;
        }
    }
    if (has_blank) *end = blank;
    else if (has_line) *end = line;
    else if (has_stop) *end = stop;
    else if (has_space) *end = space;
    else {
        *end = start + limit;
        /* a pair cut in two is two broken characters */
        if (*end > start + 1 && is_high_surrogate(units[*end - 1])) --*end;
        *next = *end;
        return;
    }
    *next = *end + 1;
}

size_t exteria_text_split(const uint16_t *units, size_t len, size_t limit, exteria_text_part *parts, size_t capacity, size_t *count) {
    size_t start = 0, total = 0;
    if (count) *count = 0;
    if (!units || !len || limit < 2) return 0;
    while (start < len) {
        size_t end, next, begin, finish;
        find_cut(units, len, start, limit, &end, &next);
        begin = start;
        finish = end;
        while (begin < finish && is_space(units[begin])) ++begin;
        while (finish > begin && is_space(units[finish - 1])) --finish;
        if (finish > begin) {
            if (parts && total < capacity) {
                parts[total].begin = begin;
                parts[total].end = finish;
                if (count) *count = total + 1;
            }
            ++total;
        }
        start = next;
    }
    return total;
}
