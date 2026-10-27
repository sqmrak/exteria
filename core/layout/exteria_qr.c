#include "exteria_qr.h"

#include <string.h>

typedef struct qr_block_info {
    uint8_t ecc;        /* error correction codewords of every block */
    uint8_t blocks1;    /* blocks of the shorter kind */
    uint8_t data1;      /* data codewords of each of them */
    uint8_t blocks2;    /* blocks with one data codeword more */
} qr_block_info;

/* level M, versions 1 to 10 */
static const qr_block_info qr_blocks[EXTERIA_QR_MAX_VERSION] = {
    {10, 1, 16, 0}, {16, 1, 28, 0}, {26, 1, 44, 0}, {18, 2, 32, 0}, {24, 2, 43, 0},
    {16, 4, 27, 0}, {18, 4, 31, 0}, {22, 2, 38, 2}, {22, 3, 36, 2}, {26, 4, 43, 1}
};

static const uint8_t qr_align[EXTERIA_QR_MAX_VERSION][3] = {
    {0, 0, 0}, {6, 18, 0}, {6, 22, 0}, {6, 26, 0}, {6, 30, 0}, {6, 34, 0}, {6, 22, 38}, {6, 24, 42}, {6, 26, 46}, {6, 28, 50}
};

static const uint32_t qr_version_bits[EXTERIA_QR_MAX_VERSION] = {0, 0, 0, 0, 0, 0, 0x07C94u, 0x085BCu, 0x09A99u, 0x0A4D3u};

static int data_codewords(int version) {
    const qr_block_info *b = &qr_blocks[version - 1];
    return b->blocks1 * b->data1 + b->blocks2 * (b->data1 + 1);
}

static int side_of(int version) {
    return 17 + 4 * version;
}

static uint8_t gf_mul(uint8_t a, uint8_t b) {
    unsigned r = 0, x = a, y = b;
    while (y) {
        if (y & 1u) r ^= x;
        x <<= 1;
        if (x & 0x100u) x ^= 0x11Du;
        y >>= 1;
    }
    return (uint8_t)r;
}

/* the remainder of data * x^n divided by the generator polynomial of degree n, n at most 30 */
static void rs_remainder(const uint8_t *data, int len, int n, uint8_t *out) {
    uint8_t gen[31];
    int i, j;
    memset(gen, 0, sizeof(gen));
    gen[n - 1] = 1;
    {
        uint8_t root = 1;
        for (i = 0; i < n; ++i) {
            for (j = 0; j < n; ++j) {
                gen[j] = gf_mul(gen[j], root);
                if (j + 1 < n) gen[j] ^= gen[j + 1];
            }
            root = gf_mul(root, 2);
        }
    }
    memset(out, 0, (size_t)n);
    for (i = 0; i < len; ++i) {
        uint8_t factor = (uint8_t)(data[i] ^ out[0]);
        memmove(out, out + 1, (size_t)n - 1);
        out[n - 1] = 0;
        for (j = 0; j < n; ++j) out[j] ^= gf_mul(gen[j], factor);
    }
}

typedef struct qr_matrix {
    int side;
    uint8_t dark[EXTERIA_QR_MAX_MODULES];
    uint8_t fixed[EXTERIA_QR_MAX_MODULES];   /* function patterns, which no data or mask touches */
} qr_matrix;

static void set_function(qr_matrix *m, int x, int y, int dark) {
    m->dark[y * m->side + x] = (uint8_t)dark;
    m->fixed[y * m->side + x] = 1;
}

static void draw_finder(qr_matrix *m, int cx, int cy) {
    int dx, dy;
    for (dy = -4; dy <= 4; ++dy) {
        for (dx = -4; dx <= 4; ++dx) {
            int x = cx + dx, y = cy + dy;
            int dist = (dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy) ? (dx < 0 ? -dx : dx) : (dy < 0 ? -dy : dy);
            if (x < 0 || y < 0 || x >= m->side || y >= m->side) continue;
            set_function(m, x, y, dist != 2 && dist != 4);
        }
    }
}

static void draw_alignment(qr_matrix *m, int cx, int cy) {
    int dx, dy;
    for (dy = -2; dy <= 2; ++dy) {
        for (dx = -2; dx <= 2; ++dx) {
            int adx = dx < 0 ? -dx : dx, ady = dy < 0 ? -dy : dy;
            int dist = adx > ady ? adx : ady;
            set_function(m, cx + dx, cy + dy, dist != 1);
        }
    }
}

static void draw_format(qr_matrix *m, int mask) {
    /* level M is 00 */
    uint32_t data = (uint32_t)mask, rem = data, bits;
    int i;
    for (i = 0; i < 10; ++i) rem = (rem << 1) ^ ((rem >> 9) * 0x537u);
    bits = ((data << 10) | rem) ^ 0x5412u;
    for (i = 0; i <= 5; ++i) set_function(m, 8, i, (bits >> i) & 1u);
    set_function(m, 8, 7, (bits >> 6) & 1u);
    set_function(m, 8, 8, (bits >> 7) & 1u);
    set_function(m, 7, 8, (bits >> 8) & 1u);
    for (i = 9; i < 15; ++i) set_function(m, 14 - i, 8, (bits >> i) & 1u);
    for (i = 0; i < 8; ++i) set_function(m, m->side - 1 - i, 8, (bits >> i) & 1u);
    for (i = 8; i < 15; ++i) set_function(m, 8, m->side - 15 + i, (bits >> i) & 1u);
    set_function(m, 8, m->side - 8, 1);
}

static void draw_function_patterns(qr_matrix *m, int version) {
    int i, j, side = m->side;
    for (i = 0; i < side; ++i) {
        set_function(m, 6, i, i % 2 == 0);
        set_function(m, i, 6, i % 2 == 0);
    }
    draw_finder(m, 3, 3);
    draw_finder(m, side - 4, 3);
    draw_finder(m, 3, side - 4);
    if (version >= 2) {
        int count = version >= 7 ? 3 : 2;
        for (i = 0; i < count; ++i) {
            for (j = 0; j < count; ++j) {
                /* the three corners that hold a finder pattern have no alignment pattern */
                if ((i == 0 && j == 0) || (i == 0 && j == count - 1) || (i == count - 1 && j == 0)) continue;
                draw_alignment(m, qr_align[version - 1][i], qr_align[version - 1][j]);
            }
        }
    }
    draw_format(m, 0);
    if (version >= 7) {
        uint32_t bits = qr_version_bits[version - 1];
        for (i = 0; i < 18; ++i) {
            int dark = (int)((bits >> i) & 1u);
            int a = side - 11 + i % 3, b = i / 3;
            set_function(m, a, b, dark);
            set_function(m, b, a, dark);
        }
    }
}

static void draw_codewords(qr_matrix *m, const uint8_t *codewords, int count) {
    int right, vert, j, bit = 0, total = count * 8;
    for (right = m->side - 1; right >= 1; right -= 2) {
        if (right == 6) right = 5;
        for (vert = 0; vert < m->side; ++vert) {
            for (j = 0; j < 2; ++j) {
                int x = right - j;
                int upward = ((right + 1) & 2) == 0;
                int y = upward ? m->side - 1 - vert : vert;
                if (m->fixed[y * m->side + x] || bit >= total) continue;
                m->dark[y * m->side + x] = (uint8_t)((codewords[bit >> 3] >> (7 - (bit & 7))) & 1u);
                ++bit;
            }
        }
    }
}

static int mask_hit(int mask, int x, int y) {
    switch (mask) {
    case 0: return (x + y) % 2 == 0;
    case 1: return y % 2 == 0;
    case 2: return x % 3 == 0;
    case 3: return (x + y) % 3 == 0;
    case 4: return (x / 3 + y / 2) % 2 == 0;
    case 5: return x * y % 2 + x * y % 3 == 0;
    case 6: return (x * y % 2 + x * y % 3) % 2 == 0;
    default: return ((x + y) % 2 + x * y % 3) % 2 == 0;
    }
}

static void apply_mask(qr_matrix *m, int mask) {
    int x, y;
    for (y = 0; y < m->side; ++y)
        for (x = 0; x < m->side; ++x)
            if (!m->fixed[y * m->side + x] && mask_hit(mask, x, y)) m->dark[y * m->side + x] ^= 1u;
}

/* the four penalty rules of the specification */
static int line_score(const uint8_t *line, int n) {
    static const uint8_t a[11] = {1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0};
    static const uint8_t b[11] = {0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1};
    int score = 0, run = 1, i, k;
    for (i = 1; i < n; ++i) {
        if (line[i] == line[i - 1]) {
            ++run;
        } else {
            if (run >= 5) score += 3 + (run - 5);
            run = 1;
        }
    }
    if (run >= 5) score += 3 + (run - 5);
    for (i = 0; i + 11 <= n; ++i) {
        int hit_a = 1, hit_b = 1;
        for (k = 0; k < 11 && (hit_a || hit_b); ++k) {
            if (line[i + k] != a[k]) hit_a = 0;
            if (line[i + k] != b[k]) hit_b = 0;
        }
        if (hit_a) score += 40;
        if (hit_b) score += 40;
    }
    return score;
}

static int penalty(const qr_matrix *m) {
    int side = m->side, score = 0, x, y, dark = 0, total = side * side, k;
    uint8_t line[EXTERIA_QR_MAX_SIDE];
    for (y = 0; y < side; ++y) score += line_score(&m->dark[y * side], side);
    for (x = 0; x < side; ++x) {
        for (y = 0; y < side; ++y) line[y] = m->dark[y * side + x];
        score += line_score(line, side);
    }
    for (y = 0; y + 1 < side; ++y) {
        for (x = 0; x + 1 < side; ++x) {
            uint8_t c = m->dark[y * side + x];
            if (c == m->dark[y * side + x + 1] && c == m->dark[(y + 1) * side + x] && c == m->dark[(y + 1) * side + x + 1]) score += 3;
        }
    }
    for (x = 0; x < total; ++x) dark += m->dark[x];
    k = (dark * 20 - total * 10) < 0 ? (total * 10 - dark * 20) : (dark * 20 - total * 10);
    k = (k + total - 1) / total - 1;
    if (k > 0) score += k * 10;
    return score;
}

exteria_status exteria_qr_encode(const uint8_t *data, size_t len, uint8_t *modules, size_t cap, int *side_out, int *mask_out) {
    static const int capacity_bits[2] = {8, 16};
    uint8_t codewords[400], interleaved[400];
    qr_matrix m;
    int version, dc, total, bitlen = 0, i, j, best_mask = 0, best_score = 0;
    const qr_block_info *info;
    int short_blocks, count_bits;
    if (side_out) *side_out = 0;
    if (mask_out) *mask_out = 0;
    if (!data || !len || !modules || !side_out || cap < (size_t)EXTERIA_QR_MAX_MODULES) return EXTERIA_E_ARG;
    for (version = 1; version <= EXTERIA_QR_MAX_VERSION; ++version) {
        count_bits = capacity_bits[version >= 10 ? 1 : 0];
        if (4 + count_bits + (int)len * 8 <= data_codewords(version) * 8) break;
    }
    if (version > EXTERIA_QR_MAX_VERSION) return EXTERIA_E_LIMIT;
    dc = data_codewords(version);
    count_bits = capacity_bits[version >= 10 ? 1 : 0];
    memset(codewords, 0, sizeof(codewords));
    /* the mode (byte, 0100), the count, the bytes, a terminator of up to four zeros, then the pad codewords */
#define PUT_BITS(value, n) do { \
        int bits_ = (n); \
        while (bits_-- > 0) { \
            if ((((value) >> bits_) & 1u)) codewords[bitlen >> 3] |= (uint8_t)(0x80u >> (bitlen & 7)); \
            ++bitlen; \
        } \
    } while (0)
    PUT_BITS(4u, 4);
    PUT_BITS((unsigned)len, count_bits);
    for (i = 0; i < (int)len; ++i) PUT_BITS((unsigned)data[i], 8);
    bitlen += dc * 8 - bitlen < 4 ? dc * 8 - bitlen : 4;
    bitlen = (bitlen + 7) / 8 * 8;
#undef PUT_BITS
    for (i = bitlen / 8, j = 0; i < dc; ++i, ++j) codewords[i] = (uint8_t)(j % 2 == 0 ? 0xEC : 0x11);

    info = &qr_blocks[version - 1];
    total = info->blocks1 + info->blocks2;
    short_blocks = info->blocks1;
    {
        /* split into blocks, add each block's error correction and interleave */
        int offset = 0, longest = info->data1 + (info->blocks2 ? 1 : 0), pos = 0, b;
        uint8_t ecc[30 * 10];
        int starts[10], lengths[10];
        for (b = 0; b < total; ++b) {
            lengths[b] = info->data1 + (b >= short_blocks ? 1 : 0);
            starts[b] = offset;
            rs_remainder(codewords + offset, lengths[b], info->ecc, ecc + b * 30);
            offset += lengths[b];
        }
        for (i = 0; i < longest; ++i)
            for (b = 0; b < total; ++b)
                if (i < lengths[b]) interleaved[pos++] = codewords[starts[b] + i];
        for (i = 0; i < info->ecc; ++i)
            for (b = 0; b < total; ++b) interleaved[pos++] = ecc[b * 30 + i];
        offset = pos;
        (void)offset;
    }
    memset(&m, 0, sizeof(m));
    m.side = side_of(version);
    draw_function_patterns(&m, version);
    draw_codewords(&m, interleaved, dc + info->ecc * total);
    {
        qr_matrix trial;
        int mask;
        for (mask = 0; mask < 8; ++mask) {
            int score;
            trial = m;
            apply_mask(&trial, mask);
            draw_format(&trial, mask);
            score = penalty(&trial);
            if (mask == 0 || score < best_score) {
                best_score = score;
                best_mask = mask;
            }
        }
    }
    apply_mask(&m, best_mask);
    draw_format(&m, best_mask);
    memcpy(modules, m.dark, (size_t)m.side * (size_t)m.side);
    *side_out = m.side;
    if (mask_out) *mask_out = best_mask;
    return EXTERIA_OK;
}
